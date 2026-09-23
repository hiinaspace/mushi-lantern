extends SceneTree

# Rendered Mobile/Vulkan comparison of the same paused scene with glow off/on.
# XDG_DATA_HOME=/tmp/mushi-bloom-check MUSHI_BLOOM_CAPTURE_DIR=/home/s/code/mushi-lantern/artifacts/m1-night \
#   godot --path . --rendering-driver vulkan --rendering-method mobile --script tests/night_bloom_checks.gd -- --terrain-size 128 --count 512

var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use isolated XDG_DATA_HOME under /tmp/mushi-")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Bloom comparison needs a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for _frame: int in 180:
		await process_frame
		if lab.simulation.gpu_ready:
			break
	_expect(lab.simulation.gpu_ready, "GPU simulation initialized")
	lab.simulation_paused = true
	if lab.panel != null:
		lab.panel.visible = false
	if lab.field_overlay != null:
		lab.field_overlay.visible = false
	if lab.flight_goal_volume != null:
		lab.flight_goal_volume.visible = false
	lab.lantern.set_mode(LightField.Mode.CLEAR)
	lab.lantern.shutter_openness = 1.0
	lab.lantern.adjust_shutter(0.0)
	lab.player.camera.rotation.x = 0.02
	var env: Environment = lab.night_environment
	_expect(env != null and env.glow_enabled, "night scene enables built-in glow")
	_expect(env.glow_hdr_threshold >= 0.85 and is_zero_approx(env.glow_bloom), "bright-pixel threshold has no full-screen bloom floor")
	env.glow_enabled = false
	var unbloomed: Image = await _capture("bloom-off.png")
	env.glow_enabled = true
	var bloomed: Image = await _capture("bloom-on.png")
	env.glow_hdr_threshold = 0.2
	env.glow_hdr_scale = 0.1
	env.glow_intensity = 1.5
	env.glow_bloom = 0.2
	var aggressive: Image = await _capture("bloom-aggressive.png")
	var changed := 0
	var max_delta := 0.0
	var dark_sum := 0.0
	var dark_count := 0
	for y: int in range(0, bloomed.get_height(), 4):
		for x: int in range(0, bloomed.get_width(), 4):
			var before := unbloomed.get_pixel(x, y)
			var after := bloomed.get_pixel(x, y)
			var delta := maxf(absf(after.r - before.r), maxf(absf(after.g - before.g), absf(after.b - before.b)))
			if delta > 2.0 / 255.0:
				changed += 1
			max_delta = maxf(max_delta, delta)
			if maxf(before.r, maxf(before.g, before.b)) < 0.06:
				dark_sum += delta
				dark_count += 1
	var dark_mean := dark_sum / maxf(1.0, float(dark_count))
	var aggressive_changed := 0
	for y: int in range(0, bloomed.get_height(), 4):
		for x: int in range(0, bloomed.get_width(), 4):
			var before := unbloomed.get_pixel(x, y)
			var after := aggressive.get_pixel(x, y)
			if maxf(absf(after.r - before.r), maxf(absf(after.g - before.g), absf(after.b - before.b))) > 2.0 / 255.0:
				aggressive_changed += 1
	print("BLOOM_DIFF changed_samples=%d max_delta=%.4f dark_mean=%.5f samples=%d" % [changed, max_delta, dark_mean, (bloomed.get_width() / 4) * (bloomed.get_height() / 4)])
	print("BLOOM_AGGRESSIVE changed_samples=%d" % aggressive_changed)
	_expect(changed > 100 and max_delta > 0.02, "postprocess visibly changes scene")
	_expect(dark_mean < 0.015, "dark background remains dark")
	await _probe_glyph_colors()
	lab.queue_free()
	await process_frame
	if _failures.is_empty():
		print("NIGHT_BLOOM_PASS")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _capture(name: String) -> Image:
	var capture_dir := OS.get_environment("MUSHI_BLOOM_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = ProjectSettings.globalize_path("res://artifacts/m1-night")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for _frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := capture_dir.path_join(name)
	_expect(image.save_png(path) == OK, "capture saved: " + path)
	return image


func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)


func _probe_glyph_colors() -> void:
	# Isolate the actual glyph shader from terrain/beacon/light spill. The three
	# instances use blue, green, and orange arousal values in the same Mobile path.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	NightEnvironment.configure(env)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	var glyphs := GlyphSwarm.new()
	glyphs.face_camera = true
	glyphs.animate_vertices = false
	glyphs.bloom_hdr_gain = 1.4
	glyphs.configure(3)
	glyphs.set_world_bounds(AABB(Vector3(-2.0, -1.0, -4.0), Vector3(4.0, 2.0, 2.0)))
	viewport.add_child(glyphs)
	var state := Image.create(3, 3, false, Image.FORMAT_RGBAF)
	var arousals := [0.0, 0.45, 1.0]
	for index: int in 3:
		var p := Vector3(float(index - 1) * 1.2, 0.0, -3.0)
		state.set_pixel(index, 0, Color(p.x, p.y, p.z, arousals[index]))
		state.set_pixel(index, 1, Color(p.x, p.y, p.z, arousals[index]))
		state.set_pixel(index, 2, Color(0.0, 1.0, 0.0, 0.0))
	glyphs._material.set_shader_parameter("interpolation_alpha", 1.0)
	glyphs._material.set_shader_parameter("energy_neutral", 0.45)
	glyphs._material.set_shader_parameter("population_variation", 0.0)
	glyphs._material.set_shader_parameter("glyph_render_scale", 1.0)
	glyphs._apply_shader_options()
	glyphs._bind_texture(ImageTexture.create_from_image(state))
	env.glow_enabled = false
	var off := await _capture_viewport(viewport, "bloom-glyph-colors-off.png")
	env.glow_enabled = true
	var on := await _capture_viewport(viewport, "bloom-glyph-colors-on.png")
	var bands := [0, 0, 0]
	var halo_bands := [0, 0, 0]
	var peak := [0.0, 0.0, 0.0]
	for y: int in range(0, on.get_height(), 2):
		for x: int in range(0, on.get_width(), 2):
			var before := off.get_pixel(x, y)
			var after := on.get_pixel(x, y)
			var delta := maxf(absf(after.r - before.r), maxf(absf(after.g - before.g), absf(after.b - before.b)))
			var band := mini(2, int(float(x) / float(on.get_width()) * 3.0))
			if delta > 2.0 / 255.0:
				bands[band] += 1
				if maxf(before.r, maxf(before.g, before.b)) < 0.015:
					halo_bands[band] += 1
			peak[band] = maxf(peak[band], delta)
	print("GLYPH_BLOOM blue=%d/%d/%.3f green=%d/%d/%.3f orange=%d/%d/%.3f (changed/halo/peak)" % [bands[0], halo_bands[0], peak[0], bands[1], halo_bands[1], peak[1], bands[2], halo_bands[2], peak[2]])
	for index: int in 3:
		_expect(bands[index] > 20 and halo_bands[index] > 10 and peak[index] > 0.02, "glyph color %d gains visible halo beyond silhouette" % index)
	viewport.queue_free()
	await process_frame


func _capture_viewport(viewport: SubViewport, name: String) -> Image:
	for _frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var capture_dir := OS.get_environment("MUSHI_BLOOM_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = ProjectSettings.globalize_path("res://artifacts/m1-night")
	_expect(image.save_png(capture_dir.path_join(name)) == OK, "capture saved: " + name)
	return image
