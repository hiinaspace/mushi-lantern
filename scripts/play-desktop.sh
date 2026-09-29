#!/usr/bin/env bash
set -euo pipefail
package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$package_dir"
exec "$package_dir/mushi-lantern.x86_64" --xr-mode off -- --desktop "$@"
