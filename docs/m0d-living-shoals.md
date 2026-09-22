# M0d — living shoals population spike

The user approved small bodies and 3D flocking on 2026-09-22, then requested 256–1024 agents, flat plankton/amoeba-like glyphs, individual variation, heterogeneous social response, neighbor arousal and occasional waking from mushroom patches. This is the next behavior/population spike; terrain and the dark-forest lighting/bloom pass remain separate.

## Comparison surface

The new **Living shoals** preset is the default, initially at 256 agents. Counts 3, 24, 64, 256, 512 and 1024 are selectable; `--count 1024` selects the largest fixture. Existing presets remain comparison controls. The ground fallback retains its old mesh rendering and is capped at 64 agents. Large flight fixtures (256+) use a fixed 30 Hz simulation with rendered position interpolation; smaller fixtures keep 60 Hz. The rate is recorded with each run and does not adapt to measured FPS.

**Trait variety** regenerates the same seed and resets the run, so individual traits and their visual signals remain reproducible. **Neighbor arousal** controls the local excitement coupling. **Occasional waking from patches** enables or disables spontaneous wake pulses. Existing recovery, blue sleep, orange wake and arousal-scatter controls remain available. Named snapshots retain all parameters and count/mode.

Flights use a shared instanced glyph renderer instead of individual multi-mesh creatures. Outline rings, irregular blobs and tailed outlines are exploratory visual families, not final art. Per-agent size and subtle color variation are combined with the existing energy palette. The scene remains daylight; glyph emission is prepared for later lighting but no dark adaptation or bloom pass is included.

Subtype-specific social preferences are an exploratory way to encourage different local patterns. They do not establish emergent heads/tails or coherent composite creatures; judge that from the resulting motion rather than from the rule names.

## Feel test

1. Start 256 Living shoals and observe a mushroom patch without the lantern. Most should rest while occasional individuals leave on their own.
2. Nudge a few orange, then guide them into another group. Look for a local, temporary disturbance that can settle again rather than an endless arousal cascade.
3. Compare Trait variety 0 and the default, then compare Neighbor arousal 0 and the default at the same seed.
4. Compare 512/1024 for the appearance of the whole school and glyph readability. Check whether mixed subtypes form useful visual patterns, and whether the large population remains legible to herd.

Laptop timing is diagnostic only. Power settings are not changed, and this run does not approve target-device or headset performance. Record the renderer and simulation costs separately before choosing a later optimization; simplified visuals do not by themselves make local flocking cheap.

## Implementation and bounded evidence

A separate seeded trait generator varies neutral arousal, speed, social weights, lantern/mushroom sensitivity, size and tint. Three visual subtypes have mild cyclic social preferences and relative longitudinal offsets. Variation zero removes the behavioral variation but retains the glyph shape mix. Neighbor excitement reads the previous step and uses the strongest distance-attenuated excess, with a target capped at 0.78, rather than summing excitation over population density. Recovery and mushroom suppression still apply.

Dormant patch residents accumulate individual 15–70 second sleep timers. A wake pulse lasts four seconds, targets moderate energy (0.54), reduces mushroom attraction and increases wandering. Disabling waking cancels active pulses. These values are exploratory defaults.

Above 64 agents, an XZ spatial hash samples at most 27 candidates across adjacent cells, with exact XYZ distance filtering. This is an approximate neighborhood, not an exact nearest-neighbor search or a guarantee of body collision avoidance. Smaller fixtures retain all-pairs neighborhoods. One MultiMesh shares the billboard quad and procedural outline shader; the current arena uses one aggregate culling box. Terrain-scale spatial chunks and GPU simulation remain future choices.

Validation on natto, 2026-09-22: `./check.sh` passes 64 ground + 18 flight + 24 population checks (106 total), plus UI count/mode/tuning/persistence checks. An actual Vulkan/Mobile render used AMD Radeon 780M (RADV PHOENIX); GPU instance transforms, colors and released-slot suppression passed, and glyph heading screenshots were inspected. The renderer is engaging the AMD device, but this is not a controlled power/performance test.

At seed 40721 after 45 simulated seconds with 256 agents and no lantern influence, 233 were sleepy, one was outside mushroom influence at the final sample, and two distinct agents had been observed outside. Most residents remained near their patches while a few departed. Short 12-step CPU diagnostics averaged 4.35 ms at 256 and 18.49 ms at 1024; these exclude rendering and do not establish sustained frame time or target-device readiness.

Evidence is retained locally under `artifacts/m0d-shoals-20260922/`: `check-final.log`, `glyph-checks.log`, `glyph-directions.png`, `living-patch.log`, `living-patch.png`, and the reproducible render/observation scripts. Earlier 1024 render captures predate the final 30 Hz large-population step and must not be treated as final performance results. Human judgment of glyph readability, social patterns and herding remains the next gate.

## Heading and height follow-up (2026-09-22)

The user accepted 1024 as sufficient to evaluate behavior and approved patch waking; the composite-animal gestalt remains unachieved. Default glyphs now orient in world space: local head-to-tail follows velocity, with the thin quad generally horizontal during horizontal travel. Resting glyphs retain their orientation; vertical headings use the previous transverse axis to avoid singularities. They are double-sided, but become thin or invisible edge-on. **Camera-facing glyphs** restores the billboard comparison live.

**Glyph size** is a render-only multiplier, 0.25–2.0, default 0.65 (35% smaller than the first glyph pass). **Max height (m)** is a live 2–8 m ceiling; Living shoals starts at 4.5 m, other presets at the prior 2.8 m. Calm flight remains gently attracted toward roughly 1.5 m while high energy increases vertical wandering and excursion into available headroom. Sleep settling and patch waking remain. All three settings persist in named presets and run history. The goal debug volume follows the ceiling.

Compare steering from different camera angles and compare billboard on/off; try ceilings 2.8, 4.5 and 8 m while energizing a school. These controls do not implement GPU simulation, terrain or new composite formations. Rendered checks and screenshots are under `artifacts/m0d-heading-20260922/`; velocity alignment, camera-independent geometry, size scaling and billboard toggling passed on Vulkan.

Follow-up validation: 112 simulation checks (64 ground, 18 flight, 24 population, 6 height) plus UI saved-setting checks pass. Height checks cover live ceiling reduction and the neutral-versus-energized vertical force; they do not establish a preferred feel. No composite formation or GPU simulation change was made.
