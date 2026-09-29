#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
godot_bin="${GODOT_BIN:-$project_dir/.local/godot/bin/godot4}"
if [[ ! -x "$godot_bin" ]]; then
  godot_bin="$(command -v godot4 || command -v godot || true)"
fi
if [[ -z "$godot_bin" || ! -x "$godot_bin" ]]; then
  echo "Godot 4.7.2 editor is required; set GODOT_BIN to its executable." >&2
  exit 127
fi

extension_dir="$project_dir/addons/godot-steam-audio/bin"
for file in libgodot-steam-audio.linux.template_release.x86_64.so libphonon.so; do
  if [[ ! -f "$extension_dir/$file" ]]; then
    echo "Linux release export needs $extension_dir/$file; the debug extension cannot be substituted." >&2
    exit 1
  fi
done
multiplayer_library="$project_dir/multiplayer-native/target/release/libmushi_multiplayer_native.so"
if [[ ! -s "$multiplayer_library" ]]; then
  echo "Build the multiplayer release library first: nix develop . --command ./multiplayer-native/build.sh release" >&2
  exit 1
fi
if [[ ! -s "$project_dir/bin/linux/libonnxruntime.so" ]]; then
  echo "Stage the voice runtime first: ./tools/fetch-viseme-runtime.py --platform linux" >&2
  exit 1
fi

python3 scripts/generate_audio_placeholders.py --if-missing
export_dir="$project_dir/artifacts/export/linux"
package_dir="$export_dir/package/Mushi-Lantern-Linux"
archive="$export_dir/Mushi-Lantern-Linux.zip"
mkdir -p "$export_dir"
"$project_dir/tools/build-godot-linux-template.sh"
rm -f -- "$export_dir/mushi-lantern.x86_64" "$export_dir/mushi-lantern.pck" \
  "$export_dir/libterrain.linux.release.x86_64.so" \
  "$export_dir/libgodot-steam-audio.linux.template_release.x86_64.so" \
  "$export_dir/libphonon.so" "$export_dir/libmushi_multiplayer_native.so"
"$godot_bin" --headless --path "$project_dir" --export-release 'Linux Desktop'
[[ -s "$export_dir/mushi-lantern.x86_64" ]] || { echo "Linux release export missing standalone executable" >&2; exit 1; }
[[ -s "$export_dir/mushi-lantern.pck" ]] || { echo "Linux release export missing mushi-lantern.pck" >&2; exit 1; }

rm -rf -- "$package_dir"
mkdir -p "$package_dir/licenses/terrain3d" \
  "$package_dir/licenses/godot-xr-tools" \
  "$package_dir/licenses/godot-steam-audio" \
  "$package_dir/licenses/godot-cpp" \
  "$package_dir/licenses/steam-audio-sdk" \
  "$package_dir/licenses/forest" \
  "$package_dir/licenses/renik" \
  "$package_dir/licenses/rpg-animations" \
	"$package_dir/licenses/multiplayer-voice" \
	"$package_dir/licenses/viseme-model" \
	"$package_dir/licenses/onnxruntime" \
  "$package_dir/licenses/godot-engine"
cp "$export_dir/mushi-lantern.pck" "$package_dir/"
install -m 755 "$export_dir/mushi-lantern.x86_64" "$package_dir/"
# Use Godot's normal exported library layout; its Unix loader resolves these
# beside the executable when the original res:// source path is absent.
mkdir -p "$package_dir/lib" "$package_dir/licenses/fonts"
for file in libterrain.linux.release.x86_64.so \
  libgodot-steam-audio.linux.template_release.x86_64.so \
  libphonon.so libmushi_multiplayer_native.so; do
  cp "$export_dir/$file" "$package_dir/"
done
cp bin/linux/libonnxruntime.so bin/linux/libonnxruntime_providers_shared.so "$package_dir/lib/"
cp assets/fonts/DejaVu-LICENSE.txt assets/fonts/KleeOne-OFL.txt \
  "$package_dir/licenses/fonts/"
install -m 755 scripts/play-desktop.sh scripts/play-vr.sh "$package_dir/"
mkdir -p "$package_dir/licenses/opus"
cp build-support/OPUS-COPYING "$package_dir/licenses/opus/COPYING"
cp UNLICENSE LICENSES.md CREDITS.md "$package_dir/"
mkdir -p "$package_dir/licenses/vrm" "$package_dir/licenses/mtoon"
cp addons/vrm/LICENSE "$package_dir/licenses/vrm/"
cp addons/Godot-MToon-Shader/LICENSE "$package_dir/licenses/mtoon/"
cp addons/godot-xr-tools/hands/License.md "$package_dir/licenses/godot-xr-tools/hands-License.md"
cp addons/godot-xr-tools/editor/icons/LICENSE "$package_dir/licenses/godot-xr-tools/icons-LICENSE"
cp addons/terrain_3d/LICENSE.txt "$package_dir/licenses/terrain3d/"
cp addons/godot-xr-tools/LICENSE "$package_dir/licenses/godot-xr-tools/"
cp build-support/steam-audio/UPSTREAM_EXTENSION_LICENSE.md "$package_dir/licenses/godot-steam-audio/"
cp build-support/steam-audio/GODOT_CPP_LICENSE.md "$package_dir/licenses/godot-cpp/"
cp build-support/steam-audio/STEAM_AUDIO_SDK_LICENSE.md \
  build-support/steam-audio/STEAM_AUDIO_SDK_THIRDPARTY.md "$package_dir/licenses/steam-audio-sdk/"
cp assets/forest/PROVENANCE.md assets/forest/licenses/* "$package_dir/licenses/forest/"
cp addons/renik/LICENSE.txt "$package_dir/licenses/renik/"
cp assets/animations/LICENSE assets/animations/README.md "$package_dir/licenses/rpg-animations/"
cp multiplayer-native/vendor/godot-network-audio/LICENSE "$package_dir/licenses/multiplayer-voice/"
cp multiplayer-native/viseme-model/LICENSE multiplayer-native/viseme-model/NOTICE.md \
	multiplayer-native/viseme-model/THIRD_PARTY_NOTICES.md "$package_dir/licenses/viseme-model/"
cp .local/viseme-runtime/linux/LICENSE .local/viseme-runtime/linux/ThirdPartyNotices.txt \
	"$package_dir/licenses/onnxruntime/"
cp build-support/godot/licenses/LICENSE.txt build-support/godot/licenses/COPYRIGHT.txt \
  build-support/godot/licenses/AUTHORS.md "$package_dir/licenses/godot-engine/"
patchelf_bin="$(command -v patchelf || true)"
if [[ -z "$patchelf_bin" ]]; then
  patchelf_out="$(nix eval --raw --impure --expr 'let f = builtins.getFlake "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a"; in f.legacyPackages.x86_64-linux.patchelf.outPath')"
  patchelf_bin="$patchelf_out/bin/patchelf"
fi
python3 build-support/bundle-linux-runtime.py "$package_dir" --patchelf "$patchelf_bin"
cat > "$package_dir/README-Linux.txt" <<'EOF'
Mushi Lantern — Linux x86_64

Run ./play-desktop.sh for keyboard and mouse, or ./play-vr.sh with a working
OpenXR runtime selected and a headset connected. Both scripts just select a
play mode. The executable can also be run directly; Godot is included.

Requires a normal glibc-based Linux desktop: glibc 2.35 or newer, libstdc++
with GLIBCXX_3.4.29 / CXXABI_1.3.11 or newer, Vulkan graphics drivers, and
ordinary X11/Wayland and audio libraries. VR requires your own OpenXR runtime.
NixOS users can use an FHS compatibility environment such as steam-run.
No private glibc, systemd, SDL or desktop-service libraries are bundled.

The additional native libraries provide Terrain3D, Steam Audio, multiplayer
and voice, and ONNX-based avatar lip sync. Iroh and the voice Opus codec are
compiled into the multiplayer extension. lib/ contains the ONNX runtime.
See native-libraries.json for library purposes, dependencies and ABI checks;
third-party notices are in licenses/.

For experimental peer-to-peer multiplayer, open Multiplayer, enter the same
code (at least three characters) on each computer, then choose Host on one
and Join on the others. Codes are case-insensitive. Mics start muted; use
Settings > Voice to choose a mic, adjust levels, and unmute.

EOF

python3 - "$package_dir" "$archive" <<'PY'
from pathlib import Path
import shutil
import sys
import time
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

package, archive = map(Path, sys.argv[1:])
archive.unlink(missing_ok=True)
with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=1) as zf:
    for path in sorted(package.rglob("*")):
        if path.is_file():
            info = ZipInfo(str(path.relative_to(package.parent)))
            timestamp = max(315532800, int(path.stat().st_mtime))
            info.date_time = time.gmtime(timestamp)[:6]
            info.compress_type = ZIP_DEFLATED
            info.external_attr = (path.stat().st_mode & 0xFFFF) << 16
            with path.open("rb") as source, zf.open(info, "w") as target:
                shutil.copyfileobj(source, target)
print(f"Packaged {package} -> {archive}")
PY
