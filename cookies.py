#!/usr/bin/env python3
"""Export Bandcamp login cookies from the user's own browser.

The Bandcamp collection/playlist APIs only return private items when the
request carries the logged-in `identity` cookie. Rather than asking the user to
export cookies by hand, this reads them straight out of the browser they are
already signed in to and writes a Netscape cookies.txt that the backend and
mpvctl.py already understand.

Usage:
  cookies.py [outputPath] [browser]

  outputPath  default: ~/.cache/omatimeatbandcamp/cookies.txt
  browser     auto (default) | chrome | chromium | brave | edge | vivaldi | firefox

Prints a single JSON object describing what happened.
"""

import base64
import glob
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
except Exception:  # pragma: no cover - cryptography is a hard dep on Omarchy
    Cipher = None

BANDCAMP = "bandcamp.com"
CHROMIUM_IV = b" " * 16
CHROMIUM_SALT = b"saltysalt"
# Chromium >= ~130 prepends a 32-byte host-bound digest to the cleartext before
# AES-128-CBC ("v11"), so the real value starts after it.
HOST_BOUND_PREFIX = 32

HOME = Path.home()
CACHE_DIR = HOME / ".cache" / "omatimeatbandcamp"
DEFAULT_OUT = CACHE_DIR / "cookies.txt"

# keyring label -> config dirs
CHROMIUM_BROWSERS = {
    "chrome": ("Chrome Safe Storage", ["~/.config/google-chrome"]),
    "chromium": ("Chromium Safe Storage", ["~/.config/chromium"]),
    "brave": ("Brave Safe Storage", ["~/.config/BraveSoftware/Brave-Browser"]),
    "edge": ("Microsoft Edge Safe Storage", ["~/.config/microsoft-edge"]),
    "vivaldi": ("Vivaldi Safe Storage", ["~/.config/vivaldi"]),
}

FIREFOX_DIRS = [
    "~/.mozilla/firefox",
    "~/.var/app/org.mozilla.firefox/.mozilla/firefox",
    "~/snap/firefox/common/.mozilla/firefox",
]


def expand(p):
    return Path(os.path.expanduser(p))


def private_copy(path):
    """Copy a locked sqlite db into the private cache dir so we can read it."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(CACHE_DIR, 0o700)
    except OSError:
        pass
    fd, tmp = tempfile.mkstemp(prefix="cookies-", suffix=".sqlite", dir=str(CACHE_DIR))
    try:
        os.fchmod(fd, 0o600)
        os.close(fd)
        # copyfile, not copy2: do not inherit a looser mode from the browser db.
        shutil.copyfile(path, tmp)
        os.chmod(tmp, 0o600)
        return tmp
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def keyring_secret(label):
    try:
        import secretstorage
    except Exception:
        return None
    try:
        bus = secretstorage.dbus_init()
        for coll in secretstorage.get_all_collections(bus):
            try:
                if coll.is_locked():
                    continue
                for item in coll.get_all_items():
                    if item.get_label() == label:
                        return item.get_secret()
            except Exception:
                continue
    except Exception:
        return None
    return None


def derive_key(password):
    return hashlib.pbkdf2_hmac("sha1", password, CHROMIUM_SALT, 1, 16)


def decrypt_value(enc, key):
    """Decrypt one Chromium encrypted_value blob. Returns str or None."""
    if Cipher is None or not enc:
        return None
    prefix = enc[:3]
    body = enc[3:]
    if prefix not in (b"v10", b"v11"):
        # Unencrypted or unknown: assume utf-8.
        try:
            return enc.decode("utf-8")
        except Exception:
            return None
    try:
        dec = Cipher(algorithms.AES(key), modes.CBC(CHROMIUM_IV)).decryptor()
        raw = dec.update(body) + dec.finalize()
    except Exception:
        return None
    if prefix == b"v11" and len(raw) > HOST_BOUND_PREFIX:
        raw = raw[HOST_BOUND_PREFIX:]
    # Strip PKCS#7 padding.
    if raw:
        pad = raw[-1]
        if 1 <= pad <= 16 and len(raw) >= pad:
            raw = raw[:-pad]
    try:
        return raw.decode("utf-8")
    except Exception:
        return None


def chromium_profiles(base):
    base = expand(base)
    if not base.is_dir():
        return []
    profiles = []
    for name in ["Default"] + [f"Profile {i}" for i in range(1, 20)]:
        cookies = base / name / "Cookies"
        if cookies.exists():
            profiles.append((name, cookies))
    # Anything else with a Cookies db (e.g. "Guest Profile").
    for cookies in base.glob("*/Cookies"):
        pair = (cookies.parent.name, cookies)
        if pair not in profiles:
            profiles.append(pair)
    return profiles


def read_chromium_cookies(cookies_path, key):
    out = []
    tmp = private_copy(cookies_path)
    try:
        con = sqlite3.connect(tmp)
        try:
            rows = con.execute(
                "select host_key, name, value, encrypted_value, path, "
                "expires_utc, is_secure, is_httponly from cookies"
            ).fetchall()
        finally:
            con.close()
    except Exception:
        return out
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    for host, name, value, enc, path, expires, secure, httponly in rows:
        if BANDCAMP not in (host or ""):
            continue
        if not value and enc:
            value = decrypt_value(enc, key)
        if value is None:
            continue
        out.append(
            {
                "domain": host,
                "name": name,
                "value": value,
                "path": path or "/",
                "expires": expires or 0,
                "secure": bool(secure),
                "httponly": bool(httponly),
            }
        )
    return out


def collect_chromium(name, label, dirs):
    key = keyring_secret(label)
    if not key:
        return None
    derived = derive_key(key)
    best = None
    for base in dirs:
        for profile, cookies in chromium_profiles(base):
            found = read_chromium_cookies(cookies, derived)
            if not found:
                continue
            candidate = {"browser": name, "profile": profile, "cookies": found}
            if best is None or len(found) > len(best["cookies"]):
                best = candidate
    return best


def collect_firefox():
    out = None
    for base in FIREFOX_DIRS:
        base = expand(base)
        if not base.is_dir():
            continue
        for db in glob.glob(str(base / "**" / "cookies.sqlite"), recursive=True):
            found = []
            tmp = private_copy(db)
            try:
                con = sqlite3.connect(tmp)
                try:
                    rows = con.execute(
                        "select host, name, value, path, expiry, isSecure, isHttpOnly "
                        "from moz_cookies"
                    ).fetchall()
                finally:
                    con.close()
            except Exception:
                rows = []
            finally:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
            for host, name, value, path, expiry, secure, httponly in rows:
                if BANDCAMP not in (host or ""):
                    continue
                found.append(
                    {
                        "domain": host,
                        "name": name,
                        "value": value or "",
                        "path": path or "/",
                        "expires": int((expiry or 0) * 1_000_000),
                        "secure": bool(secure),
                        "httponly": bool(httponly),
                    }
                )
            if found and (out is None or len(found) > len(out["cookies"])):
                out = {"browser": "firefox", "profile": Path(db).parent.parent.name, "cookies": found}
    return out


def chromium_expiry_to_unix(expires_utc):
    # Chromium stores microseconds since 1601-01-01.
    if not expires_utc:
        return 0
    return int(expires_utc / 1_000_000) - 11644473600


def write_netscape(path, cookies):
    lines = [
        "# Netscape HTTP Cookie File",
        "# Exported by OmaTimeAtBandcamp for the Bandcamp account.",
        "",
    ]
    for c in cookies:
        domain = c["domain"]
        include_sub = "TRUE" if domain.startswith(".") else "FALSE"
        secure = "TRUE" if c["secure"] else "FALSE"
        expiry = chromium_expiry_to_unix(c["expires"]) if c["expires"] else int(c["expires"])
        lines.append(
            "\t".join(
                [
                    domain,
                    include_sub,
                    c["path"],
                    secure,
                    str(expiry or 0),
                    c["name"],
                    c["value"],
                ]
            )
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path.parent, 0o700)
    except OSError:
        pass
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, path)


def score(result):
    if not result:
        return (-1, -1)
    names = {c["name"] for c in result["cookies"]}
    return (1 if "identity" in names else 0, len(result["cookies"]))


def main():
    args = sys.argv[1:]
    out_path = Path(args[0]).expanduser() if args else DEFAULT_OUT
    browser = args[1].lower() if len(args) > 1 else "auto"

    candidates = []
    if browser in ("auto", "firefox"):
        candidates.append(collect_firefox())
    if browser in ("auto", *CHROMIUM_BROWSERS.keys()):
        for name, (label, dirs) in CHROMIUM_BROWSERS.items():
            if browser not in ("auto", name):
                continue
            candidates.append(collect_chromium(name, label, dirs))

    candidates = [c for c in candidates if c]
    if not candidates:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "no browser cookies found; sign in to Bandcamp in your "
                    "browser or set a cookiePath manually",
                }
            )
        )
        return 1

    best = max(candidates, key=score)
    write_netscape(out_path, best["cookies"])
    names = {c["name"] for c in best["cookies"]}
    print(
        json.dumps(
            {
                "ok": True,
                "path": str(out_path),
                "browser": best["browser"],
                "profile": best["profile"],
                "count": len(best["cookies"]),
                "has_identity": "identity" in names,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
