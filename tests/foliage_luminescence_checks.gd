extends SceneTree

# Rendered material probe (no terrain import or simulation):
# XDG_DATA_HOME=/tmp/mushi-foliage-probe MUSHI_FOLIAGE_CAPTURE_DIR=artifacts/m1-luminescence godot --path . --rendering-driver vulkan --rendering-method mobile --script tests/foliage_luminescence_checks.gd

var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use isolated XDG_DATA_HOME under /tmp/mushi- for foliage checks")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Foliage check requires a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = environment
	stage.add_child(world_environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 5.0, 17.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 3.0, 0.0), Vector3.UP)
	camera.fov = 68.0
	camera.current = true
	stage.add_child(camera)

	var kit := TerrainEnvironment.new()
	stage.add_child(kit)
	_add_mesh(kit, "NearTree", kit._tree_mesh(), Vector3(-4.4, 0.0, 0.0))
	_add_mesh(kit, "FarTreeLOD", kit._distant_tree_mesh(), Vector3(4.4, 0.0, 0.0))
	var bush_mesh: Mesh = kit._bush_mesh()
	for index: int in 5:
		_add_mesh(kit, "Bush%d" % index, bush_mesh,
			Vector3(-2.0 + float(index), 0.0, 3.0))
	var grass_mesh: Mesh = kit._grass_mesh()
	for index: int in 25:
		_add_mesh(kit, "Grass%d" % index, grass_mesh,
			Vector3(-4.0 + float(index % 9), 0.0, 4.5 + float(index / 9) * 0.8))
	_expect(kit._foliage_materials.size() >= 6, "near and distant foliage surfaces use shader materials")
	kit.set_night_vision(0.75)
	var off_image := await _capture("foliage-nv075.png")
	var off_bright := _count_bright_pixels(off_image)
	kit.set_night_vision(1.0)
	var on_image := await _capture("foliage-nv100.png")
	var on_bright := _count_bright_pixels(on_image)
	_expect(off_bright == 0, "foliage has no emission at colored-light adaptation (bright=%d)" % off_bright)
	_expect(on_bright > 100, "sparse foliage emission appears at full dark adaptation (bright=%d)" % on_bright)
	for material: ShaderMaterial in kit._foliage_materials:
		_expect(is_equal_approx(float(material.get_shader_parameter("night_vision")), 1.0),
			"cached foliage material follows adaptation")
	stage.queue_free()
	await process_frame
	if _failures.is_empty():
		print("FOLIAGE_LUMINESCENCE_PASS off=%d on=%d" % [off_bright, on_bright])
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _add_mesh(parent: Node3D, label: String, mesh: Mesh, position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)


func _capture(name: String) -> Image:
	var capture_dir := OS.get_environment("MUSHI_FOLIAGE_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = ProjectSettings.globalize_path("res://artifacts/m1-luminescence")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for _frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := capture_dir.path_join(name)
	_expect(image.save_png(path) == OK, "capture saved: " + path)
	return image


func _count_bright_pixels(image: Image) -> int:
	var bright := 0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.035:
				bright += 1
	return bright


func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
