#!/usr/bin/env python3
"""v3.5.4 bold cat SVG asset checks.

The settings mark now ships as a visioncortex VTracer SVG trace of
docs/cat-and-flute-reference.jpg. These tests read the SVG and CatMark.qml as
text (stdlib only) and prove the properties the QML renderer relies on:

* the shipped SVG is the reviewed bold VTracer output (3 filled paths, 508 x 346);
* every path uses fill="currentColor", so no colour is baked into the asset;
* CatMark.qml carries exactly the same path data and transforms, and binds the
  fill to the theme accent instead of a hard-coded colour;
* no raster cat asset survives.
"""
from __future__ import annotations

import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "assets" / "cat-flute.svg"
QML = ROOT / "CatMark.qml"
PANEL = ROOT / "Panel.qml"

PATH_RE = re.compile(
    r'<path\s+d="([^"]*)"\s+fill="([^"]*)"\s+'
    r'transform="translate\(([-0-9.]+),\s*([-0-9.]+)\)"\s*/>'
)


def read_svg() -> tuple[str, list[tuple[str, str, str, str]]]:
    text = SVG.read_text(encoding="utf-8")
    return text, PATH_RE.findall(text)


class CatSvgAssetTest(unittest.TestCase):
    def test_svg_is_the_shipped_vtracer_trace(self):
        self.assertTrue(SVG.is_file(), "assets/cat-flute.svg is missing")
        self.assertEqual(SVG.stat().st_size, 15203)
        text, paths = read_svg()
        self.assertIn("visioncortex VTracer", text)
        self.assertRegex(text, r'<svg[^>]*width="508"[^>]*height="346"')
        self.assertEqual(len(paths), 3)
        # The old raster asset must be gone, and nothing may still point at it.
        self.assertFalse((ROOT / "assets" / "cat-flute-mask.png").exists())
        for source in (QML, PANEL):
            self.assertNotIn("cat-flute-mask.png", source.read_text(encoding="utf-8"))

    def test_every_svg_path_is_current_color(self):
        text, paths = read_svg()
        self.assertEqual(len(paths), 3)
        self.assertTrue(all(fill == "currentColor" for _, fill, _, _ in paths))
        # Exactly one fill declaration per path and no baked hex/RGB colour.
        self.assertEqual(text.count('fill="'), 3)
        self.assertNotRegex(text, r'fill="(?:#|rgb)')
        self.assertNotIn("<image", text)
        self.assertNotIn("base64", text)

    def test_qml_path_data_matches_the_svg_and_is_fill_bound(self):
        _, paths = read_svg()
        qml = QML.read_text(encoding="utf-8")
        entries = re.findall(
            r"\{\s*d:\s*'([^']*)',\s*tx:\s*([-0-9.]+),\s*ty:\s*([-0-9.]+)\s*\}",
            qml,
        )
        self.assertEqual(len(entries), 3)
        svg_data = [(d, tx, ty) for d, _, tx, ty in paths]
        qml_data = [(d, tx, ty) for d, tx, ty in entries]
        self.assertEqual(qml_data, svg_data)
        # The fill is the theme token at the scene-graph level, not a colour
        # copied into the path data.
        self.assertIn("property color tintColor: Color.accent", qml)
        self.assertIn("readonly property color fillColor: tintColor", qml)
        self.assertIn("fillColor: root.tintColor", qml)
        self.assertNotRegex(qml, r"fillColor:\s*[\"']#")


if __name__ == "__main__":
    unittest.main()
