extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("071018")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("64758b")
	environment.ambient_light_energy = 0.18
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	var surface := EnvironmentSurface.create(128, 40721)
	var shrine := GoalShrine.new()
	shrine.name = "AuditionShrine"
	shrine.set_ring_color(Color("ffac55"))
	shrine.configure(2.65, surface.get_height_at(Vector2.ZERO), surface)
	root.add_child(shrine)
	shrine.set_night_vision(0.65)
	shrine.set_progress(0, 512)
	shrine.set_progress(64, 512)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 20.0)
	floor.mesh = floor_mesh
	floor.position.y = shrine.position.y - 0.025
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("343a31")
	floor_material.roughness = 0.96
	floor.material_override = floor_material
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-47.0, -32.0, 0.0)
	light.light_energy = 1.1
	root.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(4.2, 2.75, 4.6)
	camera.fov = 52.0
	root.add_child(camera)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	camera.current = true

	check(absf(shrine.position.y - surface.get_height_at(Vector2.ZERO)) < 0.001,
		"shrine root matches sampled ground")
	var boundary := shrine.get_node("ReturnBoundary") as MeshInstance3D
	check(boundary != null and boundary.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"return ring keeps shadow casting disabled")
	check(boundary.material_override is ShaderMaterial
		and (boundary.material_override as ShaderMaterial).shader.resource_path == "res://shaders/goal_boundary.gdshader",
		"return ring keeps its gameplay boundary shader")
	var boundary_vertices: PackedVector3Array = boundary.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var maximum_ring_sample_error := 0.0
	for vertex: Vector3 in boundary_vertices:
		var world_xz := Vector2(vertex.x + shrine.position.x, vertex.z + shrine.position.z)
		var expected_y: float = surface.get_height_at(world_xz) - shrine.position.y + 0.045
		maximum_ring_sample_error = maxf(maximum_ring_sample_error, absf(vertex.y - expected_y))
	check(maximum_ring_sample_error < 0.001, "return ring continues to follow sampled terrain")
	check(shrine.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"shrine remains free of gameplay collision bodies")
	check(shrine._progress_ticks.size() == GoalShrine.PROGRESS_TICKS,
		"progress detail remains bounded")
	var paper_material := (shrine.get_node("GateArchitecture/Ofuda") as MeshInstance3D).material_override as StandardMaterial3D
	var bronze_material := (shrine.get_node("GateArchitecture/PostCollar") as MeshInstance3D).material_override as StandardMaterial3D
	check(not paper_material.emission_enabled and paper_material.roughness > 0.8,
		"paper charm stays matte and non-emissive")
	check(bronze_material.metallic > 0.65 and bronze_material.roughness < 0.5,
		"metal fittings read as aged bronze")
	check(shrine._ember_material.emission_energy_multiplier <= 0.72,
		"ember glow remains restrained at adapted view")
	var visual_meshes: Array[MeshInstance3D] = []
	_collect_meshes(shrine, visual_meshes)
	var architecture_meshes := 0
	var shadowed_meshes := 0
	for mesh: MeshInstance3D in visual_meshes:
		if mesh != boundary:
			architecture_meshes += 1
			if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				shadowed_meshes += 1
	check(architecture_meshes > 0 and shadowed_meshes == architecture_meshes,
		"shrine architecture retains shadows")

	for _frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var capture_path := OS.get_environment("MUSHI_SHRINE_CAPTURE")
	if not capture_path.is_empty():
		check(root.get_texture().get_image().save_png(capture_path) == OK, "rendered shrine capture saved")
	for failure: String in failures:
		push_error(failure)
	print("GOAL_SHRINE_VISUAL_%s meshes=%d shadowed=%d" % ["PASS" if failures.is_empty() else "FAIL", architecture_meshes, shadowed_meshes])
	quit(0 if failures.is_empty() else 1)


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, output)


func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
