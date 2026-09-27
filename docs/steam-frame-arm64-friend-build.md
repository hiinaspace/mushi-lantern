# Steam Frame ARM64 friend build investigation

Status checked 2026-09-27. No Steam Frame package was produced or uploaded.

## Platform route

Valve recommends Linux ARM64 or Android for custom-engine Steam Frame builds.
Steam Frame runs standalone on ARM64 SteamOS and supports OpenXR. Godot 4.7's
feature list explicitly includes Linux standalone Steam Frame OpenXR, and its
Linux exporter supports an `arm64` architecture. The cleanest route for this
project is a native Linux ARM64 package loaded with the SteamOS Devkit Client
and Steam Linux Runtime 3.0 ARM64 (Sniper).

Sources: [Valve Steam Frame custom engine guidance](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/custom),
[Valve Steam Frame compatibility](https://partner.steamgames.com/doc/steamhardware/steamframe/compatibility),
[Valve load and run games](https://partner.steamgames.com/doc/steamhardware/steamframe/loadgames),
[Godot 4.7 XR feature list](https://docs.godotengine.org/en/4.7/about/list_of_features.html),
[Godot Linux export architecture options](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformlinuxbsd.html).

## Checkout findings

- `export_presets.cfg` contains Linux Desktop x86_64 and Windows OpenXR x86_64.
  The Linux preset hardcodes `.local/godot-linux-template/bin/linux_release.x86_64`.
- `build-support/package-linux-friends.sh` packages only x86_64 ELF files and
  bundles x86_64 glibc, the x86_64 loader, and x86_64 OpenXR/Vulkan runtime
  libraries. It renames the PCK for the bundled x86_64 loader.
- Terrain3D is a required runtime dependency. Its GDExtension descriptor has
  Linux ARM64 library entries, but this checkout only contains Linux x86_64
  and Windows x86_64 binaries. Those ARM64 descriptor paths do not exist.
- The Steam Audio GDExtension has no Linux ARM64 entry or binary. Its current
  code has an `AudioStreamPlayer3D` fallback, but grove cues are disabled when
  `SteamAudioPlayer` is unavailable.
- `multiplayer-native/mushi_multiplayer.gdextension` only maps Linux x86_64
  and Windows x86_64. Its current release shared library is x86_64. The ARM64
  multiplayer friend path therefore needs a new native library build and a
  matching extension mapping.
- `bin/linux/libonnxruntime.so` and its shared provider are x86_64. They are
  needed by the native voice/viseme extension and need ARM64 replacements for
  that feature.
- The local Godot editor is 4.7.2 x86_64. The only locally built release
  template is x86_64. The Prim development shell provides Rust 1.97, Cargo,
  and SCons, but its Rust sysroot has no `aarch64-unknown-linux-gnu` standard
  library and no AArch64 GNU cross compiler was found.
- There is no Android export preset or project Android OpenXR loader setup.
  Android APK/Lepton remains a separate path rather than an immediate shortcut.

ELF architecture checks used `readelf -h` on Terrain3D, Steam Audio, the
multiplayer extension, and ONNX Runtime; each present Linux binary reported
`Advanced Micro Devices X86-64`. The standard Godot export-template archive
for 4.7.2 is available from the official release, but is 1.28 GB. A ranged
download attempt was rejected by the asset host, so no ARM64 template was
staged. Building the template from source would still leave the native addon
dependencies unresolved.

## Next build gates

1. Obtain or build the Godot 4.7.2 Linux ARM64 release template.
2. Build or obtain the matching Terrain3D Linux ARM64 GDExtension, then verify
   terrain import, rendering, and collision on the target runtime.
3. Build the multiplayer GDExtension for AArch64 and stage AArch64 ONNX Runtime
   if multiplayer voice/visemes are included.
4. Decide whether Steam Audio can be built for Linux ARM64; otherwise omit its
   extension only for this package and document that spatial ambience is off.
5. Add a distinct Linux ARM64 export/package path that never calls the current
   x86_64 glibc bundler. Test it on Steam Frame through the SteamOS Devkit
   Client with Steam Linux Runtime 3.0 ARM64 (Sniper).

The local environment did not provide the native ARM64 GDExtensions, target
compiler/sysroot, or paired Steam Frame device needed to finish those gates.
Any desktop export or cross-compiled ELF check would still leave OpenXR startup,
controller input, frame pacing, and multiplayer behavior unverified on-device.

## Partial packaging attempt

`godot --headless --xr-mode off --path . --export-pack 'Linux Desktop'
/tmp/mushi-steamframe-attempt/mushi-lantern.pck` produced a 92 MiB PCK and
returned exit code 0. Godot logged leaked CanvasItem/texture RIDs and resources
at shutdown. This used the existing x86_64 Linux preset and exports project
resources only; it is not an ARM64 executable or a runnable friend package.
The PCK is retained only in `/tmp` for this investigation.
