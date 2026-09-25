#!/usr/bin/env bash
set -euo pipefail
package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$package_dir"
runtime_library_path="$package_dir/lib:$package_dir/addons/godot-steam-audio/bin"
for directory in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /usr/lib /lib64 /lib /run/opengl-driver/lib; do
  if [[ -d "$directory" ]]; then runtime_library_path+=":$directory"; fi
done
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then runtime_library_path+=":$LD_LIBRARY_PATH"; fi
export LD_LIBRARY_PATH="$runtime_library_path"
if [[ -z "${ALSA_CONFIG_PATH:-}" && -f /usr/share/alsa/alsa.conf ]]; then
  export ALSA_CONFIG_PATH=/usr/share/alsa/alsa.conf
fi
if [[ -x "$package_dir/mushi-lantern.x86_64" ]]; then
  exec "$package_dir/mushi-lantern.x86_64" --xr-mode on -- --xr "$@"
fi
godot_bin="${GODOT_BIN:-$(command -v godot4 || command -v godot || true)}"
if [[ -z "$godot_bin" || ! -x "$godot_bin" ]]; then
  echo "Set GODOT_BIN to a compatible Godot 4.7.2 executable to run this PCK package." >&2
  exit 127
fi
exec "$godot_bin" --path "$package_dir" --main-pack "$package_dir/mushi-lantern.pck" \
  --xr-mode on -- --xr "$@"
