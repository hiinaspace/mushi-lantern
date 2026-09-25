#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_dir"
mkdir -p .local addons/godot-steam-audio/bin
nix build --impure --expr '
  let
    flake = builtins.getFlake "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a";
    pkgs = flake.legacyPackages.x86_64-linux.pkgsCross.mingwW64;
  in import ./build-support/steam-audio/windows.nix { inherit pkgs; }
' --cores "${JOBS:-4}" -o .local/steam-audio-windows "$@"

for file in libgodot-steam-audio.windows.template_release.x86_64.dll phonon.dll TrueAudioNext.dll GPUUtilities.dll phonon.lib libmcfgthread-2.dll; do
  install -m 0644 ".local/steam-audio-windows/bin/$file" "addons/godot-steam-audio/bin/$file"
done

printf 'Staged Windows x86_64 release Steam Audio extension and SDK DLLs.\n'
printf 'License notices are in build-support/steam-audio; export that directory with the package.\n'
