# Native multiplayer dependency provenance

The Mushi transport/session code is original project work under the Unlicense.
The files `multiplayer-native/src/viseme/frontend.rs` and `model.rs` adapt
Apache-2.0 OpenLipSync code and keep their SPDX headers. Model, configuration,
source revisions and notices are recorded in
`multiplayer-native/viseme-model/NOTICE.md` and `THIRD_PARTY_NOTICES.md`.
The mixed package therefore declares `Unlicense AND Apache-2.0`; this does not
replace dependency licenses.

## Vendored voice library

`multiplayer-native/vendor/godot-network-audio/` comes from
[Hiina's godot-network-audio](https://github.com/hiinaspace/godot-network-audio)
and includes the behavior published at
`c76728fa4748defc1137c30d2af055d0dc5d37ca`:
PCM taps, microphone gate, transmit mute, input/gated RMS and playback RMS.
The Mushi copy reduces workspace members to `voice-core` and `gdext`; remaining
source differences from that revision are formatting/import ordering.

The upstream root `LICENSE` is WTFPL v2, added by Hiina in licensing commit
`de675e58`. It is preserved verbatim in the vendor directory. Upstream Cargo
workspace metadata still declares `MIT OR Apache-2.0`, inherited from the older
scaffold. Both declarations are retained here rather than silently replacing
upstream terms. The root Mushi Unlicense does not apply to this vendor copy.

NetEq is a linked dependency, not code copied into the Mushi vendor directory.
Cargo pins Hiina's public [videocall-rs fork](https://github.com/hiinaspace/videocall-rs)
at `69c6ccb08afe56d0d1b1cd9e5a7de011679fa152`. Its NetEq source declares
MIT OR Apache-2.0, copyright 2025 Security Union LLC. The upstream project
credits WebRTC algorithmic inspiration while describing its code as an
independent rewrite.

The committed `multiplayer-native/Cargo.lock` pins the remaining Rust graph.
Those crates retain their source licenses and notices. Opus is linked through
the voice library. Linux voice currently links it statically; its notice is
preserved from `audiopus_sys` 0.2.2 at `build-support/OPUS-COPYING` and copied
into the archive. Windows packaging collects its toolchain Opus notice.

## Engine and other user-library patches

The Godot audio teardown patch and Steam Audio build patches are vendored,
with upstream revisions and licenses in
[the audio build notes](../build-support/steam-audio/README.md).
Their public Godot integration source is
[godot-libmpv-zero](https://github.com/hiinaspace/godot-libmpv-zero)
revision `293d895d0e11eca1b3665a654fe4438e2d9ea031`.
Prim influenced the transport and previously supplied a local development
shell. It is not a checkout/build dependency, and its repository may remain
private.

The GNA commit, exact NetEq pin and godot-libmpv-zero revision were checked
through anonymous HTTPS during the source-publication audit on 2026-09-27.
