# Multiplayer stretch goal: feasibility gates

Planning draft, September 24, 2026. This is a stretch goal after the singleplayer
XR build. The target is 2–8 players. The first playable gate is two players
herding one host-owned shoal toward one shared goal. Voice, avatars, competitive
goals, and host migration follow only after that gate.

## September 25 implementation checkpoint

The bounded two-player desktop slice now has a host GPU path accepting up to
eight lantern fields, Prim-style private pkarr/Iroh transport, 13-byte visual
agent records in 856-byte independent datagrams, a display-only client replica,
reliable reset/score messages, and explicit `--host` / `--join` startup with
`MUSHI_ROOM_SECRET`. The host retains the single goal and score; joiners can
drop in after the host starts. The host can restart through the existing menu
with a desktop confirmation or a second XR press; a two-process localhost test
verified epoch 1 to 2 while the client stayed connected. The UI lobby, VR
keyboard, voice, avatars,
competitive mode, headset delivery and Windows export remain future gates.
The first lighting bound shows at most three nearest remote spotlights by
default, with remote shadows and remote omni fills off; the local lantern
retains its existing shadow setting. A rendered seven-peer-lantern fixture
checked caps of 0/1/3/7 without exceeding the requested count. GPU behavior
still receives all active peer lanterns. Actual eight-player stereo lighting
cost and visual quality have not been measured.
Each viewer estimates adaptation from their own lantern and the strongest
nearby peer beam, using the existing adaptation times and one value for both
eyes. Its visual result still needs a headset check.

Two actual rendered Godot processes joined through pkarr and exchanged all
1,024 agent ranges. The host sent about 0.81–0.83 Mb/s of snapshot application
payload to one client at the existing asynchronous readback cadence; the client
received 1,024 agents and the host's score reached 5 on both sides. With 200 ms
uniform synthetic receive jitter and 1% independent chunk loss, the client
reported zero agents stale for over 500 ms in the sampled five-second windows.
This is a localhost desktop test, not WAN, headset, voice or eight-peer proof.

A deterministic 1,024-agent moving-state replay through the same codec and
replica measured p95 live position error of 0.263 m under up to 100 ms jitter
and 1% loss, and 0.380 m under up to 200 ms jitter and 5% loss. Maximum sampled
frame movement was 0.039/0.047 m respectively; the replica converged to within
0.0017 m after motion stopped. This replay uses authored smooth motion rather
than actual GPU boid trajectories. Favor jitter characterization for the PC VR
target; the 5% loss case is a stress bound.

## Current implementation and hard seams

- `GpuFlightSimulation` owns the simulation on the main RenderingDevice. Stable
  agent IDs index a 96-byte state record; an asynchronous readback currently
  updates CPU arrays about every 0.12 seconds. The GPU state texture drives
  local glyph rendering. A client needs a separate upload path for replicated
  visual state; running an independent simulation will diverge.
- The 1,024-agent game steps at 30 Hz. The compute shader currently accepts one
  lantern's position, direction, filter and exposure. Multiple lanterns require
  an explicit GPU input array and a rule for combining their effects. Where
  blue and orange overlap, blend their opposing effects, bounded to the existing
  energy range. Test equal-strength cancellation and avoid multiplying total
  influence simply because more players joined.
- The host owns score, lifecycle transitions and one-time return accounting.
  Clients interpolate display state and receive authoritative score/events.
  The local lantern and hands remain responsive without waiting for a round trip.
- Prim has shared-secret pkarr rendezvous, authenticated Iroh peer connections,
  voice, and 20 Hz pose datagrams. Its current 1,100-byte application datagram
  cap and six-person room cap are not a game-state protocol or an eight-person
  proof. Reuse its patterns/code deliberately; add sequencing, chunking,
  expiration and recovery for shoal snapshots.

## Wire-size estimate

These are application bytes before packet headers, encryption, retransmission
and relay overhead. Each host snapshot is sent separately to each recipient.

| 1,024-agent representation | Bytes/snapshot | At 5 Hz per client | At 10 Hz per client | Host egress at 8 players, 10 Hz |
| --- | ---: | ---: | ---: | ---: |
| Complete 96-byte GPU state | 98,304 | 492 kB/s | 983 kB/s | 6.9 MB/s (55 Mb/s) |
| Implemented 13-byte record plus 16 headers | 13,696 | 68 kB/s | 137 kB/s | 0.96 MB/s (7.67 Mb/s) |
| 14-byte visual record | 14,336 | 72 kB/s | 143 kB/s | 1.0 MB/s (8 Mb/s) |
| 20-byte visual record | 20,480 | 102 kB/s | 205 kB/s | 1.4 MB/s (11.5 Mb/s) |

A 14-byte candidate has 16-bit x/y/z positions, 16-bit x/y/z velocities, one
byte of arousal and one byte of lifecycle/flags. Quantization ranges and visual
error need checking against both 128 m and 256 m terrain and below-ground
return travel. Do not transmit roll/pitch/yaw or social/formation internals for
render-only clients; derive glyph orientation from interpolated velocity and
retain the seed/trait table locally. Avoid codec, delta and sleeping-agent work
until the measured uplink/packet-loss gate calls for it. The existing full GPU
readback itself is about 0.8 MB/s at its nominal 8.3 Hz and 1,024 agents; its
latency and main-thread unpack time must be measured while networking.

The host receives only bounded lantern state (world pose, filter, shutter,
timestamp/sequence) from each client, likely tens of bytes at 20 Hz. Host-side
validation clamps pose changes, range, mode, and stale input. Treat a disconnected
lantern as closed/frozen until removal. Test LAN and relay paths separately.

## Gates and stopping rules

1. **Offline two-lantern gameplay spike.** Feed two lamps into the host compute
   shader with no network. Confirm both affect the same shoal, blue/orange blend
   reads well, score remains one-time, and 1,024-agent GPU cost stays within
   headset headroom. This isolates the largest simulation change.
2. **Two-process sync spike.** Reuse Prim rendezvous/Iroh with a versioned game
   protocol. Host sends visual agent-range chunks at 8–10 Hz with session epoch,
   sequence, tick, start ID and count. A client applies newer ranges independently,
   interpolates each agent behind the host, and drops stale chunks. Requiring
   every chunk before rendering a frame would amplify ordinary packet loss.
   Include a reliable join/reset state (seed, terrain/map version,
   traits/preset, current score and lifecycle) and
   resync after loss. Measure bytes, packets, queues, GPU readback delay,
   encode/decode/upload time and visible correction under 50/100/200 ms RTT,
   0/1/5% packet loss and short bursts. Proposed first-pass budget: added host
   CPU work at or below 1 ms p95 per snapshot, with no synchronous GPU wait.
   Start with 1,024 agents and one shared goal; test 512 as a
   fallback. Local mushi prediction is optional only if interpolation looks poor.
3. **Lighting and headset gate.** The Godot Mobile renderer permits eight spot
   and eight omni lights per mesh. Each lantern currently has a shadowed spot
   and a small omni fill; the goal also has omni lights. Eight lamps can hit
   the per-mesh limits, and their overlapping shadows may be costly earlier.
   Spawn 2, 4 and 8 moving lanterns in the actual grove, measure 128/256 m,
   low/default settings and Beyond stereo frame timing. Try one local shadowed
   beam plus cheaper/shadowless distant peer lamps and cull remote fill lights
   if needed. Preserve behavioral influence even when visual lighting is LODed.
4. **Real peer gate.** Two machines, then 4 and 8 peers across direct and relay
   connections. Confirm new joins, loss/reorder, host exit, score agreement,
   microphone quality if voice is included, and no persistent divergent mushi.
   Host departure may end the game with a clear message; migration is optional.

Keep each gate bounded. If the offline two-lantern or two-process gate does not
pass quickly, prioritize singleplayer export, menu and friend playtest for the
jam. Reserve at least half of the remaining jam time for singleplayer polish
and the exported judging build. Once two-player co-op is stable, add basic
tracked head/hands, Prim voice,
and avatar IK according to remaining time. Competitive multiple-goal play is a
later rule set because it changes scoring and mushroom/goal ownership.

If that later rule set fits the remaining time, keep the same terrain and
network architecture: put a larger mushroom ring near the center, spawn players
near it, place two shrines near opposite edges, and keep independent host-owned
goal counters. Players choose sides socially; no team identity or colors are
required. It still needs a versioned map/reset message and two-goal lifecycle
accounting, so it follows the shared-goal gate.

## Eye adaptation

Adaptation belongs to each viewer and must not be broadcast as one global
number. Start with a local estimate from nearby open clear beams: sample each
lantern's distance and cone exposure at the viewer's head, combine bounded
exposures, then feed the existing rise/fall timing. Colored beams can retain the
current weaker effect. Match adaptation in both eyes and verify that walking
away from an open parked or remote lantern restores night vision gradually.
