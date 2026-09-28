{
  description = "Mushi Lantern native development tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/dc5d91f840324650bac8c379428c7037a416959a";

  outputs = { nixpkgs, ... }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        cargo rustc rustfmt clippy pkg-config cmake clang
        python3 patchelf binutils zip unzip
      ];
      buildInputs = with pkgs; [ opus openssl alsa-lib ];
      LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.opus ];
    };
  };
}
