extends Node

class FlatSurface:
	func is_in_bounds(_xz: Vector2) -> bool:
		return true

	func get_height_at(_xz: Vector2) -> float:
		return 0.0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node3D = load("res://scripts/main.gd").new()
	game._parse_arguments()
	assert(game._broom_test_enabled, "--broom-test must unlock the gesture")
	game.free()
	var interaction := MushiXRStaffInteraction.new()
	assert(not MushiXRStaffInteraction.triggers_held(0.9, 0.0))
	assert(not MushiXRStaffInteraction.triggers_held(0.65, 0.9))
	assert(MushiXRStaffInteraction.triggers_held(0.9, 0.9))
	interaction.broom_test_override = true
	interaction.broom_unlocked = true
	interaction._broom_arm_elapsed = 0.7
	interaction.reset_for_run()
	assert(interaction.broom_unlocked and is_zero_approx(interaction._broom_arm_elapsed),
		"Test unlock must survive a run reset, with fresh trigger dwell")
	var rig: MushiXRPlayer = load("res://scenes/xr_player.tscn").instantiate()
	add_child(rig)
	var test_staff := StaffTool.new()
	add_child(test_staff)
	interaction.staff = test_staff
	interaction.rig = rig
	interaction._controllers = [rig.left_controller, rig.right_controller]
	interaction._pickups = [rig.left_pickup, rig.right_pickup]
	rig.left_pickup.picked_up_object = test_staff
	rig.right_pickup.picked_up_object = test_staff
	rig.world_surface = FlatSurface.new()
	rig._body.global_position.y = 5.0
	rig._broom_flying = true
	interaction.broom_active = true
	interaction._update_broom(1.0 / 90.0)
	assert(rig._broom_landing_requested and interaction.broom_active,
		"Releasing a grip high above ground must start landing while retaining grabs")
	rig.left_pickup.picked_up_object = null
	rig.right_pickup.picked_up_object = null
	test_staff.queue_free()
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
