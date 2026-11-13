#!/usr/bin/env python3
"""Draw the Asthya pixel-art UI kit: dark charcoal panels, tarnished silver
borders with a faint engraved notch line (incomplete inscriptions), muted brass
rivets and selection states. Every pixel is placed explicitly; output is 1:1
pixel art for 9-slice use (NinePatchRect / StyleBoxTexture, nearest filter).

usage: make_ui_art.py <repo_root>
"""
import sys
from pathlib import Path

from PIL import Image

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "assets/ui"
OUT.mkdir(parents=True, exist_ok=True)

T = (0, 0, 0, 0)
INK = (10, 10, 13, 255)              # outer outline
BG = (22, 22, 27, 236)               # charcoal window fill
BG_HI = (34, 33, 40, 236)            # inner top light line
SIL_HI = (198, 200, 204, 255)        # tarnished silver bevel
SIL = (142, 144, 150, 255)
SIL_LO = (82, 82, 90, 255)
ENGRAVE = (58, 58, 66, 255)          # engraved notches in the silver
BRASS_HI = (226, 196, 128, 255)      # muted brass
BRASS = (176, 142, 80, 255)
BRASS_LO = (110, 84, 44, 255)


def frame(size: int, fill, hi_fill, rivets=True, engraved=True) -> Image.Image:
    """Square 9-slice source: 1px ink, 2px bevelled silver, 1px ink, fill."""
    im = Image.new("RGBA", (size, size), fill)
    px = im.load()
    n = size - 1
    for i in range(size):
        for (x, y) in ((i, 0), (i, n), (0, i), (n, i)):
            px[x, y] = INK
    for i in range(1, n):
        px[i, 1] = SIL_HI; px[1, i] = SIL_HI          # light top/left
        px[i, n - 1] = SIL_LO; px[n - 1, i] = SIL_LO  # dark bottom/right
    for i in range(2, n - 1):
        px[i, 2] = SIL; px[2, i] = SIL; px[i, n - 2] = SIL; px[n - 2, i] = SIL
    if engraved:
        # Faint engraved notches along the middle silver line (tile-friendly:
        # period 4 so the 9-slice edges repeat seamlessly).
        for i in range(6, n - 5, 4):
            px[i, 2] = ENGRAVE; px[2, i] = ENGRAVE; px[i, n - 2] = ENGRAVE; px[n - 2, i] = ENGRAVE
    for i in range(3, n - 2):
        px[i, 3] = INK; px[3, i] = INK; px[i, n - 3] = INK; px[n - 3, i] = INK
    for i in range(4, n - 3):
        px[i, 4] = hi_fill
    if rivets:
        for cx, cy in ((2, 2), (n - 2, 2), (2, n - 2), (n - 2, n - 2)):
            for dx, dy, c in ((-1, -1, INK), (0, -1, BRASS_HI), (1, -1, INK),
                              (-1, 0, BRASS_HI), (0, 0, BRASS), (1, 0, BRASS_LO),
                              (-1, 1, INK), (0, 1, BRASS_LO), (1, 1, INK)):
                px[cx + dx, cy + dy] = c
    return im


frame(24, BG, BG_HI).save(OUT / "panel.png")
frame(24, T, T).save(OUT / "portrait_frame.png")


def button(fill, hi_fill, edge, accent=None):
    """14x14 button, 9-slice margin 5. `accent` = brass inner line (selected)."""
    im = Image.new("RGBA", (14, 14), fill)
    px = im.load(); n = 13
    for i in range(14):
        for (x, y) in ((i, 0), (i, n), (0, i), (n, i)):
            px[x, y] = INK
    for i in range(1, n):
        px[i, 1] = edge[0]; px[1, i] = edge[0]; px[i, n - 1] = edge[2]; px[n - 1, i] = edge[2]
    for i in range(2, n - 1):
        px[i, 2] = hi_fill
    if accent:
        for i in range(2, n - 1):
            px[2, i] = accent; px[n - 2, i] = accent
    for (x, y) in ((0, 0), (n, 0), (0, n), (n, n)):
        px[x, y] = T
    return im


button((30, 30, 36, 240), (42, 41, 49, 240), (SIL, SIL, SIL_LO)).save(OUT / "button.png")
button((44, 40, 36, 245), (60, 54, 44, 245), (BRASS_HI, BRASS, BRASS_LO), BRASS_LO).save(OUT / "button_hover.png")
button((92, 74, 42, 250), (118, 96, 56, 250), (BRASS_HI, BRASS_HI, BRASS), BRASS).save(OUT / "button_pressed.png")
button((24, 24, 28, 200), (28, 28, 32, 200), ((66, 66, 72, 255),) * 3).save(OUT / "button_disabled.png")

# Selection cursor (pointing right) 6x9, brass
cmap = {"X": INK, "H": BRASS_HI, "G": BRASS, "L": BRASS_LO, ".": T}
cur = Image.new("RGBA", (6, 9), T)
for y, r in enumerate(["X.....", "XHX...", "XHGX..", "XHGGX.", "XHGGLX", "XHGLX.", "XGLX..", "XLX...", "X....."]):
    for x, c in enumerate(r):
        cur.putpixel((x, y), cmap[c])
cur.save(OUT / "cursor.png")
# "Continue" arrow (down) 9x6, silver
smap = {"X": INK, "H": SIL_HI, "G": SIL, "L": SIL_LO, ".": T}
arr = Image.new("RGBA", (9, 6), T)
for y, r in enumerate(["XXXXXXXXX", "XHHHHHGLX", ".XHGGGLX.", "..XGGLX..", "...XLX...", "....X...."]):
    for x, c in enumerate(r):
        arr.putpixel((x, y), smap[c])
arr.save(OUT / "next_arrow.png")
# Selector arrows for settings rows (left / right), 7x9
lr = ["....X..", "...XHX.", "..XHGX.", ".XHGGX.", "..XGLX.", "...XLX.", "....X.."]
la = Image.new("RGBA", (7, 7), T)
for y, r in enumerate(lr):
    for x, c in enumerate(r):
        la.putpixel((x, y), smap[c])
la.save(OUT / "arrow_left.png")
la.transpose(Image.FLIP_LEFT_RIGHT).save(OUT / "arrow_right.png")
# Thin divider with a broken-inscription gap pattern, 32x3 (tiles horizontally)
div = Image.new("RGBA", (32, 3), T)
for x in range(32):
    if x % 8 in (6,):
        continue  # gaps: the "incomplete" line
    div.putpixel((x, 1), SIL_LO)
    if x % 8 == 3:
        div.putpixel((x, 0), SIL); div.putpixel((x, 2), SIL)
div.save(OUT / "divider.png")
# Hold-to-skip ring is drawn in code; slider/progress pieces
bar_bg = Image.new("RGBA", (6, 6), INK)
for x in range(1, 5):
    for y in range(1, 5):
        bar_bg.putpixel((x, y), (30, 30, 36, 255))
bar_bg.save(OUT / "bar_bg.png")
bar_fill = Image.new("RGBA", (6, 6), T)
for x in range(1, 5):
    for y in range(1, 5):
        bar_fill.putpixel((x, y), BRASS if y > 1 else BRASS_HI)
bar_fill.save(OUT / "bar_fill.png")
print("wrote", sorted(p.name for p in OUT.glob("*.png")))
