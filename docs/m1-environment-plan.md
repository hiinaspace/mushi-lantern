> Follow-up: the user accepted the first greybox and authorized dispersed patches, 10% free starts, a smaller clearing and cliff/detour topography. The original central-three-pocket staging below is historical; see [current implementation](m1-environment.md).

# M1 environment feasibility plan — 2026-09-22

Approved design snapshot, 2026-09-22. Implementation is tracked in [m1-environment.md](m1-environment.md). The user subsequently authorized implementation with subagents, confirming a calm static nighttime target without wind or skinned trees. This plan supersedes older current-arena-only terrain notes where scale differs.

## Intent and decisions

Test whether a plausible natural environment can coexist with the accepted 1024-agent GPU simulation, with useful coarse avoidance and enough rendering headroom for later lighting. Preserve glyph size, appearance, loose-trains behavior and F1; do not reopen formation research or require CPU/ground parity.

User-confirmed: naturalistic shapes with simple materials; lighting refinement later; sayu PC VR at 90 Hz with headroom; both player and mushi remain inside the basin. Proposed scale pending preference: 128 m square first, then a bounded 256 m comparison. Treat those dimensions as the authored environment footprint including the enclosing slopes; the walkable basin is smaller. Do not imply a 256 m walkable floor plus another unbudgeted mountain ring.

Earlier plans agree on Terrain3D, heightmap clearance, coarse trunks/rocks, and built-in instancing before another scatter addon. The new scale is an expansion from the current 60 m ground slab. Keep a roughly 60 m central activity area initially so enlarging the scenery does not simultaneously dilute mushi density and alter the accepted herding behavior. The existing charter's clearing and three gathering pockets still fit.

## Verified integration constraints

- `project.godot` uses the Mobile renderer. Prior recorded target is Godot 4.7.2 on sayu; verify the installed engine and exact Terrain3D binary together during implementation.
- `scripts/main.gd` builds a 60 m slab, box walls and three trunks. Prop placement, simulation obstacles and lantern occluders are wired separately.
- `scripts/desktop_player.gd` explicitly zeros vertical velocity and sets global Y to zero each frame. Terrain requires gravity, floor snapping and a slope limit, not just replacing the floor mesh.
- `shaders/flight_compute.glsl` uses global floor/ceiling bounds, absolute preferred flight height and XZ-only cylinders. Dormancy, spawn, formation targets, goals and return presentation also need a ground-relative audit.
- `scripts/gpu_flight_simulation.gd` caps obstacles and mushrooms at 16 each. Do not silently truncate a forest to 16 collision proxies. Mushroom population need not increase for this pass.
- Its fixed 32-by-32 neighbor-grid storage already coarsens buckets with world extent. Larger maps therefore need a crowded-patch performance check as well as a dispersed check; increasing map bounds is not performance-neutral by assumption.
- Meadow source files exist at `/mnt/s/code/foresttesturp/Assets/NatureManufacture Assets/Meadow Environment Dynamic Nature`, including tree, bush and grass FBX models. The earlier Unidot-converted Godot project was not located in the bounded search, and no conversion was validated.

## Technology and assets

Use a pinned Terrain3D stable release; 1.0.2 is the documentation/release baseline researched here. Its platform documentation lists Vulkan Mobile support, but that does not validate this project's engine, compute interaction, stereo or export. First gate: editor and game load, terrain render, collision, reload and a small export with the exact engine/addon pair. Do an early headset render check before investing in dressing if the XR harness is available; full interaction work is a later milestone.

Start with Terrain3D's own instancer. It supports mesh placement and LODs with spatially divided MultiMeshes. Its documented caveats matter here: it does not create individual prop collisions, and multi-part imported scenes need preparation. Join trunk/leaf geometry into an appropriate mesh while preserving material surfaces, apply real-world scale/pivots, and verify LOD selection. Keep physics proxies in our placement data. See [Terrain3D instancing](https://terrain3d.readthedocs.io/en/stable/docs/instancer.html).

The user specifically suggested [ProtonScatter](https://github.com/HungryProton/scatter) for collision-bearing props. Its current [source](https://github.com/HungryProton/scatter/blob/main/addons/proton_scatter/src/scatter.gd) exposes chunked instancing, full scene copies and `keep_static_colliders`, which creates static shapes through PhysicsServer3D. This is a concrete reason for a bounded comparison after the basic Terrain3D gate: scatter a small set of trunk/rock scenes with simple shapes onto a slope, verify retained player collisions, save/reload/export, and inspect the placement transforms needed by the GPU proxy buffer. Enable editor terrain collision when projection depends on it. Do not rely on older Godot 3 wiki limitations as current behavior.

Adopt ProtonScatter for trunks/rocks if that trial simplifies authoring; retain Terrain3D instancing for decorative vegetation. Each prop category must have one owner so meshes/colliders are not duplicated. Bake/cache placement results and disable runtime regeneration. The GPU simulation does not consult PhysicsServer3D automatically: the same placements must still populate its coarse avoidance data. If extracting consistent transforms costs more than it saves, use the shared placement records directly. Scatter is an authoring option rather than an additional terrain or simulation system.

For the first terrain/collision gate, cylinders and irregular low-poly boulders suffice. For the performance gate, add a minimal representative kit: 2–3 tree variants with leaves, 2–3 rocks, one bush, and one or two grass clumps. Bare proxies cannot establish foliage performance: leaf coverage, material surfaces, shadows and overdraw matter alongside triangle counts.

Recommended source: offline-generated EZ-Tree trees exported as GLB, simple authored rocks, and a small grass/bush kit using original or explicitly redistributable materials. Do not create a runtime tree generator. EZ-Tree exports GLB, but its Three.js wind/LOD runtime is not a Godot integration; prepare Godot materials and LODs explicitly. Exporting all generated LODs requires checking that they are not rendered together. Retain tool version, seed, settings and asset/texture provenance. The repository is MIT; inspect the chosen textures' provenance rather than inferring all inputs from the generator license. See [EZ-Tree](https://github.com/dgreenheck/ez-tree) and its [license](https://github.com/dgreenheck/ez-tree/blob/main/LICENSE).

Meadow is a useful optional fidelity/performance reference, not a dependency of the prototype. If the generated kit is unrepresentative or slower to prepare, trial one tree, one grass clump and one rock from the existing source. Rebuild simple Godot materials; do not port the entire URP environment or shader system. Locate the prior Godot conversion only if using this route. Before distributing selected pack content, inspect the actual asset terms and keep source-pack files outside public source commits. No claim about the pack's license was established in this planning pass.

## Bounded implementation sequence

### A. Establish a comparable baseline

Record the existing accepted scene on sayu at 1024 agents with the documented loose-trains settings, same seed and fixed wake/herding route. Record engine, renderer, GPU, resolution and active refresh rate. Keep the saved preset private. Retain a dense awake fixture as well as ordinary patch activity, since dormant agents can hide costs. Baseline source is recoverable from Git; a permanent old-backend selector is unnecessary.

### B. Build the basin and ground integration

Create one deliberately authored, seeded basin: broad gently undulating floor (initial proposal: 1–3 m relief), a clearing, three nearby gathering pockets and two readable routes. Surround it with irregular steep slopes (initial proposal: 10–20 m rise), rather than four straight embankments. Start around 1 m height sample spacing. Use explicit world origin/spacing and float heights, with border samples/padding appropriate to Terrain3D regions. No erosion pipeline, caves or overhangs are needed. Author from a simple height function or editor sculpt and save the resulting data; no runtime terrain generation is required.

Create a small world-surface interface owning origin, extent, height data and playable-area mask. Terrain3D is the visual surface; CPU grounding and the GPU height texture derive from the same saved terrain data. Upload static data once on load/rebuild, not once per agent or frame. Match Terrain3D's interpolation, or measure and conservatively bound any difference. Verify against terrain height queries at slopes, corners and region seams. Reject holes/out-of-region samples explicitly. [Terrain3D collision/height-query guidance](https://terrain3d.readthedocs.io/en/stable/docs/collision.html) and [heightmap conventions](https://terrain3d.readthedocs.io/en/stable/docs/heightmaps.html).

Use local ground plus the accepted flight offsets for mushi. Sample ahead for gentle steering and enforce clearance after motion; do not merely lift them after they have crossed a bank. Handle steep slopes with inward/tangential steering from the playable-area mask. Height following alone would let agents climb the rim. Keep a final guard outside the reachable basin; normal play must be contained by visible slopes and steering, not visibly pressing against a rectangle. Return/ascent agents are a separate lifecycle and must retain one-time accounting.

Ground player, mushroom patches, lantern/reset pose, return area and visual markers consistently. Enable terrain collision for the player and use slope-limited movement. No per-agent physics bodies or per-agent CPU raycasts. Debug overlays show height samples, flight bands, basin limits and proxies.

Gate: walk and herd uphill/downhill, wake dormant patches on slopes, round a steep bank, return a group, reset and reload without buried agents, rim escapes, invalid heights or broken accounting. Minor glyph/tail clips are acceptable; sustained ground penetration or trapped groups are not.

### C. Add coarse static obstacles

Save deterministic placement records containing asset ID, transform and optional simple proxy. Generate rendered instances, player collision and GPU avoidance data from those same records. Trunks use finite cylinders/capsules; rocks use spheres/ellipsoids or a few simple proxies. Height-aware tests allow flight over low rocks without treating them as infinitely tall columns. Leaves, twigs and grass have no collision.

Replace the fixed 16-obstacle arrangement with a bounded static buffer and a small spatial index of nearby proxy IDs built at load. Report capacity overflow. Query nearby cells for steering and final overlap correction; include obstacle extent and motion lookahead when choosing cells. Use finite fallbacks for exact-center overlaps and check fast approaches for tunneling. Keep lantern trunk/rock occlusion consistent enough that an attractive source behind an obstacle cannot override clearance. Terrain-ridge occlusion can use a bounded heightfield segment test; test its cost separately. Fine leaf shadowing does not drive simulation.

Gate: a lantern behind a trunk cannot pull a group persistently through it; agents can pass above a low rock; narrow routes do not permanently trap a school. Shared transforms align physical and visible obstacles.

### D. Dress to representative cost, then compare scale

Use Terrain3D instancing with baked seeded transforms. Exclude the clearing/routes and steep slopes from inappropriate vegetation. Add representative trees, rocks, bushes and grass in steps. Initial authored-load bracket for 128 m: roughly 100–200 trees, 50–100 rocks, and 10k–30k grass clumps, with count and visible-density measurements. These are experiment inputs, not performance promises; prioritize convincing near-field coverage over uniformly filling every square meter.

Use simple opaque rock/bark materials and cutout leaf/grass materials. Provide near/far mesh detail, explicit draw distances and bounded shadow distances; avoid full-detail grass shadows across the map. Include one ordinary shadowed light and a bounded lantern-light comparison so the test does not rely entirely on unlit materials. Refined darkness, adaptation, bloom and wind remain later work. Darkness itself does not eliminate rendering cost without culling/range decisions.

Compare 256 m only after 128 m works. Preserve the central routes and local density, expanding the surrounding terrain/forest; do not scale trees or agent speeds. At equal prop density the larger footprint has four times the placed area, but visible work depends on culling. Retain 1024 mushi, initially concentrated in the same playable pockets. A dispersed 1024-agent layout is a separate exploration/density check. No automatic jump to 4096 agents to preserve population density.

### E. Measure and make the human decision

Use a fixed route through the clearing, dense vegetation, trunk/rock passage and a view across the basin. Warm imports/shaders before three measured runs, keeping first-load stutters as separate evidence. Suggested run length: 90 seconds each, followed by a 5–10 minute lifecycle/herding check. Stage matrix: existing baseline; terrain alone plus simulation; terrain/proxies; representative foliage; 256 m comparison. One dense-prop stress case and the awake-agent fixture bound the trial; no open-ended optimization sweep.

Record CPU and GPU frame-time distributions (p50/p95/p99), compute phase timings, draw calls, visible instances/triangles, VRAM, frame spikes and correctness counters. Use actual GPU timing, not CPU dispatch time. Compare identical camera routes/settings; report desktop resolution separately from headset per-eye resolution. Optional 2048-agent stress is retained as an experiment, not required for acceptance.

90 Hz gives 11.11 ms between frames. Proposed initial environment-plus-simulation target: p95 application CPU and GPU times each at or below roughly 8 ms on the actual headset configuration, with p99 below the frame interval and no sustained missed frames. This is a provisional headroom target, not a guarantee that the remaining 3 ms covers lighting and compositor costs. Check actual runtime frame delivery. If it fails, identify simulation versus shadows/overdraw/geometry/culling before reducing the accepted population. The prior ~4 ms p95 compute fixture is already material and must be remeasured here.

Desktop success is an integration gate only. Final environment acceptance requires both-eye correctness, headset frame delivery, readable mushi against foliage and a short human herding test. If XR setup is not ready, record that gate as outstanding; do not infer stereo viability from desktop FPS. Verify a packaged build loads terrain, props and the native addon; target Windows OpenXR export readiness remains explicit.

## PC VR hardware coverage and settings

User follow-up: sayu is a high-end development machine, not the audience baseline. A 512-mushi setting and lower environment detail are acceptable. Standalone Quest, mobile and Steam Frame compatibility are not targets. Godot's Mobile renderer remains the current desktop rendering choice; its name does not change that scope.

The [Steam hardware survey](https://store.steampowered.com/hwsurvey/) provides overall GPU/CPU statistics and headset statistics separately. The public tables inspected here do not cross-tabulate CPU/GPU models for VR owners, so they do not establish a median PC VR configuration. CPU clock/core counts also do not identify equivalent CPU performance. Use hardware popularity as context, not a measured VR audience percentile.

Two published PC VR examples bound expectations, without predicting our game's performance: [Half-Life: Alyx](https://store.steampowered.com/app/546560/HalfLife_Alyx/) lists minimum i5-7500/Ryzen 5 1600, 12 GB RAM and GTX 1060/RX 580 with 6 GB VRAM. [Into the Radius 2](https://store.steampowered.com/app/2307350/Into_the_Radius_2/?l=english) lists RTX 2060 and i5-7600K/Ryzen 5 3600 minimum with 72 Hz recommended; its recommended tier lists RTX 3080 and i7-8700K/Ryzen 7 5700 with 90 Hz. These are publisher requirements, not benchmark results or demographic evidence. Inspected 2026-09-22.

Proposed engineering coverage targets, pending real-machine tests:

| Role | Example test hardware | Proposed workload |
| --- | --- | --- |
| Accessible PC VR target | Desktop RTX 3060 12 GB, Ryzen 5 3600/5600 or Core i5-10400/12400, 16 GB RAM | 512 mushi, reduced decorative foliage/shadows, 90 Hz goal at documented per-eye resolution |
| Standard/high comparison | RTX 3070/3080-class test machine, modern six-core CPU | Try 1024 mushi and fuller dressing; select settings from measurements |
| Development ceiling | sayu RTX 4090, record actual CPU | 1024 accepted appearance plus high-detail stress; cannot certify lower tiers |

These are chosen test points, not claims of exact equivalence, median ownership, supported minimum specifications or achieved 90 Hz. Include an AMD PC test if one is available; vendor shader/driver coverage is a separate concern from throughput. No hardware purchase is implied. Recruit a friend/tester on a representative machine for the same packaged route when available. If no such machine is available, leave audience-performance qualification open. A resolution increase or an arbitrary 4090 speed multiplier cannot emulate an older GPU/CPU/VRAM limit, and no power/clock changes are part of this plan.

Add a small persistent settings menu during the environment pass:

- Mushi population: 512 / 1024, retaining 1024 as the accepted default; 2048 stays an advanced experiment. Apply count changes on explicit restart/reset, never silently delete active agents or corrupt return totals. Check that 512 retains useful school density and the same route/goal intent.
- Vegetation: reduce decorative grass/bush density and range, then use cheaper tree LODs. Keep collision-bearing trunks/rocks and route silhouettes in every preset; do not leave invisible obstacles.
- Shadows: quality and range, grass shadows disabled on the lower preset, bounded lantern shadows.
- Render scale and antialiasing: expose supported controls with a safe minimum for glyph readability; record actual per-eye dimensions and runtime supersampling. Keep control semantics clear to avoid accidental double scaling.
- Texture quality if measured VRAM use warrants it. Lower draw distance alone does not unload resident textures.

Use two authored presets plus individual overrides, rather than an automatic quality system. Keep simulation cadence and accepted coefficients stable. Render scale cannot fix compute-bound simulation; population reduction cannot guarantee shadow/overdraw relief. Diagnose with separate timings and show an optional frame-time display.

Add 512/1024 comparisons to the same representative environment route. Half the population need not mean half the compute time: pair searches, sampled interactions and fixed costs scale differently. Reducing decorative detail must preserve basin containment and coarse avoidance. The roughly 8 ms p95 headroom goal should apply to the chosen audience hardware/settings as well as sayu; merely achieving that on sayu is insufficient. Validate memory on an actual smaller-VRAM card before making a minimum specification claim.

## Exit and scope budget

Deliver one playable basin, repeatable placement/asset provenance, terrain-following simulation and player, coarse obstacle avoidance, retained F1, and a short measurement ledger with exact commands/settings. Select 128 or 256 m based on traversal, density and measured cost. Stop for human review before environmental polish.

Keep this to one bounded jam milestone. Do not build a general biome system, a runtime asset generator, networking, precise foliage collision or a new formation model. If asset conversion consumes the pass, use the simplest representative kit and keep the higher-fidelity comparison optional. Keep debug evidence, imported pack sources, user presets and downloaded tool binaries out of source commits and game exports where they are not runtime dependencies.

Additional source: [Terrain3D platform support](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html). Documentation support claims are not measured project results.
