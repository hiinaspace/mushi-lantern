extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var avatar := (load("res://scenes/miko_avatar.tscn") as PackedScene).instantiate()
	root.add_child(avatar)
	var skeletons := avatar.find_children("*", "Skeleton3D", true, false)
	assert(skeletons.size() == 1)
	var skeleton := skeletons[0] as Skeleton3D
	var left := skeleton.find_bone("LeftHand")
	var right := skeleton.find_bone("RightHand")
	assert(left >= 0 and right >= 0)
	skeleton.force_update_all_bone_transforms()
	var left_rest := skeleton.get_bone_global_pose(left).origin
	var right_rest := skeleton.get_bone_global_pose(right).origin
	avatar.set_guide_idle(true)
	skeleton.force_update_all_bone_transforms()
	var left_relaxed := skeleton.get_bone_global_pose(left).origin
	var right_relaxed := skeleton.get_bone_global_pose(right).origin
	print("GUIDE_HANDS rest=", left_rest, ",", right_rest, " relaxed=", left_relaxed, ",", right_relaxed)
	assert(left_relaxed.y < left_rest.y - 0.2 and right_relaxed.y < right_rest.y - 0.2,
		"Guide arms must hang below imported T-pose")
	assert(left_relaxed.x > 0.0 and right_relaxed.x < 0.0,
		"Guide hands must remain clear of the torso")
	if not OS.get_environment("MIKO_GUIDE_CAPTURE").is_empty():
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(0.0, 1.25, 3.4)
		camera.look_at(Vector3(0.0, 1.0, 0.0))
		camera.make_current()
		var light := DirectionalLight3D.new()
		root.add_child(light)
		light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
		light.light_energy = 2.0
		for frame in 8:
			await process_frame
		var path := OS.get_environment("MIKO_GUIDE_CAPTURE")
		var error := root.get_texture().get_image().save_png(path)
		assert(error == OK)
		print("GUIDE_CAPTURE ", path)
	avatar.set_guide_idle(false)
	skeleton.force_update_all_bone_transforms()
	assert(skeleton.get_bone_global_pose(left).origin.distance_to(left_rest) < 0.001)
	assert(skeleton.get_bone_global_pose(right).origin.distance_to(right_rest) < 0.001)
	print("MIKO_GUIDE_POSE_OK")
	quit(0)
