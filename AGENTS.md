# Mushi Lantern

Hiina <hiina@hiina.space>. New Godot XR jam project, started on laptop `natto` on 2026-09-21. The original charter is `docs/charter-2026-09-21.md`; current state is tracked in `/home/s/org/projects/mushi-lantern.md` when available. See `docs/jam-plan.md` for the verified Sunday September 27, 18:00 Denver deadline.

The user approved the static mushroom / dynamic lantern structure and requested a further ground-scale pass coupling high arousal to wandering and reduced social cohesion, plus an arena twice as long per side. This follow-up is authorized now; free-flight/terrain/GPU implementation remains deferred.

The user accepted the original M0 as a successful playable spike; all three variants have charm and no winner is selected. Current authorized implementation scope is **M0b: small ground-scale energy and blue-mushroom experiment**. Preserve the original three presets. Add blue-induced dormancy, orange wake/escape, slow recovery away from blue sources, readable blue/green/yellow/orange energy color, and gentler wider goal resistance. The user's preferred motion remains **loose, drifting clusters that gather and stretch under the lantern**.

After the user approves M0b, the proposed sequence is a small bounded 3D flight test, terrain/population-scale pass, then lighting/adaptation. Research into GPU particles, custom compute, Terrain3D and scatter is authorized now; do not implement those larger passes before the M0b human gate. See `docs/scale-feasibility.md` and the current tracker for details.

Keep changes small enough for a one-week jam. Use typed GDScript, seeded resets, fixed-step snapshot updates, finite populations and one-time return accounting. Test invariants and retain exact commands/results. Do not claim feel, headset comfort, stereo rendering or export readiness from headless tests or screenshots. Stop at the human M0 gate before proceeding to the later milestones unless the user authorizes continuation.

Keep downloaded literature PDFs, generated evidence, engine binaries and user presets/run records out of source commits and exported game packages. Retain source links and provenance so research can be fetched on sayu later. Do not push or publish without user authorization. Commits use Hiina's identity with `Assisted-by: Codex:<model-id>`, never Signed-off-by.
