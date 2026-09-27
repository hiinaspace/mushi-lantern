# Fern 02

- Source: [Poly Haven Fern 02](https://polyhaven.com/a/fern_02), downloaded 2026-09-27.
- License: [CC0 / public domain](https://polyhaven.com/license).
- Source files: official 1K glTF, binary geometry, and 1K JPEG diffuse, normal, ARM, and alpha textures from `dl.polyhaven.org/file/ph-assets/Models/`.
- The game uses only clump `fern_02_a` (784 triangles) from the four-clump source model, with the diffuse and alpha images in a custom cutout shader. The original four-clump asset is about 6K triangles. Moss 01 (246K triangles) and Grass Medium 02 (about 1M triangles) were not scattered as source meshes because of their cost.
- The scattered fern sits over the original Terrain3D floor, has no collision, and uses culled 16 m cells. The separate alpha texture is also used for the river stencil mask so individual fronds block the through-terrain stream without hiding it across whole cards.
