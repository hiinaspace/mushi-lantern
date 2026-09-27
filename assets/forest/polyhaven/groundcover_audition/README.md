# Groundcover candidate audition

These four Poly Haven CC0 sources are staged for review only. They are not
referenced by the live terrain setup. Each directory keeps the official 1K
glTF source bundle and a separate `_audition.glb` derivative.

| Candidate | Official source | Original mesh triangles (gltf 1K) | Audition triangles |
|---|---|---:|---:|
| Weed Plant 02 | [Poly Haven](https://polyhaven.com/a/weed_plant_02) | 11,116 across five clumps | 1,775 |
| Shrub 01 | [Poly Haven](https://polyhaven.com/a/shrub_01) | 156,012 | 1,872 |
| Grass Medium 02 | [Poly Haven](https://polyhaven.com/a/grass_medium_02) | 7,842 across five clumps | 1,252 |
| Shrub 02 | [Poly Haven](https://polyhaven.com/a/shrub_02) | 27,254 across four clumps | 2,179 |

All source models and texture maps are CC0 1.0. The audition derivatives were
created in Blender 5.2.1 by importing the 1K glTF, applying a Decimate
modifier to each mesh (ratios: Weed Plant 02 0.16, Shrub 01 0.012, Grass
Medium 02 0.16, Shrub 02 0.08), then exporting glTF binary with textures.
These settings are an initial geometry budget for visual review, not final
runtime LODs. The visual fixture sets a 28 m visibility range on imported mesh
instances; it does not establish a production scatter or headset performance
budget.

Run the rendered comparison with:

```sh
XDG_DATA_HOME=/tmp/mushi-groundcover MUSHI_GROUNDCOVER_CAPTURE=/tmp/groundcover \
  ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan \
  --rendering-method mobile --script tests/groundcover_audition_visual.gd
```

The fixture captures baseline, combined candidates, then one close review per
candidate. It changes only its in-memory scene: existing grass and shrub mesh
instances are cleared for the candidate pass; terrain, rocks, trees and source
environment scripts are not changed.
