class_name Lantern
extends Node3D

signal changed

var mode: LightField.Mode = LightField.Mode.BLUE
var shutter_openness: float = 1.0
var _last_open: float = 1.0
var spot: SpotLight3D
var glow_mesh: MeshInstance3D
var filter_mesh: MeshInstance3D
var night_vision: float = 1.0
var _adaptation := NightAdaptation.new()
var _filter_material: StandardMaterial3D
var _last_visual_mode: int = -1
var _last_visual_openness: float = -1.0
var _requested_mode: LightField.Mode = LightField.Mode.BLUE
var _transition_phase: int = 0
var _transition_elapsed: float = 0.0
var _transition_open: float = 1.0
const FILTER_HALF_TIME := 0.12

func _ready() -> void:
	_build_visual()
	_apply_visual()

func _build_visual() -> void:
	spot = SpotLight3D.new()
	spot.name = "VisibleBeam"
	spot.spot_range = 10.5
	# Godot's angle is the cone radius: 55 degrees makes a 110 degree beam.
	spot.spot_angle = 55.0
	spot.spot_angle_attenuation = 0.25
	spot.shadow_enabled = true
	spot.light_energy = 0.0
	spot.light_volumetric_fog_energy = 0.0
	add_child(spot)

	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.025
	handle_mesh.bottom_radius = 0.025
	handle_mesh.height = 0.65
	handle.mesh = handle_mesh
	handle.rotation.x = PI * 0.5
	handle.position = Vector3(0.0, 0.0, 0.28)
	handle.material_override = _material(Color("5a4030"), 0.15)
	add_child(handle)

	var cage := MeshInstance3D.new()
	var cage_mesh := CylinderMesh.new()
	cage_mesh.top_radius = 0.18
	cage_mesh.bottom_radius = 0.24
	cage_mesh.height = 0.32
	cage.mesh = cage_mesh
	cage.rotation.x = PI * 0.5
	cage.position = Vector3(0.0, 0.0, -0.11)
	cage.material_override = _material(Color("342c35"), 0.45)
	add_child(cage)

	filter_mesh = MeshInstance3D.new()
	var filter_sphere := SphereMesh.new()
	filter_sphere.radius = 0.14
	filter_sphere.height = 0.28
	filter_mesh.mesh = filter_sphere
	filter_mesh.scale = Vector3(1.0, 0.72, 1.0)
	filter_mesh.position = Vector3(0.0, 0.0, -0.2)
	_filter_material = _material(Color("f8e5b2"), 0.0)
	_filter_material.emission_enabled = true
	filter_mesh.material_override = _filter_material
	add_child(filter_mesh)

	# The emitter is inside this proxy housing; it must not shadow its own beam.
	for child: Node in get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow_mesh = filter_mesh

func set_mode(new_mode: LightField.Mode) -> void:
	_transition_phase = 0
	mode = new_mode
	_requested_mode = new_mode
	_apply_visual()
	changed.emit()

func request_mode(new_mode: LightField.Mode) -> void:
	if new_mode == _requested_mode:
		return
	_requested_mode = new_mode
	if _transition_phase == 0:
		_transition_open = shutter_openness
	_transition_elapsed = 0.0
	_transition_phase = 1

func advance_transition(delta: float) -> void:
	if _transition_phase == 0:
		return
	_transition_elapsed += clampf(delta, 0.0, 0.1)
	var t := clampf(_transition_elapsed / FILTER_HALF_TIME, 0.0, 1.0)
	if _transition_phase == 1:
		shutter_openness = _transition_open * (1.0 - t)
		if t >= 1.0:
			mode = _requested_mode
			_transition_phase = 2
			_transition_elapsed = 0.0
	else:
		shutter_openness = _transition_open * t
		if t >= 1.0:
			_transition_phase = 0
	_apply_visual()
	changed.emit()

func toggle_shutter() -> void:
	_transition_phase = 0
	if shutter_openness > 0.02:
		_last_open = shutter_openness
		shutter_openness = 0.0
	else:
		shutter_openness = maxf(_last_open, 0.55)
	_apply_visual()
	changed.emit()

func adjust_shutter(amount: float) -> void:
	_transition_phase = 0
	shutter_openness = clampf(shutter_openness + amount, 0.0, 1.0)
	if shutter_openness > 0.02:
		_last_open = shutter_openness
	_apply_visual()
	changed.emit()

func set_shutter(value: float, cancel_transition: bool = true) -> void:
	var bounded := clampf(value, 0.0, 1.0)
	if cancel_transition:
		_transition_phase = 0
	elif _transition_phase != 0:
		_transition_open = bounded
		return
	shutter_openness = bounded
	if shutter_openness > 0.02:
		_last_open = shutter_openness
	_apply_visual()
	changed.emit()

func forward_direction() -> Vector3:
	return -global_basis.z.normalized()


func advance_adaptation(delta: float, viewer_exposure: float = 1.0) -> void:
	night_vision = _adaptation.advance(delta, mode, shutter_openness, viewer_exposure)
	_apply_visual()

func mode_label() -> String:
	match mode:
		LightField.Mode.BLUE:
			return "BLUE · ATTRACT / CALM"
		LightField.Mode.ORANGE:
			return "ORANGE · REPEL / ENERGIZE"
		_:
			return "CLEAR · NAVIGATION / NEUTRAL"

func _apply_visual() -> void:
	if spot == null:
		return
	var color := Color("f8e5b2")
	var base_energy := 10.0
	var range_m := 20.0
	if mode == LightField.Mode.BLUE:
		color = Color("65c8ff")
		base_energy = 3.4
		range_m = 10.5
	elif mode == LightField.Mode.ORANGE:
		color = Color("ff9852")
		base_energy = 3.8
		range_m = 10.5
	if _last_visual_mode != int(mode):
		spot.light_color = color
		spot.spot_range = range_m
		_filter_material.albedo_color = color
		_filter_material.emission = color
		_last_visual_mode = int(mode)
	spot.light_energy = base_energy * shutter_openness * _adaptation.lantern_gain()
	if _last_visual_openness != shutter_openness:
		spot.visible = shutter_openness > 0.01
		_filter_material.emission_energy_multiplier = (1.5 + shutter_openness * 2.5) * shutter_openness
		filter_mesh.scale = Vector3.ONE * lerpf(0.65, 1.0, shutter_openness)
		_last_visual_openness = shutter_openness

func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
