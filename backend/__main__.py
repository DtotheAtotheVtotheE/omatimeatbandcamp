"""CLI:  python3 <plugin>/backend <command>

    sync [--workers N] [--no-tracks]   run a sync in this process (blocking); progress as JSON lines on stdout
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


def main(argv=None):
    ap = argparse.ArgumentParser(prog="backend")
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("sync")
    s.add_argument("--workers", type=int, default=4)
    s.add_argument("--no-tracks", action="store_true")
    sp.add_parser("status")
    sp.add_parser("summary")
    args = ap.parse_args(argv)
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

    try:
        lib.sync(workers=args.workers, deep=not args.no_tracks, progress=progress)
    except SyncBusy:
        print(json.dumps({"error": "another sync is running"}))
        return 2
    except Exception as e:  # noqa: BLE001
        print(json.dumps({"error": lib._redact(str(e))}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
