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
  echo "Build the multiplayer release library first: nix develop ../prim --command ./multiplayer-native/build.sh release" >&2
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
if [[ ! -s "$project_dir/.local/godot-linux-template/bin/linux_release.x86_64" ]]; then
  "$project_dir/tools/build-godot-linux-template.sh"
fi
rm -f -- "$export_dir/mushi-lantern.x86_64" "$export_dir/mushi-lantern.pck"
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
mkdir -p "$package_dir/addons/terrain_3d/bin" \
  "$package_dir/addons/godot-steam-audio/bin" \
	"$package_dir/multiplayer-native/target/release" \
	"$package_dir/lib" \
  "$package_dir/licenses/fonts"
cp addons/terrain_3d/bin/libterrain.linux.release.x86_64.so \
  "$package_dir/addons/terrain_3d/bin/"
cp addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_release.x86_64.so \
  addons/godot-steam-audio/bin/libphonon.so "$package_dir/addons/godot-steam-audio/bin/"
cp "$multiplayer_library" "$package_dir/multiplayer-native/target/release/"
cp bin/linux/libonnxruntime.so bin/linux/libonnxruntime_providers_shared.so "$package_dir/lib/"
cp assets/fonts/DejaVu-LICENSE.txt "$package_dir/licenses/fonts/"
install -m 755 scripts/friend-desktop.sh scripts/friend-vr.sh "$package_dir/"
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
glibc_dir="${GLIBC_RUNTIME:-}"
if [[ -z "$glibc_dir" ]]; then
  mkdir -p .local
  glibc_dir="$(nix-build build-support/linux-glibc.nix -o .local/linux-glibc --cores "${JOBS:-4}")"
fi
python3 build-support/install-linux-glibc.py "$package_dir" --glibc "$glibc_dir" --patchelf "$patchelf_bin"
# With the bundled loader as /proc/self/exe, Godot looks for this PCK name
# next to the loader. This template disables --main-pack path overrides.
mv "$package_dir/mushi-lantern.pck" "$package_dir/lib/ld-linux-x86-64.so.pck"
# Godot also resolves unpacked GDExtension paths relative to /proc/self/exe.
mv "$package_dir/addons" "$package_dir/lib/addons"
mv "$package_dir/multiplayer-native" "$package_dir/lib/multiplayer-native"
glibc_source="$(nix-instantiate --eval --strict --json --expr '(import ./build-support/linux-glibc.nix {}).src.outPath' | python3 -c 'import json,sys; print(json.load(sys.stdin))')"
mkdir -p "$package_dir/licenses/glibc"
tar -xOf "$glibc_source" glibc-2.43/COPYING.LIB > "$package_dir/licenses/glibc/COPYING.LIB"
cat > "$package_dir/README-Linux.txt" <<'EOF'
Mushi Lantern Linux x86_64 friend build

Run ./friend-desktop.sh for keyboard and mouse, or ./friend-vr.sh with a
working OpenXR runtime selected and a headset connected. On Linux, the runtime
selection is normally provided by the user's OpenXR runtime configuration.
Both launchers use the same saved game data and start a fresh session. The
archive includes its standalone game executable; no Godot installation is
needed.

For multiplayer, open the menu, choose Room, enter the same code (at least
three characters) on each computer, then choose Host on one and Join on the
others. Codes are case-insensitive. The XR menu has a pointer keyboard. Mics
start muted; use the Voice tab to choose a mic, adjust levels, and unmute.
The two-hand broom flight gesture is enabled in multiplayer.

The game needs a Vulkan-capable graphics driver. Steam Audio's optional GPU
utilities may need OpenCL from the graphics driver. Game libraries and a
matched glibc 2.43 runtime are bundled; graphics drivers and the OpenXR
runtime come from your Linux install. Third-party notices are in the licenses
directory.

Portability smoke: tested on natto (Ubuntu 26.04.1 x86_64) with /nix hidden.
The game started under isolated Sway/Wayland, rendered through Vulkan 1.4.335
on AMD Radeon 780M (RADV PHOENIX), and exited cleanly after 240 frames. This
checks startup, rendering, and exit; it does not qualify headset behavior,
OpenXR, performance on other hardware, or VR comfort.
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
