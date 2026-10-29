import unittest

from backend.textnorm import album_key, clean, norm


class TextNorm(unittest.TestCase):
    def test_clean_decodes_entities_everywhere_even_double_encoded(self):
        self.assertEqual(clean("Shamek Farrah &amp; Folks"), "Shamek Farrah & Folks")
        self.assertEqual(clean("Rock &amp;amp; Roll"), "Rock & Roll")
        self.assertEqual(clean("it&#39;s &quot;fine&quot;"), 'it\'s "fine"')
        self.assertEqual(clean(None), "")

    def test_clean_collapses_whitespace_but_keeps_case_and_punctuation(self):
        self.assertEqual(clean("  La  Dee\tLa La! "), "La Dee La La!")

    def test_key_ignores_case_punctuation_accents_entities(self):
        self.assertEqual(album_key("Shamek Farrah &amp; Folks", "La Dee La La"),
                         album_key("shamek farrah and folks", "LA DEE LA LA!"))
        self.assertEqual(album_key("Björk", "Homogénic"), album_key("Bjork", "Homogenic"))

    def test_key_keeps_distinct_titles_distinct(self):
        self.assertNotEqual(album_key("A", "Vol. 1"), album_key("A", "Vol. 2"))

    def test_symbol_only_titles_do_not_collapse_to_empty(self):
        self.assertNotEqual(norm("???"), "")
        self.assertNotEqual(album_key("X", "???"), album_key("X", "!!!"))

    def test_non_latin_titles_survive(self):
        self.assertNotEqual(norm("погребённый заживо"), "")
        self.assertNotEqual(album_key("Macroblank", "保持"), album_key("Macroblank", "本能"))


if __name__ == "__main__":
    unittest.main()
