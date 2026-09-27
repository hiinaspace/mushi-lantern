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
	var authored_gap := skeleton.get_bone_global_rest(head_id).origin.distance_to(
		skeleton.get_bone_global_rest(hip_id).origin) * avatar.model_scale
	for yaw in [0.0, PI * 0.5]:
		for pitch in [0.0, -0.8, -1.4]:
			for crouch in [0.0, 0.3]:
				var yaw_basis := Basis(Vector3.UP, yaw)
				var view := Transform3D(yaw_basis * Basis(Vector3.RIGHT, pitch),
					Vector3(0, avatar.eye_height - crouch, 0))
				avatar.apply_pose(Transform3D.IDENTITY, view, Transform3D.IDENTITY,
					Transform3D.IDENTITY, 4, Vector3.ZERO, 0.016)
				avatar._physics_process(0.016)
				var hip_target := skeleton.get_node("HipsTarget") as Node3D
				assert(absf(avatar.head_target.global_position.distance_to(hip_target.global_position) - authored_gap) < 0.001,
					"Inferred pelvis preserves the authored spine length")
				var spine := skeleton.get_node("TrackedSpine")
				spine._process_modification()
				skeleton.force_update_all_bone_transforms()
				var hips := skeleton.to_global(skeleton.get_bone_global_pose(hip_id).origin)
				assert(hips.distance_to(hip_target.global_position) < 0.02,
					"Final pelvis follows standing/crouching target")
				var forward_displacement := (hips - view.origin).dot(-yaw_basis.z)
				assert(forward_displacement < -0.04 and forward_displacement > -0.08,
					"Looking down must keep pelvis behind the eyes rather than jutting forward")
				assert(absf(hips.y - (1.1 - crouch)) < 0.025,
					"Posture adjustment must retain the calibrated standing height")
				print("XR_STANDING_POSE yaw=%.2f pitch=%.2f crouch=%.2f hip_y=%.3f hip_forward=%.3f" % [
					yaw, pitch, crouch, hips.y, forward_displacement])
	print("XR_STANDING_CALIBRATION_CHECKS_OK")
	quit(0)
