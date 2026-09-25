class_name GlyphSwarm
extends Node3D

## One static quad per agent. Motion and arousal live in a three-row RGBA32F
## texture shared by the CPU and compute simulation backends:
## row 0 = previous position.xyz/arousal, row 1 = current position.xyz/arousal.
## Row 2 = last useful forward heading. A negative arousal marks release.

const GLYPH_SHADER := preload("res://shaders/mushi_glyph.gdshader")
const RELEASED := 3

@export var face_camera := false
@export var animate_vertices := true
@export var glow_strength := 0.72
@export var bloom_hdr_gain := 1.0

var world_bounds := AABB(Vector3(-35.0, -2.0, -35.0), Vector3(70.0, 16.0, 70.0))
var instance_count: int = 0
var _multimesh := MultiMesh.new()
var _mesh_instance := MultiMeshInstance3D.new()
var _material := ShaderMaterial.new()
var _cpu_image: Image
var _cpu_texture: ImageTexture
var _bound_texture: Texture2D
var _source_id: int = 0
var _source_revision: float = -INF
var _traits_source_id: int = 0
var _headings := PackedVector3Array()
var _clear_light_fade := 0.0
var clear_fade_start := 0.10
var clear_fade_end := 0.65

const CLEAR_FADE_MAX := 0.38
const CLEAR_FADE_IN_SECONDS := 0.40
const CLEAR_FADE_OUT_SECONDS := 2.20


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
	# POSITION is built in the vertex shader, so the static identity transforms
	# still need an explicit conservative world-space culling bound.
	_multimesh.custom_aabb = world_bounds
	for index: int in instance_count:
		_multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		_multimesh.set_instance_color(index, Color.WHITE)
		_multimesh.set_instance_custom_data(index, Color(float(index % 3) / 2.0, fmod(float(index) * 0.61803398875, 1.0), 1.0, 1.0))
	_mesh_instance.multimesh = _multimesh
	_cpu_image = null
	_cpu_texture = null
	_bound_texture = null
	_source_id = 0
	_source_revision = -INF
	_traits_source_id = 0
	_headings.resize(instance_count)
	for index: int in instance_count:
		_headings[index] = Vector3(sin(float(index) * 2.4), 0.0, cos(float(index) * 2.4))


func update_swarm(sim: Variant, alpha: float, preset: HerdPreset) -> void:
	if sim == null:
		return
	var count: int = sim.positions.size()
	if instance_count != count or _multimesh.instance_count != count:
		configure(count)
	var source_id: int = sim.get_instance_id()
	if source_id != _traits_source_id:
		_upload_traits(sim)
		_traits_source_id = source_id
	face_camera = preset.glyph_billboard
	_material.set_shader_parameter("interpolation_alpha", clampf(alpha, 0.0, 1.0))
	_material.set_shader_parameter("energy_neutral", preset.energy_neutral_target)
	_material.set_shader_parameter("population_variation", preset.population_variation)
	_material.set_shader_parameter("glyph_render_scale", clampf(preset.glyph_render_scale, 0.25, 2.0))
	_material.set_shader_parameter("clear_light_fade", _clear_light_fade)
	_apply_shader_options()

	var gpu_texture: Variant = sim.get("state_texture")
	if gpu_texture is Texture2D and (gpu_texture as Texture2D).get_width() == count:
		_bind_texture(gpu_texture as Texture2D)
		return
	# FlightSimulation increments _energy_time on every fixed step. The object
	# identity catches reset/replacement even when the new clock starts at zero.
	var revision: float = sim._energy_time
	if source_id != _source_id or revision != _source_revision:
		_upload_cpu_state(sim)
		_source_id = source_id
		_source_revision = revision


## Clear navigation light gently reduces distant glyph contrast. Colored
## herding light and a closed shutter immediately request visibility recovery;
## the visual-only fade-out trails stellar adaptation by roughly 0.7 seconds.
func update_visibility_context(night_vision: float, clear_mode: bool, shutter_openness: float, delta: float) -> void:
	var clear_exposure := clampf(shutter_openness, 0.0, 1.0) if clear_mode else 0.0
	var adapted_clear := 1.0 - smoothstep(clear_fade_start, clear_fade_end, clampf(night_vision, 0.0, 1.0))
	var target := CLEAR_FADE_MAX * clear_exposure * adapted_clear
	var seconds := CLEAR_FADE_OUT_SECONDS if target > _clear_light_fade else CLEAR_FADE_IN_SECONDS
	if delta > 0.0:
		_clear_light_fade = move_toward(_clear_light_fade, target, CLEAR_FADE_MAX * delta / seconds)
	_material.set_shader_parameter("clear_light_fade", _clear_light_fade)


func set_visual_tuning(values: Dictionary) -> void:
	clear_fade_start = clampf(float(values.get("clear_start", 0.10)), 0.0, 0.98)
	clear_fade_end = clampf(float(values.get("clear_end", 0.65)), clear_fade_start + 0.01, 1.0)
	_material.set_shader_parameter("clear_fade_distance_start", float(values.get("clear_distance_start", 17.0)))
	_material.set_shader_parameter("clear_fade_distance_end", float(values.get("clear_distance_end", 52.0)))


func _upload_traits(sim: Variant) -> void:
	for index: int in instance_count:
		var subtype: int = sim.trait_types[index] if index < sim.trait_types.size() else index % 3
		var size_factor: float = sim.trait_sizes[index] if index < sim.trait_sizes.size() else 1.0
		var tint: Color = sim.trait_tints[index] if index < sim.trait_tints.size() else Color.WHITE
		_multimesh.set_instance_color(index, tint)
		_multimesh.set_instance_custom_data(index, Color(float(posmod(subtype, 3)) / 2.0, fmod(float(index) * 0.61803398875, 1.0), size_factor, 1.0))


func _upload_cpu_state(sim: Variant) -> void:
	var width := maxi(instance_count, 1)
	if _cpu_image == null or _cpu_image.get_width() != width:
		_cpu_image = Image.create(width, 3, false, Image.FORMAT_RGBAF)
		_cpu_texture = null
	for index: int in instance_count:
		var current: Vector3 = sim.positions[index]
		var previous: Vector3 = sim.previous_positions[index] if index < sim.previous_positions.size() else current
		var arousal: float = sim.arousals[index] if index < sim.arousals.size() else 0.45
		if index < sim.lifecycles.size() and sim.lifecycles[index] == RELEASED:
			arousal = -1.0
		_cpu_image.set_pixel(index, 0, Color(previous.x, previous.y, previous.z, arousal))
		_cpu_image.set_pixel(index, 1, Color(current.x, current.y, current.z, arousal))
		var velocity: Vector3 = sim.velocities[index] if index < sim.velocities.size() else Vector3.ZERO
		if velocity.length_squared() >= 0.0001:
			_headings[index] = velocity.normalized()
		var heading: Vector3 = _headings[index]
		_cpu_image.set_pixel(index, 2, Color(heading.x, heading.y, heading.z, 0.0))
	if _cpu_texture == null:
		_cpu_texture = ImageTexture.create_from_image(_cpu_image)
	else:
		_cpu_texture.update(_cpu_image)
	_bind_texture(_cpu_texture)


func _bind_texture(value: Texture2D) -> void:
	if _bound_texture != value:
		_bound_texture = value
		_material.set_shader_parameter("state_texture", value)


## Retained for deterministic checks of the former CPU orientation convention.
static func heading_basis(velocity: Vector3, previous: Basis) -> Basis:
	if velocity.length_squared() < 0.0001:
		return previous
	var forward := velocity.normalized()
	var normal := forward.cross(Vector3.UP)
	if normal.length_squared() < 0.01:
		normal = previous.z - forward * previous.z.dot(forward)
		if normal.length_squared() < 0.0001:
			normal = forward.cross(Vector3.FORWARD)
	normal = normal.normalized()
	if normal.dot(previous.z) < 0.0:
		normal = -normal
	return Basis(forward.cross(normal).normalized(), forward, normal)


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
		return Color(0.0, 0.0, 0.0, 0.0)
	return _multimesh.get_instance_custom_data(index)


func debug_instance_visible(index: int) -> bool:
	if index < 0 or index >= instance_count:
		return false
	if _cpu_image == null or _bound_texture != _cpu_texture:
		return true
	return _cpu_image.get_pixel(index, 1).a >= 0.0


func _apply_shader_options() -> void:
	_material.set_shader_parameter("face_camera", face_camera)
	_material.set_shader_parameter("animate_vertices", animate_vertices)
	_material.set_shader_parameter("glow_strength", glow_strength)
	_material.set_shader_parameter("bloom_hdr_gain", clampf(bloom_hdr_gain, 1.0, 2.0))


func set_world_bounds(bounds: AABB) -> void:
	world_bounds = bounds
	_multimesh.custom_aabb = bounds
