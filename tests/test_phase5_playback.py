import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

import mpvctl

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = ["time-pos", "duration", "pause", "idle-active", "eof-reached", "seekable"]


class Status(unittest.TestCase):
    def test_status_asks_only_for_progress_properties(self):
        asked = []

        def fake_query(props, timeout=2.0):
            asked.append(list(props))
            return {"time-pos": 12.5, "duration": 200.0, "pause": False,
                    "idle-active": False, "eof-reached": False, "seekable": True}

        with mock.patch.object(mpvctl, "socket_alive", return_value=True), \
                mock.patch.object(mpvctl, "query", fake_query):
            d = mpvctl.do_status()
        self.assertEqual(asked, [PROPS])
        self.assertEqual(d, {"running": True, "position": 12.5, "duration": 200.0, "paused": False,
                             "idle": False, "eof": False, "seekable": True})
        # The stream URL embeds credentials; status must never expose it (or the title).
        text = json.dumps(d)
        for forbidden in ("media-title", "path", "stream.view", "url"):
            self.assertNotIn(forbidden, text)

    def test_status_when_mpv_is_not_running(self):
        with mock.patch.object(mpvctl, "socket_alive", return_value=False):
            self.assertEqual(mpvctl.do_status(), {"running": False})

    def test_query_maps_request_ids_and_tolerates_missing_values(self):
        replies = [
            {"request_id": 0, "error": "success", "data": 42.0},
            {"request_id": 1, "error": "property unavailable"},
            {"event": "something-else"},
        ]
        raw = "".join(json.dumps(r) + "\n" for r in replies).encode()

        class FakeSocket:
            def __enter__(self): return self
            def __exit__(self, *a): return False
            def sendall(self, data): pass
            def recv(self, n): return raw

        with mock.patch.object(mpvctl, "socket_alive", return_value=True), \
                mock.patch.object(mpvctl, "connect", lambda timeout=2.0: FakeSocket()):
            self.assertEqual(mpvctl.query(["a", "b"]), {"a": 42.0, "b": None})


class Seek(unittest.TestCase):
    def test_seek_is_absolute_exact_and_clamped(self):
        sent = []

        def fake_send(cmd):
            sent.append(cmd)
            return {"error": "success"}

        with mock.patch.object(mpvctl, "socket_alive", return_value=True), \
                mock.patch.object(mpvctl, "send_json", fake_send):
            self.assertEqual(mpvctl.do_seek("42.5"), {"ok": True, "position": 42.5})
            self.assertEqual(mpvctl.do_seek(-5), {"ok": True, "position": 0.0})
        self.assertEqual(sent, [["seek", 42.5, "absolute+exact"], ["seek", 0.0, "absolute+exact"]])

    def test_seek_errors(self):
        with mock.patch.object(mpvctl, "socket_alive", return_value=False):
            self.assertEqual(mpvctl.do_seek(10), {"ok": False, "error": "not running"})
        with mock.patch.object(mpvctl, "socket_alive", return_value=True), \
                mock.patch.object(mpvctl, "send_json", return_value={"error": "property unavailable"}):
            d = mpvctl.do_seek(10)
            self.assertFalse(d["ok"])
            self.assertIn("unavailable", d["error"])

    def test_a_bad_number_never_reaches_mpv(self):
        with mock.patch.object(mpvctl, "socket_alive", return_value=True), \
                mock.patch.object(mpvctl, "send_json") as send:
            self.assertEqual(mpvctl.do_seek("soon"), {"ok": False, "error": "bad position"})
            send.assert_not_called()


class LoadFailureKind(unittest.TestCase):
    """The UI skips a failed *stream* but must not burn through the queue on an
    environment failure (no mpv, missing credentials)."""

    def test_mpv_not_starting_is_an_environment_failure(self):
        with mock.patch.object(mpvctl, "ensure", return_value=False):
            d = json.loads(mpvctl.do_load("https://example.invalid/x"))
        self.assertFalse(d["ok"])
        self.assertEqual(d["kind"], "environment")

    def test_loadfile_rejection_is_a_stream_failure(self):
        replies = [{"error": "success"}, {"error": "success"}, {"error": "loading failed"}]
        with mock.patch.object(mpvctl, "ensure", return_value=True), \
                mock.patch.object(mpvctl, "send_json", side_effect=replies):
            d = json.loads(mpvctl.do_load("https://example.invalid/x", None, "T"))
        self.assertFalse(d["ok"])
        self.assertEqual(d["kind"], "stream")

    def test_a_successful_load_clears_an_inherited_pause(self):
        """mpv keeps `pause` across loadfile: a player left paused would load the
        first track of the next session paused while the service says it is
        playing. A load that is meant to play must clear it."""
        sent = []

        def fake_send(command):
            sent.append(command)
            return {"error": "success"}

        with mock.patch.object(mpvctl, "ensure", return_value=True), \
                mock.patch.object(mpvctl, "send_json", fake_send):
            d = json.loads(mpvctl.do_load("https://example.invalid/x", None, "T"))
        self.assertTrue(d["ok"])
        self.assertEqual(sent[2][0], "loadfile")
        self.assertEqual(sent[-1], ["set", "pause", "no"])

    def test_a_rejected_load_never_touches_pause(self):
        sent = []

        def fake_send(command):
            sent.append(command)
            return {"error": "success"} if command[0] != "loadfile" else {"error": "loading failed"}

        with mock.patch.object(mpvctl, "ensure", return_value=True), \
                mock.patch.object(mpvctl, "send_json", fake_send):
            d = json.loads(mpvctl.do_load("https://example.invalid/x", None, "T"))
        self.assertFalse(d["ok"])
        self.assertNotIn(["set", "pause", "no"], sent)


class PlayCommandClassification(unittest.TestCase):
    def test_missing_credentials_are_fatal(self):
        with tempfile.TemporaryDirectory() as home:
            r = subprocess.run([sys.executable, os.path.join(ROOT, "backend"), "play", "t:1"],
                               capture_output=True, text=True, env={**os.environ, "HOME": home})
        d = json.loads(r.stdout)
        self.assertFalse(d["ok"])
        self.assertIs(d["fatal"], True)
        self.assertNotIn("stream.view", r.stdout + r.stderr)

    def test_a_stream_failure_is_not_fatal(self):
        from backend import subsonic
        from backend.__main__ import play
        client = subsonic.Client("account-user-123456", "pw")
        out = io.StringIO()
        with mock.patch("backend.subsonic.Client", return_value=client), \
                mock.patch.object(mpvctl, "do_load",
                                  return_value=json.dumps({"ok": False, "error": "loading failed", "kind": "stream"})), \
                redirect_stdout(out):
            code = play("t:1", "A Song")
        d = json.loads(out.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(d["ok"])
        self.assertIs(d["fatal"], False)
        for secret in client.secret_values():
            self.assertNotIn(secret, out.getvalue())


if __name__ == "__main__":
    unittest.main()
