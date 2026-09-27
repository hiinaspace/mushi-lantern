extends SceneTree

# Isolated rendered terrain/foliage check, independent of the gameplay scene.
# XDG_DATA_HOME=/tmp/mushi-ground-refresh godot --xr-mode off --path . \
#   --rendering-driver vulkan --rendering-method mobile --script tests/ground_refresh_visual.gd

var _failures: Array[String] = []

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use a rendered window and isolated /tmp/mushi-* XDG_DATA_HOME")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var surface := EnvironmentSurface.create(128)
	var grove := TerrainEnvironment.new()
	root.add_child(grove)
	grove.build(surface)
	grove.set_night_vision(1.0)
	var floor_asset := grove.terrain.assets.get_texture(0) as Terrain3DTextureAsset
	_expect(floor_asset.name == "Dark forest soil", "Forest Ground 06 is the pine base")
	_expect(grove.terrain.material.get_shader_param("mushi_soil_variation_albedo") is Texture2D, "Forest Ground 04 variation is loaded")
	var cover := grove._moss_coverage_texture().get_image()
	var moss_pixels := 0
	var soil_pixels := 0
	for y in cover.get_height():
		for x in cover.get_width():
			var pair := cover.get_pixel(x, y)
			if pair.r > 0.1:
				moss_pixels += 1
			if pair.g > 0.1:
				soil_pixels += 1
	_expect(moss_pixels > 1000 and soil_pixels > 1000, "both moss and soil masks have visible patches")
	var shrub := grove._mesh_assets.bush as Terrain3DMeshAsset
	var shrub_scene := shrub.scene_file.instantiate()
	var shrub_material := ((shrub_scene.get_node("LOD0") as MeshInstance3D).mesh.surface_get_material(0)) as ShaderMaterial
	shrub_scene.free()
	_expect(shrub_material != null and shrub_material.get_shader_parameter("foliage_alpha") is Texture2D, "shrub uses separate cutout map")
	var shrub_mask := shrub_material.get_shader_parameter("foliage_alpha") as Texture2D
	var mask_image := shrub_mask.get_image()
	_expect(mask_image.get_pixel(500, 100).r < 0.1 and mask_image.get_pixel(550, 500).r > 0.9, "shrub mask contains clear background and leaf coverage")
	var rock_bodies := 0
	var rock_crest_ok := true
	var body_index := 0
	for prop: Dictionary in surface.get_props():
		if prop.kind != "tree" and prop.kind != "rock":
			continue
		var body := grove._prop_bodies.get_child(body_index) as StaticBody3D
		body_index += 1
		if prop.kind != "rock":
			continue
		rock_bodies += 1
		var shape := (body.get_child(0) as CollisionShape3D).shape as CylinderShape3D
		rock_crest_ok = rock_crest_ok and shape != null and body.position.y + shape.height * 0.5 < float(prop.position.y) + 1.2
	_expect(rock_crest_ok, "rock collider crests stay near meshes")
	_expect(rock_bodies > 25, "coarse rock colliders remain")
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.015, 0.018, 0.025)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.26, 0.27, 0.35)
	world.environment.ambient_light_energy = 0.6
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, 28, 0)
	light.light_energy = 1.3
	root.add_child(light)
	var camera := Camera3D.new()
	camera.current = true
	var target := Vector2(23, 7)
	camera.position = Vector3(target.x - 2.0, surface.get_height_at(target) + 1.6, target.y - 2.6)
	root.add_child(camera)
	camera.look_at(Vector3(target.x, surface.get_height_at(target) + 0.5, target.y))
	for _frame in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := OS.get_environment("MUSHI_GROUND_REFRESH_CAPTURE")
	if not capture.is_empty():
		_expect(root.get_texture().get_image().save_png(capture) == OK, "isolation capture saved")
	grove.queue_free()
	world.queue_free()
	light.queue_free()
	camera.queue_free()
	await process_frame
	if _failures.is_empty():
		print("GROUND_REFRESH_PASS")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
