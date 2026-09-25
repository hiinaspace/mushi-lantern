extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var avatar := MushiMultiplayerAvatar.new()
	get_root().add_child(avatar)
	await process_frame
	var leg = avatar._leg_animation
	assert(leg != null)
	var clips: Dictionary = leg.ANIMATIONS
	assert(clips["left"] == &"UnarmedStrafeLeft")
	assert(clips["right"] == &"UnarmedStrafeRight")
	assert(clips["forward_left"] == &"UnarmedStrafeForwardLeft")
	assert(clips["back_right"] == &"UnarmedStrafeBackwardRight")
	for key in clips:
		assert(leg._source_player.has_animation(clips[key]))
	leg._animation_tree.active = false
	leg.set_locomotion_speed(leg.full_speed_mps)
	var skeleton: Skeleton3D = avatar.skeleton
	for clip in [&"UnarmedRunForward", &"UnarmedStrafeLeft", &"UnarmedStrafeRight"]:
		var animation: Animation = leg._source_player.get_animation(clip)
		for phase in [0.15, 0.35, 0.55, 0.75]:
			leg._source_player.play(clip)
			leg._source_player.seek(animation.length * phase, true)
			leg._source_player.advance(0.0)
			leg._process_modification()
			skeleton.force_update_all_bone_transforms()
			for side in ["Left", "Right"]:
				var hip := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpperLeg")).origin
				var knee := skeleton.get_bone_global_pose(skeleton.find_bone(side + "LowerLeg")).origin
				var foot := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Foot")).origin
				# The knee must bend toward Ukon's face (+Z), ahead of the hip-foot line.
				var along := (hip.y - knee.y) / maxf(hip.y - foot.y, 0.01)
				assert(knee.z - lerpf(hip.z, foot.z, along) > 0.015)
	print("PASS distinct strafe clips and forward knee bend")
	quit()
