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
this script so generated references are reused instead of regenerated.
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
    state = load_state()
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
    save_state(state)
    job = poll_job(resp["background_job_id"])
    print("character job:", job["status"], json.dumps(job.get("usage")))
    if job["status"] != "completed":
        print(json.dumps(job, indent=2)[:4000])


def cmd_character(args):
    cid = args.character_id or load_state().get("character_id")
    print(json.dumps(_request("GET", f"/characters/{cid}"), indent=2))


def cmd_animate(args):
    state = load_state()
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
    save_state(state)
    if args.wait:
        wait_animation(args.key)


def wait_animation(key: str):
    state = load_state()
    jobs = state["animations"][key]["jobs"]
    results = {}
    for direction, job_id in jobs.items():
        job = poll_job(job_id)
        results[direction] = job["status"]
        print(f"{key}/{direction}: {job['status']} usage={json.dumps(job.get('usage'))}")
        if job["status"] == "failed":
            print(json.dumps(job.get("last_response"), indent=2)[:2000])
    state["animations"][key]["status"] = results
    save_state(state)


def cmd_wait(args):
    wait_animation(args.key)


def cmd_zip(args):
    cid = load_state()["character_id"]
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


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
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

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
