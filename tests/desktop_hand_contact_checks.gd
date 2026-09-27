extends Node3D

var _avatar: MushiMultiplayerAvatar
var _wrist := Vector3.ZERO
var _left_wrist := Vector3.ZERO

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var player := DesktopPlayer.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	player.add_child(camera)
	add_child(player)
	player.set_physics_process(false)
	camera.position.y = 1.6
	camera.current = true
	camera.near = 0.025
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(25.0), 0.0)
	light.light_energy = 2.0
	add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("263242")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d4dcff")
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	player.staff_adjust_blend = 1.0
	var staff := StaffTool.new()
	add_child(staff)
	var staff_pose := player.staff_hold_transform(Vector2.ZERO, true)
	if not OS.get_environment("MUSHI_STAFF_Z_OFFSET").is_empty():
		staff_pose.origin += camera.global_basis * Vector3(0.0, 0.0, float(OS.get_environment("MUSHI_STAFF_Z_OFFSET")))
	staff.set_held_world_pose(staff_pose)
	for frame in range(30):
		staff.advance(1.0 / 60.0)
	var target := staff.grip_world_position(staff.grip_index)
	_avatar = MushiMultiplayerAvatar.new()
	add_child(_avatar)
	_avatar.configure(0.0, true)
	if not OS.get_environment("MUSHI_DESKTOP_REACH_SCALE").is_empty():
		_avatar.set_arm_reach_scale(float(OS.get_environment("MUSHI_DESKTOP_REACH_SCALE")))
	_avatar.skeleton.skeleton_updated.connect(_capture)
	var right := Transform3D(staff.global_basis, target)
	for frame in range(12):
		_avatar.apply_pose(player.global_transform, camera.global_transform,
			Transform3D.IDENTITY, right, 2, Vector3.ZERO, 1.0 / 60.0)
		await get_tree().process_frame
		await get_tree().physics_frame
	var distance := _wrist.distance_to(target)
	print("DESKTOP_HAND_CONTACT wrist_error=%.4f target=%s wrist=%s" % [distance, target, _wrist])
	assert(distance < 0.08)
	if not OS.get_environment("MUSHI_DESKTOP_CAPTURE").is_empty():
		await _capture_pose(staff, player, camera, 0.5, false, "/tmp/mushi-desktop-reach-mid.png")
		await _capture_pose(staff, player, camera, 1.0, true, "/tmp/mushi-desktop-reach-settled.png")
		var contact_camera := Camera3D.new()
		contact_camera.position = Vector3(0.9, 1.52, 0.75)
		contact_camera.fov = 58.0
		add_child(contact_camera)
		contact_camera.look_at(Vector3(0.05, 1.18, -0.10))
		contact_camera.make_current()
		await _capture_pose(staff, player, camera, 0.5, false, "/tmp/mushi-desktop-contact-mid.png")
		await _capture_pose(staff, player, camera, 1.0, true, "/tmp/mushi-desktop-contact-settled.png")
	get_tree().quit()

func _capture_pose(staff: StaffTool, player: DesktopPlayer, camera: Camera3D,
		reach: float, closed: bool, path: String) -> void:
	var rest := camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.28, -0.58, -0.34))
	var control := Transform3D(staff.lantern.global_basis, staff.control_world_position())
	var left := rest.interpolate_with(control, reach)
	var right := Transform3D(staff.global_basis, staff.grip_world_position(staff.grip_index))
	var curls := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	if closed:
		curls = PackedFloat32Array([0.65, 0.85, 0.9, 0.9, 0.8, 0, 0, 0, 0, 0])
	for frame in range(12):
		_avatar.apply_pose(player.global_transform, camera.global_transform, left, right,
			3, Vector3.ZERO, 1.0 / 60.0)
		_avatar.apply_fingers([], PackedInt32Array([0, 0]), curls)
		await get_tree().process_frame
		await get_tree().physics_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	assert(err == OK)
	print("DESKTOP_HAND_CAPTURE %s left_contact_error=%.4f target=%s wrist=%s" % [path,
		_left_wrist.distance_to(staff.control_world_position()), staff.control_world_position(), _left_wrist])

func _capture() -> void:
	if _avatar == null or _avatar.skeleton == null:
		return
	var bone := _avatar.skeleton.find_bone("RightHand")
	if bone >= 0:
		_wrist = (_avatar.skeleton.global_transform * _avatar.skeleton.get_bone_global_pose(bone)).origin
	bone = _avatar.skeleton.find_bone("LeftHand")
	if bone >= 0:
		_left_wrist = (_avatar.skeleton.global_transform * _avatar.skeleton.get_bone_global_pose(bone)).origin
