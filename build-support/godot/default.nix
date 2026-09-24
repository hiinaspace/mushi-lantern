# Godot 4.7.2 from the pinned nixpkgs revision, with the audio teardown fix.
{ pkgs }:
pkgs.godot_4.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./0001-retire-audio-before-extension-unload.patch
  ];
  sconsFlags = builtins.filter (flag: flag != "debug_symbols=true") old.sconsFlags
    ++ [ "use_static_cpp=false" "debug_symbols=false" ];
})
