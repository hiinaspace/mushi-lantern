# Mushi multiplayer native transport prototype

This standalone Godot 4.7 GDExtension provides authenticated peer connections,
private pkarr rendezvous, lantern and voice datagrams, independent snapshot
datagrams, and reliable bounded control messages. It follows the existing Prim
pattern for pkarr key derivation and Iroh TLS-exporter authentication. The
voice codec uses the vendored Prim Opus/NetEq implementation and Basis
OpenLipSync model.

Build with the project's Rust environment, for example:

```sh
nix develop . --command ./multiplayer-native/build.sh debug
nix develop . --command ./multiplayer-native/build.sh test
nix develop . --command ./multiplayer-native/build.sh windows-release
nix develop . --command ./build-support/steam-audio/package-windows.sh
```

The Linux environment is provided by the root `flake.nix`; it has no private
Prim dependency. Build commands use the committed Cargo lockfile.

Windows cross-builds require a Rust toolchain with the
`x86_64-pc-windows-gnu` standard library plus MinGW GCC and Windows Opus.
Stage the MinGW prefix at `.local/windows/msys/mingw64`, or set
`MUSHI_WINDOWS_MINGW_PREFIX=/absolute/path/to/mingw64` for an existing prefix.
The prefix needs `lib/pkgconfig/opus.pc`, `lib/libopus*`, `bin/libopus-0.dll`
and `share/licenses/opus/COPYING`. Set `RUSTC` and add MinGW GCC to `PATH` if
your tools are elsewhere; an optional `.local/windows/rustc` and
`.local/windows/toolchain/bin` are detected automatically.
For example, an existing cross-toolchain can be selected without copying it:

```sh
export MUSHI_WINDOWS_MINGW_PREFIX=/absolute/path/to/mingw64
export RUSTC=/absolute/path/to/windows-capable/rustc
export PATH=/absolute/path/to/mingw/bin:$PATH
nix develop . --command ./build-support/steam-audio/package-windows.sh
```

There is not yet a turnkey Windows Rust/Opus bootstrap script in this repository.
The package script
fetches the SHA-256-pinned ONNX Runtime DLL, exports the Windows GDExtension,
and includes its required Opus DLL and notices. The packaged executable
started a private host under Wine; native Windows/OpenXR remains a separate validation gate.

For multiplayer, open the in-game menu and select Multiplayer. Enter the same
three-or-more-character code with the desktop keyboard or XR pointer keyboard,
then choose Host on one machine and Join on the others. Codes are
case-insensitive. Room hosting skips the singleplayer tutorial and enables
two-hand broom flight in XR. Leaving the room returns to offline play.
For command-line testing, the first process explicitly hosts and the second
joins:

```sh
export MUSHI_ROOM_SECRET='a private phrase shared out of band'
./launch.sh --desktop --skip-tutorial --host
./launch.sh --desktop --skip-tutorial --join
```

Use two terminals or machines. For an isolated two-process localhost test, set
the same nonzero `MUSHI_NETWORK_LOCAL_PORT` in both terminals. Client-side
synthetic impairment is available with `MUSHI_NET_JITTER_MS=200` and
`MUSHI_NET_LOSS_PERCENT=1`. The game prints `MUSHI_NET_DIAG` every five seconds.
`MUSHI_MAX_REMOTE_LIGHTS` bounds visible peer spotlights from 0 to 7 (default
3); peer beams remain active in host gameplay when culled visually.
The current join gate uses the same 128 m map and supports 512 or 1,024 mushi;
the host controls the population and restart. The menu has a top-level mic mute
button plus microphone selection, input gain, noise gate, live input meter and
other-player voice volume controls. The XR menu uses opaque tabs.

Room phrases may be as short as three characters; short common words make a
room easy for strangers to discover and enter. Player avatars use the Ukon
model, with a random hue per join. Head, hand, articulated finger and staff
poses travel with each lantern update (443 bytes total), and the free RPG
animation sample drives looping forward and strafe locomotion legs. Nearby clear lanterns combine for visual eye
adaptation even when their beams point away; filtered lanterns together have
at most one filtered lamp's effect.
`MUSHI_AVATAR_EYE_HEIGHT=1.65` supplies the standing XR eye height, in metres,
when the session starts seated or crouched (allowed range 1.1–2.1). The XR
world scale is calibrated once against Ukon's authored height after joining;
desktop uses its camera height. Both XR and desktop receive voice but start
muted. Use `--voice-unmuted` or `MUSHI_VOICE_UNMUTED=1` to transmit from launch
for testing. Microphone choice, gain, gate threshold and received voice volume
persist locally; mute resets on launch.
The Comfort tab also offers an immediate standing-height calibration from the current headset height.

Broom flight is enabled only while a multiplayer room is active.
Hold the staff with both hands,
then hold both controller triggers for one second, regardless of staff pose.
Releasing either grip stops flight or starts a controlled landing when high
above the ground. During flight, the Ukon avatar keeps tracked head and arms while its ground leg
animation and foot planting pause. That flight state rides the existing avatar
pose byte so peers see dangling legs too. The XR Tools hand meshes are hidden while
the local multiplayer Ukon avatar is present; their hand nodes still provide
grab poses and wrist targets.

The game loads `res://multiplayer-native/mushi_multiplayer.gdextension` when
hosting or joining from the menu or command line, then creates a `MushiNetwork`
node. The roles are explicit; first-participant election is not implemented.
Build the release library before making a Linux export. The
Windows preset uses the Windows build of this extension. OpenLipSync requires
ONNX Runtime at `res://bin/linux/libonnxruntime.so` or
`res://bin/windows/onnxruntime.dll`. For local tests,
`MUSHI_ONNXRUNTIME_LIBRARY` can point to an existing runtime library. Without
the runtime, voice playback remains available and an energy-driven AA mouth
opening is used. Model provenance and licenses are in `viseme-model/`.
Microphone capture requires Godot's `audio/driver/enable_input=true`.
`./tools/fetch-viseme-runtime.py --platform linux` fetches a SHA-256-pinned
runtime into ignored local staging and `bin/linux/`; use `windows` for the
Windows DLL. `MUSHI_VOICE_TRANSMIT=1` is a legacy alias for starting unmuted.
The sender starts with a -38 dBFS gate and 160 ms hangover before encoding;
the Voice tab adjusts the threshold from -60 to -20 dBFS against a live local
meter, including while muted.
`MUSHI_VOICE_DIAG=1` prints capture state and local/remote decoded
speech levels once per second.

## Godot API

- `start(secret_phrase: String, display_name: String, hosting: bool) -> bool`
  starts an explicit host or joiner. The same secret phrase derives the pkarr
  signing key and the per-connection authentication key. Use a private,
  high-entropy phrase. A joining process retries discovery for up to five
  minutes. For deterministic loopback process tests, set the same
  `MUSHI_NETWORK_LOCAL_PORT` value on host and clients. It uses an ephemeral
  Iroh loopback connection and a short lived rendezvous file in the system
  temp directory; it skips pkarr and relay setup.
- `stop()`, `is_host()`, and `peer_count()` expose session state.
- `send_lantern(bytes) -> bool` sends a client lamp to the host. The host gets
  `lantern_received(peer_id, bytes)` and automatically forwards that datagram
  to the other connected peers. A host call broadcasts its own lamp state.
- `broadcast_snapshot_chunk(bytes) -> bool` sends one independent lossy
  snapshot chunk from host to all peers. The payload limit is 1099 bytes.
  The game payload should include its own epoch, sequence, tick, range start,
  and count so receivers can reject stale or incomplete chunks. The extension
  intentionally does not retain or retry lost snapshot datagrams.
- `broadcast_control(bytes)` and `send_control(peer_id, bytes)` use the
  reliable QUIC stream for reset/join state. Control payloads are limited to
  16 KiB. `control_received(peer_id, bytes)` delivers them to the game.
- `attach_voice_sender(NetworkAudioSender)` sends encoded packets from the
  codec worker. The host relays client voice with the original peer ID.
  `receive_voice_stream(peer_id)` returns a stream for spatial playback, and
  `get_voice_level(peer_id)` reports a smoothed 0–1 decoded PCM envelope.
  Voice payloads are capped at 1,024 bytes so client packets fit through the
  host relay with their original peer ID.
- Signals: `session_ready(peer_id, is_host)`, `peer_joined(peer_id)`,
  `peer_left(peer_id)`, `lantern_received(peer_id, bytes)`,
  `snapshot_chunk_received(peer_id, bytes)`, `control_received(peer_id, bytes)`,
  `network_error(message)`, and `session_ended()`.

Capacity is eight participants including the host. Each accepted client uses
one Iroh connection to the host; there is no mesh routing, host migration,
or identity layer. The transport cap is 1,100 bytes including a one-byte
channel tag, leaving 1,099 game bytes per datagram. QUIC provides authenticated
encryption. The game validates lantern payloads and logs application payload
bandwidth; the transport does not enforce input rate limits or add snapshot
delta/compression codecs.

`cargo test --lib` runs localhost transport tests including three-peer voice
relay identity. With ONNX Runtime available,
`MUSHI_ONNXRUNTIME_LIBRARY=/path/to/libonnxruntime.so godot --headless --path . -s tests/mushi_viseme_smoke.gd`
checks inference. Separate-process Godot
tests exercised pkarr rendezvous and synthetic receiver jitter/loss; relay
paths and actual network shaping still need testing in each intended friend setup.
Local desktop and XR user checks are separate from these automated checks.

For a packaging-only refresh with **unchanged native source**, pass
`--reuse-native` to `build-support/steam-audio/package-windows.sh`. This reuses
the staged multiplayer DLL, while still building the cached patched engine and
Steam Audio outputs and exporting the current game. The Opus runtime DLL and
notice must still be staged in the documented prefix; no Rust/MinGW compilation
is performed in this mode. Do not use this option after changing native code.
