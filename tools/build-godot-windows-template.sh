#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p .local
nix build --impure --expr '
  let
    flake = builtins.getFlake "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a";
    pkgs = flake.legacyPackages.x86_64-linux;
  in import ./build-support/godot/windows-template.nix { inherit pkgs; }
' --cores "${JOBS:-4}" -o .local/godot-windows-template "$@"

template="$project_dir/.local/godot-windows-template/bin/godot.windows.template_release.x86_64.exe"
test -s "$template"
printf 'Built patched Godot %s Windows release template: %s\n' \
  "$(nix eval --impure --raw --expr 'let f=builtins.getFlake "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a"; in f.legacyPackages.x86_64-linux.godot_4.version')" \
  "$template"
