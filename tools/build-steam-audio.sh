#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p .local addons/godot-steam-audio/bin
nix build --impure --expr '
  let
    pkgs = import (builtins.getFlake "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a").outPath { system = "x86_64-linux"; };
  in import ./build-support/steam-audio { inherit pkgs; }
' --cores "${JOBS:-4}" -o .local/steam-audio "$@"
cp -L .local/steam-audio/bin/libgodot-steam-audio.linux.template_debug.x86_64.so addons/godot-steam-audio/bin/
cp -L .local/steam-audio/bin/libphonon.so addons/godot-steam-audio/bin/
