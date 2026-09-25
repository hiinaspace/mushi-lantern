class_name UndergroundStream
extends Node3D

## A quiet, below-ground migration band revealed through the terrain surface.
## The shader treats the sampled terrain surface as a reveal window while
## retaining ordinary depth occlusion from closer geometry.

const STREAM_SHADER: Shader = preload("res://shaders/underground_stream.gdshader")
const PATH_STEPS: int = 512
const HALF_WIDTH: float = 1.95

var _surface: EnvironmentSurface
var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _night_vision: float = 0.0
var _depth_below_ground: float = 1.5
var _goal_position := Vector2.ZERO

func _init() -> void:
	name = "UndergroundMigration"
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "MigrationBand"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_instance)
	_material = ShaderMaterial.new()
	_material.shader = STREAM_SHADER
	_material.set_shader_parameter("night_vision", _night_vision)
	_mesh_instance.material_override = _material

## Build a long grove-spanning ribbon from the same height samples used by
## Terrain3D. Set depth_below_ground to 1.5 m to align its center with returns.
func configure(surface: EnvironmentSurface, goal_position: Vector2 = Vector2.ZERO, depth_below_ground: float = 1.5) -> void:
	_surface = surface
	_goal_position = goal_position
	_depth_below_ground = maxf(0.1, depth_below_ground)
	if surface == null:
		_mesh_instance.mesh = null
		return
	_material.set_shader_parameter("terrain_height", ImageTexture.create_from_image(surface.get_height_image()))
	_material.set_shader_parameter("terrain_size", float(surface.size_m))
	_mesh_instance.mesh = _build_ribbon()
	_mesh_instance.custom_aabb = AABB(
		Vector3(-surface.size_m * 0.5, -4.0, -surface.size_m * 0.5),
		Vector3(surface.size_m, 28.0, surface.size_m)
	)

func set_night_vision(value: float) -> void:
	_night_vision = clampf(value, 0.0, 1.0)
	_material.set_shader_parameter("night_vision", _night_vision)

func set_stream_depth(depth_below_ground: float) -> void:
	_depth_below_ground = maxf(0.1, depth_below_ground)
	if _surface != null:
		_mesh_instance.mesh = _build_ribbon()

func _build_ribbon() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var step_count := PATH_STEPS
	var path := path_points(_surface.size_m, _goal_position, step_count)
	for index in path.size():
		var point: Vector2 = path[index]
		var before: Vector2 = path[maxi(0, index - 1)]
		var after: Vector2 = path[mini(path.size() - 1, index + 1)]
		var tangent := (after - before).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector2.RIGHT
		var side := Vector2(-tangent.y, tangent.x)
		var width := half_width_at(point, _goal_position)
		for edge in 2:
			var sign := -1.0 if edge == 0 else 1.0
			var xz := point + side * width * sign
			vertices.append(Vector3(xz.x, _surface.get_height_at(xz) - _depth_below_ground, xz.y))
			uvs.append(Vector2(float(index) / float(step_count), float(edge)))
			var pinch_weight := exp(-point.distance_squared_to(_goal_position) / 34.0)
			colors.append(Color(1.0 + 0.18 * pinch_weight, 1.0, 1.0, 1.0))
		if index > 0:
			var base := index * 2
			indices.append_array(PackedInt32Array([base - 2, base, base - 1, base - 1, base, base + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Shared centerline sampler for terrain reveal masks and visual alignment.
static func path_points(size_m: int, goal_position: Vector2 = Vector2.ZERO, step_count: int = PATH_STEPS) -> PackedVector2Array:
	# One horizontal axis supports a single compact vertical rise near the
	# shrine. No lateral turn or fold can multiply the projected tube there.
	var half_length := float(size_m) * 2.25
	var result := PackedVector2Array()
	for sample in step_count + 1:
		var x := lerpf(-half_length, half_length, float(sample) / float(step_count))
		result.append(goal_position + Vector2(x, -2.0))
	return result

static func half_width_at(point: Vector2, goal_position: Vector2 = Vector2.ZERO) -> float:
	return lerpf(HALF_WIDTH, 1.2, exp(-point.distance_squared_to(goal_position) / 34.0))
