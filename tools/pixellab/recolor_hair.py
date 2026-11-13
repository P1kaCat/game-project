#!/usr/bin/env python3
"""Deterministic hair palette fix for a sprite set: desaturated gray pixels in
the head area become chestnut (hue/saturation of the reference ramp), keeping
the lightest grays as a few subtle strands. Applied identically to every frame
so the animation stays consistent.

usage: recolor_hair.py <png or dir> ...   (in place)
"""
import colorsys
import sys
from pathlib import Path

from PIL import Image

HUE, SAT = 0.045, 0.42          # chestnut
KEEP_GRAY_L = 0.47              # lighter grays stay gray (subtle strands)


def recolor(im: Image.Image, frame_w: int | None = None, frame_h: int | None = None) -> int:
    px = im.load()
    fw, fh = frame_w or im.width, frame_h or im.height
    n = 0
    for oy in range(0, im.height, fh):
        for ox in range(0, im.width, fw):
            box = im.crop((ox, oy, ox + fw, oy + fh)).getbbox()
            if not box:
                continue
            top, bottom = oy + box[1], oy + box[3]
            band = int((bottom - top) * 0.24)
            cx = ox + (box[0] + box[2]) // 2
            for y in range(top, top + band):
                for x in range(max(ox, cx - 9), min(ox + fw, cx + 10)):
                    r, g, b, a = px[x, y]
                    if a == 0:
                        continue
                    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
                    if s < 0.24 and 0.13 < l < KEEP_GRAY_L:
                        nr, ng, nb = colorsys.hls_to_rgb(HUE, l * 0.82, SAT)
                        px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
                        n += 1
    return n


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        p = Path(arg)
        files = sorted(p.rglob("*.png")) if p.is_dir() else [p]
        for f in files:
            im = Image.open(f).convert("RGBA")
            if "spritesheets" in f.parts:
                continue  # sheets are rebuilt from frames by the exporter
            c = recolor(im)
            im.save(f)
        print(arg, len(files), "files")
