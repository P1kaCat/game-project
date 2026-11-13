#!/usr/bin/env bash
# Build the release files the in-game updater downloads.
#
#   tools/release/build.sh [out_dir]          (default: build/release)
#
# Produces:  <out>/IsoRPG-windows.zip   full Windows build (IsoRPG.exe, data embedded)
#            <out>/IsoRPG.apk           full Android build (arm64, debug-signed)
#            <out>/game-windows.pck     game content, hot-loaded by the launcher
#            <out>/game-android.pck
#            <out>/manifest.json        version, base_id, pack names + SHA-256
# Run tools/release/set_version.py first (version + base_id in build_info.json).
#
# Needs Godot 4.7 + export templates, JDK 17+, Android SDK build-tools.
# Android signing key: the Godot editor setting, or the environment variables
# GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD (used in CI).
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
OUT="${1:-build/release}"
rm -rf "$OUT" && mkdir -p "$OUT/windows"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/windows/IsoRPG.exe"
test -s "$OUT/windows/IsoRPG.exe" || { echo "Windows export failed" >&2; exit 1; }
python3 - "$OUT" <<'PY'
import sys, zipfile, pathlib
out = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(out / "IsoRPG-windows.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.write(out / "windows" / "IsoRPG.exe", "IsoRPG.exe")
PY
rm -rf "$OUT/windows"

"$GODOT" --headless --path . --export-debug "Android" "$OUT/IsoRPG.apk"
test -s "$OUT/IsoRPG.apk" || { echo "Android export failed" >&2; exit 1; }
rm -f "$OUT/IsoRPG.apk.idsig"

"$GODOT" --headless --path . --export-pack "Windows Desktop" "$OUT/game-windows.pck"
"$GODOT" --headless --path . --export-pack "Android" "$OUT/game-android.pck"
python3 - "$OUT" <<'PY'
import hashlib, json, pathlib, sys
out = pathlib.Path(sys.argv[1])
info = json.loads(pathlib.Path("build_info.json").read_text())
packs = {}
for key in ("windows", "android"):
    p = out / f"game-{key}.pck"
    packs[key] = {"name": p.name, "size": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
(out / "manifest.json").write_text(json.dumps({**info, "packs": packs}, indent=2) + "\n")
print(json.dumps({**info, "packs": packs}, indent=2))
PY

if [ -n "${ANDROID_HOME:-}" ]; then
  BT="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)"
  "$BT/apksigner" verify --print-certs "$OUT/IsoRPG.apk" | grep -E "certificate (DN|SHA-256)"
fi
ls -la "$OUT"
