extends SceneTree

## Rendered regression check: a glancing glyph should shed broad fake halo.
func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Glyph grazing halo check needs a rendered window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.glow_enabled = false
	world.environment = env
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	var glyphs := GlyphSwarm.new()
	glyphs.animate_vertices = false
	glyphs.glow_strength = 1.0
	glyphs.bloom_hdr_gain = 3.0
	glyphs.configure(1)
	glyphs.set_world_bounds(AABB(Vector3(-1.0, -1.0, -4.0), Vector3(2.0, 2.0, 2.0)))
	viewport.add_child(glyphs)
	var state := Image.create(1, 3, false, Image.FORMAT_RGBAF)
	state.set_pixel(0, 0, Color(0.0, 0.0, -3.0, 0.45))
	state.set_pixel(0, 1, Color(0.0, 0.0, -3.0, 0.45))
	state.set_pixel(0, 2, Color(1.0, 0.0, 0.0, 0.0))
	glyphs._material.set_shader_parameter("interpolation_alpha", 1.0)
	glyphs._material.set_shader_parameter("energy_neutral", 0.45)
	glyphs._material.set_shader_parameter("population_variation", 0.0)
	glyphs._material.set_shader_parameter("glyph_render_scale", 1.0)
	glyphs._apply_shader_options()
	glyphs._bind_texture(ImageTexture.create_from_image(state))
	glyphs.set_halo_strength(0.0)
	var front_off := await _capture(viewport)
	glyphs.set_halo_strength(0.8)
	var front_on := await _capture(viewport)
	state.set_pixel(0, 2, Color(0.0, 0.0, 1.0, 0.0))
	glyphs._bind_texture(ImageTexture.create_from_image(state))
	glyphs.set_halo_strength(0.0)
	var edge_off := await _capture(viewport)
	glyphs.set_halo_strength(0.8)
	var edge_on := await _capture(viewport)
	var front := _halo_pixels(front_off, front_on)
	var edge := _halo_pixels(edge_off, edge_on)
	print("GLYPH_GRAZING_HALO front=%d edge=%d" % [front, edge])
	if front <= 10 or edge >= front:
		push_error("Glancing-angle halo was not reduced")
	viewport.queue_free()
	await process_frame
	quit(0 if front > 10 and edge < front else 1)


func _capture(viewport: SubViewport) -> Image:
	for _frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _halo_pixels(before: Image, after: Image) -> int:
	var count := 0
	for y: int in range(after.get_height()):
		for x: int in range(after.get_width()):
			var old_color := before.get_pixel(x, y)
			var new_color := after.get_pixel(x, y)
			var delta := maxf(absf(new_color.r - old_color.r), maxf(absf(new_color.g - old_color.g), absf(new_color.b - old_color.b)))
			if maxf(old_color.r, maxf(old_color.g, old_color.b)) < 0.015 and delta > 2.0 / 255.0:
				count += 1
	return count
