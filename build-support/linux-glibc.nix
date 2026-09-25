# Matched glibc for portable Linux builds and host OpenXR runtime libraries.
{ }:
let
  source = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "dc5d91f840324650bac8c379428c7037a416959a";
    narHash = "sha256-VaWGJ6+cIYN2erfSecbRV+4ljI185Ty2wUrXyvQbgOw=";
  };
  pkgs = import source { system = "x86_64-linux"; };
in pkgs.glibc.overrideAttrs (old: {
  version = "2.43";
  src = pkgs.fetchurl {
    url = "https://ftp.gnu.org/gnu/glibc/glibc-2.43.tar.xz";
    hash = "sha256-2chsa12920Oj4IJwxYRPxRd9GUQs9bjfS+fAfNX6ODE=";
  };
  configureFlags = (old.configureFlags or []) ++ [ "--disable-werror" ];
  patches = builtins.filter
    (patch: !(pkgs.lib.hasSuffix "-master.patch" (toString patch))
      && !(pkgs.lib.hasInfix "Revert-Remove-all-usage-of-BASH" (toString patch)))
    old.patches;
})
