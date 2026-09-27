#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_dir"
godot_bin="${GODOT_BIN:-$project_dir/.local/godot/bin/godot4}"
if [[ ! -x "$godot_bin" ]]; then
  godot_bin="$(command -v godot4 || command -v godot || true)"
fi
if [[ -z "$godot_bin" || ! -x "$godot_bin" ]]; then
  echo "Godot 4.7.2 is required; set GODOT_BIN to its editor binary." >&2
  exit 127
fi

python3 scripts/generate_audio_placeholders.py --if-missing
./tools/build-godot-windows-template.sh
./build-support/steam-audio/build-windows.sh
./multiplayer-native/build.sh windows-release
python3 tools/fetch-viseme-runtime.py --platform windows
windows_prefix="${MUSHI_WINDOWS_MINGW_PREFIX:-$HOME/code/prim/.local/windows/msys/mingw64}"
if [[ ! -f "$windows_prefix/bin/libopus-0.dll" ]]; then
  echo "Windows Opus DLL is missing: $windows_prefix/bin/libopus-0.dll" >&2
  exit 1
fi

export_dir="$project_dir/artifacts/export/windows"
package_root="$export_dir/package"
package_dir="$package_root/Mushi Lantern Windows"
zip_path="$export_dir/Mushi-Lantern-Windows.zip"
mkdir -p "$export_dir"
"$godot_bin" --headless --path "$project_dir" --export-release 'Windows OpenXR'

for file in mushi-lantern.exe mushi-lantern.pck \
  libterrain.windows.release.x86_64.dll \
  libgodot-steam-audio.windows.template_release.x86_64.dll \
  mushi_multiplayer_native.dll \
  phonon.dll TrueAudioNext.dll GPUUtilities.dll libmcfgthread-2.dll phonon.lib; do
  if [[ ! -f "$export_dir/$file" ]]; then
    echo "Windows export is missing required file: $file" >&2
    exit 1
  fi
done
if [[ ! -f bin/windows/onnxruntime.dll ]]; then
  echo "Windows ONNX Runtime DLL is missing" >&2
  exit 1
fi

rm -rf -- "$package_root"
mkdir -p "$package_dir/licenses/terrain3d" \
  "$package_dir/licenses/godot-xr-tools" \
  "$package_dir/licenses/godot-steam-audio" \
  "$package_dir/licenses/godot-cpp" \
  "$package_dir/licenses/steam-audio-sdk" \
  "$package_dir/licenses/mcfgthread" \
  "$package_dir/licenses/forest" \
  "$package_dir/licenses/renik" \
  "$package_dir/licenses/rpg-animations" \
  "$package_dir/licenses/fonts" \
  "$package_dir/licenses/multiplayer-native" \
  "$package_dir/licenses/onnxruntime" \
  "$package_dir/licenses/opus" \
  "$package_dir/licenses/godot-engine"

cp "$export_dir/mushi-lantern.exe" "$export_dir/mushi-lantern.pck" \
  "$export_dir"/*.dll "$export_dir/phonon.lib" "$package_dir/"
# GDExtension loads this library by the res:// path declared in
# mushi_multiplayer.gdextension. Keep a loose copy at that package-relative
# path; the root copy remains alongside the other runtime DLLs for Windows
# dependency resolution.
windows_extension_dir="$package_dir/multiplayer-native/target/x86_64-pc-windows-gnu/release"
mkdir -p "$windows_extension_dir"
cp "$export_dir/mushi_multiplayer_native.dll" \
  "$windows_extension_dir/mushi_multiplayer_native.dll"
cp bin/windows/onnxruntime.dll "$package_dir/"
cp bin/windows/onnxruntime_providers_shared.dll "$package_dir/"
cp "$windows_prefix/bin/libopus-0.dll" "$package_dir/"
cp scripts/friend-desktop.bat scripts/friend-vr.bat "$package_dir/"
cp addons/terrain_3d/LICENSE.txt "$package_dir/licenses/terrain3d/"
cp addons/godot-xr-tools/LICENSE "$package_dir/licenses/godot-xr-tools/"
cp build-support/steam-audio/UPSTREAM_EXTENSION_LICENSE.md "$package_dir/licenses/godot-steam-audio/"
cp build-support/steam-audio/GODOT_CPP_LICENSE.md "$package_dir/licenses/godot-cpp/"
cp build-support/steam-audio/STEAM_AUDIO_SDK_LICENSE.md "$package_dir/licenses/steam-audio-sdk/"
cp build-support/steam-audio/STEAM_AUDIO_SDK_THIRDPARTY.md "$package_dir/licenses/steam-audio-sdk/"
cp .local/steam-audio-windows/share/licenses/mcfgthread/LICENSE.md \
  .local/steam-audio-windows/share/licenses/mcfgthread/licenses/*.txt \
  "$package_dir/licenses/mcfgthread/"
cp assets/forest/PROVENANCE.md assets/forest/licenses/* \
  "$package_dir/licenses/forest/"
cp addons/renik/LICENSE.txt "$package_dir/licenses/renik/"
cp assets/animations/LICENSE assets/animations/README.md "$package_dir/licenses/rpg-animations/"
cp assets/fonts/DejaVu-LICENSE.txt "$package_dir/licenses/fonts/"
cp multiplayer-native/vendor/godot-network-audio/LICENSE \
  "$package_dir/licenses/multiplayer-native/godot-network-audio-LICENSE"
cp multiplayer-native/viseme-model/LICENSE \
  "$package_dir/licenses/multiplayer-native/viseme-model-LICENSE"
cp multiplayer-native/viseme-model/NOTICE.md \
  multiplayer-native/viseme-model/THIRD_PARTY_NOTICES.md \
  "$package_dir/licenses/multiplayer-native/"
cp .local/viseme-runtime/windows/LICENSE \
  .local/viseme-runtime/windows/ThirdPartyNotices.txt \
  "$package_dir/licenses/onnxruntime/"
cp "$windows_prefix/share/licenses/opus/COPYING" "$package_dir/licenses/opus/"
cp build-support/godot/licenses/LICENSE.txt \
  build-support/godot/licenses/COPYRIGHT.txt \
  build-support/godot/licenses/AUTHORS.md \
  "$package_dir/licenses/godot-engine/"

cat > "$package_dir/README-Windows.txt" <<'EOF'
Mushi Lantern Windows x86_64 friend build

Run friend-desktop.bat for keyboard and mouse, or friend-vr.bat with a working
Windows OpenXR runtime selected and a headset connected. Both launchers use
the same saved game data and start a fresh session.

For multiplayer, open the menu, choose Room, enter the same code (at least
three characters) on each computer, then choose Host on one and Join on the
others. Codes are case-insensitive. The XR menu has a pointer keyboard. Mics
start muted; use the Voice tab to choose a mic, adjust levels, and unmute.
The two-hand broom flight gesture is enabled in multiplayer.

This package is exported on Linux. It has not been validated on a native
Windows headset.

The Steam Audio SDK's optional TrueAudioNext/GPU utilities import the Microsoft
Visual C++ 2015-2022 x64 runtime and OpenCL.dll. Install the latest supported
Microsoft Visual C++ Redistributable (x64) if it is missing. OpenCL.dll is
provided by the graphics driver. The Microsoft redistributable is not bundled.

Third-party license notices are in the licenses directory.
EOF

python3 - "$package_root" "$package_dir" "$zip_path" <<'PY'
from pathlib import Path
import sys
from zipfile import ZIP_DEFLATED, ZipFile

root, package, archive = map(Path, sys.argv[1:])
archive.unlink(missing_ok=True)
with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=1) as zf:
    for path in sorted(package.rglob("*")):
        if path.is_file():
            zf.write(path, path.relative_to(root))
print(f"Packaged {package} -> {archive}")
PY
