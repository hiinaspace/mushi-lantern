# Current follow-up — richer adapted sky

The user accepted soft cliff descent and requested a much denser starfield at high night vision, a possible Milky Way band, and gentle bright-star bloom/twinkle. Preserve the sparse starting appearance while removing visible zenith pinching and uniform grid-like reveal. Keep this a bounded visual shader change with desktop render checks; headset appearance and performance remain separate validation.

# Current follow-up — smooth flight over cliffs

The user accepted the lighting/foliage pass and requested that mushi spill over cliffs naturally. Replace the terrain-relative hard upper-height clamp with soft descent through the existing flight forces, retaining ground clearance, finite bounded state and the accepted GPU behavior elsewhere.

# Current follow-up — foliage luminescence and bloom

The user requested faint luminescent spots on grass and tree foliage visible only near maximum night vision, plus slight bloom. They clarified global image-space bloom is acceptable: tune it so mushi mostly drive the glow, allow other bright objects to spill, and permit slightly HDR/paler mushi cores with colored glow. No selective-object bloom pipeline is needed.

# Current follow-up — artificial night adaptation

The user accepted the night aesthetic and requested a roughly 110-degree lantern cone, brighter/farther clear navigation light, artificial mode/shutter-driven night vision controlling star visibility and perceived lantern brightness, and debanding. Preserve lantern shadows at default/high quality. This is visual adaptation rather than automatic exposure or a change to behavioral light strength; align the widened colored cone with the simulation.

# Current follow-up — initial night lighting

The user accepted the revised terrain layout and authorized mixing in the next lighting milestone: a green goal beam visible above the landscape, a starfield sky, very low ambient illumination and the lantern as the main light, with directional shadows disabled. Terrain performance/functionality is accepted as a greybox; this is an initial nighttime orientation/visibility pass, not final aesthetic or headset qualification.

# Current follow-up — M1 terrain gameplay

The user accepted the initial environment greybox and requested more mushroom patches with fewer starting agents per patch, roughly 10% free mushi, a goal clearing 2–3 times smaller, and varied terrain with one-way drop-offs and walkable detours. Break up sightlines to the center and perimeter; preserve 128/256 m options, accepted simulation tuning and total population.

# Current authorization — M1 environment implementation

On 2026-09-22 the user approved `docs/m1-environment-plan.md` and authorized implementation, preferring subagents to conserve quota. Build the bounded Terrain3D basin, terrain-relative GPU simulation, coarse static obstacle avoidance, representative foliage/rocks/trees and persistent quality settings. Start 128 m with a 256 m comparison. Preserve accepted 1024 GPU trios/F1, with an explicit 512-agent lower-cost setting. Target PC VR 90 Hz with headroom on midrange hardware; sayu alone does not certify that. Final art direction is dark nighttime; static calm trees/foliage suffice, no wind/skinning needed. Use actual range/culling/detail controls rather than assuming darkness reduces rendering cost. No Quest/mobile/Steam Frame compatibility requirement. Plan details and validation boundaries are in the approved document. This authorization supersedes the historical checkpoint-only text below.

# Particle simulation accepted — next environment checkpoint

On 2026-09-22 the user accepted readable, aesthetic GPU head/body/tail trios and explicitly closed particle-simulation work for now. Their private `loose trains` preset weakens following to permit splitting/recombining; exact verified tuning and launch instructions are in `docs/m0g-trios.md`. Keep the accepted count/appearance and F1 sandbox. Next task is a bounded Terrain3D/environment greybox; fine collision is unnecessary, and CPU/ground modes may be retired. Do not reopen formation research by default. Current task is checkpoint/commit only; environment implementation belongs in the next task.

# Current authorization — M0f small formations

Follow-up: the user still wants readable local head/body/tail groups of three, while keeping the accepted count, glyph size and general aesthetic. A bounded transient local matching experiment is authorized before terrain. On this follow-up the user explicitly dropped the requirement to maintain CPU flight: GPU behavior, invariants, lifecycle and performance are the acceptance surface. Do not spend further effort preserving CPU/GPU trajectory equivalence. The user also permits retiring the 2D/ground simulation to Git history if useful. Neither legacy path constrains this pass; prioritize GPU flight and do not infer a need to support GPU-less systems.

The user confirmed 1024 GPU agents run smoothly and retain the desired behavior. Promote their saved `longer drift` tuning, including its run multipliers and smaller glyph scale, to the default while preserving F1 sandbox controls. Before terrain, implement one bounded comparison seeking smaller groups and directional glyph trains. Aesthetic approximations are allowed; no automated ALife search or full composite-creature system is required. Expose 2048 as an experiment, measure it, and retain the accepted 1024 default. Preserve the host-authoritative path without requiring synchronized persistent bonds. Do not infer visual success from numerical tests.

# Prior authorization — M0e performance comparison

On 2026-09-22 the user accepted living-shoal behavior and authorized a bounded performance implementation: preserve the CPU reference and ground fallback, move display-frame glyph work to shaders, and compare a stock-Godot custom-compute simulation at 256/1024 agents. Sayu PC VR is the target; laptop timings remain diagnostics. Sol/Luna delegation is explicitly requested where useful to conserve quota. No engine patch unless public APIs demonstrably block the prototype. Keep stable IDs, seeded traits, sampled social behavior and one-time return accounting. Coarse rocks/trunks and heightmap clearance are sufficient; fine foliage collision is unnecessary. Preserve a practical host-authoritative 2–4-player path, but prioritize solo VR; networking implementation is not part of this pass. Sequence a small Terrain3D greybox after the backend comparison, using its existing foliage/instancing before adding a separate scatter addon. Darkness, bloom, full XR and terrain integration remain subsequent validation work, not implied by a desktop benchmark.

The user further clarified that old experiments need not remain dynamically selectable when that complicates the implementation; prior commits or isolated worktrees are acceptable comparison surfaces. Prefer a simple winning path after measurement rather than accumulating permanent backend/renderer modes.

The simulation is aesthetic, not a ground-truth model. The user explicitly permits behavioral simplifications and temporal/spatial subsampling (including neighbor excitement) when measurements and feel justify them. Preserve finite state and one-time accounting; distinguish measured approximation from a faithful port and judge longer-run behavior by herding response rather than exact trajectories.

# Prior authorization — M0d living shoals

On 2026-09-22 the user approved 3D/smaller bodies and requested 256–1024 agents, lightweight glowing glyph rendering, seeded heterogeneous traits/social responses, local neighbor arousal and occasional spontaneous waking from mushrooms. Implement this bounded population/behavior pass now. Treat laptop power-mode timings as diagnostics, not target-device viability gates; do not change power settings. Keep prior behavior controls and ground fallback. Terrain and full darkness/bloom/XR remain later milestones. This supersedes older population deferrals below.

# Current authorization — M0c flight spike

The user approved the arousal-scatter tension and expanded arena on 2026-09-21 and explicitly requested moving on to small real 3D flight. Implement height-bounded CPU flight at 24/64 agents, retaining the energy/mushroom/lantern behavior and a selectable 2D fallback. Terrain, large population/GPU work and lighting remain later gates. The older M0b scope paragraphs below describe history; this authorization supersedes their flight deferral.

# Mushi Lantern

Hiina <hiina@hiina.space>. New Godot XR jam project, started on laptop `natto` on 2026-09-21. The original charter is `docs/charter-2026-09-21.md`; current state is tracked in `/home/s/org/projects/mushi-lantern.md` when available. See `docs/jam-plan.md` for the verified Sunday September 27, 18:00 Denver deadline.

The user approved the static mushroom / dynamic lantern structure and requested a further ground-scale pass coupling high arousal to wandering and reduced social cohesion, plus an arena twice as long per side. This follow-up is authorized now; free-flight/terrain/GPU implementation remains deferred.

The user accepted the original M0 as a successful playable spike; all three variants have charm and no winner is selected. Current authorized implementation scope is **M0b: small ground-scale energy and blue-mushroom experiment**. Preserve the original three presets. Add blue-induced dormancy, orange wake/escape, slow recovery away from blue sources, readable blue/green/yellow/orange energy color, and gentler wider goal resistance. The user's preferred motion remains **loose, drifting clusters that gather and stretch under the lantern**.

After the user approves M0b, the proposed sequence is a small bounded 3D flight test, terrain/population-scale pass, then lighting/adaptation. Research into GPU particles, custom compute, Terrain3D and scatter is authorized now; do not implement those larger passes before the M0b human gate. See `docs/scale-feasibility.md` and the current tracker for details.

Keep changes small enough for a one-week jam. Use typed GDScript, seeded resets, fixed-step snapshot updates, finite populations and one-time return accounting. Test invariants and retain exact commands/results. Do not claim feel, headset comfort, stereo rendering or export readiness from headless tests or screenshots. Stop at the human M0 gate before proceeding to the later milestones unless the user authorizes continuation.

Keep downloaded literature PDFs, generated evidence, engine binaries and user presets/run records out of source commits and exported game packages. Retain source links and provenance so research can be fetched on sayu later. Do not push or publish without user authorization. Commits use Hiina's identity with `Assisted-by: Codex:<model-id>`, never Signed-off-by.
