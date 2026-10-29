"""Bar album art cache.

The bar's art widget only ever reads one small local JPEG:
`~/.cache/omatimeatbandcamp/current-art.jpg`. This module is the only code that
turns a cover id into that file. It fetches through the authenticated Subsonic
client (whose cover-art URL embeds credentials), downscales locally to at most
128 px, and writes the result atomically with mode 0600.

Bandcamp's `getCoverArt` ignores its `size` parameter (Phase 0), so the full-size
image always arrives here and ImageMagick does the downscale. No URL, token or
credential is printed by this module or by the `backend art` command.
"""
import os
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request

CACHE_DIR = os.path.expanduser("~/.cache/omatimeatbandcamp")
ART_NAME = "current-art.jpg"
MAX_PX = 128
PLACEHOLDER = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "current-art-placeholder.jpg",
)


def art_path(cache_dir=CACHE_DIR):
    return os.path.join(cache_dir, ART_NAME)


def _secure_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


def _install(src, dest):
    """Atomically move `src` to `dest`, then make it private."""
    _secure_dir(os.path.dirname(dest))
    os.replace(src, dest)
    try:
        os.chmod(dest, 0o600)
    except OSError:
        pass


def _downscale(src, dest, max_px=MAX_PX):
    """Downscale one image to fit inside max_px x max_px. Never enlarges."""
    _secure_dir(os.path.dirname(dest))
    fd, tmp = tempfile.mkstemp(prefix=".art-", suffix=".jpg", dir=os.path.dirname(dest))
    os.close(fd)
    try:
        # `>` means "only shrink", so a small image keeps its size.
        cmd = ["convert", src + "[0]", "-auto-orient",
               "-resize", f"{int(max_px)}x{int(max_px)}>", "-strip",
               "-quality", "88", tmp]
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if proc.returncode != 0 or not os.path.getsize(tmp):
            raise RuntimeError("image downscale failed")
        _install(tmp, dest)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return dest


def write_placeholder(dest, placeholder=PLACEHOLDER):
    """Copy the bundled BC placeholder to `dest` (used whenever nothing plays)."""
    _secure_dir(os.path.dirname(dest))
    fd, tmp = tempfile.mkstemp(prefix=".art-", suffix=".jpg", dir=os.path.dirname(dest))
    os.close(fd)
    try:
        shutil.copyfile(placeholder, tmp)
        _install(tmp, dest)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return dest


def write_from_file(src, dest, max_px=MAX_PX):
    """Import a local image (used by the QML harness and offline imports)."""
    return _downscale(src, dest, max_px)


def write_cover(cover_id, dest, client=None, max_px=MAX_PX):
    """Fetch one cover through Subsonic, downscale it, and write it to `dest`.

    The URL is deliberately local to this function: it embeds the Subsonic
    token/salt, so it is never returned, logged or included in an exception.
    """
    if client is None:
        from .subsonic import Client
        client = Client()
    url = client.cover_art_url(cover_id)
    _secure_dir(os.path.dirname(dest))
    fd, raw = tempfile.mkstemp(prefix=".art-raw-", suffix=".img", dir=os.path.dirname(dest))
    os.close(fd)
    try:
        req = urllib.request.Request(url, headers={"Accept": "image/*"})
        try:
            with urllib.request.urlopen(req, timeout=getattr(client, "timeout", 60)) as r:
                data = r.read()
                status = getattr(r, "status", 200)
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"cover art fetch failed: HTTP {e.code}") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise RuntimeError("cover art fetch failed: network error") from None
        if status != 200 or not data:
            raise RuntimeError("cover art fetch failed: empty response")
        with open(raw, "wb") as f:
            f.write(data)
        return _downscale(raw, dest, max_px)
    finally:
        try:
            os.unlink(raw)
        except OSError:
            pass
