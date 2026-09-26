extends SceneTree

# Run two local processes with MUSHI_TEST_ROLE=host/client and the same
# MUSHI_ROOM_SECRET. This checks the real room transport and reliable PvP state.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var role := OS.get_environment("MUSHI_TEST_ROLE")
	if role not in ["host", "client"]:
		push_error("Set MUSHI_TEST_ROLE=host or client")
		quit(2)
		return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.friend_menu.set_open(false)
	game.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if role == "host":
		game._on_friend_mode_requested("two_shrines")
	game._start_multiplayer(OS.get_environment("MUSHI_ROOM_SECRET"), role == "host")
	var scored_frame := -1
	for frame: int in 1200:
		await process_frame
		if role == "host" and game._joined_peers.size() >= 1 and scored_frame < 0:
			game.simulation.score = 5
			game.simulation.goal_scores = PackedInt32Array([2, 3])
			scored_frame = frame
		if role == "host" and scored_frame >= 0 and frame - scored_frame >= 120:
			print("PVP_NETWORK_HOST_OK peer=%d mode=%s" % [game._joined_peers.size(), game._game_mode])
			_finish(game, 0)
			return
		if role == "client" and game._game_mode == "two_shrines" and game.simulation is RemoteFlightSimulation \
				and game.simulation.score == 5 and game.simulation.goal_scores == PackedInt32Array([2, 3]):
			print("PVP_NETWORK_CLIENT_OK epoch=%d score=%d" % [game._multiplayer_epoch, game.simulation.score])
			_finish(game, 0)
			return
	push_error("PVP_NETWORK_TIMEOUT role=%s status=%s mode=%s score=%d" % [role, game._network_status, game._game_mode, game.simulation.score])
	_finish(game, 1)


func _finish(game: Node, code: int) -> void:
	game.queue_free()
	await process_frame
	quit(code)
