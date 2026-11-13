#!/usr/bin/env python3
"""Minimal PixelLab v2 API client used to generate the player character assets.

Only documented endpoints from https://api.pixellab.ai/v2/openapi.json are used:

  GET  /balance                       - remaining generations / credits
  POST /create-character-v3           - base south sprite (Pixen) + 8 rotations (v3)
  GET  /characters/{id}               - character detail (rotation URLs, animations)
  POST /characters/animations         - animate an existing character per direction
  GET  /background-jobs/{job_id}      - poll async jobs
  GET  /characters/{id}/zip           - export rotations + animation frames

Authentication: set PIXELLAB_API_KEY in the environment. It is sent as a
Bearer token and never written to disk or logs. (In environments where an
HTTPS proxy injects the credential, the variable may be left unset.)

State (character id, animation group ids, job ids) is kept in state.json next to
this script so generated references are reused instead of regenerated. The
player lives at the top level of state.json; other characters (NPCs) under
state["npcs"][KEY], selected with the global option --npc KEY.

Also used:
  POST /portrait-character-pro         character sprite -> detailed bust portrait
  POST /create-character-pro           reference-guided character (concept + style character)
  POST /edit-images-v2                 text-guided edit keeping the image structure
  POST /create-image-pixen             small transparent images (item icons)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.pixellab.ai/v2"
HERE = Path(__file__).resolve().parent
STATE_FILE = HERE / "state.json"
ALL_DIRECTIONS = [
    "south", "south-east", "east", "north-east",
    "north", "north-west", "west", "south-west",
]


# --------------------------------------------------------------------------- http
def _request(method: str, path: str, body: dict | None = None, raw: bool = False):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    key = os.environ.get("PIXELLAB_API_KEY")
    if key and url.startswith(API):
        req.add_header("Authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:2000]
        raise SystemExit(f"HTTP {e.code} on {method} {path}: {detail}")
    if raw:
        return payload
    return json.loads(payload) if payload else None


def load_state() -> dict:
    return json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


def scope(state: dict, npc: str | None) -> dict:
    """The state dict of the selected character (player = top level)."""
    return state if not npc else state.setdefault("npcs", {}).setdefault(npc, {})


def poll_job(job_id: str, interval: float = 8.0, timeout: float = 1800.0) -> dict:
    start = time.time()
    while True:
        job = _request("GET", f"/background-jobs/{job_id}")
        status = job.get("status")
        if status in ("completed", "failed"):
            return job
        lr = job.get("last_response") or {}
        q = lr.get("queue_position")
        print(f"  job {job_id[:8]}… {status}" + (f" (queue {q})" if q is not None else ""), flush=True)
        if time.time() - start > timeout:
            raise SystemExit(f"Timed out waiting for job {job_id}")
        time.sleep(interval)


# ----------------------------------------------------------------------- commands
def cmd_balance(_args):
    print(json.dumps(_request("GET", "/balance"), indent=2))


def cmd_create_character(args):
    root = load_state()
    state = scope(root, args.npc)
    if state.get("character_id") and not args.force:
        raise SystemExit(f"Character already exists ({state['character_id']}); pass --force to create another.")
    body = {
        "description": args.description,
        "name": args.name,
        "image_size": {"width": args.size, "height": args.size},
        "view": args.view,
        "template_id": "mannequin",
        "no_background": True,
        "outline": args.outline,
        "detail": args.detail,
    }
    if args.seed is not None:
        body["seed"] = args.seed
    resp = _request("POST", "/create-character-v3", body)
    print(json.dumps(resp, indent=2))
    state.update({
        "character_id": resp["character_id"],
        "character_job": resp["background_job_id"],
        "character_request": body,
    })
    save_state(root)
    job = poll_job(resp["background_job_id"])
    print("character job:", job["status"], json.dumps(job.get("usage")))
    if job["status"] != "completed":
        print(json.dumps(job, indent=2)[:4000])


def cmd_charpro(args):
    """Reference-guided character via POST /create-character-pro (8 rotations):
    concept image (identity) + style character (an existing sprite's style)."""
    import base64
    root = load_state()
    state = scope(root, args.npc)
    if state.get("character_id") and not args.force:
        raise SystemExit(f"Character already exists ({state['character_id']}); pass --force to create another.")
    body = {
        "description": args.description,
        "image_size": {"width": args.size, "height": args.size},
        "method": "create_from_concept" if args.concept else "create_with_style",
        "view": "low top-down",
        "template_id": "mannequin",
        "no_background": True,
    }
    if args.concept:
        body["concept_image"] = {"type": "base64", "base64": base64.b64encode(Path(args.concept).read_bytes()).decode()}
    if args.style_character:
        body["style_character_id"] = args.style_character
    if args.style_description:
        body["style_description"] = args.style_description
    resp = _request("POST", "/create-character-pro", body)
    stored = {k: v for k, v in body.items() if k != "concept_image"}
    stored["concept"] = args.concept
    state.update({"character_id": resp.get("character_id"), "character_job": resp["background_job_id"],
                  "character_request": stored})
    save_state(root)
    job = poll_job(resp["background_job_id"])
    print("charpro job:", job["status"], json.dumps(job.get("usage")), "character", resp.get("character_id"))
    if job["status"] != "completed":
        print(json.dumps(job, indent=2)[:4000])


def cmd_character(args):
    cid = args.character_id or scope(load_state(), args.npc).get("character_id")
    print(json.dumps(_request("GET", f"/characters/{cid}"), indent=2))


def cmd_animate(args):
    root = load_state()
    state = scope(root, args.npc)
    cid = state["character_id"]
    anims = state.setdefault("animations", {})
    entry = anims.setdefault(args.key, {})
    directions = args.directions.split(",") if args.directions else ALL_DIRECTIONS
    body = {
        "character_id": cid,
        "animation_name": args.key,
        "mode": args.mode,
        "directions": directions,
    }
    if args.template_action:
        body["template_action"] = args.template_action
    if args.action:
        body["action_description"] = args.action
    if args.frame_count:
        body["frame_count"] = args.frame_count
    if getattr(args, "subject", None):
        body["subject_description"] = args.subject
    if getattr(args, "initial_pose", None):
        body["initial_pose"] = args.initial_pose
    # keep_first_frame is only valid for custom (non-template_action) v3/pixminimax runs.
    if args.mode in ("v3", "pixminimax") and not args.template_action:
        body["keep_first_frame"] = not args.drop_first_frame
    if entry.get("animation_group_id"):
        body["animation_group_id"] = entry["animation_group_id"]
    resp = _request("POST", "/characters/animations", body)
    print(json.dumps(resp, indent=2))
    entry["animation_group_id"] = resp.get("animation_group_id")
    entry.setdefault("jobs", {}).update(dict(zip(resp["directions"], resp["background_job_ids"])))
    entry["request"] = {k: v for k, v in body.items() if k != "character_id"}
    save_state(root)
    if args.wait:
        wait_animation(args.key, args.npc)


def wait_animation(key: str, npc: str | None = None):
    root = load_state()
    state = scope(root, npc)
    jobs = state["animations"][key]["jobs"]
    results = {}
    for direction, job_id in jobs.items():
        job = poll_job(job_id)
        results[direction] = job["status"]
        print(f"{key}/{direction}: {job['status']} usage={json.dumps(job.get('usage'))}")
        if job["status"] == "failed":
            print(json.dumps(job.get("last_response"), indent=2)[:2000])
    state["animations"][key]["status"] = results
    save_state(root)


def cmd_wait(args):
    wait_animation(args.key, args.npc)


def cmd_zip(args):
    cid = scope(load_state(), args.npc)["character_id"]
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(_request("GET", f"/characters/{cid}/zip", raw=True))
    print(f"wrote {out} ({out.stat().st_size} bytes)")


def cmd_iso_tile(args):
    """POST /create-isometric-tile, poll, then GET /isometric-tiles/{id} and save the PNG."""
    import base64
    state = load_state()
    tiles = state.setdefault("tiles", {})
    body = {
        "description": args.description,
        "image_size": {"width": args.size, "height": args.size},
        "isometric_tile_size": args.tile_size,
        "isometric_tile_shape": args.shape,
        "outline": args.outline,
        "shading": args.shading,
        "detail": args.detail,
    }
    if args.seed is not None:
        body["seed"] = args.seed
    resp = _request("POST", "/create-isometric-tile", body)
    if "image" in resp:  # synchronous variant
        b64 = resp["image"]["base64"]
    else:
        job = poll_job(resp["background_job_id"], interval=4)
        print("tile job:", job["status"], json.dumps(job.get("usage")))
        if job["status"] != "completed":
            raise SystemExit(json.dumps(job, indent=2)[:3000])
        b64 = _request("GET", f"/isometric-tiles/{resp['tile_id']}")["image"]["base64"]
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(b64.split(",")[-1]))
    tiles[args.key] = {"tile_id": resp.get("tile_id"), "request": body, "file": str(out)}
    save_state(state)
    print(f"wrote {out}")


def cmd_portrait(args):
    """Character sprite (south-facing PNG) -> bust portrait (same identity)."""
    import base64
    root = load_state()
    state = scope(root, args.npc)
    b64 = base64.b64encode(Path(args.image).read_bytes()).decode()
    body = {"direction": "character_to_portrait", "image": {"type": "base64", "base64": b64},
            "view": args.view, "result_size": args.size}
    resp = _request("POST", "/portrait-character-pro", body)
    job = poll_job(resp["background_job_id"], interval=5)
    print("portrait job:", job["status"], json.dumps(job.get("usage")))
    if job["status"] != "completed":
        raise SystemExit(json.dumps(job, indent=2)[:3000])
    img = (job.get("last_response") or {}).get("images", [None])[0]
    data = img.get("base64") if isinstance(img, dict) else img
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(data.split(",")[-1]))
    state["portrait"] = {"request": {k: v for k, v in body.items() if k != "image"},
                         "source_image": args.image.split("/")[-1], "file": str(out)}
    save_state(root)
    print(f"wrote {out}")


def cmd_icon(args):
    """Small transparent pixel-art image (item icon) via the Pixen model."""
    import base64
    root = load_state()
    body = {"description": args.description, "image_size": {"width": args.size, "height": args.size},
            "no_background": True, "outline": args.outline, "detail": args.detail}
    if args.view:
        body["view"] = args.view
    if args.seed is not None:
        body["seed"] = args.seed
    resp = _request("POST", "/create-image-pixen", body)
    print("icon usage:", json.dumps(resp.get("usage")))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(resp["image"]["base64"].split(",")[-1]))
    root.setdefault("icons", {})[args.key] = {"request": body, "file": str(out)}
    save_state(root)
    print(f"wrote {out}")


def cmd_image(args):
    """Scene / background illustration via the Pixen model (native resolution)."""
    import base64
    root = load_state()
    body = {"description": args.description, "image_size": {"width": args.width, "height": args.height},
            "no_background": args.no_bg, "detail": args.detail}
    if args.outline:
        body["outline"] = args.outline
    if args.view:
        body["view"] = args.view
    if args.seed is not None:
        body["seed"] = args.seed
    resp = _request("POST", "/create-image-pixen", body)
    print("image usage:", json.dumps(resp.get("usage")))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(resp["image"]["base64"].split(",")[-1]))
    root.setdefault("images", {})[args.key] = {"request": body, "file": str(out)}
    save_state(root)
    print(f"wrote {out}")


def _ref(path: str, usage: str = "") -> dict:
    import base64
    from PIL import Image  # only needed for illustration generation
    w, h = Image.open(path).size
    r = {"image": {"type": "base64", "base64": base64.b64encode(Path(path).read_bytes()).decode()},
         "size": {"width": w, "height": h}}
    if usage:
        r["usage_description"] = usage
    return r


def cmd_image2(args):
    """Illustration via POST /generate-image-v2 (async job: no gateway timeout
    for large images; optional style image + subject references)."""
    import base64
    root = load_state()
    body = {"description": args.description, "image_size": {"width": args.width, "height": args.height},
            "no_background": args.no_bg}
    if args.style:
        body["style_image"] = _ref(args.style)
        body["style_options"] = {"color_palette": args.style_palette, "outline": True, "detail": True, "shading": True}
    if args.ref:
        body["reference_images"] = [_ref(p.split("::")[0], p.split("::")[1] if "::" in p else "") for p in args.ref]
    if args.seed is not None:
        body["seed"] = args.seed
    resp = _request("POST", "/generate-image-v2", body)
    job = poll_job(resp["background_job_id"], interval=6)
    print("image2 job:", job["status"], json.dumps(job.get("usage")))
    if job["status"] != "completed":
        raise SystemExit(json.dumps(job, indent=2)[:3000])
    imgs = (job.get("last_response") or {}).get("images", [])
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    for i, img in enumerate(imgs[: args.keep]):
        data = img.get("base64") if isinstance(img, dict) else img
        target = out if i == 0 else out.with_name(f"{out.stem}_{i}{out.suffix}")
        target.write_bytes(base64.b64decode(data.split(",")[-1]))
        print(f"wrote {target}")
    stored = {k: v for k, v in body.items() if k not in ("style_image", "reference_images")}
    stored["style"] = args.style
    stored["refs"] = args.ref
    root.setdefault("images", {})[args.key] = {"request": stored, "file": str(out), "usage": job.get("usage")}
    save_state(root)


def cmd_edit2(args):
    """Text-guided edit via POST /edit-images-v2 (keeps the original structure,
    e.g. a second state of the same illustration for a crossfade)."""
    import base64
    from PIL import Image
    w, h = Image.open(args.image).size
    body = {"method": "edit_with_text", "description": args.description,
            "edit_images": [{"image": {"type": "base64", "base64": base64.b64encode(Path(args.image).read_bytes()).decode()},
                             "width": w, "height": h}],
            "image_size": {"width": w, "height": h}, "no_background": False}
    if args.seed is not None:
        body["seed"] = args.seed
    resp = _request("POST", "/edit-images-v2", body)
    job = poll_job(resp["background_job_id"], interval=6)
    print("edit2 job:", job["status"], json.dumps(job.get("usage")))
    if job["status"] != "completed":
        raise SystemExit(json.dumps(job, indent=2)[:3000])
    imgs = (job.get("last_response") or {}).get("images", [])
    data = imgs[0].get("base64") if isinstance(imgs[0], dict) else imgs[0]
    Path(args.out).write_bytes(base64.b64decode(data.split(",")[-1]))
    print("wrote", args.out)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--npc", help="operate on state['npcs'][NPC] instead of the player")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("balance").set_defaults(func=cmd_balance)

    c = sub.add_parser("create-character")
    c.add_argument("--description", required=True)
    c.add_argument("--name", default="player")
    c.add_argument("--size", type=int, default=64)
    c.add_argument("--view", default="low top-down", choices=["low top-down", "high top-down", "side"])
    c.add_argument("--outline", default="single color black outline")
    c.add_argument("--detail", default="high detail")
    c.add_argument("--seed", type=int)
    c.add_argument("--force", action="store_true")
    c.set_defaults(func=cmd_create_character)

    e2 = sub.add_parser("edit2")
    e2.add_argument("--image", required=True)
    e2.add_argument("--description", required=True)
    e2.add_argument("--out", required=True)
    e2.add_argument("--seed", type=int)
    e2.set_defaults(func=cmd_edit2)

    cp = sub.add_parser("charpro")
    cp.add_argument("--description", required=True)
    cp.add_argument("--size", type=int, default=64)
    cp.add_argument("--concept", help="concept image (identity reference), max 1024px")
    cp.add_argument("--style-character", help="existing character id whose sprites set the style")
    cp.add_argument("--style-description")
    cp.add_argument("--force", action="store_true")
    cp.set_defaults(func=cmd_charpro)

    g = sub.add_parser("character")
    g.add_argument("--character-id")
    g.set_defaults(func=cmd_character)

    a = sub.add_parser("animate")
    a.add_argument("--key", required=True, help="local name, e.g. idle / walk / run")
    a.add_argument("--mode", default="pixminimax", choices=["template", "skeleton-v3", "v3", "pixminimax", "pro"])
    a.add_argument("--template-action")
    a.add_argument("--action")
    a.add_argument("--frame-count", type=int)
    a.add_argument("--directions", help="comma-separated; default all 8")
    a.add_argument("--drop-first-frame", action="store_true")
    a.add_argument("--subject", help="pixminimax: one noun phrase describing the character")
    a.add_argument("--initial-pose", help="pixminimax: pose of the first frame")
    a.add_argument("--wait", action="store_true")
    a.set_defaults(func=cmd_animate)

    w = sub.add_parser("wait")
    w.add_argument("--key", required=True)
    w.set_defaults(func=cmd_wait)

    z = sub.add_parser("zip")
    z.add_argument("--out", required=True)
    z.set_defaults(func=cmd_zip)

    t = sub.add_parser("iso-tile")
    t.add_argument("--key", required=True)
    t.add_argument("--description", required=True)
    t.add_argument("--out", required=True)
    t.add_argument("--size", type=int, default=64)
    t.add_argument("--tile-size", type=int, default=32, choices=[16, 32])
    t.add_argument("--shape", default="thin tile", choices=["thick tile", "thin tile", "block"])
    t.add_argument("--outline", default="lineless")
    t.add_argument("--shading", default="medium shading")
    t.add_argument("--detail", default="highly detailed")
    t.add_argument("--seed", type=int)
    t.set_defaults(func=cmd_iso_tile)

    pt = sub.add_parser("portrait")
    pt.add_argument("--image", required=True, help="south-facing character PNG")
    pt.add_argument("--out", required=True)
    pt.add_argument("--size", type=int, default=64, choices=[16, 32, 48, 64, 128, 160])
    pt.add_argument("--view", default="low top-down")
    pt.set_defaults(func=cmd_portrait)

    ic = sub.add_parser("icon")
    ic.add_argument("--key", required=True)
    ic.add_argument("--description", required=True)
    ic.add_argument("--out", required=True)
    ic.add_argument("--size", type=int, default=32)
    ic.add_argument("--outline", default="single color black outline")
    ic.add_argument("--detail", default="highly detailed")
    ic.add_argument("--view")
    ic.add_argument("--seed", type=int)
    ic.set_defaults(func=cmd_icon)

    im = sub.add_parser("image")
    im.add_argument("--key", required=True)
    im.add_argument("--description", required=True)
    im.add_argument("--out", required=True)
    im.add_argument("--width", type=int, default=576)
    im.add_argument("--height", type=int, default=320)
    im.add_argument("--no-bg", action="store_true")
    im.add_argument("--detail", default="highly detailed")
    im.add_argument("--outline")
    im.add_argument("--view")
    im.add_argument("--seed", type=int)
    im.set_defaults(func=cmd_image)

    i2 = sub.add_parser("image2")
    i2.add_argument("--key", required=True)
    i2.add_argument("--description", required=True)
    i2.add_argument("--out", required=True)
    i2.add_argument("--width", type=int, default=576)
    i2.add_argument("--height", type=int, default=320)
    i2.add_argument("--no-bg", action="store_true")
    i2.add_argument("--style", help="style image path (pixel size / rendering)")
    i2.add_argument("--style-palette", action="store_true", help="also copy the style image palette")
    i2.add_argument("--ref", action="append", help="subject reference PATH[::how to use it]")
    i2.add_argument("--keep", type=int, default=1)
    i2.add_argument("--seed", type=int)
    i2.set_defaults(func=cmd_image2)

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
