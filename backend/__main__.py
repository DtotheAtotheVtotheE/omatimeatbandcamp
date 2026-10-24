"""CLI:  python3 <plugin>/backend <command>

    sync [--workers N] [--no-tracks] [--cookies FILE] [--user-url URL] [--no-playlists]
                                        run a sync in this process (blocking); progress as JSON lines on stdout
    play <subsonic-track-id> [--title T]
                                        load that track into the mpv player (the stream URL, which embeds
                                        credentials, never leaves this process: not printed, not in argv,
                                        not in mpv's media-title)
    status                              print status.json (idle|running|done|error)
    summary                             print counts from the cached library (no network)
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
        print(json.dumps({"ok": False, "error": str(e)}))
        return 1
    import mpvctl
    try:
        result = json.loads(mpvctl.do_load(url, None, title or "Bandcamp track"))
    except Exception as e:  # noqa: BLE001
        result = {"ok": False, "error": str(e)}
    out = {"ok": result.get("ok") is True}
    if not out["ok"]:
        out["error"] = client.redact(str(result.get("error") or "playback failed"))
    print(json.dumps(out))
    return 0 if out["ok"] else 1


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
    args = ap.parse_args(argv)
    if args.cmd == "play":
        return play(args.track_id, args.title)
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
