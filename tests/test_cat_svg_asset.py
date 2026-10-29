#!/usr/bin/env python3
"""v3.5.4.1 slim cat SVG asset checks.

The settings mark now ships as a visioncortex VTracer 0.6.12 SVG trace of
docs/cat-and-flute-reference.jpg, using the slim/smoothed trace. These tests
read the SVG and CatMark.qml as text (stdlib only) and prove the properties the
QML renderer relies on:

* the shipped SVG is the reviewed slim VTracer output (3 filled paths, 508 x 345);
* every path uses fill="currentColor", so no colour is baked into the asset;
* CatMark.qml carries exactly the same path data and transforms, and binds the
  fill to the theme accent instead of a hard-coded colour;
* no raster cat asset survives.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "assets" / "cat-flute.svg"
SOURCE_SVG = ROOT / "docs" / "cat-flute-smooth.svg"
QML = ROOT / "CatMark.qml"
PANEL = ROOT / "Panel.qml"

ASSET_SHA256 = "aeaeed62a216dcac1e9c4d2fd883c3aa289de1492f7e189c4a16cd6e7d19a6cf"

# (d length, full d sha256, transform x, transform y) for each shipped path.
PATH_INVENTORY = [
    (18357, "1b85727bfea49c32a8075ab79d1c4ebde26009d8d17a74430fe6bd5e883b42fb",
     "34", "0"),
    (416, "d0b73e1444dc3411fef318638b5cae0c514f5529722759e0ab589e98f20eb5e2",
     "87.8125", "103.5625"),
    (409, "bdd4109181f3125f34d6d7f31a4e4d615e6a5df0a63dcba32e6ca85a5052d956",
     "172.8125", "103.5625"),
]

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
        raw = SVG.read_bytes()
        self.assertEqual(len(raw), 19564)
        self.assertEqual(hashlib.sha256(raw).hexdigest(), ASSET_SHA256)
        # The reviewed source and the shipped asset are byte-identical.
        self.assertEqual(raw, SOURCE_SVG.read_bytes())
        text, paths = read_svg()
        self.assertIn("visioncortex VTracer 0.6.12", text)
        self.assertRegex(text, r'<svg[^>]*width="508"[^>]*height="345"')
        self.assertEqual(len(paths), 3)
        for (d, _, tx, ty), (length, digest, want_tx, want_ty) in zip(paths, PATH_INVENTORY):
            self.assertEqual(len(d), length)
            self.assertEqual(hashlib.sha256(d.encode()).hexdigest(), digest)
            self.assertEqual(tx, want_tx)
            self.assertEqual(ty, want_ty)
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
