#!/usr/bin/env python3
"""MPRIS (org.mpris.MediaPlayer2) bridge for OmaTimeAtBandCamp.

Why a separate process: the QML shell has no D-Bus *server* API, but the
playback state already lives in QML. Service.qml writes a small JSON state file
(title/artist/album/status/position) and this daemon publishes it on the session
bus, so the laptop's media keys (which Omarchy maps to `omarchy-shell media ...`)
can control playback.

Security fence (spec Phase 8):
  * mpv's `path` property is a signed stream URL with u/t/s parameters. It is
    never read here: the state file is parsed with an explicit key whitelist,
    so even a `path`/`url` field in the file is ignored.
  * The cover URL is never read either. `mpris:artUrl` is built here from the
    local cached file passed as --art, and only if it is a real file:// path.
  * Nothing is printed or logged. Control commands go to the plugin's IPC
    (`omarchy-shell omatimeatbandcamp <method>`), not through a shell.

Run: python3 backend/mpris.py --state <state.json> --art <current-art.jpg>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

DEFAULT_NAME = "org.mpris.MediaPlayer2.omatimeatbandcamp"
OBJECT_PATH = "/org/mpris/MediaPlayer2"
IFACE_ROOT = "org.mpris.MediaPlayer2"
IFACE_PLAYER = "org.mpris.MediaPlayer2.Player"
IFACE_PROPS = "org.freedesktop.DBus.Properties"

# Only these keys are ever copied out of the state file. Everything else,
# including any accidental path/url/credential field, is ignored.
STATE_KEYS = ("title", "artist", "album", "status", "position", "duration", "updatedAt",
              "canSeek", "canPlay", "canPause", "canNext", "canPrevious")


def _text(value) -> str:
    return value if isinstance(value, str) else ""


def _number(value) -> float:
    try:
        n = float(value)
    except (TypeError, ValueError):
        return 0.0
    return n if n >= 0 and n == n and n != float("inf") else 0.0


def _flag(value) -> bool:
    return value is True


def read_state(path: str) -> dict | None:
    """Parse the whitelisted playback state. Never raises."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(raw, dict):
        return None
    out = {k: raw.get(k) for k in STATE_KEYS}
    status = out.get("status")
    out["status"] = status if status in ("Playing", "Paused", "Stopped") else "Stopped"
    for k in ("title", "artist", "album"):
        out[k] = _text(out.get(k))
    for k in ("position", "duration", "updatedAt"):
        out[k] = _number(out.get(k))
    for k in ("canSeek", "canPlay", "canPause", "canNext", "canPrevious"):
        out[k] = _flag(out.get(k))
    return out


def empty_state() -> dict:
    return read_state("/nonexistent") or {
        "title": "", "artist": "", "album": "", "status": "Stopped",
        "position": 0.0, "duration": 0.0, "updatedAt": 0.0,
        "canSeek": False, "canPlay": False, "canPause": False,
        "canNext": False, "canPrevious": False,
    }


class MprisPlayer(dbus.service.Object):
    def __init__(self, bus, name, state_path, art_path, ctl, ctl_target, idle_exit):
        self._state_path = state_path
        self._ctl = ctl
        self._ctl_target = ctl_target
        self._idle_exit = max(0, int(idle_exit))
        self._mtime = -1
        self._last_read = time.time()
        self._plain = None
        self._state = read_state(state_path) or empty_state()

        art = Path(art_path).expanduser()
        # Local cached cover only. A remote URL can never become mpris:artUrl.
        self._art_uri = art.resolve().as_uri() if art.is_absolute() or art.exists() else ""
        if not self._art_uri.startswith("file://"):
            self._art_uri = ""

        super().__init__(bus, OBJECT_PATH)
        self._apply(self._state, emit=False)

    # ---- state ----------------------------------------------------------
    def _position_now(self) -> float:
        s = self._state
        pos = s["position"]
        if s["status"] == "Playing" and s["updatedAt"] > 0:
            pos += max(0.0, time.time() - s["updatedAt"] / 1000.0)
        if s["duration"] > 0:
            pos = min(pos, s["duration"])
        return max(0.0, pos)

    def _track_id(self) -> dbus.ObjectPath:
        s = self._state
        key = "\x1f".join((s["title"], s["artist"], s["album"]))
        digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]
        return dbus.ObjectPath(f"/org/omatimeatbandcamp/track/{digest}")

    def _metadata(self) -> dbus.Dictionary:
        s = self._state
        meta = {
            "mpris:trackid": self._track_id(),
            "mpris:length": dbus.Int64(int(round(s["duration"] * 1_000_000))),
            "xesam:title": dbus.String(s["title"]),
            "xesam:artist": dbus.Array([s["artist"]] if s["artist"] else [], signature="s"),
            "xesam:album": dbus.String(s["album"]),
        }
        if self._art_uri:
            meta["mpris:artUrl"] = dbus.String(self._art_uri)
        return dbus.Dictionary(meta, signature="sv")

    def _player_props(self) -> dict:
        s = self._state
        return {
            "PlaybackStatus": dbus.String(s["status"]),
            "Rate": dbus.Double(1.0),
            "MinimumRate": dbus.Double(1.0),
            "MaximumRate": dbus.Double(1.0),
            "Metadata": self._metadata(),
            "Volume": dbus.Double(1.0),
            "Position": dbus.Int64(int(round(self._position_now() * 1_000_000))),
            "CanGoNext": dbus.Boolean(s["canNext"]),
            "CanGoPrevious": dbus.Boolean(s["canPrevious"]),
            "CanPlay": dbus.Boolean(s["canPlay"]),
            "CanPause": dbus.Boolean(s["canPause"]),
            "CanSeek": dbus.Boolean(s["canSeek"]),
            "CanControl": dbus.Boolean(True),
        }

    def _root_props(self) -> dict:
        return {
            "CanQuit": dbus.Boolean(False),
            "CanRaise": dbus.Boolean(False),
            "HasTrackList": dbus.Boolean(False),
            "Identity": dbus.String("OmaTimeAtBandCamp"),
            "DesktopEntry": dbus.String("omatimeatbandcamp"),
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        }

    def _props(self, interface: str) -> dict:
        if interface == IFACE_PLAYER:
            return self._player_props()
        if interface == IFACE_ROOT:
            return self._root_props()
        return {}

    def _apply(self, state: dict, emit: bool = True) -> None:
        old = self._plain
        self._state = state
        plain = (state["status"], state["title"], state["artist"], state["album"],
                 state["duration"], state["canSeek"], state["canPlay"], state["canPause"],
                 state["canNext"], state["canPrevious"])
        self._plain = plain
        if not emit or old is None or old == plain:
            return
        changed = {}
        if old[0] != plain[0]:
            changed["PlaybackStatus"] = dbus.String(state["status"])
        if old[1:5] != plain[1:5]:
            changed["Metadata"] = self._metadata()
        for i, key in ((5, "CanSeek"), (6, "CanPlay"), (7, "CanPause"),
                       (8, "CanGoNext"), (9, "CanGoPrevious")):
            if old[i] != plain[i]:
                changed[key] = dbus.Boolean(plain[i])
        if changed:
            self.PropertiesChanged(IFACE_PLAYER,
                                  dbus.Dictionary(changed, signature="sv"),
                                  dbus.Array([], signature="s"))

    # ---- control --------------------------------------------------------
    def _ctl_call(self, method: str, *args) -> None:
        cmd = [self._ctl, self._ctl_target, method] + [str(a) for a in args]
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=5, check=False)
        except (OSError, subprocess.SubprocessError):
            pass

    # ---- org.freedesktop.DBus.Properties --------------------------------
    @dbus.service.method(IFACE_PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        props = self._props(interface)
        if prop not in props:
            raise dbus.exceptions.DBusException(
                f"Unknown property {prop}", name="org.freedesktop.DBus.Error.InvalidArgs")
        return props[prop]

    @dbus.service.method(IFACE_PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self._props(interface), signature="sv")

    @dbus.service.method(IFACE_PROPS, in_signature="ssv", out_signature="")
    def Set(self, interface, prop, value):
        # Volume is the only writable MPRIS property; this player is always at 1.0.
        if interface == IFACE_PLAYER and prop == "Volume":
            return
        raise dbus.exceptions.DBusException(
            f"Property {prop} is not writable", name="org.freedesktop.DBus.Error.PropertyReadOnly")

    @dbus.service.signal(IFACE_PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    # ---- org.mpris.MediaPlayer2 -----------------------------------------
    @dbus.service.method(IFACE_ROOT, in_signature="", out_signature="")
    def Raise(self):
        pass

    @dbus.service.method(IFACE_ROOT, in_signature="", out_signature="")
    def Quit(self):
        pass

    # ---- org.mpris.MediaPlayer2.Player ----------------------------------
    @dbus.service.method(IFACE_PLAYER, in_signature="", out_signature="")
    def Next(self):
        self._ctl_call("next")

    @dbus.service.method(IFACE_PLAYER, in_signature="", out_signature="")
    def Previous(self):
        self._ctl_call("previous")

    @dbus.service.method(IFACE_PLAYER, in_signature="", out_signature="")
    def Pause(self):
        self._ctl_call("pause")

    @dbus.service.method(IFACE_PLAYER, in_signature="", out_signature="")
    def PlayPause(self):
        self._ctl_call("playPause")

    @dbus.service.method(IFACE_PLAYER, in_signature="", out_signature="")
    def Stop(self):
        self._ctl_call("stop")

    @dbus.service.method(IFACE_PLAYER, in_signature="", out_signature="")
    def Play(self):
        self._ctl_call("resume")

    @dbus.service.method(IFACE_PLAYER, in_signature="x", out_signature="")
    def Seek(self, offset):
        target = self._position_now() + int(offset) / 1_000_000
        self._ctl_call("seek", f"{max(0.0, target):.3f}")

    @dbus.service.method(IFACE_PLAYER, in_signature="ox", out_signature="")
    def SetPosition(self, track_id, position):
        self._ctl_call("seek", f"{max(0.0, int(position) / 1_000_000):.3f}")

    @dbus.service.method(IFACE_PLAYER, in_signature="s", out_signature="")
    def OpenUri(self, uri):
        pass


def _die_with_parent() -> None:
    """Ask the kernel to SIGTERM us when the Quickshell process goes away.

    Without this, `omarchy restart shell` would leave the old daemon holding the
    MPRIS name until its 60 s idle timeout, and the new daemon would exit because
    the name is taken.
    """
    try:
        import ctypes
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except Exception:
        pass


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="OmaTimeAtBandCamp MPRIS bridge")
    ap.add_argument("--state", required=True)
    ap.add_argument("--art", required=True)
    ap.add_argument("--ctl", default="omarchy-shell")
    ap.add_argument("--ctl-target", default="omatimeatbandcamp")
    ap.add_argument("--name", default=DEFAULT_NAME)
    ap.add_argument("--idle-exit", type=int, default=60,
                    help="exit after this many seconds without a state update (0 = never)")
    args = ap.parse_args(argv)
    _die_with_parent()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        bus_name = dbus.service.BusName(args.name, bus=bus, do_not_queue=True)
    except dbus.exceptions.NameExistsException:
        return 0  # another instance owns the name; never fight it

    player = MprisPlayer(bus, args.name, args.state, args.art,
                         args.ctl, args.ctl_target, args.idle_exit)
    player.bus_name = bus_name  # keep the name owned for the process lifetime

    loop = GLib.MainLoop()

    def poll():
        now = time.time()
        try:
            mtime = os.stat(args.state).st_mtime_ns
        except OSError:
            mtime = -1
        if mtime != player._mtime:
            player._mtime = mtime
            state = read_state(args.state)
            if state is not None:
                player._last_read = now
                player._apply(state)
        if args.idle_exit and now - player._last_read > args.idle_exit:
            loop.quit()
            return False
        return True

    GLib.timeout_add(200, poll)

    def quit_loop(*_):
        loop.quit()

    signal.signal(signal.SIGTERM, quit_loop)
    signal.signal(signal.SIGINT, quit_loop)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
