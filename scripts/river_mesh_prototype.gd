class_name RiverMeshPrototype
extends MeshInstance3D

## Independent near-grove tube experiment. The live opaque receiver is left
## intact until this raster path proves stereo, foliage, and blocker masking.
const SHADER: Shader = preload("res://shaders/river_mesh_prototype.gdshader")
const CREST_HALF_M := 28.0
const SIDES := 24


func _init() -> void:
	name = "RiverMeshPrototype"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("shell_index", 0)
	material.render_priority = 0
	material_override = material
	mesh = _build_mesh()
	# Shader deformation can widen and deepen the tube beyond its base vertices.
	custom_aabb = AABB(Vector3(-3020.0, -135.0, -70.0), Vector3(6040.0, 150.0, 140.0))


func _ready() -> void:
	for layer in [1, 2]:
		var shell := MeshInstance3D.new()
		shell.name = "ParticleShell%d" % layer
		shell.mesh = mesh
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("shell_index", layer)
		material.render_priority = layer
		shell.material_override = material
		shell.custom_aabb = custom_aabb
		add_child(shell)
	apply_tuning({})


func set_tuning(values: Dictionary) -> void:
	apply_tuning(values)


func apply_tuning(values: Dictionary) -> void:
	var names := ["river_width", "river_depth", "path_long_scale", "path_medium_scale", "path_long_frequency", "path_medium_frequency", "path_long_speed", "path_medium_speed", "surface_bump_scale", "surface_bump_frequency", "surface_bump_speed"]
	var keys := [&"river_width", &"river_depth", &"path_long", &"path_medium", &"path_long_frequency", &"path_medium_frequency", &"path_long_speed", &"path_medium_speed", &"surface_bump", &"surface_bump_frequency", &"surface_bump_speed"]
	var defaults := [2.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
	var targets: Array[Node] = [self]
	for child: Node in get_children():
		if child is MeshInstance3D:
			targets.append(child)
	for target: Node in targets:
		var material := (target as MeshInstance3D).material_override as ShaderMaterial
		if material == null:
			continue
		for i in names.size():
			material.set_shader_parameter(names[i], float(values.get(keys[i], defaults[i])))


func _build_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	var previous_center := Vector3.ZERO
	var arc_length := 0.0
	var x_positions: Array[float] = []
	for far_ring in 45:
		x_positions.append(-3000.0 + float(far_ring) * 40.0)
	for middle_ring in 135:
		x_positions.append(-1200.0 + float(middle_ring) * 8.0)
	for local_ring in 241:
		x_positions.append(-120.0 + float(local_ring))
	for middle_ring in 135:
		x_positions.append(128.0 + float(middle_ring) * 8.0)
	for far_ring in 45:
		x_positions.append(1240.0 + float(far_ring) * 40.0)
	for ring in x_positions.size():
		var x := x_positions[ring]
		var center := Vector3(x, _center_y(x), -2.0)
		if ring > 0:
			arc_length += center.distance_to(previous_center)
		previous_center = center
		var tangent := Vector3(1.0, _center_slope(x), 0.0).normalized()
		var cross_up := Vector3(0.0, 0.0, 1.0).cross(tangent).normalized()
		for side in SIDES + 1:
			var theta := TAU * float(side) / float(SIDES)
			var radial := Vector3(0.0, 0.0, cos(theta)) + cross_up * sin(theta)
			vertices.append(center + radial * 3.9)
			normals.append(radial)
			uv.append(Vector2(arc_length, float(side) / float(SIDES)))
			uv2.append(Vector2(x, theta))
		if ring > 0:
			for side in SIDES:
				var previous := (ring - 1) * (SIDES + 1) + side
				var current := ring * (SIDES + 1) + side
				indices.append_array(PackedInt32Array([
					previous, current, previous + 1,
					previous + 1, current, current + 1,
				]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func _center_y(x: float) -> float:
	var shoulder := maxf(1.0 - (x / CREST_HALF_M) ** 2.0, 0.0)
	return -30.0 + 14.0 * shoulder ** 3.0


static func _center_slope(x: float) -> float:
	var unit := x / CREST_HALF_M
	var shoulder := maxf(1.0 - unit * unit, 0.0)
	return -3.0 * unit * shoulder * shoulder
