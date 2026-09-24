#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$project_dir/scripts/generate_audio_placeholders.py" --if-missing
fallback_godot="/home/s/.local/share/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
patched_godot="$project_dir/.local/godot/bin/godot4"

if [[ -n "${GODOT_BIN:-}" ]]; then
  godot_bin="$GODOT_BIN"
elif [[ -f "$project_dir/addons/godot-steam-audio/bin/libgodot-steam-audio.gdextension" ]]; then
  if [[ ! -f "$project_dir/addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_debug.x86_64.so" || ! -f "$project_dir/addons/godot-steam-audio/bin/libphonon.so" ]]; then
    echo "Steam Audio native libraries are missing. Run ./tools/build-steam-audio.sh." >&2
    exit 127
  fi
  if [[ ! -x "$patched_godot" ]]; then
    echo "Steam Audio needs patched Godot. Run ./tools/build-godot-audio.sh or set GODOT_BIN to a compatible patched engine." >&2
    exit 127
  fi
  godot_bin="$patched_godot"
elif command -v godot4 >/dev/null 2>&1; then
  godot_bin="$(command -v godot4)"
elif command -v godot >/dev/null 2>&1; then
  godot_bin="$(command -v godot)"
elif [[ -x "$fallback_godot" ]]; then
  godot_bin="$fallback_godot"
else
  echo "Godot 4 was not found. Set GODOT_BIN to the Godot 4.x executable." >&2
  exit 127
fi

if [[ ! -f "$project_dir/.godot/global_script_class_cache.cfg" ]]; then
  "$godot_bin" --headless --path "$project_dir" --editor --quit
fi

# The desktop session can stall on V-Sync presentation. Its 60 FPS cap must not
# throttle an XR runtime, which paces frames at the headset refresh rate.
engine_args=(--path "$project_dir" --disable-vsync)
launch_xr=false
for launch_arg in "$@"; do
  if [[ "$launch_arg" == --xr ]]; then
    launch_xr=true
    break
  fi
done
if [[ "$launch_xr" == false ]]; then
  engine_args+=(--xr-mode off --max-fps 60)
else
  engine_args+=(--xr-mode on)
fi
exec "$godot_bin" "${engine_args[@]}" -- "$@"
