# M0e — bounded performance comparison

Authorized 2026-09-22 after acceptance of Living shoals behavior. Preserve the current 256/1024-agent comparison, seeded traits, sampled neighborhoods, energy, waking, lantern response, height controls and finite return lifecycle. Keep the CPU reference and ground fallback. This pass does not select small ground animals versus small flying shoals on artistic grounds.

## Backend comparison

The ordinary rendered flight launch uses GPU compute. The CPU reference remains an explicit comparison and the fallback for headless/Compatibility operation. Select the backend in the panel (resets the same seeded fixture) or launch explicitly:

```bash
./launch.sh --count 1024 --simulation cpu
./launch.sh --count 1024 --simulation gpu
./launch.sh --ground
```

GPU simulation uses the renderer's main RenderingDevice, with fixed-step state kept on the GPU and shader interpolation at display rate. CPU submission time is not GPU execution time. Delayed CPU snapshots serve inspection and lifecycle accounting; they are not the rendered source of truth. Stable IDs and monotonic lifecycle state preserve one-time return accounting. CPU and GPU floating-point trajectories are not promised to remain bit-identical over long runs.

The final kernel builds index-ordered cell buckets once per tick, then simulates against that snapshot. At the ordinary 3.6 m neighbor radius this preserves the CPU reference's rotated candidate probes and accumulation order. A bounded 32×32 allocation uses at most 4 MiB for bucket IDs. Very small tuned neighbor radii use candidate cells no smaller than `world_limit / 15` (1.8 m in this arena); exact distance filtering still uses the requested radius. Counts up to 64 retain all-pairs neighbors. The reference's swept cylinder collision is replaced by coarse pushout on the GPU, as authorized.

The renderer has one implementation: static instanced glyphs sampling a three-row position/energy/heading texture. CPU comparison uploads that texture only after a simulation tick; compute writes it directly. No old per-instance rendering mode remains. Headings retain their last useful direction at rest, with a shader fallback near vertical. Full state snapshots are read asynchronously every four ordinary 30 Hz ticks; there is no synchronous per-frame readback. Run records explicitly mark GPU return counts as delayed snapshots, which can lag a reset/close by the readback interval.

Compare resting at mushrooms, spontaneous waking, orange extraction, blue gathering, scattering, return and release. Evaluate group structure, energy distribution, response to the lantern and correction-free visual motion. Performance alone cannot approve behavioral parity. Retain evidence of failures as well as successful fixtures.

The user explicitly permits aesthetic simplification and temporal/spatial subsampling when useful. Exact long trajectories are not a target. The first compute comparison retains the deterministic sampled neighborhood, while coarse obstacle pushout may replace swept collision. Prior experiments can remain in a previous commit/worktree instead of permanent runtime branches.

## Target and limits

Sayu PC VR is the performance target. Laptop power mode remains untouched. The launcher's 60 FPS desktop cap is not an XR benchmark. Measure warm runs, simulation ticks and displayed frames separately, including percentile spikes and GPU execution where instrumented. A provisional 90 Hz frame budget is 11.1 ms; the actual headset refresh and representative scene determine acceptance. Desktop screenshots and headless tests do not establish stereo correctness, comfort, export readiness or headset performance.

## Terrain and dressing sequence

The earlier Terrain3D/Scatter proposal is retained in `docs/scale-feasibility.md` and the local org tracker. The user reports successful prior Terrain3D use; integration with this exact project/backend still needs a smoke test.

1. Finish the flat-arena CPU/GPU comparison without changing accepted behavior.
2. Trial one modest wavy Terrain3D greybox around the existing gameplay scale. Use a shared heightmap contract for CPU samples and GPU texture samples, with explicit world origin, scale and height convention. Both ground and flight modes use the same ground surface. Do not first expand to a 256 m map.
3. Represent rocks/trunks with coarse proxies. Mushi may clip; fine foliage collision, mesh raycasts and arbitrary rigid-body interaction are unnecessary. Height clearance is the primary requirement.
4. Try Terrain3D's own foliage/instancing for sparse greybox grass, rocks and trees before adding a separate scatter addon. Add another placement tool only if authoring needs justify it.
5. Add a representative lantern-lit dark scene and bloom, then verify actual headset rendering and frame-time margin. Darkness permits a short visible range but does not automatically cull geometry, lights or shadows: configure draw distances and culling explicitly. Separate the performance fixture from a full lighting/adaptation milestone.

## Optional co-op contract

Prioritize solo VR while preserving a practical 2–4-player host-authoritative path. The host consumes timestamped lantern inputs and owns return/release outcomes; clients can interpolate compact snapshots and later predict local response if needed. Seeds initialize traits but do not guarantee cross-GPU lockstep. Stable IDs, tick numbers and reset generations belong in snapshots; host lifecycle transitions override visual estimates. Moderate positional drift is acceptable, but group location, energy and response to both lanterns must agree well enough for cooperative herding. Coarse world interaction reduces correction complexity. Networking is not implemented by this pass.

An illustrative 20-byte record × 1024 creatures × 10 snapshots/s is 204,800 bytes/s per recipient before transport overhead. This is a sizing calculation, not a measured network or readback budget.

## Evidence

Exact commands and measurements are recorded below as the bounded checks complete. Local logs and captures live under `artifacts/m0e-performance/` and remain excluded from commits and game imports/exports.

### CPU baseline on sayu

Godot `4.7.2.stable.nixpkgs.ed1daf0bf`, Mobile/Vulkan, RTX 4090 and Ryzen 7 9800X3D. Original implementation commit `c2e33ffc`. The benchmark uses seed 40721, authored mushrooms before reset, 30 Hz, 30 warmup and 150 measured ticks with clear/blue/orange phases near the first patch. These are short diagnostic samples, not sustained headset evidence.

| Count | CPU simulation p50 / p95 / p99 (ms) | Original glyph CPU update p50 / p95 / p99 (ms) |
| --- | --- | --- |
| 256 | 4.318 / 4.823 / 4.965 | 0.383 / 0.450 / 0.647 |
| 1024 | 18.380 / 20.062 / 20.358 | 1.477 / 1.505 / 1.539 |

Simulation figures are headless. Original glyph figures are rendered in an isolated checkout with the same corrected harness. Original held-state (no simulation step) glyph update medians were 0.536 ms / 1.657 ms at 256 / 1024. The separate neighbor-build median was 0.953 / 3.923 ms; it is already included in simulation time and must not be added again. Godot's `TIME_PROCESS` samples had outliers and are not GPU or presentation measurements. An accidental run against an in-progress renderer was discarded; see the retained provenance in `artifacts/m0d-benchmark-baseline/results.txt`.

Commands for the CPU diagnostic and rendered fixture:

```bash
godot --headless --path . --script tests/performance_compare.gd
MUSHI_RENDERED_BENCH=1 godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --script tests/performance_compare.gd
```

### Final implementation measurements and checks

Final serial runs explicitly selected **Vulkan/Mobile**, with no concurrent benchmark processes. The final 150-sample GPU timing fixture brackets parameter upload, bucket construction and simulation; it excludes glyph drawing and presentation. CPU and GPU costs occupy different resources and should not be summed into a claimed headset frame time.

| Count | GPU upload + compute p50 / p95 (ms) | CPU submission p50 / p95 (ms) | CPU glyph update p50 / p95 (ms) | Snapshot application p50 / p95 (ms) |
| --- | --- | --- | --- | --- |
| 256 | 0.167 / 0.169 | 0.029 / 0.059 | 0.006 / 0.012 | 0.049 / 0.097 |
| 1024 | 2.692 / 3.319 | 0.028 / 0.059 | 0.006 / 0.011 | 0.189 / 0.382 |

The 1024-agent GPU median varied across runs (~1.31–2.69 ms), and a narrower phase probe was lower still. Do not select that favorable probe as a viability result: **the provisional <1 ms GPU budget was not reliably met at 1024**. The implementation removes the large CPU simulation stall, but whole-scene GPU headroom and the timing variability remain target-headset profiling work. The initial per-agent bucket reconstruction measured 3.04 ms median at 1024; its source and log are retained under `gpu-v1/` and `gpu-performance.log`. The first and final timing scenarios differ slightly in lantern height; no controlled speedup ratio is claimed between them.

For the CPU reference, the new renderer costs 0.585 / 0.601 ms (p50 / p95) at a 1024-agent tick and 0.013 / 0.014 ms between ticks. A fresh original-commit Mobile comparison cost 1.494 / 1.519 ms at a tick and 1.493 / 2.021 ms without a tick. Both use one glyph draw call. These CPU measurements establish reduced display-frame work, not total GPU pixel cost.

GPU timestamp units were checked against the pinned engine source: Vulkan returns nanoseconds and Godot's profiler converts them to milliseconds. The online class reference's microsecond wording is inconsistent with that implementation. See [pinned Vulkan timestamp conversion](https://github.com/godotengine/godot/blob/ed1daf0bf/drivers/vulkan/rendering_device_driver_vulkan.cpp) and [pinned profiler consumer](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/rendering_server_default.cpp). Instrumentation is disabled in ordinary gameplay.

Validation:

- `./check.sh`: 124 simulation/texture checks plus isolated UI save/load checks pass.
- `./check-gpu.sh`: rendered Mobile CPU/GPU comparisons at 64/256/1024 pass; normal 12-step maximum positional difference is 0.00017 m. The accelerated-wake and clear→blue→orange fixture differs by at most 0.00611 m, with maximum energy difference 0.00001.
- A forced 256-agent return fixture commits once, reaches RELEASED with score still 256, and survives rapid 1024→64 reset without stale state. The real scene passes direct GPU texture binding, pause, resize, live height, same-seed reset and CPU/ground/backend switching.
- Ordinary `./launch.sh --count 1024 --screenshot ... --screenshot-delay 2` initializes Mobile/GPU flight, renders and exits without errors or leaked resources. A close-up energized 1024-agent scene was also captured and inspected. No headset, terrain, bloom or export qualification is implied.

Exact final commands (the runners isolate saved user data):

```bash
./check.sh
MUSHI_GPU_CAPTURE=/home/s/code/mushi-lantern/artifacts/m0e-performance/living-shoals-gpu.png ./check-gpu.sh
MUSHI_RENDERED_BENCH=1 godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --script tests/performance_compare.gd
godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --max-fps 60 --script tests/gpu_performance.gd
```

Retained local evidence: `check-final.log`, `gpu-check-final.log`, `baseline-rendered-mobile.log`, `cpu-texture-renderer-final.log`, `gpu-performance-final.log`, `source-hashes.txt`, `ordinary-launch.log`, and the two PNG captures in `artifacts/m0e-performance/`. Earlier standalone compute checks used Forward+; the final checks above explicitly establish Mobile operation.
