# Forest audition asset samples

Prepared 2026-09-24 for a naturalistic, restrained Mushi Lantern forest pass. Forest Ground 06 and the Forest Ground 04 albedo are now used in the pine grove; the other source candidates remain available for comparison. Ground maps were downloaded from the individual Poly Haven file endpoints at 1K JPG resolution. The normal maps use Poly Haven's OpenGL tangent-space variant (`nor_gl`), appropriate for Godot's normal-map convention.

## Ground A/B

| Candidate | Character | Dimensions | Albedo | Normal | License |
|---|---|---:|---:|---:|---|
| Forest Ground 01 | Leaf litter, dry grass, twigs and mossy soil; likely the broadleaf oak/ash baseline | 2 m material tile | `forrest_ground_01_diff_1k.jpg` (833,711 B) | `forrest_ground_01_nor_gl_1k.jpg` (1,428,763 B) | CC0 1.0 |
| Forest Ground 06 | Dark compact soil, pebble and twig flecks; current pine base | 2.1 m material tile | `forest_ground_06_diff_1k.jpg` (851,532 B) | `forest_ground_06_nor_gl_1k.jpg` (1,392,106 B) | CC0 1.0 |
| Forest Ground 04 | Dry soil with stones and gravel; useful rockier/pine comparison | 3.2 m material tile | `forest_ground_04_diff_1k.jpg` (1,113,899 B) | `forest_ground_04_nor_gl_1k.jpg` (1,326,812 B) | CC0 1.0 |

Sources: [Forest Ground 01](https://polyhaven.com/a/forrest_ground_01), [Forest Ground 04](https://polyhaven.com/a/forest_ground_04), [Poly Haven license](https://polyhaven.com/license). Poly Haven's individual asset pages specify CC0; its license page says its textures, models and HDRIs are CC0. The API download endpoints are listed below for file-level provenance. These are 1K JPGs, not the much larger all-map packages advertised on the asset pages.

- Forest Ground 01 albedo: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forrest_ground_01/forrest_ground_01_diff_1k.jpg
- Forest Ground 01 OpenGL normal: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forrest_ground_01/forrest_ground_01_nor_gl_1k.jpg
- Forest Ground 04 albedo: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forest_ground_04/forest_ground_04_diff_1k.jpg
- Forest Ground 04 OpenGL normal: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forest_ground_04/forest_ground_04_nor_gl_1k.jpg

## Mushroom candidate

[Warspawn's Mushroom](https://opengameart.org/content/mushroom-1) is an author-posted CC0 model, described on its page as a low-poly model suitable for mobile games. The downloaded source archive is `warspawn_mushroom.zip` (106,939 B); it contains `mushroom.blend` (462,000 B), `mushroom_skin.png` (9,732 B, 64x64), a 6,432 B layout PNG, and a 23,822 B Paint.NET layout file. Blender 5.2.1 inspection reports one mesh with 45 vertices, 41 polygons / 83 triangulated faces, and no assigned mesh material. The source image is present in the blend file; material hookup may need a small import step. No triangulated material or draw-call cost beyond this one mesh was measured.

## Suggested Godot / Terrain3D audition setup

Import each ground pair as a separate Terrain3D texture/material entry using albedo and `nor_gl` normal, with default high roughness (about 0.9) and no displacement. Begin at 1K; use a neutral/dim albedo tint only if the existing night lighting leaves the floor too bright. Keep the samples as separate A/B terrain layers, so their appearance can be compared under the same scene light and tree placement. For the mushroom, add its 64x64 skin as a simple albedo material, export/import one GLB or glTF, then instance a few differently rotated/scaled copies in a ring around a patch. Its geometry is tiny; repeated visibility and overdraw should matter more than triangle count. The mushroom has not yet been converted or imported into the project.

SHA-256:

- `forrest_ground_01_diff_1k.jpg`: `3dd6875cb3908e022a3c45ebbffa5e84c670ff2691fbbb6dc9ea4bff88523800`
- `forrest_ground_01_nor_gl_1k.jpg`: `32528a7cdee962cc0b248ee4023a74d0df175737ea90e1eb425122351e0bdab4`
- `forest_ground_04_diff_1k.jpg`: `50a4dda30875020c64385261aa7e00e2155b592302fa6794165f58fae73cbd2c`
- `forest_ground_04_nor_gl_1k.jpg`: `9c3a0200e02ce40edffbbf9f5f623ef08ea9b1b7812b556182ec978f88887151`
- `warspawn_mushroom.zip`: `82723eb8dafad63b3cfbab278f52edd9342c4c71619172bd2322193ebd20f110`

The original source-audition note predates the current pine-ground integration. The current 06/04 use and rendered validation are documented in `PROVENANCE.md` and `tests/ground_refresh_visual.gd`; headset appearance remains a separate review.

Forest Ground 06 official 1K JPG files: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forest_ground_06/forest_ground_06_diff_1k.jpg and https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forest_ground_06/forest_ground_06_nor_gl_1k.jpg. SHA-256: `2bcfe6e3de263e50c236b1e7db09b674a4385e79f8906c94dce4c9d10afa7e18` (diffuse), `73d28252b149b46c9274b3da84d2ffb6b7749ad9e2cf1c73906811dd90643822` (OpenGL normal). [Source and CC0 license](https://polyhaven.com/a/forest_ground_06).
