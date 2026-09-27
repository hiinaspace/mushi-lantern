class_name StaffTool
extends XRToolsPickable

## World-space lantern tool. The shaft runs along local +Y; local -Z is the beam aim.
## Input drivers own only the held pose. This node owns every unheld pose.
enum Placement { HELD, FLOATING, SETTLING, PARKED, RECALL_HOVER }

const GRIP_Y := [-0.82, -0.62, -0.40, -0.18, 0.08, 0.43]
const MID_GRIP_INDEX := 3
const SHAFT_BOTTOM_Y := -1.02
const SHAFT_TOP_Y := 0.77
const GRIP_WRAP_RADIUS := 0.030
const FLOAT_TIME := 0.38
const PARK_HEIGHT := 1.04
const RECALL_SPEED := 8.0
const RECALL_OFFSET := Vector3(0.18, 0.18, -0.38)
const SHUTTER_HAND_TRAVEL_M := 0.08
const SHUTTER_DEAD_ZONE_M := 0.02
# The grip pose is forward of the wrist. Tracking this point removes most of
# the apparent vertical motion caused by tilting the controller in place.
const WRIST_BACK_OFFSET_M := 0.10
const FILTER_STEP_YAW := 0.55
const FILTER_ENTER_YAW := 0.30
const FILTER_EXIT_YAW := 0.25
const SUSPENSION_LENGTH := 0.39
const SUSPENSION_PIVOT_LOCAL := Vector3(0.0, 0.64, -0.36)
const SWING_GRAVITY := 7.6
const SWING_DRAG := 5.2
const SWING_ACCELERATION_FOLLOW := 0.55
const SWING_STEP := 1.0 / 120.0
const SWING_JUMP_DISTANCE := 0.55
const STAFF_GRAB_POINT = preload("res://scripts/staff_grab_point.gd")

var placement: Placement = Placement.HELD
var lantern: Lantern
var world_surface: Variant
var grip_index: int = MID_GRIP_INDEX
var _forced_grip_index := -1
var _swing: Node3D
var _bob_world := Vector3.ZERO
var _bob_velocity := Vector3.ZERO
var _previous_pivot := Vector3.ZERO
var _previous_pivot_velocity := Vector3.ZERO
var _swing_sim_pivot := Vector3.ZERO
var _desktop_yaw_reference := Transform3D.IDENTITY
var _previous_desktop_yaw_reference := Transform3D.IDENTITY
var _has_desktop_yaw_reference := false
var _xr_rig_reference := Transform3D.IDENTITY
var _previous_xr_rig_reference := Transform3D.IDENTITY
var _has_xr_rig_reference := false
var _float_elapsed := 0.0
var _float_origin := Transform3D.IDENTITY
var _park_target := Transform3D.IDENTITY
var _last_horizontal_aim := Vector3.FORWARD
var _flight_aim_active := false
var _flight_horizontal_aim := Vector3.FORWARD
var _recovering_flight_aim := false
var _adjusting := false
var _adjust_reference := Basis.IDENTITY
var _adjust_yaw_uses_right := false
var _adjust_origin_y := 0.0
var _adjust_open := 1.0
var _last_yaw_detent := 0
var _adjust_origin_dial := 0.0
var _adjust_last_dial := 0.0
var _desktop_adjusting := false
var _desktop_adjust_drag := Vector2.ZERO
var _desktop_adjust_open := 1.0
var _desktop_adjust_detent := 0
var _recall_hand := Transform3D.IDENTITY
var external_pose_owned := false
var _identity_hue: float = 0.0
var _identity_material: StandardMaterial3D
var _shaft_hint_material: StandardMaterial3D
var _control_hint_material: StandardMaterial3D

## Desktop lamp controls are available only while the desktop driver owns the
## held staff. A parked, recalling, or XR-owned staff cannot be adjusted via
## desktop keys or mouse input.
func desktop_can_control_lantern() -> bool:
	return placement == Placement.HELD and not external_pose_owned

## Captured desktop mouse travel acts like the offhand pulling the short
## setting grip. Releasing the button commits the nearest filter detent.
func begin_desktop_adjust() -> void:
	if not desktop_can_control_lantern():
		return
	_desktop_adjusting = true
	_desktop_adjust_drag = Vector2.ZERO
	_desktop_adjust_open = lantern.shutter_openness
	_desktop_adjust_detent = _mode_detent(lantern.mode)
	lantern.begin_dial_preview()
	lantern.set_dial_preview(float(_desktop_adjust_detent) * FILTER_STEP_YAW)

func update_desktop_adjust(relative: Vector2, allow_shutter: bool = true, allow_filter: bool = true) -> void:
	if not _desktop_adjusting or not desktop_can_control_lantern():
		return
	_desktop_adjust_drag += relative
	var vertical := _desktop_adjust_drag.y
	var travel := signf(vertical) * maxf(absf(vertical) - 6.0, 0.0)
	if allow_shutter:
		lantern.set_shutter(clampf(_desktop_adjust_open - travel / 150.0, 0.0, 1.0))
	# A deliberate sideways drag is needed before the filter dial moves. This
	# keeps small diagonal mouse drift from changing color while pulling rope.
	var horizontal := signf(_desktop_adjust_drag.x) * maxf(absf(_desktop_adjust_drag.x) - 32.0, 0.0)
	var dial := clampf(float(_desktop_adjust_detent) * FILTER_STEP_YAW + (horizontal if allow_filter else 0.0) * FILTER_STEP_YAW / 120.0,
		-FILTER_STEP_YAW, FILTER_STEP_YAW)
	lantern.set_dial_preview(dial)
	var detent := -1 if dial < -FILTER_ENTER_YAW else 1 if dial > FILTER_ENTER_YAW else 0
	if detent != _mode_detent(lantern.mode):
		lantern.set_mode(LightField.Mode.BLUE if detent < 0 else LightField.Mode.ORANGE if detent > 0 else LightField.Mode.CLEAR, true)

func end_desktop_adjust() -> void:
	if not _desktop_adjusting:
		return
	_desktop_adjusting = false
	lantern.end_dial_preview()

func desktop_is_adjusting() -> bool:
	return _desktop_adjusting

## During broom flight the beam follows the viewer's horizontal heading. A
## vertical gaze retains the previous heading, so looking up/down cannot turn
## the lantern through a projection singularity.
func set_flight_aim(active: bool, world_forward: Vector3) -> void:
	if active and not _flight_aim_active:
		_flight_horizontal_aim = _last_horizontal_aim
	if not active and _flight_aim_active:
		_recovering_flight_aim = true
	_flight_aim_active = active
	if active:
		_recovering_flight_aim = false
		var horizontal := Vector3(world_forward.x, 0.0, world_forward.z)
		if horizontal.is_finite() and horizontal.length_squared() > 0.0001:
			_flight_horizontal_aim = horizontal.normalized()

func _ready() -> void:
	freeze = true
	# XR Tools pickup probes layer 3 (bit 2) in the vendored rig.
	collision_layer = 4
	# Pickable caches its original layer before _ready and restores it on drop.
	original_collision_layer = 4
	picked_up_layer = 4
	release_mode = ReleaseMode.FROZEN
	# XR Tools blends the two grab point poses when both hands hold the shaft.
	second_hand_grab = SecondHandGrab.SECOND
	_build_grab_points()
	super._ready()
	set_process(false)
	_build_visual()
	_reset_swing()
	_capture_aim()

func pick_up(by: Node3D) -> void:
	super.pick_up(by)
	if not is_picked_up():
		return
	var point := get_active_grab_point()
	var index := MID_GRIP_INDEX
	if _forced_grip_index >= 0:
		index = clampi(_forced_grip_index, 0, GRIP_Y.size() - 1)
		for child: Node in get_children():
			if child is XRToolsGrabPointHand and absf((child as XRToolsGrabPointHand).position.y - GRIP_Y[index]) < 0.02:
				var grab_point := child as XRToolsGrabPointHand
				if grab_point.hand == (XRToolsGrabPointHand.Hand.LEFT if by.get_parent().name == "LeftController" else XRToolsGrabPointHand.Hand.RIGHT):
					switch_active_grab_point(grab_point)
					break
		_forced_grip_index = -1
		point = get_active_grab_point()
	if point != null:
		for candidate: int in GRIP_Y.size():
			if absf(point.position.y - GRIP_Y[candidate]) < 0.02:
				index = candidate
				break
	adopt_external_grab(index)

func force_next_grip(index: int) -> void:
	_forced_grip_index = clampi(index, 0, GRIP_Y.size() - 1) if index >= 0 else -1

func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.08
	shape.height = SHAFT_TOP_Y - SHAFT_BOTTOM_Y
	collider.shape = shape
	collider.position.y = (SHAFT_TOP_Y + SHAFT_BOTTOM_Y) * 0.5
	add_child(collider)
	var shaft := MeshInstance3D.new()
	shaft.name = "StaffShaft"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.019
	shaft_mesh.bottom_radius = 0.029
	shaft_mesh.height = SHAFT_TOP_Y - SHAFT_BOTTOM_Y
	shaft.mesh = shaft_mesh
	shaft.position.y = (SHAFT_TOP_Y + SHAFT_BOTTOM_Y) * 0.5
	shaft.material_override = _wood_material()
	add_child(shaft)
	# An emissive wrap stays visible from either side without adding a light.
	# Keep it between grip positions so hands do not conceal the owner cue.
	var identity_band := MeshInstance3D.new()
	identity_band.name = "IdentityStripe"
	var identity_mesh := CylinderMesh.new()
	identity_mesh.top_radius = 0.027
	identity_mesh.bottom_radius = 0.028
	identity_mesh.height = 0.10
	identity_mesh.radial_segments = 16
	identity_band.mesh = identity_mesh
	identity_band.position.y = 0.58
	identity_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_identity_material = _material(Color.WHITE, 0.7, 0.55)
	identity_band.material_override = _identity_material
	add_child(identity_band)
	set_identity_hue(_identity_hue)
	var wrap_material := _woven_grip_material()
	for y: float in GRIP_Y:
		var wrap := MeshInstance3D.new()
		var wrap_mesh := CylinderMesh.new()
		wrap_mesh.top_radius = GRIP_WRAP_RADIUS
		wrap_mesh.bottom_radius = GRIP_WRAP_RADIUS
		wrap_mesh.height = 0.13
		wrap.mesh = wrap_mesh
		wrap.position.y = y
		wrap.material_override = wrap_material
		add_child(wrap)
	var ferrule := MeshInstance3D.new()
	var ferrule_mesh := CylinderMesh.new()
	ferrule_mesh.top_radius = 0.045
	ferrule_mesh.bottom_radius = 0.045
	ferrule_mesh.height = 0.09
	ferrule.mesh = ferrule_mesh
	ferrule.position.y = SHAFT_BOTTOM_Y
	var dark_brass := _material(Color("88745c"), 0.39, 0.0)
	dark_brass.metallic = 0.72
	ferrule.material_override = dark_brass
	add_child(ferrule)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.014
	arm_mesh.bottom_radius = 0.014
	arm_mesh.height = 0.38
	arm.mesh = arm_mesh
	arm.rotation.x = -PI * 0.5
	arm.position = Vector3(0.0, 0.75, -0.17)
	arm.material_override = dark_brass
	add_child(arm)
	_swing = Node3D.new()
	_swing.name = "DampedLanternJoint"
	var crook_tip := MeshInstance3D.new()
	crook_tip.name = "CrookTip"
	var crook_mesh := CylinderMesh.new()
	crook_mesh.top_radius = 0.013
	crook_mesh.bottom_radius = 0.014
	crook_mesh.height = 0.11
	crook_tip.mesh = crook_mesh
	crook_tip.position = Vector3(0.0, 0.69, -0.36)
	crook_tip.material_override = dark_brass
	add_child(crook_tip)
	_swing.position = SUSPENSION_PIVOT_LOCAL
	add_child(_swing)
	var suspension := MeshInstance3D.new()
	suspension.name = "SuspensionCord"
	var cord_mesh := CylinderMesh.new()
	cord_mesh.top_radius = 0.005
	cord_mesh.bottom_radius = 0.005
	cord_mesh.height = 0.13
	suspension.mesh = cord_mesh
	suspension.position.y = -0.065
	suspension.material_override = dark_brass
	suspension.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swing.add_child(suspension)
	lantern = Lantern.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0.0, -SUSPENSION_LENGTH, 0.0)
	_swing.add_child(lantern)
	# Hover feedback is a small lit dash at the grip and a pinpoint at the
	# lantern control, rather than XR Tools' large billboard ring.
	var shaft_hint := MeshInstance3D.new()
	shaft_hint.name = "ShaftGripPulse"
	var shaft_hint_mesh := CylinderMesh.new()
	shaft_hint_mesh.top_radius = 0.011
	shaft_hint_mesh.bottom_radius = 0.011
	shaft_hint_mesh.height = 0.07
	shaft_hint.mesh = shaft_hint_mesh
	shaft_hint.position.y = GRIP_Y[MID_GRIP_INDEX]
	_shaft_hint_material = _make_hint_material()
	shaft_hint.material_override = _shaft_hint_material
	shaft_hint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft_hint)
	var control_hint := MeshInstance3D.new()
	control_hint.name = "ControlGripPulse"
	var control_hint_mesh := SphereMesh.new()
	control_hint_mesh.radius = 0.018
	control_hint_mesh.height = 0.036
	control_hint.mesh = control_hint_mesh
	control_hint.position = lantern.position + lantern.control_grip_local_position()
	_control_hint_material = _make_hint_material()
	control_hint.material_override = _control_hint_material
	control_hint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swing.add_child(control_hint)

func _make_hint_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.78, 0.38, 0.0)
	mat.emission_enabled = true
	mat.emission = Color("ffd083")
	mat.emission_energy_multiplier = 0.0
	return mat

func set_interaction_hint(shaft_strength: float, control_strength: float) -> void:
	if _shaft_hint_material != null:
		_set_hint_strength(_shaft_hint_material, shaft_strength)
	if _control_hint_material != null:
		_set_hint_strength(_control_hint_material, control_strength)

func _set_hint_strength(mat: StandardMaterial3D, strength: float) -> void:
	var value := clampf(strength, 0.0, 1.0)
	var color := Color(1.0, 0.78, 0.38, value * 0.72)
	mat.albedo_color = color
	mat.emission_energy_multiplier = value * 1.15

func _build_grab_points() -> void:
	for hand_side: int in 2:
		for point_index: int in GRIP_Y.size():
			var point := STAFF_GRAB_POINT.new() as XRToolsGrabPointHand
			point.name = ("Left" if hand_side == 0 else "Right") + "ShaftGrip%d" % point_index
			point.hand = XRToolsGrabPointHand.Hand.LEFT if hand_side == 0 else XRToolsGrabPointHand.Hand.RIGHT
			point.mode = XRToolsGrabPointHand.Mode.GENERAL
			point.snap_hand = true
			point.position = Vector3(0.0, GRIP_Y[point_index], 0.0)
			add_child(point)

func _material(color: Color, roughness: float, emission: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

func _wood_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
void fragment() {
	float grain = sin(UV.x * 74.0 + sin(UV.y * 17.0) * 1.2 + sin(UV.x * 13.0 + UV.y * 31.0));
	float fine = sin(UV.x * 173.0 + UV.y * 8.0);
	float stain = 0.83 + 0.11 * grain + 0.035 * fine;
	ALBEDO = vec3(0.31, 0.21, 0.12) * stain;
	ROUGHNESS = 0.79;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _woven_grip_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
void fragment() {
	float strand = abs(fract(UV.x * 18.0 + UV.y * 5.0) - 0.5);
	float crossing = abs(fract(UV.x * 18.0 - UV.y * 5.0) - 0.5);
	float weave = smoothstep(0.36, 0.49, min(strand, crossing));
	ALBEDO = mix(vec3(0.31, 0.19, 0.105), vec3(0.49, 0.35, 0.21), weave);
	ROUGHNESS = 0.91;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func set_identity_hue(hue_turns: float) -> void:
	# Ukon's authored garment is red; its network color rotates that hue.
	# Cache before _ready as well, for remote staff created after avatar packets.
	_identity_hue = fposmod(hue_turns, 1.0)
	if _identity_material != null:
		var color := Color.from_hsv(_identity_hue, 0.78, 0.85)
		_identity_material.albedo_color = color
		_identity_material.emission = color


func set_world_surface(surface: Variant) -> void:
	world_surface = surface

func grip_world_position(index: int) -> Vector3:
	return to_global(Vector3(0.0, GRIP_Y[clampi(index, 0, GRIP_Y.size() - 1)], 0.0))

func control_world_position() -> Vector3:
	return lantern.to_global(lantern.control_grip_local_position())

func hold(hand_world: Transform3D, index: int = MID_GRIP_INDEX) -> void:
	if not _valid_transform(hand_world):
		return
	grip_index = clampi(index, 0, GRIP_Y.size() - 1)
	placement = Placement.HELD
	external_pose_owned = false
	var basis := hand_world.basis.orthonormalized()
	global_transform = Transform3D(basis, hand_world.origin - basis * Vector3(0.0, GRIP_Y[grip_index], 0.0))
	_rebase_swing_if_jump()
	_capture_aim()

func set_held_world_pose(staff_world: Transform3D) -> void:
	if not _valid_transform(staff_world):
		return
	placement = Placement.HELD
	external_pose_owned = false
	global_transform = Transform3D(staff_world.basis.orthonormalized(), staff_world.origin)
	_rebase_swing_if_jump()
	_capture_aim()

## Desktop mouselook rotates the held staff around the camera, which moves its
## suspension point along an arc despite the player standing still. Supply the
## camera transform each frame so that arc does not become a pendulum impulse.
## XR hand poses do not use this compensation.
func set_desktop_yaw_reference(camera_world: Transform3D) -> void:
	if not _valid_transform(camera_world):
		return
	_desktop_yaw_reference = camera_world
	if not _has_desktop_yaw_reference:
		_previous_desktop_yaw_reference = camera_world
		_has_desktop_yaw_reference = true

func clear_desktop_yaw_reference() -> void:
	if not _has_desktop_yaw_reference:
		return
	_has_desktop_yaw_reference = false
	_swing_sim_pivot = _swing.global_position
	_previous_pivot = _swing_sim_pivot
	_previous_pivot_velocity = Vector3.ZERO

## Optional explicit rig reference for deterministic fixtures and alternate grab drivers.
## During an XR Tools grab this is read from the owning controller's XROrigin3D.
func set_xr_rig_reference(rig_world: Transform3D) -> void:
	if not _valid_transform(rig_world):
		return
	_xr_rig_reference = rig_world
	if not _has_xr_rig_reference:
		_previous_xr_rig_reference = rig_world
		_has_xr_rig_reference = true

func transfer(hand_world: Transform3D, index: int = MID_GRIP_INDEX) -> void:
	# A hand swap is atomic. It never passes through gameplay release.
	hold(hand_world, index)

func adopt_external_grab(index: int = MID_GRIP_INDEX) -> void:
	grip_index = clampi(index, 0, GRIP_Y.size() - 1)
	placement = Placement.HELD
	external_pose_owned = true
	_rebase_swing_if_jump()

func release_external_grab(intentional_final: bool) -> void:
	if not external_pose_owned:
		return
	external_pose_owned = false
	if intentional_final:
		release_final()
	else:
		tracking_lost()

func tracking_lost() -> void:
	# Freeze in place until tracking returns or the player explicitly releases.
	_bob_velocity = Vector3.ZERO
	_previous_pivot = _swing.global_position
	if is_instance_valid(_grab_driver):
		_grab_driver.set_physics_process(false)

func tracking_restored() -> void:
	_previous_pivot = _swing.global_position
	_bob_velocity = Vector3.ZERO
	if is_instance_valid(_grab_driver):
		_grab_driver.set_physics_process(true)

func release_final() -> void:
	if placement != Placement.HELD:
		return
	_adjusting = false
	external_pose_owned = false
	lantern.end_dial_preview()
	_capture_aim()
	_float_origin = global_transform
	_float_elapsed = 0.0
	placement = Placement.FLOATING
	_choose_park_target()

func begin_recall(hand_world: Transform3D) -> void:
	if placement == Placement.HELD or not _valid_transform(hand_world):
		return
	_recall_hand = hand_world
	placement = Placement.RECALL_HOVER

func update_recall(hand_world: Transform3D, delta: float) -> void:
	if placement != Placement.RECALL_HOVER or not _valid_transform(hand_world):
		return
	_recall_hand = hand_world
	var target := _recall_hover_pose()
	var weight := 1.0 - exp(-RECALL_SPEED * clampf(delta, 0.0, 0.1))
	global_transform = global_transform.interpolate_with(target, weight)
	_rebase_swing_if_jump()

func end_recall() -> void:
	if placement != Placement.RECALL_HOVER:
		return
	_float_origin = global_transform
	_float_elapsed = 0.0
	_capture_aim()
	_choose_park_target()
	placement = Placement.FLOATING

func begin_adjust(hand_world: Transform3D) -> void:
	if not _valid_transform(hand_world):
		return
	_adjusting = true
	var hand_local := _adjust_frame().affine_inverse() * hand_world
	_adjust_reference = hand_local.basis.orthonormalized()
	# Use the controller axis with the more stable horizontal projection.
	_adjust_yaw_uses_right = absf(_adjust_reference.z.y) > 0.8
	_adjust_origin_y = _adjust_wrist_height(hand_local)
	_adjust_open = lantern.shutter_openness
	_last_yaw_detent = _mode_detent(lantern.mode)
	_adjust_origin_dial = float(_last_yaw_detent) * FILTER_STEP_YAW
	_adjust_last_dial = _adjust_origin_dial
	_bob_velocity = Vector3.ZERO
	_previous_pivot = _swing.global_position
	lantern.begin_dial_preview()
	lantern.set_dial_preview(_adjust_origin_dial)

func update_adjust(hand_world: Transform3D) -> void:
	if not _adjusting or not _valid_transform(hand_world):
		return
	var hand_local := _adjust_frame().affine_inverse() * hand_world
	var current_basis := hand_local.basis.orthonormalized()
	# The level lantern frame follows the tool through stick locomotion and turning.
	# Horizontal yaw remains separate from vertical hand travel in a rolled grip.
	var reference_axis := _adjust_reference.x if _adjust_yaw_uses_right else -_adjust_reference.z
	var current_axis := current_basis.x if _adjust_yaw_uses_right else -current_basis.z
	reference_axis.y = 0.0
	current_axis.y = 0.0
	# Raise/lower the adjusting hand for aperture; horizontal controller yaw selects a filter.
	var height_delta := _adjust_wrist_height(hand_local) - _adjust_origin_y
	var shutter_motion := signf(height_delta) * maxf(absf(height_delta) - SHUTTER_DEAD_ZONE_M, 0.0)
	lantern.set_shutter(clampf(_adjust_open + shutter_motion / SHUTTER_HAND_TRAVEL_M, 0.0, 1.0))
	if reference_axis.length_squared() > 0.04 and current_axis.length_squared() > 0.04:
		reference_axis = reference_axis.normalized()
		current_axis = current_axis.normalized()
		var yaw := atan2(-reference_axis.cross(current_axis).y, reference_axis.dot(current_axis))
		_adjust_last_dial = clampf(_adjust_origin_dial + yaw, -FILTER_STEP_YAW, FILTER_STEP_YAW)
		lantern.set_dial_preview(_adjust_last_dial)
		var detent := _last_yaw_detent
		if _adjust_last_dial < (-FILTER_ENTER_YAW if detent == 0 else -FILTER_EXIT_YAW):
			detent = -1
		elif _adjust_last_dial > (FILTER_ENTER_YAW if detent == 0 else FILTER_EXIT_YAW):
			detent = 1
		elif absf(_adjust_last_dial) < FILTER_EXIT_YAW:
			detent = 0
		if detent != _last_yaw_detent:
			_last_yaw_detent = detent
			lantern.set_mode(LightField.Mode.CLEAR if detent == 0 else LightField.Mode.BLUE if detent < 0 else LightField.Mode.ORANGE, true)

func end_adjust() -> void:
	if _adjusting:
		var final_detent := -1 if _adjust_last_dial < -FILTER_STEP_YAW * 0.5 else 1 if _adjust_last_dial > FILTER_STEP_YAW * 0.5 else 0
		lantern.set_mode(LightField.Mode.CLEAR if final_detent == 0 else LightField.Mode.BLUE if final_detent < 0 else LightField.Mode.ORANGE, true)
	_adjusting = false
	lantern.end_dial_preview()
	_previous_pivot = _swing.global_position
	_bob_velocity = Vector3.ZERO

func _mode_detent(value: LightField.Mode) -> int:
	return -1 if value == LightField.Mode.BLUE else 1 if value == LightField.Mode.ORANGE else 0

func _adjust_wrist_height(hand_world: Transform3D) -> float:
	return (hand_world.origin + hand_world.basis.orthonormalized() * Vector3(0.0, 0.0, WRIST_BACK_OFFSET_M)).y

func _adjust_frame() -> Transform3D:
	# Use the shaft yaw so pendulum motion cannot turn the dial reference.
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = _last_horizontal_aim
	forward = forward.normalized()
	var z_axis := -forward
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	return Transform3D(Basis(x_axis, Vector3.UP, z_axis), control_world_position())

func reset_to_pose(staff_world: Transform3D, shutter: float = 1.0, held: bool = true) -> void:
	if not _valid_transform(staff_world):
		return
	global_transform = Transform3D(staff_world.basis.orthonormalized(), staff_world.origin)
	placement = Placement.HELD if held else Placement.PARKED
	external_pose_owned = false
	_flight_aim_active = false
	_recovering_flight_aim = false
	_has_xr_rig_reference = false
	_adjusting = false
	lantern.end_dial_preview()
	_float_elapsed = 0.0
	_reset_swing()
	lantern.set_shutter(shutter)
	_capture_aim()
	_park_target = global_transform

func advance(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	if placement == Placement.FLOATING:
		_float_elapsed += dt
		var rise := minf(_float_elapsed / FLOAT_TIME, 1.0)
		var pos := _float_origin.origin + Vector3.UP * (0.18 * sin(rise * PI))
		global_transform = Transform3D(_float_origin.basis, pos)
		if rise >= 1.0 and _park_target != Transform3D.IDENTITY:
			placement = Placement.SETTLING
	elif placement == Placement.SETTLING:
		var weight := 1.0 - exp(-4.6 * dt)
		global_transform = global_transform.interpolate_with(_park_target, weight)
		if global_position.distance_to(_park_target.origin) < 0.018:
			global_transform = _park_target
			placement = Placement.PARKED
	_update_swing(dt)
	lantern.advance_flame(dt)
	lantern.advance_transition(dt)

func _choose_park_target() -> void:
	_park_target = Transform3D.IDENTITY
	var xz := Vector2(global_position.x, global_position.z)
	var offsets := [Vector2.ZERO, Vector2(0.7, 0.0), Vector2(-0.7, 0.0), Vector2(0.0, 0.7), Vector2(0.0, -0.7), Vector2(1.3, 0.0), Vector2(-1.3, 0.0)]
	for offset: Vector2 in offsets:
		var point: Vector2 = xz + offset
		if not _safe_ground(point):
			continue
		var height := _ground_height(point)
		var forward := _last_horizontal_aim
		var basis := Basis.looking_at(forward, Vector3.UP)
		_park_target = Transform3D(basis, Vector3(point.x, height + PARK_HEIGHT, point.y))
		return

func _safe_ground(point: Vector2) -> bool:
	if world_surface == null:
		return true
	if not bool(world_surface.is_playable(point, 1.3)):
		return false
	var h := _ground_height(point)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if absf(_ground_height(point + direction * 0.5) - h) > 0.24:
			return false
	for obstacle: Dictionary in world_surface.get_obstacles():
		if point.distance_to(obstacle.center) < float(obstacle.radius) + 0.5:
			return false
	return true

func _ground_height(point: Vector2) -> float:
	return float(world_surface.get_height_at(point)) if world_surface != null else 0.0

func _recall_hover_pose() -> Transform3D:
	var basis := _recall_hand.basis.orthonormalized()
	return Transform3D(basis, _recall_hand.origin + basis * RECALL_OFFSET)

func _capture_aim() -> void:
	var forward := lantern.forward_direction() if lantern != null else -global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		_last_horizontal_aim = forward.normalized()

func _rebase_swing_if_jump() -> void:
	if _swing_motion_since_previous_pivot().length() > SWING_JUMP_DISTANCE:
		_reset_swing()

func _reset_swing() -> void:
	_previous_pivot = _swing.global_position
	_swing_sim_pivot = _previous_pivot
	_previous_pivot_velocity = Vector3.ZERO
	_bob_world = _previous_pivot + Vector3.DOWN * SUSPENSION_LENGTH
	_bob_velocity = Vector3.ZERO
	_orient_swing(_previous_pivot)

func _update_swing(dt: float) -> void:
	if dt <= 0.0:
		return
	_update_xr_rig_reference()
	var pivot := _swing.global_position
	if _swing_motion_since_previous_pivot().length() > SWING_JUMP_DISTANCE:
		_reset_swing()
		return
	var simulation_pivot := pivot
	if _has_xr_rig_reference:
		# XROrigin locomotion moves the tracked controller and staff together. Remove
		# only that shared rigid transform so controller motion within the rig still
		# swings the lantern, including deliberate hand waving.
		var rig_motion := _xr_rig_arc(_previous_pivot, _previous_xr_rig_reference, _xr_rig_reference)
		simulation_pivot = _swing_sim_pivot + (pivot - _previous_pivot) - rig_motion
	if _has_desktop_yaw_reference:
		var yaw_arc := _desktop_yaw_arc(_previous_pivot, _previous_desktop_yaw_reference, _desktop_yaw_reference)
		# Subtract only camera-yaw orbital motion. Camera translation and
		# movement of the held aim offset still reach the swing simulation.
		simulation_pivot = _swing_sim_pivot + (pivot - _previous_pivot) - yaw_arc
	var render_offset := pivot - simulation_pivot
	var simulation_bob := _bob_world - (_previous_pivot - _swing_sim_pivot)
	if _adjusting:
		simulation_bob += simulation_pivot - _swing_sim_pivot
		_bob_velocity = Vector3.ZERO
		_previous_pivot_velocity = Vector3.ZERO
	else:
		var steps := maxi(1, ceili(dt / SWING_STEP))
		var step_dt := dt / float(steps)
		var pivot_velocity := (simulation_pivot - _swing_sim_pivot) / dt
		if placement == Placement.HELD:
			# Carry some of the grip's acceleration into the bob. This softens
			# abrupt WASD starts/stops without any steady-speed displacement.
			_bob_velocity += (pivot_velocity - _previous_pivot_velocity) * SWING_ACCELERATION_FOLLOW
			_previous_pivot_velocity = pivot_velocity
		else:
			_previous_pivot_velocity = Vector3.ZERO
		for step: int in steps:
			var step_pivot := _swing_sim_pivot + (simulation_pivot - _swing_sim_pivot) * (float(step + 1) / float(steps))
			var old_bob := simulation_bob
			# Damping acts on motion relative to the grip. Damping world velocity
			# held the lantern sideways indefinitely at constant walking speed.
			var relative_velocity := _bob_velocity - pivot_velocity
			relative_velocity += Vector3.DOWN * SWING_GRAVITY * step_dt
			relative_velocity *= exp(-SWING_DRAG * step_dt)
			var unconstrained := simulation_bob + (pivot_velocity + relative_velocity) * step_dt
			var direction := unconstrained - step_pivot
			if direction.length_squared() < 0.000001:
				direction = Vector3.DOWN
			direction = direction.normalized()
			simulation_bob = step_pivot + direction * SUSPENSION_LENGTH
			_bob_velocity = (simulation_bob - old_bob) / step_dt
			# The string removes radial velocity relative to its moving pivot.
			_bob_velocity -= direction * (_bob_velocity - pivot_velocity).dot(direction)
	_bob_world = simulation_bob + render_offset
	_previous_pivot = pivot
	_swing_sim_pivot = simulation_pivot
	if _has_desktop_yaw_reference:
		_previous_desktop_yaw_reference = _desktop_yaw_reference
	if _has_xr_rig_reference:
		_previous_xr_rig_reference = _xr_rig_reference
	_orient_swing(pivot, dt)

func _update_xr_rig_reference() -> void:
	if not external_pose_owned or not is_instance_valid(_grab_driver) or not is_instance_valid(_grab_driver.primary):
		return
	var controller: XRController3D = _grab_driver.primary.controller
	if controller == null:
		return
	var rig := controller.get_parent() as Node3D
	if rig == null:
		return
	set_xr_rig_reference(rig.global_transform)

func _swing_motion_since_previous_pivot() -> Vector3:
	var motion := _swing.global_position - _previous_pivot
	if _has_desktop_yaw_reference:
		motion -= _desktop_yaw_arc(_previous_pivot, _previous_desktop_yaw_reference, _desktop_yaw_reference)
	if _has_xr_rig_reference:
		motion -= _xr_rig_arc(_previous_pivot, _previous_xr_rig_reference, _xr_rig_reference)
	return motion

func _xr_rig_arc(previous_pivot: Vector3, previous_rig: Transform3D, current_rig: Transform3D) -> Vector3:
	return (current_rig * previous_rig.affine_inverse() * previous_pivot) - previous_pivot

func _desktop_yaw_arc(previous_pivot: Vector3, previous_camera: Transform3D, current_camera: Transform3D) -> Vector3:
	var previous_forward := -previous_camera.basis.z
	var current_forward := -current_camera.basis.z
	previous_forward.y = 0.0
	current_forward.y = 0.0
	if previous_forward.length_squared() <= 0.001 or current_forward.length_squared() <= 0.001:
		return Vector3.ZERO
	previous_forward = previous_forward.normalized()
	current_forward = current_forward.normalized()
	var yaw_delta := atan2(previous_forward.cross(current_forward).y, previous_forward.dot(current_forward))
	var previous_relative := previous_pivot - previous_camera.origin
	return Basis(Vector3.UP, yaw_delta) * previous_relative - previous_relative

func _orient_swing(pivot: Vector3, dt: float = 0.0) -> void:
	var down := (_bob_world - pivot).normalized()
	if down.length_squared() < 0.5:
		down = Vector3.DOWN
	var physical_up := -down
	# Aim follows the staff's actual front, independent of the shaft's +Y
	# direction. The shaft axis is ambiguous under a two-hand grip and can
	# reverse when XR Tools changes its grab solution. Near vertical front
	# poses retain the last heading; any genuine reversal is rate-limited.
	if _flight_aim_active:
		_last_horizontal_aim = _flight_horizontal_aim
	else:
		var staff_forward := -global_basis.z
		staff_forward.y = 0.0
		if staff_forward.length_squared() > 0.04:
			var desired := staff_forward.normalized()
			var angle := atan2(_last_horizontal_aim.cross(desired).y, _last_horizontal_aim.dot(desired))
			if dt > 0.0 and (_recovering_flight_aim or absf(angle) > 0.9):
				var turn_speed := 3.5 if _recovering_flight_aim else 12.0
				var turn := clampf(angle, -turn_speed * dt, turn_speed * dt)
				_last_horizontal_aim = Basis(Vector3.UP, turn) * _last_horizontal_aim
			else:
				_last_horizontal_aim = desired
	var forward := _last_horizontal_aim
	var up := physical_up
	if _flight_aim_active:
		# A pendulum can momentarily point along the beam. Preserve its tilt
		# where possible, but keep the beam fixed on the horizontal flight aim.
		# World up is a non-singular fallback for this horizontal forward vector.
		up = physical_up - forward * physical_up.dot(forward)
		var upright_blend := 1.0 - smoothstep(0.15, 0.45, up.dot(Vector3.UP))
		up = up.lerp(Vector3.UP, upright_blend)
	elif _recovering_flight_aim and dt > 0.0:
		up = _swing.global_basis.y.slerp(physical_up, 1.0 - exp(-6.0 * dt))
	if _flight_aim_active:
		up -= forward * up.dot(forward)
		if up.length_squared() < 0.0001:
			up = Vector3.UP
		up = up.normalized()
	else:
		up = up.normalized()
		forward -= up * forward.dot(up)
		if forward.length_squared() < 0.0001:
			forward = _swing.global_basis.z * -1.0
			forward -= up * forward.dot(up)
		if forward.length_squared() < 0.0001:
			forward = Vector3.UP.cross(up)
		forward = forward.normalized()
	var z_axis := -forward
	var x_axis := up.cross(z_axis).normalized()
	_swing.global_transform = Transform3D(Basis(x_axis, up, z_axis), pivot)
	if _recovering_flight_aim and up.dot(physical_up) > 0.999:
		var staff_horizontal := -global_basis.z
		staff_horizontal.y = 0.0
		if staff_horizontal.length_squared() > 0.04 and _last_horizontal_aim.dot(staff_horizontal.normalized()) > 0.999:
			_recovering_flight_aim = false

func _valid_transform(value: Transform3D) -> bool:
	return is_finite(value.origin.x) and is_finite(value.origin.y) and is_finite(value.origin.z) and is_finite(value.basis.determinant()) and absf(value.basis.determinant()) > 0.01
