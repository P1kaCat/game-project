#!/usr/bin/env python3
"""Export a PixelLab NPC (character ZIP) into the game's asset layout.

usage: export_npc.py <extracted_character_zip_dir> <npc_name> <repo_root> [portrait.png]

Writes assets/characters/<npc>/ with the same structure and metadata format
as the player (see export_assets.py), so DirectionalSprite can load it:
  rotations/<dir>.png, <anim>/<dir>/frame_NN.png, spritesheets/<npc>_<anim>.png,
  <npc>_animations.json, and portrait.png when given.
Animations are taken from the ZIP (whatever exists, e.g. idle only).
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_assets import DIRS, binarize_alpha  # noqa: E402

FRAME_MS = {"idle": 200, "walk": 100, "run": 75, "greet": 110, "gesture": 120}
ONCE = {"greet", "gesture", "getup"}  # one-shot animations (no loop)


def main(src: Path, name: str, root: Path, portrait: Path | None) -> None:
    meta = json.loads((src / "metadata.json").read_text())
    state = meta["states"][0]
    char = state["character"]
    frames_meta = state["frames"]
    out = root / "assets/characters" / name
    if out.exists():
        shutil.rmtree(out)
    (out / "spritesheets").mkdir(parents=True)

    # Animations can come on different canvases (68x68, 80x80...): centre-pad
    # everything onto the largest one and align each animation's feet with the
    # base rotations, like export_assets.py does for the player.
    raw = {key: {code: [Image.open(src / p).convert("RGBA") for p in dirs[pl]] for code, pl in DIRS if pl in dirs}
           for key, dirs in frames_meta["animations"].items()}
    raw_rot = {code: Image.open(src / frames_meta["rotations"][pl]).convert("RGBA") for code, pl in DIRS}
    sizes = [im.size for a in raw.values() for v in a.values() for im in v] + [im.size for im in raw_rot.values()]
    cw, ch = max(w for w, _ in sizes), max(h for _, h in sizes)
    canvas = (cw, ch)

    def pad(im, dy=0):
        c = Image.new("RGBA", canvas, (0, 0, 0, 0))
        c.alpha_composite(im, ((cw - im.width) // 2, (ch - im.height) // 2 + dy))
        return c

    def modal_bottom(ims):
        b = [im.getbbox()[3] for im in ims if im.getbbox()]
        return max(set(b), key=b.count)

    rotations = {}
    (out / "rotations").mkdir()
    for code, im in raw_rot.items():
        rotations[code], _ = binarize_alpha(pad(im))
        rotations[code].save(out / "rotations" / f"{code}.png")
    ref = modal_bottom(rotations.values())
    anims = {}
    for key, per_dir in raw.items():
        dy = ref - modal_bottom([pad(im) for v in per_dir.values() for im in v])
        anims[key] = {code: [pad(im, dy) for im in ims] for code, ims in per_dir.items()}

    bottoms = [im.getbbox()[3] for im in rotations.values()]
    foot_y = max(set(bottoms), key=bottoms.count)
    anim_meta = {}
    for key, per_dir in anims.items():
        n = max(len(v) for v in per_dir.values())
        rows = [code for code, _ in DIRS if code in per_dir]
        sheet = Image.new("RGBA", (cw * n, ch * len(rows)), (0, 0, 0, 0))
        for row, code in enumerate(rows):
            d = out / key / code
            d.mkdir(parents=True)
            for i, im in enumerate(per_dir[code]):
                im, _ = binarize_alpha(im)
                im.save(d / f"frame_{i:02d}.png")
                sheet.alpha_composite(im, (i * cw, row * ch))
        sheet.save(out / "spritesheets" / f"{name}_{key}.png")
        dur = FRAME_MS.get(key, 120)
        anim_meta[key] = {"sheet": f"spritesheets/{name}_{key}.png", "frames": n, "frame_duration_ms": dur,
                          "fps": round(1000 / dur, 3), "loop": key not in ONCE, "rows": rows,
                          "frame_dir": f"{key}/<direction>/frame_NN.png"}

    s_box = rotations["s"].getbbox()
    metadata = {
        "name": name,
        "source": {"generator": "PixelLab API v2", "character_endpoint": "POST /v2/create-character-v3",
                   "animation_endpoint": "POST /v2/characters/animations",
                   "pixellab_character_id": char["id"], "view": char["view"],
                   "character_canvas": [char["size"]["width"], char["size"]["height"]], "prompt": char["prompt"]},
        "frame_width": cw, "frame_height": ch,
        "pivot": {"x": cw // 2, "y": foot_y, "note": "foot contact point in frame pixels"},
        "character_body_size_south": [s_box[2] - s_box[0], s_box[3] - s_box[1]],
        "directions": [c for c, _ in DIRS], "direction_names": {c: pl for c, pl in DIRS},
        "sheet_layout": "rows = directions in 'directions' order, columns = frames, no spacing",
        "animations": anim_meta, "filtering": "nearest",
    }
    if portrait:
        im, _ = binarize_alpha(Image.open(portrait))
        im.save(out / "portrait.png")
        metadata["portrait"] = {"file": "portrait.png", "size": list(im.size),
                                "source": "POST /v2/portrait-character-pro (character_to_portrait, from rotations/s)"}
    (out / f"{name}_animations.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"canvas": canvas, "pivot": metadata["pivot"], "body": metadata["character_body_size_south"],
                      "animations": {k: v["frames"] for k, v in anim_meta.items()}}))


if __name__ == "__main__":
    main(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4]) if len(sys.argv) > 4 else None)
