"""Minimal Subsonic/OpenSubsonic client for the Bandcamp endpoint.

URL shape:  https://bandcamp.com/api/subsonic/rest/<method>.view?f=json&u=..&t=..&s=..&v=..&c=..
Auth:       token auth, t = md5(password + salt), fresh random salt per request.
Credentials are read from ~/.config/omatimeatbandcamp/credentials.toml and the
u/t/s values are never printed or logged.
"""
import hashlib
import os
import secrets
import time
import tomllib
from urllib.parse import urlencode

import requests

BASE_URL = "https://bandcamp.com/api/subsonic"
API_VERSION = "1.16.1"
CLIENT_NAME = "OmaTimeAtBandcamp-spike"
CRED_PATH = os.path.expanduser("~/.config/omatimeatbandcamp/credentials.toml")
SECRET_KEYS = ("u", "t", "s", "p")


def load_credentials():
    with open(CRED_PATH, "rb") as f:
        cfg = tomllib.load(f)
    return cfg["user"], cfg["pass"]


def build_params(user, password, extra=None):
    salt = secrets.token_hex(8)
    token = hashlib.md5((password + salt).encode()).hexdigest()
    params = {"u": user, "t": token, "s": salt, "v": API_VERSION,
              "c": CLIENT_NAME, "f": "json"}
    if extra:
        params.update(extra)
    return params


def build_url(method, params):
    """Method goes in the PATH; f=json is just a query parameter."""
    return f"{BASE_URL}/rest/{method}.view?{urlencode(params, doseq=True)}"


def redact(text, params):
    for k in SECRET_KEYS:
        v = params.get(k)
        if v:
            text = text.replace(str(v), f"<{k}>")
    return text


class Client:
    def __init__(self):
        self.user, self.password = load_credentials()
        self.session = requests.Session()

    def url(self, method, **extra):
        return build_url(method, build_params(self.user, self.password, extra))

    def call(self, method, timeout=60, **extra):
        """Returns (parsed_json_or_None, elapsed_seconds, http_status, error_str)."""
        params = build_params(self.user, self.password, extra)
        t0 = time.perf_counter()
        try:
            r = self.session.get(f"{BASE_URL}/rest/{method}.view", params=params, timeout=timeout)
            dt = time.perf_counter() - t0
            try:
                body = r.json()
            except ValueError:
                return None, dt, r.status_code, redact(f"non-JSON body: {r.text[:200]!r}", params)
            return body, dt, r.status_code, None
        except requests.RequestException as e:
            return None, time.perf_counter() - t0, None, redact(str(e), params)

    def raw(self, method, timeout=60, **extra):
        """For binary endpoints (getCoverArt/stream): returns the Response, stream=True."""
        params = build_params(self.user, self.password, extra)
        params.pop("f", None)
        return self.session.get(f"{BASE_URL}/rest/{method}.view", params=params,
                                timeout=timeout, stream=True)
