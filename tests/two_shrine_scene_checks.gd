extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.friend_menu.set_open(false)
	game.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._on_friend_mode_requested("two_shrines")
	game._reset_run(false)
	check(game._game_mode == "two_shrines", "PvP selected")
	check(game.simulation.goal_mode_two, "two goals sent to simulation")
	check(game.simulation.spawn_centers.size() == 3, "central spawn centers")
	print("PATCH_COUNTS world=%d sim=%d visuals=%d" % [game.world_surface.patch_centers.size(), game.simulation.mushroom_centers.size(), game.mushroom_nodes.size()])
	check(game.simulation.mushroom_centers.size() == game.world_surface.patch_centers.size() + 3, "central mushroom zones added")
	check(not game.simulation.preset.spontaneous_waking_enabled, "periodic waking disabled")
	check(game.goal_shrine.position.x < -35.0 and game.second_goal_shrine.position.x > 35.0, "shrines beyond opposite ridge ends")
	check(game.second_goal_shrine.visible, "second shrine visible")
	var shrine_goals: Array[Vector2] = [game.simulation.goal_position, game.simulation.second_goal_position]
	for index in shrine_goals.size():
		var goal: Vector2 = shrine_goals[index]
		var ground_height: float = game.world_surface.get_height_at(goal)
		var ring_min_height := INF
		var ring_max_height := -INF
		for sample in 64:
			var ring_point: Vector2 = goal + Vector2.from_angle(TAU * float(sample) / 64.0) * game.simulation.goal_radius
			var ring_height: float = game.world_surface.get_height_at(ring_point)
			ring_min_height = minf(ring_min_height, ring_height)
			ring_max_height = maxf(ring_max_height, ring_height)
		check(absf(ground_height) < 2.0 and game.world_surface._terrain_grade(goal) < 0.12,
			"shrine %d stands on level floor behind ridge" % index)
		check(game.world_surface.basin_margin(goal) > game.simulation.goal_radius + 2.0,
			"shrine %d remains clear of basin rim" % index)
		check(ring_max_height - ring_min_height < 1.0,
			"shrine %d return ring stays close to level" % index)
		check(absf((game.goal_shrine if index == 0 else game.second_goal_shrine).position.y - ground_height) < 0.001,
			"shrine %d base matches sampled ground" % index)
	check(game.simulation.spawn_centers[0].distance_to(shrine_goals[0]) > 30.0
		and game.simulation.spawn_centers[2].distance_to(shrine_goals[1]) > 30.0,
		"central player starts remain separated from goal shrines")
	check(game.mushroom_nodes.size() == game.simulation.mushroom_centers.size(), "mushroom visuals match simulation")
	for frame: int in 180:
		await process_frame
		if game.simulation.gpu_ready:
			break
	check(game.simulation.gpu_ready, "GPU ready")
	if game.simulation.gpu_ready:
		for frame: int in 30:
			await process_frame
		check(game.simulation.state_revision > 0, "GPU PvP simulation advanced")
	game._toggle_spectator()
	check(game.spectator_camera.active and root.get_camera_3d() == game.spectator_camera, "spectator camera becomes active")
	var capture_path := OS.get_environment("MUSHI_PVP_CAPTURE")
	if not capture_path.is_empty():
		game.spectator_camera.global_position = Vector3(0.0, 22.0, 43.0)
		game.spectator_camera.fov = 86.0
		game.spectator_camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)
		game._spectator_adaptation = 0.95
		for frame: int in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture_path) == OK, "spectator frame captured")
	game._on_friend_mode_requested("classic")
	game._reset_run(false)
	check(not game.simulation.goal_mode_two and not game.second_goal_shrine.visible, "classic mode restored")
	check(game.simulation.mushroom_centers.size() == game.world_surface.patch_centers.size(), "classic patches restored")
	check(game._tutorial_movement_locked and not game.player.movement_enabled, "spectator does not unlock tutorial movement")
	game._toggle_spectator()
	check(not game.player.movement_enabled, "leaving spectator keeps tutorial lock")
	game._skip_tutorial()
	check(game.player.movement_enabled, "tutorial skip restores movement")
	game.elapsed = 123.4
	game.simulation.score = ceili(float(game.fixture_count) * 0.25)
	game._record_completion_milestones()
	check(game._milestone_times.has("25") and not game._milestone_times.has("50"), "first completion time recorded once")
	game._multiplayer_role = "client"
	var reset_message := {"kind": "reset", "version": 1, "epoch": 12,
		"terrain_size": game.terrain_size, "count": 512, "seed": 40721,
		"preset": game.current_preset.to_dict(), "mode": "two_shrines",
		"score": 5, "goal_scores": [2, 3], "elapsed_seconds": 200.0,
		"milestones": {"25": 80.0}}
	game._on_network_control("host", JSON.stringify(reset_message).to_utf8_buffer())
	check(game._game_mode == "two_shrines" and game.simulation is RemoteFlightSimulation, "late join uses host PvP mode")
	check(game.simulation.score == 5 and game.simulation.goal_scores == PackedInt32Array([2, 3]), "late join scores synchronized")
	check(game.elapsed >= 200.0 and float(game._milestone_times.get("25", 0.0)) == 80.0, "late join timer and milestone synchronized")
	check(game.second_goal_shrine.visible, "late join shows second shrine")
	game._on_network_control("host", JSON.stringify({"kind": "score", "epoch": 12, "score": 7, "goal_scores": [2, 5]}).to_utf8_buffer())
	check(game.simulation.score == 7 and game.simulation.goal_scores == PackedInt32Array([2, 5]), "new scores synchronized")
	game.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("TWO_SHRINE_SCENE_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, label: String) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)
