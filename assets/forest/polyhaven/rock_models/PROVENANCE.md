# Poly Haven rock meshes

The pine Terrain3D grove instances three moss boulder silhouettes through `GroveRockModels.rock_mesh(variant)`. `cliff_mesh()` exposes a cliff face for a later placement audition; it is not currently instanced.

| Runtime asset | Source | Author | Source triangles | Runtime triangles |
|---|---|---|---:|---:|
| `moss_rock01.gltf` | [Poly Haven Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) | Kless Gyzen | 11,000 | 2,400 |
| `moss_rock03.gltf` | Same set | Kless Gyzen | 5,000 | 1,800 |
| `moss_rock05.gltf` | Same set | Kless Gyzen | 16,548 | 2,800 |
| `cliff_face.gltf` | [Poly Haven Rock Face 02](https://polyhaven.com/a/rock_face_02) | Dario Barresi; processing by Rico Cilliers | 29,564 | 3,998 |

Both sources are [Poly Haven CC0](https://polyhaven.com/license). The project already includes the CC0 1.0 text at `assets/forest/licenses/CC0-1.0.txt`. We downloaded the official glTFs and JPG maps from the Poly Haven public files API on 2026-09-27. The first 600–1,200 triangle export had hundreds of open mesh edges because decimation was applied before shared positions at UV seams were welded. The repaired Blender 5.2.1 export welds geometric duplicates while keeping per-face UVs, then decimates moderately. Each moss stone has zero geometric boundary or nonmanifold edges after export; the source cliff face is intentionally open and remains so. The three moss stones retain their roughly 2 m maximum horizontal width, their low point at ground level, and their coarse existing collision proxies. Terrain3D instances are planted 30% of their scaled height below the sampled ground.

The moss stones now reference the official 2K diffuse, OpenGL normal, and roughness JPGs; source MD5 values were checked after download. The unused cliff face retains its 1K maps. The previous 1K moss maps are removed. This is a bounded desktop visual/geometry pass; headset appearance and performance still need direct validation.
