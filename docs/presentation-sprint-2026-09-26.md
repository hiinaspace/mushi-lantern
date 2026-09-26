# Presentation and jam follow-up — 2026-09-26

The September 26 presentation build targets screenshots and short footage first. It adds a desktop spectator camera and a bounded two-shrine multiplayer variant while preserving the original Classic game. Both players need the same build.

## Shipped in this slice

- F6 toggles the desktop spectator camera in solo or multiplayer. Mouse and WASD/Q/E fly; Shift and Ctrl change speed. F7 toggles a gentle sweep about a shrine; F8/F9 set spectator eye adaptation and F10 restores automatic adaptation. The spectator has its own audio listener and can see the local avatar from outside.
- The host selects Classic or Two shrines from the Session menu. Two shrines uses central mushroom starts, disables periodic waking, places amber and blue goals at opposite ends, and tracks scores separately. Reset, late join, score, mode, and elapsed time use the existing host-authoritative flow. Classic remains the default.
- The room UI has a visible mute control and stable text entry. Guest mushi audio now uses fresh snapshots. The staff gains a player-color stripe; edge-on mushi halo, VR filter preview, shutter sound repeat, broom release/regrip, and below-ground recovery receive bounded fixes.
- Sustained meaningful orange illumination in a mushroom patch now overcomes the worst per-agent suppression after roughly 2–5 seconds, without changing short orange passes or blue-dominant multiplayer exposure.

## Verification and limits

Rendered Vulkan Mobile scene checks cover camera, both goals, GPU advancement, Classic restoration, and late join state. A local two-process host/client transport check reached the same two-shrine mode and score on both peers. Solo and PvP GPU goal accounting and bounded orange-patch checks pass. Linux packaged startup and Windows Wine startup are release smoke checks. Native Windows, WAN relay, and headset comfort need live friend testing; screenshot appearance is not a headset performance result.

## Next priority order

1. Before presentation: capture the needed solo/PvP shots with F6/F7 and perform a short real friend session on the published matching ZIPs.
2. Before jam submission: reproduce the reported missing Windows desktop footsteps and temporary guest lamp swing stall; review voice gain/gate threshold in a live session. Fix only with a clear reproduction.
3. If time remains: one-controller locomotion and VR comfort options, then the small audio-range and shadow-priority polish from `~/org/inbox.md`.
4. Stretch after the judging build: major stream/terrain/audio redesign, alternate materials and font, host migration, and broader UI/telemetry work.

The Sunday jam deadline is September 27, 18:00 Denver. Preserve a final export and testing window rather than letting stretch items consume it.
