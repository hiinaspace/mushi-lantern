extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node3D = load("res://scripts/main.gd").new()
	game._parse_arguments()
	assert(game._broom_test_enabled, "--broom-test must unlock the gesture")
	game.free()
	var rig: MushiXRPlayer = load("res://scenes/xr_player.tscn").instantiate()
	add_child(rig)
	var mesh_count := 0
	rig.set_controller_hand_meshes_visible(false)
	for controller in [rig.left_controller, rig.right_controller]:
		var hand := controller.get_node("Hand") as Node3D
		assert(hand.visible)
		for mesh in hand.find_children("*", "MeshInstance3D", true, false):
			assert(not (mesh as MeshInstance3D).visible)
			mesh_count += 1
	assert(mesh_count >= 2)
	rig.set_controller_hand_meshes_visible(true)
	for controller in [rig.left_controller, rig.right_controller]:
		for mesh in controller.get_node("Hand").find_children("*", "MeshInstance3D", true, false):
			assert((mesh as MeshInstance3D).visible)
	var avatar := MushiMultiplayerAvatar.new()
	add_child(avatar)
	avatar.configure(0.0, true)
	assert(avatar._leg_animation.active)
	var eye := avatar.get_authored_eye_height()
	var head := Transform3D(Basis.IDENTITY, Vector3(0.0, eye, 0.0))
	var left := Transform3D(Basis.IDENTITY, Vector3(-0.3, eye - 0.35, -0.35))
	var right := Transform3D(Basis.IDENTITY, Vector3(0.3, eye - 0.35, -0.35))
	avatar.apply_pose(Transform3D.IDENTITY, head, left, right, 7,
		Vector3.ZERO, 1.0 / 90.0)
	avatar.apply_pose(Transform3D.IDENTITY, head, left, right,
		7 | MultiplayerAvatarPose.FLYING_FLAG, Vector3.ZERO, 1.0 / 90.0)
	assert(not avatar._leg_animation.active)
	assert(not avatar.leg_modifiers[0].active and not avatar.leg_modifiers[1].active)
	assert(avatar.arm_modifiers[0].active and avatar.arm_modifiers[1].active)
	assert(not avatar.placement.target_foot_is_valid)
	avatar.apply_pose(Transform3D.IDENTITY, head, left, right, 7,
		Vector3.ZERO, 1.0 / 90.0)
	assert(avatar._leg_animation.active)
	print("BROOM_AVATAR_CHECKS_OK")
	get_tree().quit(0)
