#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"
case "${1:-release}" in
  debug) cargo build --locked ;;
  release) cargo build --locked --release ;;
  test) cargo test --locked ;;
  windows-debug|windows-release)
    target=x86_64-pc-windows-gnu
    windows_prefix="${MUSHI_WINDOWS_MINGW_PREFIX:-$SCRIPT_DIR/../.local/windows/msys/mingw64}"
    if [[ -d "$windows_prefix/lib/pkgconfig" ]]; then
      export PKG_CONFIG_ALLOW_CROSS=1
      export PKG_CONFIG_PATH="$windows_prefix/lib/pkgconfig"
      export PKG_CONFIG_LIBDIR="$windows_prefix/lib/pkgconfig"
      export PKG_CONFIG_SYSROOT_DIR="$(dirname "$windows_prefix")"
      export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-L$windows_prefix/lib"
      windows_root="$(dirname "$(dirname "$windows_prefix")")"
      if [[ -d "$windows_root/toolchain/bin" ]]; then
        export PATH="$windows_root/toolchain/bin:$PATH"
      fi
      if [[ -z "${RUSTC:-}" && -x "$windows_root/rustc" ]]; then
        export RUSTC="$windows_root/rustc"
      fi
    fi
    if [[ ! -d "$("${RUSTC:-rustc}" --print target-libdir --target "$target")" ]]; then
      echo "Rust standard library for $target is missing from the selected toolchain" >&2
      exit 1
    fi
    if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
      echo "MinGW x86_64-w64-mingw32-gcc is required" >&2
      exit 1
    fi
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc
    export CC_x86_64_pc_windows_gnu=x86_64-w64-mingw32-gcc
    export AR_x86_64_pc_windows_gnu=x86_64-w64-mingw32-ar
    # Godot and Iroh expose many symbols; MinGW auto-export otherwise exceeds
    # the PE ordinal limit. Rust's explicit exports include the GDExtension entry.
    export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,--exclude-all-symbols"
    if [[ "$1" == windows-release ]]; then
      cargo build --locked --target "$target" --release
    else
      cargo build --locked --target "$target"
    fi
    ;;
  *) echo "usage: $0 [debug|release|test|windows-debug|windows-release]" >&2; exit 2 ;;
esac
