"""Library: merged web+Subsonic collection, persisted locally, synced in the background.

Why it is shaped this way: pulling every album's tracks takes ~95 s sequentially
(687 getAlbum calls), so nothing the UI needs may wait on a sync.

* `Library.load()` reads the on-disk cache only (a few MB of JSON) and is what the
  UI should call at start-up. It never touches the network.
* `Library.sync()` does the network work in stages and *publishes after each stage*:
    1. album lists (web feed + Subsonic)                  ~2 s
    2. matching, incl. single-track parent albums          ~10 s -> library usable, published
       and saved here (tracklists of most albums still "unloaded")
    3. playlists                                           ~10 s
    4. pre-order / web-only album pages
    5. per-album tracklists (the slow part), incremental: albums whose cached
       entry still matches (same Subsonic id and declared count) are not re-fetched.
  Progress is written to status.json; the cache is rewritten atomically after every
  stage and every `SAVE_EVERY` albums, so killing a sync loses at most a few seconds.
* `Library.start_sync()` runs sync() on a daemon thread; the CLI (`python3 backend sync`)
  runs it as a separate process the QML service can spawn and poll.
* One sync at a time, enforced with an flock on sync.lock.

Cache files live in ~/.cache/omatimeatbandcamp/library/ (dir 0700, files 0600) and are
written through a guard that refuses to persist Subsonic credentials/tokens.
"""
import fcntl
import json
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from . import bandcamp as bc
from .match import match_albums
from .model import (DETAIL_VERSION, Album, Playlist, album_from_feed_item, album_from_subsonic_list_entry,
                    track_from_subsonic, track_from_tralbum, tracks_from_subsonic_album)
from .subsonic import Client, SubsonicError

log = logging.getLogger("omatime.library")

CACHE_DIR = os.path.expanduser("~/.cache/omatimeatbandcamp/library")
COOKIES = os.path.expanduser("~/.cache/omatimeatbandcamp/cookies.txt")
SCHEMA = 1
SAVE_EVERY = 100


class SyncBusy(Exception):
    pass


class SecretLeak(Exception):
    pass


def _secure_dir(p):
    os.makedirs(p, mode=0o700, exist_ok=True)
    try:
        os.chmod(p, 0o700)
    except OSError:
        pass


class Library:
    def __init__(self, cache_dir=CACHE_DIR, subsonic=None, bandcamp=None):
        self.cache_dir = cache_dir
        self.subsonic = subsonic
        self.bandcamp = bandcamp
        self.albums = []
        self.playlists = []
        self.report = {}
        self.meta = {}
        self._cancel = threading.Event()
        self._thread = None
        self._secrets = []

    # -- paths -----------------------------------------------------------------------------
    def _p(self, name):
        return os.path.join(self.cache_dir, name)

    # -- persistence -------------------------------------------------------------------------
    def _write_json(self, name, obj):
        text = json.dumps(obj, ensure_ascii=False)
        for s in self._secrets:
            if s and s in text:
                raise SecretLeak(f"refusing to write {name}: contains a Subsonic credential value")
        _secure_dir(self.cache_dir)
        tmp = self._p(name + ".tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, self._p(name))

    def save(self):
        self._write_json("library.json", {
            "schema": SCHEMA,
            "meta": self.meta,
            "match_report": self.report,
            "albums": [a.to_dict() for a in self.albums],
            "playlists": [p.to_dict() for p in self.playlists],
        })

    def load(self):
        """Read the cache. No network. Returns True if a usable cache existed."""
        try:
            with open(self._p("library.json"), encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, ValueError):
            return False
        if d.get("schema") != SCHEMA:
            return False
        self.meta = d.get("meta") or {}
        self.report = d.get("match_report") or {}
        self.albums = [Album.from_dict(a) for a in d.get("albums") or []]
        self.playlists = [Playlist.from_dict(p) for p in d.get("playlists") or []]
        return True

    # -- status ---------------------------------------------------------------------------------
    def _status(self, state, stage="", done=0, total=0, error=None):
        now = time.time()
        self.meta.setdefault("started", now)
        st = {"state": state, "stage": stage, "done": done, "total": total, "error": error,
              "started": self.meta.get("started"), "updated": now}
        self._write_json("status.json", st)
        return st

    def status(self):
        try:
            with open(self._p("status.json"), encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return {"state": "idle"}

    # -- lookups -----------------------------------------------------------------------------------
    def find(self, artist, title):
        from .textnorm import album_key
        k = album_key(artist, title)
        return [a for a in self.albums if a.key == k]

    def playlist(self, name):
        return next((p for p in self.playlists if p.name == name), None)

    # -- sync ----------------------------------------------------------------------------------------
    def cancel(self):
        self._cancel.set()

    def start_sync(self, **kw):
        if self._thread and self._thread.is_alive():
            return self._thread
        self._thread = threading.Thread(target=self._sync_thread, kwargs=kw, daemon=True, name="library-sync")
        self._thread.start()
        return self._thread

    def _sync_thread(self, **kw):
        try:
            self.sync(**kw)
        except SyncBusy:
            pass
        except Exception:  # noqa: BLE001 - recorded in status.json for the UI
            log.exception("sync failed")

    def sync(self, workers=4, deep=True, progress=None, user_url=None, playlists=True):
        _secure_dir(self.cache_dir)
        lockf = open(self._p("sync.lock"), "w")
        try:
            fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            lockf.close()
            raise SyncBusy("another sync is running") from None
        try:
            self._cancel.clear()
            self.meta = {"started": time.time()}
            self._run(workers, deep, progress or (lambda *a: None), user_url, playlists)
        except Exception as e:
            self._status("error", error=self._redact(str(e)))
            raise
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
            lockf.close()

    def _redact(self, s):
        return self.subsonic.redact(s) if self.subsonic else s

    def _checkpoint(self, stage, done=0, total=0, progress=None):
        self._status("running", stage, done, total)
        if progress:
            progress(stage, done, total)
        if self._cancel.is_set():
            raise InterruptedError("sync cancelled")

    def _run(self, workers, deep, progress, user_url=None, playlists=True):
        t_start = time.perf_counter()
        sub = self.subsonic or Client()
        self.subsonic = sub
        self._secrets = sub.secret_values()
        web = self.bandcamp or bc.Bandcamp(bc.load_cookie(COOKIES))
        self.bandcamp = web
        cached = {a.subsonic_id: a for a in self.albums if a.subsonic_id}
        cached_playlists = {p.id: p for p in self.playlists}
        timings = {}

        # 1. album lists
        self._checkpoint("album lists", progress=progress)
        t = time.perf_counter()
        feed = web.collection_feed(user_url) if user_url else web.collection_feed()
        sub_entries = sub.albums()
        timings["album_lists_s"] = round(time.perf_counter() - t, 2)
        uurl = getattr(web, "user_url", None)
        if uurl:
            self.meta["user"] = uurl.rstrip("/").rsplit("/", 1)[-1]
        web_albums = [album_from_feed_item(v) for v in feed]
        sub_albums = [album_from_subsonic_list_entry(a) for a in sub_entries]
        self._checkpoint("album lists", len(feed) + len(sub_entries), len(feed) + len(sub_entries), progress)

        # 2. matching (stage 2 needs the tracks of still-unmatched Subsonic albums; only those are fetched)
        self._checkpoint("matching", progress=progress)
        t = time.perf_counter()
        fetched = {}

        def sub_tracks_for(sid):
            if sid not in fetched:
                c = cached.get(sid)
                if c and c.tracks_loaded and c.tracks_source == "subsonic" and c.detail_version >= DETAIL_VERSION:
                    fetched[sid] = (c.tracks, None)
                else:
                    payload = sub.album(sid)
                    fetched[sid] = (tracks_from_subsonic_album(payload), payload)
            return fetched[sid][0]

        merged, rep = match_albums(web_albums, sub_albums, sub_tracks_for)
        for a in merged:  # reuse what stage 2 already pulled
            if a.subsonic_id in fetched and not a.tracks_loaded:
                a.set_tracks(fetched[a.subsonic_id][0], "subsonic")
        timings["matching_s"] = round(time.perf_counter() - t, 2)
        self._reuse_cache(merged, cached)
        self.albums, self.report = merged, rep.to_dict()
        self._finish_meta(timings, t_start, "matched")
        self.save()
        log.info(rep.summary())

        # 3. playlists
        self._checkpoint("playlists", progress=progress)
        t = time.perf_counter()
        self.playlists = self._pull_playlists(sub, cached_playlists, progress) if playlists else []
        timings["playlists_s"] = round(time.perf_counter() - t, 2)

        self.save()

        # 4. pages for pre-orders and web-only albums
        targets = [a for a in merged if a.bandcamp_url and a.kind == "album" and
                   (a.is_preorder or "subsonic" not in a.sources)]
        for i, a in enumerate(targets):
            self._checkpoint("album pages", i, len(targets), progress)
            self._apply_page(a, web)
            time.sleep(web.pause)
        self.save()

        # 5. per-album tracklists, incremental
        if deep:
            todo = [a for a in merged if a.subsonic_id and not a.tracks_loaded]
            total = len(todo)
            t = time.perf_counter()
            done = 0
            failures = []
            if total:
                with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
                    futs = {ex.submit(self._fetch_album, sub, a): a for a in todo}
                    for fut in futs:
                        a = futs[fut]
                        try:
                            payload = fut.result()
                            a.set_tracks(tracks_from_subsonic_album(payload), "subsonic")
                            if a.declared_track_count is None:
                                a.declared_track_count = payload.get("songCount")
                        except SubsonicError as e:
                            failures.append({"subsonic_id": a.subsonic_id, "title": a.title, "error": self._redact(str(e))})
                        done += 1
                        if done % SAVE_EVERY == 0:
                            self._checkpoint("tracklists", done, total, progress)
                            self.save()
                        if self._cancel.is_set():
                            for f in futs:
                                f.cancel()
                            break
            timings["tracklists_s"] = round(time.perf_counter() - t, 2)
            timings["tracklists_fetched"] = done
            timings["tracklist_failures"] = failures
        self._finish_meta(timings, t_start, "complete" if deep else "no-tracklists")
        self.save()
        self._status("done", "done", len(self.albums), len(self.albums))
        progress("done", len(self.albums), len(self.albums))

    def _finish_meta(self, timings, t_start, phase):
        self.meta.update({"phase": phase, "finished": time.time(), "timings": timings,
                          "elapsed_s": round(time.perf_counter() - t_start, 2), "schema": SCHEMA})

    @staticmethod
    def _fetch_album(sub, a):
        return sub.album(a.subsonic_id)

    @staticmethod
    def _reuse_cache(merged, cached):
        """Carry tracklists over from the previous cache when the album is demonstrably unchanged."""
        for a in merged:
            c = cached.get(a.subsonic_id) if a.subsonic_id else None
            if (c and not a.tracks_loaded and c.tracks_loaded and c.tracks_source == "subsonic"
                    and c.detail_version >= DETAIL_VERSION
                    and c.declared_track_count == a.declared_track_count and c.purchased == a.purchased):
                a.set_tracks(c.tracks, "subsonic")

    def _apply_page(self, a, web):
        info = web.album_page(a.bandcamp_url)
        if info is None:
            log.warning("no data-tralbum for %s (page missing or unreadable); leaving tracks unloaded", a.bandcamp_url)
            return
        a.album_is_preorder = info["album_is_preorder"]
        a.is_preorder = bool(info["is_preorder"] or info["album_is_preorder"])
        a.release_date = info["album_release_date"]
        ti = info["trackinfo"]
        a.declared_track_count = len(ti)
        if "subsonic" not in a.sources:
            a.set_tracks([track_from_tralbum(t, a.title, a.artist, a.album_is_preorder) for t in ti], "bandcamp-page")

    def _pull_playlists(self, sub, cached, progress):
        out = []
        lst = sub.playlists()
        for i, p in enumerate(lst):
            self._checkpoint("playlists", i, len(lst), progress)
            c = cached.get(p["id"])
            if c and c.tracks_loaded and c.changed == p.get("changed") and c.declared_track_count == p.get("songCount"):
                out.append(c)
                continue
            pl = Playlist(id=p["id"], name=p.get("name") or "", declared_track_count=p.get("songCount"),
                          public=p.get("public"), changed=p.get("changed"))
            payload = sub.playlist(p["id"])
            pl.tracks = [track_from_subsonic(e) for e in payload.get("entry") or []]
            pl.tracks_loaded = True
            out.append(pl)
        return out
