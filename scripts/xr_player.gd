class_name MushiXRPlayer
extends XROrigin3D

class BroomFlightProvider extends XRToolsMovementProvider:
	var rig: Node
	var order: int = 100

	func _ready() -> void:
		add_to_group("movement_providers")

	func physics_movement(_delta: float, player_body: XRToolsPlayerBody, _disabled: bool) -> bool:
		if rig == null or not rig._broom_flying:
			return false
		var velocity: Vector3 = rig._broom_horizontal_velocity + Vector3.UP * rig._broom_vertical_speed
		player_body.move_player(velocity)
		return true

signal recall_requested(controller: XRController3D)
signal recall_released(controller: XRController3D)
signal menu_toggled(open: bool)
signal tutorial_trigger_pressed
signal fall_recovered(body_position: Vector3)

@export var recall_hold_seconds: float = 0.5
@export var snap_turn: bool = true
@export_range(0.0, 0.5, 0.01) var locomotion_deadzone: float = 0.22
@export var move_hand_left: bool = true

@onready var camera: XRCamera3D = $Camera
@onready var left_controller: XRController3D = $LeftController
@onready var right_controller: XRController3D = $RightController
@onready var left_pickup: XRToolsFunctionPickup = $LeftController/Pickup
@onready var right_pickup: XRToolsFunctionPickup = $RightController/Pickup
@onready var _body: XRToolsPlayerBody = $PlayerBody
@onready var _move: XRToolsMovementDirect = $LeftController/MovementDirect
@onready var _turn: XRToolsMovementTurn = $RightController/MovementTurn
@onready var _left_turn: XRToolsMovementTurn = $LeftController/MovementTurn
@onready var _right_move: XRToolsMovementDirect = $RightController/MovementDirect
@onready var _left_pointer: XRToolsFunctionPointer = $LeftController/Pointer
@onready var _right_pointer: XRToolsFunctionPointer = $RightController/Pointer
@onready var _menu_surface: XRToolsViewport2DIn3D = $Camera/MenuSurface

var xr_active: bool = false
var world_surface: Variant
var _menu_open: bool = false
var _interaction_lock: bool = false
var _movement_neutral_required: bool = false
var _active_move_deadzone: float = 0.22
var _active_turn_deadzone: float = 0.22
var _single_controller_side: int = -1 # -1: both/neither, 0: left only, 1: right only
var _controller_active_mask: int = -1 # Force an initial route refresh before either controller is active.
var _jump_input_latched: bool = false
var _recall_pressed_at: Dictionary = {}
var _recall_active: Dictionary = {}
var _tutorial_trigger_down := [false, false]
var _last_ground_recovery_msec: int = -10000
var _last_safe_ground_position := Vector3.ZERO
var _has_safe_ground_position := false
var _broom_flying: bool = false
var _broom_landing_requested: bool = false
var _broom_forward_local: Vector3 = Vector3.FORWARD
var _broom_hand_heading_local: Vector3 = Vector3.ZERO
var _broom_horizontal_velocity: Vector3 = Vector3.ZERO
var _broom_vertical_speed: float = 0.0
var _broom_provider: BroomFlightProvider
var _comfort_vignette: XRToolsVignette
var _vignette_strength: float = 0.0

const MIN_TRACKED_HEAD_HEIGHT: float = 0.55
const GROUND_START_CLEARANCE: float = 0.25
const GROUND_RECOVERY_DEPTH: float = 0.3
const MENU_POINTER_CUTOFF_M: float = 1.0
const MENU_STANDOFF_M: float = 0.78
const BROOM_MAX_SPEED: float = 4.2
const BROOM_VERTICAL_SPEED: float = 3.0
const BROOM_HORIZONTAL_ACCELERATION: float = 6.0
const BROOM_HORIZONTAL_BRAKING: float = 2.8
const BROOM_VERTICAL_ACCELERATION: float = 4.5
const BROOM_VERTICAL_BRAKING: float = 2.5
const BROOM_RELEASE_LOCK_HEIGHT: float = 2.0
const BROOM_LANDING_SPEED: float = 3.5
const BROOM_LAND_CLEARANCE: float = 0.18
const FALL_RECOVERY_Y: float = -10.0
const BROOM_MAX_YAW_STEP: float = 0.05
const BROOM_SMOOTH_TURN_SPEED: float = 2.0
const JUMP_STICK_THRESHOLD: float = 0.8

func _enter_tree() -> void:
	_broom_provider = BroomFlightProvider.new()
	_broom_provider.name = "BroomFlightProvider"
	_broom_provider.rig = self
	add_child(_broom_provider)
	# Main only instantiates this scene for XR. Keep a command-line escape hatch
	# for desktop/headless runs when a runtime happens to be installed.
	if "--desktop" in OS.get_cmdline_user_args():
		return
	var openxr: XRInterface = XRServer.find_interface("OpenXR")
	if openxr != null and openxr.initialize():
		xr_active = true
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _ready() -> void:
	if xr_active:
		print("MUSHI_XR_ACTIVE: OpenXR player rig initialized")
	# Match desktop's slightly more permissive grade limit so the rear ramps
	# remain walkable while the sharp terrace lips stay too steep to climb.
	_body.default_physics.move_max_slope = 50.0
	# PlayerBody snapshots the movement-provider group in its own _ready().
	# The broom provider is added dynamically, after that snapshot is taken.
	if not _body._movement_providers.has(_broom_provider):
		_body._movement_providers.append(_broom_provider)
		_body._movement_providers.sort_custom(_body.sort_by_order)
	# XR Tools otherwise calibrates on its first physics tick, which can see a
	# zero HMD pose. That offset subsequently pulls the body below the basin.
	_body.enabled = false
	_body.player_calibrate_height = false
	_body.player_height_offset = 0.0
	_update_locomotion_deadzone()
	_turn.turn_mode = XRToolsMovementTurn.TurnMode.SNAP if snap_turn else XRToolsMovementTurn.TurnMode.SMOOTH
	_left_turn.turn_mode = _turn.turn_mode
	_comfort_vignette = preload("res://addons/godot-xr-tools/effects/vignette.tscn").instantiate() as XRToolsVignette
	_comfort_vignette.name = "ComfortVignette"
	camera.add_child(_comfort_vignette)
	set_vignette_strength(_vignette_strength)
	left_controller.button_pressed.connect(_on_button_pressed.bind(left_controller))
	left_controller.button_released.connect(_on_button_released.bind(left_controller))
	right_controller.button_pressed.connect(_on_button_pressed.bind(right_controller))
	right_controller.button_released.connect(_on_button_released.bind(right_controller))
	set_menu_open(false)
	_update_movement()


func set_controller_hand_meshes_visible(show_meshes: bool) -> void:
	# Keep XR Tools hand nodes, skeletons, and grab-point tracking alive for
	# avatar wrist targets. Only the duplicate rendered meshes are hidden.
	for controller in [left_controller, right_controller]:
		var hand := controller.get_node_or_null("Hand") as Node3D
		if hand == null:
			continue
		for mesh in hand.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).visible = show_meshes


func _process(_delta: float) -> void:
	if not xr_active:
		return
	_update_locomotion_route()
	if _movement_neutral_required and not _menu_open and not _interaction_lock:
		if _locomotion_is_neutral():
			_movement_neutral_required = false
			_update_movement()
	var now: float = Time.get_ticks_msec() / 1000.0
	# Several OpenXR profiles expose trigger_click through an analog binding.
	# Edge-detect the value instead, once for either tracked controller.
	for index in range(2):
		var controller: XRController3D = left_controller if index == 0 else right_controller
		var down: bool = controller.get_is_active() and controller.get_float("trigger") >= 0.65
		if down and not _tutorial_trigger_down[index] and not _menu_open:
			tutorial_trigger_pressed.emit()
		_tutorial_trigger_down[index] = down
	for controller in [left_controller, right_controller]:
		if _recall_pressed_at.has(controller) and not _recall_active.has(controller):
			if now - float(_recall_pressed_at[controller]) >= recall_hold_seconds:
				_recall_active[controller] = true
				recall_requested.emit(controller)

func _physics_process(_delta: float) -> void:
	if not xr_active:
		return
	if not _body.enabled:
		_try_activate_body()
		return
	_update_jump_input()
	if world_surface == null:
		return
	if _broom_flying:
		_update_broom_motion(_delta)
	var feet: Vector3 = _body.global_position
	var xz := Vector2(feet.x, feet.z)
	if feet.y < FALL_RECOVERY_Y:
		_recover_out_of_bounds_fall()
		return
	if not world_surface.is_in_bounds(xz):
		if _has_safe_ground_position and feet.y < _last_safe_ground_position.y - 4.0:
			_recover_out_of_bounds_fall()
		return
	var ground: float = float(world_surface.get_height_at(xz))
	if is_finite(ground) and feet.y < ground - 2.0:
		_recover_out_of_bounds_fall()
		return
	if is_finite(ground) and feet.y >= ground - GROUND_RECOVERY_DEPTH:
		_last_safe_ground_position = Vector3(feet.x, ground + GROUND_START_CLEARANCE, feet.z)
		_has_safe_ground_position = true
	if is_finite(ground) and feet.y < ground - GROUND_RECOVERY_DEPTH:
		_teleport_body_above_ground(ground)
		_last_safe_ground_position = Vector3(feet.x, ground + GROUND_START_CLEARANCE, feet.z)
		_has_safe_ground_position = true
		var now := Time.get_ticks_msec()
		if now - _last_ground_recovery_msec > 1000:
			print("MUSHI_XR_GROUND_RECOVERY: body feet %.2f below terrain %.2f" % [feet.y, ground])
			_last_ground_recovery_msec = now
	if _broom_flying and _body.on_ground:
		if _broom_landing_requested:
			_finish_broom_flight()

func _update_jump_input() -> void:
	var left_active := left_controller.get_is_active()
	var right_active := right_controller.get_is_active()
	# A lone controller uses this same Y axis for walking. Keep that axis free
	# and use its stick click instead; either hand can then play one-handed.
	var pressed := _jump_input_pressed(
		left_active, right_active,
		right_controller.get_vector2("primary").y,
		left_controller.is_button_pressed("primary_click"),
		right_controller.is_button_pressed("primary_click"))
	var can_jump := not _menu_open and not _interaction_lock and not _movement_neutral_required and not _broom_flying
	if pressed and not _jump_input_latched and can_jump and _body.on_ground:
		_body.request_jump()
	_jump_input_latched = pressed

static func _jump_input_pressed(left_active: bool, right_active: bool, right_stick_y: float,
		left_stick_click: bool, right_stick_click: bool) -> bool:
	if left_active and right_active:
		return right_stick_y >= JUMP_STICK_THRESHOLD or right_stick_click
	if left_active:
		return left_stick_click
	if right_active:
		return right_stick_click
	return false

func _update_broom_motion(delta: float) -> void:
	# Controller poses are local to this rig. Unlike the Pickable's physics-tick
	# world pose, they cannot feed a rig rotation back into the next yaw sample.
	var hand_heading := _broom_controller_heading()
	if hand_heading != Vector3.ZERO:
		if _broom_hand_heading_local != Vector3.ZERO:
			var yaw_delta := atan2(_broom_hand_heading_local.cross(hand_heading).y,
				_broom_hand_heading_local.dot(hand_heading))
			if absf(yaw_delta) > 0.005:
				_body.rotate_player(-clampf(yaw_delta, -BROOM_MAX_YAW_STEP, BROOM_MAX_YAW_STEP))
		_broom_hand_heading_local = hand_heading
		# Match axial thrust to the current visible shaft after the rig turn.
		_broom_forward_local = hand_heading
	# Use XR Tools' smooth-turn rate and deadzone while its ordinary turn
	# provider is disabled for flight. Rotating the origin carries the held
	# staff and both grabbers together; their rig-local heading stays stable.
	if right_controller.get_is_active() and not _menu_open:
		var turn_input := _apply_axis_deadzone(right_controller.get_vector2("primary").x,
			_active_turn_deadzone)
		if not is_zero_approx(turn_input):
			_body.rotate_player(BROOM_SMOOTH_TURN_SPEED * delta * turn_input)

	var clearance := broom_height_above_ground()
	if _broom_landing_requested:
		_broom_horizontal_velocity = Vector3.ZERO
		_broom_vertical_speed = -BROOM_LANDING_SPEED
	else:
		var left_y := _left_stick_y() if not _menu_open else 0.0
		var right_y := _right_stick_y() if not _menu_open else 0.0
		# Use the headset-tested stick directions for staff-forward and ascent.
		# World-space momentum keeps a shaft turn from rotating existing drift.
		var axial_input := _apply_stick_deadzone(left_y)
		var vertical_input := _apply_stick_deadzone(right_y)
		var forward: Vector3 = global_transform.basis * _broom_forward_local
		forward.y = 0.0
		forward = forward.normalized()
		var target_horizontal := forward * axial_input * BROOM_MAX_SPEED
		var target_vertical := vertical_input * BROOM_VERTICAL_SPEED
		var step := clampf(delta, 0.0, 0.1)
		var horizontal_rate := BROOM_HORIZONTAL_BRAKING if is_zero_approx(axial_input) else BROOM_HORIZONTAL_ACCELERATION
		var vertical_rate := BROOM_VERTICAL_BRAKING if is_zero_approx(vertical_input) else BROOM_VERTICAL_ACCELERATION
		_broom_horizontal_velocity = _broom_horizontal_velocity.move_toward(target_horizontal, horizontal_rate * step)
		_broom_vertical_speed = move_toward(_broom_vertical_speed, target_vertical, vertical_rate * step)
		if (_body.on_ground or clearance <= BROOM_LAND_CLEARANCE) and _broom_vertical_speed < 0.0:
			# Never accumulate downward speed against the floor.
			_broom_vertical_speed = 0.0

	# The dedicated movement provider applies the requested velocity through
	# PlayerBody.move_player(), preserving collision handling without gravity.

func _left_stick_y() -> float:
	return left_controller.get_vector2("primary").y if left_controller.get_is_active() else 0.0

func _right_stick_y() -> float:
	return right_controller.get_vector2("primary").y if right_controller.get_is_active() else 0.0

func _apply_stick_deadzone(value: float) -> float:
	return _apply_axis_deadzone(value, _active_move_deadzone)

func _apply_axis_deadzone(value: float, deadzone: float) -> float:
	if not is_finite(value):
		return 0.0
	var magnitude := absf(value)
	if magnitude <= deadzone:
		return 0.0
	return signf(value) * clampf((magnitude - deadzone) / (1.0 - deadzone), 0.0, 1.0)

func _finish_broom_flight() -> void:
	_broom_flying = false
	_broom_landing_requested = false
	_broom_horizontal_velocity = Vector3.ZERO
	_broom_vertical_speed = 0.0
	_broom_hand_heading_local = Vector3.ZERO
	_body.velocity = Vector3.ZERO
	_update_movement()

## Begin axial staff flight. The supplied vector points toward the broom's
## front; only its horizontal heading is used so the player's body stays upright.
func start_broom_flight(forward: Vector3) -> bool:
	if not is_node_ready() or not _body.enabled or world_surface == null or _menu_open:
		return false
	var heading := _world_to_local_heading(forward)
	if heading.length_squared() < 0.001:
		return false
	# The staff chooses the initial direction; reconstructing XR Tools' two-hand
	# pose from live grabber transforms supplies steering without depending on
	# GrabDriver's physics update ordering.
	_broom_forward_local = heading
	_broom_hand_heading_local = _broom_controller_heading()
	_broom_flying = true
	_broom_landing_requested = false
	_broom_horizontal_velocity = Vector3.ZERO
	_broom_vertical_speed = 0.0
	_body.velocity = Vector3.ZERO
	_update_movement()
	return true

## The held Pickable can update one physics tick behind a rig turn. Steering is
## sampled from the local controller pair in _update_broom_motion instead.
func set_broom_forward(_forward: Vector3) -> void:
	pass

func _broom_controller_heading() -> Vector3:
	if not left_controller.get_is_active() or not right_controller.get_is_active():
		return Vector3.ZERO
	var staff := left_pickup.picked_up_object as XRToolsPickable
	if staff == null or right_pickup.picked_up_object != staff:
		return Vector3.ZERO
	var driver: XRToolsGrabDriver = staff._grab_driver
	if not is_instance_valid(driver) or not is_instance_valid(driver.primary) or not is_instance_valid(driver.secondary):
		return Vector3.ZERO
	var primary: Grab = driver.primary
	var secondary: Grab = driver.secondary
	if not is_instance_valid(primary.by) or not is_instance_valid(secondary.by):
		return Vector3.ZERO
	# Use exactly the grab transforms and blending that GrabDriver uses, but
	# calculate in rig-local space before its RemoteTransform moves the staff.
	var rig_inverse := global_transform.affine_inverse()
	var primary_by: Transform3D = rig_inverse * primary.by.global_transform
	var secondary_by: Transform3D = rig_inverse * secondary.by.global_transform
	var first: Transform3D = primary_by * primary.transform.affine_inverse()
	var second: Transform3D = secondary_by * secondary.transform.affine_inverse()
	var angle_weight: float = secondary.drive_angle / (primary.drive_angle + secondary.drive_angle) \
		if primary.drive_angle + secondary.drive_angle > 0.0 else 0.0
	var position_weight: float = secondary.drive_position / (primary.drive_position + secondary.drive_position) \
		if primary.drive_position + secondary.drive_position > 0.0 else 0.0
	var pose := Transform3D(first.basis.slerp(second.basis, angle_weight),
		first.origin.lerp(second.origin, position_weight))
	if secondary.drive_aim > 0.0:
		var primary_local := primary_by.affine_inverse() * pose
		var secondary_from: Vector3 = (primary_local * secondary.transform.origin).normalized()
		var secondary_to: Vector3 = (primary_by.affine_inverse() * secondary_by.origin).normalized()
		if secondary_from.length_squared() > 0.001 and secondary_to.length_squared() > 0.001:
			var aim := Basis(Quaternion(secondary_from, secondary_to))
			var rotate := Basis.IDENTITY.slerp(aim, secondary.drive_aim)
			pose = primary_by * Transform3D(rotate, Vector3.ZERO) * primary_local
	var axis := pose.basis.y
	axis.y = 0.0
	return axis.normalized() if axis.length_squared() > 0.001 else Vector3.ZERO

func _world_to_local_heading(forward: Vector3) -> Vector3:
	var horizontal := Vector3(forward.x, 0.0, forward.z)
	if horizontal.length_squared() < 0.001:
		return Vector3.ZERO
	var local := global_transform.basis.inverse() * horizontal.normalized()
	local.y = 0.0
	return local.normalized() if local.length_squared() > 0.001 else Vector3.ZERO

## A release above two metres requests a controlled landing; below that
## height flight ends immediately and PlayerBody gravity takes over.
func stop_broom_flight() -> void:
	if not _broom_flying:
		return
	if _broom_landing_requested:
		return
	if broom_height_above_ground() > BROOM_RELEASE_LOCK_HEIGHT:
		_broom_landing_requested = true
	else:
		_finish_broom_flight()

func resume_broom_flight() -> bool:
	if not _broom_flying or not _broom_landing_requested or broom_height_above_ground() <= BROOM_RELEASE_LOCK_HEIGHT:
		return false
	_broom_landing_requested = false
	_broom_vertical_speed = 0.0
	return true

func is_broom_flying() -> bool:
	return _broom_flying

func broom_release_locked() -> bool:
	return _broom_flying and (_broom_landing_requested or broom_height_above_ground() > BROOM_RELEASE_LOCK_HEIGHT)

func broom_height_above_ground() -> float:
	if world_surface == null or not is_instance_valid(_body):
		return 0.0
	var feet := _body.global_position
	var xz := Vector2(feet.x, feet.z)
	if not world_surface.is_in_bounds(xz):
		return 0.0
	var ground := float(world_surface.get_height_at(xz))
	if not is_finite(ground):
		return 0.0
	return maxf(0.0, feet.y - ground)

func _try_activate_body() -> void:
	var tracked_height: float = camera.transform.origin.y
	if not is_finite(tracked_height) or tracked_height < MIN_TRACKED_HEAD_HEIGHT or tracked_height > 3.0:
		return
	if world_surface != null:
		var head_position: Vector3 = camera.global_position
		var xz := Vector2(head_position.x, head_position.z)
		if not world_surface.is_in_bounds(xz):
			return
		var ground: float = float(world_surface.get_height_at(xz))
		if not is_finite(ground) or not _terrain_collision_ready(xz, ground):
			return
		_teleport_body_above_ground(ground)
	_body.enabled = true
	print("MUSHI_XR_BODY_READY: tracked head height %.2f m" % tracked_height)

func _terrain_collision_ready(xz: Vector2, ground: float) -> bool:
	var from := Vector3(xz.x, ground + 2.0, xz.y)
	var to := Vector3(xz.x, ground - 2.0, xz.y)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider is Node and hit.collider.name == "BakedBasinCollision"

func _teleport_body_above_ground(ground: float) -> void:
	var target: Transform3D = _body.global_transform
	target.origin.y = ground + GROUND_START_CLEARANCE
	_body.teleport(target)
	_body.velocity = Vector3.ZERO

func _recover_out_of_bounds_fall() -> void:
	if not _has_safe_ground_position:
		var center := Vector2.ZERO
		if world_surface == null or not world_surface.is_in_bounds(center):
			return
		var ground := float(world_surface.get_height_at(center))
		if not is_finite(ground):
			return
		_last_safe_ground_position = Vector3(center.x, ground + GROUND_START_CLEARANCE, center.y)
		_has_safe_ground_position = true
	if _broom_flying:
		_finish_broom_flight()
	var target := _body.global_transform
	target.origin = _last_safe_ground_position
	_body.teleport(target)
	_body.velocity = Vector3.ZERO
	fall_recovered.emit(_last_safe_ground_position)
	print("MUSHI_XR_FALL_RECOVERY: returned player and staff to last safe terrain position")

func _on_button_pressed(action: String, controller: XRController3D) -> void:
	if action == "by_button":
		set_menu_open(not _menu_open)
	elif action == "ax_button":
		_recall_pressed_at[controller] = Time.get_ticks_msec() / 1000.0

func _on_button_released(action: String, controller: XRController3D) -> void:
	if action == "ax_button":
		_recall_pressed_at.erase(controller)
		if _recall_active.has(controller):
			_recall_active.erase(controller)
			recall_released.emit(controller)

func set_menu_open(open: bool) -> void:
	if open and _broom_flying:
		return
	if _menu_open == open and _menu_surface.visible == open:
		return
	_menu_open = open
	if open:
		_movement_neutral_required = true
		# Place the panel once from the opening head pose, then keep it in the
		# world scene so subsequent head motion does not drag the menu or aim.
		var camera_forward := -camera.global_transform.basis.z
		var horizontal_forward := Vector3(camera_forward.x, 0.0, camera_forward.z).normalized()
		if horizontal_forward.length_squared() < 0.001:
			horizontal_forward = Vector3.FORWARD
		var yaw := atan2(-horizontal_forward.x, -horizontal_forward.z)
		var menu_standoff := minf(MENU_STANDOFF_M, MENU_POINTER_CUTOFF_M * 0.8)
		var panel_position := camera.global_position + horizontal_forward * menu_standoff + Vector3.UP * -0.12
		var world_root := get_tree().current_scene
		if world_root != null and _menu_surface.get_parent() != world_root:
			_menu_surface.reparent(world_root, true)
		_menu_surface.global_transform = Transform3D(Basis(Vector3.UP, yaw), panel_position)
	_menu_surface.visible = open
	_menu_surface.enabled = open
	_left_pointer.enabled = open
	_right_pointer.enabled = open
	_update_movement()
	menu_toggled.emit(open)

func is_menu_open() -> bool:
	return _menu_open

func set_interaction_lock(locked: bool) -> void:
	if locked:
		_movement_neutral_required = true
	_interaction_lock = locked
	_update_movement()

func set_pickups_enabled(enabled: bool) -> void:
	left_pickup.enabled = enabled
	right_pickup.enabled = enabled

func _update_movement() -> void:
	var active: bool = xr_active and not _menu_open and not _interaction_lock and not _movement_neutral_required and not _broom_flying
	var left_active: bool = left_controller.get_is_active()
	var right_active: bool = right_controller.get_is_active()
	var both: bool = left_active and right_active
	var left_moves: bool = left_active and (not both or move_hand_left)
	var right_moves: bool = right_active and (not both or not move_hand_left)
	var left_turns: bool = left_active and (not both or not move_hand_left)
	var right_turns: bool = right_active and (not both or move_hand_left)
	# With one tracked controller the same X axis turns, so it must not strafe.
	_move.strafe = both
	_right_move.strafe = both
	_move.enabled = active and left_moves
	_right_move.enabled = active and right_moves
	_left_turn.enabled = active and left_turns
	_turn.enabled = active and right_turns
	# Providers are polled by PlayerBody, so suppress their input separately.
	_move.max_speed = 2.8 if active else 0.0
	_right_move.max_speed = 2.8 if active else 0.0
	_turn.smooth_turn_speed = 2.0 if active else 0.0
	_turn.step_turn_angle = 30.0 if active else 0.0
	_left_turn.smooth_turn_speed = 2.0 if active else 0.0
	_left_turn.step_turn_angle = 30.0 if active else 0.0

func _update_locomotion_route() -> void:
	var left_active: bool = left_controller.get_is_active()
	var right_active: bool = right_controller.get_is_active()
	var side := 0 if left_active and not right_active else (1 if right_active and not left_active else -1)
	var active_mask := int(left_active) | (int(right_active) << 1)
	if side == _single_controller_side and active_mask == _controller_active_mask:
		return
	_single_controller_side = side
	_controller_active_mask = active_mask
	_update_movement()

func _locomotion_is_neutral() -> bool:
	if _single_controller_side == 0:
		var stick := left_controller.get_vector2("primary")
		return stick.length() <= maxf(_active_move_deadzone, _active_turn_deadzone)
	if _single_controller_side == 1:
		var stick := right_controller.get_vector2("primary")
		return stick.length() <= maxf(_active_move_deadzone, _active_turn_deadzone)
	var move_stick := left_controller.get_vector2("primary") if move_hand_left else right_controller.get_vector2("primary")
	var turn_stick := right_controller.get_vector2("primary") if move_hand_left else left_controller.get_vector2("primary")
	return move_stick.length() <= _active_move_deadzone and absf(turn_stick.x) <= _active_turn_deadzone

func set_world_surface(surface: Variant) -> void:
	world_surface = surface

func reset_pose(world_position: Vector3) -> void:
	if _broom_flying:
		_finish_broom_flight()
	if world_surface != null:
		var xz := Vector2(world_position.x, world_position.z)
		if world_surface.is_in_bounds(xz):
			world_position.y = maxf(world_position.y, float(world_surface.get_height_at(xz)) + GROUND_START_CLEARANCE)
			_last_safe_ground_position = world_position
			_has_safe_ground_position = true
	if not is_node_ready():
		global_position = world_position
		return
	var target: Transform3D = _body.global_transform
	target.origin = world_position
	_body.teleport(target)
	_body.velocity = Vector3.ZERO


## One-time placement by tracked head position, optionally facing a chosen
## horizontal direction. The camera pivot is respected so yaw does not displace
## the head before it is translated to the requested XZ point.
func snap_head_horizontal_to(world_xz: Vector2, desired_forward: Vector3 = Vector3.ZERO) -> void:
	if not is_node_ready() or not is_finite(world_xz.x) or not is_finite(world_xz.y):
		return
	var target_forward := Vector3(desired_forward.x, 0.0, desired_forward.z)
	if target_forward.length_squared() > 0.0001:
		target_forward = target_forward.normalized()
		var current_forward := -camera.global_transform.basis.z
		current_forward.y = 0.0
		if current_forward.length_squared() > 0.0001:
			current_forward = current_forward.normalized()
			var yaw_delta := atan2(current_forward.cross(target_forward).y, current_forward.dot(target_forward))
			if absf(yaw_delta) > 0.0001:
				if _body.enabled:
					_body.rotate_player(-yaw_delta)
				else:
					var pivot := camera.global_position
					var turn := Basis(Vector3.UP, yaw_delta)
					var target := global_transform
					target.origin = pivot + turn * (target.origin - pivot)
					target.basis = turn * target.basis
					global_transform = target.orthonormalized()
	var head_position := camera.global_position
	var translation := Vector3(world_xz.x - head_position.x, 0.0, world_xz.y - head_position.z)
	if _body.enabled:
		var body_target := _body.global_transform
		body_target.origin += translation
		_body.teleport(body_target)
	else:
		global_position += translation
	_body.velocity = Vector3.ZERO

func set_snap_turn(enabled: bool) -> void:
	snap_turn = enabled
	if is_node_ready():
		_update_locomotion_deadzone()
		_turn.turn_mode = XRToolsMovementTurn.TurnMode.SNAP if enabled else XRToolsMovementTurn.TurnMode.SMOOTH
		_left_turn.turn_mode = _turn.turn_mode

func set_move_hand_left(enabled: bool) -> void:
	move_hand_left = enabled
	if is_node_ready():
		_update_movement()

func set_vignette_strength(strength: float) -> void:
	_vignette_strength = clampf(strength, 0.0, 1.0)
	if _comfort_vignette == null:
		return
	_comfort_vignette.auto_adjust = _vignette_strength > 0.0
	_comfort_vignette.auto_inner_radius = 1.0 - 0.65 * _vignette_strength
	_comfort_vignette.auto_velocity_limit = 2.8
	_comfort_vignette.auto_rotation_limit = 80.0
	if is_zero_approx(_vignette_strength):
		_comfort_vignette.radius = 1.0

func set_haptics_enabled(enabled: bool) -> void:
	XRToolsUserSettings.haptics_scale = 1.0 if enabled else 0.0

func _update_locomotion_deadzone() -> void:
	_active_move_deadzone = maxf(
		locomotion_deadzone,
		maxf(XRToolsUserSettings.x_axis_dead_zone, XRToolsUserSettings.y_axis_dead_zone))
	_active_turn_deadzone = maxf(locomotion_deadzone, XRToolsUserSettings.x_axis_dead_zone)
	if snap_turn:
		_active_turn_deadzone = maxf(_active_turn_deadzone, XRTools.get_snap_turning_deadzone())
	_move.stick_deadzone = _active_move_deadzone
	_right_move.stick_deadzone = _active_move_deadzone
	_turn.stick_deadzone = _active_turn_deadzone
	_left_turn.stick_deadzone = _active_turn_deadzone
