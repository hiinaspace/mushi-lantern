class_name FernGroundcoverAudition
extends Node3D

const FERN_SCENE: PackedScene = preload("res://assets/forest/polyhaven/fern_02/fern_02_1k.gltf")
const FERN_SHADER: Shader = preload("res://shaders/fern_groundcover.gdshader")
const RIVER_MASK_SHADER: Shader = preload("res://shaders/fern_river_mask.gdshader")
const CELL_SIZE := 16.0

var instance_total := 0
var cell_total := 0
var _material: ShaderMaterial
var _river_mask: ShaderMaterial
var _reveal_start := 0.90
var _reveal_end := 0.99

## Opt-in fern audition. Existing terrain, collider, grass and stream mask stay
## in place. Small 16 m cells allow normal frustum and distance culling.
func build(surface: EnvironmentSurface, low_quality: bool = false) -> void:
	for child in get_children():
		child.queue_free()
	instance_total = 0
	cell_total = 0
	var fern_mesh := _small_clump_mesh()
	if fern_mesh == null:
		push_error("Poly Haven fern_02 small clump is missing")
		return
	_material = ShaderMaterial.new()
	_material.shader = FERN_SHADER
	_material.set_shader_parameter("fern_diffuse", load("res://assets/forest/polyhaven/fern_02/textures/fern_02_diff_1k.jpg"))
	_material.set_shader_parameter("fern_alpha", load("res://assets/forest/polyhaven/fern_02/textures/fern_02_alpha_1k.jpg"))
	_material.set_shader_parameter("reveal_start", _reveal_start)
	_material.set_shader_parameter("reveal_end", _reveal_end)
	_river_mask = ShaderMaterial.new()
	_river_mask.shader = RIVER_MASK_SHADER
	_river_mask.render_priority = -20
	_river_mask.set_shader_parameter("fern_alpha", load("res://assets/forest/polyhaven/fern_02/textures/fern_02_alpha_1k.jpg"))
	var cells: Dictionary = {}
	var grass_index := 0
	var stride := 60 if low_quality else 30
	for prop: Dictionary in surface.get_props():
		if prop.kind != "grass":
			continue
		grass_index += 1
		var position: Vector3 = prop.position
		var xz := Vector2(position.x, position.z)
		# The authored lesson looks along this stream-facing bank. A little
		# extra edge detail there makes the traversable terrain legible during
		# adaptation while keeping the shrine ring and lesson path open.
		var stream_bank := xz.x > 6.0 and xz.x < 28.0 and xz.y > -9.0 and xz.y < 7.0 \
			and xz.distance_to(Vector2(-3.0, 4.0)) > 7.0 \
			and xz.distance_to(Vector2(0.0, 18.4)) > 9.0
		var chosen_stride := (10 if low_quality else 5) if stream_bank else stride
		if grass_index % chosen_stride != 0:
			continue
		var cell := Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))
		var transforms: Array = cells.get(cell, [])
		var variant: int = int(prop.get("variant", 0))
		# Distinct clump silhouettes without a second draw material or mesh.
		var size_hash := float(posmod(grass_index * 37 + variant * 17, 101)) / 100.0
		var scale := 0.62 + 1.38 * size_hash
		var width := 0.86 + 0.28 * (1.0 - size_hash)
		var basis := Basis(Vector3.UP, float(prop.yaw)).scaled(Vector3(scale * width, scale, scale / width))
		var cell_origin := Vector3(float(cell.x) * CELL_SIZE, 0.0, float(cell.y) * CELL_SIZE)
		transforms.append(Transform3D(basis, position - cell_origin))
		cells[cell] = transforms
	for cell: Vector2i in cells:
		var transforms: Array = cells[cell]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = fern_mesh
		multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index, transforms[index])
		var patch := MultiMeshInstance3D.new()
		patch.name = "FernCell_%d_%d" % [cell.x, cell.y]
		patch.multimesh = multi
		patch.material_override = _material
		patch.material_overlay = _river_mask
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.visibility_range_end = 18.0 if low_quality else 28.0
		patch.visibility_range_end_margin = 3.0
		patch.position = Vector3(float(cell.x) * CELL_SIZE, 0.0, float(cell.y) * CELL_SIZE)
		add_child(patch)
		instance_total += transforms.size()
		cell_total += 1

func set_night_vision(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("night_vision", clampf(value, 0.0, 1.0))

func set_reveal_range(start: float, end: float) -> void:
	_reveal_start = start
	_reveal_end = end
	if _material != null:
		_material.set_shader_parameter("reveal_start", _reveal_start)
		_material.set_shader_parameter("reveal_end", _reveal_end)

func _small_clump_mesh() -> Mesh:
	var scene := FERN_SCENE.instantiate()
	var mesh: Mesh
	for child in scene.get_children():
		if child is MeshInstance3D and child.name == "fern_02_a":
			mesh = child.mesh
			break
	scene.free()
	return mesh
