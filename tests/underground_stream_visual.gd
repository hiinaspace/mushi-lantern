extends SceneTree

# Stereo/depth behavior still needs headset review. This fixture captures the
# same grove framing at forced night-vision endpoints on the rendered backend.
# XDG_DATA_HOME=/tmp/mushi-stream-128 MUSHI_STREAM_CAPTURE_DIR=/tmp/mushi-stream-128 godot --path . --rendering-driver vulkan --rendering-method mobile --script tests/underground_stream_visual.gd -- --terrain-size 128
# Repeat with a separate XDG_DATA_HOME and --terrain-size 256.

var _failures: Array[String] = []

func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-") or DisplayServer.get_name() == "headless":
		push_error("Use a rendered window and isolated XDG_DATA_HOME under /tmp/mushi-")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var expected_size := 128
	var args := OS.get_cmdline_user_args()
	for index: int in args.size() - 1:
		if args[index] == "--terrain-size":
			expected_size = int(args[index + 1])
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	lab.simulation_paused = true
	_expect(lab.environment_enabled and lab.terrain_size == expected_size, "requested Terrain3D grove is active")
	_expect(lab.terrain_environment.terrain_reveal_active, "opaque river receiver is active")
	if not lab.environment_enabled or not lab.terrain_environment.terrain_reveal_active:
		_finish(lab)
		return
	if OS.get_environment("MUSHI_STREAM_HIDE_FAR") == "1":
		lab.terrain_environment._river_far_receiver.visible = false
	lab.player.global_position = Vector3(0.0, 6.35, 19.0)
	lab.player.look_at(Vector3(0.0, lab.world_surface.get_height_at(Vector2.ZERO) - 1.5, 0.0), Vector3.UP)
	lab.player.camera.rotation.x = 0.0
	if lab.panel != null:
		lab.panel.visible = false
	if lab.hud_label != null:
		lab.hud_label.visible = false
	if lab.help_label != null:
		lab.help_label.visible = false
	if lab.field_overlay != null:
		lab.field_overlay.visible = false
	if lab.flight_goal_volume != null:
		lab.flight_goal_volume.visible = false
	if lab.tutorial_ui != null:
		lab.tutorial_ui.visible = false
	if lab.tutorial_guide != null:
		lab.tutorial_guide.visible = false
	if OS.get_environment("MUSHI_STREAM_DEBUG_LIGHT") == "1":
		var inspection_light := DirectionalLight3D.new()
		inspection_light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
		inspection_light.light_energy = 2.0
		lab.add_child(inspection_light)
	var sky_material := lab.night_environment.sky.sky_material as ShaderMaterial
	# This fixture forces reveal endpoints independently of the scripted intro.
	lab.tutorial_director.skip()
	if lab.friend_menu != null:
		lab.friend_menu.set_open(false)
	lab.lantern.set_mode(LightField.Mode.CLEAR)
	if lab.lantern.shutter_openness > 0.5:
		lab.lantern.toggle_shutter()
	# Freeze Main's automatic adaptation/gating after tutorial skip. Drive the
	# stream endpoints directly below while retaining the renderer across frames.
	lab.set_process(false)
	for state: Dictionary in [
		{"name": "clear", "vision": 0.0},
		{"name": "adapted", "vision": 1.0},
	]:
		var vision: float = state.vision
		lab.lantern.reset_adaptation(vision)
		NightEnvironment.set_night_vision(lab.night_environment, vision)
		lab.terrain_environment.set_night_vision(vision)
		lab.terrain_environment.set_stream_visibility(vision)
		_expect(is_equal_approx(float(sky_material.get_shader_parameter("night_vision")), vision), "sky forced to %s endpoint" % state.name)
		_expect(is_equal_approx(lab.terrain_environment._night_vision, vision), "terrain forced to %s endpoint" % state.name)
		var receiver_vision: float = float(lab.terrain_environment.terrain.material.get_shader_param("river_night_vision"))
		if lab.terrain_environment._river_mesh_active:
			var mesh_material := lab.terrain_environment._river_mesh.material_override as ShaderMaterial
			_expect(is_equal_approx(receiver_vision, vision) and is_zero_approx(float(lab.terrain_environment.terrain.material.get_shader_param("river_tube_enabled"))) and is_equal_approx(float(mesh_material.get_shader_parameter("river_night_vision")), vision), "mesh stream forced to %s endpoint" % state.name)
		else:
			_expect(is_equal_approx(receiver_vision, vision), "stream forced to %s endpoint" % state.name)
		await _capture("stream-%d-%s.png" % [expected_size, state.name])
		if state.name == "adapted":
			_expect(lab.tutorial_director.stage == TutorialDirector.Stage.FREE_PLAY
				and lab.terrain_environment._stream_visibility >= 0.95,
				"stream remains revealed for ten rendered frames after tutorial skip")
			if lab.terrain_environment._river_mesh_active:
				for shell: Node in lab.terrain_environment._river_mesh.get_children():
					if shell is MeshInstance3D:
						var shell_material := (shell as MeshInstance3D).material_override as ShaderMaterial
						_expect(is_equal_approx(float(shell_material.get_shader_parameter("river_night_vision")), 1.0),
							"particle shell retains adapted visibility after rendered frames")
			var dark_ambient: float = lab.night_environment.ambient_light_energy
			lab.night_environment.ambient_light_energy = 0.18
			await _capture("stream-%d-adapted-debug-ambient.png" % expected_size)
			lab.night_environment.ambient_light_energy = dark_ambient
			lab.player.global_position = Vector3(0.0, 4.5, 9.0)
			lab.player.look_at(Vector3(0.0, -7.5, -2.0), Vector3.UP)
			lab.player.camera.rotation.x = 0.0
			await _capture("stream-%d-close-crest.png" % expected_size)
			lab.player.global_position = Vector3(15.0, 5.0, 12.0)
			lab.player.look_at(Vector3(0.0, -9.0, -2.0), Vector3.UP)
			lab.player.camera.rotation.x = 0.0
			await _capture("stream-%d-oblique-crest.png" % expected_size)
			# A shallow view down each arm exposes far-country cutoff and the
			# octave fade where scintillation falls below a pixel.
			for side: float in [-1.0, 1.0]:
				lab.player.global_position = Vector3(0.0, 6.35, 11.0)
				lab.player.look_at(Vector3(side * 600.0, -7.0, -4.0), Vector3.UP)
				lab.player.camera.rotation.x = 0.0
				await _capture("stream-%d-horizon-%s.png" % [expected_size, "west" if side < 0.0 else "east"])
	_finish(lab)

func _capture(name: String) -> void:
	var capture_dir := OS.get_environment("MUSHI_STREAM_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = "/tmp/mushi-stream-captures"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for _frame: int in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := capture_dir.path_join(name)
	_expect(root.get_texture().get_image().save_png(path) == OK, "capture saved: " + path)

func _finish(lab: Node) -> void:
	lab.queue_free()
	await process_frame
	if _failures.is_empty():
		print("UNDERGROUND_STREAM_VISUAL_PASS")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
