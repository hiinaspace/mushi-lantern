# Terrain3D environment dependency

The project vendors the `addons/terrain_3d` directory from
[Terrain3D v1.0.2-stable](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable),
the upstream release published 2026-05-19. The release ZIP SHA-256 is
`a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2`.
Run `scripts/setup-terrain3d.sh` to reproduce the checked-in subset. The
included binaries are the Linux and Windows x86-64 debug/release GDExtensions
needed for PC VR development and export. Android, iOS, macOS, Web and other
architectures, plus addon extras, are omitted. The original addon license is
preserved at `addons/terrain_3d/LICENSE.txt` (MIT).

The basin and nature geometry are generated locally by
`scripts/environment_surface.gd` and `scripts/terrain_environment.gd` from
seed `40721`. These use no third-party textures or Meadow pack content. The
four simple materials and tree/rock/bush/grass meshes are original placeholder
geometry intended to exercise terrain and representative prop rendering.
Procedural alpha masks give near tree crowns, bushes and upright grass cards
cutout coverage; a coarse opaque tree mesh supplies the distant LOD. The static
silhouettes have no wind or rigging. Terrain3D instances decorative
geometry; simple `StaticBody3D` trunk and rock shapes use the same placement
records as GPU avoidance.

On this Godot 4.7.2 build, Terrain3D's native `HeightMapShape3D` collision
missed rectangular patches of valid terrain in repeatable vertical ray tests.
The scene therefore disables that collision and creates one static triangle
collider from `Terrain3D.bake_mesh(0)` after importing the height map. This is
the same terrain data, baked once at load. The tracked
`tests/environment_surface_checks.gd` checks 100 ground rays and height queries
for each world size, including region seams and the original activity area.
The local check yielded 32,768 collider triangles for 128 m and 131,072 for
256 m. This is a local workaround; headset/player movement still needs human
validation.

Version check performed with Godot `4.7.2.stable.nixpkgs.ed1daf0bf` and the
Mobile renderer. Terrain3D 1.0.2 officially documents Godot 4.4–4.6 with
possible later compatibility; this project's import and smoke checks establish
only the tested local 4.7.2 combination. The addon remains an explicit runtime
dependency for exported Linux and Windows builds.
