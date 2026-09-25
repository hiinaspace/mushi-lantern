# Forest audition assets

`MUSHI_FOREST_STYLE=oak` and `MUSHI_FOREST_STYLE=pine` choose the rendered A/B candidates. Pine is the default. Both use the same deterministic Terrain3D placement records, coarse collisions, lighting, fern positions, grass, rocks, and scale. They vary the main tree model and Terrain3D ground dressing. The default `procedural` style keeps the generated tree/bush kit.

## Candidates and provenance

- Oak Medium / Pine Medium tree LODs: generated from [EZ-Tree](https://github.com/dgreenheck/ez-tree) at source commit `dcf309bd86bd521083d9c70f01f2de45fdc7c457`, with seeds 35729 / 13977. The project code and leaf textures follow the included MIT license; bark source maps are CC0. EZ-Tree does not separately specify rights for generated GLB exports, so these are audition candidates and must not be described as CC0 or redistributed on that basis without clarifying output rights. Source dimensions are normalized to 9.5m tall in the scene. LOD triangle counts are Oak 13,806 / 6,694 / 3,782 and Pine 19,872 / 8,248 / 3,456. Leaf alpha masks use the matching imported material cutoffs: oak 128/255, pine 77/255.
- Pine Bark albedo / OpenGL normal: [Poly Haven](https://polyhaven.com/a/pine_bark), CC0 1.0. Pine trunks use this mapped material with a subtle tint and normal strength.
- Pine needle ground uses Forest Ground 03; [Mossy Rock](https://polyhaven.com/a/mossy_rock) supplies the green moss-on-stone overlay. Both are 1K CC0 assets from [Poly Haven](https://polyhaven.com/license). A deterministic Terrain3D control mask blends the overlay only on gentle terrain and fades it away from the goal, starts, mushroom clearings and traversal route. Automatic slope texturing remains enabled elsewhere so cliffs retain their rock material.
- Naturalistic pine/oak terrain and boulders use Poly Haven [Rock 01](https://polyhaven.com/a/rock_01) 1K diffuse and OpenGL normal maps (CC0). Pine moss uses a filtered half-metre shader mask rather than quantized 1m overlay control pixels; Terrain3D retains the pine-needle base and slope autoshader.
- Royal fern understory and meadow grass clump: [Dense Temperate Forest Flora](https://3dassets.dev/packs/dense-temperate-forest-flora), CC0 1.0. Blender re-export removes `KHR_mesh_quantization`, which Godot 4.7 does not import in the original GLBs. Ferns reuse bush placements at 0.52 scale. Meadow clumps replace pine grass at a sparse deterministic subset of the existing grass positions, with a smaller generated tuft LOD from 12–32m and culling beyond 32m (10–24m in low quality).
- Rocks and the boulder mesh remain unchanged. The added assets do not use parallax, depth, or AO maps.

## Capture commands

Use a separate cache directory for every run. These commands use the patched Godot runtime and the same test framing:

```sh
XDG_DATA_HOME=/tmp/mushi-forest-oak-128 MUSHI_FOREST_STYLE=oak MUSHI_FOREST_CAPTURE=/tmp/mushi-forest-oak-128.png ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan --rendering-method mobile --script tests/forest_audition_visual.gd -- --terrain-size 128
XDG_DATA_HOME=/tmp/mushi-forest-pine-128 MUSHI_FOREST_STYLE=pine MUSHI_FOREST_CAPTURE=/tmp/mushi-forest-pine-128.png ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan --rendering-method mobile --script tests/forest_audition_visual.gd -- --terrain-size 128
```

Change the cache, capture filename, and final argument to `256` for the larger basin. The screenshots are desktop render captures; tree silhouette, edge shimmer and comfort still need the accepted headset review.
