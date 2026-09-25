#!/usr/bin/env python3
"""Bundle non-glibc ELF dependencies for the standalone Linux friend build."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


parser = argparse.ArgumentParser()
parser.add_argument("package", type=Path)
parser.add_argument("--patchelf", required=True, type=Path)
parser.add_argument("--interpreter", default="/lib64/ld-linux-x86-64.so.2")
args = parser.parse_args()
package = args.package.resolve()
libdir = package / "lib"
libdir.mkdir(parents=True, exist_ok=True)
patchelf = str(args.patchelf)


def run(*command: str) -> str:
    environment = os.environ.copy()
    if search_paths:
        paths = [str(libdir), *search_paths]
        prior = environment.get("LD_LIBRARY_PATH")
        if prior:
            paths.append(prior)
        environment["LD_LIBRARY_PATH"] = ":".join(dict.fromkeys(paths))
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, env=environment).strip()


def elf(path: Path) -> bool:
    try:
        return path.is_file() and path.open("rb").read(4) == b"\x7fELF"
    except OSError:
        return False


def is_nix_glibc(path: Path) -> bool:
    return "/nix/store/" in str(path) and "glibc-" in str(path)


def bundled_backend(path: Path) -> bool:
    return re.fullmatch(
        r"lib(?:X[^/]*|wayland[^/]*|xkbcommon[^/]*|pulse[^/]*|asound[^/]*|"
        r"openxr[^/]*|vulkan[^/]*|GL[^/]*|EGL[^/]*|udev[^/]*|dbus[^/]*|"
        r"SDL[^/]*)\.so(?:\..*)?",
        path.name,
    ) is not None


seeds = [
    package / "mushi-lantern.x86_64",
    package / "addons/terrain_3d/bin/libterrain.linux.release.x86_64.so",
    package / "addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_release.x86_64.so",
    package / "addons/godot-steam-audio/bin/libphonon.so",
]
search_paths: list[str] = []


def add_runpaths(seed: Path) -> None:
    for directory in run(patchelf, "--print-rpath", str(seed)).split(":"):
        if directory.startswith("/") and directory not in search_paths:
            search_paths.append(directory)


for seed in seeds:
    if not elf(seed):
        raise SystemExit(f"Required ELF is missing or invalid: {seed}")
    add_runpaths(seed)

# Godot loads windowing/audio/OpenXR/Vulkan backends by SONAME at runtime, so
# collect those from the template's Nix RUNPATHs as well as DT_NEEDED closure.
for seed in list(seeds):
    for directory in run(patchelf, "--print-rpath", str(seed)).split(":"):
        if not directory.startswith("/"):
            continue
        base = Path(directory)
        if base.is_dir():
            for candidate in base.glob("*.so*"):
                if bundled_backend(candidate) and elf(candidate):
                    seeds.append(candidate)


queue = list(seeds)
seen: set[Path] = set()
providers: dict[str, Path] = {}
store_roots: set[Path] = set()
missing: set[str] = set()
while queue:
    source = queue.pop()
    source_real = source.resolve()
    if source_real in seen:
        continue
    seen.add(source_real)
    add_runpaths(source)
    output = run("ldd", str(source))
    for line in output.splitlines():
        miss = re.match(r"\s*(\S+)\s+=>\s+not found", line)
        if miss:
            missing.add(miss.group(1))
            continue
        match = re.match(r"\s*(\S+)\s+=>\s+(/\S+)", line)
        if not match:
            match = re.match(r"\s*(/\S+)\s+\(0x", line)
            if not match:
                continue
            soname, resolved = Path(match.group(1)).name, Path(match.group(1))
        else:
            soname, resolved = match.group(1), Path(match.group(2))
        if not resolved.is_file() or is_nix_glibc(resolved):
            continue
        if "/nix/store/" not in str(resolved):
            continue
        store_root = Path("/nix/store") / resolved.parts[3]
        store_roots.add(store_root)
        prior = providers.get(soname)
        if prior is not None:
            if hashlib.sha256(prior.read_bytes()).digest() != hashlib.sha256(resolved.read_bytes()).digest():
                print(f"Keeping first provider for {soname}: {prior}", file=sys.stderr)
            continue
        providers[soname] = resolved
        queue.append(resolved)

if missing:
    raise SystemExit("Unresolved runtime libraries: " + ", ".join(sorted(missing)))

for soname, source in providers.items():
    shutil.copy2(source, libdir / soname)

# Record notices for the Nix runtime libraries that were redistributed.
notice_dir = package / "licenses/linux-runtime"
for root in sorted(store_roots):
    if not root.exists():
        continue
    name = root.name.split("-", 1)[-1]
    for base in (root / "share/licenses", root / "share/doc"):
        if not base.is_dir():
            continue
        for pattern in ("**/LICENSE*", "**/LICENCE*", "**/COPYING*", "**/COPYRIGHT*", "**/NOTICE*", "**/copyright"):
            for source in base.glob(pattern):
                if not source.is_file() or source.stat().st_size > 1_000_000:
                    continue
                relative = source.relative_to(root / "share")
                destination = notice_dir / name / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)

for path in sorted(package.rglob("*")):
    if not elf(path):
        continue
    path.chmod(path.stat().st_mode | 0o200)
    needed = run(patchelf, "--print-needed", str(path)).splitlines()
    for name in needed:
        if name.startswith("/nix/store/"):
            soname = Path(name).name
            if not (libdir / soname).is_file():
                raise SystemExit(f"Missing absolute Nix dependency {name} for {path}")
            subprocess.run([patchelf, "--replace-needed", name, soname, str(path)], check=True)
    relative = os.path.relpath(libdir, path.parent)
    rpath = "$ORIGIN" if relative == "." else "$ORIGIN/" + relative
    subprocess.run([patchelf, "--set-rpath", rpath, str(path)], check=True)
    if path == package / "mushi-lantern.x86_64":
        subprocess.run([patchelf, "--set-interpreter", args.interpreter, str(path)], check=True)

for path in sorted(package.rglob("*")):
    if not elf(path):
        continue
    dynamic = run("readelf", "-d", str(path))
    program = run("readelf", "-l", str(path)) if path == package / "mushi-lantern.x86_64" else ""
    if "/nix/store/" in dynamic or "/nix/store/" in program:
        raise SystemExit(f"Nix store path remains in ELF metadata: {path}")

(package / "runtime-libraries.json").write_text(
    json.dumps(sorted(providers), indent=2) + "\n", encoding="utf-8"
)
print(f"Bundled {len(providers)} runtime libraries into {libdir}")
