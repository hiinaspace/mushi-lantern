#!/usr/bin/env python3
"""Normalize and audit an explicit set of Linux game libraries; never copy OS libs."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

# These are the ordinary host ABI, not a redistributable dependency closure.
HOST = {
    "libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "librt.so.1",
    "libresolv.so.2", "libutil.so.1", "ld-linux-x86-64.so.2",
    "libstdc++.so.6", "libgcc_s.so.1",
}
FILES = {
    "mushi-lantern.x86_64": "Godot 4.7.2 with audio teardown fix; upstream built-in dependencies",
    "libterrain.linux.release.x86_64.so": "Terrain3D terrain rendering",
    "libgodot-steam-audio.linux.template_release.x86_64.so": "Godot Steam Audio integration",
    "libphonon.so": "Valve Steam Audio SDK for spatial audio",
    "libmushi_multiplayer_native.so": "Multiplayer (Iroh/pkarr), voice (Opus), and avatar lip-sync integration",
    "lib/libonnxruntime.so": "Dynamically loaded ONNX model inference for avatar lip sync",
    "lib/libonnxruntime_providers_shared.so": "ONNX execution-provider support",
}
LIMITS = {"GLIBC": (2, 35), "GLIBCXX": (3, 4, 29), "CXXABI": (1, 3, 11), "GCC": (7, 0, 0)}


def elf(path: Path) -> bool:
    if not path.is_file():
        return False
    with path.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--patchelf", required=True)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    package = args.package.resolve()
    actual = {str(p.relative_to(package)) for p in package.rglob("*") if elf(p)}
    if actual != FILES.keys():
        raise SystemExit(f"Unexpected ELF inventory: missing={FILES.keys() - actual}, extra={actual - FILES.keys()}")
    provided = {Path(name).name for name in FILES}
    rows = []
    for name, purpose in FILES.items():
        path = package / name
        if not args.check_only:
            path.chmod(path.stat().st_mode | 0o200)
            for needed in run(args.patchelf, "--print-needed", str(path)).splitlines():
                if needed.startswith("/nix/store/"):
                    basename = Path(needed).name
                    if basename not in provided | HOST:
                        raise SystemExit(f"Unexpected absolute dependency: {name}: {needed}")
                    subprocess.run([args.patchelf, "--replace-needed", needed, basename, str(path)], check=True)
            subprocess.run([args.patchelf, "--set-rpath", "$ORIGIN", str(path)], check=True)
            if name == "mushi-lantern.x86_64":
                subprocess.run([args.patchelf, "--set-interpreter", "/lib64/ld-linux-x86-64.so.2", str(path)], check=True)
        header = run("readelf", "-h", str(path))
        if "ELF64" not in header or "Advanced Micro Devices X86-64" not in header:
            raise SystemExit(f"Unexpected ELF architecture: {name}")
        dynamic = run("readelf", "-d", str(path))
        program = run("readelf", "-l", str(path))
        if "/nix/store/" in dynamic + program:
            raise SystemExit(f"Nix path in loader metadata: {name}")
        needed = re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic)
        unknown = set(needed) - provided - HOST
        if unknown:
            raise SystemExit(f"Unexpected runtime dependencies: {name}: {sorted(unknown)}")
        # A provided dependency must also be reachable via this object's RUNPATH.
        for dependency in set(needed) & provided:
            if not (path.parent / dependency).is_file():
                raise SystemExit(f"Bundled dependency not adjacent to {name}: {dependency}")
        if run(args.patchelf, "--print-rpath", str(path)).strip() != "$ORIGIN":
            raise SystemExit(f"Unexpected RUNPATH: {name}")
        if name == "mushi-lantern.x86_64" and run(args.patchelf, "--print-interpreter", str(path)).strip() != "/lib64/ld-linux-x86-64.so.2":
            raise SystemExit("Unexpected interpreter")
        symbols = run("readelf", "--dyn-syms", "--wide", str(path))
        undefined = "\n".join(line for line in symbols.splitlines() if " UND " in line)
        versions = {}
        for family, limit in LIMITS.items():
            found = [tuple(map(int, v.split('.'))) for v in re.findall(rf"@{family}_([0-9.]+)", undefined)]
            if found:
                highest = max(found)
                versions[family] = '.'.join(map(str, highest))
                if highest > limit:
                    raise SystemExit(f"ABI floor exceeded: {name}: {family}_{versions[family]}")
        if "GLIBC_PRIVATE" in undefined or "GLIBC_ABI_" in undefined:
            raise SystemExit(f"Unexpected glibc private/extension ABI: {name}")
        rows.append({"file": name, "purpose": purpose, "needed": needed,
                     "max_symbol_versions": versions, "bytes": path.stat().st_size,
                     "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"host_abi": "glibc >= 2.35; GLIBCXX >= 3.4.29; CXXABI >= 1.3.11",
                "host_services": "Vulkan drivers, X11/Wayland, audio, and (for VR) an OpenXR runtime",
                "libraries": rows}
    destination = package / "native-libraries.json"
    if args.check_only:
        if json.loads(destination.read_text()) != manifest:
            raise SystemExit("Library manifest does not match package")
    else:
        destination.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"LINUX_PACKAGE_AUDIT_OK: {len(rows)} ELF files; host glibc; no bundled desktop stack")


if __name__ == "__main__":
    main()
