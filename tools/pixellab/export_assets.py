#!/usr/bin/env python3
"""Organise a PixelLab character ZIP export into the game's asset layout.

usage: export_assets.py <extracted_character_zip_dir> <tiles_src_dir|-> <repo_root> [anim spec]

anim spec: comma list of pixellab_key:local_name:frame_ms[:once], e.g.
  idle:idle:200,walk:walk:100,run:run:75,getup:getup:110:once
Animations may exist in only some directions (e.g. a one-off get-up move).

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

# Animation key in PixelLab -> (local name, frame duration ms, loop).
# walk/run come from the skeleton-v3 regeneration (one shared 3D motion for
# all 8 directions, cloak hanging naturally); the first v3 versions ("walk",
# "run") had direction-dependent motion and a wind-blown cloak.
ANIMS = {
    "idle": ("idle", 200, True),
    "walk_s3": ("walk", 100, True),
    "run_s3": ("run", 75, True),
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
    # PixelLab grows each animation's canvas symmetrically around the character
    # (68x68, 80x80...). Everything is centre-padded onto the largest canvas,
    # then each animation is shifted vertically so its feet rest on the same
    # row as the base rotations (no 1 px jump when switching animations).
    raw: dict[str, dict[str, list[Image.Image]]] = {}
    for key, (name, _, _) in ANIMS.items():
        dirs = frames_meta["animations"][key]
        raw[name] = {code: [Image.open(src / p).convert("RGBA") for p in dirs[pl]] for code, pl in DIRS if pl in dirs}
    raw_rot = {code: Image.open(src / frames_meta["rotations"][pl]).convert("RGBA") for code, pl in DIRS}
    cw = max([im.width for a in raw.values() for v in a.values() for im in v] + [im.width for im in raw_rot.values()])
    ch = max([im.height for a in raw.values() for v in a.values() for im in v] + [im.height for im in raw_rot.values()])
    canvas = (cw, ch)

    def pad(im: Image.Image, dy: int = 0) -> Image.Image:
        out = Image.new("RGBA", canvas, (0, 0, 0, 0))
        out.alpha_composite(im, ((cw - im.width) // 2, (ch - im.height) // 2 + dy))
        return out

    def modal_bottom(ims) -> int:
        b = [im.getbbox()[3] for im in ims if im.getbbox()]
        return max(set(b), key=b.count)

    rotations = {code: pad(im) for code, im in raw_rot.items()}
    ref_bottom = modal_bottom(rotations.values())
    anim_frames: dict[str, dict[str, list[Image.Image]]] = {}
    for name, per_dir in raw.items():
        padded = {code: [pad(im) for im in ims] for code, ims in per_dir.items()}
        dy = ref_bottom - modal_bottom([im for ims in padded.values() for im in ims])
        anim_frames[name] = {code: [pad(im, dy) for im in ims] for code, ims in per_dir.items()}
        print(f"{name}: source canvas {next(iter(per_dir.values()))[0].size}, dirs {list(per_dir)}, feet aligned with dy={dy}")

    # ---- foot pivot: bottom edge of the feet, horizontal centre of canvas -----
    bottoms = [rotations[c].getbbox()[3] for c, _ in DIRS]
    bottoms += [im.getbbox()[3] for im in sum(anim_frames.get("idle", {}).values(), [])]
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
        rows = [code for code, _ in DIRS if code in anim_frames[name]]
        sheet = Image.new("RGBA", (cw * n_frames, ch * len(rows)), (0, 0, 0, 0))
        for row, code in enumerate(rows):
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
            "rows": rows,
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
    if str(tiles_src) == "-":
        tile_imgs = None
    tout = root / "assets/tiles/terrain"
    if str(tiles_src) == "-":
        print(json.dumps({"canvas": canvas, "pivot": pivot, "body_south": metadata["character_body_size_south"],
                          "animations": {k: v["frames"] for k, v in anim_meta.items()}}))
        return
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
    if len(sys.argv) > 4:
        ANIMS.clear()
        for spec in sys.argv[4].split(","):
            parts = spec.split(":")
            ANIMS[parts[0]] = (parts[1], int(parts[2]), not (len(parts) > 3 and parts[3] == "once"))
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
