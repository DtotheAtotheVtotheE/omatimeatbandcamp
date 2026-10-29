"""Regression tests for the security-audit fixes (F1-F9, F12)."""

import io
import json
import logging
import os
import sqlite3
import stat
import sys
import tempfile
import unittest
import urllib.error
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

import cookies
import mpvctl
from backend import bandcamp as bc
from backend import subsonic
from backend.library import Library

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class CookieHostGate(unittest.TestCase):
    """F1: cookies only travel to https Bandcamp hosts."""

    def fetch(self, url):
        seen = {}

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return b"{}"

        def fake_urlopen(req, timeout=60):
            seen["req"] = req
            return Response()

        with mock.patch("backend.bandcamp.urllib.request.urlopen", fake_urlopen):
            bc.default_http(url, cookie="identity=<dummy>")
        return seen["req"].get_header("Cookie")

    def test_cookies_go_only_to_https_bandcamp_hosts(self):
        self.assertEqual(self.fetch("https://bandcamp.com/settings"), "identity=<dummy>")
        self.assertEqual(self.fetch("https://shamekfarrah.bandcamp.com/album/1"), "identity=<dummy>")
        self.assertIsNone(self.fetch("https://example.com/settings"))
        self.assertIsNone(self.fetch("https://bandcamp.com.evil.example/settings"))
        self.assertIsNone(self.fetch("http://bandcamp.com/settings"))
        self.assertIsNone(self.fetch("http://shamekfarrah.bandcamp.com/album/1"))
        self.assertIsNone(self.fetch("https://bandcamp.com@evil.example/settings"))

    def test_cookie_allowed_rejects_lookalikes_and_plain_http(self):
        self.assertTrue(bc.cookie_allowed("https://bandcamp.com/x"))
        self.assertTrue(bc.cookie_allowed("https://a.b.bandcamp.com/x"))
        self.assertFalse(bc.cookie_allowed("http://bandcamp.com/x"))
        self.assertFalse(bc.cookie_allowed("https://notbandcamp.com/x"))
        self.assertFalse(bc.cookie_allowed("https://bandcamp.com.evil.example/x"))


class ErrorUrlRedaction(unittest.TestCase):
    """F6: public URLs in error paths lose query, fragment and userinfo."""

    def test_http_error_message_keeps_only_scheme_host_path(self):
        url = "https://user:pw@bandcamp.com/album/x?secret=1#frag"
        err = urllib.error.HTTPError(url, 500, "boom", None, None)
        try:
            with mock.patch("backend.bandcamp.urllib.request.urlopen", side_effect=err):
                with self.assertRaises(bc.BandcampError) as cm:
                    bc.default_http(url)
        finally:
            err.close()
        text = str(cm.exception)
        self.assertIn("https://bandcamp.com/album/x", text)
        self.assertNotIn("secret=1", text)
        self.assertNotIn("frag", text)
        self.assertNotIn("user:pw", text)

    def test_safe_url_and_scrub_urls_drop_query_and_userinfo(self):
        self.assertEqual(bc.safe_url("https://u:p@bandcamp.com/a/b?q=1#f"),
                         "https://bandcamp.com/a/b")
        self.assertEqual(bc.scrub_urls("x https://u:p@bandcamp.com/a?q=1 y"),
                         "x https://bandcamp.com/a y")


class CookieTempCopy(unittest.TestCase):
    """F2: browser databases are copied into the 0700 cache dir as 0600, then removed."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name) / "cache"
        self.patches = [mock.patch.object(cookies, "CACHE_DIR", self.cache)]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def test_copy_lives_in_private_cache_with_private_mode(self):
        source = Path(self.tmp.name) / "Cookies"
        source.write_bytes(b"browser-cookie-db")
        os.chmod(source, 0o644)
        copied = cookies.private_copy(source)
        try:
            self.assertEqual(Path(copied).parent, self.cache)
            self.assertEqual(stat.S_IMODE(os.stat(copied).st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(os.stat(self.cache).st_mode), 0o700)
            self.assertEqual(Path(copied).read_bytes(), b"browser-cookie-db")
        finally:
            os.unlink(copied)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_reader_unlinks_its_temp_copy_even_on_success(self):
        source = Path(self.tmp.name) / "cookies.sqlite"
        con = sqlite3.connect(source)
        con.execute("create table cookies (host_key text, name text, value text, "
                    "encrypted_value blob, path text, expires_utc integer, "
                    "is_secure integer, is_httponly integer)")
        con.execute("insert into cookies values ('bandcamp.com','identity','x',null,'/',0,1,1)")
        con.commit()
        con.close()
        rows = cookies.read_chromium_cookies(source, None)
        self.assertEqual([r["name"] for r in rows], ["identity"])
        self.assertEqual(list(self.cache.iterdir()), [])


class CredentialPermissions(unittest.TestCase):
    """F3: the credentials file and its plugin-owned directory are private."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "omatimeatbandcamp"
        self.dir.mkdir()
        os.chmod(self.dir, 0o755)
        self.path = self.dir / "credentials.toml"
        self.path.write_text('user = "test-user"\npass = "test-pass"\n', encoding="utf-8")
        os.chmod(self.path, 0o644)

    def tearDown(self):
        self.tmp.cleanup()

    def test_loose_file_and_directory_are_tightened(self):
        user, password = subsonic.load_credentials(str(self.path))
        self.assertEqual((user, password), ("test-user", "test-pass"))
        self.assertEqual(stat.S_IMODE(os.stat(self.dir).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600)

    def test_unfixable_mode_fails_with_the_chmod_command(self):
        with mock.patch("backend.subsonic.os.chmod", side_effect=PermissionError("denied")):
            with self.assertRaises(subsonic.CredentialsError) as cm:
                subsonic.load_credentials(str(self.path))
        message = str(cm.exception)
        self.assertIn("chmod 700", message)
        self.assertIn(str(self.dir), message)


class MpvLog(unittest.TestCase):
    """F5: the mpv log is private, under the cache dir, and never follows symlinks."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name) / "cache"
        self.patch = mock.patch.object(mpvctl, "CACHE_DIR", self.cache)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def test_log_is_created_0600_under_the_0700_cache_dir(self):
        f = mpvctl._open_log()
        try:
            f.write(b"log line\n")
        finally:
            f.close()
        path = self.cache / f"mpv-{mpvctl.UID}.log"
        self.assertTrue(path.exists())
        self.assertEqual(path.parent, self.cache)
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(self.cache).st_mode), 0o700)

    def test_log_open_refuses_a_symlink(self):
        self.cache.mkdir(parents=True)
        victim = Path(self.tmp.name) / "victim"
        victim.write_text("do not touch", encoding="utf-8")
        os.symlink(victim, self.cache / f"mpv-{mpvctl.UID}.log")
        with self.assertRaises(OSError):
            mpvctl._open_log()
        self.assertEqual(victim.read_text(encoding="utf-8"), "do not touch")


class ArgvCredentialGuard(unittest.TestCase):
    """F8: mpvctl refuses credential-bearing URLs supplied in process argv."""

    SECRET_URL = "https://bandcamp.com/api/subsonic/rest/stream.view?u=SECRET-USER&t=SECRET-TOKEN&s=SECRET-SALT&id=t:1"

    def test_credential_shapes_are_detected(self):
        for url in (self.SECRET_URL,
                    "https://user:pw@example.com/x",
                    "file:///tmp/x?token=1",
                    "https://example.com/x?password=1"):
            self.assertTrue(mpvctl.url_has_credentials(url), url)
        for url in ("file:///tmp/tone.wav",
                    "https://example.com/album/x?sort=title",
                    "https://example.com/album/x"):
            self.assertFalse(mpvctl.url_has_credentials(url), url)

    def test_argv_load_refuses_before_do_load(self):
        out = io.StringIO()
        with mock.patch.object(sys, "argv", ["mpvctl.py", "load", self.SECRET_URL]), \
                mock.patch.object(mpvctl, "do_load") as do_load, redirect_stdout(out):
            code = mpvctl.main()
        self.assertEqual(code, 2)
        do_load.assert_not_called()
        text = out.getvalue()
        self.assertIn("refusing", text)
        for secret in ("SECRET-USER", "SECRET-TOKEN", "SECRET-SALT"):
            self.assertNotIn(secret, text)


class TracebackRedaction(unittest.TestCase):
    """F7: the log filter redacts formatted exception text, not just the message."""

    def test_credential_shaped_url_in_exception_is_redacted(self):
        from backend.__main__ import _Redact

        class FakeSub:
            def redact(self, s):
                return str(s).replace("SECRET-TOKEN", "<t>")

        with tempfile.TemporaryDirectory() as tmp:
            lib = Library(cache_dir=tmp, subsonic=FakeSub())
            stream = io.StringIO()
            handler = logging.StreamHandler(stream)
            handler.setFormatter(logging.Formatter("%(message)s"))
            handler.addFilter(_Redact(lib))
            logger = logging.getLogger("audit.traceback.test")
            logger.handlers = [handler]
            logger.propagate = False
            logger.setLevel(logging.INFO)
            try:
                raise RuntimeError("bad response from https://x/stream?t=SECRET-TOKEN")
            except RuntimeError:
                logger.exception("sync failed")
            logger.handlers = []
        text = stream.getvalue()
        self.assertIn("Traceback", text)
        self.assertIn("<t>", text)
        self.assertNotIn("SECRET-TOKEN", text)


class GitignoreBackups(unittest.TestCase):
    """F9: plain *.bak files are ignored as well as *.bak-*."""

    def test_gitignore_has_plain_bak(self):
        text = (Path(ROOT) / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("*.bak\n", text)


if __name__ == "__main__":
    unittest.main()
