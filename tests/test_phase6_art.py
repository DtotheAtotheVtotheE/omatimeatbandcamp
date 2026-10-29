"""Phase 6: bar art file — fetch/placeholder/downscale, no URL output."""
import contextlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import urllib.error

from backend import art
from backend.__main__ import main as cli_main

HAVE_IM = bool(shutil.which("convert") and shutil.which("identify"))


def dims(path):
    out = subprocess.check_output(["identify", "-format", "%w %h", path], text=True)
    w, h = out.split()
    return int(w), int(h)


def make_image(path, w, h, colour):
    subprocess.check_call(["convert", "-size", f"{w}x{h}", "xc:" + colour, path],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


@unittest.skipUnless(HAVE_IM, "ImageMagick convert/identify not installed")
class ArtFileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="omatime-art-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_placeholder_is_a_valid_128px_jpeg(self):
        out = os.path.join(self.tmp, "current-art.jpg")
        art.write_placeholder(out)
        self.assertTrue(os.path.isfile(out))
        self.assertEqual(dims(out), (128, 128))
        self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)

    def test_from_file_downscales_but_never_enlarges(self):
        big = os.path.join(self.tmp, "big.jpg")
        small = os.path.join(self.tmp, "small.jpg")
        make_image(big, 400, 200, "#c33")
        make_image(small, 64, 32, "#3c3")
        out1 = os.path.join(self.tmp, "a.jpg")
        out2 = os.path.join(self.tmp, "b.jpg")
        art.write_from_file(big, out1)
        art.write_from_file(small, out2)
        self.assertEqual(dims(out1), (128, 64))
        self.assertEqual(dims(out2), (64, 32))

    def test_track_change_replaces_the_file(self):
        one = os.path.join(self.tmp, "one.jpg")
        two = os.path.join(self.tmp, "two.jpg")
        out = os.path.join(self.tmp, "current-art.jpg")
        make_image(one, 300, 120, "#c33")
        make_image(two, 90, 260, "#3c3")
        art.write_from_file(one, out)
        first = dims(out)
        with open(out, "rb") as f:
            first_bytes = f.read()
        art.write_from_file(two, out)
        second = dims(out)
        self.assertEqual(first, (128, 51))
        self.assertEqual(second, (44, 128))
        with open(out, "rb") as f:
            self.assertNotEqual(first_bytes, f.read())

    def test_fetch_cover_uses_bytes_and_never_echoes_the_url(self):
        class FakeClient:
            timeout = 5
            def cover_art_url(self, cover_id):
                return "file:///tmp/fake-cover-source"

        src = os.path.join(self.tmp, "cover.jpg")
        make_image(src, 300, 300, "#369")
        with open(src, "rb") as f:
            raw = f.read()

        class Resp:
            status = 200
            def __enter__(self): return self
            def __exit__(self, *a): return False
            def read(self): return raw

        old = art.urllib.request.urlopen
        art.urllib.request.urlopen = lambda req, timeout=None: Resp()
        try:
            out = os.path.join(self.tmp, "current-art.jpg")
            art.write_cover("cover-1", out, client=FakeClient())
            self.assertEqual(dims(out), (128, 128))
        finally:
            art.urllib.request.urlopen = old

    def test_fetch_failure_message_has_no_url_or_credentials(self):
        class FakeClient:
            timeout = 5
            def cover_art_url(self, cover_id):
                return "file:///tmp/fake-cover-source"

        def boom(req, timeout=None):
            raise urllib.error.HTTPError(req.full_url, 403, "no", {}, None)

        old = art.urllib.request.urlopen
        art.urllib.request.urlopen = boom
        try:
            with self.assertRaises(RuntimeError) as cm:
                art.write_cover("cover-1", os.path.join(self.tmp, "x.jpg"), client=FakeClient())
            msg = str(cm.exception)
            self.assertNotIn("fake-cover-source", msg)
            self.assertNotIn("SECRET", msg)
            self.assertNotIn("SALTSALT", msg)
        finally:
            art.urllib.request.urlopen = old

    def test_cli_prints_only_local_paths(self):
        src = os.path.join(self.tmp, "src.jpg")
        make_image(src, 200, 100, "#963")
        out = os.path.join(self.tmp, "current-art.jpg")

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli_main(["art", "--from-file", src, "--out", out])
        d = json.loads(buf.getvalue())
        self.assertEqual(rc, 0)
        self.assertTrue(d["ok"])
        self.assertEqual(d["path"], out)
        self.assertEqual(dims(out), (128, 64))

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli_main(["art", "--placeholder", "--out", out])
        d = json.loads(buf.getvalue())
        self.assertEqual(rc, 0)
        self.assertTrue(d["placeholder"])
        self.assertEqual(dims(out), (128, 128))
        self.assertNotIn("http", buf.getvalue().lower())


if __name__ == "__main__":
    unittest.main()
