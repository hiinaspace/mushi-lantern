class_name MushroomPatch
extends Node3D

const FRUIT_COUNT := 21
const FRUIT_SCALE := 0.17
const MUSHROOM_SCENE: PackedScene = preload("res://assets/forest/mushroom/pale_woodland_mushroom.glb")
const FRUIT_SHADER: Shader = preload("res://shaders/mushroom_edge_emission.gdshader")
const FRUIT_ALBEDO: Texture2D = preload("res://assets/forest/mushroom/pale_woodland_albedo.png")
const FRUIT_EDGE_MASK: Texture2D = preload("res://assets/forest/mushroom/pale_woodland_edges.png")

var boundary: MeshInstance3D
var _fruit: MultiMeshInstance3D
var _fruit_source_transform := Transform3D.IDENTITY
var _radius := 2.0
var _night_vision := 0.0
var _visual_tuning: Dictionary = {"foliage_start": 0.90, "foliage_end": 0.99}

func _ready() -> void:
	var source_root := MUSHROOM_SCENE.instantiate()
	var source_mesh := _find_source_mesh(source_root, Transform3D.IDENTITY)
	if source_mesh != null:
		_fruit = _instances("Mushrooms", source_mesh.mesh, _fruit_material())
		source_root.free()
		_rebuild_ring()
	else:
		push_error("Pale woodland mushroom scene has no MeshInstance3D")
		if source_root != null:
			source_root.free()
	boundary = MeshInstance3D.new()
	boundary.position.y = 0.04
	boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var boundary_material := _material(Color(0.15, 0.4, 0.85, 0.2), 0.0)
	boundary_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	boundary.material_override = boundary_material
	add_child(boundary)
	_update_boundary()
	set_visual_tuning(_visual_tuning)
	set_night_vision(_night_vision)

func set_radius(radius: float) -> void:
	_radius = maxf(0.5, radius)
	if _fruit != null:
		_rebuild_ring()
	if boundary != null:
		_update_boundary()

func show_boundary(enabled: bool) -> void:
	if boundary != null:
		boundary.visible = enabled

func set_night_vision(value: float) -> void:
	_night_vision = clampf(value, 0.0, 1.0)
	if _fruit != null:
		var material := _fruit.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("night_vision", _night_vision)

func set_visual_tuning(values: Dictionary) -> void:
	_visual_tuning = values.duplicate()
	if _fruit != null:
		var material := _fruit.material_override as ShaderMaterial
		if material != null:
			_apply_mushroom_reveal_tuning(material)

func _instances(label: String, shape: Mesh, material: Material) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = shape
	instances.instance_count = FRUIT_COUNT
	node.multimesh = instances
	node.material_override = material
	add_child(node)
	return node

func _find_source_mesh(node: Node, parent_transform: Transform3D) -> MeshInstance3D:
	var local_transform := Transform3D.IDENTITY
	if node is Node3D:
		local_transform = (node as Node3D).transform
	var composed_transform := parent_transform * local_transform
	if node is MeshInstance3D:
		_fruit_source_transform = composed_transform
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found := _find_source_mesh(child, composed_transform)
		if found != null:
			return found
	return null

func _rebuild_ring() -> void:
	if _fruit == null:
		return
	var transforms := _perimeter_transforms(_radius, _fruit_source_transform)
	for index in transforms.size():
		_fruit.multimesh.set_instance_transform(index, transforms[index])

static func _perimeter_transforms(radius: float, source_transform: Transform3D) -> Array[Transform3D]:
	# Keep all visible fruits in an uneven perimeter ring, like a fairy circle.
	# The simulation still queries the same uniform radius around the same center.
	var safe_radius := maxf(0.5, radius)
	var ring_radius := minf(maxf(0.75, safe_radius - 0.55), safe_radius * 0.78)
	var transforms: Array[Transform3D] = []
	for index in FRUIT_COUNT:
		var index_f := float(index)
		var angle := index_f * TAU / float(FRUIT_COUNT) + 0.055 * sin(index_f * 2.3)
		var distance_from_center := ring_radius * (0.95 + 0.06 * sin(index_f * 4.17) + 0.035 * sin(index_f * 7.31))
		var at := Vector3(cos(angle) * distance_from_center, 0.0, sin(angle) * distance_from_center)
		var size := 0.48 + 0.28 * (0.5 + 0.5 * sin(index_f * 9.37 + 0.8))
		# The model is rotationally symmetric and its small stems must stay upright.
		# Placement jitter, scale variation and cap geometry provide visual variety.
		var oval := Vector3(1.0 + 0.035 * sin(index_f * 5.7), 1.0, 1.0 + 0.035 * sin(index_f * 3.9 + 0.4))
		var fruit_basis := Basis().scaled(oval * size * FRUIT_SCALE)
		var placement := Transform3D(fruit_basis, at)
		transforms.append(placement * source_transform)
	return transforms

func _update_boundary() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(0.1, _radius - 0.025)
	ring.outer_radius = _radius + 0.025
	ring.rings = 48
	boundary.mesh = ring

func _fruit_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FRUIT_SHADER
	material.set_shader_parameter("albedo_tex", FRUIT_ALBEDO)
	material.set_shader_parameter("edge_mask", FRUIT_EDGE_MASK)
	material.set_shader_parameter("albedo_tint", Color(0.96, 0.97, 0.99, 1.0))
	# Shader color uniforms carry `source_color`, so keep the authored sRGB
	# outline saturated enough to survive conversion and mip filtering.
	material.set_shader_parameter("edge_color", Color("a663db"))
	material.set_shader_parameter("edge_strength", 1.8)
	material.set_shader_parameter("silhouette_strength", 0.72)
	material.set_shader_parameter("alpha_cutoff", 0.5)
	material.set_shader_parameter("night_vision", _night_vision)
	_apply_mushroom_reveal_tuning(material)
	material.set_shader_parameter("patch_seed", Vector2(global_position.x, global_position.z))
	return material


func _apply_mushroom_reveal_tuning(material: ShaderMaterial) -> void:
	# Mushrooms start glowing earlier than tree/grass edge treatment, while the
	# existing foliage controls still adjust their reveal timing.
	var start := clampf(float(_visual_tuning.get("foliage_start", 0.90)) - 0.48, 0.18, 0.7)
	var end := maxf(start + 0.12,
		clampf(float(_visual_tuning.get("foliage_end", 0.99)) - 0.35, start + 0.12, 0.85))
	material.set_shader_parameter("foliage_reveal_start", start)
	material.set_shader_parameter("foliage_reveal_end", end)

func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = emission > 0.0
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = emission
	return material
