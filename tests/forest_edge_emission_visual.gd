extends SceneTree

## Captures the same forest framing at adaptation endpoints and reports the
## shader uniforms and visible pixel delta. Run in a rendered window.
## MUSHI_FOREST_STYLE=oak MUSHI_EDGE_CAPTURE_DIR=/tmp/mushi-edge ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan --rendering-method mobile --script tests/forest_edge_emission_visual.gd

var _failures: Array[String] = []

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requires a rendered window")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var capture_dir := OS.get_environment("MUSHI_EDGE_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = "/tmp/mushi-edge-emission"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	lab.simulation_paused = true
	lab.tutorial_director.skip()
	for control_name in ["panel", "hud_label", "help_label", "field_overlay", "tutorial_ui", "tutorial_guide"]:
		var control := lab.get(control_name) as CanvasItem
		if control != null:
			control.visible = false
	var environment: TerrainEnvironment = lab.terrain_environment
	_expect(environment.forest_style == "oak", "oak style is active")
	var tree_scene := environment._mesh_assets.tree.scene_file.instantiate() as Node
	_expect(_count_edge_materials(tree_scene) == 3, "all three oak LODs carry edge material")
	tree_scene.free()
	var mushroom: MushroomPatch = lab.mushroom_nodes[0]
	var fruit := mushroom.get_node("Mushrooms") as MultiMeshInstance3D
	var fruit_material := fruit.material_override as ShaderMaterial
	_expect(fruit_material != null, "mushroom fruit shader is present")
	var tree_base := Vector2(28.0, 18.0)
	var tree_height: float = lab.world_surface.get_height_at(tree_base)
	var camera_x := 24.0
	var camera_z := 18.0
	var camera_ground: float = lab.world_surface.get_height_at(Vector2(camera_x, camera_z))
	lab.player.global_position = Vector3(camera_x, camera_ground + 0.05, camera_z)
	lab.player.look_at(Vector3(tree_base.x, tree_height + 7.0, tree_base.y), Vector3.UP)
	lab.player.camera.rotation.x = 0.16
	for mode in [{"label": "nv0", "value": 0.0}, {"label": "nv1", "value": 1.0}]:
		var vision: float = mode.value
		lab.lantern.reset_adaptation(vision)
		NightEnvironment.set_night_vision(lab.night_environment, vision)
		environment.set_night_vision(vision)
		mushroom.set_night_vision(vision)
		lab.player.global_position = Vector3(camera_x, camera_ground + 0.05, camera_z)
		lab.player.look_at(Vector3(tree_base.x, tree_height + 7.0, tree_base.y), Vector3.UP)
		lab.player.camera.rotation.x = 0.16
		for _frame in 18:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/%s-tree.png" % [capture_dir, mode.label]
		_expect(image.save_png(path) == OK, "%s capture saved" % mode.label)
		print("EDGE_CAPTURE %s %s" % [mode.label, path])
		var mushroom_position := mushroom.global_position
		var mushroom_ground: float = lab.world_surface.get_height_at(Vector2(mushroom_position.x, mushroom_position.z))
		lab.player.global_position = Vector3(mushroom_position.x + 0.8, mushroom_ground, mushroom_position.z + 0.8)
		lab.player.look_at(Vector3(mushroom_position.x, mushroom_ground + 0.22, mushroom_position.z), Vector3.UP)
		lab.player.camera.fov = 40.0
		for _frame in 18:
			await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
		path = "%s/%s-mushroom.png" % [capture_dir, mode.label]
		_expect(image.save_png(path) == OK, "%s mushroom capture saved" % mode.label)
		print("EDGE_CAPTURE %s %s" % [mode.label, path])
		print("EDGE_STATE lantern=%.3f terrain=%.3f fruit=%.3f" % [lab.lantern.night_vision, environment._night_vision, float(fruit_material.get_shader_parameter("night_vision"))])
	_expect(is_equal_approx(float(fruit_material.get_shader_parameter("night_vision")), 1.0), "fruit shader receives NV=1")
	var materials := _collect_edge_materials(environment)
	_expect(not materials.is_empty(), "runtime tree edge materials are present")
	for material in materials:
		_expect(is_equal_approx(float(material.get_shader_parameter("night_vision")), 1.0), "runtime leaf shader receives NV=1")
	# Candidate production range: a wider alpha outline preserves coverage in
	# mips; restrained colored emission keeps selected patches below white.
	var wider_image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/forest/ez-tree/edge-masks/oak_leaf_alpha_edges_3px.png"))
	wider_image.generate_mipmaps()
	var wider_mask := ImageTexture.create_from_image(wider_image)
	for material in materials:
		material.set_shader_parameter("edge_mask", wider_mask)
		material.set_shader_parameter("edge_strength", 0.65)
		material.set_shader_parameter("edge_color", Color(0.66, 0.42, 0.84))
	var candidate_tree := await _capture(lab, capture_dir, "candidate-tree", Vector3(camera_x, camera_ground + 0.05, camera_z), Vector3(tree_base.x, tree_height + 7.0, tree_base.y))
	_expect(candidate_tree, "wide brighter edge tree capture saved")
	fruit_material.set_shader_parameter("edge_strength", 0.5)
	fruit_material.set_shader_parameter("edge_color", Color(0.66, 0.42, 0.84))
	var mushroom_position := mushroom.global_position
	var mushroom_ground: float = lab.world_surface.get_height_at(Vector2(mushroom_position.x, mushroom_position.z))
	var candidate_fruit := await _capture(lab, capture_dir, "candidate-mushroom", Vector3(mushroom_position.x + 0.8, mushroom_ground, mushroom_position.z + 0.8), Vector3(mushroom_position.x, mushroom_ground + 0.22, mushroom_position.z))
	_expect(candidate_fruit, "stronger mushroom edge capture saved")
	_finish(lab)

func _capture(lab: Node, capture_dir: String, label: String, from: Vector3, target: Vector3) -> bool:
	lab.player.global_position = from
	lab.player.look_at(target, Vector3.UP)
	for _frame in 18:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [capture_dir, label]
	return root.get_texture().get_image().save_png(path) == OK

func _count_edge_materials(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index) as ShaderMaterial
			if material != null and material.shader == preload("res://shaders/forest_edge_emission.gdshader"):
				count += 1
	for child: Node in node.get_children():
		count += _count_edge_materials(child)
	return count

func _collect_edge_materials(environment: TerrainEnvironment) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for material in environment._foliage_materials:
		if material.shader == preload("res://shaders/forest_edge_emission.gdshader"):
			found.append(material)
	return found

func _finish(lab: Node) -> void:
	lab.queue_free()
	await process_frame
	if _failures.is_empty():
		print("FOREST_EDGE_EMISSION_VISUAL_PASS")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
