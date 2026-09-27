extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 0.2, 8)
	collider.shape = box
	floor.position.y = -0.1
	floor.add_child(collider)
	root.add_child(floor)
	var avatar := MushiMultiplayerAvatar.new()
	root.add_child(avatar)
	avatar.configure(0, true)
	avatar.set_eye_height(1.6)
	var eye := 1.6
	for frame in range(40):
		avatar.apply_pose(Transform3D.IDENTITY,
			Transform3D(Basis.IDENTITY, Vector3(0, eye, 0)),
			Transform3D.IDENTITY, Transform3D.IDENTITY, 0, Vector3.ZERO, 0.016)
		await physics_frame
	var sk := avatar.skeleton
	# Headless SceneTree does not render the skeleton modifier pass; invoke it
	# explicitly so this check measures the final untracked idle pose.
	avatar._leg_animation._process_modification()
	sk.force_update_all_bone_transforms()
	for name in ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightFoot"]:
		var bone := sk.find_bone(name)
		print(name, " ", sk.to_global(sk.get_bone_global_pose(bone).origin))
	var left_wrist := sk.to_global(sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin)
	var right_wrist := sk.to_global(sk.get_bone_global_pose(sk.find_bone("RightHand")).origin)
	print("IDLE_WRISTS left=", left_wrist, " right=", right_wrist)
	assert(left_wrist.x < -0.25 and right_wrist.x > 0.25, "idle wrists clear the skirt laterally")
	assert(left_wrist.z < -0.04 and right_wrist.z < -0.04, "idle wrists rest slightly forward of the waist")
	for side in ["Left", "Right"]:
		var ankle := sk.to_global(sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin)
		assert(ankle.y > 0.0 and ankle.y < 0.15)
		assert(absf(ankle.z) < 0.15)
	assert(avatar.leg_modifiers[0].influence > 0.99)
	print("PASS local avatar ankles remain above planted targets near floor")
	quit()
