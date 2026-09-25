extends Node3D

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var remote := RemoteStaffVisual.new()
	add_child(remote)
	var initial_staff := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, 0.0))
	var initial_lamp := initial_staff * (StaffTool.SUSPENSION_PIVOT_LOCAL + Vector3.DOWN * StaffTool.SUSPENSION_LENGTH)
	remote.apply_remote_pose(initial_staff, initial_lamp, Vector3.FORWARD, StaffTool.Placement.HELD)
	assert(remote.lantern.global_position.distance_to(initial_lamp) < 0.001,
		"first remote pose places lamp under crook")
	var moved_staff := Transform3D(Basis.IDENTITY, Vector3(0.4, 1.3, 0.0))
	var moved_lamp := moved_staff * (StaffTool.SUSPENSION_PIVOT_LOCAL + Vector3.DOWN * StaffTool.SUSPENSION_LENGTH)
	remote.apply_remote_pose(moved_staff, moved_lamp, Vector3.FORWARD, StaffTool.Placement.HELD)
	var before := remote.lantern.global_position
	remote.advance_remote(1.0 / 60.0)
	assert(remote.global_position.x > 0.0 and remote.global_position.x < moved_staff.origin.x,
		"staff interpolates between network samples")
	assert(remote.lantern.global_position.distance_to(before) > 0.0001,
		"lamp predicts motion before next authoritative sample")
	assert(remote._swing.global_position.distance_to(remote.to_global(StaffTool.SUSPENSION_PIVOT_LOCAL)) < 0.001,
		"suspension cord remains attached to staff crook")
	for i in 240:
		remote.advance_remote(1.0 / 60.0)
	assert(remote.lantern.global_position.distance_to(moved_lamp) < 0.03,
		"idle visual lamp converges to authoritative packet position")
	remote.free()
	print("REMOTE_STAFF_VISUAL_OK")
	get_tree().quit()
