# Linux x86_64 template with this project's Steam Audio teardown fix.
{ pkgs }:
let
  editor = import ./default.nix { inherit pkgs; };
in editor.overrideAttrs (old: {
  pname = "godot-linux-steam-audio-template";
  outputs = [ "out" ];
  sconsFlags = builtins.map
    (flag:
      if flag == "target=editor" then "target=template_release"
      else if flag == "debug_symbols=true" then "debug_symbols=false"
      else flag)
    old.sconsFlags ++ [ "lto=none" ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -m 0755 bin/godot.linuxbsd.template_release.x86_64 \
      "$out/bin/linux_release.x86_64"
    runHook postInstall
  '';
})
