#!/usr/bin/env python3
"""Draw the ASTHYA title as pixel art: Roman inscription capitals (traced from
Cinzel Bold, OFL, on the pixel grid without anti-aliasing), stepped tarnished-
silver fill, bevel, gilded (brass) top edges, ink outline and a drop shadow,
over an engraved rule broken by a small open circle (the incomplete
inscription).

usage: make_logo.py <repo_root>  -> assets/ui/logo_asthya.png
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
FONT = ROOT / "tools/ui/fonts/Cinzel-Bold.ttf"
OUT = ROOT / "assets/ui/logo_asthya.png"

TEXT = "ASTHYA"
CAP = 30           # cap height in final pixels
TRACK = 5          # extra letter spacing
SS = 8             # supersampling for the trace

T = (0, 0, 0, 0)
INK = (8, 8, 11, 255)
SHADOW = (8, 8, 11, 170)
SIL = [(236, 237, 240, 255), (204, 206, 212, 255), (170, 172, 180, 255), (138, 140, 150, 255), (104, 105, 116, 255)]
BEVEL_LO = (72, 72, 82, 255)
BRASS_HI = (236, 206, 140, 255)
BRASS = (190, 152, 86, 255)
BRASS_LO = (120, 92, 50, 255)


def trace_word() -> Image.Image:
    """1-bit mask of the word, traced at SS x and box-downsampled."""
    size = CAP * SS * 1.45
    font = ImageFont.truetype(str(FONT), int(size))
    # measure cap height precisely from the "H" glyph
    hb = font.getbbox("H")
    scale = (CAP * SS) / (hb[3] - hb[1])
    font = ImageFont.truetype(str(FONT), int(size * scale))
    widths = [font.getbbox(c)[2] - font.getbbox(c)[0] for c in TEXT]
    W = sum(widths) + TRACK * SS * (len(TEXT) - 1) + 8 * SS
    H = CAP * SS + 8 * SS
    big = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(big)
    x = 4 * SS
    top = font.getbbox("H")[1]
    for c, w in zip(TEXT, widths):
        bb = font.getbbox(c)
        d.text((x - bb[0], 4 * SS - top), c, font=font, fill=255)
        x += w + TRACK * SS
    small = big.resize((W // SS, H // SS), Image.BOX)
    return small.point(lambda v: 255 if v >= 118 else 0)


def main() -> None:
    m = trace_word()
    mw, mh = m.size
    mp = m.load()
    bb = m.getbbox()
    inside = lambda x, y: 0 <= x < mw and 0 <= y < mh and mp[x, y] > 0
    pad = 4
    rule_h = 9
    W, H = mw + 2 * pad, mh + 2 * pad + rule_h
    im = Image.new("RGBA", (W, H), T)
    px = im.load()
    top, bot = bb[1], bb[3] - 1
    # drop shadow + outline
    for y in range(mh):
        for x in range(mw):
            if inside(x, y):
                for dx, dy in ((1, 2), (2, 2), (1, 1)):
                    X, Y = x + pad + dx, y + pad + dy
                    if 0 <= X < W and 0 <= Y < H and px[X, Y][3] == 0:
                        px[X, Y] = SHADOW
    for y in range(mh):
        for x in range(mw):
            if inside(x, y):
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        if not inside(x + dx, y + dy):
                            px[x + pad + dx, y + pad + dy] = INK
    # fill: stepped silver by height, bevel and gilded top edges
    for y in range(mh):
        for x in range(mw):
            if not inside(x, y):
                continue
            t = (y - top) / max(1, bot - top)
            c = SIL[min(len(SIL) - 1, int(t * len(SIL)))]
            if not inside(x, y - 1):
                c = BRASS_HI if not inside(x, y - 2) or t < 0.5 else BRASS
            elif not inside(x - 1, y) and t < 0.85:
                c = SIL[0] if t < 0.5 else SIL[1]
            elif not inside(x, y + 1) or not inside(x + 1, y):
                c = BEVEL_LO
            px[x + pad, y + pad] = c
    # engraved rule with a small open circle in the middle
    ry = pad + mh + 3
    cx = W // 2
    for x in range(pad + bb[0] + 6, pad + bb[2] - 6):
        if abs(x - cx) <= 7:
            continue
        fade = min(x - (pad + bb[0] + 6), (pad + bb[2] - 6) - x)
        if fade < 12 and x % 2:
            continue  # dotted ends: the line fades out
        px[x, ry] = BRASS_LO if fade < 24 else BRASS
        px[x, ry + 1] = INK
    ring = ["..XXX..", ".X...X.", "X.....X", "X......", "X.....X", ".X...X.", "..XXX.."]
    for j, row in enumerate(ring):
        for i, ch in enumerate(row):
            if ch == "X":
                px[cx - 3 + i, ry - 3 + j] = BRASS_HI if j < 3 else BRASS
    im = im.crop(im.getbbox())
    im.save(OUT)
    print("wrote", OUT, im.size)


main()
