extends Node3D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var staff := StaffTool.new()
	add_child(staff)
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	assert(staff.desktop_can_control_lantern())
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
	assert(not staff.desktop_can_control_lantern())
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.35))
	for frame: int in 100:
		staff.advance(1.0 / 60.0)
	assert(staff.placement == StaffTool.Placement.PARKED)
	assert(not staff.desktop_can_control_lantern())
	assert(is_equal_approx(staff.lantern.shutter_openness, 0.35))
	assert(staff.global_position.y > 0.7)
	assert(absf(staff.lantern.forward_direction().y) < 0.08)
	assert(staff.control_world_position().y < staff.lantern.global_position.y - 0.15)
	staff.begin_recall(Transform3D(Basis.IDENTITY, Vector3(3.0, 1.0, 0.0)))
	assert(staff.placement == StaffTool.Placement.RECALL_HOVER)
	assert(not staff.desktop_can_control_lantern())
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
	# Gravity keeps the bob below the pivot regardless of shaft roll.
	staff.reset_to_pose(Transform3D(Basis(Vector3.FORWARD, PI * 0.50), Vector3(0.0, 1.0, 0.0)))
	for frame: int in 90:
		staff.advance(1.0 / 60.0)
	assert((staff._swing.global_basis * Vector3.DOWN).dot(Vector3.DOWN) > 0.85)
	# Pitch and roll together cannot move the world-space bob.
	staff.reset_to_pose(Transform3D(Basis.from_euler(Vector3(deg_to_rad(80.0), 0.0, deg_to_rad(45.0))), Vector3(0.0, 1.0, 0.0)))
	for frame: int in 150:
		staff.advance(1.0 / 60.0)
	assert((staff._swing.global_basis * Vector3.DOWN).dot(Vector3.DOWN) > 0.92)
	# Equal sideways and forward pivot traces have the same response.
	var side_peak := _wave_peak(staff, Vector3.RIGHT)
	var forward_peak := _wave_peak(staff, Vector3.FORWARD)
	assert(side_peak > 0.01 and forward_peak > 0.01)
	assert(absf(side_peak - forward_peak) < maxf(side_peak, forward_peak) * 0.12)
	# Walking may kick the lantern at startup, but constant velocity must not
	# leave it tilted as if the hand were accelerating forever.
	var walk_60 := _locomotion_profile(staff, 60)
	var walk_90 := _locomotion_profile(staff, 90)
	print("STAFF_WALK peak60=%.4f steady60=%.4f peak90=%.4f steady90=%.4f" % [walk_60.x, walk_60.y, walk_90.x, walk_90.y])
	assert(walk_60.x > 0.02 and walk_90.x > 0.02)
	assert(walk_60.x < 0.12 and walk_90.x < 0.12)
	assert(walk_60.y < 0.02 and walk_90.y < 0.02)
	assert(absf(walk_60.y - walk_90.y) < 0.01)
	# XR locomotion moves XROrigin and tracked controllers together. That shared
	# translation should carry the tool without swinging the lantern, including
	# acceleration and stopping; hand motion relative to the rig remains physical.
	var xr_walk := _xr_locomotion_profile(staff, 90)
	print("STAFF_XR_WALK peak=%.4f steady=%.4f stopped=%.4f" % [xr_walk.x, xr_walk.y, xr_walk.z])
	assert(xr_walk.x < 0.01)
	assert(xr_walk.y < 0.01)
	assert(xr_walk.z < 0.01)
	var xr_wave := _xr_hand_wave_peak(staff)
	assert(xr_wave > 0.01)
	# Pure shaft yaw about the suspension point turns the beam without kicking the bob.
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	var pivot := staff._swing.global_position
	var bob_before := staff._bob_world
	var yaw_basis := Basis(Vector3.UP, 0.8)
	var yaw_origin := pivot - yaw_basis * StaffTool.SUSPENSION_PIVOT_LOCAL
	staff.set_held_world_pose(Transform3D(yaw_basis, yaw_origin))
	staff.advance(1.0 / 60.0)
	assert(staff._bob_world.distance_to(bob_before) < 0.002)
	assert(staff.lantern.forward_direction().dot(Vector3.FORWARD) < 0.8)
	# A two-hand solve can roll the shaft through horizontal. Its +Y axis then
	# changes hemispheres, but the staff front and beam must stay forward.
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	for roll: float in [-0.5, 0.5]:
		staff.set_held_world_pose(Transform3D(Basis(Vector3.FORWARD, roll), Vector3(0.0, 1.0, 0.0)))
		staff.advance(1.0 / 60.0)
		assert(staff.lantern.forward_direction().dot(Vector3.FORWARD) > 0.97)
	# Flight heading follows the viewer even when the two-hand shaft solve
	# reverses. A pendulum aligned with the beam cannot flip the lantern back.
	staff.set_flight_aim(true, Vector3.RIGHT)
	staff._bob_world = staff._swing.global_position + Vector3.RIGHT * StaffTool.SUSPENSION_LENGTH
	staff._orient_swing(staff._swing.global_position, 1.0 / 90.0)
	assert(staff.lantern.forward_direction().dot(Vector3.RIGHT) > 0.999)
	assert(staff._swing.global_basis.is_finite())
	staff.set_flight_aim(true, Vector3(0.0, 1.0, 0.0))
	staff._orient_swing(staff._swing.global_position, 1.0 / 90.0)
	assert(staff.lantern.forward_direction().dot(Vector3.RIGHT) > 0.999)
	staff.set_flight_aim(false, Vector3.ZERO)
	staff._bob_world = staff._swing.global_position + Vector3.DOWN * StaffTool.SUSPENSION_LENGTH
	staff._orient_swing(staff._swing.global_position, 1.0 / 90.0)
	assert(staff.lantern.forward_direction().dot(Vector3.RIGHT) > 0.98)
	for frame: int in 90:
		staff._orient_swing(staff._swing.global_position, 1.0 / 90.0)
	assert(staff.lantern.forward_direction().dot(Vector3.FORWARD) > 0.97)
	# Desktop camera yaw moves the staff on an orbit around the head. That
	# apparent pivot travel must not kick the pendulum as if the player ran.
	var raw_yaw_kick := _camera_yaw_peak_velocity(staff, false)
	var compensated_yaw_kick := _camera_yaw_peak_velocity(staff, true)
	print("STAFF_YAW raw=%.4f compensated=%.4f" % [raw_yaw_kick, compensated_yaw_kick])
	assert(raw_yaw_kick > 0.5)
	assert(compensated_yaw_kick < raw_yaw_kick * 0.25)
	# Even a 45-degree frame step must not trip the large-pivot reset guard.
	assert(_rapid_camera_yaw_sim_motion(staff) < 0.002)
	# A moving pivot settles back to a vertical hang without parked pitch.
	_wave_peak(staff, Vector3.RIGHT)
	for frame: int in 240:
		staff.advance(1.0 / 60.0)
	assert(staff._bob_world.distance_to(staff._swing.global_position + Vector3.DOWN * StaffTool.SUSPENSION_LENGTH) < 0.025)
	# A tracking jump and recall never leave a huge or non-finite pendulum state.
	staff.set_held_world_pose(Transform3D(Basis.IDENTITY, Vector3(50.0, 2.0, -30.0)))
	staff.advance(1.0 / 60.0)
	assert(_finite_swing(staff))
	assert(staff._bob_velocity.length() < 0.1)
	staff.release_final()
	staff.begin_recall(Transform3D(Basis.IDENTITY, Vector3(-20.0, 1.0, 12.0)))
	for frame: int in 60:
		staff.update_recall(Transform3D(Basis.IDENTITY, Vector3(-20.0, 1.0, 12.0)), 1.0 / 60.0)
		staff.advance(1.0 / 60.0)
		assert(_finite_swing(staff))
	staff.end_recall()
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), 1.0, false)
	staff.lantern.set_mode(LightField.Mode.CLEAR)
	staff.begin_adjust(Transform3D.IDENTITY)
	var held_bob_offset := staff._bob_world - staff._swing.global_position
	staff.global_position += Vector3(0.08, 0.0, 0.0)
	staff.advance(1.0 / 60.0)
	assert((staff._bob_world - staff._swing.global_position).distance_to(held_bob_offset) < 0.002)
	assert(staff._bob_velocity.length() < 0.001)
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
	# One uninterrupted grip must keep sweeping through both filter boundaries.
	staff.lantern.set_mode(LightField.Mode.BLUE)
	staff.begin_adjust(Transform3D.IDENTITY)
	staff.update_adjust(Transform3D(Basis(Vector3.UP, -0.50), Vector3.ZERO))
	assert(staff.lantern.mode == LightField.Mode.CLEAR and staff.lantern._dial_preview_active,
		"First detent must not end the held dial preview")
	staff.update_adjust(Transform3D(Basis(Vector3.UP, -0.80), Vector3.ZERO))
	assert(staff.lantern._dial_preview > 0.1 and staff.lantern._dial_preview_active
		and staff.lantern._dial_preview_amount > 0.0 and staff.lantern._dial_preview_amount < 1.0,
		"Continued twist must sweep the second filter rather than snap")
	staff.update_adjust(Transform3D(Basis(Vector3.UP, -1.20), Vector3.ZERO))
	assert(staff.lantern.mode == LightField.Mode.ORANGE and staff.lantern._dial_preview_active,
		"The second detent must retain preview until grip release")
	staff.end_adjust()
	assert(not staff.lantern._dial_preview_active)
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
		var offset_from_vertical := staff._bob_world - staff._swing.global_position - Vector3.DOWN * StaffTool.SUSPENSION_LENGTH
		peak = maxf(peak, absf(offset_from_vertical.dot(direction)))
	return peak

func _locomotion_profile(staff: StaffTool, fps: int) -> Vector2:
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	var dt := 1.0 / float(fps)
	var distance := 0.0
	var peak := 0.0
	for frame: int in fps * 3:
		var step_distance := 1.8 * dt
		distance += step_distance
		staff.set_held_world_pose(Transform3D(Basis.IDENTITY, Vector3(distance, 1.0, 0.0)))
		staff.advance(dt)
		peak = maxf(peak, absf(staff._bob_world.x - staff._swing.global_position.x))
	return Vector2(peak, absf(staff._bob_world.x - staff._swing.global_position.x))

func _xr_locomotion_profile(staff: StaffTool, fps: int) -> Vector3:
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	staff.set_xr_rig_reference(Transform3D.IDENTITY)
	var dt := 1.0 / float(fps)
	var distance := 0.0
	var moving_peak := 0.0
	for frame: int in fps * 2:
		distance += 1.8 * dt
		var rig := Transform3D(Basis.IDENTITY, Vector3(distance, 0.0, 0.0))
		# main currently calls this every XR physics tick; clearing an already
		# inactive desktop reference must not rebase the swing simulation.
		staff.clear_desktop_yaw_reference()
		staff.set_xr_rig_reference(rig)
		staff.set_held_world_pose(Transform3D(Basis.IDENTITY, Vector3(distance, 1.0, 0.0)))
		staff.advance(dt)
		moving_peak = maxf(moving_peak, absf(staff._bob_world.x - staff._swing.global_position.x))
	var stopped_peak := 0.0
	for frame: int in fps:
		staff.clear_desktop_yaw_reference()
		staff.set_xr_rig_reference(Transform3D(Basis.IDENTITY, Vector3(distance, 0.0, 0.0)))
		staff.set_held_world_pose(Transform3D(Basis.IDENTITY, Vector3(distance, 1.0, 0.0)))
		staff.advance(dt)
		stopped_peak = maxf(stopped_peak, absf(staff._bob_world.x - staff._swing.global_position.x))
	return Vector3(moving_peak, absf(staff._bob_world.x - staff._swing.global_position.x), stopped_peak)

func _xr_hand_wave_peak(staff: StaffTool) -> float:
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	staff.set_xr_rig_reference(Transform3D.IDENTITY)
	var peak := 0.0
	for frame: int in 45:
		var seconds := float(frame + 1) / 60.0
		var offset := Vector3.RIGHT * (0.05 * sin(TAU * 2.0 * seconds))
		staff.clear_desktop_yaw_reference()
		staff.set_xr_rig_reference(Transform3D.IDENTITY)
		staff.set_held_world_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0) + offset))
		staff.advance(1.0 / 60.0)
		peak = maxf(peak, absf(staff._bob_world.x - staff._swing.global_position.x))
	return peak

func _camera_yaw_peak_velocity(staff: StaffTool, compensate: bool) -> float:
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	var head_origin := Vector3.ZERO
	var peak := 0.0
	if not compensate:
		staff.clear_desktop_yaw_reference()
	for frame: int in 24:
		var yaw := TAU * 0.75 * float(frame + 1) / 24.0
		var camera_basis := Basis(Vector3.UP, yaw)
		var camera_pose := Transform3D(camera_basis, head_origin)
		if compensate:
			staff.set_desktop_yaw_reference(camera_pose)
		var staff_pose := Transform3D(camera_basis, head_origin + camera_basis * Vector3(0.56, -0.06, -0.72))
		staff.set_held_world_pose(staff_pose)
		staff.advance(1.0 / 60.0)
		peak = maxf(peak, staff._bob_velocity.length())
	return peak

func _rapid_camera_yaw_sim_motion(staff: StaffTool) -> float:
	staff.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	var peak := 0.0
	for frame: int in 6:
		var yaw := TAU * 0.75 * float(frame + 1) / 6.0
		var camera_basis := Basis(Vector3.UP, yaw)
		staff.set_desktop_yaw_reference(Transform3D(camera_basis, Vector3.ZERO))
		staff.set_held_world_pose(Transform3D(camera_basis, camera_basis * Vector3(0.56, -0.06, -0.72)))
		var prior_sim_pivot := staff._swing_sim_pivot
		staff.advance(1.0 / 60.0)
		peak = maxf(peak, staff._swing_sim_pivot.distance_to(prior_sim_pivot))
		assert(_finite_swing(staff))
	return peak

func _finite_swing(staff: StaffTool) -> bool:
	for value: float in [staff._bob_world.x, staff._bob_world.y, staff._bob_world.z, staff._bob_velocity.x, staff._bob_velocity.y, staff._bob_velocity.z]:
		if not is_finite(value):
			return false
	return absf(staff._bob_world.distance_to(staff._swing.global_position) - StaffTool.SUSPENSION_LENGTH) < 0.002
