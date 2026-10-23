#!/usr/bin/env python3
"""Phase 0 probe of the Bandcamp Subsonic endpoint (read-only).

Runs against the real API and writes spike/SUBSONIC-REPORT.md containing only
measured results. Nothing in the report is hand-written except section headings
and the labels for the figures that were *stated* (not measured) in advance.

    python3 spike/subsonic_probe.py

Credentials come from ~/.config/omatimeatbandcamp/credentials.toml. u/t/s are
never printed or written; the account `owner` id is masked in pasted JSON.
"""
import json
import os
import statistics
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from subsonic_client import BASE_URL, Client, build_url, build_params  # noqa: E402

REPORT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "SUBSONIC-REPORT.md")

# Figures stated by the user before the probe ran. Compared against, never reported as results.
STATED_ALBUMS = 645
STATED_PLAYLISTS = 33
STATED_POSTPUNKY = 213
POSTPUNKY_NAME = "Postpunky?"
PAGE = 500
OUT = []


def w(s=""):
    OUT.append(s)
    print(s, flush=True)


def mask(obj):
    """Deep-copy with the account-identifying `owner` field masked."""
    if isinstance(obj, dict):
        return {k: ("<owner-id>" if k == "owner" else mask(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [mask(v) for v in obj]
    return obj


def block(obj, limit=None):
    s = json.dumps(mask(obj), indent=2, ensure_ascii=False)
    if limit and len(s) > limit:
        s = s[:limit] + "\n... (truncated)"
    w("```json\n" + s + "\n```")


def sub(body):
    return (body or {}).get("subsonic-response")


def ok(c, method, **kw):
    """call() + unwrap. Returns (subsonic-response dict, seconds). Raises on failure."""
    body, dt, status, err = c.call(method, **kw)
    r = sub(body)
    if r is None or r.get("status") != "ok":
        raise RuntimeError(f"{method} {kw.get('id', '')} failed: http={status} err={err} resp={r}")
    return r, dt


def pull_albums(c):
    """Page getAlbumList2 until a short page. Returns (albums, seconds, page_timings)."""
    albums, pages, off = [], [], 0
    t0 = time.perf_counter()
    while True:
        r, dt = ok(c, "getAlbumList2", type="alphabeticalByName", size=PAGE, offset=off)
        page = r["albumList2"].get("album", [])
        pages.append((off, len(page), dt))
        albums += page
        if len(page) < PAGE:
            break
        off += PAGE
    return albums, time.perf_counter() - t0, pages


def pull_playlist(c, name):
    t0 = time.perf_counter()
    r, dt_list = ok(c, "getPlaylists")
    pls = r["playlists"].get("playlist", [])
    match = [p for p in pls if p["name"] == name]
    if not match:
        return pls, None, time.perf_counter() - t0, dt_list, None
    r2, dt_one = ok(c, "getPlaylist", id=match[0]["id"])
    return pls, r2["playlist"], time.perf_counter() - t0, dt_list, dt_one


def stream_probe(c, track_id):
    """Range-request the first KiB of a track. Returns dict; never records the redirect URL."""
    params = build_params(c.user, c.password, {"id": track_id})
    params.pop("f")
    t0 = time.perf_counter()
    try:
        r = c.session.get(f"{BASE_URL}/rest/stream.view", params=params,
                          headers={"Range": "bytes=0-1023"}, stream=True, timeout=30)
        dt = time.perf_counter() - t0
        ctype = r.headers.get("content-type", "")
        total = None
        cr = r.headers.get("content-range")
        if cr and "/" in cr:
            total = int(cr.rsplit("/", 1)[1])
        got = len(r.raw.read(1024)) if r.status_code in (200, 206) else 0
        r.close()
        good = r.status_code in (200, 206) and ctype.startswith("audio/") and got > 0
        return {"id": track_id, "http": r.status_code, "ctype": ctype, "total": total,
                "got": got, "ok": good, "secs": dt,
                "hops": [h.status_code for h in r.history], "xml_error": ctype.startswith(("text/", "application/xml"))}
    except Exception as e:  # noqa: BLE001
        return {"id": track_id, "http": None, "ctype": "", "total": None, "got": 0, "ok": False,
                "secs": time.perf_counter() - t0, "hops": [], "xml_error": False, "err": type(e).__name__}


def cover_probe(c, cid, size=None):
    kw = {"id": cid}
    if size:
        kw["size"] = size
    params = build_params(c.user, c.password, kw)
    params.pop("f")
    t0 = time.perf_counter()
    r1 = c.session.get(f"{BASE_URL}/rest/getCoverArt.view", params=params, allow_redirects=False, timeout=30)
    loc = r1.headers.get("location")
    r2 = c.session.get(loc, timeout=30) if loc else None
    dt = time.perf_counter() - t0
    return {"id": cid, "size_param": size, "api_http": r1.status_code,
            "redirect_host": urlparse(loc).netloc if loc else None,
            "final_http": r2.status_code if r2 is not None else None,
            "ctype": r2.headers.get("content-type") if r2 is not None else None,
            "bytes": len(r2.content) if r2 is not None else None,
            "magic": r2.content[:3].hex() if r2 is not None else None, "secs": dt}


def fmt_t(x):
    return f"{x:.2f} s"


def main():
    c = Client()
    started = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    w("# Subsonic API probe report (Phase 0)")
    w()
    w(f"Generated by `spike/subsonic_probe.py` on {started}. Every figure below was measured by that run against "
      f"`{BASE_URL}/rest/<method>.view` (token auth, fresh random salt per request, `f=json`). "
      "JSON is pasted as received, except that the account `owner` id is replaced with `<owner-id>`. "
      "u/t/s values are never recorded.")
    w()
    w("Figures supplied beforehand by the user (645 albums, 33 playlists, 213 tracks in \"Postpunky?\") are shown "
      "only as comparison points, labelled *stated*.")
    w()
    w("Request shape used: `GET " + build_url("<method>", {"f": "json", "u": "<u>", "t": "<t>", "s": "<s>", "v": "1.16.1", "c": "..."}
                                              ).replace("%3C", "<").replace("%3E", ">") + "`")

    # 1. ping / server info
    w("\n## 1. Ping / server info\n")
    for m in ("ping", "getOpenSubsonicExtensions", "getLicense"):
        body, dt, status, err = c.call(m)
        w(f"`{m}` -> HTTP {status}, {fmt_t(dt)}")
        block(sub(body) if body else {"error": err})
    ext = sub(c.call("getOpenSubsonicExtensions")[0]).get("openSubsonicExtensions")
    w(f"`openSubsonic` flag in ping: {sub(c.call('ping')[0]).get('openSubsonic')}; "
      f"`openSubsonicExtensions` entries advertised: {len(ext) if ext is not None else 'field absent'}.")

    # 2. album count
    w("\n## 2. Full album list\n")
    albums, secs, pages = pull_albums(c)
    ids = [a["id"] for a in albums]
    w(f"- Method: `getAlbumList2?type=alphabeticalByName&size={PAGE}&offset=N`, paged until a short page.")
    for off, n, dt in pages:
        w(f"  - offset {off}: {n} albums, {fmt_t(dt)}")
    w(f"- **Albums returned: {len(albums)}** ({len(set(ids))} unique ids). *Stated:* {STATED_ALBUMS}. "
      f"Difference: {len(albums) - STATED_ALBUMS:+d}.")
    w(f"- Albums with `songCount` = 0: {sum(1 for a in albums if a.get('songCount') == 0)}")
    w(f"- Total of `songCount` over albums: {sum(a.get('songCount', 0) for a in albums)}")
    for size in (1000, 5000):
        r, dt = ok(c, "getAlbumList2", type="alphabeticalByName", size=size)
        w(f"- Page-size check: `size={size}` -> {len(r['albumList2'].get('album', []))} albums in one response, {fmt_t(dt)}")
    r, dt = ok(c, "getAlbumList2", type="alphabeticalByName", size=PAGE + 1)
    w(f"- Page-size check: `size={PAGE + 1}` -> {len(r['albumList2'].get('album', []))} albums in one response")
    r, _ = ok(c, "getArtists")
    arts = [a for i in r["artists"]["index"] for a in i["artist"]]
    w(f"- `getArtists`: {len(arts)} artists, sum of `albumCount` = {sum(a.get('albumCount', 0) for a in arts)}")
    for t in ("newest", "recent", "frequent", "random", "alphabeticalByArtist"):
        r, _ = ok(c, "getAlbumList2", type=t, size=PAGE)
        w(f"- Other list type `{t}` (size={PAGE}, offset 0): {len(r['albumList2'].get('album', []))} albums")
    w("\nFirst two entries of the list, as received:")
    block(albums[:2])

    # 3. playlists
    w("\n## 3. Playlists\n")
    pls, pp, psecs, dt_list, dt_one = pull_playlist(c, POSTPUNKY_NAME)
    w(f"- **Playlists returned by `getPlaylists`: {len(pls)}**. *Stated:* {STATED_PLAYLISTS}. "
      f"Difference: {len(pls) - STATED_PLAYLISTS:+d}.")
    w(f"- Public: {sum(1 for p in pls if p.get('public'))}, private: {sum(1 for p in pls if not p.get('public'))}")
    w(f"- Sum of playlist `songCount`: {sum(p.get('songCount', 0) for p in pls)}")
    w("\nAll playlists (name, id, songCount, changed):\n")
    w("| name | id | songCount | changed |\n|---|---|---|---|")
    for p in pls:
        w(f"| {p['name']} | {p['id']} | {p.get('songCount')} | {p.get('changed')} |")
    w("\n### \"Postpunky?\"\n")
    if pp is None:
        w(f"**Playlist named `{POSTPUNKY_NAME}` not found.**")
    else:
        entries = pp.get("entry", [])
        tids = [e["id"] for e in entries]
        w(f"- Playlist metadata `songCount`: {pp.get('songCount')}")
        w(f"- **`entry` array length in `getPlaylist`: {len(entries)}** ({len(set(tids))} unique track ids). "
          f"*Stated:* {STATED_POSTPUNKY}. Difference: {len(entries) - STATED_POSTPUNKY:+d}.")
        w(f"- Playlist created {pp.get('created')}, last changed {pp.get('changed')} (compare with run time above).")
        w("\nPlaylist header and first entry, as received:")
        block({k: v for k, v in pp.items() if k != "entry"})
        block(entries[:1])

    # 4. critical albums
    w("\n## 4. Shamek Farrah albums\n")
    low = lambda s: (s or "").lower()  # noqa: E731
    w("### \"First Impressions (Deluxe Edition)\"\n")
    in_list = [a for a in albums if "first impressions" in low(a["name"])]
    w(f"- In the full album list ({len(albums)} albums), name contains \"first impressions\": {len(in_list)}")
    w("- In the full album list, artist contains \"farrah\": "
      + json.dumps([(a['name'], a['artist']) for a in albums if 'farrah' in low(a['artist'])], ensure_ascii=False))
    for q in ("First Impressions (Deluxe Edition)", "First Impressions", "Impressions"):
        r, dt = ok(c, "search3", query=q, albumCount=100, songCount=100, artistCount=100)
        s = r["searchResult3"]
        w(f"- `search3?query={q}` -> {len(s['artist'])} artists, {len(s['album'])} albums, {len(s['song'])} songs ({fmt_t(dt)})")
        if q.startswith("First Impressions ("):
            block(s)
    if pp:
        hits = [e for e in pp.get("entry", []) if "first impressions" in low(e.get("album"))]
        w(f"- Tracks in \"{POSTPUNKY_NAME}\" whose album contains \"first impressions\": {len(hits)}")
    w("\n### \"La Dee La La\"\n")
    ldl = [a for a in albums if low(a["name"]) == "la dee la la"]
    w(f"- In the full album list: {len(ldl)} -> " + json.dumps(mask(ldl), ensure_ascii=False))
    if ldl:
        r, dt = ok(c, "getAlbum", id=ldl[0]["id"])
        w(f"\n`getAlbum?id={ldl[0]['id']}` ({fmt_t(dt)}):")
        block(r["album"])
    for q in ("La Dee La La", "Shamek Farrah"):
        r, dt = ok(c, "search3", query=q, albumCount=100, songCount=100, artistCount=100)
        w(f"\n`search3?query={q}` ({fmt_t(dt)}):")
        block(r["searchResult3"])
    farr = [a for a in arts if "farrah" in low(a["name"])]
    for a in farr:
        r, dt = ok(c, "getArtist", id=a["id"])
        w(f"\n`getArtist?id={a['id']}` ({fmt_t(dt)}):")
        block(r["artist"])

    # 5. cover art
    w("\n## 5. getCoverArt\n")
    w("`getCoverArt.view` returns an HTTP redirect to the image CDN; the Location URL is not recorded here, only its host.\n")
    covers = []
    if ldl:
        covers += [(ldl[0]["coverArt"], None), (ldl[0]["coverArt"], 300), (ldl[0]["coverArt"], 50)]
    if pp:
        covers.append((pp["coverArt"], None))
    if farr:
        covers.append((farr[0]["coverArt"], None))
    covers.append((albums[0]["coverArt"], None))
    w("| id | size param | API HTTP | redirect host | final HTTP | content-type | bytes | magic | secs |\n|---|---|---|---|---|---|---|---|---|")
    for cid, size in covers:
        x = cover_probe(c, cid, size)
        w(f"| {x['id']} | {x['size_param']} | {x['api_http']} | {x['redirect_host']} | {x['final_http']} | "
          f"{x['ctype']} | {x['bytes']} | {x['magic']} | {x['secs']:.2f} |")
    w("\n(magic `ffd8ff` = JPEG.) If the byte counts are identical across `size` values, the server ignores `size`.")
    miss = [a for a in albums if not a.get("coverArt")]
    w(f"\nAlbums in the full list with no `coverArt` field: {len(miss)} of {len(albums)}")

    # 6. streamability, one released album
    w("\n## 6. Per-track streamability: \"La Dee La La\"\n")
    if ldl:
        r, _ = ok(c, "getAlbum", id=ldl[0]["id"])
        w("Each track is requested via `stream.view?id=<track>` with `Range: bytes=0-1023`; a track counts as streamable "
          "if the final response is 200/206 with an `audio/*` content-type and bytes arrive.\n")
        w("| # | title | id | http | hops | content-type | total bytes | metadata `size` | streamable |\n|---|---|---|---|---|---|---|---|---|")
        for s in r["album"]["song"]:
            x = stream_probe(c, s["id"])
            w(f"| {s.get('track')} | {s['title']} | {s['id']} | {x['http']} | {x['hops']} | {x['ctype']} | "
              f"{x['total']} | {s.get('size')} | {'yes' if x['ok'] else 'NO'} |")
    w("\nNon-existent id for comparison (`stream?id=t:1`, with `f=json` sent):")
    x = stream_probe(c, "t:1")
    w(f"- http {x['http']}, content-type `{x['ctype']}`, streamable: {x['ok']}")

    # 6b. streamability across Postpunky
    if pp:
        w("\n### Streamability across every entry in \"Postpunky?\"\n")
        res = [stream_probe(c, e["id"]) for e in pp["entry"]]
        bad = [(e, x) for e, x in zip(pp["entry"], res) if not x["ok"]]
        w(f"- Tracks probed: {len(res)}; streamable: {sum(1 for x in res if x['ok'])}; not streamable: {len(bad)}")
        for e, x in bad[:40]:
            w(f"  - {e.get('artist')} - {e.get('title')} ({e['id']}): http {x['http']}, `{x['ctype']}`")
        w(f"- Median probe time {statistics.median(x['secs'] for x in res):.2f} s")

    # 7. timings
    w("\n## 7. Timings\n")
    w("Wall-clock, sequential requests, one `requests.Session`. Three repetitions each.\n")
    ra, rp = [], []
    for _ in range(3):
        a, s, _p = pull_albums(c)
        ra.append((s, len(a)))
    for _ in range(3):
        l, p, s, dl, do = pull_playlist(c, POSTPUNKY_NAME)
        rp.append((s, len(p.get("entry", [])) if p else 0, dl, do))
    w("| pull | run 1 | run 2 | run 3 |\n|---|---|---|---|")
    w(f"| Full album list ({PAGE}/page, {ra[0][1]} albums) | " + " | ".join(fmt_t(s) for s, _ in ra) + " |")
    w(f"| \"{POSTPUNKY_NAME}\" (`getPlaylists` + `getPlaylist`, {rp[0][1]} tracks) | " + " | ".join(fmt_t(s) for s, *_ in rp) + " |")
    w(f"| of which `getPlaylists` | " + " | ".join(fmt_t(x[2]) for x in rp) + " |")
    w(f"| of which `getPlaylist` | " + " | ".join(fmt_t(x[3]) for x in rp) + " |")

    w("\n### Deep pull: `getAlbum` for every album (tracks for the whole collection)\n")
    t0 = time.perf_counter()
    per, tracks, failed, nosize, mism = [], 0, [], 0, []
    for a in albums:
        try:
            r, dt = ok(c, "getAlbum", id=a["id"])
            per.append(dt)
            songs = r["album"].get("song", [])
            tracks += len(songs)
            if len(songs) != a.get("songCount"):
                mism.append((a["id"], a["artist"], a["name"], a.get("songCount"), len(songs), r["album"].get("songCount")))
            nosize += sum(1 for s in songs if "size" not in s)
        except Exception as e:  # noqa: BLE001
            failed.append((a["id"], a["name"], str(e)[:120]))
    total = time.perf_counter() - t0
    w(f"- {len(albums)} `getAlbum` calls: **{fmt_t(total)}** total ({len(failed)} failed)")
    if per:
        w(f"- Per call: median {statistics.median(per):.2f} s, mean {statistics.mean(per):.2f} s, max {max(per):.2f} s")
    w(f"- Tracks returned: {tracks}; tracks lacking a `size` field in `getAlbum`: {nosize}")
    for f in failed[:20]:
        w(f"  - FAILED {f}")
    w(f"\n### `songCount` in album list vs tracks actually returned by `getAlbum`\n")
    w(f"- Albums where list `songCount` != number of `song` entries in `getAlbum`: {len(mism)} of {len(albums)}")
    w(f"- Sum of list `songCount`: {sum(a.get('songCount', 0) for a in albums)}; sum of tracks returned: {tracks}")
    if mism:
        w("\n| id | artist | album | list songCount | getAlbum songs | getAlbum songCount |\n|---|---|---|---|---|---|")
        for m in mism[:60]:
            w("| " + " | ".join(str(x).replace("|", "/") for x in m) + " |")
        if len(mism) > 60:
            w(f"\n(first 60 of {len(mism)} shown)")
    zero = [a for a in albums if a.get("songCount") == 0]
    w("\nAlbums with list `songCount` = 0, as received:")
    block(zero)

    with open(REPORT, "w") as f:
        f.write("\n".join(OUT) + "\n")
    print(f"\nwrote {REPORT}")


if __name__ == "__main__":
    main()
