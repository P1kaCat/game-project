#!/usr/bin/env python3
"""Extend a pixel-art illustration beyond its borders (outpainting) with
POST /v2/inpaint-v3, in overlapping windows (256x256 on a Tier 1 plan: larger
inpainting needs Tier 2), so a 480x254 menu background can cover any screen.
Window size: WIN_W / WIN_H environment variables (default 256).

usage: outpaint.py <in.png> <out.png> <W> <H> "<description>"
The source is centred on a WxH canvas; each window inpaints only what is
still unknown (mask white = generate), keeping everything already there.
"""
import base64
import io
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixellab_client import _request, poll_job  # noqa: E402

WIN = (int(__import__("os").environ.get("WIN_W", 256)), int(__import__("os").environ.get("WIN_H", 256)))


def b64(im: Image.Image) -> dict:
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return {"type": "base64", "base64": base64.b64encode(buf.getvalue()).decode()}


def main(src: str, dst: str, W: int, H: int, desc: str) -> None:
    art = Image.open(src).convert("RGB")
    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    known = Image.new("L", (W, H), 0)
    ox, oy = (W - art.width) // 2, (H - art.height) // 2
    canvas.paste(art, (ox, oy))
    known.paste(255, (ox, oy, ox + art.width, oy + art.height))
    def starts(total, win):
        if total <= win:
            return [0]
        n = -(-(total - win) // (win * 3 // 4)) + 1      # >= 25 % overlap
        return sorted({round(i * (total - win) / (n - 1)) for i in range(n)})
    xs = starts(W, WIN[0])
    ys = starts(H, WIN[1])
    for y in ys:
        for x in xs:
            box = (x, y, x + min(WIN[0], W), y + min(WIN[1], H))
            k = known.crop(box)
            if min(k.getdata()) == 255:
                continue
            img = canvas.crop(box)
            mask = k.point(lambda v: 0 if v else 255).convert("RGB")
            w, h = img.size
            body = {"description": desc,
                    "inpainting_image": {"image": b64(img), "size": {"width": w, "height": h}},
                    "mask_image": {"image": b64(mask), "size": {"width": w, "height": h}},
                    "crop_to_mask": True}
            resp = _request("POST", "/inpaint-v3", body)
            job = poll_job(resp["background_job_id"], interval=6)
            print(f"window {box}: {job['status']} {job.get('usage')}")
            if job["status"] != "completed":
                lr = job.get("last_response") or {}
                raise SystemExit("failed: " + str({k: v for k, v in lr.items() if k not in ("image", "images")})[:2000])
            lr = job.get("last_response") or {}
            item = lr.get("image") or (lr.get("images") or [None])[0]
            data = item.get("base64") if isinstance(item, dict) else item
            out = Image.open(io.BytesIO(base64.b64decode(data.split(",")[-1]))).convert("RGB").resize((w, h))
            # keep known pixels exactly, take generated ones elsewhere
            merged = Image.composite(img, out, k)
            canvas.paste(merged, box[:2])
            known.paste(255, box)
            canvas.save(dst)
    canvas.save(dst)
    print("wrote", dst, canvas.size)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5])
