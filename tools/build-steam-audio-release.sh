#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p .local addons/godot-steam-audio/bin
nix build --impure --expr '
  let
    pkgs = import (builtins.getFlake "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a").outPath { system = "x86_64-linux"; };
  in import ./build-support/steam-audio/linux-release.nix { inherit pkgs; }
' --cores "${JOBS:-4}" -o .local/steam-audio-linux-release "$@"
cp -L .local/steam-audio-linux-release/bin/libgodot-steam-audio.linux.template_release.x86_64.so \
  addons/godot-steam-audio/bin/
if [[ -f .local/steam-audio/bin/libphonon.so ]]; then
  cp -L .local/steam-audio/bin/libphonon.so addons/godot-steam-audio/bin/
fi
[[ -f addons/godot-steam-audio/bin/libphonon.so ]] || {
  echo "libphonon.so is missing; run ./tools/build-steam-audio.sh first." >&2
  exit 1
}
printf 'Staged Linux x86_64 release Steam Audio extension.\n'
