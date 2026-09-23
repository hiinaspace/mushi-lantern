#!/usr/bin/env bash
set -euo pipefail

# Reproduce the PC VR addon subset from the pinned upstream release.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$(mktemp -t mushi-terrain3d-XXXXXX.zip)"
trap 'test -f "$archive" && unlink "$archive"' EXIT
curl --fail --location --silent --show-error \
  'https://github.com/TokisanGames/Terrain3D/releases/download/v1.0.2-stable/Terrain3D_v1.0.2-stable.zip' \
  --output "$archive"
printf '%s  %s\n' 'a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2' "$archive" | sha256sum --check
python3 - "$archive" "$repo_root" <<'PY'
import pathlib
import sys
import zipfile

archive = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive) as source:
    for entry in source.infolist():
        name = entry.filename
        if not name.startswith("addons/terrain_3d/") or name.endswith("/"):
            continue
        if "/extras/" in name:
            continue
        if "/bin/" in name and not name.endswith((
            "linux.debug.x86_64.so", "linux.release.x86_64.so",
            "windows.debug.x86_64.dll", "windows.release.x86_64.dll",
        )):
            continue
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read(entry))
print("Terrain3D 1.0.2 PC VR addon installed")
PY
