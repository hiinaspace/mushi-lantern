# Optional rock mesh audition

These meshes are a bounded, unintegrated art audition. The current Terrain3D grove still uses its procedural rock mesh. `GroveRockModels.rock_mesh(variant)` returns one of three candidate boulders; `cliff_mesh()` returns the cliff face. Scene integration and ridge placement need a separate visual/performance gate.

| Runtime asset | Source | Author | Source triangles | Runtime triangles |
|---|---|---|---:|---:|
| `moss_rock01.gltf` | [Poly Haven Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) | Kless Gyzen | 11,000 | 700 |
| `moss_rock03.gltf` | Same set | Kless Gyzen | 5,000 | 599 |
| `moss_rock05.gltf` | Same set | Kless Gyzen | 16,548 | 799 |
| `cliff_face.gltf` | [Poly Haven Rock Face 02](https://polyhaven.com/a/rock_face_02) | Dario Barresi; processing by Rico Cilliers | 29,566 | 1,200 |

Both sources are [Poly Haven CC0](https://polyhaven.com/license). The project already includes the CC0 1.0 text at `assets/forest/licenses/CC0-1.0.txt`. We downloaded the official 1K glTF and its referenced 1K JPG maps from the Poly Haven public files API on 2026-09-27. Blender 5.2.1 imported each glTF, centered each selected mesh, moved its low point to ground level, decimated it with the Decimate modifier, and exported a separate glTF with the source color, OpenGL normal, and roughness/ARM maps. The three moss stones were scaled to about 2 m maximum horizontal width to match the existing coarse rock placement and collision radius. The high-detail source files remain outside the source tree. No new collision mesh is included.

The assets in this folder total about 3.4 MB on disk. The isolated Vulkan Mobile comparison rendered each as one draw call: the current procedural rock was 320 triangles; these boulders are 599–799 triangles, and the cliff face is 1,200 triangles. This is a geometry and material audition, not headset or full-grove performance approval.
