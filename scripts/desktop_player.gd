class_name DesktopPlayer
extends CharacterBody3D

@export var move_speed: float = 5.4
@export var mouse_sensitivity: float = 0.0022

var world_surface: Variant
var controls_enabled: bool = true

var camera: Camera3D
var look_enabled: bool = true
var _pitch: float = -0.12

func _ready() -> void:
	camera = get_node("Camera") as Camera3D
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(42.0)
	reset_look()

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if not controls_enabled or (look_enabled and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED) or get_viewport().gui_get_focus_owner() is LineEdit:
		input = Vector2.ZERO
	if Input.is_key_pressed(KEY_SHIFT):
		input *= 0.3
	var local_direction := Vector3(input.x, 0.0, input.y)
	var world_direction := global_basis * local_direction
	velocity.x = world_direction.x * move_speed
	velocity.z = world_direction.z * move_speed
	if world_surface == null:
		velocity.y = 0.0
		move_and_slide()
		global_position.y = 0.0
	else:
		var old_xz := Vector2(global_position.x, global_position.z)
		var margin := float(world_surface.basin_margin(old_xz))
		# The outer slope is scenery. Bleed outward input away as it steepens,
		# including at 256 m where the broader bank could otherwise be walked.
		if margin < 0.0:
			var inward: Vector2 = world_surface.inward_direction(old_xz)
			var horizontal := Vector2(velocity.x, velocity.z)
			var outward_speed := minf(horizontal.dot(inward), 0.0)
			horizontal -= inward * outward_speed * clampf(-margin / 3.0, 0.0, 1.0)
			velocity.x = horizontal.x
			velocity.z = horizontal.y
		velocity.y -= 18.0 * delta
		move_and_slide()
		var new_xz := Vector2(global_position.x, global_position.z)
		if float(world_surface.basin_margin(new_xz)) < -4.0 and world_surface.basin_margin(new_xz) < margin:
			global_position.x = old_xz.x
			global_position.z = old_xz.y
		# Only a recovery guard: ordinary walking uses Terrain3D collision and
		# floor snapping. Missing collision must not drop the player below land.
		var ground := float(world_surface.get_height_at(Vector2(global_position.x, global_position.z)))
		if is_finite(ground) and global_position.y < ground - 0.2:
			global_position.y = ground + 0.02
			velocity.y = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and controls_enabled and look_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.3, 1.05)
		camera.rotation.x = _pitch
	elif controls_enabled and look_enabled and event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func reset_look() -> void:
	_pitch = -0.12
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	if camera != null:
		camera.rotation = Vector3(_pitch, 0.0, 0.0)
