class_name StaffTool
extends XRToolsPickable

## World-space lantern tool. The shaft runs along local +Y; local -Z is the beam aim.
## Input drivers own only the held pose. This node owns every unheld pose.
enum Placement { HELD, FLOATING, SETTLING, PARKED, RECALL_HOVER }

const GRIP_Y := [-0.48, 0.0, 0.46]
const SHAFT_HALF_LENGTH := 0.77
const FLOAT_TIME := 0.38
const PARK_HEIGHT := 0.79
const RECALL_SPEED := 8.0
const RECALL_OFFSET := Vector3(0.18, -0.10, -0.38)
const SHUTTER_HAND_TRAVEL_M := 0.08
const SHUTTER_DEAD_ZONE_M := 0.02
# The grip pose is forward of the wrist. Tracking this point removes most of
# the apparent vertical motion caused by tilting the controller in place.
const WRIST_BACK_OFFSET_M := 0.10
const FILTER_ENTER_PITCH := 0.30
const FILTER_CENTER_PITCH := 0.16

var placement: Placement = Placement.HELD
var lantern: Lantern
var world_surface: Variant
var grip_index: int = 1
var _swing: Node3D
var _swing_angle := Vector2.ZERO
var _swing_velocity := Vector2.ZERO
var _previous_position := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _float_elapsed := 0.0
var _float_origin := Transform3D.IDENTITY
var _park_target := Transform3D.IDENTITY
var _last_horizontal_aim := Vector3.FORWARD
var _adjusting := false
var _adjust_reference := Basis.IDENTITY
var _adjust_origin_y := 0.0
var _adjust_open := 1.0
var _last_pitch_detent := 0
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
	_previous_position = global_position
	_capture_aim()

func pick_up(by: Node3D) -> void:
	super.pick_up(by)
	if not is_picked_up():
		return
	var point := get_active_grab_point()
	var index := 1
	if point != null:
		for candidate: int in GRIP_Y.size():
			if absf(point.position.y - GRIP_Y[candidate]) < 0.02:
				index = candidate
				break
	adopt_external_grab(index)

func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.08
	shape.height = SHAFT_HALF_LENGTH * 2.0
	collider.shape = shape
	add_child(collider)
	var shaft := MeshInstance3D.new()
	shaft.name = "StaffShaft"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.022
	shaft_mesh.bottom_radius = 0.037
	shaft_mesh.height = SHAFT_HALF_LENGTH * 2.0
	shaft.mesh = shaft_mesh
	shaft.material_override = _material(Color("51402b"), 0.75, 0.0)
	add_child(shaft)
	for y: float in GRIP_Y:
		var wrap := MeshInstance3D.new()
		var wrap_mesh := CylinderMesh.new()
		wrap_mesh.top_radius = 0.037
		wrap_mesh.bottom_radius = 0.037
		wrap_mesh.height = 0.13
		wrap.mesh = wrap_mesh
		wrap.position.y = y
		wrap.material_override = _material(Color("9d7953"), 0.8, 0.0)
		add_child(wrap)
	var ferrule := MeshInstance3D.new()
	var ferrule_mesh := CylinderMesh.new()
	ferrule_mesh.top_radius = 0.045
	ferrule_mesh.bottom_radius = 0.045
	ferrule_mesh.height = 0.09
	ferrule.mesh = ferrule_mesh
	ferrule.position.y = -SHAFT_HALF_LENGTH
	ferrule.material_override = _material(Color("857f69"), 0.48, 0.0)
	add_child(ferrule)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.014
	arm_mesh.bottom_radius = 0.014
	arm_mesh.height = 0.31
	arm.mesh = arm_mesh
	arm.rotation.z = PI * 0.5
	arm.position = Vector3(0.15, 0.68, 0.0)
	arm.material_override = _material(Color("857f69"), 0.48, 0.0)
	add_child(arm)
	_swing = Node3D.new()
	_swing.name = "DampedLanternJoint"
	_swing.position = Vector3(0.30, 0.68, 0.0)
	add_child(_swing)
	lantern = Lantern.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0.0, -0.25, 0.0)
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
	return to_global(Vector3(0.0, GRIP_Y[clampi(index, 0, 2)], 0.0))

func control_world_position() -> Vector3:
	return lantern.global_position

func hold(hand_world: Transform3D, index: int = 1) -> void:
	if not _valid_transform(hand_world):
		return
	grip_index = clampi(index, 0, 2)
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

func transfer(hand_world: Transform3D, index: int = 1) -> void:
	# A hand swap is atomic. It never passes through gameplay release.
	hold(hand_world, index)

func adopt_external_grab(index: int = 1) -> void:
	grip_index = clampi(index, 0, 2)
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
	_swing_velocity = Vector2.ZERO
	_previous_position = global_position
	_previous_velocity = Vector3.ZERO
	if is_instance_valid(_grab_driver):
		_grab_driver.set_physics_process(false)

func tracking_restored() -> void:
	_previous_position = global_position
	_previous_velocity = Vector3.ZERO
	if is_instance_valid(_grab_driver):
		_grab_driver.set_physics_process(true)

func release_final() -> void:
	if placement != Placement.HELD:
		return
	_adjusting = false
	external_pose_owned = false
	lantern.set_shutter(1.0)
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
	_adjust_reference = hand_world.basis.orthonormalized()
	_adjust_origin_y = _adjust_wrist_height(hand_world)
	_adjust_open = lantern.shutter_openness
	_last_pitch_detent = 0
	_swing_velocity *= 0.2

func update_adjust(hand_world: Transform3D) -> void:
	if not _adjusting or not _valid_transform(hand_world):
		return
	var relative := _adjust_reference.inverse() * hand_world.basis.orthonormalized()
	# Angles come from the captured relative basis, avoiding Euler subtraction at wrap.
	var pitch := atan2(-relative.z.y, relative.z.z)
	# Raise/lower the adjusting hand for aperture; pitch now only selects a filter.
	var height_delta := _adjust_wrist_height(hand_world) - _adjust_origin_y
	var shutter_motion := signf(height_delta) * maxf(absf(height_delta) - SHUTTER_DEAD_ZONE_M, 0.0)
	lantern.set_shutter(clampf(_adjust_open + shutter_motion / SHUTTER_HAND_TRAVEL_M, 0.0, 1.0))
	var detent := _last_pitch_detent
	if pitch < (-FILTER_ENTER_PITCH if detent == 0 else -0.19):
		detent = -1
	elif pitch > (FILTER_ENTER_PITCH if detent == 0 else 0.19):
		detent = 1
	elif absf(pitch) < FILTER_CENTER_PITCH:
		detent = 0
	if detent != _last_pitch_detent:
		_last_pitch_detent = detent
		lantern.set_mode(LightField.Mode.CLEAR if detent == 0 else LightField.Mode.BLUE if detent < 0 else LightField.Mode.ORANGE)

func end_adjust() -> void:
	_adjusting = false

func _adjust_wrist_height(hand_world: Transform3D) -> float:
	return (hand_world.origin + hand_world.basis.orthonormalized() * Vector3(0.0, 0.0, WRIST_BACK_OFFSET_M)).y

func reset_to_pose(staff_world: Transform3D, shutter: float = 1.0, held: bool = true) -> void:
	if not _valid_transform(staff_world):
		return
	global_transform = Transform3D(staff_world.basis.orthonormalized(), staff_world.origin)
	placement = Placement.HELD if held else Placement.PARKED
	external_pose_owned = false
	_adjusting = false
	_float_elapsed = 0.0
	_swing_angle = Vector2.ZERO
	_swing_velocity = Vector2.ZERO
	_swing.rotation = Vector3.ZERO
	_previous_position = global_position
	_previous_velocity = Vector3.ZERO
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
	elif placement == Placement.RECALL_HOVER:
		update_recall(_recall_hand, dt)
	_update_swing(dt)
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
	if global_position.distance_to(_previous_position) > 0.55:
		_swing_velocity = Vector2.ZERO
		_previous_velocity = Vector3.ZERO
		_previous_position = global_position

func _update_swing(dt: float) -> void:
	if dt <= 0.0:
		return
	var velocity := (global_position - _previous_position) / dt
	if velocity.length() > 8.0:
		velocity = Vector3.ZERO
		_previous_velocity = Vector3.ZERO
	var acceleration := (velocity - _previous_velocity) / dt
	var local_accel := global_basis.inverse() * acceleration
	var resting_pitch := -0.25 if placement == Placement.PARKED or placement == Placement.SETTLING else 0.0
	var target := Vector2(clampf(-local_accel.z * 0.018, -0.22, 0.22) + resting_pitch, clampf(local_accel.x * 0.018, -0.22, 0.22))
	if _adjusting:
		target = _swing_angle
	_swing_velocity += (target - _swing_angle) * (22.0 * dt)
	_swing_velocity *= exp(-7.0 * dt)
	_swing_angle += _swing_velocity * dt
	_swing_angle.x = clampf(_swing_angle.x, -0.46, 0.38)
	_swing_angle.y = clampf(_swing_angle.y, -0.36, 0.36)
	_swing.rotation = Vector3(_swing_angle.x, 0.0, _swing_angle.y)
	_previous_position = global_position
	_previous_velocity = velocity

func _valid_transform(value: Transform3D) -> bool:
	return is_finite(value.origin.x) and is_finite(value.origin.y) and is_finite(value.origin.z) and is_finite(value.basis.determinant()) and absf(value.basis.determinant()) > 0.01
