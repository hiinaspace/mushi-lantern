extends SceneTree

# XDG_DATA_HOME=/tmp/mushi-halo-check MUSHI_BLOOM_CAPTURE_DIR=artifacts/m1-night \
#   godot --path . --rendering-driver vulkan --rendering-method mobile --script tests/glyph_halo_checks.gd

var _failures: Array[String] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Glyph halo check needs a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.glow_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	var glyphs := GlyphSwarm.new()
	glyphs.face_camera = true
	glyphs.animate_vertices = false
	glyphs.glow_strength = 1.0
	glyphs.bloom_hdr_gain = 3.0
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
	glyphs.set_halo_strength(0.0)
	var off := await _capture(viewport, "glyph-halo-off.png")
	glyphs.set_halo_strength(0.8)
	var on := await _capture(viewport, "glyph-halo-on.png")
	var bands := [0, 0, 0]
	var halo_bands := [0, 0, 0]
	var peak := [0.0, 0.0, 0.0]
	var left_boundary := (camera.unproject_position(Vector3(-1.2, 0.0, -3.0)).x + camera.unproject_position(Vector3.ZERO + Vector3(0.0, 0.0, -3.0)).x) * 0.5
	var right_boundary := (camera.unproject_position(Vector3.ZERO + Vector3(0.0, 0.0, -3.0)).x + camera.unproject_position(Vector3(1.2, 0.0, -3.0)).x) * 0.5
	for y: int in range(0, on.get_height(), 2):
		for x: int in range(0, on.get_width(), 2):
			var before := off.get_pixel(x, y)
			var after := on.get_pixel(x, y)
			var delta := maxf(absf(after.r - before.r), maxf(absf(after.g - before.g), absf(after.b - before.b)))
			var band := 0 if float(x) < left_boundary else (1 if float(x) < right_boundary else 2)
			if delta > 2.0 / 255.0:
				bands[band] += 1
				if maxf(before.r, maxf(before.g, before.b)) < 0.015:
					halo_bands[band] += 1
			peak[band] = maxf(peak[band], delta)
	print("GLYPH_HALO blue=%d/%d/%.3f green=%d/%d/%.3f orange=%d/%d/%.3f (changed/halo/peak)" % [bands[0], halo_bands[0], peak[0], bands[1], halo_bands[1], peak[1], bands[2], halo_bands[2], peak[2]])
	for index: int in 3:
		_expect(bands[index] > 20 and halo_bands[index] > 10 and peak[index] > 0.02, "glyph color %d gains halo beyond silhouette" % index)
	if _failures.is_empty():
		print("GLYPH_HALO_PASS")
	viewport.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _capture(viewport: SubViewport, name: String) -> Image:
	for _frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var capture_dir := OS.get_environment("MUSHI_BLOOM_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = ProjectSettings.globalize_path("res://artifacts/m1-night")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	_expect(image.save_png(capture_dir.path_join(name)) == OK, "capture saved: " + name)
	return image


func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
