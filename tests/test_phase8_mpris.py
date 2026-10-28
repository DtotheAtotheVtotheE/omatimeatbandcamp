#!/usr/bin/env python3
"""Phase 8 MPRIS tests: published metadata and the URL/credential fence.

Runs backend/mpris.py against a private session bus (dbus-daemon), with a
throwaway state file, cover file and control recorder. Nothing here touches the
real session bus, the real player, or the user's credentials.

The security assertion is the point of the file: mpv's `path` is a signed
stream URL. The daemon must publish only title/artist/album plus a local
file:// cover URI. A decoy `path`/`url`/`coverArtUrl` in the state file must be
ignored, and no published value (other than the local art URI) may contain a
URL scheme, query string or credential word.
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import dbus

ROOT = Path(__file__).resolve().parent.parent
DAEMON = ROOT / "backend" / "mpris.py"
MPVCTL = ROOT / "mpvctl.py"
IFACE_ROOT = "org.mpris.MediaPlayer2"
IFACE_PLAYER = "org.mpris.MediaPlayer2.Player"
IFACE_PROPS = "org.freedesktop.DBus.Properties"
OBJECT_PATH = "/org/mpris/MediaPlayer2"
TEST_NAME = "org.mpris.MediaPlayer2.omatimeatbandcamp.test8"


class MprisBridgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="omatime-mpris-test.")
        base = Path(cls.tmp.name)
        cls.state_path = base / "mpris-state.json"
        cls.art_path = base / "current-art.jpg"
        cls.art_path.write_bytes(b"\xff\xd8\xff\xd9")  # path only; never decoded
        cls.ctl_log = base / "ctl.log"
        cls.ctl_path = base / "ctl.sh"
        cls.ctl_path.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CTL_LOG\"\n", encoding="utf-8")
        cls.ctl_path.chmod(0o755)

        cls.bus_proc = subprocess.Popen(
            ["dbus-daemon", "--session", "--nofork", "--print-address=1"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        cls.address = cls.bus_proc.stdout.readline().strip()
        if not cls.address:
            raise unittest.SkipTest("could not start a private dbus-daemon")

        cls.write_state(playing=True)
        env = os.environ.copy()
        env["DBUS_SESSION_BUS_ADDRESS"] = cls.address
        env["CTL_LOG"] = str(cls.ctl_log)
        cls.daemon = subprocess.Popen(
            [sys.executable, str(DAEMON), "--state", str(cls.state_path),
             "--art", str(cls.art_path), "--ctl", str(cls.ctl_path),
             "--ctl-target", "test", "--name", TEST_NAME, "--idle-exit", "0"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

        cls.bus = dbus.bus.BusConnection(cls.address)
        deadline = time.time() + 5
        while time.time() < deadline:
            if cls.bus.name_has_owner(TEST_NAME):
                break
            if cls.daemon.poll() is not None:
                err = cls.daemon.stderr.read() if cls.daemon.stderr else ""
                raise RuntimeError("MPRIS daemon exited early: " + err)
            time.sleep(0.05)
        else:
            raise RuntimeError("MPRIS daemon did not claim its bus name")

        obj = cls.bus.get_object(TEST_NAME, OBJECT_PATH)
        cls.props = dbus.Interface(obj, IFACE_PROPS)
        cls.player = dbus.Interface(obj, IFACE_PLAYER)
        cls._wait_for(lambda: cls._status() == "Playing")

    @classmethod
    def tearDownClass(cls):
        try:
            cls.daemon.terminate()
            cls.daemon.wait(timeout=3)
        except Exception:
            cls.daemon.kill()
        try:
            cls.bus_proc.terminate()
            cls.bus_proc.wait(timeout=3)
        except Exception:
            cls.bus_proc.kill()
        for stream in (cls.bus_proc.stdout, cls.daemon.stderr):
            try:
                stream.close()
            except Exception:
                pass
        try:
            cls.bus.close()
        except Exception:
            pass
        cls.tmp.cleanup()

    # ---- helpers --------------------------------------------------------
    @classmethod
    def write_state(cls, playing=True, title="Test Track", artist="Test Artist",
                    album="Test Album", status=None, position=12.5, duration=200.0):
        # Decoy fields model what mpv's `path` would look like if it ever reached
        # the state file. The daemon must ignore them by construction.
        decoy = ("https://" + "example.invalid" + "/stream?u=" + "FAKEUSER"
                 + "&t=" + "FAKETOKEN" + "&s=" + "FAKESALT")
        state = {
            "title": title, "artist": artist, "album": album,
            "status": status or ("Playing" if playing else "Paused"),
            "position": position, "duration": duration,
            "updatedAt": int(time.time() * 1000),
            "canSeek": True, "canPlay": True, "canPause": True,
            "canNext": True, "canPrevious": False,
            "path": decoy, "url": decoy, "coverArtUrl": decoy,
        }
        cls.state_path.write_text(json.dumps(state), encoding="utf-8")

    @classmethod
    def _status(cls):
        try:
            return str(cls.props.Get(IFACE_PLAYER, "PlaybackStatus"))
        except dbus.exceptions.DBusException:
            return ""

    @classmethod
    def _wait_for(cls, predicate, timeout=3.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if predicate():
                return True
            time.sleep(0.05)
        return False

    def get_player(self):
        return self.props.GetAll(IFACE_PLAYER)

    def get_meta(self):
        return self.get_player()["Metadata"]

    # ---- tests ----------------------------------------------------------
    def test_published_metadata_is_clean_and_local(self):
        self.write_state()
        self.assertTrue(self._wait_for(lambda: str(self.get_meta().get("xesam:title")) == "Test Track"))

        player = self.get_player()
        meta = player["Metadata"]
        self.assertEqual(str(meta.get("xesam:title")), "Test Track")
        self.assertEqual([str(a) for a in meta.get("xesam:artist")], ["Test Artist"])
        self.assertEqual(str(meta.get("xesam:album")), "Test Album")
        self.assertEqual(str(player["PlaybackStatus"]), "Playing")
        self.assertGreaterEqual(int(player["Position"]), 12_000_000)

        art = str(meta.get("mpris:artUrl", ""))
        self.assertTrue(art.startswith("file://"), "art must be a local file URI")
        self.assertEqual(Path(art[7:]).resolve(), self.art_path.resolve())

        # The fence: every non-art value is free of URLs, query strings and
        # credential-looking material. This includes the decoy `path`/`url`/
        # `coverArtUrl` fields written into the state file above.
        others = {str(k): str(v) for k, v in meta.items() if str(k) != "mpris:artUrl"}
        blob = repr(others)
        self.assertNotIn("path", [str(k) for k in meta.keys()])
        self.assertNotIn("url", [str(k) for k in meta.keys()])
        self.assertNotIn("xesam:url", [str(k) for k in meta.keys()])
        self.assertNotIn("coverArtUrl", [str(k) for k in meta.keys()])
        self.assertFalse("example.invalid" in blob, "metadata leaked a remote URL")
        self.assertFalse("://" in blob, "metadata leaked a URL scheme")
        self.assertFalse("?" in blob, "metadata leaked a query string")
        self.assertFalse("FAKETOKEN" in blob, "metadata leaked a credential value")
        self.assertFalse("FAKESALT" in blob, "metadata leaked a credential value")

        root = self.props.GetAll(IFACE_ROOT)
        self.assertEqual(str(root["Identity"]), "OmaTimeAtBandcamp")
        self.assertEqual(bool(root["HasTrackList"]), False)
        self.assertEqual(bool(root["CanQuit"]), False)

    def test_state_updates_are_published(self):
        self.write_state(status="Paused", title="Paused Track")
        self.assertTrue(self._wait_for(lambda: str(self.get_meta().get("xesam:title")) == "Paused Track"))
        self.assertEqual(str(self.get_player()["PlaybackStatus"]), "Paused")

    def test_control_methods_reach_the_plugin_ipc(self):
        self.write_state()
        self.assertTrue(self._wait_for(lambda: str(self.get_meta().get("xesam:title")) == "Test Track"))
        if self.ctl_log.exists():
            self.ctl_log.unlink()

        self.player.PlayPause()
        self.player.Next()
        self.player.Previous()
        self.player.Pause()
        self.player.Play()
        self.player.Seek(dbus.Int64(5_000_000))
        self.player.SetPosition(self.get_meta()["mpris:trackid"], dbus.Int64(10_000_000))

        self.assertTrue(self._wait_for(lambda: self.ctl_log.exists() and len(self.ctl_log.read_text().splitlines()) >= 7))
        lines = self.ctl_log.read_text().splitlines()
        self.assertEqual(lines[:5], ["test playPause", "test next", "test previous",
                                     "test pause", "test resume"])
        self.assertTrue(lines[5].startswith("test seek "), "Seek must reach the plugin")
        self.assertTrue(lines[6].startswith("test seek "), "SetPosition must reach the plugin")

    def test_mpv_spawn_disables_global_mpris_script(self):
        spec = importlib.util.spec_from_file_location("omatime_mpvctl", MPVCTL)
        mpvctl = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mpvctl)
        calls = []

        class FakePopen:
            def __init__(self, args, **kwargs):
                calls.append(args)

        with mock.patch.object(mpvctl.subprocess, "Popen", FakePopen), \
                mock.patch("builtins.open", mock.mock_open()):
            mpvctl.spawn_mpv()
        self.assertTrue(calls, "spawn_mpv did not start a process")
        self.assertIn("--load-scripts=no", calls[0],
                      "our mpv must not load /etc/mpv/scripts/mpris.so")


if __name__ == "__main__":
    unittest.main()
