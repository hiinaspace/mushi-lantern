extends Node3D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var staff := StaffTool.new()
	add_child(staff)
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	assert(staff.lantern != null)
	assert(staff.control_world_position().distance_to(staff.lantern.global_position) > 0.20)
	assert(staff.original_collision_layer == 4)
	assert(staff.picked_up_layer == 4)
	assert(staff.get_child_count() > 6)
	staff.lantern.set_shutter(0.35)
	staff.transfer(Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 0.0)), 2)
	assert(staff.placement == StaffTool.Placement.HELD)
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.35))
	staff.tracking_lost()
	assert(staff.placement == StaffTool.Placement.HELD)
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.35))
	staff.release_final()
	assert(staff.placement == StaffTool.Placement.FLOATING)
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.35))
	for frame: int in 100:
		staff.advance(1.0 / 60.0)
	assert(staff.placement == StaffTool.Placement.PARKED)
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.35))
	assert(staff.global_position.y > 0.7)
	assert(staff.lantern.forward_direction().y < -0.08)
	assert(staff.control_world_position().y < staff.lantern.global_position.y - 0.15)
	staff.begin_recall(Transform3D(Basis.IDENTITY, Vector3(3.0, 1.0, 0.0)))
	assert(staff.placement == StaffTool.Placement.RECALL_HOVER)
	staff.update_recall(Transform3D(Basis.IDENTITY, Vector3(3.0, 1.0, 0.0)), 0.5)
	assert(staff.global_position.x > 1.0)
	staff.end_recall()
	assert(staff.placement == StaffTool.Placement.FLOATING)
	for frame: int in 100:
		staff.advance(1.0 / 60.0)
	assert(staff.placement == StaffTool.Placement.PARKED)
	assert(staff.global_position.x > 1.0)
	# Full darkness survives an intentional release, parking, and recall.
	staff.lantern.set_shutter(0.0)
	staff.hold(Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 0.0)))
	staff.release_final()
	for frame: int in 100:
		staff.advance(1.0 / 60.0)
	assert(staff.placement == StaffTool.Placement.PARKED)
	assert(is_zero_approx(staff.lantern.shutter_openness))
	staff.begin_recall(Transform3D(Basis.IDENTITY, Vector3(2.0, 1.0, 0.0)))
	assert(is_zero_approx(staff.lantern.shutter_openness))
	staff.end_recall()
	staff.lantern.set_shutter(1.0)
	# Gravity straightens the hanging lantern after the shaft rolls.
	staff.reset_to_pose(Transform3D(Basis(Vector3.FORWARD, PI * 0.50), Vector3(0.0, 1.0, 0.0)))
	for frame: int in 90:
		staff.advance(1.0 / 60.0)
	assert((staff._swing.global_basis * Vector3.DOWN).dot(Vector3.DOWN) > 0.85)
	# Pitch and roll together require compensating for pitch in the roll angle.
	staff.reset_to_pose(Transform3D(Basis.from_euler(Vector3(deg_to_rad(80.0), 0.0, deg_to_rad(45.0))), Vector3(0.0, 1.0, 0.0)))
	for frame: int in 150:
		staff.advance(1.0 / 60.0)
	assert((staff._swing.global_basis * Vector3.DOWN).dot(Vector3.DOWN) > 0.92)
	# Equal sideways and forward waves should throw the lantern less sideways.
	var side_peak := _wave_peak(staff, Vector3.RIGHT)
	var forward_peak := _wave_peak(staff, Vector3.FORWARD)
	assert(side_peak < forward_peak * 0.8)
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), 1.0, false)
	staff.lantern.set_mode(LightField.Mode.CLEAR)
	staff.begin_adjust(Transform3D.IDENTITY)
	staff.update_adjust(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.01, 0.0)))
	assert(is_equal_approx(staff.lantern.shutter_openness, 1.0))
	staff.update_adjust(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.068, 0.0)))
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.4))
	# Pitching around an estimated wrist should leave both controls unchanged.
	var pitched := Basis(Vector3.RIGHT, 0.5)
	var pitch_wrist_offset_y: float = (pitched * Vector3(0.0, 0.0, StaffTool.WRIST_BACK_OFFSET_M)).y
	staff.update_adjust(Transform3D(pitched, Vector3(0.0, -0.068 - pitch_wrist_offset_y, 0.0)))
	assert(staff.lantern.mode == LightField.Mode.CLEAR)
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.4))
	var tilted := Basis(Vector3.UP, -0.5)
	var wrist_offset_y: float = (tilted * Vector3(0.0, 0.0, StaffTool.WRIST_BACK_OFFSET_M)).y
	staff.update_adjust(Transform3D(tilted, Vector3(0.0, -0.068 - wrist_offset_y, 0.0)))
	assert(staff.lantern.mode == LightField.Mode.ORANGE)
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.4))
	staff.update_adjust(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.068, 0.0)))
	assert(staff.lantern.mode == LightField.Mode.CLEAR)
	var blue_hand := Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.0, -0.068, 0.0))
	staff.update_adjust(blue_hand)
	assert(staff.lantern.mode == LightField.Mode.BLUE)
	var walked_and_turned := Transform3D(Basis(Vector3.UP, 0.4), Vector3(2.0, 0.3, -1.0))
	staff.global_transform = walked_and_turned * staff.global_transform
	staff.update_adjust(walked_and_turned * blue_hand)
	assert(staff.lantern.mode == LightField.Mode.BLUE)
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.4))
	staff.end_adjust()
	assert(staff.placement == StaffTool.Placement.PARKED)
	# A partial turn previews the filter but settles to the nearest center mode.
	staff.lantern.set_mode(LightField.Mode.CLEAR)
	staff.begin_adjust(Transform3D.IDENTITY)
	staff.update_adjust(Transform3D(Basis(Vector3.UP, 0.10), Vector3.ZERO))
	staff.end_adjust()
	assert(staff.lantern.mode == LightField.Mode.CLEAR)
	# A motionless adjustment preserves the selected filter.
	staff.lantern.set_mode(LightField.Mode.BLUE)
	staff.begin_adjust(Transform3D.IDENTITY)
	staff.end_adjust()
	assert(staff.lantern.mode == LightField.Mode.BLUE)
	staff.begin_adjust(Transform3D.IDENTITY)
	staff.update_adjust(Transform3D(Basis(Vector3.UP, -0.30), Vector3.ZERO))
	staff.end_adjust()
	assert(staff.lantern.mode == LightField.Mode.CLEAR)
	print("STAFF_TOOL_SMOKE_OK")
	get_tree().quit()

func _wave_peak(staff: StaffTool, direction: Vector3) -> float:
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	var peak := 0.0
	for frame: int in 45:
		var seconds := float(frame + 1) / 60.0
		var offset := direction * (0.05 * sin(TAU * 2.0 * seconds))
		staff.set_held_world_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0) + offset))
		staff.advance(1.0 / 60.0)
		peak = maxf(peak, absf(staff._swing_angle.y if direction == Vector3.RIGHT else staff._swing_angle.x))
	return peak
