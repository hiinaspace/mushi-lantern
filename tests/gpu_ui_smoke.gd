extends SceneTree

## Actual scene/backend lifecycle check. Run with a rendered Vulkan window and
## isolated XDG_DATA_HOME plus MUSHI_TEST_DATA_ROOT, as with ui_smoke.gd.
var failures := 0

func _initialize() -> void:
	if OS.get_environment("MUSHI_TEST_DATA_ROOT").is_empty():
		push_error("GPU UI check requires isolated user data")
		quit(1)
		return
	call_deferred("_run")

func _run() -> void:
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_expect(lab.current_preset.preset_name == "Longer drift", "Longer drift is the launch default")
	_expect(lab.fixture_count == 1024 and is_equal_approx(lab.strength_slider.value, 0.8) and is_equal_approx(lab.social_slider.value, 1.4) and is_equal_approx(lab.wander_slider.value, 0.5), "launch defaults match saved population and live multipliers")
	var population_choices: Array[String] = []
	for child: Node in lab.panel.find_children("*", "Button", true, false):
		population_choices.append((child as Button).text)
	_expect(population_choices.has("2048"), "2048-agent option is visible")
	lab._set_fixture(256)
	lab._set_backend(1)
	await _wait_ready(lab)
	_expect(lab._active_backend == "gpu", "GPU selected without fallback")
	if lab._active_backend != "gpu":
		lab.queue_free()
		await process_frame
		quit(1)
		return
	for _frame: int in 30:
		await process_frame
	_expect(lab.simulation.state_revision > 0, "GPU ticks advance through ordinary scene")
	_expect(lab.glyph_swarm._bound_texture == lab.simulation.state_texture and lab.simulation.state_texture.get_height() == 3, "renderer directly samples the GPU state texture")
	# Wake the entire isolated fixture so live-disable exercises real links.
	lab._apply_preset(7, false)
	lab.current_preset.energy_dynamics = false
	lab._reset_run(false)
	await _wait_ready(lab)
	for _frame: int in 45:
		await process_frame
	_expect(lab.simulation.formation_predecessors.count(-1) < lab.fixture_count, "awake GPU fixture forms local partners")
	lab.formation_follow_slider.value = 0.0
	for _frame: int in 30:
		await process_frame
	_expect(lab.simulation.formation_predecessors.count(-1) == lab.fixture_count and lab.simulation.formation_successors.count(-1) == lab.fixture_count, "live follow disable clears both partner slots")
	lab._apply_preset(6, true)
	await _wait_ready(lab)
	lab.simulation_paused = true
	var paused_revision: int = lab.simulation.state_revision
	for _frame: int in 5:
		await process_frame
	_expect(lab.simulation.state_revision == paused_revision, "pause stops simulation ticks")
	lab._set_fixture(2048)
	await _wait_ready(lab)
	_expect(lab.simulation.positions.size() == 2048 and lab._active_backend == "gpu", "2048-agent UI choice retains GPU backend")
	lab.height_slider.value = 2.2
	lab.size_slider.value = 0.8
	lab.billboard_toggle.button_pressed = true
	lab.simulation_paused = false
	lab._set_fixture(1024)
	await _wait_ready(lab)
	_expect(lab.simulation.positions.size() == 1024, "GPU resize rebuilds population")
	_expect(is_equal_approx(lab.simulation.max_height, 2.2), "live height survives resize")
	for _frame: int in 20:
		await process_frame
	var capture_path := OS.get_environment("MUSHI_GPU_CAPTURE")
	if not capture_path.is_empty():
		lab.player.position = Vector3(-14.4, 0.0, -8.0)
		lab.player.reset_look()
		lab.lantern.set_mode(LightField.Mode.ORANGE)
		for _frame: int in 60:
			await process_frame
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(capture_path) == OK, "GPU scene screenshot saved")
	lab._reset_run(false)
	await _wait_ready(lab)
	_expect(lab.simulation.score == 0, "same-seed reset clears return accounting")
	lab._set_flight(false)
	_expect(lab.simulation is FlockSimulation and lab._active_backend == "cpu", "ground fallback disposes GPU backend")
	lab._set_flight(true)
	await _wait_ready(lab)
	_expect(lab._active_backend == "gpu", "flight restores requested backend")
	lab._set_backend(0)
	_expect(lab.simulation is FlightSimulation and lab._active_backend == "cpu", "CPU reference selectable after GPU")
	lab.queue_free()
	await process_frame
	await process_frame
	print("GPU_UI_SMOKE %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _wait_ready(lab: Node) -> void:
	for _frame: int in 180:
		await process_frame
		if lab._active_backend != "gpu" or lab.simulation.gpu_ready:
			return
	_expect(false, "GPU initialization finished within 180 frames")

func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures += 1
