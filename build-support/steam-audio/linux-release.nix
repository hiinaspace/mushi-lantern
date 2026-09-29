{ pkgs }:
let
  baseline = import ../linux-release-toolchain.nix;
  debug = import ./default.nix { inherit pkgs; inherit (baseline) stdenv; };
in debug.overrideAttrs (old: {
  pname = "godot-steam-audio-linux-release";
  nativeBuildInputs = with baseline; [ cmake ninja python3 autoPatchelfHook ];
  cmakeFlags = builtins.map
    (flag: if flag == "-DGODOTCPP_TARGET=template_debug" then "-DGODOTCPP_TARGET=template_release" else flag)
    old.cmakeFlags;
  installPhase = ''
    mkdir -p "$out/bin"
    cp libgodot-steam-audio.linux.template_release.x86_64.so "$out/bin/"
  '';
})
