#!/usr/bin/env python3
import os
import sys
import json
import re
import time
import urllib.request
from pathlib import Path

CACHE_DIR = Path.home() / ".cache" / "omatimeatbandcamp"
COLL_FILE = CACHE_DIR / "collection.json"
PL_FILE = CACHE_DIR / "playlists.json"
IDX_FILE = CACHE_DIR / "index.json"

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

STREAM_KEYS = ["mp3-v0", "mp3-320", "mp3-128", "aac-hi", "flac", "wav", "aiff-lossless"]


def load_cookie(path):
    if not path:
        return None
    try:
        p = Path(path).expanduser()
        if not p.exists():
            return None
        parts = []
        for line in p.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            toks = line.split("\t")
            if len(toks) >= 7 and "bandcamp.com" in toks[0]:
                parts.append(f"{toks[5]}={toks[6]}")
        if parts:
            return "; ".join(parts)
    except Exception as e:
        print(f"cookie err {e}", file=sys.stderr)
    return None


def http(url, cookie=None, data=None):
    headers = {"User-Agent": UA, "Accept": "application/json, text/html"}
    if data is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(data).encode()
    if cookie:
        headers["Cookie"] = cookie
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read().decode("utf-8", "ignore")
    except Exception as e:
        print(f"fetch err {e} {url}", file=sys.stderr)
        return None


def get_json(url, cookie=None, data=None):
    raw = http(url, cookie, data)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None


def page_blob(url, cookie=None):
    html = http(url, cookie)
    if not html:
        return None
    m = re.search(r'data-blob="([^"]+)"', html)
    if not m:
        return None
    try:
        return json.loads(m.group(1).replace("&quot;", '"'))
    except Exception:
        return None


def secure_dir(p):
    p.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(p, 0o700)
    except OSError:
        pass


def write_secure(path, text):
    secure_dir(path.parent)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, path)


def resolve_account(cookie):
    """Return the logged-in fan from the identity cookie, or None.

    Any Bandcamp page carries an `identities.fan` object derived from the
    session cookie; /settings is the canonical self page. This lets the plugin
    work without the user pasting their profile URL.
    """
    if not cookie:
        return None
    blob = page_blob("https://bandcamp.com/settings", cookie)
    if not blob:
        return None
    fan = (blob.get("identities") or {}).get("fan")
    if not isinstance(fan, dict):
        return None
    username = fan.get("username")
    url = fan.get("url") or (f"https://bandcamp.com/{username}" if username else None)
    return {"fan_id": fan.get("id"), "username": username, "url": url}


def best_stream(fileobj):
    if not isinstance(fileobj, dict):
        return None
    for k in STREAM_KEYS:
        if fileobj.get(k):
            return fileobj[k]
    for v in fileobj.values():
        if isinstance(v, str) and v.startswith("http"):
            return v
    return None


def normalize_track(t, idx=0, album_title=None, album_url=None, artist=None):
    alb = t.get("album") if isinstance(t.get("album"), dict) else {}
    return {
        "id": str(t.get("id") or ""),
        "title": t.get("title") or "",
        "track_num": t.get("track_number") or t.get("track_num") or (idx + 1),
        "duration": t.get("duration") or 0,
        "streamUrl": t.get("streamUrl") or best_stream(t.get("file")),
        "trackUrl": t.get("url") or "",
        "albumUrl": album_url or alb.get("url") or "",
        "artist": t.get("artistName") or artist or "",
        "album": album_title or alb.get("title") or "",
        "streamType": t.get("streamType") or "d",
        "streamingDisabled": bool(t.get("isStreamingDisabled")),
    }


def fetch_tracklist(item_type, item_id, cookie=None):
    tracks = []
    cursor = None
    while True:
        d = get_json(
            "https://bandcamp.com/api/player/2/player_data_web",
            cookie,
            {"item_type": item_type, "item_id": int(item_id), "next_cursor": cursor},
        )
        if not d or "tracklist" not in d:
            break
        tl = d["tracklist"]
        artist = None
        if isinstance(tl.get("attribution"), dict):
            artist = tl["attribution"].get("name")
        album_title = tl.get("title")
        album_url = tl.get("itemUrl")
        for i, t in enumerate(tl.get("tracks") or []):
            tracks.append(normalize_track(t, i, album_title, album_url, artist))
        cursor = tl.get("nextCursor")
        if not cursor:
            break
        time.sleep(0.1)
    return tracks


def fan_username_from_url(url):
    return url.rstrip("/").split("/")[-1]


def normalize_item(v, artist=None):
    ttype = {"a": "album", "t": "track"}.get(v.get("tralbum_type"))
    itype = ttype or v.get("item_type") or "album"
    iid = v.get("tralbum_id") or v.get("item_id")
    if itype == "package":
        itype = {"a": "album", "t": "track"}.get(v.get("tralbum_type")) or "album"
    return {
        "id": str(iid or ""),
        "type": itype,
        "title": v.get("item_title") or v.get("title") or "",
        "artist": v.get("band_name") or artist or "",
        "item_url": v.get("item_url") or "",
        "album_url": v.get("item_url") or "",
        "art_id": v.get("item_art_id"),
        "tracks": [],
    }


def fetch_collection(user_url, cookie):
    username = fan_username_from_url(user_url)
    blob = page_blob(f"https://bandcamp.com/{username}", cookie)
    items = []
    seen = set()
    token = None
    fan_id = None
    if blob:
        fan_id = (blob.get("fan_data") or {}).get("fan_id")
        cd = blob.get("collection_data") or {}
        token = cd.get("last_token")
        cache = (blob.get("item_cache") or {}).get("collection") or {}
        for k, v in cache.items():
            item = normalize_item(v)
            key = (item["type"], item["id"])
            if item["id"] and key not in seen:
                seen.add(key)
                items.append(item)
    while token and fan_id:
        d = get_json(
            "https://bandcamp.com/api/fancollection/1/collection_items",
            cookie,
            {"fan_id": fan_id, "older_than_token": token, "count": 100},
        )
        if not d or d.get("error") or not d.get("items"):
            break
        tls = d.get("tracklists") or {}
        for v in d["items"]:
            key_str = (v.get("tralbum_type") or "") + str(v.get("tralbum_id") or v.get("item_id") or "")
            tl = tls.get(key_str) or []
            artist = tl[0].get("artist") if tl else None
            item = normalize_item(v, artist)
            key = (item["type"], item["id"])
            if item["id"] and key not in seen:
                seen.add(key)
                items.append(item)
        token = d.get("last_token")
        if not d.get("more_available"):
            break
        time.sleep(0.1)
    return items


def fetch_playlists(user_url, cookie):
    username = fan_username_from_url(user_url)
    blob = page_blob(f"https://bandcamp.com/{username}/playlists", cookie)
    fan_id = None
    if blob:
        fan_id = (blob.get("fan_data") or {}).get("fan_id")
    playlists = []
    token = None
    if not fan_id:
        return playlists
    while True:
        d = get_json(
            "https://bandcamp.com/api/fan_collection/1/playlists",
            cookie,
            {"page_fan_id": fan_id, "page_size": 50, "next_cursor": token, "query": None},
        )
        if not d or not d.get("items"):
            break
        for v in d["items"]:
            playlists.append(
                {
                    "id": str(v.get("itemId") or ""),
                    "name": v.get("title") or "Playlist",
                    "description": v.get("description"),
                    "url": v.get("itemUrl") or "",
                    "trackCount": (v.get("tracksSummary") or {}).get("totalCount"),
                    "tracks": [],
                }
            )
        token = d.get("nextCursor")
        if not token:
            break
        time.sleep(0.1)
    for pl in playlists:
        if pl["id"]:
            pl["tracks"] = fetch_tracklist("playlist", pl["id"], cookie)
            time.sleep(0.1)
    return playlists


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: fetch.py <userUrl> [cookiePath] [includePlaylists]", file=sys.stderr)
        sys.exit(1)
    if sys.argv[1] == "--tracks":
        if len(sys.argv) < 4:
            print("usage: fetch.py --tracks <item_type> <item_id> [cookiePath]", file=sys.stderr)
            sys.exit(1)
        item_type = sys.argv[2]
        item_id = sys.argv[3]
        cookie = load_cookie(sys.argv[4]) if len(sys.argv) > 4 else None
        tracks = fetch_tracklist(item_type, item_id, cookie)
        print(json.dumps({"ok": True, "tracks": tracks}))
        return

    user_url = sys.argv[1]
    cookie_path = sys.argv[2] if len(sys.argv) > 2 else ""
    include_pl = sys.argv[3] if len(sys.argv) > 3 else "1"
    cookie = load_cookie(cookie_path)

    detected = None
    if not user_url.strip():
        acct = resolve_account(cookie)
        if not acct or not acct.get("username"):
            print(
                json.dumps(
                    {
                        "ok": False,
                        "error": "not signed in to Bandcamp — sign in in your browser "
                        "or set your collection URL",
                    }
                )
            )
            return 1
        user_url = acct["url"]
        detected = acct["username"]

    secure_dir(CACHE_DIR)
    coll = fetch_collection(user_url, cookie)
    pls = fetch_playlists(user_url, cookie) if include_pl == "1" else []
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write_secure(COLL_FILE, json.dumps({"items": coll, "last_updated": now}, indent=2))
    write_secure(PL_FILE, json.dumps({"playlists": pls, "last_updated": now}, indent=2))
    all_tracks = []
    for pl in pls:
        for t in pl.get("tracks", []):
            all_tracks.append(t)
    write_secure(IDX_FILE, json.dumps({"all_tracks": all_tracks, "last_updated": now}, indent=2))
    print(
        json.dumps(
            {
                "ok": True,
                "coll": len(coll),
                "pl": len(pls),
                "user": detected or fan_username_from_url(user_url),
            }
        )
    )
    return 0


if __name__ == "__main__":
    main()
