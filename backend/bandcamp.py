"""Bandcamp web side: the collection feed and album-page data-tralbum.

Network access goes through an injectable `http` callable so the parsers are
testable offline. Session cookies come from the Netscape cookies.txt the plugin
already imports; they are never logged.

`featured_track*` fields in the feed are never read anywhere in the backend:
substituting a featured/first track for an album's real tracklist is a v1 bug
this rewrite must not reproduce.
"""
import html
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
FEED_URL = "https://bandcamp.com/api/fancollection/1/collection_items"
SETTINGS_URL = "https://bandcamp.com/settings"


def _host(url):
    try:
        parsed = urllib.parse.urlsplit(str(url))
        host = (parsed.hostname or "").rstrip(".").lower()
    except ValueError:
        return None
    return host


def cookie_allowed(url):
    """True only for https URLs on bandcamp.com or a *.bandcamp.com host."""
    try:
        parsed = urllib.parse.urlsplit(str(url))
    except ValueError:
        return False
    host = (parsed.hostname or "").rstrip(".").lower()
    return (parsed.scheme == "https" and bool(host)
            and (host == "bandcamp.com" or host.endswith(".bandcamp.com")))


def safe_url(url):
    """Return scheme://host/path, dropping userinfo, query and fragment."""
    try:
        parsed = urllib.parse.urlsplit(str(url))
    except ValueError:
        return "<url>"
    host = _host(url)
    if not parsed.scheme or not host:
        return "<url>"
    try:
        port = f":{parsed.port}" if parsed.port else ""
    except ValueError:
        port = ""
    return f"{parsed.scheme}://{host}{port}{parsed.path}"


def scrub_urls(text):
    """Redact every URL embedded in free-form error text to its safe form."""
    def repl(match):
        return safe_url(match.group(0))
    return re.sub(r"https?://[^\s'\"<>]+", repl, str(text))


def load_cookie(path):
    """Netscape cookies.txt -> Cookie header string (or None)."""
    try:
        parts = []
        with open(path, encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                toks = line.split("\t")
                if len(toks) >= 7 and "bandcamp.com" in toks[0]:
                    parts.append(f"{toks[5]}={toks[6]}")
        return "; ".join(parts) or None
    except OSError:
        return None


def default_http(url, cookie=None, data=None, timeout=60):
    headers = {"User-Agent": UA, "Accept": "application/json, text/html"}
    body = None
    if data is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(data).encode()
    if cookie and cookie_allowed(url):
        headers["Cookie"] = cookie
    req = urllib.request.Request(url, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "ignore")
    except urllib.error.HTTPError as e:
        raise BandcampError(f"HTTP {e.code} for {safe_url(url)}") from None
    except (urllib.error.URLError, OSError) as e:
        raise BandcampError(f"network error for {safe_url(url)}: {scrub_urls(e)}") from None


class BandcampError(Exception):
    pass


def _attr_json(page, attr):
    m = re.search(rf'{attr}="([^"]+)"', page or "")
    if not m:
        return None
    try:
        return json.loads(html.unescape(m.group(1)))
    except ValueError:
        return None


def parse_tralbum(page):
    """Extract the data-tralbum object from an album/track page, or None."""
    return _attr_json(page, "data-tralbum")


def tralbum_summary(t):
    """The pre-order fields, as received, plus declared track count and tracks."""
    return {
        "bandcamp_id": str(t.get("id")) if t.get("id") is not None else None,
        "artist": t.get("artist"),
        "title": (t.get("current") or {}).get("title"),
        "album_is_preorder": t.get("album_is_preorder"),
        "is_preorder": t.get("is_preorder"),
        "album_release_date": t.get("album_release_date"),
        "is_purchased": t.get("is_purchased"),
        "trackinfo": t.get("trackinfo") or [],
    }


class Bandcamp:
    def __init__(self, cookie=None, http=default_http, pause=0.1):
        self.cookie = cookie
        self.user_url = None
        self.http = http
        self.pause = pause

    def _get(self, url):
        return self.http(url, self.cookie)

    def _post(self, url, data):
        return json.loads(self.http(url, self.cookie, data))

    def account_url(self):
        blob = _attr_json(self._get(SETTINGS_URL), "data-blob") or {}
        fan = (blob.get("identities") or {}).get("fan") or {}
        if not fan.get("url") and fan.get("username"):
            return f"https://bandcamp.com/{fan['username']}"
        return fan.get("url")

    def collection_feed(self, user_url=None):
        """All collection rows, de-duplicated by (tralbum_type, tralbum_id). Returns raw feed dicts."""
        user_url = user_url or self.account_url()
        if not user_url:
            raise BandcampError("not signed in to Bandcamp (no account found for the session cookie)")
        self.user_url = user_url
        blob = _attr_json(self._get(user_url), "data-blob")
        if not blob:
            raise BandcampError("collection page carried no data-blob")
        fan_id = (blob.get("fan_data") or {}).get("fan_id")
        cd = blob.get("collection_data") or {}
        rows = list(((blob.get("item_cache") or {}).get("collection") or {}).values())
        token = cd.get("last_token")
        while token and fan_id:
            d = self._post(FEED_URL, {"fan_id": fan_id, "older_than_token": token, "count": 100})
            if not d.get("items"):
                break
            rows += d["items"]
            token = d.get("last_token")
            if not d.get("more_available"):
                break
            time.sleep(self.pause)
        uniq = {}
        for v in rows:
            uniq.setdefault((v.get("tralbum_type"), str(v.get("tralbum_id") or v.get("item_id"))), v)
        return list(uniq.values())

    def album_page(self, url):
        """Fetch an album page and return its data-tralbum summary, or None if it has none (404 etc.)."""
        try:
            page = self._get(url)
        except BandcampError:
            return None
        t = parse_tralbum(page)
        return tralbum_summary(t) if t else None
