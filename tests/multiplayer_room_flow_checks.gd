extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	assert(game._network == null, "Room menu should load transport only when needed")
	game._force_tutorial = true
	game.friend_menu.set_room_code("test")
	game.friend_menu._submit_room(true)
	assert(game._network != null, "Menu Host should initialize native transport")
	assert(game._multiplayer_role == "host")
	assert(game._skip_tutorial_requested and not game._force_tutorial,
		"Multiplayer room should bypass the solo tutorial")
	game.friend_menu.multiplayer_leave_requested.emit()
	assert(game._multiplayer_role == "offline")
	assert(game._force_tutorial, "Leaving the room should restore solo tutorial preference")
	print("MULTIPLAYER_ROOM_FLOW_OK")
	quit(0)
