import unittest

from backend.match import match_albums
from backend.model import Album, Track, R_SUBSONIC


def web(title, artist, bid, kind="album", purchased=None, preorder=False):
    return Album(title=title, artist=artist, kind=kind, bandcamp_id=bid, purchased=purchased, is_preorder=preorder,
                 bandcamp_url=f"https://x/{bid}", sources=["bandcamp"])


def sub(title, artist, sid, count=1, created=None):
    return Album(title=title, artist=artist, subsonic_id=sid, declared_track_count=count, purchased=created, sources=["subsonic"])


def tracks(*titles):
    return [Track(title=t, streamable=True, streamable_reason=R_SUBSONIC) for t in titles]


class Match(unittest.TestCase):
    def test_entities_and_case_do_not_block_a_match(self):
        merged, rep = match_albums([web("La Dee La La", "Shamek Farrah &amp; Folks", "1")],
                                   [sub("la dee la la", "Shamek Farrah & Folks", "a:1", 4)])
        self.assertEqual(rep.matched_by_key, 1)
        a = merged[0]
        self.assertEqual((a.subsonic_id, a.bandcamp_id, a.declared_track_count, a.sources), ("a:1", "1", 4, ["bandcamp", "subsonic"]))
        self.assertEqual(a.artist, "Shamek Farrah & Folks")

    def test_duplicate_keys_are_paired_by_purchase_time_not_order(self):
        w1 = web("Kuiper Belt", "Frog Myst", "w-old", purchased="01 Jan 2020 00:00:00 GMT")
        w2 = web("Kuiper Belt", "Frog Myst", "w-new", purchased="01 Jan 2025 00:00:00 GMT")
        s_new = sub("Kuiper Belt", "Frog Myst", "a:new", created="01 Jan 2025 00:00:01 GMT")
        s_old = sub("Kuiper Belt", "Frog Myst", "a:old", created="01 Jan 2020 00:00:01 GMT")
        merged, rep = match_albums([w1, w2], [s_new, s_old])
        pairs = {a.bandcamp_id: a.subsonic_id for a in merged}
        self.assertEqual(pairs, {"w-old": "a:old", "w-new": "a:new"})
        self.assertEqual((rep.matched_by_key, rep.duplicate_keys_paired, len(merged)), (2, 2, 2))

    def test_preorder_is_web_only_and_flagged(self):
        merged, rep = match_albums([web("First Impressions (Deluxe Edition)", "Shamek Farrah", "9", preorder=True)], [])
        self.assertEqual(len(rep.web_only), 1)
        self.assertTrue(rep.web_only[0]["is_preorder"])
        self.assertEqual(merged[0].sources, ["bandcamp"])

    def test_subsonic_only_albums_are_kept(self):
        merged, rep = match_albums([], [sub("HOSTILE", "Macroblank", "a:5", 10)])
        self.assertEqual((len(merged), len(rep.subsonic_only)), (1, 1))

    def test_single_track_matched_to_parent_album_by_track_title(self):
        w = [web("Red Sound", "Yosi Horikawa & Dorian Concept", "t1", kind="single"),
             web("Yosi Horikawa live (part 1)", "WSK.FM", "t2", kind="single"),
             web("Yosi Horikawa live (part 2)", "WSK.FM", "t3", kind="single")]
        s = [sub("Various Assets", "Red Bull Music Academy", "a:rb"), sub("WSK 2014", "WSK.FM", "a:wsk", 2)]
        lookup = {"a:rb": tracks("Red Sound"), "a:wsk": tracks("Yosi Horikawa live (part 1)", "Yosi Horikawa live (part 2)")}
        merged, rep = match_albums(w, s, lambda sid: lookup[sid])
        self.assertEqual((rep.single_items_matched_by_track, rep.single_parent_albums, len(merged)), (3, 2, 2))
        wsk = next(a for a in merged if a.subsonic_id == "a:wsk")
        self.assertEqual((wsk.kind, sorted(wsk.web_item_ids)), ("single", ["t2", "t3"]))
        self.assertEqual(rep.unresolved_singles, [])

    def test_unresolved_single_is_kept_and_reported_not_dropped(self):
        merged, rep = match_albums([web("Lost Song", "Nobody", "t9", kind="single")], [sub("Other", "X", "a:1")], lambda sid: tracks("Other"))
        self.assertEqual(len(rep.unresolved_singles), 1)
        self.assertIn("t9", [a.bandcamp_id for a in merged])
        self.assertEqual(len(merged), 2)

    def test_album_match_consumes_before_single_stage(self):
        w = [web("Solo", "A", "w1"), web("Solo", "A", "t1", kind="single")]
        s = [sub("Solo", "A", "a:1")]
        merged, rep = match_albums(w, s, lambda sid: tracks("Solo"))
        self.assertEqual(rep.matched_by_key, 1)
        self.assertEqual(len(rep.unresolved_singles), 1)  # the single had no unmatched parent left

    def test_report_arithmetic_and_summary(self):
        w = [web("A", "x", "1"), web("B", "x", "2", preorder=True), web("S", "y", "t1", kind="single")]
        s = [sub("A", "x", "a:1"), sub("Parent", "y", "a:2"), sub("Extra", "z", "a:3")]
        merged, rep = match_albums(w, s, lambda sid: tracks("S") if sid == "a:2" else tracks("q"))
        self.assertEqual(rep.web_items_matched, 2)
        self.assertEqual(len(merged), rep.merged_albums)
        self.assertEqual(rep.merged_albums, 1 + 1 + 1 + 1)  # A, parent(S), web-only B, Subsonic-only Extra
        self.assertIn("2/3", rep.summary())


if __name__ == "__main__":
    unittest.main()
