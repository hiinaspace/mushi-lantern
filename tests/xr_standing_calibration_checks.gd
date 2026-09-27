extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var avatar := MushiMultiplayerAvatar.new()
	world.add_child(avatar)
	avatar.configure(0.0, true)
	avatar.set_player_eye_height(1.8)
	var skeleton := avatar.skeleton
	var head_id := skeleton.find_bone("Head")
	var hip_id := skeleton.find_bone("Hips")
	var authored_gap := (skeleton.get_bone_global_rest(head_id).origin.y - skeleton.get_bone_global_rest(hip_id).origin.y) * avatar.model_scale
	for yaw in [0.0, PI * 0.5]:
		for crouch in [0.0, 0.3]:
			var view := Transform3D(Basis(Vector3.UP, yaw), Vector3(0, avatar.eye_height - crouch, 0))
			avatar.apply_pose(Transform3D.IDENTITY, view, Transform3D.IDENTITY,
				Transform3D.IDENTITY, 4, Vector3.ZERO, 0.016)
			avatar._physics_process(0.016)
			var hip_target := skeleton.get_node("HipsTarget") as Node3D
			assert(absf(avatar.head_target.global_position.y - hip_target.global_position.y - authored_gap) < 0.001)
			var spine := skeleton.get_node("TrackedSpine")
			spine._process_modification()
			skeleton.force_update_all_bone_transforms()
			var hips := skeleton.to_global(skeleton.get_bone_global_pose(hip_id).origin)
			assert(hips.distance_to(hip_target.global_position) < 0.02, "Final pelvis follows calibrated standing/crouching target")
			print("XR_STANDING_POSE yaw=%.2f crouch=%.2f hip_y=%.3f" % [yaw, crouch, hips.y])
	print("XR_STANDING_CALIBRATION_CHECKS_OK")
	quit(0)
