# Locomotion animation source

`explosive_rpg_unarmed.glb` is the unarmed sample from **RPG Animations GLB FREE** by Explosive LLC. The Godot Asset Store listing identifies the asset as MIT licensed:

- Store listing: https://store.godotengine.org/asset/explosive-llc/rpg-character-animations-pack-free/
- Downloaded package: `RPG_Animations_GLB_FREE-0.1.0-2.zip`
- Source animations: `Unarmed.glb`

The source rig and clips are adapted at runtime by `scripts/miko_leg_animation.gd`; the adapter transfers only hips and lower-body rotations to the Miko VRM rig.
