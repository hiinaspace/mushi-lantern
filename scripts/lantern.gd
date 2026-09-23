class_name Lantern
extends Node3D

signal changed

const FILTER_HALF_TIME := 0.12
const BEHAVIOR_HALF_ANGLE_DEGREES := 55.0
const BLIND_COUNT := 7
const COOKIE_SIZE := 64
const COOKIE_STEPS := 16
const HOUSING_SCALE := 0.7
const DIAL_RANGE_YAW := 0.55
const COLOR_SETTLE_TIME := 0.42

var mode: LightField.Mode = LightField.Mode.BLUE
var shutter_openness: float = 1.0
var _last_open: float = 1.0
var spot: SpotLight3D
var glow_mesh: MeshInstance3D
var filter_mesh: MeshInstance3D
var night_vision: float = 1.0
var _adaptation := NightAdaptation.new()
var _front_glow_material: ShaderMaterial
var _glyph_materials: Array[StandardMaterial3D] = []
var _side_glow_material: ShaderMaterial
var _visual_root: Node3D
var _dial_preview := 0.0
var _dial_preview_active := false
var _settling_split := false
var _dial_preview_amount := 0.0
var _dial_preview_source: LightField.Mode = LightField.Mode.BLUE
var _dial_preview_target: LightField.Mode = LightField.Mode.CLEAR
var _settle_elapsed := 1.0
var _settle_from_amount := 0.0
var _settle_to_amount := 0.0
var _settle_from_dial := 0.0
var _settle_to_dial := 0.0
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
	# The projector inscribes a square in this cone. Its horizontal edge still
	# reaches roughly the original 55-degree half angle used by the simulation.
	spot.spot_angle = 65.0
	spot.spot_angle_attenuation = 0.25
	spot.shadow_enabled = true
	spot.light_energy = 0.0
	spot.light_volumetric_fog_energy = 0.0
	add_child(spot)

	var metal := _material(Color("514751"), 0.0)
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

	# A quad gives the filter full 0..1 UVs; BoxMesh atlas UVs collapse the
	# moving color boundary into one side of its tiny front panel.
	filter_mesh = MeshInstance3D.new()
	filter_mesh.name = "FrontGlow"
	var front_quad := QuadMesh.new()
	front_quad.size = Vector2(0.29, 0.33)
	filter_mesh.mesh = front_quad
	filter_mesh.position.z = -0.128
	filter_mesh.rotation.y = PI
	filter_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(filter_mesh)
	_front_glow_material = _make_side_glow_material()
	filter_mesh.material_override = _front_glow_material
	glow_mesh = filter_mesh
	# The suspension is part of the lantern so it follows the pendulum joint.
	_box("Hanger", Vector3(0.013, 0.17, 0.013), Vector3(0.0, 0.29, 0.0), metal)
	_box("HangerLoop", Vector3(0.08, 0.015, 0.06), Vector3(0.0, 0.38, 0.0), metal)

	var rear_face := _material(Color("242630"), 0.0)
	var glyph_colors := [_mode_color(LightField.Mode.BLUE), _mode_color(LightField.Mode.CLEAR), _mode_color(LightField.Mode.ORANGE)]
	for i: int in 3:
		var glyph_material := _material(glyph_colors[i], 0.0)
		glyph_material.emission_enabled = true
		_glyph_materials.append(glyph_material)
	_side_glow_material = _make_side_glow_material()
	_add_glow_face("Rear", Vector3(0.0, 0.0, 0.126), 0.0, rear_face, Vector2(0.29, 0.33))
	_add_glow_face("Left", Vector3(-0.182, 0.0, 0.0), -PI * 0.5, rear_face, Vector2(0.20, 0.33))
	_add_glow_face("Right", Vector3(0.182, 0.0, 0.0), PI * 0.5, rear_face, Vector2(0.20, 0.33))
	# The front retains a very small mode tell even with the shutter fully closed.
	for i: int in 3:
		_box("FrontMode%d" % i, Vector3(0.019, 0.008, 0.005), Vector3((float(i) - 1.0) * 0.028, -0.192, -0.148), _glyph_materials[i])
	# The offhand catches this short pull below the smaller housing.
	_box("SettingCord", Vector3(0.008, 0.14, 0.008), Vector3(0.0, -0.205, 0.0), _material(Color("70839a"), 0.22), self)
	_box("SettingGrip", Vector3(0.042, 0.045, 0.027), Vector3(0.0, -0.29, 0.0), metal, self)
	_box("SettingGripGuide", Vector3(0.046, 0.008, 0.031), Vector3(0.0, -0.29, 0.0), _material(Color("b4d0e2"), 0.42), self)

func control_grip_local_position() -> Vector3:
	return Vector3(0.0, -0.29, 0.0)

func _add_glow_face(label: String, at: Vector3, yaw: float, panel: Material, window_size: Vector2) -> void:
	var face := Node3D.new()
	face.name = label + "Window"
	face.position = at
	face.rotation.y = yaw
	_visual_root.add_child(face)
	_box(label + "WindowBacking", Vector3(window_size.x + 0.015, window_size.y + 0.015, 0.004), Vector3.ZERO, panel, face)
	var window := MeshInstance3D.new()
	window.name = label + "Glow"
	var quad := QuadMesh.new()
	quad.size = window_size
	window.mesh = quad
	window.position.z = 0.004
	window.material_override = _side_glow_material
	window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.add_child(window)

func _make_side_glow_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 filter_source = vec3(0.263, 0.561, 0.910);
uniform vec3 filter_target = vec3(0.263, 0.561, 0.910);
uniform float source_chevron = -1.0;
uniform float target_chevron = -1.0;
uniform float split_fraction = 0.0;
uniform bool split_active = false;
uniform float shutter_open = 1.0;
uniform float glow_strength = 0.28;
void fragment() {
	float row = UV.y;
	float strip = fract(row * 7.0);
	float visible_open = max(shutter_open, 0.075);
	float lit = smoothstep(0.13, 0.16, strip) * (1.0 - smoothstep(0.14 + 0.80 * visible_open - 0.02, 0.14 + 0.80 * visible_open + 0.01, strip));
	if (shutter_open >= 0.995) { lit = 1.0; }
	float mix_amount = split_active ? smoothstep(1.0 - split_fraction - 0.018, 1.0 - split_fraction + 0.018, UV.x) : 0.0;
	vec3 color = mix(filter_source, filter_target, mix_amount);
	// The filter engraving follows each color across the sliding lens.
	float corner = 1.0 - 2.0 * abs(fract(UV.x * 3.0) - 0.5);
	float blue_phase = abs(fract((UV.y - corner * 0.11) * 4.0) - 0.5);
	float red_phase = abs(fract((UV.y + corner * 0.11) * 4.0) - 0.5);
	float blue_line = 1.0 - smoothstep(0.035, 0.12, blue_phase);
	float red_line = 1.0 - smoothstep(0.035, 0.12, red_phase);
	float source_line = source_chevron < -0.5 ? blue_line : source_chevron > 0.5 ? red_line : 0.0;
	float target_line = target_chevron < -0.5 ? blue_line : target_chevron > 0.5 ? red_line : 0.0;
	color *= 1.0 - 0.19 * mix(source_line, target_line, mix_amount);
	// Unshaded materials write their visible light through ALBEDO.
	ALBEDO = vec3(0.012, 0.012, 0.018) + color * lit * glow_strength;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

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
	var key := "%d:%d:%d:%d:%d" % [step, int(mode), int(_dial_preview_source), int(_dial_preview_target), split_step]
	if key == _projector_key:
		return
	if step == 0:
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
		# This inscribed square fades before the spotlight's round cone edge.
		# Full-open still needs this texture, but has no shutter stripes.
		for x: int in COOKIE_SIZE:
			var u := (float(x) + 0.5) / float(COOKIE_SIZE)
			var v := (float(y) + 0.5) / float(COOKIE_SIZE)
			var edge := smoothstep(0.145, 0.17, u) * (1.0 - smoothstep(0.83, 0.855, u))
			edge *= smoothstep(0.145, 0.17, v) * (1.0 - smoothstep(0.83, 0.855, v))
			var projector_color := Color.WHITE
			var source_pattern := _chevron_multiplier(u, row, _dial_preview_source if split_active else mode)
			if split_active:
				# A colored filter slides across the lens before the mode detent changes.
				var target_weight := smoothstep(1.0 - split_fraction - 0.018, 1.0 - split_fraction + 0.018, u)
				projector_color = source_color.lerp(target_color, target_weight)
				var target_pattern := _chevron_multiplier(u, row, _dial_preview_target)
				source_pattern = lerpf(source_pattern, target_pattern, target_weight)
			image.set_pixel(x, y, projector_color * (intensity * edge * source_pattern))
	# The finite shutter/preview quantization has fewer than 600 reachable
	# textures. Keep them for this lantern's lifetime: evicting a texture while
	# the spotlight still references it can invalidate Godot's projector atlas.
	_projector_textures[key] = ImageTexture.create_from_image(image)
	spot.light_projector = _projector_textures[key]
	_projector_key = key

func _preview_split_step() -> int:
	return clampi(roundi(_dial_preview_amount * COOKIE_STEPS), 0, COOKIE_STEPS) if _dial_preview_active or _settling_split else 0

func _preview_has_rgb_split() -> bool:
	var step := _preview_split_step()
	return (_dial_preview_active or _settling_split) and _dial_preview_source != _dial_preview_target and step > 0 and step < COOKIE_STEPS

func _chevron_multiplier(u: float, row: float, filter_mode: LightField.Mode) -> float:
	if filter_mode == LightField.Mode.CLEAR:
		return 1.0
	var corner := 1.0 - 2.0 * absf(fposmod(u * 3.0, 1.0) - 0.5)
	var bend := -0.11 if filter_mode == LightField.Mode.BLUE else 0.11
	var phase := absf(fposmod((row + corner * bend) * 4.0, 1.0) - 0.5)
	return 1.0 - 0.38 * (1.0 - smoothstep(0.035, 0.12, phase))

func _mode_color(filter_mode: LightField.Mode) -> Color:
	if filter_mode == LightField.Mode.BLUE:
		return Color("438fe8")
	if filter_mode == LightField.Mode.ORANGE:
		return Color("ed5d49")
	return Color("f8e5b2")

func set_mode(new_mode: LightField.Mode) -> void:
	_transition_phase = 0
	if not _dial_preview_active:
		_settling_split = false
		_settle_elapsed = 1.0
	mode = new_mode
	_requested_mode = new_mode
	_apply_visual()
	changed.emit()

func begin_dial_preview() -> void:
	_settling_split = false
	_dial_preview_active = true
	_dial_preview_amount = 0.0
	_settle_elapsed = 1.0
	set_dial_preview(_mode_dial_position(mode))

func _mode_dial_position(filter_mode: LightField.Mode) -> float:
	return -DIAL_RANGE_YAW if filter_mode == LightField.Mode.BLUE else DIAL_RANGE_YAW if filter_mode == LightField.Mode.ORANGE else 0.0

func set_dial_preview(dial_position: float) -> void:
	_dial_preview = clampf(dial_position, -DIAL_RANGE_YAW, DIAL_RANGE_YAW)
	if _dial_preview_active:
		# The dial slides through adjacent blue, clear, and orange filters.
		if _dial_preview <= 0.0:
			_dial_preview_source = LightField.Mode.BLUE
			_dial_preview_target = LightField.Mode.CLEAR
			_dial_preview_amount = (_dial_preview + DIAL_RANGE_YAW) / DIAL_RANGE_YAW
		else:
			_dial_preview_source = LightField.Mode.CLEAR
			_dial_preview_target = LightField.Mode.ORANGE
			_dial_preview_amount = _dial_preview / DIAL_RANGE_YAW
	if _dial_preview_active:
		_apply_visual()

func end_dial_preview() -> void:
	if not _dial_preview_active:
		return
	_settle_from_amount = _dial_preview_amount
	_settle_to_amount = 0.0 if mode == _dial_preview_source else 1.0
	_settle_from_dial = _dial_preview
	_settle_to_dial = _mode_dial_position(mode)
	_settle_elapsed = 0.0
	_dial_preview_active = false
	_settling_split = not is_equal_approx(_settle_from_amount, _settle_to_amount)
	if not _settling_split:
		set_dial_preview(_settle_to_dial)
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
	if _settling_split:
		_settle_elapsed = minf(_settle_elapsed + dt / COLOR_SETTLE_TIME, 1.0)
		var settle_weight := smoothstep(0.0, 1.0, _settle_elapsed)
		_dial_preview_amount = lerpf(_settle_from_amount, _settle_to_amount, settle_weight)
		_dial_preview = lerpf(_settle_from_dial, _settle_to_dial, settle_weight)
		if _settle_elapsed >= 1.0:
			_settling_split = false
			set_dial_preview(_settle_to_dial)
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
		color = _mode_color(mode)
		base_energy = 3.4
		range_m = 10.5
	elif mode == LightField.Mode.ORANGE:
		color = _mode_color(mode)
		base_energy = 3.8
		range_m = 10.5
	if _last_visual_mode != int(mode):
		spot.spot_range = range_m
		var active_glyph := 0 if mode == LightField.Mode.BLUE else 2 if mode == LightField.Mode.ORANGE else 1
		for i: int in _glyph_materials.size():
			_glyph_materials[i].emission_energy_multiplier = 1.8 if i == active_glyph else 0.045
		if not _dial_preview_active and not _settling_split:
			set_dial_preview(_mode_dial_position(mode))
		_last_visual_mode = int(mode)
	var split_active := _preview_has_rgb_split()
	if split_active:
		spot.light_color = Color.WHITE
	elif _dial_preview_active or _settling_split:
		spot.light_color = _mode_color(_dial_preview_target if _dial_preview_amount >= 0.5 else _dial_preview_source)
	else:
		spot.light_color = color
	spot.light_energy = base_energy * shutter_openness * _adaptation.lantern_gain() * _flame_gain
	for glow_material: ShaderMaterial in [_front_glow_material, _side_glow_material]:
		glow_material.set_shader_parameter("filter_source", _mode_color(_dial_preview_source) if split_active else spot.light_color)
		glow_material.set_shader_parameter("filter_target", _mode_color(_dial_preview_target))
		glow_material.set_shader_parameter("source_chevron", _chevron_direction(_dial_preview_source if split_active else mode))
		glow_material.set_shader_parameter("target_chevron", _chevron_direction(_dial_preview_target))
		glow_material.set_shader_parameter("split_fraction", float(_preview_split_step()) / float(COOKIE_STEPS))
		glow_material.set_shader_parameter("split_active", split_active)
		glow_material.set_shader_parameter("shutter_open", shutter_openness)
	_front_glow_material.set_shader_parameter("glow_strength", (1.5 + shutter_openness * 2.5) * maxf(shutter_openness, 0.12) * _flame_gain)
	_side_glow_material.set_shader_parameter("glow_strength", (0.12 + shutter_openness * 0.16) * _flame_gain)
	if _last_visual_openness != shutter_openness:
		spot.visible = shutter_openness > 0.01
		_last_visual_openness = shutter_openness
	_update_cookie()

func _chevron_direction(filter_mode: LightField.Mode) -> float:
	return -1.0 if filter_mode == LightField.Mode.BLUE else 1.0 if filter_mode == LightField.Mode.ORANGE else 0.0

func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
