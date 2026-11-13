#!/usr/bin/env python3
"""Build nearest-neighbour preview strips from an extracted PixelLab character ZIP.

usage: preview.py <extracted_zip_dir> <out_dir> [scale]
Writes one PNG per animation (rows = directions, cols = frames) and prints frame
sizes + per-frame bounding boxes so size drift / foot sliding can be checked.
"""
import json, sys
from pathlib import Path
from PIL import Image

src, out = Path(sys.argv[1]), Path(sys.argv[2])
scale = int(sys.argv[3]) if len(sys.argv) > 3 else 6
out.mkdir(parents=True, exist_ok=True)
meta = json.loads((src / "metadata.json").read_text())
ORDER = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
for state in meta["states"]:
    for anim, dirs in state["frames"]["animations"].items():
        rows = [d for d in ORDER if d in dirs]
        frames = {d: [Image.open(src / p).convert("RGBA") for p in dirs[d]] for d in rows}
        fw, fh = frames[rows[0]][0].size
        n = max(len(v) for v in frames.values())
        sheet = Image.new("RGBA", (fw * n * scale, fh * len(rows) * scale), (60, 90, 70, 255))
        for r, d in enumerate(rows):
            boxes = []
            for c, im in enumerate(frames[d]):
                sheet.alpha_composite(im.resize((fw * scale, fh * scale), Image.NEAREST), (c * fw * scale, r * fh * scale))
                boxes.append(im.getbbox())
            print(f"{anim}/{d}: {len(frames[d])} frames {fw}x{fh} bboxes={boxes}")
        name = anim.replace(" ", "_").replace("/", "_")
        sheet.save(out / f"{name}.png")
