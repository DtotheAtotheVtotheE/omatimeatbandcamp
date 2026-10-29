import io
import json
import urllib.error
import urllib.parse
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

from backend import subsonic
from backend.subsonic import Client, SubsonicError, parse_response

XML_ERR = ('<subsonic-response status="failed" version="1.16.1" type="BandcampServer" serverVersion="1.0" '
           'openSubsonic="true">\n  <error code="70" message="not found" />\n</subsonic-response>\n')
JSON_ERR = json.dumps({"subsonic-response": {"status": "failed", "version": "1.16.1",
                                              "error": {"code": 40, "message": "Wrong username or password"}}})
JSON_OK = json.dumps({"subsonic-response": {"status": "ok", "version": "1.16.1", "albumList2": {"album": []}}})


class FakeResp(io.BytesIO):
    def __init__(self, body, status=200):
        super().__init__(body.encode() if isinstance(body, str) else body)
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class Parse(unittest.TestCase):
    def test_json_ok(self):
        self.assertEqual(parse_response(JSON_OK)["status"], "ok")

    def test_json_error(self):
        with self.assertRaises(SubsonicError) as cm:
            parse_response(JSON_ERR, "getAlbum")
        self.assertEqual(cm.exception.code, 40)
        self.assertIn("Wrong username", str(cm.exception))

    def test_xml_error_even_though_json_was_requested(self):
        with self.assertRaises(SubsonicError) as cm:
            parse_response(XML_ERR, "stream", 200)
        self.assertEqual(cm.exception.code, 70)
        self.assertIn("not found", str(cm.exception))

    def test_garbage_is_a_clean_error(self):
        for raw in (b"", b"<html>", b"not json"):
            with self.assertRaises(SubsonicError):
                parse_response(raw, "x")


class ClientSecrets(unittest.TestCase):
    def setUp(self):
        self.c = Client("someaccountname", "hunter2-password")

    def test_url_shape_method_in_path_f_json_in_query(self):
        url = self.c._url("getAlbum", {"id": "a:1"}, as_json=True)
        p = urllib.parse.urlparse(url)
        self.assertEqual(p.path, "/api/subsonic/rest/getAlbum.view")
        q = urllib.parse.parse_qs(p.query)
        self.assertEqual(q["f"], ["json"])
        self.assertEqual(q["id"], ["a:1"])
        self.assertNotIn("/rest/json", url)

    def test_salt_is_fresh_per_client_and_stable_within_one(self):
        other = Client("someaccountname", "hunter2-password")
        self.assertNotEqual(self.c._salt, other._salt)
        self.assertEqual(self.c._auth_params()["s"], self.c._auth_params()["s"])
        import hashlib
        self.assertEqual(self.c._token, hashlib.md5(("hunter2-password" + self.c._salt).encode()).hexdigest())

    def test_repr_and_redact_hide_u_t_s_and_password_never_in_url(self):
        c = self.c
        self.assertNotIn("someaccountname", repr(c))
        red = c.redact(c.stream_url("t:9"))
        for v in (c._user, c._token, c._salt):
            self.assertNotIn(v, red)
        self.assertNotIn("hunter2-password", c.stream_url("t:9"))

    def test_network_error_message_is_redacted(self):
        c = self.c
        err = urllib.error.URLError(f"cannot reach {c.stream_url('t:1')}")
        with mock.patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(SubsonicError) as cm:
                c.call("getAlbum", id="a:1")
        for v in (c._user, c._token, c._salt):
            self.assertNotIn(v, str(cm.exception))

    def test_nothing_secret_printed_during_calls(self):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err), mock.patch(
                "urllib.request.urlopen", side_effect=[FakeResp(JSON_OK), FakeResp(XML_ERR)]):
            self.c.albums(page_size=500)
            with self.assertRaises(SubsonicError):
                self.c.call("getAlbum", id="a:1")
        for v in self.c.secret_values():
            self.assertNotIn(v, out.getvalue() + err.getvalue())

    def test_http_500_empty_body_means_rejected_credentials(self):
        e = urllib.error.HTTPError("u", 500, "err", {}, io.BytesIO(b""))
        self.addCleanup(e.close)
        with mock.patch("urllib.request.urlopen", side_effect=e):
            with self.assertRaises(SubsonicError) as cm:
                self.c.call("getPlaylists")
        self.assertEqual(cm.exception.http_status, 500)
        self.assertIn("credentials", str(cm.exception))

    def test_check_auth_false_on_rejection_true_on_ok(self):
        e = urllib.error.HTTPError("u", 500, "err", {}, io.BytesIO(b""))
        self.addCleanup(e.close)
        with mock.patch("urllib.request.urlopen", side_effect=e):
            self.assertFalse(self.c.check_auth())
        with mock.patch("urllib.request.urlopen", return_value=FakeResp(JSON_OK)):
            self.assertTrue(self.c.check_auth())

    def test_albums_pages_until_short_page(self):
        page1 = json.dumps({"subsonic-response": {"status": "ok", "albumList2": {"album": [{"id": f"a:{i}"} for i in range(3)]}}})
        page2 = json.dumps({"subsonic-response": {"status": "ok", "albumList2": {"album": [{"id": "a:9"}]}}})
        with mock.patch("urllib.request.urlopen", side_effect=[FakeResp(page1), FakeResp(page2)]) as m:
            got = self.c.albums(page_size=3)
        self.assertEqual([a["id"] for a in got], ["a:0", "a:1", "a:2", "a:9"])
        self.assertEqual(m.call_count, 2)


if __name__ == "__main__":
    unittest.main()
