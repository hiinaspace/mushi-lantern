class_name StaffTool
extends XRToolsPickable

## World-space lantern tool. The shaft runs along local +Y; local -Z is the beam aim.
## Input drivers own only the held pose. This node owns every unheld pose.
enum Placement { HELD, FLOATING, SETTLING, PARKED, RECALL_HOVER }

const GRIP_Y := [-0.82, -0.62, -0.40, -0.18, 0.08, 0.43]
const MID_GRIP_INDEX := 3
const SHAFT_BOTTOM_Y := -1.02
const SHAFT_TOP_Y := 0.77
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
const SWING_GRAVITY := 9.81
const SWING_DRAG := 2.6
const SWING_STEP := 1.0 / 120.0
const SWING_JUMP_DISTANCE := 0.55
const XR_LOCOMOTION_FOLLOW := 0.45

var placement: Placement = Placement.HELD
var lantern: Lantern
var world_surface: Variant
var grip_index: int = MID_GRIP_INDEX
var _forced_grip_index := -1
var _swing: Node3D
var _bob_world := Vector3.ZERO
var _bob_velocity := Vector3.ZERO
var _previous_pivot := Vector3.ZERO
var _float_elapsed := 0.0
var _float_origin := Transform3D.IDENTITY
var _park_target := Transform3D.IDENTITY
var _last_horizontal_aim := Vector3.FORWARD
var _adjusting := false
var _adjust_reference := Basis.IDENTITY
var _adjust_yaw_uses_right := false
var _adjust_origin_y := 0.0
var _adjust_open := 1.0
var _last_yaw_detent := 0
var _adjust_origin_dial := 0.0
var _adjust_last_dial := 0.0
var _recall_hand := Transform3D.IDENTITY
var external_pose_owned := false

func _ready() -> void:
	freeze = true
	# XR Tools pickup probes layer 3 (bit 2) in the vendored rig.
	collision_layer = 4
	# Pickable caches its original layer before _ready and restores it on drop.
	original_collision_layer = 4
	picked_up_layer = 4
	release_mode = ReleaseMode.FROZEN
	second_hand_grab = SecondHandGrab.SWAP
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
	shaft_mesh.top_radius = 0.022
	shaft_mesh.bottom_radius = 0.037
	shaft_mesh.height = SHAFT_TOP_Y - SHAFT_BOTTOM_Y
	shaft.mesh = shaft_mesh
	shaft.position.y = (SHAFT_TOP_Y + SHAFT_BOTTOM_Y) * 0.5
	shaft.material_override = _material(Color("51402b"), 0.75, 0.15)
	add_child(shaft)
	for y: float in GRIP_Y:
		var wrap := MeshInstance3D.new()
		var wrap_mesh := CylinderMesh.new()
		wrap_mesh.top_radius = 0.037
		wrap_mesh.bottom_radius = 0.037
		wrap_mesh.height = 0.13
		wrap.mesh = wrap_mesh
		wrap.position.y = y
		wrap.material_override = _material(Color("9d7953"), 0.8, 0.08)
		add_child(wrap)
	var ferrule := MeshInstance3D.new()
	var ferrule_mesh := CylinderMesh.new()
	ferrule_mesh.top_radius = 0.045
	ferrule_mesh.bottom_radius = 0.045
	ferrule_mesh.height = 0.09
	ferrule.mesh = ferrule_mesh
	ferrule.position.y = SHAFT_BOTTOM_Y
	ferrule.material_override = _material(Color("857f69"), 0.48, 0.0)
	add_child(ferrule)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.014
	arm_mesh.bottom_radius = 0.014
	arm_mesh.height = 0.38
	arm.mesh = arm_mesh
	arm.rotation.x = -PI * 0.5
	arm.position = Vector3(0.0, 0.75, -0.17)
	arm.material_override = _material(Color("857f69"), 0.48, 0.0)
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
	crook_tip.material_override = _material(Color("857f69"), 0.48, 0.10)
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
	suspension.material_override = _material(Color("857f69"), 0.55, 0.08)
	suspension.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swing.add_child(suspension)
	lantern = Lantern.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0.0, -SUSPENSION_LENGTH, 0.0)
	_swing.add_child(lantern)

func _build_grab_points() -> void:
	for hand_side: int in 2:
		for point_index: int in GRIP_Y.size():
			var point := XRToolsGrabPointHand.new()
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
			lantern.set_mode(LightField.Mode.CLEAR if detent == 0 else LightField.Mode.BLUE if detent < 0 else LightField.Mode.ORANGE)

func end_adjust() -> void:
	if _adjusting:
		var final_detent := -1 if _adjust_last_dial < -FILTER_STEP_YAW * 0.5 else 1 if _adjust_last_dial > FILTER_STEP_YAW * 0.5 else 0
		lantern.set_mode(LightField.Mode.CLEAR if final_detent == 0 else LightField.Mode.BLUE if final_detent < 0 else LightField.Mode.ORANGE)
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
	_adjusting = false
	lantern.end_dial_preview()
	_float_elapsed = 0.0
	_reset_swing()
	lantern.set_shutter(shutter)
	_capture_aim()
	_park_target = global_transform

func advance(delta: float, xr_locomotion_delta: Vector3 = Vector3.ZERO) -> void:
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
	_update_swing(dt, xr_locomotion_delta)
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
	if _swing.global_position.distance_to(_previous_pivot) > SWING_JUMP_DISTANCE:
		_reset_swing()

func _reset_swing() -> void:
	_previous_pivot = _swing.global_position
	_bob_world = _previous_pivot + Vector3.DOWN * SUSPENSION_LENGTH
	_bob_velocity = Vector3.ZERO
	_orient_swing(_previous_pivot)

func _update_swing(dt: float, xr_locomotion_delta: Vector3 = Vector3.ZERO) -> void:
	if dt <= 0.0:
		return
	var pivot := _swing.global_position
	if pivot.distance_to(_previous_pivot) > SWING_JUMP_DISTANCE:
		_reset_swing()
		return
	# The rig's joystick translation carries part of the bob along with the hand.
	# Leave tracked hand motion and world-space gravity untouched.
	if placement == Placement.HELD and not _adjusting and xr_locomotion_delta.is_finite() and xr_locomotion_delta.length() < SWING_JUMP_DISTANCE:
		_bob_world += xr_locomotion_delta * XR_LOCOMOTION_FOLLOW
	if _adjusting:
		_bob_world += pivot - _previous_pivot
		_bob_velocity = Vector3.ZERO
	else:
		var steps := maxi(1, ceili(dt / SWING_STEP))
		var step_dt := dt / float(steps)
		var pivot_velocity := (pivot - _previous_pivot) / dt
		for step: int in steps:
			var step_pivot := _previous_pivot + (pivot - _previous_pivot) * (float(step + 1) / float(steps))
			var old_bob := _bob_world
			_bob_velocity += Vector3.DOWN * SWING_GRAVITY * step_dt
			_bob_velocity *= exp(-SWING_DRAG * step_dt)
			var unconstrained := _bob_world + _bob_velocity * step_dt
			var direction := unconstrained - step_pivot
			if direction.length_squared() < 0.000001:
				direction = Vector3.DOWN
			direction = direction.normalized()
			_bob_world = step_pivot + direction * SUSPENSION_LENGTH
			_bob_velocity = (_bob_world - old_bob) / step_dt
			# The string removes radial velocity relative to its moving pivot.
			_bob_velocity -= direction * (_bob_velocity - pivot_velocity).dot(direction)
	_previous_pivot = pivot
	_orient_swing(pivot)

func _orient_swing(pivot: Vector3) -> void:
	var down := (_bob_world - pivot).normalized()
	if down.length_squared() < 0.5:
		down = Vector3.DOWN
	var up := -down
	# Shaft yaw affects only the beam orientation, never the bob simulation.
	var forward := -global_basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = _last_horizontal_aim - up * _last_horizontal_aim.dot(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	forward = forward.normalized()
	var z_axis := -forward
	var x_axis := up.cross(z_axis).normalized()
	_swing.global_transform = Transform3D(Basis(x_axis, up, z_axis), pivot)

func _valid_transform(value: Transform3D) -> bool:
	return is_finite(value.origin.x) and is_finite(value.origin.y) and is_finite(value.origin.z) and is_finite(value.basis.determinant()) and absf(value.basis.determinant()) > 0.01
