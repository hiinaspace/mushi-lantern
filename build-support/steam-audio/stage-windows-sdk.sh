#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_dir"
mkdir -p .local addons/godot-steam-audio/bin
nix build --impure --expr '
  let
    flake = builtins.getFlake "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a";
    pkgs = flake.legacyPackages.x86_64-linux;
  in import ./build-support/steam-audio/windows-sdk.nix { inherit pkgs; }
' --cores "${JOBS:-2}" -o .local/steam-audio-windows-sdk "$@"

for file in phonon.dll TrueAudioNext.dll GPUUtilities.dll phonon.lib; do
  install -m 0644 ".local/steam-audio-windows-sdk/bin/$file" "addons/godot-steam-audio/bin/$file"
done

printf 'Staged the pinned Windows x86_64 Steam Audio runtime DLLs.\n'
printf 'SDK license notices remain in build-support/steam-audio and must ship with the package.\n'
