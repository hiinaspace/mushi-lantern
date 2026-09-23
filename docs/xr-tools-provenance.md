# XR Tools provenance

`addons/godot-xr-tools/` is vendored from [GodotVR/godot-xr-tools](https://github.com/GodotVR/godot-xr-tools), tag `4.5.1`, commit `aecfc894d9581cf4ca6df7fdd09098040497aa8e`, fetched 2026-09-23. `openxr_action_map.tres` started from the same commit. The addon includes its MIT license at `addons/godot-xr-tools/LICENSE`, plus asset notices in its subdirectories.

Project-local compatibility changes for Godot 4.7.2:

- `objects/viewport_2d_in_3d.gd`: return `null` for unknown property revert requests so all return paths compile.
- `objects/viewport_2d_in_3d.tscn`: set `ViewportTexture.viewport_path` explicitly to avoid an unbound viewport texture during scene instantiation.
- `functions/function_teleport.gd`: return `null` for unknown revert requests so all return paths compile during export.
- `examples/fall_damage.tscn`: use a `Node3D` root, matching its script's native base type.
- `objects/virtual_keyboard.tscn`: bind its `ViewportTexture` to the scene viewport for export conversion.
- `openxr_action_map.tres`: remove four invalid Back/System button bindings in unused Pico Neo 3, Vive Cosmos and Vive Focus 3 profiles. Godot 4.7.2 rejected those paths during startup; the Valve Index bindings remain intact.

The pinned map exposes `primary` for each thumbstick, `grip` for each hand, `ax_button` for X/A, and `by_button` for Y/B, including the Valve Index profile. The project's XR rig uses XR Tools' player body, movement providers, low-poly hands, 0.32 m grip pickups, pointers, and viewport panel. Pickups probe collision layer 3 and have ranged grabbing disabled; the staff sets that collision layer. XR Tools' desktop support remains available, while the existing desktop player remains the flat-mode driver for this initial slice.
