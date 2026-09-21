# Scale feasibility: agents, terrain, and dressing

Research note only, 2026-09-21. No addon was installed and no project or target-device profiling was performed. Godot `latest` documentation can describe behavior newer than the pinned 4.7.2 build, so the later gates require checks in that exact build and on the intended Mobile/XR target.

## Recommendation

Finish M0b first at the current ground scale: make energy readable and make blue mushrooms affect the existing loop. Preserve all three successful M0 presets. Every larger implementation below waits for the user's M0b `lgtm`.

After approval, make the smallest bounded 3D flight spike at 24 agents, then 64. Keep the current straightforward CPU representation while it meets correctness and frame-time gates. Retain stable integer IDs and CPU-owned energy, goals, and one-time return accounting. Add a spatial grid only when neighbor checks measure as material; move rendering to chunked `MultiMesh` only when node, draw-submission, or transform-upload cost measures as material.

Do not make thousands of agents or an engine patch a requirement. Prototype custom GPU compute only if the 256/512-agent profile shows CPU simulation or upload is the actual blocker, and consider an engine patch only after a minimal reproduction shows the public APIs are insufficient.

## Godot agent options

`GPUParticles3D` supports custom particle shaders. A particle retains values written during the prior frame and exposes `INDEX`, emission-sequence `NUMBER`, transform, velocity, `CUSTOM`, collision state, and combined `ATTRACTOR_FORCE`. Attractors can be boxes, spheres, or vector fields. Particle collision supports boxes, spheres, SDFs, and a dynamic height field; SDF collision is documented for Forward+ and Mobile.

This is a good fit for the independent-seeker or curl/flow-field variant the user already liked: many visually autonomous fliers can wander, seek shared fields, and react to attractors or terrain. Keep the distinction explicit: field-driven independent motion is not true social flocking.

A particle shader processes its own persistent state and aggregate attractor/collision inputs. The documented interface has no arbitrary neighbor-particle lookup, so true separation/alignment/cohesion needs a separately constructed neighbor field or spatial grid. Do not add that complexity unless social flocking improves the experience enough to earn it.

`INDEX` is a particle-buffer slot; `NUMBER` is unique since emission began. Neither alone is a durable gameplay identity across resize, restart, and re-emission. `CUSTOM` provides four persistent floats and is useful for visual state, seed, phase, or a compact ID. Authoritative energy and goal completion should remain in CPU-owned records unless a compute design explicitly returns compact events.

Godot exposes custom compute through `RenderingDevice`; current `RenderingServer` documentation also exposes the global `MultiMesh` buffer RID for GPU-driven writes. A local RenderingDevice cannot share resources with the global renderer, so the simple local-compute tutorial does not establish a zero-copy render path. Synchronous `buffer_get_data()` stalls for the GPU, and even large asynchronous downloads can be too expensive for real time. A GPU design should keep simulation and transforms on the GPU and read back only small delayed counters/events, never every transform every frame.

For hundreds to low thousands, CPU spatial hashing plus a `MultiMesh` is a credible next optimization, not the starting architecture. Godot documents GDScript as reasonable for a few thousand MultiMesh instances, but that is not an XR performance guarantee. Split large populations spatially because each MultiMesh culls as one object.

## Terrain and static dressing

Terrain3D 1.0.2 is the current stable release. Its release notes explicitly support Godot 4.4–4.6+; that wording is not a 4.7.2 compatibility guarantee. Its platform page calls Vulkan Mobile fully supported, while the release notes describe mobile and web platforms as experimental. Treat 4.7.2 + Mobile + XR as unverified until a smoke test covers editor load, both-eye rendering, packaged launch, height queries/collision, and frame timing.

For CPU agents with known X/Z, use `Terrain3DData.get_height()`. Terrain3D recommends direct region heightmap-image access for thousands of samples; a bulk path should cache that data and preserve interpolation. GPU-only agents can sample an explicitly supplied height texture or use Godot's GPU-particle height-field collision. Avoid per-agent physics raycasts merely to follow the ground.

ProtonScatter is an editor-oriented Godot 4 procedural placement addon that produces MultiMeshes. Its 4.0 release described support for Godot 4.0–4.2 at the time, so 4.7.2 remains a smoke-test item. `ScatterCache` can store generated results for runtime loading, with a documented warning that restoring transforms may be slower depending on complexity and count.

If adopted, use Scatter for authored tree/cylinder placement, split its output into cullable chunks, bake or cache deterministic results, and verify a clean packaged export without relying on editor state. Keep agent simulation independent from Scatter.

## Sequence and stop gates

1. **M0b, current ground scale:** readable energy and blue-mushroom behavior in the existing arena. Gate: user `lgtm` on feel and readability. Stop all larger implementation until approved.
2. **Bounded 3D flight:** 24, then 64 agents using the simplest current CPU representation. Gate: stable IDs, correct energy/goal accounting, seeded reset/replay, no visible jitter, and target frame time.
3. **Population ramp:** 128, 256, then 512 in the same scene. Record simulation, node/draw submission, rendering/upload, and worst-frame costs separately. Stop at the first missed correctness or frame-time gate. Add a spatial grid or chunked MultiMesh only for the measured bottleneck. Separately test GPUParticles if the independent/curl-flow visual variant is desired.
4. **Terrain:** flat 256 m square first, then one Terrain3D heightmap with the same load. Gate: packaged Mobile/XR render, correct height following, acceptable memory, and target frame time. At 1.4 m/s a 256 m crossing is about 3 minutes; at 3 m/s it is 85 seconds; at 5 m/s it is 51 seconds. A diagonal is 1.41 times longer. This is already a meaningful exploratory area; require a demonstrated traversal need before trying 512 m.
5. **Dressing and lighting:** add chunked/baked tree cylinders, then lighting polish. Gate: culling, both-eye correctness, and target frame time under the retained agent load. Keeping lighting last makes simulation and terrain costs legible.
6. **GPU compute, conditional:** only if profiling shows CPU/grid/upload cost blocks the desired count. Require behavior/accounting parity at 64 and 256, stable identity, compact event readback, and a clean Mobile/XR run before scaling further.

## Primary sources

- [Godot particle shader state and built-ins](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/particle_shader.html)
- [Godot particle attractors](https://docs.godotengine.org/en/latest/tutorials/3d/particles/attractors.html)
- [Godot particle collision and height fields](https://docs.godotengine.org/en/latest/tutorials/3d/particles/collision.html)
- [Godot renderer and XR/Mobile matrix](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
- [Godot MultiMesh behavior and performance](https://docs.godotengine.org/en/latest/tutorials/performance/using_multimesh.html)
- [Godot RenderingServer global/local devices and MultiMesh buffers](https://docs.godotengine.org/en/latest/classes/class_renderingserver.html)
- [Godot RenderingDevice readback costs](https://docs.godotengine.org/en/4.4/classes/class_renderingdevice.html)
- [Terrain3D 1.0.2 release requirements](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable)
- [Terrain3D platforms and renderers](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html)
- [Terrain3D height-query guidance](https://terrain3d.readthedocs.io/en/stable/docs/collision.html)
- [ProtonScatter repository](https://github.com/HungryProton/scatter)
- [ProtonScatter 4.0 release and ScatterCache](https://github.com/HungryProton/scatter/releases/tag/4.0)

These sources establish documented APIs and claimed support, not this project's runtime behavior or target-device performance.
