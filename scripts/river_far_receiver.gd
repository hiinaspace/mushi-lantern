class_name RiverFarReceiver
extends MeshInstance3D

## Sparse opaque far-country mesh. It only receives the same eye-ray volume as
## Terrain3D and foliage; no additive overlay bypasses staff or shrine depth.
const SHADER: Shader = preload("res://shaders/river_far_receiver.gdshader")
const GRID_STEP := 24

var _material: ShaderMaterial

func _init() -> void:
	name = "RiverFarCountry"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material

func configure(surface: EnvironmentSurface, map: ImageTexture, length_m: float) -> void:
	if surface == null:
		mesh = null
		return
	var extent := TerrainRiverReveal.path_extent(surface.size_m)
	mesh = _build_mesh(surface, extent)
	_material.set_shader_parameter("river_path_map", map)
	_material.set_shader_parameter("river_size", float(extent))
	_material.set_shader_parameter("river_length", length_m)
	_material.set_shader_parameter("river_plane_y", TerrainRiverReveal.RIVER_PLANE_Y)
	_material.set_shader_parameter("river_goal_xz", Vector2.ZERO)
	_material.set_shader_parameter("river_night_vision", 0.0)

func set_night_vision(value: float) -> void:
	_material.set_shader_parameter("river_night_vision", clampf(value, 0.0, 1.0))

func set_shrine_beam_visibility(value: float) -> void:
	_material.set_shader_parameter("shrine_beam_visibility", clampf(value, 0.0, 1.0))

func set_tube_enabled(enabled: bool) -> void:
	_material.set_shader_parameter("river_tube_enabled", 1.0 if enabled else 0.0)

func set_depth(scale: float) -> void:
	_material.set_shader_parameter("river_plane_y", TerrainRiverReveal.RIVER_PLANE_Y * scale)
	_material.set_shader_parameter("river_depth", scale)

func _build_mesh(surface: EnvironmentSurface, extent: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var half := float(surface.size_m) * 0.5
	var outer := float(extent) * 0.5
	var cells := int(ceilf(float(extent) / float(GRID_STEP)))
	for zi in cells:
		for xi in cells:
			var x0 := -outer + float(xi * GRID_STEP)
			var x1 := x0 + float(GRID_STEP)
			var z0 := -outer + float(zi * GRID_STEP)
			var z1 := z0 + float(GRID_STEP)
			if maxf(absf(x0), absf(x1)) <= half and maxf(absf(z0), absf(z1)) <= half:
				continue
			var base := vertices.size()
			vertices.append(_point(surface, Vector2(x0, z0), half))
			vertices.append(_point(surface, Vector2(x1, z0), half))
			vertices.append(_point(surface, Vector2(x0, z1), half))
			vertices.append(_point(surface, Vector2(x1, z1), half))
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	# Narrow far arms carry the ray receiver almost to the camera far plane.
	# The route evaluator continues the final centerline analytically there.
	var inner := outer
	var arm_step := 40.0
	var arm_cells := int(ceilf((TerrainRiverReveal.FAR_ARM_END_M - inner) / arm_step))
	for direction: float in [-1.0, 1.0]:
		for arm_index in arm_cells:
			var near_x := inner + float(arm_index) * arm_step
			var far_x := minf(near_x + arm_step, TerrainRiverReveal.FAR_ARM_END_M)
			var x0: float = near_x * direction
			var x1: float = far_x * direction
			var base := vertices.size()
			vertices.append(_point(surface, Vector2(x0, -28.0), half))
			vertices.append(_point(surface, Vector2(x1, -28.0), half))
			vertices.append(_point(surface, Vector2(x0, 28.0), half))
			vertices.append(_point(surface, Vector2(x1, 28.0), half))
			if direction > 0.0:
				indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
			else:
				indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func _point(surface: EnvironmentSurface, xz: Vector2, half: float) -> Vector3:
	var edge := Vector2(clampf(xz.x, -half + 0.01, half - 0.01), clampf(xz.y, -half + 0.01, half - 0.01))
	var outside := maxf(maxf(absf(xz.x), absf(xz.y)) - half, 0.0)
	var decay := exp(-outside / (float(surface.size_m) * 0.29))
	var y := surface.get_height_at(edge) * decay - 1.2 * (1.0 - decay) - 0.05
	return Vector3(xz.x, y, xz.y)
