class_name DesktopPlayer
extends CharacterBody3D

@export var move_speed: float = 5.4
@export var mouse_sensitivity: float = 0.0022

var camera: Camera3D
var look_enabled: bool = true
var _pitch: float = -0.12

func _ready() -> void:
	camera = get_node("Camera") as Camera3D
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	reset_look()

func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if (look_enabled and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED) or get_viewport().gui_get_focus_owner() is LineEdit:
		input = Vector2.ZERO
	if Input.is_key_pressed(KEY_SHIFT):
		input *= 0.3
	var local_direction := Vector3(input.x, 0.0, input.y)
	var world_direction := global_basis * local_direction
	velocity.x = world_direction.x * move_speed
	velocity.z = world_direction.z * move_speed
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and look_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.3, 1.05)
		camera.rotation.x = _pitch
	elif look_enabled and event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func reset_look() -> void:
	_pitch = -0.12
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	if camera != null:
		camera.rotation = Vector3(_pitch, 0.0, 0.0)
