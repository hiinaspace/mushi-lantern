{ pkgs }:
let
  debug = import ./default.nix { inherit pkgs; };
in debug.overrideAttrs (old: {
  pname = "godot-steam-audio-linux-release";
  cmakeFlags = builtins.map
    (flag: if flag == "-DGODOTCPP_TARGET=template_debug" then "-DGODOTCPP_TARGET=template_release" else flag)
    old.cmakeFlags;
  installPhase = ''
    mkdir -p "$out/bin"
    cp libgodot-steam-audio.linux.template_release.x86_64.so "$out/bin/"
  '';
})
