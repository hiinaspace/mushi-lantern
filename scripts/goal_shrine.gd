class_name GoalShrine
extends Node3D
## Small, static return landmark. No physics bodies or per-frame work are used.
## Configure once after adding the node, then update its compact progress cue.

const PROGRESS_TICKS := 8

var goal_radius: float = 2.05
var ground_height: float = 0.0
var world_surface: Variant
var night_vision: float = 0.0
var ring_color: Color = Color(1.0, 0.67, 0.27)
var _boundary_material: ShaderMaterial
var _score_pulse: float = 0.0
var _last_score: int = -1
var _progress_ticks: Array[MeshInstance3D] = []
var _progress_materials: Array[StandardMaterial3D] = []
var _up_light: SpotLight3D
var _architecture_root: Node3D


func _ready() -> void:
	_build()
	_apply_night_vision()


func configure(radius: float, ground_y: float, surface: Variant = null) -> void:
	goal_radius = maxf(0.5, radius)
	ground_height = ground_y
	world_surface = surface
	position.y = ground_height
	if is_inside_tree():
		_rebuild()


func set_progress(score: int, total: int) -> void:
	if score < _last_score:
		_score_pulse = 0.0
		set_process(false)
		if _boundary_material != null:
			_boundary_material.set_shader_parameter("return_pulse", 0.0)
	if _last_score >= 0 and score > _last_score:
		_score_pulse = 1.0
		set_process(true)
		if _boundary_material != null:
			_boundary_material.set_shader_parameter("return_pulse", _score_pulse)
	_last_score = score
	var ratio := 0.0 if total <= 0 else clampf(float(score) / float(total), 0.0, 1.0)
	var lit_count := int(round(ratio * PROGRESS_TICKS))
	for index in range(_progress_ticks.size()):
		var active := index < lit_count
		_progress_materials[index].emission_energy_multiplier = 0.75 if active else 0.025
		_progress_materials[index].albedo_color = Color("e9b872") if active else Color("302c2a")


func set_night_vision(value: float) -> void:
	night_vision = clampf(value, 0.0, 1.0)
	_apply_night_vision()
	if _boundary_material != null:
		_boundary_material.set_shader_parameter("adaptation", night_vision)


func set_ring_color(value: Color) -> void:
	ring_color = value
	if _boundary_material != null:
		_boundary_material.set_shader_parameter("ring_color", Vector3(value.r, value.g, value.b))


func _process(delta: float) -> void:
	_score_pulse = maxf(0.0, _score_pulse - delta * 0.75)
	if _boundary_material != null:
		_boundary_material.set_shader_parameter("return_pulse", _score_pulse)
	if _score_pulse <= 0.0:
		set_process(false)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_progress_ticks.clear()
	_progress_materials.clear()
	_up_light = null
	_boundary_material = null
	_build()
	_apply_night_vision()


func _build() -> void:
	position.y = ground_height
	set_process(false)
	_add_goal_boundary()
	# The migration runs along world X. Face the passage down that line while
	# keeping the terrain-sampled goal boundary in unrotated world coordinates.
	_architecture_root = Node3D.new()
	_architecture_root.name = "GateArchitecture"
	# Turn the tally and ofuda around from the old cross-grove presentation so
	# the tutorial player's position southwest of the goal sees their front.
	_architecture_root.rotation.y = -PI * 0.5
	add_child(_architecture_root)
	var warm_wood := _lacquered_wood(Color(1.0, 0.80, 0.70), 0.56)
	var lacquer := _lacquered_wood(Color(1.0, 0.55, 0.48), 0.45)
	var stone := _material(Color("41413b"), Color("000000"), 0.0)
	var altar_top := _material(Color("887255"), Color("170d08"), 0.02)
	var paper := _material(Color("b4a17f"), Color("000000"), 0.0)
	var vermilion := _material(Color("8e3b27"), Color("000000"), 0.0)
	var bronze := _material(Color("786348"), Color("000000"), 0.0)
	bronze.metallic = 0.72
	bronze.roughness = 0.4

	# Keep the center clear for descending returns; place the altar and tally at the far rim.
	var altar_z := -maxf(0.35, goal_radius * 0.66)
	_add_box("Foundation", Vector3(1.15, 0.16, 0.82), Vector3(0.0, 0.08, altar_z), stone)
	_add_box("Altar", Vector3(0.76, 0.55, 0.54), Vector3(0.0, 0.435, altar_z), lacquer)
	_add_box("AltarBand", Vector3(0.84, 0.055, 0.61), Vector3(0.0, 0.68, altar_z), bronze)
	_add_box("AltarCap", Vector3(1.02, 0.11, 0.74), Vector3(0.0, 0.765, altar_z), altar_top)
	# A restrained pitched canopy breaks up the altar silhouette without filling
	# the return passage with a solid panel.
	var roof_left := _add_box("AltarRoofLeft", Vector3(0.62, 0.09, 0.78),
		Vector3(-0.29, 1.08, altar_z), warm_wood)
	roof_left.rotation.z = deg_to_rad(23.0)
	var roof_right := _add_box("AltarRoofRight", Vector3(0.62, 0.09, 0.78),
		Vector3(0.29, 1.08, altar_z), warm_wood)
	roof_right.rotation.z = deg_to_rad(-23.0)
	_add_box("AltarRoofRidge", Vector3(0.09, 0.11, 0.82),
		Vector3(0.0, 1.23, altar_z), lacquer)
	var post_x := 0.82
	for side in [-1.0, 1.0]:
		_add_box("GatewayPost", Vector3(0.17, 1.38, 0.17), Vector3(side * post_x, 0.76, 0.0), lacquer)
		_add_box("PostCollar", Vector3(0.205, 0.055, 0.205), Vector3(side * post_x, 1.19, 0.0), bronze)
	_add_box("GatewayLintel", Vector3(2.18, 0.15, 0.22), Vector3(0.0, 1.43, 0.0), warm_wood)
	_add_box("GatewayCrown", Vector3(2.48, 0.21, 0.36), Vector3(0.0, 1.58, 0.0), altar_top)
	# A small ofuda makes the gate read as a shrine. The paper is
	# matte and non-emissive so it catches the lantern instead of becoming a lamp.
	_add_box("OfudaCord", Vector3(0.035, 0.14, 0.028), Vector3(0.0, 1.36, 0.15), bronze)
	_add_box("Ofuda", Vector3(0.29, 0.39, 0.035), Vector3(0.0, 1.08, 0.17), paper)
	_add_box("OfudaSeal", Vector3(0.115, 0.115, 0.012), Vector3(0.0, 1.09, 0.195), vermilion)

	# Eight short amber marks communicate the total returned at a glance.
	for index in range(PROGRESS_TICKS):
		var material := _material(Color("302c2a"), Color("e9b872"), 0.012)
		var tick := _add_box("ProgressTick", Vector3(0.075, 0.055, 0.035),
			Vector3((float(index) - 3.5) * 0.105, 0.86, altar_z + 0.39), material)
		_progress_ticks.append(tick)
		_progress_materials.append(material)

	# A single buried upward cone gives broad, even fill across the gate and
	# guide, without four visible point-light pools on the ground.
	_up_light = SpotLight3D.new()
	_up_light.name = "ShrineWarmUplight"
	_up_light.light_color = Color("ffc477")
	_up_light.light_energy = 2.2
	_up_light.spot_range = 5.0
	_up_light.spot_angle = 78.0
	_up_light.spot_attenuation = 0.78
	_up_light.shadow_enabled = false
	_up_light.rotation.x = deg_to_rad(90.0)
	_up_light.position = Vector3(0.0, 0.07, 0.0)
	add_child(_up_light)


func _add_goal_boundary() -> void:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 128
	for segment: int in SEGMENTS + 1:
		var u := float(segment) / float(SEGMENTS)
		var angle := u * TAU
		var direction := Vector2(cos(angle), sin(angle))
		for radial: int in 3:
			var offset := (float(radial) - 1.0) * 0.085
			var point := direction * (goal_radius + offset)
			var height := ground_height
			if world_surface != null:
				height = float(world_surface.get_height_at(point + Vector2(position.x, position.z)))
			vertices.append(Vector3(point.x, height - ground_height + 0.045, point.y))
			uvs.append(Vector2(u, float(radial) * 0.5))
	for segment: int in SEGMENTS:
		var start := segment * 3
		for radial: int in 2:
			var a := start + radial
			var b := a + 3
			indices.append_array(PackedInt32Array([a, b, a + 1, b, b + 1, a + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var boundary := MeshInstance3D.new()
	boundary.name = "ReturnBoundary"
	boundary.mesh = mesh
	boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boundary_material = ShaderMaterial.new()
	_boundary_material.shader = load("res://shaders/goal_boundary.gdshader")
	_boundary_material.set_shader_parameter("adaptation", night_vision)
	_boundary_material.set_shader_parameter("return_pulse", _score_pulse)
	_boundary_material.set_shader_parameter("ring_color", Vector3(ring_color.r, ring_color.g, ring_color.b))
	boundary.material_override = _boundary_material
	add_child(boundary)


func _apply_night_vision() -> void:
	# Keep the landmark legible at low adaptation without acting like another beacon.
	if _up_light != null:
		_up_light.light_energy = lerpf(1.65, 2.2, night_vision)


func _add_box(node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at + Vector3.UP * _terrain_delta(at)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_architecture_root.add_child(instance)
	return instance


func _add_cylinder(node_name: String, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.2
	mesh.height = height
	instance.mesh = mesh
	instance.position = at + Vector3.UP * _terrain_delta(at)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_architecture_root.add_child(instance)
	return instance


func _terrain_delta(local_position: Vector3) -> float:
	if world_surface == null or _architecture_root == null:
		return 0.0
	var world_position := _architecture_root.to_global(local_position)
	return float(world_surface.get_height_at(Vector2(world_position.x, world_position.z))) - ground_height


func _material(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	material.metallic = 0.0
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	return material


func _lacquered_wood(tint: Color, roughness_value: float) -> StandardMaterial3D:
	var material := _material(tint, Color("2e110b"), 0.018)
	material.albedo_texture = load("res://assets/forest/polyhaven/material_pass/lacquered_cherry_wood_diff_2k.jpg")
	material.normal_enabled = true
	material.normal_texture = load("res://assets/forest/polyhaven/material_pass/lacquered_cherry_wood_nor_gl_2k.jpg")
	material.normal_scale = 0.25
	material.roughness = roughness_value
	return material
