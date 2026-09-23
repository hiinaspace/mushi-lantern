extends SceneTree

# Rendered Vulkan Mobile check. Set MUSHI_FILTER_CAPTURE_DIR to retain screenshots.
var _failures := 0
var _capture_dir := ""

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Lantern filter check needs a rendered window")
		quit(2)
		return
	_capture_dir = OS.get_environment("MUSHI_FILTER_CAPTURE_DIR")
	if _capture_dir.is_empty():
		_capture_dir = ProjectSettings.globalize_path("user://lantern-filter-checks")
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var lantern := Lantern.new()
	scene.add_child(lantern)
	var wall := MeshInstance3D.new()
	var wall_mesh := QuadMesh.new()
	wall_mesh.size = Vector2(5.0, 5.0)
	wall.mesh = wall_mesh
	wall.position.z = -3.0
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color.WHITE
	wall.material_override = wall_material
	scene.add_child(wall)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("20242b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	world.environment = environment
	scene.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, -1.0)
	camera.fov = 100.0
	camera.current = true
	scene.add_child(camera)
	for mode: LightField.Mode in [LightField.Mode.CLEAR, LightField.Mode.BLUE, LightField.Mode.ORANGE]:
		lantern.set_mode(mode)
		lantern.set_shutter(1.0)
		lantern.spot.light_energy = 0.5
		var cookie := lantern.spot.light_projector as ImageTexture
		_expect(cookie != null, "full-open cookie in mode %d" % mode)
		if cookie != null:
			var image := cookie.get_image()
			_expect(image != null and image.get_width() == Lantern.COOKIE_SIZE, "cookie image has expected size")
			if image != null:
				image.save_png(_capture_dir.path_join("cookie-%d.png" % mode))
				if mode == LightField.Mode.CLEAR:
					_expect(image.get_pixel(30, 30).r > 0.98, "clear filter has no engraving")
				else:
					var low := 1.0
					var high := 0.0
					for y: int in range(14, 50):
						for x: int in range(14, 50):
							var value := image.get_pixel(x, y).r
							low = minf(low, value)
							high = maxf(high, value)
					_expect(high > 0.98 and low < 0.75, "colored filter engraves cookie")
					_expect(absf(image.get_pixel(30, 30).r - image.get_pixel(30, 30).b) < 0.01, "steady cookie stays neutral")
					if mode == LightField.Mode.BLUE:
						_expect(image.get_pixel(24, 34).r < image.get_pixel(24, 29).r, "blue cookie V points down in projector coordinates")
					else:
						_expect(image.get_pixel(24, 29).r < image.get_pixel(24, 34).r, "orange cookie caret points up in projector coordinates")
		await _capture(camera, "beam-%d.png" % mode)
		await _capture_window(camera, wall, "window-%d.png" % mode)
	lantern.set_mode(LightField.Mode.BLUE)
	lantern.set_shutter(0.55)
	lantern.spot.light_energy = 0.5
	await _capture(camera, "beam-blue-partial.png")
	lantern.set_shutter(1.0)
	lantern.begin_dial_preview()
	lantern.set_dial_preview(-Lantern.DIAL_RANGE_YAW * 0.5)
	lantern.spot.light_energy = 0.5
	_expect(lantern.spot.light_color == Color.WHITE, "split projector uses white spotlight")
	await _capture(camera, "beam-blue-clear-split.png")
	await _capture_window(camera, wall, "window-blue-clear-split.png")
	var split_cookie := lantern.spot.light_projector as ImageTexture
	if split_cookie != null:
		var split_image := split_cookie.get_image()
		split_image.save_png(_capture_dir.path_join("cookie-blue-clear-split.png"))
		_expect(split_image.get_pixel(18, 30).b > split_image.get_pixel(18, 30).r, "split has blue source")
		_expect(split_image.get_pixel(46, 30).r > split_image.get_pixel(46, 30).b, "split has warm clear target")
	lantern.end_dial_preview()
	for _i: int in 30:
		lantern.advance_flame(0.02)
		await process_frame
	_expect(not lantern._settling_split, "split preview settles")
	scene.queue_free()
	await process_frame
	print("LANTERN_FILTER_%s capture=%s" % ["PASS" if _failures == 0 else "FAIL", _capture_dir])
	quit(0 if _failures == 0 else 1)

func _capture(camera: Camera3D, filename: String) -> void:
	camera.rotation.y = 0.0
	for _i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(_capture_dir.path_join(filename)) == OK, "saved " + filename)

func _capture_window(camera: Camera3D, wall: MeshInstance3D, filename: String) -> void:
	wall.visible = false
	camera.rotation.y = PI
	for _i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(_capture_dir.path_join(filename)) == OK, "saved " + filename)
	wall.visible = true

func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)
