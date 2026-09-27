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
	staff.update_desktop_adjust(Vector2(-80.0, -80.0))
	assert(staff.lantern.mode == LightField.Mode.BLUE)
	assert(staff.lantern.shutter_openness > 0.9)
	staff.update_desktop_adjust(Vector2(160.0, 160.0))
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
	staff.release_final()
	staff.begin_desktop_adjust()
	assert(not staff.desktop_is_adjusting())
	print("DESKTOP_LANTERN_ADJUST_OK")
	get_tree().quit()
