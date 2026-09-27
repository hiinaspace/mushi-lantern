extends SceneTree

# Rendered integration gate (not a benchmark):
# XDG_DATA_HOME=/tmp/mushi-environment-scene-test MUSHI_ENV_CAPTURE=/tmp/mushi-environment-scene.png godot --path . --rendering-method mobile --script tests/environment_scene_checks.gd
# Do not use --headless: main intentionally uses the old reference arena there.

var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use an isolated XDG_DATA_HOME under /tmp/mushi- for this test")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	# The friend-facing scene starts at its paused menu; enter play before
	# asserting that the GPU simulation advances.
	if lab.friend_menu != null:
		lab.friend_menu.set_open(false)
	# The tutorial intentionally holds the real swarm until the player finishes
	# or skips it. This fixture checks terrain flight, so enter free play first.
	if lab.tutorial_director != null and lab.tutorial_director.tutorial_enabled:
		lab._skip_tutorial()
	lab.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_expect(lab.environment_enabled, "environment enabled with rendered Mobile backend")
	if not lab.environment_enabled:
		_finish(lab)
		return
	_expect(lab.terrain_size == 128, "128 m default world")
	_expect(lab.world_surface != null and lab.world_surface.size_m == 128, "heightmap source present")
	_expect(lab.world_surface.patch_centers.size() == 9, "nine distributed patches")
	_expect(lab.mushroom_nodes.size() == 9 and lab.simulation.mushroom_centers.size() == 9, "visible patches match simulation sources")
	_expect(lab.terrain_environment != null and lab.terrain_environment.terrain != null, "Terrain3D constructed")
	_expect(lab.world_surface.get_obstacles().size() > 16, "coarse prop list exceeds old fixed obstacle cap")
	_expect(absf(lab.player.global_position.y - lab.world_surface.get_height_at(Vector2(lab.player.global_position.x, lab.player.global_position.z))) < 0.2, "player spawns at terrain height")
	for _frame: int in 10:
		await physics_frame
	_expect(lab.player.is_on_floor(), "player has real terrain collision")
	lab.player.set_physics_process(false)
	_expect(lab.fixture_count == 1024, "accepted count is default")
	await _wait_gpu(lab)
	_expect(lab._active_backend == "gpu" and lab.simulation.gpu_ready, "GPU simulation active with terrain")
	if lab._active_backend != "gpu" or not lab.simulation.gpu_ready:
		_finish(lab)
		return
	for _frame: int in 12:
		await process_frame
	_expect(lab.simulation.positions.size() == 1024 and lab.simulation.state_revision > 0, "1024 simulation advances")
	var obstacle_count: int = int(lab.simulation.get("_terrain_obstacle_count"))
	_expect(obstacle_count > 16, "GPU receives coarse obstacles")
	var quality: Dictionary = lab.quality_menu.get_settings()
	quality["vegetation"] = "low"
	quality["shadows"] = "low"
	quality["render_scale"] = 0.8
	lab._apply_quality(quality)
	_expect(is_equal_approx(root.scaling_3d_scale, 0.8), "render scale applies to viewport")
	_expect(lab.terrain_environment._quality["vegetation"] == "low", "vegetation quality applies")
	lab._set_fixture(512)
	await _wait_gpu(lab)
	_expect(lab.fixture_count == 512 and lab.simulation.positions.size() == 512, "explicit 512 reset")
	lab._set_fixture(1024)
	await _wait_gpu(lab)
	_expect(lab.fixture_count == 1024 and lab.simulation.positions.size() == 1024, "1024 reset restores accepted population")
	var capture_path := OS.get_environment("MUSHI_ENV_CAPTURE")
	if not capture_path.is_empty():
		for _frame: int in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(capture_path) == OK, "rendered capture saved")
	_finish(lab)


func _wait_gpu(lab: Node) -> void:
	for _frame: int in 180:
		await process_frame
		if lab._active_backend != "gpu" or lab.simulation.gpu_ready:
			return
	_expect(false, "GPU became ready within 180 frames")


func _finish(lab: Node) -> void:
	lab.queue_free()
	await process_frame
	await process_frame
	if _failures.is_empty():
		print("ENVIRONMENT_SCENE_PASS")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
