# M3 audio plan — spatial cues in the grove

Planning checkpoint, 2026-09-23. The user asked for Steam Audio like Prim or Mainspring, audible nearby mushi, footsteps, localized forest insects, and lantern flame, movement, and control sounds. Placeholder audio is acceptable until samples are chosen. This plan was reviewed by an Astra subagent before implementation. Initial feasibility was desktop only; the user later finished VRChat and reopened OpenXR testing for the integrated build.

## Implementation checkpoint — 2026-09-23

The Linux x86_64 debug Steam Audio extension and audio-patched Godot 4.7.2 now build from pinned Nix recipes in this repository, with source patches and notices. `launch.sh` selects the local patched engine. The game has a 24-source pool with stable nearby mushi IDs, spatial insect beds at tree locations, lantern flame and movement/control events, grounded footsteps, category buses, and one listener on the active desktop or XR camera. The 21 original mono WAV placeholders have a deterministic offline generator. The existing asynchronous GPU snapshot supplies agent positions; audio does not add a readback. The renderer and creature simulation remain unchanged.

On the local patched engine, `tests/audio_spatial_smoke.gd` captured the correct right/left ear emphasis and reversed it when the listener turned, with zero discarded frames. A rendered 1024-agent desktop fixture captured audible output at 1, 12, and 24 forced sources and a zero-audio baseline. The final `./check-audio.sh --long` run completed 3,601 frames and 465 GPU snapshots over 60 seconds at 24 continuously audible sources, with wall-frame p95 17.92 ms, snapshot-apply p95 0.33 ms, and no capture overflow. These are desktop measurements under a 60 FPS cap, not a target-headset frame budget. A four-cycle stop/reset/restart/teardown test passed. A separate normal-gameplay desktop probe observed 12 selected mushi, calls, all three tree beds, flame, shutter/filter cues, creaks, and footsteps. An imported WAV loop was initially silent because its runtime `loop_end` was zero; the pool now sets a real endpoint on a duplicated loop stream. Source gain now survives `play_stream()` and the pool's fade control. `check.sh` passed after updating an old eight-preset assertion to include the already accepted ninth Loose trains preset.

The OpenXR build initialized on Monado with the Bigscreen Beyond, Knuckles controllers, the grove camera/body, and Steam Audio. The user confirmed the grove, localized mushi/forest sound, and broadly balanced footsteps, flame, creaks and controls. In a second 1024-agent headset run, distance falloff felt about right despite placeholder clips, with no noticed crackles, clipping, or performance trouble. This is a subjective headset check, not measured 90 Hz delivery. The initial reproducible backend supplies Linux debug only; Windows/release extension builds and the final sample/mix pass remain open.

The follow-up sound pass moved generated placeholder WAVs out of Git while
retaining the deterministic generator; launch and check scripts recreate them
when missing. [Sample candidates](audio-sample-shortlist.md) began the ear
review. A bandpass-noise mushi generator is being auditioned separately.

In the next listening pass, the user selected two CC0 cricket/cicada recordings,
foliage footsteps, lantern swing, shutter gestures, and a wooden wick texture.
Edited mono excerpts are included in `assets/audio/field/`, with exact credits,
source hashes, and edit spans in [Credits](../CREDITS.md) and the asset README.
The forest uses three separated nearby tree emitters and different playback
offsets. The footstep composite fades with grounded movement; lantern swing
fades with actual relative lantern motion. The shutter source was cut into two
open/close gestures that the user accepted by ear. Four audio
category levels now have live F3 and XR pointer controls plus a locally saved
mix preset. The first narrower 500–3000 Hz mushi sketches led to a still
narrower set with independent slow gain and Q motion per partial, inspired by
glass-harp tones. The new `glass_harp_soft` sketch provisionally supplies four
seeded in-game calls. Six nearby mushi slots are active by default; baseline
arousal near 0.08 gets long 35–65 second intervals after an initial wait,
while high arousal can shorten intervals to 10–20 seconds and raise pitch
modestly. The source gain starts 12 dB lower than in the first audio pass. The
other new sketches and overall balance still need ear review.

The user then supplied a [glass-harp reference](mushi-audio-reference.md),
particularly its 1:26–1:33 fifth. The measured passage is dominated by two
notes near 650 and 986 Hz with alternating ~2.9 Hz rubbing pulses. A later
spectral comparison found faint but important high harmonics and moving
6–9 kHz content missing from the first reconstruction. Three brighter original
auditions now test an etched edge, gentle detuned beating, and added contact
noise. The user selected the contact texture, which adds an insect-like high
edge without the less desirable detuned beating. All four generated in-game
calls now use that texture, in two near fourths and two near fifths. The
first spatialized mix then received headset review.

In that review, the user liked the mushi timbre and the relative balance of
steps, lantern hinge, and forest, but found the whole output quiet even at the
category sliders' former 150% limit. The mix panel now has an Overall control
starting at 300% of the former master gain and adjustable up to 600%; the
category controls retain their local saved levels. Candle gains 4 dB. Moving
mushi now call again roughly every 3 seconds from a smaller 10 m audible area;
dormant mushi call less often and at much lower gain, while arousal raises
pitch. The shorter falloff and six-slot default retain individual spatial
positions. Shutter cues trigger when manual travel begins instead of waiting
for a large position change, and filter-driven shutter animation no longer
triggers them. The source clips' leading quiet material was trimmed, and the
filter control rotates through additional recorded transient cuts. The revised
output level, cue timing, and new cuts still need headset listening review.

## Intended sound

- **Mushi:** nearly continuous, quiet mono calls from nearby moving agents, suggesting glass resonances with insect-like contact texture. Dormant agents fade toward silence, and arousal lifts pitch. Calls remain audible when the mushi are hidden by the visibility effect. Keep the source pool bounded instead of mixing all 1024 agents.
- **Forest:** several localized insect/cricket beds at authored or seeded grove positions, including near trees, with restrained variation. Add a faint campfire cue when that landmark exists. Keep enough silence to locate hidden mushi.
- **Player and lantern:** footsteps from grounded travel; a soft flame at the lantern; sparse metal/rope creaks from actual relative swing; shutter/filter sounds from actual control travel and detents. One-shots need thresholds and cooldowns so steady motion does not rattle continuously.
- Keep creature discovery, tool feedback, and later collective return acknowledgment distinct in the mix. Future multiplayer voice should have reserved source budget and its own validation pass.

The project tracker already asks for a small pool of nearby voices with distance/hysteresis and forbids misleading averaged group locations (`/home/s/org/projects/mushi-lantern.md`, M3 Audio). This plan preserves that constraint.

## Backend and data path

Use Prim's pinned community Godot Steam Audio extension as the starting point: stechyo `godot-steam-audio` commit `8f65c29b21c1d8cdbf2d6dbfc53c92ef95dd2a93`, Steam Audio SDK 4.8.1, and Prim's five extension patches. Reuse the relevant pinned Godot audio teardown patch as well. The stock `godot4` binary crashed on isolated playback exit with `free(): invalid size`; Prim's patched 4.7.2 binary completed the same probe. This establishes a build compatibility difference, but does not isolate that one patch as the cause. Pin source, build recipe, patches, and notices in this repository instead of depending on a mutable Prim checkout. Start Linux desktop with the patched point-source binaural path, mono source assets, one active listener, and **direct HRTF only**. Forest ambience is diffuse and the grove has few hard surfaces, so occlusion and reflections are low-priority even beyond the first pass. Strong occlusion could also erase the hidden-mushi cue. Keep Godot's panning/attenuation from processing the source a second time, and use `SteamAudioPlayer.play_stream(stream)` rather than assigning `.stream` directly. Future voice should reuse Prim's Iroh voice stack and these compatible engine/extension builds; voice integration remains a separate milestone.

The GPU simulation already copies 24 float32 words per agent into CPU arrays asynchronously about every 0.12 seconds (`scripts/gpu_flight_simulation.gd`). At 1024 agents this is 96 KiB per snapshot, roughly 0.8 MiB/s at that interval. Audio should consume those existing stable-index positions, velocity, lifecycle, and arousal arrays after `snapshot_applied`; it does not need another GPU readback. Audio positions can interpolate between snapshots, with a modest stale-data timeout. Reset/reseed, returned agents, and stale snapshots fade and release their voices safely.

Start with a hard cap of **24 concurrent spatial sources**, provisionally 12 mushi, 6 forest, 4 lantern/tool, and 2 footsteps. Count fades and one-shots inside the cap. Choose nearby audible agent IDs using distance and modest activity, retain an incumbent until a newcomer is clearly better (about a 20–30% score margin), give slots a minimum hold time, and crossfade reassignment. Prefer one actual agent from each nearby cluster or cell when possible; never move a sound to an average location between distant creatures. Let call timing remain sparse even when all 12 mushi slots are assigned. Reserve capacity for later voices by making category caps configurable, not by assuming 24 is the final mix budget.

Use small generated mono 48 kHz WAV placeholders, with several resonant-noise mushi variants and simple chirps, footfalls, metal/rope movement, control detents, flame, and insects. Generate them offline and commit the source generator and provenance; keep reproducible WAV outputs out of Git. Avoid synthesizing waveforms per audio frame in GDScript. Route categories through buses for independent level and mute controls. Keep a nonspatial UI bus. The final samples and subjective mix remain a listening pass.

## Implementation sequence

1. **Pin and load the backend.** Bring in the reproducible extension/SDK build and necessary Godot patch with notices. Add a desktop-safe audio bootstrap/listener attached to the active camera and a few temporary sound emitters. Check startup, playback, listener turn, source stop, reset, and clean exit. Keep the existing desktop and XR camera selection explicit.
2. **Prove the full-scene budget.** In the 1024-agent grove, compare audio disabled, direct HRTF with 1, 12, and 24 live sources, then brief 32/48-source stress cases. Run at least 60 seconds at 24 audible sources and repeatedly stop, reset, and exit to catch lifecycle failures. Measure delivered frame times (p50/p95/p99), process CPU, existing GPU snapshot apply time, source churn, and captured audio output/underruns where available. Capture finite, nonzero left/right output for sources on both sides and after a listener turn, checking for overflow. Repeat at 512 agents if the 1024 result leaves little headroom. Keep the source count or effects lower if target frame delivery regresses. This must happen before polishing sounds.
3. **Integrate gameplay sources.** Add the stable-ID selector and sound pool, then forest positions, grounded footsteps in both desktop and XR rigs, and lantern flame/swing/control event emitters. Audio observes state; it must not modify flight, lantern physics, or player motion. Verify hidden creatures stay audible, source handoffs do not pop, continuous adjustment does not produce a constant creak, and parking/recall keeps sound at the physical tool.
4. **Listen and qualify.** Tune loudness and timing on desktop, then run a separate Beyond/Monado stereo and frame-delivery check when the user is ready. Test turning toward a hidden call, quiet standing, walking, handling the lantern, and the grove at 512/1024 agents. Check the release target separately: Prim's current staged extension is Linux `template_debug`, not evidence of a Windows/export-ready build. Add later voice and room acoustics only after the direct-cue mix works.

## Desktop feasibility completed

An isolated `/tmp/mushi-steam-audio-feasibility` Godot project loaded the Prim-pinned extension without touching this repository or XR. A read-only Nix-store addon symlink failed during Godot import because import metadata could not be written; copying it into the temporary project imported successfully. With the ordinary system Godot 4.7.2 binary, one-player headless playback aborted at exit (`free(): invalid size`). The Prim-patched Godot 4.7.2 binary completed the identical probe.

With a private PulseAudio null sink and the patched binary, one HRTF source gave nonzero captured stereo output (RMS left 0.0116, right 0.0226 for a source placed to the right). The temporary null-sink module was unloaded afterward; no user sink or XR runtime was changed. A four-second looped-source sweep completed without logged audio errors:

| Sources | Process user + system CPU time over ~4.5 s wall time |
| ---: | ---: |
| 0 | 1.11 s |
| 12 | 1.17 s |
| 24 | 1.41 s |
| 32 | 1.51 s |
| 48 | 1.59 s |

These are short isolated-process feasibility numbers while the host was also running VRChat. They show startup/playback stability and a plausible direct-HRTF source range, not full-grove frame headroom or freedom from callback underruns. The matched full-scene comparison and headset listening gate remain required.

## Senior review disposition

The Astra reviewer endorsed the existing delayed GPU snapshot, a bounded pool near actual agents, direct point-source HRTF first, and synthetic mono placeholders. Its main cautions were native lifecycle/exit, double spatialization, source handoff clicks, hidden-mushi occlusion, and reserving future voice capacity. Its final review added the sustained 24-source, repeated teardown, and left/right plus listener-turn capture gates; it also cautioned against attributing the stock-engine crash to a single unisolated patch. The sequence and gates above address those points. No full audio implementation is authorized by this planning checkpoint alone.
