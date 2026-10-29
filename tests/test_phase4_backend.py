import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

from backend.library import Library
from backend.match import match_albums
from backend.model import (DETAIL_VERSION, Album, Track, parse_bc_date, track_from_subsonic)

from .test_library import FakeSub, FakeWeb, feed_item, song, world

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Timestamps(unittest.TestCase):
    def test_parse_bc_date(self):
        self.assertEqual(parse_bc_date("27 Nov 2026 00:00:00 GMT"), 1795737600)
        self.assertIsNone(parse_bc_date(None))
        self.assertIsNone(parse_bc_date("garbage"))

    def test_album_exposes_epoch_seconds_in_dict(self):
        a = Album(title="x", artist="y", purchased="20 Oct 2026 21:36:25 GMT", release_date="27 Nov 2026 00:00:00 GMT")
        d = a.to_dict()
        self.assertEqual((d["purchased_ts"], d["release_ts"]), (parse_bc_date(a.purchased), 1795737600))
        self.assertIsNone(Album(title="x", artist="y").to_dict()["purchased_ts"])

    def test_year_is_earliest_plausible_track_year(self):
        a = Album(title="x", artist="y")
        ts = [track_from_subsonic({"id": f"t:{i}", "title": str(i), "track": i, "year": y}) for i, y in enumerate([2021, 2019, 0, None], 1)]
        a.set_tracks(ts, "subsonic")
        self.assertEqual((a.year, a.detail_version), (2019, DETAIL_VERSION))
        b = Album(title="x", artist="y")
        b.set_tracks([Track(title="t")], "subsonic")
        self.assertIsNone(b.year)


class Matching(unittest.TestCase):
    def test_single_parent_album_inherits_the_web_purchase_date(self):
        web = Album(title="Red Sound", artist="Y", kind="single", bandcamp_id="t1", purchased="01 Jan 2024 00:00:00 GMT", sources=["bandcamp"])
        sub = Album(title="Parent", artist="Z", subsonic_id="a:1", declared_track_count=1, purchased=None, sources=["subsonic"])
        merged, _ = match_albums([web], [sub], lambda sid: [Track(title="Red Sound")])
        self.assertEqual(merged[0].purchased, "01 Jan 2024 00:00:00 GMT")


class SyncOptions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "library")

    def tearDown(self):
        self.tmp.cleanup()

    def test_old_cache_without_detail_is_refetched_once_then_reused(self):
        sub, web = world()
        Library(cache_dir=self.dir, subsonic=sub, bandcamp=web).sync()
        path = os.path.join(self.dir, "library.json")
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for a in data["albums"]:
            a["detail_version"] = 0           # what a pre-Phase-4 cache looks like
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        sub.album_calls.clear()
        lib = Library(cache_dir=self.dir, subsonic=sub, bandcamp=web)
        lib.load()
        lib.sync()
        self.assertEqual(sorted(sub.album_calls), ["a:1", "a:2", "a:3"])
        sub.album_calls.clear()
        lib2 = Library(cache_dir=self.dir, subsonic=sub, bandcamp=web)
        lib2.load()
        lib2.sync()
        self.assertEqual(sub.album_calls, [])

    def test_playlists_can_be_skipped(self):
        sub, web = world()
        lib = Library(cache_dir=self.dir, subsonic=sub, bandcamp=web)
        lib.sync(playlists=False)
        self.assertEqual((lib.playlists, sub.playlist_calls), ([], []))

    def test_user_url_is_passed_to_the_feed(self):
        sub, web = world()
        seen = []
        web.collection_feed = lambda user_url=None: seen.append(user_url) or [feed_item(1, "La Dee La La", "A")]
        Library(cache_dir=self.dir, subsonic=sub, bandcamp=web).sync(user_url="https://bandcamp.com/someone")
        self.assertEqual(seen, ["https://bandcamp.com/someone"])


class PlayCommand(unittest.TestCase):
    def test_play_without_credentials_is_a_clean_json_error_that_leaks_nothing(self):
        with tempfile.TemporaryDirectory() as home:
            r = subprocess.run([sys.executable, os.path.join(ROOT, "backend"), "play", "t:1"], capture_output=True, text=True,
                               env={**os.environ, "HOME": home})
        self.assertEqual(r.returncode, 1)
        out = json.loads(r.stdout)
        self.assertFalse(out["ok"])
        self.assertIn("credentials", out["error"])
        self.assertNotIn("stream.view", r.stdout + r.stderr)


class PlayNeverLeaksTheUrl(unittest.TestCase):
    LEAKY = "stream.view?u=SECRET-USER&t=SECRETTOKEN&s=SECRETSALT&id=t:1"

    def run_play(self, mpv_result, title=""):
        from backend.__main__ import play
        import mpvctl
        out = io.StringIO()
        with mock.patch("backend.subsonic.load_credentials", return_value=("acct-user-123456", "pw")), \
                mock.patch.object(mpvctl, "do_load", return_value=json.dumps(mpv_result)) as dl, redirect_stdout(out):
            code = play("t:1", title)
        return code, out.getvalue(), dl

    def test_url_in_mpv_result_title_is_never_printed(self):
        code, text, dl = self.run_play({"ok": True, "title": self.LEAKY})
        self.assertEqual((code, json.loads(text)), (0, {"ok": True}))
        for needle in ("stream.view", "SECRET", "u=", "t="):
            self.assertNotIn(needle, text)

    def test_url_in_an_error_is_redacted(self):
        import backend.subsonic as sub
        c = sub.Client("acct-user-123456", "pw")
        err = f"bad thing at {c.stream_url('t:9')}"
        with mock.patch("backend.subsonic.Client", return_value=c):
            from backend.__main__ import play
            import mpvctl
            out = io.StringIO()
            with mock.patch.object(mpvctl, "do_load", return_value=json.dumps({"ok": False, "error": err})), redirect_stdout(out):
                code = play("t:9")
        self.assertEqual(code, 1)
        for secret in c.secret_values():
            self.assertNotIn(secret, out.getvalue())

    def test_the_title_is_passed_to_the_player_with_a_default(self):
        _, _, dl = self.run_play({"ok": True}, "La Dee La La Song")
        self.assertEqual(dl.call_args[0][2], "La Dee La La Song")
        _, _, dl = self.run_play({"ok": True}, "")
        self.assertEqual(dl.call_args[0][2], "Bandcamp track")

    def test_do_load_forces_the_media_title_and_never_reads_it_back(self):
        import mpvctl
        calls = []

        def fake(cmd):
            calls.append(cmd)
            return {"error": "success", "data": self.LEAKY}

        with mock.patch.object(mpvctl, "ensure", return_value=True), mock.patch.object(mpvctl, "send_json", fake):
            out = json.loads(mpvctl.do_load("https://x/" + self.LEAKY, None, "My Song"))
            json.loads(mpvctl.do_load("https://x/other", None, None))
        self.assertIn(["set_property", "force-media-title", "My Song"], calls)
        self.assertIn(["set_property", "force-media-title", ""], calls)       # a stale title is cleared
        self.assertNotIn(["get_property", "media-title"], calls)
        self.assertEqual(out, {"ok": True, "title": "My Song"})


if __name__ == "__main__":
    unittest.main()
