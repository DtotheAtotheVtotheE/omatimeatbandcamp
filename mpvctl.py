#!/usr/bin/env python3
"""Tiny mpv IPC controller for OmaTimeAtBandcamp.

Keeps one idle mpv instance alive with an IPC socket so track changes,
pause/resume and volume are fast JSON commands rather than process spawns.

Usage:
  mpvctl.py ensure
  mpvctl.py load <url> [cookiePath] [title]
  mpvctl.py cmd '<json command>'
  mpvctl.py pause
  mpvctl.py play
  mpvctl.py toggle
  mpvctl.py seek <seconds>
  mpvctl.py stop
  mpvctl.py volume <0-150>
  mpvctl.py quit
  mpvctl.py status
"""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

UID = os.getuid()
SOCK = os.environ.get("OMATIME_MPV_SOCK") or f"/tmp/omatime-mpv-{UID}.sock"
CACHE_DIR = Path(os.environ.get("OMATIME_CACHE_DIR")
                 or (Path.home() / ".cache" / "omatimeatbandcamp"))


def _open_log():
    """Open the mpv log at 0600 under the private cache dir, never following a symlink."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(CACHE_DIR, 0o700)
    except OSError:
        pass
    path = CACHE_DIR / f"mpv-{UID}.log"
    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
    except OSError:
        pass
    return os.fdopen(fd, "ab")


def connect(timeout=2.0):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(SOCK)
    return s


def socket_alive():
    if not Path(SOCK).exists():
        return False
    try:
        connect(0.5).close()
        return True
    except OSError:
        return False


def spawn_mpv():
    args = [
        "mpv",
        "--idle=yes",
        "--no-video",
        "--force-window=no",
        "--really-quiet",
        "--no-input-terminal",
        "--user-agent=Mozilla/5.0",
        # /etc/mpv/scripts/mpris.so is auto-loaded into every mpv on this system.
        # It would publish mpv's `path` (the credential-bearing stream URL) on
        # D-Bus, so our headless player must never load auto-loaded scripts.
        # Playback control is exposed by backend/mpris.py with library metadata.
        "--load-scripts=no",
        f"--input-ipc-server={SOCK}",
    ]
    extra = os.environ.get("OMATIME_MPV_FLAGS", "").strip()
    if extra:
        args.extend(extra.split())
    log = _open_log()
    try:
        subprocess.Popen(args, stdout=log, stderr=log, stdin=subprocess.DEVNULL,
                         start_new_session=True)
    finally:
        log.close()


def ensure():
    if socket_alive():
        return True
    if Path(SOCK).exists():
        try:
            os.unlink(SOCK)
        except OSError:
            pass
    spawn_mpv()
    for _ in range(50):
        if socket_alive():
            return True
        time.sleep(0.1)
    return False


def send(command):
    payload = json.dumps({"command": command}) + "\n"
    with connect() as s:
        s.sendall(payload.encode())
        try:
            return s.recv(65536).decode("utf-8", "ignore").strip()
        except socket.timeout:
            return ""


AUTH_PARAMS = {"u", "t", "s", "p", "token", "password", "auth", "key", "sig"}


def url_has_credentials(url):
    """True when an argv URL carries embedded credentials or auth parameters."""
    try:
        parsed = urllib.parse.urlsplit(str(url))
    except ValueError:
        return True
    if parsed.scheme not in ("file", "http", "https"):
        return True
    if parsed.username is not None or parsed.password is not None:
        return True
    try:
        names = urllib.parse.parse_qs(parsed.query, keep_blank_values=True).keys()
    except ValueError:
        return True
    return any(name.lower() in AUTH_PARAMS for name in names)


def cookie_header(cookie_path):
    if not cookie_path:
        return None
    try:
        data = Path(cookie_path).expanduser().read_text(errors="ignore")
    except OSError:
        return None
    parts = []
    for line in data.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        toks = line.split("\t")
        if len(toks) >= 7 and "bandcamp.com" in toks[0]:
            parts.append(f"{toks[5]}={toks[6]}")
    return "; ".join(parts) if parts else None


def send_json(command):
    """Send one command and decode mpv's JSON reply into a Python dict."""
    raw = send(command)
    if not raw:
        return {}
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if "error" in obj:
            return obj
    return {}


def query(props, timeout=2.0):
    """Read several mpv properties over ONE connection.

    Returns {name: value or None}. Deliberately never requests `media-title` or
    `path` from callers that could print them: for a Subsonic stream both hold
    the URL, and the URL embeds the account's credentials.
    """
    if not socket_alive():
        return {}
    pending = {i: p for i, p in enumerate(props)}
    try:
        with connect(timeout) as s:
            for i, p in pending.items():
                s.sendall((json.dumps({"command": ["get_property", p], "request_id": i}) + "\n").encode())
            out, buf, deadline = {}, b"", time.time() + timeout
            while len(out) < len(pending) and time.time() < deadline:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    try:
                        obj = json.loads(line)
                    except ValueError:
                        continue
                    rid = obj.get("request_id")
                    if rid in pending:
                        out[rid] = None if obj.get("error") not in (None, "success") else obj.get("data")
            return {name: out.get(i) for i, name in pending.items()}
    except OSError:
        return {}


def do_status():
    """Current position/duration/pause state as JSON. No titles, no URLs."""
    if not socket_alive():
        return {"running": False}
    d = query(["time-pos", "duration", "pause", "idle-active", "eof-reached", "seekable"])
    return {
        "running": True,
        "position": d.get("time-pos"),
        "duration": d.get("duration"),
        "paused": d.get("pause"),
        "idle": d.get("idle-active"),
        "eof": d.get("eof-reached"),
        "seekable": d.get("seekable"),
    }


def do_seek(seconds):
    """Seek to an absolute position. `absolute+exact` lands on the requested
    second rather than the previous keyframe. mpv seeks inside its network cache
    fine for Subsonic streams (verified live, see V2-NOTES.md)."""
    if not socket_alive():
        return {"ok": False, "error": "not running"}
    try:
        target = max(0.0, float(seconds))
    except (TypeError, ValueError):
        return {"ok": False, "error": "bad position"}
    res = send_json(["seek", target, "absolute+exact"])
    if res.get("error") not in (None, "success"):
        return {"ok": False, "error": str(res.get("error"))}
    return {"ok": True, "position": target}


def do_load(url, cookie_path=None, title=None):
    if not url:
        return json.dumps({"ok": False, "error": "no url", "kind": "environment"})
    if not ensure():
        return json.dumps({"ok": False, "error": "mpv did not start", "kind": "environment"})

    headers = ["User-Agent: Mozilla/5.0"]
    cookie = cookie_header(cookie_path)
    if cookie:
        headers.append(f"Cookie: {cookie}")

    # In mpv >= 0.38 the loadfile signature is
    #   loadfile <url> [<flags> [<index> [<options>]]]
    # so per-file options can no longer be appended as bare arguments (they get
    # parsed as <index>, yielding "invalid parameter"). Set the headers as a
    # property first, then issue a plain three-argument loadfile.
    hdr = send_json(["set_property", "http-header-fields", headers])
    if hdr.get("error") not in (None, "success"):
        return json.dumps({"ok": False, "error": "headers: " + str(hdr.get("error")), "kind": "environment"})

    # Without a title mpv falls back to the URL as `media-title`, which for a Subsonic stream
    # embeds credentials and would surface in every client of the player (MPRIS, bars,
    # this command's own output). Always set it explicitly ("" clears a stale one).
    send_json(["set_property", "force-media-title", title or ""])

    res = send_json(["loadfile", url, "replace"])
    if res.get("error") != "success":
        return json.dumps({"ok": False, "error": str(res.get("error") or "load failed"), "kind": "stream"})

    # mpv keeps `pause` across loadfile, so a player left paused by an earlier
    # session would load the first new track paused while the service believes it
    # is playing. Every load from here is meant to play (Service.playCurrent()
    # sets isPlaying=true/isPaused=false), so clear the inherited pause. Ignore
    # the reply: the load itself already succeeded.
    send_json(["set", "pause", "no"])

    # Never read `media-title` back: it may be (or contain) the URL.
    return json.dumps({"ok": True, "title": title or ""})


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    action = sys.argv[1]
    if action == "ensure":
        ok = ensure()
        print("ok" if ok else "failed")
        return 0 if ok else 1
    if action == "load":
        if len(sys.argv) < 3:
            return 2
        url = sys.argv[2]
        if url_has_credentials(url):
            # The in-process `backend play` path calls do_load() with the signed
            # stream URL; argv must never carry one.
            print(json.dumps({"ok": False, "error": "refusing a credential-bearing URL in argv",
                              "kind": "environment"}))
            return 2
        cookie = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
        title = sys.argv[4] if len(sys.argv) > 4 else None
        print(do_load(url, cookie, title))
        return 0
    if action == "cmd":
        if len(sys.argv) < 3:
            return 2
        ensure()
        print(send(json.loads(sys.argv[2])))
        return 0
    if action == "pause":
        ensure()
        print(send(["set", "pause", "yes"]))
    elif action == "play":
        ensure()
        print(send(["set", "pause", "no"]))
    elif action == "toggle":
        ensure()
        print(send(["cycle", "pause"]))
    elif action == "stop":
        if socket_alive():
            print(send(["stop"]))
        else:
            print("not running")
    elif action == "volume":
        ensure()
        print(send(["set", "volume", sys.argv[2] if len(sys.argv) > 2 else "100"]))
    elif action == "quit":
        if socket_alive():
            print(send(["quit"]))
        else:
            print("not running")
    elif action == "status":
        print(json.dumps(do_status()))
    elif action == "seek":
        if len(sys.argv) < 3:
            return 2
        print(json.dumps(do_seek(sys.argv[2])))
    else:
        print(f"unknown action {action}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
