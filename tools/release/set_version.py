#!/usr/bin/env python3
"""Set the game version everywhere it lives and recompute the base fingerprint.

usage: set_version.py X.Y.Z

- project.godot     application/config/version
- export_presets    Android version/name + version/code (X*10000 + Y*100 + Z,
                    always increasing so Android accepts the update)
- build_info.json   {"version", "base_id"} read by the launcher

base_id identifies the part of the game that a downloaded content pack can NOT
replace at runtime: engine/project settings (project.godot, input map...),
export settings, autoload scripts and the launcher itself. Releases with the
same base_id are delivered as hot-loaded .pck files (no restart, no reinstall);
a different base_id makes the launcher do a full update (new exe / APK).
Version numbers are excluded so a version bump alone keeps the same base.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE_DIRS = ["scripts/launcher"]
BASE_FILES = ["scenes/launcher.tscn"]
# Baked into the exe / APK at export time (app icons): a change needs a full update.
BASE_BINARY = ["icon.png", "assets/branding"]


def strip_versions(text: str) -> str:
    text = re.sub(r'^config/version=".*"$', "", text, flags=re.M)
    text = re.sub(r'^version/(name|code)=.*$', "", text, flags=re.M)
    return text


def base_id() -> str:
    h = hashlib.sha256()
    project = (ROOT / "project.godot").read_text()

    def add(rel: str, content: str) -> None:
        h.update(rel.encode() + b"\0" + content.replace("\r\n", "\n").encode() + b"\0")

    add("project.godot", strip_versions(project))
    add("export_presets.cfg", strip_versions((ROOT / "export_presets.cfg").read_text()))
    files = set(BASE_FILES)
    for d in BASE_DIRS:
        files |= {str(p.relative_to(ROOT)) for p in (ROOT / d).rglob("*.gd")}
    for m in re.finditer(r'^\w+="\*?res://([^"]+)"$', project.split("[autoload]", 1)[1].split("\n[", 1)[0], re.M):
        files.add(m.group(1))
    for rel in sorted(files):
        add(rel, (ROOT / rel).read_text())
    binaries = []
    for b in BASE_BINARY:
        p = ROOT / b
        binaries += sorted(p.rglob("*")) if p.is_dir() else [p]
    for p in binaries:
        if p.is_file() and p.suffix != ".import":
            h.update(str(p.relative_to(ROOT)).encode() + b"\0" + hashlib.sha256(p.read_bytes()).digest())
    return h.hexdigest()[:16]


def main(v: str) -> None:
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", v.strip())
    if not m:
        sys.exit(f"invalid version {v!r}, expected X.Y.Z")
    major, minor, patch = map(int, m.groups())
    version = f"{major}.{minor}.{patch}"
    code = major * 10000 + minor * 100 + patch

    p = ROOT / "project.godot"
    s, n = re.subn(r'^config/version=".*"$', f'config/version="{version}"', p.read_text(), flags=re.M)
    assert n == 1, "config/version not found in project.godot"
    p.write_text(s)

    p = ROOT / "export_presets.cfg"
    s = p.read_text()
    s, n1 = re.subn(r'^version/name=".*"$', f'version/name="{version}"', s, flags=re.M)
    s, n2 = re.subn(r"^version/code=\d+$", f"version/code={code}", s, flags=re.M)
    assert n1 == 1 and n2 == 1, "Android version fields not found in export_presets.cfg"
    p.write_text(s)

    bid = base_id()
    (ROOT / "build_info.json").write_text(json.dumps({"version": version, "base_id": bid}, indent=2) + "\n")
    print(f"version {version} (android code {code}), base_id {bid}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
