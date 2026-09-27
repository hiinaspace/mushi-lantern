extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	var rig: MushiXRPlayer = load("res://scenes/xr_player.tscn").instantiate()
	add_child(rig)
	rig.xr_active = true
	game.xr_player = rig
	game._ensure_local_avatar()
	var avatar: MushiMultiplayerAvatar = game._local_avatar
	assert(avatar != null and avatar.local_first_person)
	game._ensure_local_avatar()
	assert(game._local_avatar == avatar, "Solo XR and multiplayer reuse one local avatar")
	var meshes := 0
	for controller in [rig.left_controller, rig.right_controller]:
		for mesh in controller.get_node("Hand").find_children("*", "MeshInstance3D", true, false):
			assert(not (mesh as MeshInstance3D).visible, "XR Tools hand render meshes stay hidden")
			meshes += 1
	assert(meshes >= 2)
	game._update_local_avatar(1.0 / 90.0)
	assert(avatar._ready_pose, "Offline XR pose reaches Ukon IK")
	game._leave_multiplayer()
	assert(game._local_avatar == avatar, "Leaving a room keeps the solo XR body")
	print("XR_SOLO_AVATAR_CHECKS_OK")
	get_tree().quit(0)
