#!/usr/bin/env python3
"""Organise a PixelLab character ZIP export into the game's asset layout.

usage: export_assets.py <extracted_character_zip_dir> <tiles_src_dir> <repo_root>

Produces (relative to repo root):

  assets/characters/player/rotations/<dir>.png          base 8-direction sprites
  assets/characters/player/{idle,walk,run}/<dir>/frame_NN.png
  assets/characters/player/spritesheets/player_<anim>.png
  assets/characters/player/player_animations.json        metadata (read by Godot)
  assets/tiles/terrain/<name>.png + terrain_atlas.png + terrain.json

All frames share ONE canvas size and ONE foot pivot, so switching animation or
direction never shifts the character. Frames are copied pixel-for-pixel (no
resampling); rotations are padded, never scaled.
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

# Direction order used everywhere (sprite sheet rows, metadata, Godot code).
DIRS = [  # (short code, PixelLab name)
    ("n", "north"), ("ne", "north-east"), ("e", "east"), ("se", "south-east"),
    ("s", "south"), ("sw", "south-west"), ("w", "west"), ("nw", "north-west"),
]

# Animation key in PixelLab -> (local name, frame duration ms, loop)
ANIMS = {
    "idle": ("idle", 200, True),
    "walk": ("walk", 100, True),
    "run": ("run", 75, True),
}

TILES = ["grass", "grass_flowers", "dirt", "cobblestone"]


def binarize_alpha(im: Image.Image) -> tuple[Image.Image, int]:
    """Pixel art must have hard alpha. Count (and fix) any partial-alpha pixels."""
    im = im.convert("RGBA")
    px = im.load()
    fixed = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if 0 < a < 255:
                fixed += 1
                px[x, y] = (r, g, b, 255 if a >= 128 else 0)
            elif a == 0 and (r or g or b):
                px[x, y] = (0, 0, 0, 0)
    return im, fixed


def main(src: Path, tiles_src: Path, root: Path) -> None:
    meta = json.loads((src / "metadata.json").read_text())
    state = meta["states"][0]
    frames_meta = state["frames"]
    char = state["character"]

    out = root / "assets/characters/player"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    # ---- load everything, determine the common canvas ------------------------
    anim_frames: dict[str, dict[str, list[Image.Image]]] = {}
    canvas = None
    for key, (name, _, _) in ANIMS.items():
        dirs = frames_meta["animations"][key]
        anim_frames[name] = {}
        for code, pl in DIRS:
            ims = [Image.open(src / p).convert("RGBA") for p in dirs[pl]]
            for im in ims:
                if canvas is None:
                    canvas = im.size
                assert im.size == canvas, f"{name}/{pl} has size {im.size}, expected {canvas}"
            anim_frames[name][code] = ims
    cw, ch = canvas

    # Rotations are smaller (character canvas); PixelLab grows animation canvases
    # symmetrically around the character, so centre-pad to the animation canvas.
    rotations = {}
    for code, pl in DIRS:
        im = Image.open(src / frames_meta["rotations"][pl]).convert("RGBA")
        pad = Image.new("RGBA", canvas, (0, 0, 0, 0))
        pad.alpha_composite(im, ((cw - im.width) // 2, (ch - im.height) // 2))
        rotations[code] = pad

    # ---- foot pivot: bottom edge of the feet, horizontal centre of canvas -----
    bottoms = [rotations[c].getbbox()[3] for c, _ in DIRS]
    bottoms += [im.getbbox()[3] for im in sum(anim_frames["idle"].values(), [])]
    foot_y = max(set(bottoms), key=bottoms.count)  # most common bottom edge
    pivot = (cw // 2, foot_y)

    # ---- write individual frames + sprite sheets ------------------------------
    alpha_fixed = 0
    (out / "rotations").mkdir()
    for code, im in rotations.items():
        im, n = binarize_alpha(im)
        alpha_fixed += n
        im.save(out / "rotations" / f"{code}.png")
        rotations[code] = im

    (out / "spritesheets").mkdir()
    anim_meta = {}
    for key, (name, dur, loop) in ANIMS.items():
        n_frames = max(len(v) for v in anim_frames[name].values())
        sheet = Image.new("RGBA", (cw * n_frames, ch * len(DIRS)), (0, 0, 0, 0))
        for row, (code, _) in enumerate(DIRS):
            d = out / name / code
            d.mkdir(parents=True)
            frames = anim_frames[name][code]
            assert len(frames) == n_frames, f"{name}/{code}: {len(frames)} != {n_frames}"
            for i, im in enumerate(frames):
                im, n = binarize_alpha(im)
                alpha_fixed += n
                im.save(d / f"frame_{i:02d}.png")
                sheet.alpha_composite(im, (i * cw, row * ch))
        sheet_path = out / "spritesheets" / f"player_{name}.png"
        sheet.save(sheet_path)
        anim_meta[name] = {
            "sheet": f"spritesheets/player_{name}.png",
            "frames": n_frames,
            "frame_duration_ms": dur,
            "fps": round(1000 / dur, 3),
            "loop": loop,
            "rows": [c for c, _ in DIRS],
            "frame_dir": f"{name}/<direction>/frame_NN.png",
        }

    # rotation sheet (1 frame per direction, same row order) for convenience
    rot_sheet = Image.new("RGBA", (cw, ch * len(DIRS)), (0, 0, 0, 0))
    for row, (code, _) in enumerate(DIRS):
        rot_sheet.alpha_composite(rotations[code], (0, row * ch))
    rot_sheet.save(out / "spritesheets" / "player_rotations.png")

    # bounding box of the character body (for documentation / collision tuning)
    all_imgs = list(rotations.values()) + [im for a in anim_frames.values() for v in a.values() for im in v]
    bx = [im.getbbox() for im in all_imgs]
    union = (min(b[0] for b in bx), min(b[1] for b in bx), max(b[2] for b in bx), max(b[3] for b in bx))
    s_box = rotations["s"].getbbox()

    metadata = {
        "name": "player",
        "source": {
            "generator": "PixelLab API v2",
            "character_endpoint": "POST /v2/create-character-v3",
            "animation_endpoint": "POST /v2/characters/animations",
            "pixellab_character_id": char["id"],
            "view": char["view"],
            "character_canvas": [char["size"]["width"], char["size"]["height"]],
            "prompt": char["prompt"],
        },
        "frame_width": cw,
        "frame_height": ch,
        "pivot": {"x": pivot[0], "y": pivot[1], "note": "foot contact point in frame pixels; place this on the ground position"},
        "character_body_size_south": [s_box[2] - s_box[0], s_box[3] - s_box[1]],
        "content_union_bbox": union,
        "directions": [c for c, _ in DIRS],
        "direction_names": {c: pl for c, pl in DIRS},
        "sheet_layout": "rows = directions in 'directions' order, columns = frames left to right, no padding/spacing",
        "rotations": {"dir": "rotations/<direction>.png", "sheet": "spritesheets/player_rotations.png"},
        "animations": anim_meta,
        "filtering": "nearest",
    }
    (out / "player_animations.json").write_text(json.dumps(metadata, indent=2) + "\n")

    # ---- tiles -----------------------------------------------------------------
    tout = root / "assets/tiles/terrain"
    if tout.exists():
        shutil.rmtree(tout)
    tout.mkdir(parents=True)
    tile_imgs = []
    for n in TILES:
        im, k = binarize_alpha(Image.open(tiles_src / f"{n}.png"))
        alpha_fixed += k
        im.save(tout / f"{n}.png")
        tile_imgs.append(im)
    tw, th = tile_imgs[0].size
    atlas = Image.new("RGBA", (tw * len(TILES), th), (0, 0, 0, 0))
    for i, im in enumerate(tile_imgs):
        atlas.alpha_composite(im, (i * tw, 0))
    atlas.save(tout / "terrain_atlas.png")
    (tout / "terrain.json").write_text(json.dumps({
        "source": {"generator": "PixelLab API v2", "endpoint": "POST /v2/create-isometric-tile",
                   "isometric_tile_size": 32, "isometric_tile_shape": "thin tile", "image_size": [tw, th]},
        "projection": "2:1 isometric diamond",
        "cell_size": [64, 32],
        "texture_size": [tw, th],
        "top_face": {"top_vertex_y": 22, "side_corner_y": 38, "bottom_vertex_y": 54, "center": [32, 38],
                      "note": "the walkable top face is an exact 64x32 diamond centred at (32,38); ~10px of earth side below it"},
        "atlas": "terrain_atlas.png",
        "atlas_order": TILES,
        "filtering": "nearest",
    }, indent=2) + "\n")

    print(json.dumps({"canvas": canvas, "pivot": pivot, "body_south": metadata["character_body_size_south"],
                      "union": union, "alpha_pixels_fixed": alpha_fixed,
                      "animations": {k: v["frames"] for k, v in anim_meta.items()}}, indent=2))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
