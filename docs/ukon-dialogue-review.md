# Ukon tutorial cold read — 2026-09-27

Astra review and bounded wording pass for the final jam tutorial.

## Findings and changes

- Begin with the visible little light, then name mushi. The previous opening assumed a new player already understood what “this” referred to and introduced migration before the immediate lesson.
- Explain the light vein before the shrine. The old wording made the vein’s pull responsible for stranding the mushi, then asked the player to return them to it. The revised text describes strays and a route home without adding a causal claim.
- Keep the Japanese term on one page alongside “light vein”; later pages use the English name or its immediate referent. Retain the explicit solid-ground explanation for the underground visual.
- Preserve the direct safety reassurance: no jumpscares and nothing that hurts the player. This describes this game, rather than the source anime’s sometimes dangerous world.
- Give each color an observable effect, then explain the group action. The release demonstration now says Ukon lifts the glass so the mushi can reach the shrine, instead of requesting player action during a scripted beat.
- End by naming either shrine and making the pace optional. Preserve the accepted progress congratulations; reduce repeated menu/time reminders and remove unsupported claims that every return visibly brightens the vein or that strays spawn where it grows thin.
- Completion-time references now point to Play, matching the revised menu.

## Source reference

Read the user-provided local English subtitle tracks. All 26 S1 episodes were extracted to `/tmp/mushi-subtitle-reference/`, outside the repository. Focused reading covered the opening explanation in episode 1 and channel/light explanations in episodes 9, 11, and 19. The useful delivery pattern is to notice something concrete, name it, and explain only what the listener needs next. No subtitle dialogue is copied into the game or this review. The game keeps its own gentle rules and does not import the anime’s dangers or additional terminology.

## Delivery and verification

Existing manual advance, click-to-finish text reveal, and five-second observation gates remain in place. Shorter instructional beats leave time to watch the jar; the player still decides when to continue. No additional forced delay or page was added.

`./.local/godot/bin/godot4 --headless --xr-mode off --path . --script res://tests/tutorial_director_checks.gd` passes with `TUTORIAL_DIRECTOR_CHECKS failures=0`. This covers the retained lesson sequence, release and scoring invariants, reassurance, adrift/solid-ground beats, and progress references. Desktop and headset reading comfort remain part of the next user playthrough.
