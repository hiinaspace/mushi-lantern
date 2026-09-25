#!/usr/bin/env python3
"""Install a matched glibc and loader into a staged Linux friend package."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--glibc", required=True, type=Path)
    parser.add_argument("--patchelf", required=True)
    args = parser.parse_args()
    package = args.package.resolve()
    runtime = args.glibc.resolve()
    libdir = package / "lib"
    if not (package / "mushi-lantern.x86_64").is_file() or not libdir.is_dir():
        raise SystemExit("Expected a staged Linux friend package")
    sources = sorted(path for path in (runtime / "lib").glob("*.so*")
                     if path.is_file() and path.open("rb").read(4) == b"\x7fELF")
    names = {path.name for path in sources}
    required = {"ld-linux-x86-64.so.2", "libc.so.6", "libm.so.6"}
    if not required <= names:
        raise SystemExit(f"Incomplete glibc: {sorted(required - names)}")
    versions = subprocess.check_output(
        ["readelf", "--version-info", str(runtime / "lib/libc.so.6")], text=True)
    if "Name: GLIBC_ABI_GNU2_TLS" not in versions or "Name: GLIBC_2.43" not in versions:
        raise SystemExit("glibc must provide GLIBC_ABI_GNU2_TLS and GLIBC_2.43")
    manifest = {}
    for source in sources:
        target = libdir / source.name
        target.unlink(missing_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o755)
        if not source.name.startswith("ld-linux"):
            subprocess.run([args.patchelf, "--set-rpath", "$ORIGIN", str(target)], check=True)
        dynamic = subprocess.check_output(["readelf", "-d", str(target)], text=True)
        if "/nix/store/" in dynamic:
            raise SystemExit(f"Nix dependency remains in {target}")
        manifest[source.name] = hashlib.sha256(target.read_bytes()).hexdigest()
    (package / "glibc-runtime.json").write_text(
        json.dumps({"version": "2.43", "sha256": manifest}, indent=2) + "\n")
    inventory = package / "runtime-libraries.json"
    if inventory.exists():
        inventory.write_text(json.dumps(sorted(set(json.loads(inventory.read_text())) | names), indent=2) + "\n")
    print(f"Installed {len(sources)} matched glibc libraries into {package}")


if __name__ == "__main__":
    main()
