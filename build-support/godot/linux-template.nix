# Upstream-style export template, not nixpkgs' system-library editor build.
{ pkgs }:
let
  baseline = import ../linux-release-toolchain.nix;
  accesskit = pkgs.fetchzip {
    url = "https://github.com/godotengine/godot-accesskit-c-static/releases/download/0.22.3/accesskit-c-0.22.3.zip";
    sha256 = "1fv0byxr6qj96x0frlwxrbnmxbf7mzpmcv3qh7m546aj5wgnlgsm";
  };
in baseline.stdenv.mkDerivation {
  pname = "mushi-godot-linux-template";
  version = pkgs.godot_4.version;
  src = pkgs.godot_4.src;
  patches = [ ./0001-retire-audio-before-extension-unload.patch ];
  nativeBuildInputs = [ pkgs.scons pkgs.pkg-config pkgs.wayland-scanner ];
  # Let SCons see the Nix compiler wrapper environment, without any of the
  # distro Godot patches that replace builtins or hard-code library paths.
  postPatch = ''
    substituteInPlace SConstruct --replace \
      'env = Environment(tools=[])' \
      'env = Environment(tools=[], ENV=os.environ)'
  '';
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    scons -j"$NIX_BUILD_CORES" platform=linuxbsd target=template_release \
      accesskit_sdk_path=${accesskit} \
      arch=x86_64 use_static_cpp=yes use_sowrap=yes debug_symbols=no lto=none
    runHook postBuild
  '';
  installPhase = ''
    mkdir -p "$out/bin"
    install -m755 bin/godot.linuxbsd.template_release.x86_64 "$out/bin/linux_release.x86_64"
  '';
}
