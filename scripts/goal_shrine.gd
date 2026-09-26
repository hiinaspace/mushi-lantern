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
var _ember_material: StandardMaterial3D
var _ember_lights: Array[OmniLight3D] = []
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
		child.queue_free()
	_progress_ticks.clear()
	_progress_materials.clear()
	_ember_lights.clear()
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
	_architecture_root.rotation.y = PI * 0.5
	add_child(_architecture_root)
	var dark_wood := _material(Color("211b18"), Color("100b08"), 0.12)
	var warm_wood := _material(Color("38261b"), Color("1b0c05"), 0.1)
	var stone := _material(Color("30312d"), Color("100f0d"), 0.08)
	var altar_top := _material(Color("52473a"), Color("271607"), 0.12)
	_ember_material = _material(Color("e6853e"), Color("ff6b28"), 1.0)

	# Keep the center clear for descending returns; place the altar and tally at the far rim.
	var altar_z := -maxf(0.35, goal_radius * 0.66)
	_add_box("Foundation", Vector3(1.15, 0.16, 0.82), Vector3(0.0, 0.08, altar_z), stone)
	_add_box("Altar", Vector3(0.76, 0.55, 0.54), Vector3(0.0, 0.435, altar_z), warm_wood)
	_add_box("AltarCap", Vector3(1.02, 0.11, 0.74), Vector3(0.0, 0.765, altar_z), altar_top)
	var post_x := 0.82
	for side in [-1.0, 1.0]:
		_add_box("GatewayPost", Vector3(0.12, 1.3, 0.12), Vector3(side * post_x, 0.73, 0.0), dark_wood)
	_add_box("GatewayLintel", Vector3(2.05, 0.16, 0.2), Vector3(0.0, 1.45, 0.0), warm_wood)
	_add_box("GatewayCrown", Vector3(2.24, 0.08, 0.25), Vector3(0.0, 1.57, 0.0), altar_top)

	# Eight short amber marks communicate the total returned at a glance.
	for index in range(PROGRESS_TICKS):
		var material := _material(Color("302c2a"), Color("e9b872"), 0.025)
		var tick := _add_box("ProgressTick", Vector3(0.075, 0.055, 0.035),
			Vector3((float(index) - 3.5) * 0.105, 0.86, altar_z + 0.39), material)
		_progress_ticks.append(tick)
		_progress_materials.append(material)

	var brazier_distance := goal_radius + 0.42
	for side in [-1.0, 1.0]:
		var x: float = float(side) * brazier_distance
		_add_cylinder("BrazierFoot", 0.22, 0.12, Vector3(x, 0.06, 0.0), stone)
		_add_cylinder("BrazierCup", 0.14, 0.32, Vector3(x, 0.27, 0.0), warm_wood)
		_add_cylinder("BrazierRim", 0.2, 0.065, Vector3(x, 0.46, 0.0), altar_top)
		var ember := MeshInstance3D.new()
		ember.name = "Ember"
		var ember_mesh := SphereMesh.new()
		ember_mesh.radius = 0.09
		ember_mesh.height = 0.18
		ember.mesh = ember_mesh
		ember.position = Vector3(x, 0.56, 0.0)
		ember.material_override = _ember_material
		_architecture_root.add_child(ember)
		var light := OmniLight3D.new()
		light.name = "BrazierGlow"
		light.light_color = Color("ff8d4c")
		light.light_energy = 0.22
		light.omni_range = 2.2
		light.shadow_enabled = false
		light.position = Vector3(x, 0.6, 0.0)
		_architecture_root.add_child(light)
		_ember_lights.append(light)


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
	if _ember_material != null:
		_ember_material.emission_energy_multiplier = lerpf(0.5, 1.0, night_vision)
	for light in _ember_lights:
		light.light_energy = lerpf(0.14, 0.24, night_vision)


func _add_box(node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
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
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_architecture_root.add_child(instance)
	return instance


func _material(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	return material
