# M1 — Terrain3D basin and static environment

Implementation after the approved [environment plan](m1-environment-plan.md). The default scene is a 128 m square authored footprint including the valley rim. `--terrain-size 256` expands the surrounding basin while retaining the central activity area, agent count and movement scale. The scene now begins an initial dark, calm nighttime pass: very low ambient illumination, a fixed starfield with subtle bright-star twinkle and lantern lighting, with no directional illumination or shadows. A tall green goal beam provides orientation above the landscape. There is no wind, skinning or branch animation.

## Run and inspect

```bash
./launch.sh
./launch.sh --preset 7 --saved-preset "loose trains" --count 1024
./launch.sh --terrain-size 256 --preset 7 --saved-preset "loose trains" --count 1024
```

The named preset command reads the user's existing private saved preset; it is not bundled in the game. Without that name, the built-in Longer drift default remains. An explicit `--count` overrides the saved preset's count. F1 still opens the behavioral sandbox. F2 opens quality controls and pauses the simulation while the menu is open; choose 512 or 1024 and explicitly apply/reset to change population. Vegetation, shadows and 80%/100% 3D render scale apply independently. Preferences live in `user://m1_quality.json`. Runtime/headset supersampling is separate. The normal launcher retains its 60 FPS desktop cap; benchmarks below bypass it.

Test card:

1. Walk from the clearing to several mushroom patches. Check that the player stays grounded over rises and does not snag on ordinary slopes.
2. Wake a group with orange, move it around a nearby trunk/rock, then let it settle. Check readable flight above the ground, useful obstacle avoidance and recovery of a split group.
3. Walk toward the rim; its rising terrain bounds the basin. Mushi turn inward before reaching the steep banks. Player outward movement fades on the lower bank; a final guard stays within the terrain footprint.
4. Return a group to the clearing, reset, and try 512 through F2. Count changes intentionally start a new run; quality changes retain collision-bearing props and the route layout.
5. Inspect the forest fringe, including both close foliage and distant crowns. Compare low/high vegetation and shadows. The 256 m variant tests surrounding-area cost, not four times as many mushi.
6. At the east terrace, step down toward `(10, 0)`, try the steep face from below, then walk around the south side to regain the top near `(20, 0)`. Check that the route reads clearly without a wall or jump mechanic.

## Initial night pass

The terrain scene now uses a directional procedural starfield, blue ambient energy 0.012, and no sky reflections. Directional light energy is zero and its shadows remain disabled at every quality setting. The lantern remains the main scene light: high/default shadows preserve its foliage and terrain shadows; the low-shadow setting disables them as a performance fallback. Mushrooms, mushi and the goal remain self-lit visual cues.

A green unshaded core and faint halo extend 300 m upward from the goal. They cast no shadows and add no scene light; ordinary depth testing lets hills hide the base while the upper beam shows against the sky. This is an orientation placeholder, without final fictional styling. Test it with the lantern shutter both open and closed, especially from behind a ridge. Rendered checks passed at 128 and 256 m with 512 GPU agents, including all lantern colors, open/closed shutter and high/low shadow settings. Captures and raw logs are retained in `artifacts/m1-night/`. The rendered test is part of `check-environment.sh`; screenshots establish desktop visibility in those views, not headset readability.

## Artificial adaptation and navigation light

All lantern modes now use a 55-degree angular radius (110-degree full cone) with soft angular attenuation. The terrain simulation's colored-light cone follows that width; clear mode remains behaviorally neutral. Clear light reaches 20 m at base energy 10, versus 10.5 m and base energy 3.4/3.8 for blue/orange. High-quality lantern shadows remain enabled.

`NightAdaptation` tracks a visual-only `night_vision` value in [0,1]. Fully open clear targets 0; either colored filter targets 0.75; a closed shutter targets 1. Partial shutters interpolate those targets. Exponential time constants are 1.5 seconds toward light adaptation and 6 seconds toward dark adaptation (about 4.5/18 seconds for 95% of a full transition). Pausing also pauses adaptation. Light output is multiplied by `1 + 0.7 * night_vision`, so a dark-adapted player sees a short bright onset before clear illumination settles. This visual gain does not multiply the simulation stimulus.

The sky keeps fixed star positions in 3D direction space, avoiding latitude/longitude pinching and seams. Sparse bright guide stars remain visible after clear-light adaptation; many independently revealed dim stars and a mottled, tilted Milky Way band appear as night vision returns. Only the bright stars twinkle slowly, with independent phases and modest HDR brightness for the existing bloom. Ambient lighting, goal beacon and mushi colors do not adapt in this pass. This deliberately authored effect is not biological vision simulation or engine auto-exposure. The unused sky radiance pass returns a constant dark color and uses a small cubemap; detailed stars are evaluated only for the visible background.

Godot's [built-in debanding](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-anti-aliasing-quality-use-debanding) is enabled at project startup. A local 4.7.2 Vulkan Mobile gradient probe verified that the on/off setting changes gradient pixels without lifting pure black; no extra fullscreen shader was added. Probe source: `tests/debanding_probe.gd`; evidence: `artifacts/m1-night/debanding-probe/`.

Headless `tests/adaptation_checks.gd` passes monotonic transitions, frame-step consistency, shutter/mode targets and output/range checks. Rendered `tests/night_scene_checks.gd` passed both map sizes, including bright onset, clear settling, sky uniform agreement and dark recovery; comparative captures and logs are in `artifacts/m1-adaptation/`. A warmed three-second-per-view 256 m / 1024-agent desktop smoke passed with finite simulation, but is not a full performance matrix or VR qualification.

The richer sky follow-up passes `tests/night_sky_checks.gd` (sparse/intermediate/full adaptation, two zenith views, fixed-time twinkle) and the 256 m full night scene check. Captures in `artifacts/m1-night/sky/` were visually inspected; the initial periodic haze was replaced with smooth 3D cloud noise, with faint screen-pixel dithering confined to the haze to reduce Mobile HDR banding. Final full-scene captures and a warmed 256 m / 1024-agent, 1440×900 desktop smoke are in `artifacts/m1-starry-sky/`: viewport GPU p95 0.205/0.234 ms and upload+compute p95 0.902/0.902 ms for central/wooded views, finite simulation, zero failures. These short, separate timing distributions are not additive frame budgets, a controlled before/after comparison, or headset/midrange qualification.


## Foliage luminescence and subtle bloom

Sparse, stable, soft-edged teal-green markings on grass, bushes and tree leaves become visible as `night_vision` passes 0.90 and reach full strength at 0.99. Colored lanterns settle at 0.75, below the onset; closing the shutter and waiting reveals the markings. Both tree LODs participate. The shader retains normal lantern lighting, cutout depth/shadows and foliage culling, and does not add lights or animate the spots. The effect is intentionally faint and sits below the bloom threshold.

Global Godot glow is enabled for a slight halo, with Mobile HDR threshold 0.90, HDR bleed scale 0.20, intensity 1.5, no bloom floor and mostly small blur levels. Mushi use a modest 1.4 HDR emission gain with slightly paler bright rings. Their shape, size, simulation and alpha remain unchanged. The goal beam's emission was reduced to 0.3 while retaining its unshaded green core, so it does not dominate the glow. Other very bright objects can still bleed, as intended; this is threshold-based global bloom, not an object mask. F2 provides a persistent **Bloom** toggle without resetting the population.

`tests/night_bloom_checks.gd` rendered off/on comparisons and isolated blue/green/orange glyphs with measurable halo outside their silhouettes on the local Mobile renderer. `tests/foliage_luminescence_checks.gd` passed with no visible emission at 0.75 night vision and sparse markings at 1.0. Integrated night checks passed on both map sizes; the final rounded-fleck version was also captured in the 256 m scene. Glow controls follow the [Godot Environment API](https://docs.godotengine.org/en/4.6/classes/class_environment.html). Bloom comparisons are retained under `artifacts/m1-night/`, and foliage/integrated captures under `artifacts/m1-luminescence/`.

## Implementation

`EnvironmentSurface` generates a deterministic one-metre float height grid, irregular raised rim and shared prop records from seed 40721. The F1 seed resets agents; it does not regenerate the world. Terrain3D, CPU grounding and the GPU height texture derive from the same samples. The map is generated once on scene load and does not deform during play. `TerrainEnvironment` uses Terrain3D's instancer and simple original meshes/materials, with static cutout leaves and grass plus a coarser distant tree mesh. No Meadow assets or external texture pack are included.

The revised basin has nine walkable mushroom patches at 128 m and 18 at 256 m. The GPU source packet accommodates up to 32 patches, so the 256 m layout does not truncate them at the old 16-patch limit. Roughly one agent in ten, selected by stable ID, starts away from patches within the playable basin; the rest are distributed among the patches. This gives solo wanderers and more places to wake groups without increasing the accepted 1024 default. The central goal remains the gathering target. The old open-center exclusion has shrunk to 10 m for trees, 8 m for rocks/bushes and 6 m for grass, with local clearance around patches and player/goal starts; this allows foliage closer to the action while keeping the return route readable.

Three raised central terraces add one-way drops inside the basin. Their steep front faces can be descended; gentler rear and side slopes provide a walking route back up. At the east terrace, the sampled top at `(20, 0)` is 5.86 m above `(10, 0)`. The actual desktop player capsule descended and landed, stopped at x=13.75 when trying to walk straight uphill, and returned to the top through `(10, 22) → (37, 22) → (37, 0) → (26, 0) → (20, 0)`. This passed on both 128 and 256 m terrain in `tests/environment_traversal_checks.gd`; it verifies physics traversal at those points, not every route or human comfort.

Trunks/rocks share transforms and coarse dimensions between player shapes and GPU proxies. GPU flight has a bounded static spatial index supporting 1024 proxies instead of the old 16-fixture limit. Height-aware trunk/rock avoidance allows flight above low obstacles. The terrain-relative upper flight band is a soft target: after crossing a cliff, agents can temporarily remain above it and descend through velocity-limited steering instead of snapping to the lower ground's ceiling. Ground clearance remains hard. A separate emergency altitude guard above the highest terrain sample bounds runaway states; it does not follow individual cliffs. A 600-tick rendered GPU regression crosses an 8 m drop, permits temporary above-band flight, checks each step against the speed limit, and requires lowland settling. It passed with a largest one-step descent of 0.113 m; terrain lifecycle, vertical-translation blue attraction and flat GPU smoke also passed. Evidence: `artifacts/m1-environment-v2/cliff/`. Ground-relative spawn, dormant settling, mushroom attraction, flight bands, lantern targets and return ascent retain the accepted simulation lifecycle. Leaves and grass are decorative; fine clipping is acceptable. Light occlusion is a coarse bounded approximation, not a renderer-derived shadow test. Its four GPU beam samples can miss narrow trunks or over-shadow a low rock when a sampled height differs from the actual ray crossing; movement avoidance uses separate height-aware proxies.

Native Terrain3D heightmap collision showed repeatable missed ground rays on this local engine combination. Player grounding therefore uses a static triangle collider baked from Terrain3D itself, with native heightmap collision disabled. The 128/256 m variants contain 32,768/131,072 ground triangles. A grid of 100 rays per size passed across region seams and gathering pockets, with less than 0.00005 m difference from queried terrain height. This workaround does not add per-agent physics or a separately authored height surface.

Low vegetation reduces decorative instances and their distance; it keeps collision-bearing trunks and rocks. Low shadows disables tree/bush and lantern shadow work and shortens directional shadow range. Grass does not cast shadows. These are actual renderer controls: darkness alone does not remove rendering work. F1 field diagnostics are excluded from performance runs.

The supported terrain path requires Vulkan Mobile and GPU flight. `--flat-lab` retains the old comparison for regression tests; headless main-scene tests use that legacy surface. Compatibility renderer launches reject the terrain scene rather than silently running an ungrounded CPU simulation. The glyph bounds were enlarged for the map and return ascent.

A bounded ProtonScatter trial at commit `2ced25f1` retained three static colliders on a slope and restored them after saving/loading cached placements. Editor projection and package export of Scatter were not tested. This seed-generated map already has one placement source serving instancing, physics and GPU avoidance, so Scatter is not included as a second dependency. Retained trial script/provenance: `artifacts/m1-environment/scatter-trial/`.

## Validation and performance

For the revised `basin-128m-v2` / `basin-256m-v2` layout, the surface, actual-player traversal, GPU spawn, vertical blue-target and lifecycle checks passed. Spawn checks cover 512 agents on 128 m and 1024 on 256 m, deterministic resets, patch counts differing by at most one agent, and free starts outside mushroom/prop footprints. The rendered main-scene check verifies all nine visible 128 m patches match the simulation sources. Current logs are in `artifacts/m1-environment-v2/`; the terrain-ray log is `artifacts/m1-environment/surface-check-v2.log`. The earlier measurements and package smoke below describe v1.

Focused checks pass at 128/256 m: terrain height agreement and collision rays, 1024 GPU agents with more than 16 proxies, and a 900-tick uneven-terrain lifecycle fixture covering dormancy, rim containment, low-rock overflight and reset back to flat. The F2 settings test covers persistence and explicit population application; the rendered scene check covers actual player floor contact and 512/1024 resets. Final `check.sh`, `check-gpu.sh` and `check-environment.sh` passed on sayu. A paired 180-tick blue-herding test also passed: translating terrain and lantern upward by 10 m gave zero measured trajectory difference after translating back, with clear attraction. Logs are retained as `artifacts/m1-environment/final-{headless,gpu,environment}.log`. Headless editor import emits a Terrain3D editor preview cleanup leak at exit; the rendered gameplay fixtures have no corresponding leak/error. The first combined environment suite was rejected because its settings fixture left a saved 512-agent preference for the fresh-default scene test; each fixture now receives its own isolated user directory. Automated scene checks establish terrain collision, finite state and reset behavior; they cannot establish herding feel or headset comfort. PC VR at 90 Hz and lower-tier hardware remain explicit qualification gates.

```bash
./check.sh
./check-gpu.sh
./check-environment.sh
```

**Historical M1 v1 benchmark.** The table below measured the first 128/256 m layout before the later patch-count, clearing and traversable-cliff revision. It is retained as a comparison record, not a performance measurement of the revised scene. The benchmark harness `tests/environment_performance.gd` uses the documented loose-trains coefficients, seed 40721, a central wake view and a forest-facing view. It fixes the render viewport at 1440×900 independently of compositor window tiling, hides field diagnostics, and reports viewport rendering and custom compute timings separately. These are two static viewpoint diagnostics, not a complete traversal or headset workload. Do not add their percentile values as though they were simultaneous frame samples.

```bash
mkdir -p /tmp/mushi-bench-local
XDG_DATA_HOME=/tmp/mushi-bench-local MUSHI_BENCH_SECONDS=30 godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --script tests/environment_performance.gd
XDG_DATA_HOME=/tmp/mushi-bench-local MUSHI_BENCH_SECONDS=30 MUSHI_BENCH_COUNT=512 MUSHI_BENCH_QUALITY=low godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --script tests/environment_performance.gd
```

GPU timestamps are polled every rendered frame by the harness. Polling only at the 30 Hz simulation dispatch can miss timestamp results when rendering runs much faster; the rejected initial instrumentation run is retained with the evidence. A first unbounded-window run was also rejected because the compositor resized its render surface. Neither is included in comparisons. A late blue-target height correction and F1 marker correction do not affect these orange/clear, F1-hidden measurements. The final imported shader passed a separate three-second-per-view timing smoke (`post-blue-smoke.log`); final source hashes are retained in `final-source.sha256`.

Three completed runs per configuration on sayu (Godot 4.7.2, Vulkan Mobile, RTX 4090, Ryzen 9800X3D) measured each static view for 30 seconds after a five-second warmup. Every range below is the minimum to maximum of the **six per-view p95 values**. The baseline is the frozen pre-environment source under `artifacts/m1-environment/baseline`; it uses the same viewpoints and accepted loose-trains coefficients. All runs rendered at 1440×900, with low quality using 80% 3D render scale. Logs `baseline-[123].log`, `128-high-[123].log`, `128-low-[123].log` and `256-high-[123].log` are retained under `artifacts/m1-environment/`.

| Scene / setting | Mushi | Wall frame p95 (ms) | Process p95 (ms) | Viewport render CPU / GPU p95 (ms) | GPU upload + compute p95 (ms) | Draw calls p95 | Godot video-memory monitor max (MiB) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Frozen flat baseline | 1024 | 0.605–0.655 | 2.341–3.699 | 0.060–0.071 / 0.060–0.066 | 1.073–1.127 | 18–29 | 137.5 |
| 128 m, high | 1024 | 0.879–0.901 | 2.504–2.909 | 0.103–0.118 / 0.253–0.265 | 1.084–1.293 | 118–149 | 141.0 |
| 128 m, low | 512 | 0.673–0.748 | 2.465–3.478 | 0.086–0.095 / 0.145–0.150 | 0.551–0.569 | 99–124 | 101.1 |
| 256 m, high | 1024 | 0.883–0.905 | 2.507–2.826 | 0.109–0.124 / 0.224–0.270 | 1.067–1.250 | 136–173 | 187.7 |

The terrain and foliage increase visible draw calls and viewport render time, while the 256 m case remains close to the 128 m case from these two viewpoints. The 512-agent low setting roughly halves measured GPU upload-and-compute time. The low row changes population, vegetation, shadows and render scale together, so this matrix does not attribute its rendering improvement to any one control. Wall frame times are from an unthrottled desktop window; process, viewport and compute monitors sample different work at different times, and their percentile values cannot be added into a 90 Hz frame budget. Godot's video-memory monitor is not a measurement of total driver or headset VRAM use.

## Scope and next gates

This is a small original nature kit, not final realistic forest art. It represents leaf cutout coverage, geometry, static shadows and grass instancing, but not the texture memory, material complexity or visual quality of a full Meadow scene. The final dark lighting pass can choose shorter distances after evaluating the actual visibility needs.

The development machine's RTX 4090/Ryzen 9800X3D results cannot establish a supported minimum spec. The proposed RTX 3060/Ryzen 3600–5600-class 512-agent target remains untested. No Quest, mobile or Steam Frame target was added. Full OpenXR, stereo frame delivery, subjective herding/comfort and Windows export validation remain subsequent gates.


## Local package smoke

```bash
scripts/package-scene.sh
cd artifacts/m1-environment/package
godot --main-pack mushi-lantern.pck
```

This produces a runtime resource pack and its Linux Terrain3D libraries for an installed Godot engine; it is not a standalone Linux or Windows release. Packaging uses an isolated staging copy, excludes evidence/docs/tests/user data, and disables the editor-only Terrain3D plugin in that copy to avoid its headless preview cleanup leak. Runtime extension loading remains enabled. The working project's editor plugin remains available.

The initial M1 v1 pack built and started successfully from its package directory with isolated user data, rendering the 128 m terrain and 512 GPU agents before capturing and exiting. Evidence: `artifacts/m1-environment/final-package-build.log` and `artifacts/m1-environment/package/package-smoke.{log,png}`. A redundant fresh `--editor --quit` import crashed in this Godot build while generating GDExtension documentation; the helper now uses the export command's own import step. The rejected import log and coredump stack are retained separately.
