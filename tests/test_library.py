import json
import os
import stat
import tempfile
import threading
import time
import unittest

from backend.library import Library, SecretLeak, SyncBusy
from backend.subsonic import SubsonicError

from .test_model import fixture_page
from backend import bandcamp as bc

DUMMY_T = "deadbeefdeadbeefdeadbeefdeadbeef"
DUMMY_S = "0123456789abcdef"


class FakeSub:
    def __init__(self, albums=None, songs=None, playlists=None, fail=()):
        self._albums = albums or []
        self._songs = songs or {}
        self._playlists = playlists or {}
        self.fail = set(fail)
        self.album_calls = []
        self.playlist_calls = []

    def secret_values(self):
        return [DUMMY_T, DUMMY_S]

    def redact(self, s):
        return str(s).replace(DUMMY_T, "<t>").replace(DUMMY_S, "<s>")

    def albums(self):
        return list(self._albums)

    def album(self, sid):
        self.album_calls.append(sid)
        if sid in self.fail:
            raise SubsonicError("getAlbum: boom", "getAlbum", code=0)
        name = next(a["name"] for a in self._albums if a["id"] == sid)
        return {"id": sid, "name": name, "song": self._songs.get(sid, [])}

    def playlists(self):
        return [{"id": k, "name": v["name"], "songCount": len(v["entry"]), "public": False, "changed": "x"}
                for k, v in self._playlists.items()]

    def playlist(self, pid):
        self.playlist_calls.append(pid)
        return self._playlists[pid]


class FakeWeb:
    pause = 0

    def __init__(self, feed, pages=None):
        self.feed, self.pages, self.page_calls = feed, pages or {}, []

    def collection_feed(self):
        return list(self.feed)

    def album_page(self, url):
        self.page_calls.append(url)
        return self.pages.get(url)


def song(i, title, aid):
    return {"id": f"t:{i}", "title": title, "track": i, "duration": 100, "albumId": aid, "artist": "A"}


def feed_item(i, title, artist, t="a", pre=False, url=None):
    return {"tralbum_type": t, "tralbum_id": i, "item_title": title, "band_name": artist, "is_preorder": pre,
            "item_url": url or f"https://x.bandcamp.com/album/{i}", "purchased": "01 Jan 2024 00:00:00 GMT",
            "featured_track": 5, "featured_track_title": "SHOULD NEVER APPEAR"}


def world():
    sub = FakeSub(
        albums=[{"id": "a:1", "name": "La Dee La La", "artist": "Shamek Farrah & Folks", "songCount": 4, "created": "01 Jan 2024 00:00:00 GMT"},
                {"id": "a:2", "name": "Big Comp", "artist": "Many", "songCount": 10, "created": "01 Jan 2024 00:00:00 GMT"},
                {"id": "a:3", "name": "Empty", "artist": "Nobody", "songCount": 0, "created": "01 Jan 2024 00:00:00 GMT"}],
        songs={"a:1": [song(i, f"s{i}", "a:1") for i in range(1, 5)], "a:2": [song(i, f"b{i}", "a:2") for i in range(1, 4)]},
        playlists={"pl:1": {"id": "pl:1", "name": "Postpunky?", "songCount": 2,
                            "entry": [song(1, "x &amp; y", "a:1"), song(2, "z", "a:2")]}})
    pre_url = "https://shamekfarrah.bandcamp.com/album/first-impressions-deluxe-edition"
    web = FakeWeb(
        [feed_item(1, "La Dee La La", "Shamek Farrah &amp; Folks"), feed_item(2, "Big Comp", "Many"), feed_item(3, "Empty", "Nobody"),
         feed_item(9, "First Impressions (Deluxe Edition)", "Shamek Farrah", pre=True, url=pre_url)],
        pages={pre_url: bc.tralbum_summary(bc.parse_tralbum(fixture_page()))})
    return sub, web


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "library")

    def tearDown(self):
        self.tmp.cleanup()

    def lib(self, sub, web):
        return Library(cache_dir=self.dir, subsonic=sub, bandcamp=web)

    def test_full_sync_builds_honest_library(self):
        sub, web = world()
        lib = self.lib(sub, web)
        lib.sync(workers=2)
        la = lib.find("Shamek Farrah & Folks", "La Dee La La")[0]
        self.assertEqual((la.returned_track_count, la.streamable_track_count, la.completeness), (4, 4, "complete"))
        big = lib.find("Many", "Big Comp")[0]
        self.assertEqual((big.declared_track_count, big.returned_track_count, big.missing_track_count, big.completeness), (10, 3, 7, "partial"))
        self.assertEqual(lib.find("Nobody", "Empty")[0].completeness, "empty")
        fi = lib.find("Shamek Farrah", "First Impressions (Deluxe Edition)")[0]
        self.assertTrue(fi.is_preorder and fi.album_is_preorder)
        self.assertEqual(fi.release_date, "27 Nov 2026 00:00:00 GMT")
        self.assertEqual((fi.returned_track_count, fi.streamable_track_count), (7, 0))
        self.assertEqual(lib.playlist("Postpunky?").tracks[0].title, "x & y")
        self.assertIn("3/4", lib.report["summary"])  # the pre-order has no Subsonic counterpart
        self.assertEqual(lib.status()["state"], "done")

    def test_cache_is_private_and_free_of_secrets_entities_and_featured_tracks(self):
        sub, web = world()
        lib = self.lib(sub, web)
        lib.sync()
        self.assertEqual(stat.S_IMODE(os.stat(self.dir).st_mode), 0o700)
        for name in ("library.json", "status.json"):
            self.assertEqual(stat.S_IMODE(os.stat(os.path.join(self.dir, name)).st_mode), 0o600)
        with open(os.path.join(self.dir, "library.json"), encoding="utf-8") as f:
            raw = f.read()
        self.assertNotIn(DUMMY_T, raw)
        self.assertNotIn(DUMMY_S, raw)
        self.assertNotIn("&amp;", raw)
        self.assertNotIn("SHOULD NEVER APPEAR", raw)

    def test_write_guard_refuses_credentials(self):
        lib = Library(cache_dir=self.dir)
        lib._secrets = [DUMMY_T]
        with self.assertRaises(SecretLeak):
            lib._write_json("x.json", {"leak": f"https://x?t={DUMMY_T}"})
        self.assertFalse(os.path.exists(os.path.join(self.dir, "x.json")))

    def test_load_reads_cache_only_and_roundtrips(self):
        sub, web = world()
        a = self.lib(sub, web)
        a.sync()
        b = Library(cache_dir=self.dir)  # no clients at all: load() must not need the network
        self.assertTrue(b.load())
        self.assertEqual([x.to_dict() for x in b.albums], [x.to_dict() for x in a.albums])
        self.assertEqual(len(b.playlists), 1)
        self.assertFalse(Library(cache_dir=os.path.join(self.tmp.name, "nope")).load())

    def test_second_sync_is_incremental(self):
        sub, web = world()
        lib = self.lib(sub, web)
        lib.sync()
        first = len(sub.album_calls)
        sub.album_calls.clear()
        sub.playlist_calls.clear()
        lib2 = self.lib(sub, web)
        lib2.load()
        lib2.sync()
        self.assertEqual(sub.album_calls, [])
        self.assertEqual(sub.playlist_calls, [])
        self.assertGreater(first, 0)
        self.assertEqual(lib2.find("Shamek Farrah & Folks", "La Dee La La")[0].returned_track_count, 4)

    def test_changed_album_is_refetched(self):
        sub, web = world()
        self.lib(sub, web).sync()
        sub._albums[0]["songCount"] = 5
        sub._songs["a:1"].append(song(5, "s5", "a:1"))
        sub.album_calls.clear()
        lib = self.lib(sub, web)
        lib.load()
        lib.sync()
        self.assertEqual(sub.album_calls, ["a:1"])
        self.assertEqual(lib.find("Shamek Farrah & Folks", "La Dee La La")[0].returned_track_count, 5)

    def test_failed_album_stays_unloaded_not_faked(self):
        sub, web = world()
        sub.fail = {"a:2"}
        lib = self.lib(sub, web)
        lib.sync()
        big = lib.find("Many", "Big Comp")[0]
        self.assertEqual((big.completeness, big.tracks), ("unloaded", []))
        self.assertEqual(lib.meta["timings"]["tracklist_failures"][0]["subsonic_id"], "a:2")

    def test_missing_page_leaves_preorder_tracks_unloaded(self):
        sub, web = world()
        web.pages = {}
        lib = self.lib(sub, web)
        lib.sync()
        fi = lib.find("Shamek Farrah", "First Impressions (Deluxe Edition)")[0]
        self.assertEqual((fi.completeness, fi.tracks), ("unloaded", []))
        self.assertTrue(fi.is_preorder)  # from the feed

    def test_sync_does_not_block_the_caller_and_lock_prevents_overlap(self):
        sub, web = world()
        gate = threading.Event()
        orig = sub.albums

        def slow():
            gate.wait(5)
            return orig()

        sub.albums = slow
        lib = self.lib(sub, web)
        t0 = time.perf_counter()
        th = lib.start_sync()
        self.assertLess(time.perf_counter() - t0, 0.5)
        time.sleep(0.2)
        self.assertEqual(lib.status()["state"], "running")
        other = Library(cache_dir=self.dir, subsonic=sub, bandcamp=web)
        with self.assertRaises(SyncBusy):
            other.sync()
        gate.set()
        th.join(10)
        self.assertEqual(lib.status()["state"], "done")

    def test_cancel_stops_sync_and_reports_error_status(self):
        sub, web = world()
        lib = self.lib(sub, web)
        lib._cancel.set()
        lib._cancel.clear = lambda: None  # keep the pre-set cancel for this test
        with self.assertRaises(InterruptedError):
            lib.sync()
        self.assertEqual(lib.status()["state"], "error")


if __name__ == "__main__":
    unittest.main()
