#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"
case "${1:-release}" in
  debug) cargo build ;;
  release) cargo build --release ;;
  test) cargo test ;;
  *) echo "usage: $0 [debug|release|test]" >&2; exit 2 ;;
esac
