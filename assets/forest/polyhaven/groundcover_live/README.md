# Runtime ground cover

`shrub_02.glb` is the selected Poly Haven CC0 derivative from the ground-cover
review. The source 1K glTF bundle, reduction settings, and link are in
`../groundcover_audition/README.md`. Terrain3D instancing uses clump B at 1.50
mesh scale, capped at 1.10 terrain-record scale, with distance culling. The diffuse PNG is RGB only, so the shader
uses Poly Haven's official separate 1K alpha mask to remove card backgrounds;
the cutout edge emits violet near full adaptation. The source mask is
[Poly Haven Shrub 02](https://polyhaven.com/a/shrub_02), CC0 1.0:
`https://dl.polyhaven.org/file/ph-assets/Models/png/1k/shrub_02/shrub_02_alpha_1k.png`
(SHA-256 `5c2c31bac311051db77443e1780078403c2df0a832c40fe6ed7bcd982695cdf0`).

Weed Plant 02 remains only in `../groundcover_audition/` for source comparison.
