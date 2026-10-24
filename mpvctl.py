#!/usr/bin/env python3
"""Tiny mpv IPC controller for OmaTimeAtBandCamp.

Keeps one idle mpv instance alive with an IPC socket so track changes,
pause/resume and volume are fast JSON commands rather than process spawns.

Usage:
  mpvctl.py ensure
  mpvctl.py load <url> [cookiePath] [title]
  mpvctl.py cmd '<json command>'
  mpvctl.py pause
  mpvctl.py play
  mpvctl.py toggle
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
from pathlib import Path

UID = os.getuid()
SOCK = os.environ.get("OMATIME_MPV_SOCK") or f"/tmp/omatime-mpv-{UID}.sock"


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
        f"--input-ipc-server={SOCK}",
    ]
    extra = os.environ.get("OMATIME_MPV_FLAGS", "").strip()
    if extra:
        args.extend(extra.split())
    log = open(f"/tmp/omatime-mpv-{UID}.log", "ab")
    subprocess.Popen(args, stdout=log, stderr=log, stdin=subprocess.DEVNULL,
                     start_new_session=True)


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


def do_load(url, cookie_path=None, title=None):
    if not url:
        return json.dumps({"ok": False, "error": "no url"})
    if not ensure():
        return json.dumps({"ok": False, "error": "mpv did not start"})

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
        return json.dumps({"ok": False, "error": "headers: " + str(hdr.get("error"))})

    # Without a title mpv falls back to the URL as `media-title`, which for a Subsonic stream
    # embeds credentials and would surface in every client of the player (MPRIS, bars,
    # this command's own output). Always set it explicitly ("" clears a stale one).
    send_json(["set_property", "force-media-title", title or ""])

    res = send_json(["loadfile", url, "replace"])
    if res.get("error") != "success":
        return json.dumps({"ok": False, "error": str(res.get("error") or "load failed")})

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
        cookie = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
        title = sys.argv[4] if len(sys.argv) > 4 else None
        print(do_load(sys.argv[2], cookie, title))
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
        if not socket_alive():
            print(json.dumps({"running": False}))
            return 0
        raw = send(["get_property", "pause"])
        raw2 = send(["get_property", "media-title"])
        print(json.dumps({"running": True, "pause_raw": raw, "title_raw": raw2}))
    else:
        print(f"unknown action {action}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
