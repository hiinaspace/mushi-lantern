extends SceneTree

# Rendered sky-only check for adaptation, Milky Way, zenith, and gentle twinkle.
# XDG_DATA_HOME=/tmp/mushi-sky-check MUSHI_SKY_CAPTURE_DIR=/home/s/code/mushi-lantern/artifacts/m1-night/sky \
#   godot --path . --rendering-driver vulkan --rendering-method mobile --script tests/night_sky_checks.gd

var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use isolated XDG_DATA_HOME under /tmp/mushi-")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Sky checks require a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var world := WorldEnvironment.new()
	var env := Environment.new()
	NightEnvironment.configure(env)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	root.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 90.0
	camera.current = true
	root.add_child(camera)
	var sky_material := env.sky.sky_material as ShaderMaterial
	_expect(sky_material != null, "night sky shader configured")
	if sky_material == null:
		quit(1)
		return
	var code := sky_material.shader.code
	_expect(code.contains("star_time_override"), "deterministic star-time probe supported")
	sky_material.set_shader_parameter("star_time_override", 0.0)
	camera.look_at(Vector3(0.8, 0.2, 0.6), Vector3.UP)
	NightEnvironment.set_night_vision(env, 0.0)
	var band_0 := await _capture("sky-band-nv0.png")
	NightEnvironment.set_night_vision(env, 0.75)
	var band_75 := await _capture("sky-band-nv075.png")
	NightEnvironment.set_night_vision(env, 1.0)
	var band_1 := await _capture("sky-band-nv1.png")
	var early_stars := _bright_pixels(band_0)
	var intermediate_stars := _bright_pixels(band_75)
	var adapted_stars := _bright_pixels(band_1)
	print("SKY_BRIGHT_PIXELS nv0=%d nv075=%d nv1=%d" % [early_stars, intermediate_stars, adapted_stars])
	_expect(adapted_stars > early_stars * 2, "adapted sky reveals many more stars")
	_expect(intermediate_stars > early_stars, "star visibility rises during adaptation")
	_expect(_changed_pixels(band_0, band_1) > 500, "adaptation changes visible sky")
	# Near-zenith views exercise the projection seam/pole independently of the
	# band-facing view; the two orientations also expose a fixed radial pinch.
	camera.look_at(Vector3(0.005, 1.0, 0.0), Vector3.FORWARD)
	NightEnvironment.set_night_vision(env, 0.0)
	var zenith_dark := await _capture("sky-zenith-nv0.png")
	NightEnvironment.set_night_vision(env, 1.0)
	var zenith := await _capture("sky-zenith-nv1.png")
	camera.look_at(Vector3(0.0, 1.0, 0.005), Vector3.RIGHT)
	var zenith_rotated := await _capture("sky-zenith-rotated-nv1.png")
	_expect(_bright_pixels(zenith) > 100, "zenith contains stars")
	_expect(_bright_pixels(zenith_rotated) > 100, "rotated zenith contains stars")
	_expect(_changed_pixels(zenith_dark, zenith) > 500,
		"zenith band and stars emerge during adaptation")
	camera.look_at(Vector3(0.8, 0.2, 0.6), Vector3.UP)
	sky_material.set_shader_parameter("star_time_override", 23.0)
	var later := await _capture("sky-band-nv1-time23.png")
	var changed := _changed_pixels(band_1, later)
	print("SKY_TWINKLE changed_pixels=%d of %d" % [changed, band_1.get_width() * band_1.get_height()])
	_expect(changed > 20, "fixed-time variation changes bright stars")
	_expect(changed < band_1.get_width() * band_1.get_height() / 4, "twinkle does not flash the whole sky")
	if _failures.is_empty():
		print("NIGHT_SKY_PASS")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _capture(name: String) -> Image:
	var capture_dir := OS.get_environment("MUSHI_SKY_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = ProjectSettings.globalize_path("res://artifacts/m1-night/sky")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for _frame: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_expect(image.save_png(capture_dir.path_join(name)) == OK, "capture saved: " + name)
	return image


func _bright_pixels(image: Image) -> int:
	var count := 0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.20:
				count += 1
	return count


func _changed_pixels(before: Image, after: Image) -> int:
	var count := 0
	for y: int in range(0, before.get_height(), 2):
		for x: int in range(0, before.get_width(), 2):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.0 / 255.0:
				count += 1
	return count


func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
