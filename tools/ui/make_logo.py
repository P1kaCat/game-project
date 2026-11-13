#!/usr/bin/env python3
"""Hand-built pixel-art logo "ASTHYA": angular capitals inspired by ancient
chiselled inscriptions (thick/thin strokes, small serifs), tarnished silver
with a brass highlight, 1 px ink outline. Above it, an incomplete circular
inscription (the same broken-ring motif as the protagonist's neck mark),
exported separately so the game can animate it.

usage: make_logo.py <repo_root>
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "assets/ui"
H = 24          # cap height in pixels (drawn 1:1, no scaling)
LW = 17         # letter width
GAP = 5

INK = (10, 10, 13, 255)
SIL_HI = (222, 224, 228, 255)
SIL = (168, 170, 176, 255)
SIL_LO = (104, 104, 112, 255)
BRASS = (196, 160, 92, 255)

# Letters as stroke lists on a LW x H grid: (x0, y0, x1, y1, width)
B = H - 1
LETTERS = {
    "A": [(1, B, 8, 0, 2), (8, 0, 15, B, 3), (5, 15, 12, 15, 1),
          (0, B, 3, B, 1), (13, B, 16, B, 1)],
    "S": [(14, 2, 12, 0, 2), (12, 0, 4, 0, 2), (4, 0, 1, 3, 2), (1, 3, 1, 8, 2),
          (1, 9, 14, 13, 3), (14, 14, 14, 19, 2), (14, 20, 11, B, 2), (11, B, 3, B, 2), (3, B, 1, 20, 2)],
    "T": [(0, 0, 16, 0, 2), (0, 0, 0, 3, 1), (16, 0, 16, 3, 1), (8, 0, 8, B, 3), (5, B, 11, B, 1)],
    "H": [(2, 0, 2, B, 3), (14, 0, 14, B, 3), (2, 11, 14, 11, 1),
          (0, 0, 4, 0, 1), (12, 0, 16, 0, 1), (0, B, 4, B, 1), (12, B, 16, B, 1)],
    "Y": [(1, 0, 8, 11, 2), (16, 0, 9, 11, 3), (8, 11, 8, B, 3),
          (0, 0, 3, 0, 1), (14, 0, 16, 0, 1), (5, B, 11, B, 1)],
}


def letter_mask(ch: str) -> Image.Image:
    m = Image.new("L", (LW + 2, H + 2), 0)
    d = ImageDraw.Draw(m)
    for x0, y0, x1, y1, w in LETTERS[ch]:
        d.line([(x0 + 1, y0 + 1), (x1 + 1, y1 + 1)], fill=255, width=w)
    return m


def build_word(word: str) -> Image.Image:
    width = len(word) * LW + (len(word) - 1) * GAP + 4
    mask = Image.new("L", (width, H + 4), 0)
    for i, ch in enumerate(word):
        mask.paste(letter_mask(ch), (1 + i * (LW + GAP), 1), letter_mask(ch))
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    mp = mask.load(); op = out.load()
    W, Hh = mask.size
    for y in range(Hh):
        for x in range(W):
            if mp[x, y]:
                t = (y - 1) / H  # vertical silver gradient (light top, darker base)
                c = SIL_HI if t < 0.3 else SIL if t < 0.75 else SIL_LO
                op[x, y] = c
            else:
                near = any(0 <= x + dx < W and 0 <= y + dy < Hh and mp[x + dx, y + dy]
                           for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if near:
                    op[x, y] = INK
    # brass highlight: top pixel row of each stroke segment
    for y in range(1, Hh):
        for x in range(W):
            if mp[x, y] and not mp[x, y - 1] and y < Hh * 0.55:
                op[x, y] = BRASS
    return out


def build_ring(radius: int = 15) -> Image.Image:
    """Incomplete circular inscription: glyph dashes with a missing arc."""
    size = radius * 2 + 5
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size // 2
    pts = []
    for i in range(720):
        a = math.radians(i / 2)
        p = (round(c + radius * math.cos(a)), round(c + radius * math.sin(a)))
        if p not in pts:
            pts.append(p)
    for k, (x, y) in enumerate(pts):
        ang = (math.degrees(math.atan2(y - c, x - c)) + 360) % 360
        if 300 <= ang <= 345:
            continue  # the interrupted part
        seg = k % 7
        if seg == 6:
            continue  # gap between glyphs
        im.putpixel((x, y), SIL if seg != 3 else BRASS)
        if seg == 1:  # small tick = glyph stroke, pointing inward
            ix = round(c + (radius - 2) * math.cos(math.atan2(y - c, x - c)))
            iy = round(c + (radius - 2) * math.sin(math.atan2(y - c, x - c)))
            im.putpixel((ix, iy), SIL_LO)
    return im


word = build_word("ASTHYA")
word.save(OUT / "logo_asthya.png")
build_ring().save(OUT / "logo_ring.png")
print("logo", word.size, "ring", build_ring().size)
