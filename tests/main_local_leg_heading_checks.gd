extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Variant = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	var avatar := MushiMultiplayerAvatar.new()
	game.add_child(avatar)
	avatar.configure(0.0, true)
	var skeleton := avatar.skeleton
	var left_id := skeleton.find_bone("LeftFoot")
	var right_id := skeleton.find_bone("RightFoot")
	var hip_id := skeleton.find_bone("Hips")
	var sides: Array[Vector3] = []
	for yaw in [0.0, PI * 0.5, PI]:
		game.player.rotation.y = yaw
		var initial_hip_forward := Vector3.ZERO
		for frame in 45:
			var pose: Dictionary = game._sample_local_avatar_pose()
			avatar.apply_pose(pose.body, pose.head, pose.left, pose.right,
				pose.tracking, Vector3.ZERO, 1.0 / 60.0)
			await process_frame
			if frame == 0:
				initial_hip_forward = _hip_forward(skeleton, hip_id)
		var ground: Object = avatar.placement.left_ground
		assert(ground != null and ground != game.player,
			"Idle foot ray must reach terrain instead of the player's own capsule")
		assert(not avatar.placement.enable_hip_placement,
			"Desktop poses must not apply RenIK hip placement")
		assert(initial_hip_forward.dot(_hip_forward(skeleton, hip_id)) > 0.95,
			"Pelvis must not swivel as idle foot planting fades in")
		var side := skeleton.to_global(skeleton.get_bone_global_pose(right_id).origin) - \
			skeleton.to_global(skeleton.get_bone_global_pose(left_id).origin)
		side.y = 0.0
		sides.append(side.normalized())
	assert(absf(sides[0].dot(sides[1])) < 0.45 and sides[0].dot(sides[2]) < -0.75,
		"Local legs must rotate with the desktop player")
	print("MAIN_LOCAL_LEG_HEADING_OK")
	quit(0)

func _hip_forward(skeleton: Skeleton3D, hip_id: int) -> Vector3:
	var basis := skeleton.global_basis * skeleton.get_bone_global_pose(hip_id).basis
	var forward := -basis.z
	forward.y = 0.0
	return forward.normalized()
