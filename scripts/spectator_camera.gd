class_name MushiSpectatorCamera
extends Camera3D

const MOVE_SPEED := 8.0
const MOUSE_SENSITIVITY := 0.0022

var active := false
var controls_enabled := true
var sweeping := false
var sweep_target := Vector3.ZERO
var _sweep_start := Transform3D.IDENTITY
var _sweep_radius := 14.0
var _sweep_height := 8.0
var _sweep_angle := 0.0
var _sweep_time := 0.0
var _pitch := 0.0
var _yaw := 0.0

func enter_from(view: Camera3D) -> void:
	global_transform = view.global_transform
	_pitch = rotation.x
	_yaw = rotation.y
	active = true
	sweeping = false
	make_current()

func leave() -> void:
	active = false
	sweeping = false

func toggle_sweep(target: Vector3) -> void:
	if sweeping:
		sweeping = false
		return
	sweep_target = target
	_sweep_start = global_transform
	var offset := global_position - target
	_sweep_radius = clampf(Vector2(offset.x, offset.z).length(), 10.0, 22.0)
	_sweep_height = clampf(offset.y, 5.0, 14.0)
	_sweep_angle = atan2(offset.x, offset.z)
	_sweep_time = 0.0
	sweeping = true

func _process(delta: float) -> void:
	if not active or not controls_enabled:
		return
	if sweeping:
		_sweep_time += delta
		var angle := _sweep_angle + 0.42 * sin(_sweep_time * 0.13)
		var destination := sweep_target + Vector3(sin(angle) * _sweep_radius, _sweep_height, cos(angle) * _sweep_radius)
		var blend := smoothstep(0.0, 1.5, _sweep_time)
		var position_now := _sweep_start.origin.lerp(destination, blend)
		var facing := Transform3D(Basis.IDENTITY, position_now).looking_at(sweep_target, Vector3.UP)
		var turn := Quaternion(_sweep_start.basis.orthonormalized()).slerp(Quaternion(facing.basis), blend)
		global_transform = Transform3D(Basis(turn), position_now)
		_pitch = rotation.x
		_yaw = rotation.y
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(input.x, 0.0, input.y)
	if Input.is_key_pressed(KEY_Q):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		direction.y += 1.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var speed := MOVE_SPEED * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 0.25 if Input.is_key_pressed(KEY_CTRL) else 1.0)
	global_position += direction * speed * delta

func _unhandled_input(event: InputEvent) -> void:
	if not active or not controls_enabled or sweeping:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
		rotation = Vector3(_pitch, _yaw, 0.0)
