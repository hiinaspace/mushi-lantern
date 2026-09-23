class_name Lantern
extends Node3D

signal changed

const FILTER_HALF_TIME := 0.12
const BLIND_COUNT := 7
const COOKIE_SIZE := 64
const COOKIE_STEPS := 16

var mode: LightField.Mode = LightField.Mode.BLUE
var shutter_openness: float = 1.0
var _last_open: float = 1.0
var spot: SpotLight3D
var glow_mesh: MeshInstance3D
var filter_mesh: MeshInstance3D
var night_vision: float = 1.0
var _adaptation := NightAdaptation.new()
var _filter_material: StandardMaterial3D
var _glyph_materials: Array[StandardMaterial3D] = []
var _aperture_line: MeshInstance3D
var _front_strips: Array[MeshInstance3D] = []
var _last_visual_mode: int = -1
var _last_visual_openness: float = -1.0
var _requested_mode: LightField.Mode = LightField.Mode.BLUE
var _transition_phase: int = 0
var _transition_elapsed: float = 0.0
var _transition_open: float = 1.0
var _flame_time := 0.0
var _flame_gain := 1.0
var _cookie_step := -1
var _cookie_textures: Array[Texture2D] = []

func _ready() -> void:
	_build_visual()
	_apply_visual()

func _build_visual() -> void:
	spot = SpotLight3D.new()
	spot.name = "VisibleBeam"
	spot.position = Vector3(0.0, 0.0, -0.145)
	spot.spot_range = 10.5
	# Godot's angle is the cone radius: 55 degrees makes a 110 degree beam.
	spot.spot_angle = 55.0
	spot.spot_angle_attenuation = 0.25
	spot.shadow_enabled = true
	spot.light_energy = 0.0
	spot.light_volumetric_fog_energy = 0.0
	add_child(spot)

	var metal := _material(Color("514751"), 0.0)
	var dark := _material(Color("1b1a21"), 0.0)
	var glass := _material(Color("2e3036"), 0.0)
	# Opaque side and rear walls keep the high-energy emitter directional.
	_box("RearWall", Vector3(0.34, 0.40, 0.018), Vector3(0.0, 0.0, 0.112), metal)
	_box("LeftWall", Vector3(0.018, 0.40, 0.23), Vector3(-0.17, 0.0, 0.0), metal)
	_box("RightWall", Vector3(0.018, 0.40, 0.23), Vector3(0.17, 0.0, 0.0), metal)
	_box("Top", Vector3(0.35, 0.022, 0.25), Vector3(0.0, 0.20, 0.0), metal)
	_box("Bottom", Vector3(0.35, 0.022, 0.25), Vector3(0.0, -0.20, 0.0), metal)
	_box("FrontWindowBacking", Vector3(0.305, 0.35, 0.004), Vector3(0.0, 0.0, -0.119), glass)
	for x: float in [-0.163, 0.163]:
		_box("FrontStile", Vector3(0.018, 0.40, 0.025), Vector3(x, 0.0, -0.131), metal)
	for y: float in [-0.19, 0.19]:
		_box("FrontRail", Vector3(0.34, 0.018, 0.025), Vector3(0.0, y, -0.131), metal)

	filter_mesh = _box("FrontGlow", Vector3(0.29, 0.33, 0.003), Vector3(0.0, 0.0, -0.126), null)
	_filter_material = _material(Color("f8e5b2"), 0.0)
	_filter_material.emission_enabled = true
	filter_mesh.material_override = _filter_material
	glow_mesh = filter_mesh
	# A strip always has a dark hinge line; the lit part grows upwards within it.
	for i: int in BLIND_COUNT:
		var strip := _box("FrontStrip%d" % i, Vector3(0.294, 0.01, 0.005), Vector3(0.0, 0.0, -0.131), dark)
		_front_strips.append(strip)

	# The suspension is part of the lantern so it follows the pendulum joint.
	_box("Hanger", Vector3(0.013, 0.17, 0.013), Vector3(0.0, 0.29, 0.0), metal)
	_box("HangerLoop", Vector3(0.08, 0.015, 0.06), Vector3(0.0, 0.38, 0.0), metal)

	var rear_face := _material(Color("242630"), 0.0)
	_box("RearIndicatorPanel", Vector3(0.25, 0.20, 0.005), Vector3(0.0, 0.067, 0.124), rear_face)
	var glyph_colors := [Color("65c8ff"), Color("f8e5b2"), Color("ff9852")]
	for i: int in 3:
		var glyph_material := _material(glyph_colors[i], 0.0)
		glyph_material.emission_enabled = true
		_glyph_materials.append(glyph_material)
		var x := (float(i) - 1.0) * 0.075
		# Three legible greybox glyphs read left to right: wave, diamond, rays.
		if i == 0:
			for segment: int in 2:
				var stroke := _box("BlueWave%d" % segment, Vector3(0.009, 0.047, 0.003), Vector3(x + (float(segment) - 0.5) * 0.018, 0.085, 0.129), glyph_material)
				stroke.rotation.z = -0.43 if segment == 0 else 0.43
		elif i == 1:
			var diamond := _box("ClearDiamond", Vector3(0.028, 0.028, 0.003), Vector3(x, 0.085, 0.129), glyph_material)
			diamond.rotation.z = PI * 0.25
		else:
			for ray: int in 3:
				_box("OrangeRay%d" % ray, Vector3(0.035 - absf(float(ray) - 1.0) * 0.012, 0.007, 0.003), Vector3(x, 0.065 + float(ray) * 0.019, 0.129), glyph_material)
	_box("ApertureTrack", Vector3(0.012, 0.105, 0.003), Vector3(0.0, -0.055, 0.128), dark)
	_aperture_line = _box("ApertureLevel", Vector3(0.009, 0.10, 0.003), Vector3(0.0, -0.055, 0.132), _material(Color("f8e5b2"), 1.3))

	# Housing geometry is a proxy and must not shadow the spotlight itself.
	for child: Node in get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _box(label: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	if material != null:
		part.material_override = material
	add_child(part)
	return part

func _update_cookie() -> void:
	var step := clampi(roundi(shutter_openness * COOKIE_STEPS), 0, COOKIE_STEPS)
	if step == _cookie_step:
		return
	if _cookie_textures.is_empty():
		_cookie_textures.resize(COOKIE_STEPS + 1)
	if _cookie_textures[step] != null:
		spot.light_projector = _cookie_textures[step]
		_cookie_step = step
		return
	var visual_open := float(step) / float(COOKIE_STEPS)
	var image := Image.create(COOKIE_SIZE, COOKIE_SIZE, false, Image.FORMAT_RGB8)
	for y: int in COOKIE_SIZE:
		var row := 1.0 - float(y) / float(COOKIE_SIZE - 1)
		var strip_position := fposmod(row * float(BLIND_COUNT), 1.0)
		var lit := strip_position > 0.14 and strip_position < 0.14 + 0.80 * visual_open
		var intensity := 1.0 if lit else 0.0
		# A slight center falloff keeps the square projection from showing hard corners.
		for x: int in COOKIE_SIZE:
			var u := (float(x) + 0.5) / float(COOKIE_SIZE)
			var edge := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.86, 1.0, u))
			image.set_pixel(x, y, Color.WHITE * (intensity * edge))
	_cookie_textures[step] = ImageTexture.create_from_image(image)
	spot.light_projector = _cookie_textures[step]
	_cookie_step = step

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

func advance_flame(delta: float) -> void:
	_flame_time += clampf(delta, 0.0, 0.1)
	var wave := sin(_flame_time * 17.0) * 0.55 + sin(_flame_time * 29.0 + 1.7) * 0.30 + sin(_flame_time * 43.0 + 0.4) * 0.15
	_flame_gain = 1.0 + wave * 0.035
	spot.position = Vector3(0.006 * sin(_flame_time * 11.0), 0.005 * sin(_flame_time * 13.0 + 0.8), -0.145)
	_apply_visual()

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
		var active_glyph := 0 if mode == LightField.Mode.BLUE else 2 if mode == LightField.Mode.ORANGE else 1
		for i: int in _glyph_materials.size():
			_glyph_materials[i].emission_energy_multiplier = 1.8 if i == active_glyph else 0.045
		_last_visual_mode = int(mode)
	spot.light_energy = base_energy * shutter_openness * _adaptation.lantern_gain() * _flame_gain
	if _last_visual_openness != shutter_openness:
		spot.visible = shutter_openness > 0.01
		_filter_material.emission_energy_multiplier = (1.5 + shutter_openness * 2.5) * shutter_openness * _flame_gain
		for i: int in BLIND_COUNT:
			var cell_height := 0.33 / float(BLIND_COUNT)
			var exposed := 0.80 * shutter_openness * cell_height
			_front_strips[i].scale.y = maxf((cell_height - exposed) / 0.01, 0.01)
			_front_strips[i].position.y = -0.165 + (float(i) + 0.5) * cell_height + exposed * 0.5
		_aperture_line.scale.y = maxf(shutter_openness, 0.001)
		_aperture_line.position.y = -0.105 + 0.05 * shutter_openness
		_update_cookie()
		_last_visual_openness = shutter_openness
	else:
		_filter_material.emission_energy_multiplier = (1.5 + shutter_openness * 2.5) * shutter_openness * _flame_gain

func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
