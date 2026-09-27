extends Node3D

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var staff := StaffTool.new()
	add_child(staff)
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	staff.lantern.set_mode(LightField.Mode.CLEAR)
	staff.lantern.set_shutter(0.5)
	staff.begin_desktop_adjust()
	assert(staff.desktop_is_adjusting())
	staff.update_desktop_adjust(Vector2(-28.0, -80.0))
	assert(staff.lantern.mode == LightField.Mode.CLEAR)
	staff.update_desktop_adjust(Vector2(-82.0, 0.0))
	assert(staff.lantern.mode == LightField.Mode.BLUE)
	assert(staff.lantern.shutter_openness > 0.9)
	staff.update_desktop_adjust(Vector2(220.0, 160.0))
	assert(staff.lantern.mode == LightField.Mode.ORANGE)
	assert(staff.lantern.shutter_openness < 0.1)
	staff.end_desktop_adjust()
	assert(not staff.desktop_is_adjusting())
	assert(staff.lantern.mode == LightField.Mode.ORANGE)
	staff.lantern.set_shutter(1.0)
	staff.begin_desktop_adjust()
	staff.update_desktop_adjust(Vector2(-220.0, 170.0), false)
	assert(staff.lantern.mode == LightField.Mode.BLUE)
	assert(is_equal_approx(staff.lantern.shutter_openness, 1.0))
	staff.end_desktop_adjust()
	assert(staff.find_child("ControlGripPulse", true, false) == null)
	var player := DesktopPlayer.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	player.add_child(camera)
	add_child(player)
	player.staff_adjust_blend = 0.0
	var resting := player.staff_hold_transform(Vector2.ZERO)
	player.staff_adjust_blend = 1.0
	var drawn_in := player.staff_hold_transform(Vector2.ZERO, true)
	# The suspended control sits ahead of the shaft and must come inward when
	# the right hand turns the shaft for the offhand reach.
	var control_offset := StaffTool.SUSPENSION_PIVOT_LOCAL + Vector3(0.0,
		-StaffTool.SUSPENSION_LENGTH - 0.29, 0.0)
	var resting_control := resting * control_offset
	var drawn_control := drawn_in * control_offset
	var camera_right := player.camera.global_basis.x
	assert((drawn_control - resting_control).dot(camera_right) < -0.07)
	staff.release_final()
	staff.begin_desktop_adjust()
	assert(not staff.desktop_is_adjusting())
	print("DESKTOP_LANTERN_ADJUST_OK")
	get_tree().quit()
