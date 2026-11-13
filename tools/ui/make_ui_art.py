#!/usr/bin/env python3
"""Draw the pixel-art UI pieces (dark fantasy + warm gold) used by the dialogue
and shop windows. Every pixel is placed explicitly; output is 1:1 pixel art
meant for 9-slice (NinePatch / StyleBoxTexture) use with nearest filtering.

usage: make_ui_art.py <repo_root>
"""
import sys
from pathlib import Path

from PIL import Image

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "assets/ui"
OUT.mkdir(parents=True, exist_ok=True)

INK = (11, 9, 16, 255)          # outline
BG = (24, 19, 33, 238)          # window fill (slightly translucent)
BG_HI = (40, 32, 54, 238)       # inner top highlight
GOLD_HI = (246, 214, 132, 255)
GOLD = (214, 160, 72, 255)
GOLD_LO = (138, 88, 38, 255)
GEM = (178, 52, 44, 255)
GEM_HI = (240, 120, 96, 255)
T = (0, 0, 0, 0)


def frame(size: int, fill, hi_fill, gold=(GOLD_HI, GOLD, GOLD_LO), studs=True) -> Image.Image:
    """Square 9-slice source: 1px ink, 2px bevelled gold, 1px ink, fill."""
    im = Image.new("RGBA", (size, size), fill)
    px = im.load()
    n = size - 1
    hi, mid, lo = gold
    for i in range(size):
        for (x, y) in ((i, 0), (i, n), (0, i), (n, i)):
            px[x, y] = INK
    for i in range(1, n):
        # outer gold ring (bevel: light top/left, dark bottom/right)
        px[i, 1] = hi; px[1, i] = hi
        px[i, n - 1] = lo; px[n - 1, i] = lo
    for i in range(2, n - 1):
        px[i, 2] = mid; px[2, i] = mid; px[i, n - 2] = mid; px[n - 2, i] = mid
    for i in range(3, n - 2):
        px[i, 3] = INK; px[3, i] = INK; px[i, n - 3] = INK; px[n - 3, i] = INK
    for i in range(4, n - 3):
        px[i, 4] = hi_fill  # inner top light line
    if studs:
        for cx, cy in ((2, 2), (n - 2, 2), (2, n - 2), (n - 2, n - 2)):
            for dx, dy, c in ((0, -2, INK), (-1, -1, INK), (0, -1, GOLD_HI), (1, -1, INK),
                              (-2, 0, INK), (-1, 0, GOLD), (0, 0, GEM), (1, 0, GOLD_LO), (2, 0, INK),
                              (-1, 1, INK), (0, 1, GOLD_LO), (1, 1, INK), (0, 2, INK)):
                x, y = cx + dx, cy + dy
                if 0 <= x < size and 0 <= y < size:
                    px[x, y] = c
            px[cx, cy - 1] = GEM_HI if (cx, cy) == (2, 2) else px[cx, cy - 1]
    return im


# Main window (dialogue box, shop panels): 9-slice margin 8
frame(24, BG, BG_HI).save(OUT / "panel.png")
# Portrait frame: same border, transparent centre (portrait drawn behind)
p = frame(24, T, T)
p.save(OUT / "portrait_frame.png")
# Buttons / choice rows: thinner look, no studs, 9-slice margin 5
def button(fill, hi_fill, gold):
    im = Image.new("RGBA", (14, 14), fill)
    px = im.load(); n = 13
    for i in range(14):
        for (x, y) in ((i, 0), (i, n), (0, i), (n, i)):
            px[x, y] = INK
    for i in range(1, n):
        px[i, 1] = gold[0]; px[1, i] = gold[0]; px[i, n - 1] = gold[2]; px[n - 1, i] = gold[2]
    for i in range(2, n - 1):
        px[i, 2] = hi_fill
    for (x, y) in ((0, 0), (n, 0), (0, n), (n, n)):
        px[x, y] = T  # rounded corners
    return im
button((36, 29, 48, 240), (52, 42, 68, 240), (GOLD, GOLD, GOLD_LO)).save(OUT / "button.png")
button((74, 54, 34, 245), (110, 82, 44, 245), (GOLD_HI, GOLD_HI, GOLD)).save(OUT / "button_hover.png")
button((150, 104, 44, 250), (182, 132, 60, 250), (GOLD_HI, GOLD_HI, GOLD_HI)).save(OUT / "button_pressed.png")
button((28, 25, 32, 200), (34, 31, 38, 200), ((90, 80, 70, 255),) * 3).save(OUT / "button_disabled.png")
# Selection cursor (pointing right) 6x9
cur = Image.new("RGBA", (6, 9), T)
rows = ["X.....", "XHX...", "XHGX..", "XHGGX.", "XHGGLX", "XHGLX.", "XGLX..", "XLX...", "X....."]
cmap = {"X": INK, "H": GOLD_HI, "G": GOLD, "L": GOLD_LO, ".": T}
for y, r in enumerate(rows):
    for x, c in enumerate(r):
        cur.putpixel((x, y), cmap[c])
cur.save(OUT / "cursor.png")
# "Continue" arrow (pointing down) 9x6
arr = Image.new("RGBA", (9, 6), T)
rows = ["XXXXXXXXX", "XHHHHHGLX", ".XHGGGLX.", "..XGGLX..", "...XLX...", "....X...."]
for y, r in enumerate(rows):
    for x, c in enumerate(r):
        arr.putpixel((x, y), cmap[c])
arr.save(OUT / "next_arrow.png")
print("wrote", sorted(p.name for p in OUT.glob("*.png")))
