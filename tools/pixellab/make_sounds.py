#!/usr/bin/env python3
"""Generate the game's sound effects and ambience loops with PixelLab
(POST /v2/sound-effects, documented in https://api.pixellab.ai/v2/openapi.json).

usage: make_sounds.py <repo_root> [name ...]   (default: every missing sound)

Writes assets/audio/<name>.wav. Existing files are kept (delete to redo).
Cost: ~0.614 generations per second of audio (see the endpoint docs).
Needs a PixelLab Tier 2 subscription (Tier 1 gets HTTP 403); until then the
game uses tools/audio/synth_sounds.py.
"""
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixellab_client import _request  # noqa: E402

SOUNDS = {
    # ambience loops (Audio.ambience)
    "amb_menu": ("cold wind blowing over ancient stone ruins on a mountain at dusk, distant low drone, lonely, no music, no birds", 20),
    "amb_hall": ("vast empty stone cathedral hall ambience, faint reverberant air, very low distant drone, eerie silence", 20),
    "amb_ritual": ("deep ominous ritual hum slowly rising, resonant metallic drone, faint whispering chant, dark fantasy", 20),
    "amb_void": ("muffled underwater-like void ambience, slow deep wind, distant warped echoes, floating in darkness", 20),
    "amb_meadow": ("quiet overcast meadow ambience, soft wind through tall grass, distant crows, calm and melancholic", 20),
    # one-shots (Audio.sfx)
    "clang": ("a single heavy iron gate slamming shut in a huge stone hall, long metallic echo", 3),
    "ritual": ("a magical ritual circle activating, bright resonant energy burst with a deep boom", 3),
    "void": ("a deep whoosh of falling into a dark void, wind rushing past, fading", 3),
    "getup": ("cloth rustling as a person slowly gets up from damp grass", 1.5),
    "ui_move": ("a very soft short wooden click for a menu cursor moving", 0.5),
    "ui_confirm": ("a soft metallic chime click confirming a menu selection, brass", 0.8),
    "ui_back": ("a soft muted low click for closing a menu", 0.6),
    "ui_open": ("a soft paper and brass rustle opening a pause menu", 0.8),
}


def make(root: Path, name: str) -> None:
    out = root / "assets/audio" / f"{name}.wav"
    if out.exists():
        print(f"{name}: exists, skipped")
        return
    prompt, seconds = SOUNDS[name]
    started = _request("POST", "/sound-effects", {"prompt": prompt, "seconds": seconds, "name": f"asthya_{name}"})
    sid = started.get("id") or started.get("sound_effect_id")
    print(f"{name}: started {sid} (quoted {started.get('quoted_generations')})")
    for _ in range(90):
        time.sleep(3)
        info = _request("GET", f"/sound-effects/{sid}")
        status = info.get("status")
        if info.get("audio_url"):
            out.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(info["audio_url"], timeout=120) as r:
                out.write_bytes(r.read())
            print(f"{name}: {info.get('duration_ms')} ms -> {out}")
            return
        if status in ("failed", "error"):
            raise SystemExit(f"{name}: failed {info}")
    raise SystemExit(f"{name}: timed out")


if __name__ == "__main__":
    root = Path(sys.argv[1])
    for n in sys.argv[2:] or list(SOUNDS):
        make(root, n)
