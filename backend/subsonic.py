"""Client for Bandcamp's Subsonic/OpenSubsonic endpoint.

URL shape:  https://bandcamp.com/api/subsonic/rest/<method>.view?f=json&u=..&t=..&s=..&v=..&c=..
Auth:       token auth, t = md5(password + salt). One fresh random salt per Client
            (= per session); build a new Client to rotate it.

Secrets: u/t/s never appear in repr(), exceptions, or log lines produced here.
`stream_url()` / `cover_art_url()` return URLs that DO embed them (mpv needs
that); treat those strings as secrets and pass them through `Client.redact()`
before logging. Never persist them.

Errors: the server answers failures as XML even when f=json is sent, and as JSON
at other times; both are parsed into SubsonicError.
"""
import hashlib
import json
import os
import secrets
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

BASE_URL = "https://bandcamp.com/api/subsonic"
API_VERSION = "1.16.1"
CLIENT_NAME = "OmaTimeAtBandcamp"
CRED_PATH = os.path.expanduser("~/.config/omatimeatbandcamp/credentials.toml")
DEFAULT_TIMEOUT = 60
PAGE_SIZE = 500
SECRET_PARAMS = ("u", "t", "s")


class SubsonicError(Exception):
    """API-level or transport-level failure. Message is safe to log."""

    def __init__(self, message, method=None, code=None, http_status=None):
        super().__init__(message)
        self.method = method
        self.code = code
        self.http_status = http_status


class CredentialsError(SubsonicError):
    pass


def load_credentials(path=CRED_PATH):
    try:
        with open(path, "rb") as f:
            cfg = tomllib.load(f)
        return str(cfg["user"]), str(cfg["pass"])
    except FileNotFoundError:
        raise CredentialsError(f"credentials file not found: {path}") from None
    except (KeyError, tomllib.TOMLDecodeError):
        raise CredentialsError(f"credentials file {path} must contain `user` and `pass`") from None


def parse_response(raw, method=None, http_status=None):
    """Return the `subsonic-response` dict for an OK reply; raise SubsonicError otherwise.

    Accepts JSON ({"subsonic-response": {...}}) and XML (<subsonic-response .../>).
    """
    text = raw.decode("utf-8", "replace") if isinstance(raw, (bytes, bytearray)) else str(raw)
    stripped = text.lstrip()
    if stripped.startswith("<"):
        try:
            root = ET.fromstring(stripped)
        except ET.ParseError:
            raise SubsonicError("unparseable XML response", method, http_status=http_status) from None
        status = root.get("status")
        err = next((e for e in root if e.tag.split("}")[-1] == "error"), None)
        if status == "ok" and err is None:
            # Not expected with f=json; only the envelope is available in this form.
            return {"status": "ok", "version": root.get("version"), "_xml": True}
        code = int(err.get("code")) if err is not None and (err.get("code") or "").isdigit() else None
        msg = err.get("message") if err is not None else "failed without error element"
        raise SubsonicError(f"{method or 'request'}: {msg} (code {code})", method, code, http_status)
    try:
        resp = json.loads(stripped)["subsonic-response"]
    except (ValueError, KeyError, TypeError):
        raise SubsonicError("response is neither Subsonic JSON nor XML", method, http_status=http_status) from None
    if resp.get("status") != "ok":
        err = resp.get("error") or {}
        code = err.get("code")
        raise SubsonicError(f"{method or 'request'}: {err.get('message', 'failed')} (code {code})",
                            method, code, http_status)
    return resp


class Client:
    def __init__(self, user=None, password=None, timeout=DEFAULT_TIMEOUT, base_url=BASE_URL):
        if user is None or password is None:
            user, password = load_credentials()
        self._user = user
        self._salt = secrets.token_hex(8)
        self._token = hashlib.md5((password + self._salt).encode()).hexdigest()
        self.timeout = timeout
        self.base_url = base_url
        self.request_count = 0

    def __repr__(self):
        return f"<subsonic.Client {self.base_url}>"

    # -- secret handling -------------------------------------------------------
    def _auth_params(self):
        return {"u": self._user, "t": self._token, "s": self._salt, "v": API_VERSION, "c": CLIENT_NAME}

    def redact(self, text):
        """Replace u/t/s values in `text` with placeholders."""
        text = str(text)
        auth = self._auth_params()
        for key in SECRET_PARAMS:
            if auth[key]:
                text = text.replace(auth[key], f"<{key}>")
        return text

    def secret_values(self):
        """Values that must never reach disk or logs (for write-time guards)."""
        a = self._auth_params()
        return [a["t"], a["s"]] + ([a["u"]] if len(a["u"]) >= 8 else [])

    def _url(self, method, params, as_json):
        q = self._auth_params()
        if as_json:
            q["f"] = "json"
        q.update({k: v for k, v in params.items() if v is not None})
        return f"{self.base_url}/rest/{method}.view?{urllib.parse.urlencode(q, doseq=True)}"

    # -- JSON calls --------------------------------------------------------------
    def call(self, method, **params):
        """Call an endpoint; returns the unwrapped `subsonic-response` dict."""
        url = self._url(method, params, as_json=True)
        self.request_count += 1
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                raw, status = r.read(), r.status
        except urllib.error.HTTPError as e:
            raw, status = e.read(), e.code
            try:
                return parse_response(raw, method, status)
            except SubsonicError as pe:
                if pe.code is not None:
                    raise
                hint = " (empty error body; the server does this for rejected credentials)" if status in (401, 403, 500) and not raw else ""
                raise SubsonicError(f"{method}: HTTP {status}{hint}", method, http_status=status) from None
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            raise SubsonicError(self.redact(f"{method}: network error: {e}"), method) from None
        return parse_response(raw, method, status)

    def timed_call(self, method, **params):
        t0 = time.perf_counter()
        resp = self.call(method, **params)
        return resp, time.perf_counter() - t0

    # -- convenience wrappers ----------------------------------------------------
    def ping(self):
        """Server info. NOTE: succeeds even with wrong credentials; use check_auth()."""
        return self.call("ping")

    def check_auth(self):
        """True if the credentials are accepted (cheap authenticated call)."""
        try:
            self.call("getAlbumList2", type="alphabeticalByName", size=1)
            return True
        except SubsonicError as e:
            if e.http_status in (401, 403, 500) or e.code in (40, 41, 44):
                return False
            raise

    def albums(self, page_size=PAGE_SIZE):
        """Every album (getAlbumList2, paged until a short page)."""
        out, offset = [], 0
        while True:
            resp = self.call("getAlbumList2", type="alphabeticalByName", size=page_size, offset=offset)
            page = (resp.get("albumList2") or {}).get("album") or []
            out += page
            if len(page) < page_size:
                return out
            offset += page_size

    def album(self, album_id):
        return self.call("getAlbum", id=album_id).get("album") or {}

    def playlists(self):
        return (self.call("getPlaylists").get("playlists") or {}).get("playlist") or []

    def playlist(self, playlist_id):
        return self.call("getPlaylist", id=playlist_id).get("playlist") or {}

    def search(self, query, count=100):
        return self.call("search3", query=query, albumCount=count, songCount=count,
                         artistCount=count).get("searchResult3") or {}

    # -- URLs that embed credentials ---------------------------------------------
    def stream_url(self, track_id):
        return self._url("stream", {"id": track_id}, as_json=False)

    def cover_art_url(self, cover_id, size=None):
        return self._url("getCoverArt", {"id": cover_id, "size": size}, as_json=False)
