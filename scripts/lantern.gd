class_name Lantern
extends Node3D

signal changed

var mode: LightField.Mode = LightField.Mode.BLUE
var shutter_openness: float = 1.0
var _last_open: float = 1.0
var spot: SpotLight3D
var glow_mesh: MeshInstance3D
var filter_mesh: MeshInstance3D

func _ready() -> void:
	_build_visual()
	_apply_visual()

func _build_visual() -> void:
	spot = SpotLight3D.new()
	spot.name = "VisibleBeam"
	spot.spot_range = 10.5
	spot.spot_angle = 38.0
	spot.shadow_enabled = true
	spot.light_energy = 5.0
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
	add_child(filter_mesh)

	# The emitter is inside this proxy housing; it must not shadow its own beam.
	for child: Node in get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow_mesh = filter_mesh

func set_mode(new_mode: LightField.Mode) -> void:
	mode = new_mode
	_apply_visual()
	changed.emit()

func toggle_shutter() -> void:
	if shutter_openness > 0.02:
		_last_open = shutter_openness
		shutter_openness = 0.0
	else:
		shutter_openness = maxf(_last_open, 0.55)
	_apply_visual()
	changed.emit()

func adjust_shutter(amount: float) -> void:
	shutter_openness = clampf(shutter_openness + amount, 0.0, 1.0)
	if shutter_openness > 0.02:
		_last_open = shutter_openness
	_apply_visual()
	changed.emit()

func forward_direction() -> Vector3:
	return -global_basis.z.normalized()

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
	var base_energy := 6.0
	if mode == LightField.Mode.BLUE:
		color = Color("65c8ff")
		base_energy = 3.4
	elif mode == LightField.Mode.ORANGE:
		color = Color("ff9852")
		base_energy = 3.8
	spot.light_color = color
	spot.light_energy = base_energy * shutter_openness
	spot.visible = shutter_openness > 0.01
	filter_mesh.material_override = _material(color, 1.5 + shutter_openness * 2.5)
	filter_mesh.scale = Vector3.ONE * lerpf(0.65, 1.0, shutter_openness)

func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
