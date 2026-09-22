class_name GlyphSwarm
extends Node3D

## A deliberately small rendering adapter for dense flight simulations. Every
## mushi is one camera-facing quad in one MultiMesh draw call; simulation state
## remains authoritative in FlightSimulation.

const GLYPH_SHADER := preload("res://shaders/mushi_glyph.gdshader")
const RELEASED := 3

@export var face_camera := true
@export var animate_vertices := true
@export var glow_strength := 0.72

var instance_count: int = 0
var _multimesh := MultiMesh.new()
var _mesh_instance := MultiMeshInstance3D.new()
var _material := ShaderMaterial.new()


func _init() -> void:
	_mesh_instance.name = "GlyphInstances"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	_material.shader = GLYPH_SHADER
	_apply_shader_options()


func configure(count: int) -> void:
	instance_count = maxi(0, count)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = _material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = instance_count
	# The arena is currently bounded to roughly 60 m. An explicit AABB prevents
	# the whole swarm disappearing while instance transforms are being replaced.
	_multimesh.custom_aabb = AABB(Vector3(-35.0, -2.0, -35.0), Vector3(70.0, 12.0, 70.0))
	_mesh_instance.multimesh = _multimesh


func update_swarm(sim: Variant, alpha: float, preset: HerdPreset) -> void:
	if sim == null:
		return
	var count: int = mini(instance_count, sim.positions.size())
	if _multimesh.instance_count != instance_count:
		configure(instance_count)
	_apply_shader_options()
	var blend := clampf(alpha, 0.0, 1.0)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var camera_basis_inverse := camera.global_transform.basis.inverse() if camera != null else Basis.IDENTITY
	for index: int in instance_count:
		if index >= count or (index < sim.lifecycles.size() and sim.lifecycles[index] == RELEASED):
			_multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			_multimesh.set_instance_color(index, Color(0.0, 0.0, 0.0, 0.0))
			_multimesh.set_instance_custom_data(index, Color(0.0, 0.0, 0.5, 0.0))
			continue
		var point: Vector3 = sim.positions[index]
		if index < sim.previous_positions.size():
			point = sim.previous_positions[index].lerp(point, blend)
		_multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))

		var energy: float = sim.arousals[index] if index < sim.arousals.size() else preset.energy_neutral_target
		var subtype: int = sim.trait_types[index] if index < sim.trait_types.size() else index % 3
		var color := EnergyVisual.color_for(energy, preset.energy_neutral_target)
		color = Color.from_hsv(fposmod(color.h + float(subtype - 1) * 0.04 * preset.population_variation, 1.0), color.s, color.v, color.a)
		var trait_tint := Color.WHITE
		if index < sim.trait_tints.size():
			trait_tint = sim.trait_tints[index]
		color = color.lerp(color * trait_tint, 0.18)
		color.a = 1.0
		_multimesh.set_instance_color(index, color)

		var size_factor: float = sim.trait_sizes[index] if index < sim.trait_sizes.size() else 1.0
		# trait_sizes is a relative phenotype. The base half-size keeps glyphs in
		# the requested ~0.12-0.25 m range without baking scale into transforms.
		var half_size := clampf(0.175 * size_factor, 0.12, 0.25)
		var heading := 0.0
		if index < sim.velocities.size():
			var velocity: Vector3 = sim.velocities[index]
			if velocity.length_squared() > 0.0001:
				if face_camera and camera != null:
					var view_velocity := camera_basis_inverse * velocity
					heading = atan2(-view_velocity.x, view_velocity.y)
				else:
					heading = atan2(velocity.x, velocity.z)
		var seed := fmod(float(index) * 0.61803398875, 1.0)
		_multimesh.set_instance_custom_data(index, Color(float(posmod(subtype, 3)) / 2.0, seed, heading / TAU + 0.5, half_size))


func debug_instance_transform(index: int) -> Transform3D:
	if index < 0 or index >= _multimesh.instance_count:
		return Transform3D.IDENTITY
	return _multimesh.get_instance_transform(index)


func debug_instance_color(index: int) -> Color:
	if index < 0 or index >= _multimesh.instance_count:
		return Color(0.0, 0.0, 0.0, 0.0)
	return _multimesh.get_instance_color(index)


func debug_instance_custom_data(index: int) -> Color:
	if index < 0 or index >= _multimesh.instance_count:
		return Color(0.0, 0.0, 0.5, 0.0)
	return _multimesh.get_instance_custom_data(index)


func debug_instance_visible(index: int) -> bool:
	return debug_instance_color(index).a > 0.001 and debug_instance_custom_data(index).a > 0.001


func _apply_shader_options() -> void:
	_material.set_shader_parameter("face_camera", face_camera)
	_material.set_shader_parameter("animate_vertices", animate_vertices)
	_material.set_shader_parameter("glow_strength", glow_strength)
