# License scope and third-party notices

Hiina dedicates the **original Mushi Lantern work** to the public domain under
[the Unlicense](UNLICENSE). This covers original game code, shaders, scenes,
procedural geometry, documentation and build tools, except where a file or its
provenance specifies another license. The original woodland mushroom assets,
for example, retain their explicit CC0 dedication.

**This is not a blanket license for everything in this repository or its
exports.** Imported assets, vendored libraries, copied source and patches to
third-party files retain their respective upstream licenses. Their copyright,
attribution, redistribution and notice requirements continue to apply.
The Unlicense does not grant any rights to third-party characters, trademarks,
or to the Mushishi manga/anime. Mushi Lantern is an unofficial, unaffiliated
project inspired by that work.

## Where to find the terms

| Component | License and provenance |
| --- | --- |
| Ukon VRM model by kitsune_tsuki | Custom VRoid Hub terms; attribution required. Author, source and permission URL in [CREDITS.md](CREDITS.md). These terms are not the Unlicense or CC0. |
| Forest meshes, textures and material sources | [Forest provenance](assets/forest/PROVENANCE.md), [additional material/asset records](assets/forest/PROVENANCE-SOURCES.md), and license texts in `assets/forest/licenses/`. Poly Haven and the listed CC0 flora use CC0. EZ-Tree source and leaf textures use MIT; generated mesh output has no separate CC0 grant. |
| Audio recordings | CC0 source credits and edit records in [CREDITS.md](CREDITS.md) and [field audio notes](assets/audio/field/README.md). |
| RPG animation sample | MIT; `assets/animations/LICENSE` and `assets/animations/README.md`. |
| Klee One and DejaVu fonts | SIL OFL and DejaVu/Bitstream terms; `assets/fonts/KleeOne-OFL.txt` and `assets/fonts/DejaVu-LICENSE.txt`. |
| Godot XR Tools and hand models | MIT code (`addons/godot-xr-tools/LICENSE`); CC0 hand assets (`addons/godot-xr-tools/hands/License.md`); editor icon notice in `addons/godot-xr-tools/editor/icons/LICENSE`. |
| Godot VRM, MToon and RenIK | MIT; license texts within their directories under `addons/`. Local modifications retain those terms. |
| Terrain3D | MIT; `addons/terrain_3d/LICENSE.txt` and [pinned binary/source provenance](docs/terrain3d-provenance.md). |
| Godot, godot-cpp and Steam Audio | [Build provenance](build-support/steam-audio/README.md), `build-support/godot/licenses/`, and Steam Audio extension, SDK and dependency notices under `build-support/steam-audio/`. |
| Native multiplayer, vendored voice code and Rust dependencies | [Native dependency provenance](docs/native-dependency-provenance.md); vendored notices under `multiplayer-native/vendor/`; dependencies retain the licenses of their pinned Cargo sources. |
| OpenLipSync model and ONNX Runtime | Apache-2.0 model and third-party notices in `multiplayer-native/viseme-model/`; downloaded ONNX Runtime license/notices copied into package licenses by export scripts. |

Keep the relevant upstream notices with redistributed components. Source
license texts and attribution records should be consulted before extracting
an individual asset or library for another project.
