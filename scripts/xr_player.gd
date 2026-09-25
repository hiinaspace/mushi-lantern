class_name MushiXRPlayer
extends XROrigin3D

signal recall_requested(controller: XRController3D)
signal recall_released(controller: XRController3D)
signal menu_toggled(open: bool)

@export var recall_hold_seconds: float = 0.5
@export var snap_turn: bool = false
@export_range(0.0, 0.5, 0.01) var locomotion_deadzone: float = 0.22

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
var _recall_pressed_at: Dictionary = {}
var _recall_active: Dictionary = {}
var _last_ground_recovery_msec: int = -10000

const MIN_TRACKED_HEAD_HEIGHT: float = 0.55
const GROUND_START_CLEARANCE: float = 0.25
const GROUND_RECOVERY_DEPTH: float = 0.3
const MENU_POINTER_CUTOFF_M: float = 1.0
const MENU_STANDOFF_M: float = 0.78

func _enter_tree() -> void:
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
	# XR Tools otherwise calibrates on its first physics tick, which can see a
	# zero HMD pose. That offset subsequently pulls the body below the basin.
	_body.enabled = false
	_body.player_calibrate_height = false
	_body.player_height_offset = 0.0
	_update_locomotion_deadzone()
	_turn.turn_mode = XRToolsMovementTurn.TurnMode.SNAP if snap_turn else XRToolsMovementTurn.TurnMode.SMOOTH
	_left_turn.turn_mode = _turn.turn_mode
	left_controller.button_pressed.connect(_on_button_pressed.bind(left_controller))
	left_controller.button_released.connect(_on_button_released.bind(left_controller))
	right_controller.button_pressed.connect(_on_button_pressed.bind(right_controller))
	right_controller.button_released.connect(_on_button_released.bind(right_controller))
	set_menu_open(false)
	_update_movement()

func _process(_delta: float) -> void:
	if not xr_active:
		return
	_update_locomotion_route()
	if _movement_neutral_required and not _menu_open and not _interaction_lock:
		if _locomotion_is_neutral():
			_movement_neutral_required = false
			_update_movement()
	var now: float = Time.get_ticks_msec() / 1000.0
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
	if world_surface == null:
		return
	var feet: Vector3 = _body.global_position
	var xz := Vector2(feet.x, feet.z)
	if not world_surface.is_in_bounds(xz):
		return
	var ground: float = float(world_surface.get_height_at(xz))
	if is_finite(ground) and feet.y < ground - GROUND_RECOVERY_DEPTH:
		_teleport_body_above_ground(ground)
		var now := Time.get_ticks_msec()
		if now - _last_ground_recovery_msec > 1000:
			print("MUSHI_XR_GROUND_RECOVERY: body feet %.2f below terrain %.2f" % [feet.y, ground])
			_last_ground_recovery_msec = now

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
	var active: bool = xr_active and not _menu_open and not _interaction_lock and not _movement_neutral_required
	var left_active: bool = left_controller.get_is_active()
	var right_active: bool = right_controller.get_is_active()
	var left_moves: bool = left_active and (right_active or _single_controller_side == 0)
	var right_moves: bool = right_active and not left_active
	var left_turns: bool = left_active and not right_active
	var right_turns: bool = right_active
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
	if side == _single_controller_side:
		return
	_single_controller_side = side
	_update_movement()

func _locomotion_is_neutral() -> bool:
	if _single_controller_side == 0:
		var stick := left_controller.get_vector2("primary")
		return stick.length() <= maxf(_active_move_deadzone, _active_turn_deadzone)
	if _single_controller_side == 1:
		var stick := right_controller.get_vector2("primary")
		return stick.length() <= maxf(_active_move_deadzone, _active_turn_deadzone)
	return left_controller.get_vector2("primary").length() <= _active_move_deadzone and absf(right_controller.get_vector2("primary").x) <= _active_turn_deadzone

func set_world_surface(surface: Variant) -> void:
	world_surface = surface

func reset_pose(world_position: Vector3) -> void:
	if world_surface != null:
		var xz := Vector2(world_position.x, world_position.z)
		if world_surface.is_in_bounds(xz):
			world_position.y = maxf(world_position.y, float(world_surface.get_height_at(xz)) + GROUND_START_CLEARANCE)
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
