extends SceneTree

# Rendered same-seed/same-framing candidate capture. Run once per style and
# terrain size with a separate XDG_DATA_HOME and MUSHI_FOREST_CAPTURE path.
# Example:
# XDG_DATA_HOME=/tmp/mushi-oak-128 MUSHI_FOREST_STYLE=oak MUSHI_FOREST_CAPTURE=/tmp/oak-128.png ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan --rendering-method mobile --script tests/forest_audition_visual.gd -- --terrain-size 128

var _failures: Array[String] = []

func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-") or DisplayServer.get_name() == "headless":
		push_error("Use a rendered window and isolated XDG_DATA_HOME under /tmp/mushi-")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var style := OS.get_environment("MUSHI_FOREST_STYLE").to_lower()
	if style not in ["oak", "pine", "procedural"]:
		push_error("MUSHI_FOREST_STYLE must be oak, pine or procedural")
		quit(2)
		return
	var expected_size := 128
	var args := OS.get_cmdline_user_args()
	for index: int in args.size() - 1:
		if args[index] == "--terrain-size":
			expected_size = 256 if int(args[index + 1]) == 256 else 128
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	lab.simulation_paused = true
	var environment: TerrainEnvironment = lab.terrain_environment
	_expect(lab.environment_enabled and lab.terrain_size == expected_size, "requested %dm grove is active" % expected_size)
	_expect(environment.forest_style == style, "%s forest style selected" % style)
	_expect(lab.world_surface.get_obstacles().size() > 16, "coarse obstacle source remains populated")
	if environment.forest_style != style or environment.terrain == null:
		_finish(lab)
		return
	var texture_asset: Terrain3DTextureAsset = environment.terrain.assets.get_texture(0)
	_expect(texture_asset.albedo_texture != null and texture_asset.normal_texture != null, "matched albedo and OpenGL normal ground maps loaded")
	var expected_texture_name := "Meadow earth"
	if style == "oak":
		expected_texture_name = "Oak leaf litter"
	elif style == "pine":
		expected_texture_name = "Pine needles"
	_expect(texture_asset.name == expected_texture_name, "style-specific ground material selected")
	var rock_texture: Terrain3DTextureAsset = environment.terrain.assets.get_texture(1)
	if style in ["oak", "pine"]:
		_expect(rock_texture != null and rock_texture.name == "Weathered rock" and rock_texture.albedo_texture != null and rock_texture.normal_texture != null,
			"weathered rock texture maps load for slope material")
	if style == "pine":
		var terrain_shader := environment.terrain.material.shader_override as Shader
		var moss_coverage := environment.terrain.material.get_shader_param("mushi_moss_coverage") as Texture2D
		var moss_albedo := environment.terrain.material.get_shader_param("mushi_moss_albedo") as Texture2D
		_expect(terrain_shader != null and terrain_shader.code.contains("mushi_moss_weight") and moss_coverage != null and moss_albedo != null,
			"filtered CC0 moss blend is installed into the Terrain3D shader")
		_expect(moss_albedo != null and ResourceLoader.exists("res://assets/forest/polyhaven/mossy_rock_diff_1k.jpg"),
			"pine moss overlay loads the verified green moss-on-rock albedo")
		_expect(moss_coverage != null and moss_coverage.get_width() == expected_size * 2 and moss_coverage.get_height() == expected_size * 2,
			"moss coverage mask is half-metre sampled and mipmapped")
		var controls := environment._pine_ground_control_image()
		var autoshader_pixels := 0
		for z in controls.get_height():
			for x in controls.get_width():
				var bits := Terrain3DUtil.as_uint(controls.get_pixel(x, z).r)
				if Terrain3DUtil.is_auto(bits) and Terrain3DUtil.get_base(bits) == 0:
					autoshader_pixels += 1
		_expect(autoshader_pixels == expected_size * expected_size, "needle base and automatic slope material remain across the pine control map")
		_expect(_control_is_auto(controls, Vector2(0.0, 18.4)), "goal clearing retains automatic cliff material")
		_expect(_control_is_auto(controls, Vector2(-14.4, -8.0)), "player start retains automatic slope material")
		_expect(environment.terrain_reveal_active and environment._river_mesh_active, "normal river mesh path remains installed beside smooth moss material")
	var tree_asset: Terrain3DMeshAsset = environment._mesh_assets.tree
	var grass_asset: Terrain3DMeshAsset = environment._mesh_assets.grass
	if style == "pine":
		_expect(grass_asset.name == "CC0 Meadow Grass Clump" and grass_asset.last_lod == 1, "natural pine grass uses CC0 clumps with a distant LOD")
		_expect(is_equal_approx(grass_asset.lod0_range, 12.0) and is_equal_approx(grass_asset.lod1_range, 32.0), "pine grass detail switches at 12m and culls at 32m")
	if style in ["oak", "pine"]:
		_expect(tree_asset.last_lod == 2 and tree_asset.scene_file != null, "three LOD tree scene assigned to Terrain3D")
		print("FOREST_LOD_CONFIG count=%d last=%d ranges=%.1f/%.1f/%.1f" % [tree_asset.lod_count, tree_asset.last_lod, tree_asset.lod0_range, tree_asset.lod1_range, tree_asset.lod2_range])
		_expect(tree_asset.lod_count == 3, "Terrain3D resolves exactly three direct tree LOD meshes")
		var tree_scene := tree_asset.scene_file.instantiate()
		var leaf_count := _count_edge_leaf_lod_materials(tree_scene)
		_expect(leaf_count == 3, "all three leaf LODs use the patchy edge emission shader")
		var bark_count := _count_lit_bark_lod_materials(tree_scene)
		_expect(bark_count == 3, "all three tree LODs have opaque, lit bark materials")
		if style == "pine":
			_expect(_count_textured_bark_lod_materials(tree_scene) == 3, "all three pine LODs use sourced bark albedo and normal maps")
		tree_scene.free()
	else:
		_expect(tree_asset.last_lod == 1, "procedural fallback remains available")
	var expected_tree_count := 114 if expected_size == 128 else 444
	var observed_tree_count := 0
	var observed_grass_records := 0
	for prop: Dictionary in lab.world_surface.get_props():
		if prop.kind == "tree":
			observed_tree_count += 1
		elif prop.kind == "grass":
			observed_grass_records += 1
	_expect(observed_tree_count == expected_tree_count, "same deterministic tree placements retained (%d)" % expected_tree_count)
	var expected_grass_records := 24000 if expected_size == 128 else 96000
	_expect(observed_grass_records == expected_grass_records, "dense pine ground-cover source has %d deterministic records" % expected_grass_records)
	print("FOREST_GROUND_COVER size=%d records=%d high_stride=4 low_stride=8" % [expected_size, observed_grass_records])
	if not lab.mushroom_nodes.is_empty():
		var fruit := lab.mushroom_nodes[0].get_node_or_null("Mushrooms") as MultiMeshInstance3D
		_expect(fruit != null and fruit.multimesh.instance_count == 21, "representative CC0 mushroom patch has 21 perimeter fruits")
		var fruit_material := fruit.material_override as ShaderMaterial if fruit != null else null
		_expect(fruit_material != null and fruit_material.shader == preload("res://shaders/mushroom_edge_emission.gdshader"), "mushroom fruit uses dedicated fruit edge shader")
	# Hold framing and adaptation constant for direct Oak/Pine comparison.
	lab.tutorial_director.skip()
	if lab.panel != null:
		lab.panel.visible = false
	if lab.hud_label != null:
		lab.hud_label.visible = false
	if lab.help_label != null:
		lab.help_label.visible = false
	if lab.field_overlay != null:
		lab.field_overlay.visible = false
	if lab.tutorial_ui != null:
		lab.tutorial_ui.visible = false
	if lab.tutorial_guide != null:
		lab.tutorial_guide.visible = false
	lab.lantern.set_mode(LightField.Mode.CLEAR)
	lab.lantern.set_shutter(1.0)
	var adaptation := clampf(float(OS.get_environment("MUSHI_FOREST_ADAPTATION")) if not OS.get_environment("MUSHI_FOREST_ADAPTATION").is_empty() else 0.35, 0.0, 1.0)
	lab.lantern.reset_adaptation(adaptation)
	NightEnvironment.set_night_vision(lab.night_environment, adaptation)
	environment.set_night_vision(adaptation)
	var leaf_uniforms_match := true
	var leaf_masks_loaded := true
	var edge_material_count := 0
	for material: ShaderMaterial in environment._foliage_materials:
		if material.shader != preload("res://shaders/forest_edge_emission.gdshader"):
			continue
		edge_material_count += 1
		leaf_uniforms_match = leaf_uniforms_match and is_equal_approx(float(material.get_shader_parameter("night_vision")), adaptation)
		leaf_masks_loaded = leaf_masks_loaded and material.get_shader_parameter("edge_mask") is Texture2D
	_expect(leaf_uniforms_match and edge_material_count == 3, "all tree LOD edge materials receive current adaptation")
	_expect(leaf_masks_loaded, "tree edge masks are loaded for all LOD materials")
	environment.set_stream_visibility(0.0)
	var capture_path := OS.get_environment("MUSHI_FOREST_CAPTURE")
	if not capture_path.is_empty():
		if OS.get_environment("MUSHI_FOREST_QUICK_CAPTURE") == "1":
			var dark_capture := OS.get_environment("MUSHI_FOREST_DARK_CAPTURE") == "1"
			if dark_capture:
				lab.lantern.set_shutter(0.0)
			var camera_xz := Vector2(5.0, -7.0)
			var target_xz := Vector2(7.0, -4.0)
			var camera_height := 1.5
			var target_height := 0.0
			if dark_capture:
				# Frame actual ground-cover placements so the NV1 capture shows
				# the adapted needle and fern glow instead of the spawn clearing.
				var closest_grass: Dictionary = {}
				var closest_distance := INF
				for prop: Dictionary in lab.world_surface.get_props():
					if prop.kind != "grass":
						continue
					var pos: Vector3 = prop.position
					var distance_to_view := Vector2(pos.x, pos.z).distance_to(Vector2(25.0, 8.0))
					if distance_to_view < closest_distance:
						closest_distance = distance_to_view
						closest_grass = prop
				if not closest_grass.is_empty():
					var grass_pos: Vector3 = closest_grass.position
					camera_xz = Vector2(grass_pos.x, grass_pos.z - 1.6)
					target_xz = Vector2(grass_pos.x, grass_pos.z)
					camera_height = 0.55
					target_height = 0.16
			var ground_y: float = lab.world_surface.get_height_at(camera_xz)
			var target_y: float = lab.world_surface.get_height_at(target_xz)
			lab.player.global_position = Vector3(camera_xz.x, ground_y + camera_height, camera_xz.y)
			lab.player.look_at(Vector3(target_xz.x, target_y + target_height, target_xz.y), Vector3.UP)
			lab.player.camera.rotation.x = -0.1
			print("MOSS_QUICK_FRAME center=%s coverage=%.3f dark=%s" % [target_xz, environment._moss_coverage(target_xz) * environment._moss_clearance(target_xz), dark_capture])
			for _frame: int in 18:
				await process_frame
			await RenderingServer.frame_post_draw
			var quick_path := capture_path.get_basename() + ("-quick-dark.png" if dark_capture else "-quick-moss.png")
			_expect(root.get_texture().get_image().save_png(quick_path) == OK, "quick adapted forest capture saved")
			_finish(lab)
			return
		for view: Dictionary in [
			{"name": "near", "camera_x": 12.0},
			{"name": "mid", "camera_x": -6.0},
			{"name": "far", "camera_x": -60.0},
		]:
			var tree_base := Vector2(28.0, 18.0)
			var tree_height: float = lab.world_surface.get_height_at(tree_base)
			var camera_x: float = view.camera_x
			var camera_z := 18.0
			var camera_ground: float = lab.world_surface.get_height_at(Vector2(camera_x, camera_z))
			lab.player.global_position = Vector3(camera_x, camera_ground + 0.05, camera_z)
			lab.player.look_at(Vector3(tree_base.x, tree_height + 5.0, tree_base.y), Vector3.UP)
			lab.player.camera.rotation.x = 0.16
			for _frame: int in 18:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := capture_path.get_basename() + "-%s.png" % view.name
			_expect(root.get_texture().get_image().save_png(path) == OK, "%s ordinary lantern capture saved" % view.name)
		# One key-lit near frame is diagnostic only; it separates geometry/material
		# issues from the intentionally dark playable lighting.
		var inspection_light := DirectionalLight3D.new()
		inspection_light.rotation_degrees = Vector3(-42.0, 24.0, 0.0)
		inspection_light.light_energy = 0.72
		inspection_light.shadow_enabled = false
		lab.add_child(inspection_light)
		lab.player.global_position = Vector3(12.0, lab.world_surface.get_height_at(Vector2(12.0, 18.0)) + 0.05, 18.0)
		lab.player.look_at(Vector3(28.0, lab.world_surface.get_height_at(Vector2(28.0, 18.0)) + 8.0, 18.0), Vector3.UP)
		lab.player.camera.rotation.x = 0.16
		for _frame: int in 18:
			await process_frame
		await RenderingServer.frame_post_draw
		var diagnostic_path := capture_path.get_basename() + "-near-inspection-light.png"
		_expect(root.get_texture().get_image().save_png(diagnostic_path) == OK, "near diagnostic key-lit capture saved")
		if style == "pine":
			# Compare leaf reveal, moss contrast and ordinary clear-light visibility
			# around the goal, a cliff face and the outer 64m basin edge.
			var contextual_views := [
				{"name": "moss", "camera": Vector2(12.0, 18.0), "target": Vector2(28.0, 18.0)},
				{"name": "goal", "camera": Vector2(-5.0, 16.0), "target": Vector2(0.0, 18.4)},
				{"name": "cliff", "camera": Vector2(18.0, 12.0), "target": Vector2(38.0, 22.0)},
				{"name": "boundary", "camera": Vector2(-59.0, 8.0), "target": Vector2(-43.0, 8.0)},
			]
			lab.lantern.set_shutter(0.0)
			for nv in [0.0, 0.94, 1.0]:
				lab.lantern.reset_adaptation(nv)
				NightEnvironment.set_night_vision(lab.night_environment, nv)
				environment.set_night_vision(nv)
				for view: Dictionary in contextual_views:
					var camera_xz: Vector2 = view.camera
					var target_xz: Vector2 = view.target
					var ground_y: float = lab.world_surface.get_height_at(camera_xz)
					var target_y: float = lab.world_surface.get_height_at(target_xz)
					lab.player.global_position = Vector3(camera_xz.x, ground_y + 0.05, camera_xz.y)
					lab.player.look_at(Vector3(target_xz.x, target_y + 3.0, target_xz.y), Vector3.UP)
					lab.player.camera.rotation.x = 0.12
					for _frame: int in 12:
						await process_frame
					await RenderingServer.frame_post_draw
					var nv_label := "%.2f" % nv
					var context_path := capture_path.get_basename() + "-nv%s-%s.png" % [nv_label, view.name]
					_expect(root.get_texture().get_image().save_png(context_path) == OK, "pine NV %s %s capture saved" % [nv_label, view.name])
			lab.lantern.set_shutter(1.0)
			lab.lantern.reset_adaptation(0.94)
			NightEnvironment.set_night_vision(lab.night_environment, 0.94)
			environment.set_night_vision(0.94)
			lab.lantern.spot.light_energy *= 0.55
			lab.staff_tool.visible = false
			await _capture_detail(lab, Vector2(20.0, 18.0), Vector2(28.0, 18.0), 2.0, capture_path.get_basename() + "-bark-close.png")
			await _capture_detail(lab, Vector2(5.0, -7.0), Vector2(5.0, -2.0), 0.05, capture_path.get_basename() + "-ground-close.png")
			lab.staff_tool.visible = true
			# High and low quality use different actual LOD distance bands; take
			# captures just on both sides of those transitions for inspection.
			lab.lantern.reset_adaptation(0.94)
			NightEnvironment.set_night_vision(lab.night_environment, 0.94)
			environment.set_night_vision(0.94)
			for lod_view: Dictionary in [
				{"name": "high-32-before", "camera_x": -2.0}, {"name": "high-32-after", "camera_x": -4.0},
				{"name": "high-80-before", "camera_x": -50.0}, {"name": "high-80-after", "camera_x": -52.0},
			]:
				await _capture_tree_distance(lab, lod_view, capture_path.get_basename())
			environment.apply_quality({"vegetation": "low"})
			_expect(is_equal_approx((environment._mesh_assets.tree as Terrain3DMeshAsset).lod0_range, 20.0) and is_equal_approx((environment._mesh_assets.tree as Terrain3DMeshAsset).lod1_range, 55.0), "low quality uses 20m/55m pine LOD boundaries")
			_expect(is_equal_approx(grass_asset.lod0_range, 10.0) and is_equal_approx(grass_asset.lod1_range, 24.0), "low quality uses shorter pine grass LOD/cull ranges")
			for lod_view: Dictionary in [
				{"name": "low-20-before", "camera_x": 8.0}, {"name": "low-20-after", "camera_x": 6.0},
				{"name": "low-55-before", "camera_x": -25.0}, {"name": "low-55-after", "camera_x": -27.0},
			]:
				await _capture_tree_distance(lab, lod_view, capture_path.get_basename())
	_finish(lab)

func _capture_tree_distance(lab: Node, view: Dictionary, output_base: String) -> void:
	var camera_x: float = view.camera_x
	var camera_z := 18.0
	var ground_y: float = lab.world_surface.get_height_at(Vector2(camera_x, camera_z))
	var target_y: float = lab.world_surface.get_height_at(Vector2(28.0, 18.0))
	lab.player.global_position = Vector3(camera_x, ground_y + 0.05, camera_z)
	lab.player.look_at(Vector3(28.0, target_y + 5.0, 18.0), Vector3.UP)
	lab.player.camera.rotation.x = 0.16
	for _frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var output_path := output_base + "-%s.png" % view.name
	_expect(root.get_texture().get_image().save_png(output_path) == OK, "%s LOD transition capture saved" % view.name)

func _capture_detail(lab: Node, camera_xz: Vector2, target_xz: Vector2, target_height: float, output_path: String) -> void:
	var ground_y: float = lab.world_surface.get_height_at(camera_xz)
	var target_y: float = lab.world_surface.get_height_at(target_xz) + target_height
	lab.player.global_position = Vector3(camera_xz.x, ground_y + 0.05, camera_xz.y)
	lab.player.look_at(Vector3(target_xz.x, target_y, target_xz.y), Vector3.UP)
	lab.player.camera.rotation.x = 0.0
	for _frame: int in 18:
		await process_frame
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(output_path) == OK, "%s close material capture saved" % output_path.get_file())

func _count_edge_leaf_lod_materials(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.name.begins_with("LOD"):
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index) as ShaderMaterial
			if material != null and material.shader == preload("res://shaders/forest_edge_emission.gdshader"):
				count += 1
	for child: Node in node.get_children():
		count += _count_edge_leaf_lod_materials(child)
	return count

func _count_lit_bark_lod_materials(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.name.begins_with("LOD"):
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
			if material != null and material.albedo_color.get_luminance() >= 0.12 and material.roughness >= 0.8:
				count += 1
	for child: Node in node.get_children():
		count += _count_lit_bark_lod_materials(child)
	return count

func _count_textured_bark_lod_materials(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.name.begins_with("LOD"):
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
			if material != null and material.albedo_texture != null and material.normal_enabled and material.normal_texture != null:
				count += 1
	for child: Node in node.get_children():
		count += _count_textured_bark_lod_materials(child)
	return count

func _control_is_auto(image: Image, world: Vector2) -> bool:
	var x := clampi(roundi(world.x + float(image.get_width()) * 0.5), 0, image.get_width() - 1)
	var y := clampi(roundi(world.y + float(image.get_height()) * 0.5), 0, image.get_height() - 1)
	return Terrain3DUtil.is_auto(Terrain3DUtil.as_uint(image.get_pixel(x, y).r))

func _finish(lab: Node) -> void:
	lab.queue_free()
	await process_frame
	if _failures.is_empty():
		print("FOREST_AUDITION_VISUAL_PASS style=%s" % OS.get_environment("MUSHI_FOREST_STYLE"))
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
