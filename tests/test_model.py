import os
import unittest

from backend import bandcamp as bc
from backend.model import (Album, Playlist, Track, album_from_feed_item, album_from_subsonic_list_entry,
                           track_from_subsonic, track_from_tralbum, tracks_from_subsonic_album,
                           C_COMPLETE, C_EMPTY, C_PARTIAL, C_UNLOADED, R_NO_FILE, R_PAGE_FILE, R_SUBSONIC, R_UNRELEASED,
                           R_DISABLED)

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "first_impressions_page.html")


def fixture_page():
    with open(FIXTURE, encoding="utf-8") as f:
        return f.read()


def trk(n, title="t", **kw):
    return Track(title=title, track_number=n, streamable=True, streamable_reason=R_SUBSONIC, **kw)


class Honesty(unittest.TestCase):
    def test_entities_decoded_in_album_track_playlist(self):
        a = Album(title="Rock &amp; Roll", artist="Shamek Farrah &amp; Folks")
        self.assertEqual((a.title, a.artist), ("Rock & Roll", "Shamek Farrah & Folks"))
        self.assertEqual(Track(title="A &amp; B", artist="X &amp; Y", album="Z &#39;n&#39; Z").album, "Z 'n' Z")
        self.assertEqual(Playlist(id="pl:1", name="Q &amp; A").name, "Q & A")

    def test_streamable_is_always_an_explicit_bool(self):
        self.assertIs(Track(title="x").streamable, False)
        self.assertIs(Track(title="x", streamable=1).streamable, True)
        self.assertIsInstance(track_from_subsonic({"id": "t:1", "title": "x"}).streamable, bool)

    def test_unloaded_album_claims_nothing(self):
        a = Album(title="A", artist="B", declared_track_count=5)
        self.assertEqual(a.completeness, C_UNLOADED)
        self.assertEqual(a.missing_track_count, 0)
        self.assertEqual(a.tracks, [])

    def test_empty_album_stays_empty_never_padded(self):
        a = Album(title="TERMINALS", artist="x", declared_track_count=0)
        a.set_tracks([], "subsonic")
        self.assertEqual((a.completeness, a.returned_track_count, a.tracks), (C_EMPTY, 0, []))

    def test_empty_album_with_featured_track_in_feed_is_not_substituted(self):
        a = album_from_feed_item({"item_title": "T", "band_name": "B", "tralbum_type": "a", "tralbum_id": 1,
                                  "featured_track": 123, "featured_track_title": "The Hit",
                                  "featured_track_url": "https://x/track/the-hit", "num_streamable_tracks": 0})
        self.assertEqual(a.tracks, [])
        a.set_tracks([], "bandcamp-page")
        self.assertEqual(a.tracks, [])
        self.assertNotIn("featured", repr(a.to_dict()).lower())

    def test_partial_album_reports_gap_and_keeps_only_real_tracks(self):
        a = Album(title="The First 100 Songs", artist="x", declared_track_count=100)
        a.set_tracks([trk(i) for i in range(1, 96)], "subsonic")
        self.assertEqual(a.completeness, C_PARTIAL)
        self.assertEqual((a.returned_track_count, a.missing_track_count), (95, 5))
        self.assertEqual(len(a.tracks), 95)

    def test_complete_album(self):
        a = Album(title="x", artist="y", declared_track_count=2)
        a.set_tracks([trk(2), trk(1)], "subsonic")
        self.assertEqual(a.completeness, C_COMPLETE)
        self.assertEqual([t.track_number for t in a.tracks], [1, 2])

    def test_roundtrip_through_dict_preserves_everything(self):
        a = Album(title="x", artist="y", declared_track_count=3, is_preorder=True, release_date="27 Nov 2026 00:00:00 GMT",
                  album_is_preorder=True, web_item_ids=["1", "2"])
        a.set_tracks([trk(1), Track(title="u", track_number=2, streamable=False, streamable_reason=R_UNRELEASED)], "bandcamp-page")
        b = Album.from_dict(a.to_dict())
        self.assertEqual(b.to_dict(), a.to_dict())
        self.assertEqual((b.completeness, b.missing_track_count, b.streamable_track_count), (C_PARTIAL, 1, 1))

    def test_subsonic_builders(self):
        al = album_from_subsonic_list_entry({"id": "a:1", "name": "N &amp; M", "artist": "A", "songCount": 4, "coverArt": "ca:1"})
        self.assertEqual((al.title, al.declared_track_count, al.sources), ("N & M", 4, ["subsonic"]))
        tr = tracks_from_subsonic_album({"name": "N", "song": [{"id": "t:1", "title": "x", "track": 1, "duration": 10, "albumId": "a:1"}]})
        self.assertEqual((tr[0].streamable, tr[0].streamable_reason, tr[0].subsonic_album_id), (True, R_SUBSONIC, "a:1"))


class Tralbum(unittest.TestCase):
    def test_preorder_fields_from_real_fixture(self):
        t = bc.parse_tralbum(fixture_page())
        s = bc.tralbum_summary(t)
        self.assertIs(s["album_is_preorder"], True)
        self.assertIs(s["is_preorder"], True)
        self.assertEqual(s["album_release_date"], "27 Nov 2026 00:00:00 GMT")
        self.assertEqual(len(s["trackinfo"]), 7)

    def test_fixture_tracks_unreleased_not_streamable(self):
        s = bc.tralbum_summary(bc.parse_tralbum(fixture_page()))
        tracks = [track_from_tralbum(t, "First Impressions (Deluxe Edition)", "Shamek Farrah", True) for t in s["trackinfo"]]
        self.assertEqual(len(tracks), 7)
        self.assertTrue(all(t.streamable is False and t.streamable_reason == R_UNRELEASED for t in tracks))

    def test_per_track_flag_reflects_each_track_not_the_album(self):
        base = {"title": "t", "track_num": 1, "track_id": 9}
        self.assertEqual(track_from_tralbum({**base, "file": {"mp3-128": "https://x"}, "streaming": 1}, "A", "B", False).streamable_reason, R_PAGE_FILE)
        self.assertTrue(track_from_tralbum({**base, "file": {"mp3-128": "https://x"}, "streaming": 1}, "A", "B", False).streamable)
        self.assertEqual(track_from_tralbum({**base, "file": None, "streaming": 1}, "A", "B", False).streamable_reason, R_NO_FILE)
        self.assertEqual(track_from_tralbum({**base, "file": {"mp3-128": "https://x"}, "streaming": 0}, "A", "B", False).streamable_reason, R_DISABLED)
        mixed = [track_from_tralbum({**base, "track_num": 1, "file": {"mp3-128": "https://x"}, "streaming": 1}, "A", "B", True),
                 track_from_tralbum({**base, "track_num": 2, "unreleased_track": True, "file": None, "streaming": 1}, "A", "B", True)]
        self.assertEqual([t.streamable for t in mixed], [True, False])

    def test_missing_tralbum_is_none_not_a_crash(self):
        self.assertIsNone(bc.parse_tralbum("<html>no data here</html>"))
        self.assertIsNone(bc.parse_tralbum(None))


if __name__ == "__main__":
    unittest.main()
