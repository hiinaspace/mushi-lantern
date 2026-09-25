extends SceneTree

# Rendered integration check, separate from performance qualification:
# XDG_DATA_HOME=/tmp/mushi-night-check MUSHI_NIGHT_CAPTURE_DIR=/home/s/code/mushi-lantern/artifacts/m1-night godot --path . --rendering-driver vulkan --rendering-method mobile --script tests/night_scene_checks.gd -- --terrain-size 128 --count 512
# Repeat with --terrain-size 256 and a distinct XDG_DATA_HOME.

var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use isolated XDG_DATA_HOME under /tmp/mushi- for night scene checks")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Night scene check requires a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var expected_size := 128
	var user_args := OS.get_cmdline_user_args()
	for index: int in user_args.size() - 1:
		if user_args[index] == "--terrain-size":
			expected_size = int(user_args[index + 1])
	_expect(user_args.has("--count") and user_args.has("512"), "explicit --count 512 fixture")
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	# Enter play from the friend-facing start menu before measuring GPU ticks.
	if lab.friend_menu != null:
		lab.friend_menu.set_open(false)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_expect(lab.environment_enabled and lab.terrain_size == expected_size, "terrain scene and requested size")
	_expect(lab.fixture_count == 512, "CLI selects 512 GPU agents")
	var world_environment: WorldEnvironment
	for child: Node in lab.get_children():
		if child is WorldEnvironment:
			world_environment = child as WorldEnvironment
			break
	_expect(world_environment != null and world_environment.environment != null, "WorldEnvironment configured")
	if world_environment != null and world_environment.environment != null:
		var environment := world_environment.environment
		_expect(environment.background_mode == Environment.BG_SKY, "sky background enabled")
		_expect(environment.sky != null and environment.sky.sky_material is ShaderMaterial, "shader sky material present")
		if environment.sky != null and environment.sky.sky_material is ShaderMaterial:
			var sky_shader := (environment.sky.sky_material as ShaderMaterial).shader
			_expect(sky_shader != null and sky_shader.code.contains("star_hash"), "deterministic starfield shader loaded")
		_expect(environment.ambient_light_energy <= 0.02, "night ambient is dim")
	var beacon := lab.get_node_or_null("GoalSkyBeacon") as Node3D
	_expect(beacon != null, "goal sky beacon exists")
	if beacon != null:
		for mesh_name: String in ["Core", "Halo"]:
			var mesh := beacon.get_node_or_null(mesh_name) as MeshInstance3D
			_expect(mesh != null and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s beacon mesh does not cast shadows" % mesh_name)
		_expect(beacon.find_children("*", "Light3D", true, false).is_empty(), "beacon adds no Light3D")
	var quality: Dictionary = lab.quality_menu.get_settings()
	quality["bloom"] = false
	lab._apply_quality(quality)
	_expect(not lab.night_environment.glow_enabled, "F2 bloom can be disabled")
	quality["bloom"] = true
	lab._apply_quality(quality)
	_expect(lab.night_environment.glow_enabled, "F2 bloom can be enabled")
	quality["shadows"] = "high"
	lab._apply_quality(quality)
	_expect(is_zero_approx(lab.sun_light.light_energy) and not lab.sun_light.shadow_enabled, "sun remains off under high quality")
	_expect(lab.lantern.spot.shadow_enabled, "high quality preserves lantern foliage shadows")
	quality["shadows"] = "low"
	lab._apply_quality(quality)
	_expect(is_zero_approx(lab.sun_light.light_energy) and not lab.sun_light.shadow_enabled, "sun remains off under low quality")
	_expect(not lab.lantern.spot.shadow_enabled, "low quality disables lantern shadows")
	quality["shadows"] = "high"
	lab._apply_quality(quality)
	for mode: LightField.Mode in [LightField.Mode.CLEAR, LightField.Mode.BLUE, LightField.Mode.ORANGE]:
		lab.lantern.set_mode(mode)
		lab.lantern.shutter_openness = 1.0
		lab.lantern.adjust_shutter(0.0)
		_expect(lab.lantern.spot.visible and lab.lantern.spot.light_energy > 0.0, "open lantern emits in mode %d" % mode)
	lab.lantern.set_mode(LightField.Mode.CLEAR)
	lab.lantern.adjust_shutter(1.0)
	await _wait_gpu(lab)
	_expect(lab._active_backend == "gpu" and lab.simulation.gpu_ready, "GPU flight active at night")
	for _frame: int in 20:
		await process_frame
	_expect(lab.simulation.positions.size() == 512 and lab.simulation.state_revision > 0 and lab.simulation.is_finite_and_bounded(), "512-agent night simulation advances finitely")
	if lab.panel != null:
		lab.panel.visible = false
	if lab.field_overlay != null:
		lab.field_overlay.visible = false
	if lab.flight_goal_volume != null:
		lab.flight_goal_volume.visible = false
	lab.player.camera.rotation.x = 0.08
	await _capture("night-%d-main-clear.png" % expected_size)
	lab.lantern.toggle_shutter()
	_expect(is_zero_approx(lab.lantern.spot.light_energy) and not lab.lantern.spot.visible, "closed shutter has no visible emitter")
	await _capture("night-%d-main-closed.png" % expected_size)
	lab.lantern.toggle_shutter()
	var ridge := Vector2(30.0, 0.0)
	lab.player.global_position = Vector3(ridge.x, lab.world_surface.get_height_at(ridge) + 0.05, ridge.y)
	lab.player.look_at(Vector3(0.0, lab.player.global_position.y, 0.0), Vector3.UP)
	lab.player.camera.rotation.x = -0.12
	await _capture("night-%d-ridge-clear.png" % expected_size)
	lab.simulation_paused = true
	lab.player.camera.rotation.x = 0.35
	lab.lantern.set_mode(LightField.Mode.CLEAR)
	lab.lantern.shutter_openness = 0.0
	lab.lantern.advance_adaptation(90.0)
	lab.lantern.adjust_shutter(1.0)
	var flash_energy: float = lab.lantern.spot.light_energy
	_expect(is_equal_approx(lab.lantern.spot.spot_angle, 65.0) and Lantern.BEHAVIOR_HALF_ANGLE_DEGREES == 55.0, "square projector keeps 110 degree effective beam")
	_expect(is_equal_approx(lab.lantern.spot.spot_range, 20.0), "clear navigation range is 20 m")
	await _capture("night-%d-clear-flash.png" % expected_size)
	lab.lantern.advance_adaptation(30.0)
	_expect(lab.lantern.night_vision < 0.01 and lab.lantern.spot.light_energy < flash_energy * 0.65, "clear exposure settles from initial flash")
	await _capture("night-%d-clear-adapted.png" % expected_size)
	var sky_material := lab.night_environment.sky.sky_material as ShaderMaterial
	_expect(absf(float(sky_material.get_shader_parameter("night_vision")) - lab.lantern.night_vision) < 0.001, "sky tracks visual adaptation")
	lab.lantern.set_mode(LightField.Mode.BLUE)
	lab.lantern.advance_adaptation(60.0)
	_expect(lab.lantern.night_vision > 0.74 and lab.lantern.night_vision < 0.76, "colored mode recovers most night vision")
	_expect(is_equal_approx(lab.lantern.spot.spot_range, 10.5), "colored range remains shorter")
	lab.lantern.toggle_shutter()
	lab.lantern.advance_adaptation(90.0)
	_expect(lab.lantern.night_vision > 0.99 and is_zero_approx(lab.lantern.spot.light_energy), "closed shutter recovers night vision without light")
	await _capture("night-%d-dark-adapted.png" % expected_size)
	lab.queue_free()
	await process_frame
	await process_frame
	if _failures.is_empty():
		print("NIGHT_SCENE_PASS size=%d" % expected_size)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _wait_gpu(lab: Node) -> void:
	for _frame: int in 180:
		await process_frame
		if lab._active_backend != "gpu" or lab.simulation.gpu_ready:
			return
	_expect(false, "GPU ready within 180 frames")


func _capture(name: String) -> void:
	var capture_dir := OS.get_environment("MUSHI_NIGHT_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = ProjectSettings.globalize_path("res://artifacts/m1-night")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for _frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := capture_dir.path_join(name)
	_expect(root.get_texture().get_image().save_png(path) == OK, "capture saved: " + path)


func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
