# Local development runtime

Sayu performance validation, 2026-09-22: installed `godot`/`godot4` reports **4.7.2.stable.nixpkgs.ed1daf0bf**; rendered checks explicitly use Vulkan/Mobile on **NVIDIA GeForce RTX 4090**, driver **615.71.09**, with Ryzen 7 9800X3D. See [m0e-performance.md](m0e-performance.md) for commands and bounded evidence. This is desktop compute/render validation, not headset or export qualification. Power settings were not changed.

Verified on `natto`, 2026-09-21:

- Ubuntu 26.04.1 LTS; AMD Radeon 780M (RADV PHOENIX), Mesa 26.0.8.
- Official Godot **4.7.2.stable.official.ed1daf0bf** Linux x86_64.
- Installed executable: `/home/s/.local/share/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64`.
- [Official release download](https://github.com/godotengine/godot/releases/tag/4.7.2-stable).
- SHA-256 of the extracted executable: `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`.

A minimal local windowed scene successfully initialized **Vulkan 1.4.335 / Forward Mobile** on the physical Radeon GPU and exited without logged errors. Probe log: `artifacts/m0-20260921/renderer-probe.log` (local, ignored). This establishes renderer availability, not game performance, exported build compatibility or XR readiness.

Use `GODOT_BIN` with the project launcher to select an engine on another host. Carry source, saved tuning choices and research manifests to sayu; recreate the Godot import cache there. Do not carry this laptop's absolute executable path as an assumed installation on sayu. A headset/stereo check and the final target export are still required later.
