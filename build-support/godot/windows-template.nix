# Godot 4.7.2 MinGW template with this project's Steam Audio teardown fix.
{ pkgs }:
let
  cross = pkgs.pkgsCross.mingwW64;
  source = pkgs.godot_4.src;
in cross.stdenv.mkDerivation {
  pname = "godot-windows-steam-audio-template";
  version = pkgs.godot_4.version;
  src = source;
  patches = [ ./0001-retire-audio-before-extension-unload.patch ];

  nativeBuildInputs = [ pkgs.scons pkgs.pkg-config ];
  buildInputs = [ cross.windows.mcfgthreads ];
  NIX_CFLAGS_COMPILE = "-I${cross.windows.mcfgthreads.dev}/include";
  NIX_LDFLAGS = "-L${cross.windows.mcfgthreads}/lib";
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # SCons expects a MinGW prefix directory. Keep the pinned Nix wrappers,
    # but use GCC's LTO-aware archive tools as in Prim's tested cross route.
    mingw_prefix="$TMPDIR/mingw-prefix"
    mkdir -p "$mingw_prefix/bin"
    for tool in ${cross.stdenv.cc}/bin/*; do
      ln -s "$tool" "$mingw_prefix/bin/$(basename "$tool")"
    done
    ln -sf ${cross.stdenv.cc.cc}/bin/x86_64-w64-mingw32-gcc-ar \
      "$mingw_prefix/bin/x86_64-w64-mingw32-gcc-ar"
    ln -sf ${cross.stdenv.cc.cc}/bin/x86_64-w64-mingw32-gcc-ranlib \
      "$mingw_prefix/bin/x86_64-w64-mingw32-gcc-ranlib"
    export MINGW_PREFIX="$mingw_prefix"

    scons \
      platform=windows \
      arch=x86_64 \
      target=template_release \
      use_mingw=yes \
      use_static_cpp=yes \
      d3d12=no \
      opengl3=yes \
      debug_symbols=no \
      lto=none \
      production=yes \
      precision=single \
      module_mono_enabled=no \
      winrt=no \
      accesskit=no \
      ccflags=-I${cross.windows.mcfgthreads.dev}/include \
      linkflags=-L${cross.windows.mcfgthreads}/lib \
      -j"$NIX_BUILD_CORES"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -m 0755 bin/godot.windows.template_release.x86_64.exe \
      "$out/bin/godot.windows.template_release.x86_64.exe"
    runHook postInstall
  '';
}
