extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.friend_menu.set_open(false)
	game.set_process_unhandled_input(false)
	game.player.set_process_unhandled_input(false)
	game.player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for index: int in 7:
		var visual := Lantern.new()
		visual.name = "SyntheticPeerLantern%d" % index
		game.add_child(visual)
		visual.global_position = Vector3(float(index - 3) * 2.5, 2.2, -float(index % 3) * 4.0)
		visual.set_mode(LightField.Mode.BLUE if index % 2 == 0 else LightField.Mode.ORANGE)
		visual.set_shutter(1.0)
		game._peer_lanterns[str(index)] = visual
	for allowed: int in [0, 1, 3, 7]:
		game._max_remote_spots = allowed
		game._limit_remote_lights()
		var visible_spots := 0
		for visual: Lantern in game._peer_lanterns.values():
			if visual.spot.visible:
				visible_spots += 1
			if visual.spot.shadow_enabled or visual.housing_fill.visible:
				failures += 1
		if visible_spots != allowed:
			failures += 1
		print("MULTIPLAYER_LIGHTS remote_allowed=%d remote_visible=%d local_shadow=%s" % [allowed, visible_spots, str(game.lantern.spot.shadow_enabled)])
	if not game.lantern.spot.shadow_enabled:
		failures += 1
	game.queue_free()
	await process_frame
	print("MULTIPLAYER_LIGHTING_CHECKS %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
