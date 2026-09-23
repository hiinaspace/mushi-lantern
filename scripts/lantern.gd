class_name Lantern
extends Node3D

signal changed

const FILTER_HALF_TIME := 0.12
const BLIND_COUNT := 7
const COOKIE_SIZE := 64
const COOKIE_STEPS := 16
const HOUSING_SCALE := 0.7

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
var _aperture_lines: Array[MeshInstance3D] = []
var _front_strips: Array[MeshInstance3D] = []
var _visual_root: Node3D
var _dial: Node3D
var _dial_preview := 0.0
var _dial_preview_active := false
var _dial_preview_amount := 0.0
var _dial_preview_source: LightField.Mode = LightField.Mode.BLUE
var _dial_preview_target: LightField.Mode = LightField.Mode.CLEAR
var _settle_from_color := Color.WHITE
var _settle_elapsed := 1.0
var _last_visual_mode: int = -1
var _last_visual_openness: float = -1.0
var _requested_mode: LightField.Mode = LightField.Mode.BLUE
var _transition_phase: int = 0
var _transition_elapsed: float = 0.0
var _transition_open: float = 1.0
var _flame_time := 0.0
var _flame_gain := 1.0
var _projector_key := ""
var _projector_textures := {}

func _ready() -> void:
	_build_visual()
	_apply_visual()

func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualHousing"
	_visual_root.scale = Vector3.ONE * HOUSING_SCALE
	add_child(_visual_root)
	spot = SpotLight3D.new()
	spot.name = "VisibleBeam"
	spot.position = Vector3(0.0, 0.0, -0.145 * HOUSING_SCALE)
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
	var glyph_colors := [Color("65c8ff"), Color("f8e5b2"), Color("ff9852")]
	for i: int in 3:
		var glyph_material := _material(glyph_colors[i], 0.0)
		glyph_material.emission_enabled = true
		_glyph_materials.append(glyph_material)
	_add_status_face("Rear", Vector3(0.0, 0.0, 0.126), 0.0, rear_face, dark, 1.0)
	_add_status_face("Left", Vector3(-0.182, 0.0, 0.0), -PI * 0.5, rear_face, dark, 0.88)
	_add_status_face("Right", Vector3(0.182, 0.0, 0.0), PI * 0.5, rear_face, dark, 0.88)
	# The front retains a very small mode tell even with the shutter fully closed.
	for i: int in 3:
		_box("FrontMode%d" % i, Vector3(0.019, 0.008, 0.005), Vector3((float(i) - 1.0) * 0.028, -0.192, -0.148), _glyph_materials[i])
	# The offhand catches this short pull below the smaller housing.
	_box("SettingCord", Vector3(0.008, 0.14, 0.008), Vector3(0.0, -0.205, 0.0), dark, self)
	_box("SettingGrip", Vector3(0.042, 0.045, 0.027), Vector3(0.0, -0.29, 0.0), metal, self)

func control_grip_local_position() -> Vector3:
	return Vector3(0.0, -0.29, 0.0)

func _add_status_face(label: String, at: Vector3, yaw: float, panel: Material, track: Material, size_factor: float) -> void:
	var face := Node3D.new()
	face.name = label + "Status"
	face.position = at
	face.rotation.y = yaw
	face.scale = Vector3.ONE * size_factor
	_visual_root.add_child(face)
	_box(label + "Panel", Vector3(0.25, 0.20, 0.005), Vector3(0.0, 0.015, 0.0), panel, face)
	for i: int in 3:
		var x := (float(i) - 1.0) * 0.075
		var mark := _box(label + "Color%d" % i, Vector3(0.026, 0.026, 0.004), Vector3(x, 0.077, 0.006), _glyph_materials[i], face)
		if i == 1:
			mark.rotation.z = PI * 0.25
	_box(label + "ApertureTrack", Vector3(0.012, 0.105, 0.004), Vector3(0.10, -0.040, 0.006), track, face)
	var line := _box(label + "ApertureLevel", Vector3(0.009, 0.10, 0.005), Vector3(0.10, -0.040, 0.010), _material(Color("f8e5b2"), 1.3), face)
	_aperture_lines.append(line)
	if label == "Rear":
		_dial = Node3D.new()
		_dial.name = "ColorDial"
		_dial.position = Vector3(0.0, -0.125, 0.008)
		face.add_child(_dial)
		var disc := _box("DialBody", Vector3(0.046, 0.046, 0.008), Vector3.ZERO, _material(Color("7c746a"), 0.0), _dial)
		disc.rotation.z = PI * 0.25
		_box("DialPointer", Vector3(0.007, 0.029, 0.004), Vector3(0.0, 0.018, 0.007), _material(Color("f8e5b2"), 0.65), _dial)
		for i: int in 3:
			_box("DialDetent%d" % i, Vector3(0.009, 0.006, 0.004), Vector3((float(i) - 1.0) * 0.020, -0.099 if i != 1 else -0.090, 0.013), _glyph_materials[i], face)

func _box(label: String, size: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	if material != null:
		part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent == null:
		_visual_root.add_child(part)
	else:
		parent.add_child(part)
	return part

func _update_cookie() -> void:
	var step := 0 if shutter_openness <= 0.005 else COOKIE_STEPS if shutter_openness >= 0.995 else clampi(roundi(shutter_openness * COOKIE_STEPS), 1, COOKIE_STEPS - 1)
	var split_step := _preview_split_step()
	var split_active := _preview_has_rgb_split()
	var key := "%d:%d:%d:%d" % [step, int(_dial_preview_source), int(_dial_preview_target), split_step]
	if key == _projector_key:
		return
	if step == 0 or (step == COOKIE_STEPS and not split_active):
		spot.light_projector = null
		_projector_key = key
		return
	if _projector_textures.has(key):
		spot.light_projector = _projector_textures[key]
		_projector_key = key
		return
	var visual_open := float(step) / float(COOKIE_STEPS)
	var split_fraction := float(split_step) / float(COOKIE_STEPS)
	var source_color := _mode_color(_dial_preview_source)
	var target_color := _mode_color(_dial_preview_target)
	var image := Image.create(COOKIE_SIZE, COOKIE_SIZE, false, Image.FORMAT_RGB8)
	for y: int in COOKIE_SIZE:
		var row := 1.0 - float(y) / float(COOKIE_SIZE - 1)
		var strip_position := fposmod(row * float(BLIND_COUNT), 1.0)
		var lit := step == COOKIE_STEPS or (strip_position > 0.14 and strip_position < 0.14 + 0.80 * visual_open)
		var intensity := 1.0 if lit else 0.0
		# A slight center falloff keeps the square projection from showing hard corners.
		for x: int in COOKIE_SIZE:
			var u := (float(x) + 0.5) / float(COOKIE_SIZE)
			var edge := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.86, 1.0, u))
			var projector_color := Color.WHITE
			if split_active:
				# A colored filter slides across the lens before the mode detent changes.
				var target_weight := smoothstep(1.0 - split_fraction - 0.07, 1.0 - split_fraction + 0.07, u)
				projector_color = source_color.lerp(target_color, target_weight)
			image.set_pixel(x, y, projector_color * (intensity * edge))
	if _projector_textures.size() >= 256:
		_projector_textures.clear()
	_projector_textures[key] = ImageTexture.create_from_image(image)
	spot.light_projector = _projector_textures[key]
	_projector_key = key

func _preview_split_step() -> int:
	return clampi(roundi(_dial_preview_amount * COOKIE_STEPS), 0, COOKIE_STEPS) if _dial_preview_active else 0

func _preview_has_rgb_split() -> bool:
	var step := _preview_split_step()
	return _dial_preview_active and _dial_preview_source != _dial_preview_target and step > 0 and step < COOKIE_STEPS

func _mode_color(filter_mode: LightField.Mode) -> Color:
	if filter_mode == LightField.Mode.BLUE:
		return Color("65c8ff")
	if filter_mode == LightField.Mode.ORANGE:
		return Color("ff9852")
	return Color("f8e5b2")

func set_mode(new_mode: LightField.Mode) -> void:
	_transition_phase = 0
	mode = new_mode
	_requested_mode = new_mode
	_apply_visual()
	changed.emit()

func begin_dial_preview() -> void:
	_dial_preview_active = true
	_dial_preview_amount = 0.0
	_settle_elapsed = 1.0
	set_dial_preview(_mode_dial_position(mode))

func _mode_dial_position(filter_mode: LightField.Mode) -> float:
	return -0.30 if filter_mode == LightField.Mode.BLUE else 0.30 if filter_mode == LightField.Mode.ORANGE else 0.0

func set_dial_preview(dial_position: float) -> void:
	_dial_preview = clampf(dial_position, -0.30, 0.30)
	if _dial_preview_active:
		# The dial slides through adjacent blue, clear, and orange filters.
		if _dial_preview <= 0.0:
			_dial_preview_source = LightField.Mode.BLUE
			_dial_preview_target = LightField.Mode.CLEAR
			_dial_preview_amount = (_dial_preview + 0.30) / 0.30
		else:
			_dial_preview_source = LightField.Mode.CLEAR
			_dial_preview_target = LightField.Mode.ORANGE
			_dial_preview_amount = _dial_preview / 0.30
	if _dial != null:
		_dial.rotation.z = -_dial_preview * 1.9
	if _dial_preview_active:
		_apply_visual()

func end_dial_preview() -> void:
	if not _dial_preview_active:
		return
	_settle_from_color = _mode_color(_dial_preview_source).lerp(_mode_color(_dial_preview_target), _dial_preview_amount)
	_settle_elapsed = 0.0
	_dial_preview_active = false
	_dial_preview_amount = 0.0
	# Return to the selected color when the adjusting hand releases.
	set_dial_preview(_mode_dial_position(mode))
	_apply_visual()

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
	var dt := clampf(delta, 0.0, 0.1)
	_flame_time += dt
	_settle_elapsed = minf(_settle_elapsed + dt / 0.18, 1.0)
	var wave := sin(_flame_time * 17.0) * 0.48 + sin(_flame_time * 29.0 + 1.7) * 0.32 + sin(_flame_time * 43.0 + 0.4) * 0.20
	_flame_gain = 1.0 + wave * 0.075
	spot.position = Vector3(
		0.014 * sin(_flame_time * 11.0) + 0.004 * sin(_flame_time * 23.0 + 0.7),
		0.011 * sin(_flame_time * 13.0 + 0.8),
		-0.145 * HOUSING_SCALE + 0.007 * sin(_flame_time * 9.0 + 1.2)
	)
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
		spot.spot_range = range_m
		_filter_material.albedo_color = color
		_filter_material.emission = color
		var active_glyph := 0 if mode == LightField.Mode.BLUE else 2 if mode == LightField.Mode.ORANGE else 1
		for i: int in _glyph_materials.size():
			_glyph_materials[i].emission_energy_multiplier = 1.8 if i == active_glyph else 0.045
		if not _dial_preview_active:
			set_dial_preview(_mode_dial_position(mode))
		_last_visual_mode = int(mode)
	var split_active := _preview_has_rgb_split()
	if split_active:
		spot.light_color = Color.WHITE
	elif _dial_preview_active:
		spot.light_color = _mode_color(_dial_preview_target if _dial_preview_amount >= 0.5 else _dial_preview_source)
	elif _settle_elapsed < 1.0:
		spot.light_color = _settle_from_color.lerp(color, smoothstep(0.0, 1.0, _settle_elapsed))
	else:
		spot.light_color = color
	spot.light_energy = base_energy * shutter_openness * _adaptation.lantern_gain() * _flame_gain
	if _last_visual_openness != shutter_openness:
		spot.visible = shutter_openness > 0.01
		_filter_material.emission_energy_multiplier = (1.5 + shutter_openness * 2.5) * shutter_openness * _flame_gain
		for i: int in BLIND_COUNT:
			var cell_height := 0.33 / float(BLIND_COUNT)
			var exposed := 0.80 * shutter_openness * cell_height
			_front_strips[i].scale.y = maxf((cell_height - exposed) / 0.01, 0.01)
			_front_strips[i].position.y = -0.165 + (float(i) + 0.5) * cell_height + exposed * 0.5
			_front_strips[i].visible = shutter_openness < 0.995
		for line: MeshInstance3D in _aperture_lines:
			line.scale.y = maxf(shutter_openness, 0.001)
			line.position.y = -0.090 + 0.05 * shutter_openness
		_last_visual_openness = shutter_openness
	else:
		_filter_material.emission_energy_multiplier = (1.5 + shutter_openness * 2.5) * shutter_openness * _flame_gain
	_update_cookie()

func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
