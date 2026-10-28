#!/usr/bin/env python3
"""v3.5.2 cat stencil asset checks.

The settings mark ships as a tintable PNG derived from
docs/cat-and-flute-reference.jpg. These tests read the PNG directly (stdlib
only) and prove the properties the QML renderer relies on:

* 8-bit RGBA with a fully transparent background;
* every visible pixel is pure white, so no colour is baked into the asset;
* a soft alpha ramp, not a hard threshold, so line edges keep the reference's
  antialiased coverage;
* a tight crop that still includes the full drawing on all four edges.
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / "assets" / "cat-flute-mask.png"


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_rgba_png(path: Path) -> tuple[int, int, bytearray]:
    """Decode a non-interlaced 8-bit RGBA PNG without third-party modules."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos = 8
    width = height = depth = colour = interlace = None
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
    assert width is not None and height is not None
    assert depth == 8 and colour == 6 and interlace == 0, "expected 8-bit RGBA, non-interlaced"

    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    rows: list[bytearray] = []
    prev = bytearray(stride)
    rp = 0
    for _ in range(height):
        filt = raw[rp]
        rp += 1
        row = bytearray(raw[rp:rp + stride])
        rp += stride
        if filt == 1:
            for i in range(4, stride):
                row[i] = (row[i] + row[i - 4]) & 0xFF
        elif filt == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xFF
        elif filt == 3:
            for i in range(stride):
                left = row[i - 4] if i >= 4 else 0
                row[i] = (row[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filt == 4:
            for i in range(stride):
                left = row[i - 4] if i >= 4 else 0
                up_left = prev[i - 4] if i >= 4 else 0
                row[i] = (row[i] + _paeth(left, prev[i], up_left)) & 0xFF
        elif filt != 0:
            raise AssertionError(f"unsupported PNG filter {filt}")
        rows.append(row)
        prev = row

    return width, height, bytearray().join(rows)


class CatMaskAssetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.width, cls.height, cls.pixels = read_rgba_png(ASSET)

    def test_mask_is_white_ink_on_a_transparent_background(self):
        w, h, px = self.width, self.height, self.pixels
        self.assertEqual((w, h), (509, 346))
        alphas = [px[i] for i in range(3, len(px), 4)]
        self.assertIn(0, alphas)
        self.assertIn(255, alphas)
        visible = 0
        for i in range(0, len(px), 4):
            if px[i + 3] == 0:
                continue
            visible += 1
            self.assertEqual((px[i], px[i + 1], px[i + 2]), (255, 255, 255))
        self.assertGreater(visible, 1000)
        # Fully transparent corners, i.e. no background card/box survived the crop.
        for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            self.assertEqual(px[(y * w + x) * 4 + 3], 0)

    def test_mask_has_a_soft_ramp_and_a_tight_full_drawing_crop(self):
        w, h, px = self.width, self.height, self.pixels
        partial = 0
        xs: list[int] = []
        ys: list[int] = []
        for y in range(h):
            for x in range(w):
                a = px[(y * w + x) * 4 + 3]
                if 0 < a < 255:
                    partial += 1
                if a > 0:
                    xs.append(x)
                    ys.append(y)
        # A hard threshold would have only 0/255; this keeps the JPEG's
        # antialiased line edges as partial alpha.
        self.assertGreater(partial, 500)
        self.assertLess(partial, w * h // 2)
        # Tight to the ink: the visible drawing reaches every crop edge.
        self.assertEqual((min(xs), max(xs), min(ys), max(ys)), (0, w - 1, 0, h - 1))
        self.assertAlmostEqual(w / h, 509 / 346, delta=0.01)


if __name__ == "__main__":
    unittest.main()
