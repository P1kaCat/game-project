#!/usr/bin/env python3
"""Asthya application icon: an emblem, not a character. A broken inscription
ring (the incomplete soul inscription) in tarnished silver around an engraved
Roman "A", brass light escaping from the break. Drawn pixel by pixel on a
64x64 grid, then scaled by whole numbers.

usage: make_icon.py <repo_root>
  icon.png (192), assets/branding/icon_512.png, icon.ico,
  adaptive_foreground.png / adaptive_background.png (432, Android)
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
FONT = ROOT / "tools/ui/fonts/Cinzel-Bold.ttf"
B = ROOT / "assets/branding"
B.mkdir(parents=True, exist_ok=True)

T = (0, 0, 0, 0)
INK = (8, 8, 11, 255)
BG = [(30, 30, 37, 255), (25, 25, 31, 255), (20, 20, 25, 255), (16, 16, 20, 255)]
SIL = [(232, 233, 237, 255), (196, 198, 205, 255), (160, 162, 171, 255), (124, 126, 137, 255), (92, 93, 104, 255)]
NOTCH = (52, 52, 60, 255)
BRASS_HI = (246, 220, 156, 255)
BRASS = (200, 162, 92, 255)
BRASS_LO = (128, 98, 52, 255)
GLOW = (246, 220, 156, 90)

N = 64
C = (N - 1) / 2.0
R_OUT, R_IN = 27.5, 23.5
GAP = (-58.0, -28.0)        # degrees (screen coords, 0 = right, -90 = up): break at upper right


def angle(x, y):
    return math.degrees(math.atan2(y - C, x - C))


def emblem(with_bg: bool) -> Image.Image:
    im = Image.new("RGBA", (N, N), T)
    px = im.load()
    if with_bg:
        for y in range(N):
            for x in range(N):
                d = math.hypot(x - C, y - C) / (N / 2)
                px[x, y] = BG[min(3, int(d * 2.6))]
    ring = set()
    for y in range(N):
        for x in range(N):
            d = math.hypot(x - C, y - C)
            a = angle(x, y)
            if R_IN <= d <= R_OUT and not (GAP[0] < a < GAP[1]):
                ring.add((x, y))
    # outline of the ring
    for (x, y) in ring:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in ring and 0 <= x + dx < N and 0 <= y + dy < N:
                    px[x + dx, y + dy] = INK
    for (x, y) in ring:
        # light from the top-left: shade by the normal direction
        nx, ny = (x - C), (y - C)
        light = (-nx - ny) / (math.hypot(nx, ny) * 1.414 + 1e-6)   # -1..1
        k = int((1 - (light + 1) / 2) * (len(SIL) - 1) + 0.5)
        px[x, y] = SIL[k]
    # engraved notches every 20 degrees (inscription marks)
    for a in range(0, 360, 20):
        ar = math.radians(a)
        if GAP[0] - 6 < (a if a <= 180 else a - 360) < GAP[1] + 6:
            continue
        for r in (R_IN + 1.0, R_IN + 2.2, R_IN + 3.2):
            x, y = round(C + math.cos(ar) * r), round(C + math.sin(ar) * r)
            if (x, y) in ring:
                px[x, y] = NOTCH
    # brass light at both ends of the break
    for a in GAP:
        for r in (R_IN, R_IN + 1.5, R_IN + 3, R_OUT):
            ar = math.radians(a + (-2 if a == GAP[0] else 2))
            x, y = round(C + math.cos(ar) * r), round(C + math.sin(ar) * r)
            if 0 <= x < N and 0 <= y < N:
                px[x, y] = BRASS_HI if r < R_OUT else BRASS
    # a few brass sparks escaping through the break
    mid = math.radians((GAP[0] + GAP[1]) / 2)
    for r, side, col in ((R_OUT + 2.5, 0, BRASS_HI), (R_OUT + 5.0, 1.5, BRASS), (R_OUT + 3.5, -2.0, BRASS_LO), (R_IN + 2.0, 0, BRASS)):
        x = round(C + math.cos(mid) * r + side * math.sin(mid))
        y = round(C + math.sin(mid) * r - side * math.cos(mid))
        if 0 <= x < N and 0 <= y < N:
            px[x, y] = col
    # engraved "A" (traced from Cinzel Bold, OFL)
    cap = 29
    font = ImageFont.truetype(str(FONT), 400)
    bb = font.getbbox("A")
    big = Image.new("L", (bb[2] - bb[0] + 40, bb[3] - bb[1] + 40), 0)
    ImageDraw.Draw(big).text((20 - bb[0], 20 - bb[1]), "A", font=font, fill=255)
    s = cap / (bb[3] - bb[1])
    m = big.resize((max(1, round(big.width * s)), max(1, round(big.height * s))), Image.BOX).point(lambda v: 255 if v > 120 else 0)
    mb = m.getbbox()
    m = m.crop(mb)
    mp = m.load()
    ox = round(C - m.width / 2 + 0.5)
    oy = round(C - m.height / 2 + 1)
    inside = lambda x, y: 0 <= x < m.width and 0 <= y < m.height and mp[x, y] > 0
    for y in range(m.height):
        for x in range(m.width):
            if inside(x, y):
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        if not inside(x + dx, y + dy):
                            px[ox + x + dx, oy + y + dy] = INK
    for y in range(m.height):
        for x in range(m.width):
            if not inside(x, y):
                continue
            t = y / max(1, m.height - 1)
            c = SIL[min(len(SIL) - 1, int(t * len(SIL)))]
            if not inside(x, y - 1):
                c = BRASS_HI
            elif not inside(x - 1, y) and t < 0.8:
                c = SIL[0]
            elif not inside(x, y + 1) or not inside(x + 1, y):
                c = (72, 72, 82, 255)
            px[ox + x, oy + y] = c
    return im


full = emblem(True)
full.resize((192, 192), Image.NEAREST).save(ROOT / "icon.png")
full.resize((512, 512), Image.NEAREST).save(B / "icon_512.png")
full.resize((256, 256), Image.NEAREST).save(B / "icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
# Android adaptive icon: the emblem inside the 66 % safe zone, plain background
fg = Image.new("RGBA", (432, 432), T)
fg.alpha_composite(emblem(False).resize((256, 256), Image.NEAREST), (88, 88))
fg.save(B / "adaptive_foreground.png")
Image.new("RGBA", (432, 432), BG[1]).save(B / "adaptive_background.png")
print("icons written")
