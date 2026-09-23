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
var _recall_pressed_at: Dictionary = {}
var _recall_active: Dictionary = {}

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
	_body.enabled = xr_active
	_update_locomotion_deadzone()
	_turn.turn_mode = XRToolsMovementTurn.TurnMode.SNAP if snap_turn else XRToolsMovementTurn.TurnMode.SMOOTH
	left_controller.button_pressed.connect(_on_button_pressed.bind(left_controller))
	left_controller.button_released.connect(_on_button_released.bind(left_controller))
	right_controller.button_pressed.connect(_on_button_pressed.bind(right_controller))
	right_controller.button_released.connect(_on_button_released.bind(right_controller))
	set_menu_open(false)
	_update_movement()

func _process(_delta: float) -> void:
	if not xr_active:
		return
	if _movement_neutral_required and not _menu_open and not _interaction_lock:
		if left_controller.get_vector2("primary").length() <= _active_move_deadzone and absf(right_controller.get_vector2("primary").x) <= _active_turn_deadzone:
			_movement_neutral_required = false
			_update_movement()
	var now: float = Time.get_ticks_msec() / 1000.0
	for controller in [left_controller, right_controller]:
		if _recall_pressed_at.has(controller) and not _recall_active.has(controller):
			if now - float(_recall_pressed_at[controller]) >= recall_hold_seconds:
				_recall_active[controller] = true
				recall_requested.emit(controller)

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
	_move.set_physics_process(active)
	_turn.set_physics_process(active)
	# Providers are polled by PlayerBody, so suppress their input separately.
	_move.max_speed = 2.8 if active else 0.0
	_turn.smooth_turn_speed = 2.0 if active else 0.0
	_turn.step_turn_angle = 30.0 if active else 0.0

func set_world_surface(surface: Variant) -> void:
	world_surface = surface

func reset_pose(world_position: Vector3) -> void:
	if not is_node_ready():
		global_position = world_position
		return
	var target: Transform3D = _body.global_transform
	target.origin = world_position
	_body.teleport(target)
	_body.velocity = Vector3.ZERO

func set_snap_turn(enabled: bool) -> void:
	snap_turn = enabled
	if is_node_ready():
		_update_locomotion_deadzone()
		_turn.turn_mode = XRToolsMovementTurn.TurnMode.SNAP if enabled else XRToolsMovementTurn.TurnMode.SMOOTH

func _update_locomotion_deadzone() -> void:
	_active_move_deadzone = maxf(
		locomotion_deadzone,
		maxf(XRToolsUserSettings.x_axis_dead_zone, XRToolsUserSettings.y_axis_dead_zone))
	_active_turn_deadzone = maxf(locomotion_deadzone, XRToolsUserSettings.x_axis_dead_zone)
	if snap_turn:
		_active_turn_deadzone = maxf(_active_turn_deadzone, XRTools.get_snap_turning_deadzone())
	_move.stick_deadzone = _active_move_deadzone
	_turn.stick_deadzone = _active_turn_deadzone
