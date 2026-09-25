extends SceneTree

## Checks the authored fruit mesh and fairy-circle layout without loading terrain.
## Run: ./.local/godot/bin/godot4 --headless --path . --script tests/mushroom_patch_checks.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var patch := MushroomPatch.new()
	root.add_child(patch)
	patch.set_radius(3.4)
	patch.set_night_vision(1.0)
	var fruit := patch.get_node_or_null("Mushrooms") as MultiMeshInstance3D
	_expect(fruit != null, "fruit multimesh exists")
	if fruit == null:
		quit(1)
		return
	_expect(fruit.multimesh.instance_count == 21, "21 fruit instances form the perimeter ring")
	var triangle_count := fruit.multimesh.mesh.get_faces().size() / 3
	_expect(triangle_count >= 3500 and triangle_count <= 6000, "fruit mesh has smooth game-ready detail (%d triangles)" % triangle_count)
	var fruit_bounds := fruit.multimesh.mesh.get_aabb().size
	_expect(fruit_bounds.y > maxf(fruit_bounds.x, fruit_bounds.z) * 1.05, "GLB mesh itself is Y-up with stems upright")
	var transforms := MushroomPatch._perimeter_transforms(3.4, Transform3D.IDENTITY)
	var min_distance := INF
	var max_distance := 0.0
	var transforms_upright := true
	for transform in transforms:
		var distance := transform.origin.length()
		min_distance = minf(min_distance, distance)
		max_distance = maxf(max_distance, distance)
		transforms_upright = transforms_upright and transform.basis.y.normalized().dot(Vector3.UP) > 0.999
	_expect(transforms.size() == fruit.multimesh.instance_count, "rendered ring and placement data use the same fruit count")
	_expect(transforms_upright, "perimeter transforms preserve upright fruit")
	_expect(min_distance > 2.20 and max_distance < 2.90, "all visible fruit sits near the 3.4 m gameplay radius perimeter")
	var min_scale := INF
	var max_scale := 0.0
	for transform in transforms:
		min_scale = minf(min_scale, transform.basis.x.length())
		max_scale = maxf(max_scale, transform.basis.x.length())
	_expect(min_scale >= 0.08 and max_scale <= 0.14, "fruit scale is increased for readability with size variation")
	var material := fruit.material_override as ShaderMaterial
	_expect(material != null and material.shader == preload("res://shaders/mushroom_edge_emission.gdshader"), "fruit uses per-instance edge emission shader")
	if material != null:
		_expect(material.get_shader_parameter("albedo_tex") == preload("res://assets/forest/mushroom/pale_woodland_albedo.png"), "natural pale albedo is assigned")
		_expect(material.get_shader_parameter("edge_mask") == preload("res://assets/forest/mushroom/pale_woodland_edges.png"), "edge-derived emission mask is assigned")
		_expect(float(material.get_shader_parameter("night_vision")) == 1.0, "violet edge cue follows night vision")
		var edge_color: Color = material.get_shader_parameter("edge_color")
		_expect(edge_color.b > edge_color.r and edge_color.r > edge_color.g, "fruit glow stays violet and distinct from sleeping mushi")
		_expect(float(material.get_shader_parameter("edge_strength")) >= 1.5, "edge emission remains perceptible in dark adaptation")
	quit(0 if not root.get_meta("checks_failed", false) else 1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		push_error("FAIL: " + message)
		root.set_meta("checks_failed", true)
