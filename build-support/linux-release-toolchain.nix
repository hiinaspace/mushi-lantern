# An older glibc sysroot keeps exports usable on ordinary Ubuntu/Arch systems.
# Development/editor builds continue to use the main, newer nixpkgs pin.
(builtins.getFlake "github:NixOS/nixpkgs/ea4c80b39be4c09702b0cb3b42eab59e2ba4f24b").legacyPackages.x86_64-linux
