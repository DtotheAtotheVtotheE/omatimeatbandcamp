"""CLI:  python3 <plugin>/backend <command>

    sync [--workers N] [--no-tracks] [--cookies FILE] [--user-url URL] [--no-playlists]
                                        run a sync in this process (blocking); progress as JSON lines on stdout
    play <subsonic-track-id> [--title T]
                                        load that track into the mpv player (the stream URL, which embeds
                                        credentials, never leaves this process: not printed, not in argv,
                                        not in mpv's media-title)
    status                              print status.json (idle|running|done|error)
    summary                             print counts from the cached library (no network)
    art [cover-id] [--out FILE] [--placeholder] [--from-file IMAGE]
                                        write the bar's current-art.jpg: fetch a Subsonic cover
                                        and downscale it to <=128 px, copy the bundled
                                        placeholder, or import a local image (harness/offline).
                                        Prints only {ok, path, placeholder}; never a URL.
"""
import argparse
import json
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.library import CACHE_DIR, Library, SyncBusy, _secure_dir  # noqa: E402


class _Redact(logging.Filter):
    def __init__(self, lib):
        super().__init__()
        self.lib = lib

    def filter(self, record):
        record.msg = self.lib._redact(record.getMessage())
        record.args = ()
        if record.exc_info and not record.exc_text:
            record.exc_text = logging.Formatter().formatException(record.exc_info)
        if record.exc_text:
            record.exc_text = self.lib._redact(record.exc_text)
        if record.stack_info:
            record.stack_info = self.lib._redact(record.stack_info)
        return True


def play(track_id, title=""):
    """Resolve a Subsonic track to its stream URL and hand it to mpv (mpvctl.do_load).
    Prints one JSON object {ok, error?}. The URL embeds credentials, so it is never output;
    only `ok` and a redacted `error` are ever printed, whatever mpvctl returns."""
    from backend.subsonic import Client, SubsonicError
    try:
        client = Client()
        url = client.stream_url(track_id)
    except SubsonicError as e:
        # Not a stream failure: credentials/server are missing or wrong, so moving on
        # to the next track would fail the same way. The UI shows this without skipping.
        print(json.dumps({"ok": False, "error": str(e), "fatal": True}))
        return 1
    import mpvctl
    try:
        result = json.loads(mpvctl.do_load(url, None, title or "Bandcamp track"))
    except Exception as e:  # noqa: BLE001
        result = {"ok": False, "error": str(e), "kind": "environment"}
    out = {"ok": result.get("ok") is True}
    if not out["ok"]:
        out["error"] = client.redact(str(result.get("error") or "playback failed"))
        # kind=stream means mpv refused/failed the stream: the queue should skip it.
        # environment means mpv or the player setup failed: skipping would only repeat it.
        out["fatal"] = result.get("kind") != "stream"
    print(json.dumps(out))
    return 0 if out["ok"] else 1


def art(cover_id="", out="", placeholder=False, from_file=""):
    """Write the bar art file. The file is always valid: on any fetch/scale
    failure it falls back to the bundled placeholder. Output never contains a
    cover-art URL, token or credential."""
    from backend import art as artmod
    dest = os.path.expanduser(out) if out else artmod.art_path()
    used_placeholder = False
    ok = True
    error = ""
    try:
        if placeholder or (not cover_id and not from_file):
            artmod.write_placeholder(dest)
            used_placeholder = True
        elif from_file:
            artmod.write_from_file(os.path.expanduser(from_file), dest)
        else:
            artmod.write_cover(cover_id, dest)
    except Exception as e:  # noqa: BLE001 - the bar must still have a valid image
        ok = False
        error = "cover art unavailable"
        try:
            artmod.write_placeholder(dest)
            used_placeholder = True
        except Exception:
            pass
        # Keep the reason local: never echo a URL or the raw urllib error.
        if isinstance(e, RuntimeError):
            error = str(e)
    print(json.dumps({"ok": ok, "path": dest, "placeholder": used_placeholder, "error": error}))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="backend")
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("sync")
    s.add_argument("--workers", type=int, default=4)
    s.add_argument("--no-tracks", action="store_true")
    s.add_argument("--cookies", default="")
    s.add_argument("--user-url", default="")
    s.add_argument("--no-playlists", action="store_true")
    pl = sp.add_parser("play")
    pl.add_argument("track_id")
    pl.add_argument("--title", default="")
    sp.add_parser("status")
    sp.add_parser("summary")
    ar = sp.add_parser("art")
    ar.add_argument("cover_id", nargs="?", default="")
    ar.add_argument("--out", default="")
    ar.add_argument("--placeholder", action="store_true")
    ar.add_argument("--from-file", default="")
    args = ap.parse_args(argv)
    if args.cmd == "play":
        return play(args.track_id, args.title)
    if args.cmd == "art":
        return art(args.cover_id, args.out, args.placeholder, args.from_file)
    lib = Library()
    if args.cmd == "status":
        print(json.dumps(lib.status()))
        return 0
    if args.cmd == "summary":
        if not lib.load():
            print(json.dumps({"cache": False}))
            return 1
        print(json.dumps({"cache": True, "albums": len(lib.albums), "playlists": len(lib.playlists),
                          "match": lib.report.get("summary"), "meta": lib.meta}))
        return 0
    _secure_dir(CACHE_DIR)
    handler = logging.FileHandler(os.path.join(CACHE_DIR, "sync.log"))
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
    handler.addFilter(_Redact(lib))
    logging.getLogger("omatime").addHandler(handler)
    logging.getLogger("omatime").setLevel(logging.INFO)
    lib.load()  # previous cache makes the sync incremental

    def progress(stage, done, total):
        print(json.dumps({"stage": stage, "done": done, "total": total}), flush=True)

    if args.cookies:
        from backend import bandcamp as bc
        lib.bandcamp = bc.Bandcamp(bc.load_cookie(os.path.expanduser(args.cookies)))
    try:
        lib.sync(workers=args.workers, deep=not args.no_tracks, progress=progress,
                 user_url=args.user_url or None, playlists=not args.no_playlists)
    except SyncBusy:
        print(json.dumps({"error": "another sync is running"}))
        return 2
    except Exception as e:  # noqa: BLE001
        print(json.dumps({"error": lib._redact(str(e))}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
