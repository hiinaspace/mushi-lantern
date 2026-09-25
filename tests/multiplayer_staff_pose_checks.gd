extends Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var field := LightField.new()
	var staff_pose := Transform3D(Basis.IDENTITY, Vector3(2.4, 1.3, -2.8))
	field.update_transform(staff_pose * (StaffTool.SUSPENSION_PIVOT_LOCAL +
		Vector3.DOWN * StaffTool.SUSPENSION_LENGTH), Vector3.FORWARD)
	var identity := Transform3D.IDENTITY
	var packet := MultiplayerAvatarPose.append(MultiplayerLantern.encode(4, field), identity,
		identity, identity, identity, 0, 0.4, Vector3.ZERO)
	packet = MultiplayerStaffPose.append(packet, staff_pose, StaffTool.Placement.FLOATING)
	assert(packet.size() == MultiplayerStaffPose.BYTES)
	assert(not MultiplayerAvatarPose.decode(packet, 128).is_empty())
	var decoded := MultiplayerStaffPose.decode(packet, 128)
	assert(not decoded.is_empty())
	assert(decoded.pose.origin.is_equal_approx(staff_pose.origin))
	assert(int(decoded.placement) == StaffTool.Placement.FLOATING)
	assert(MultiplayerStaffPose.decode(packet.slice(0, packet.size() - 1), 128).is_empty())
	var visual := RemoteStaffVisual.new()
	add_child(visual)
	visual.apply_remote_pose(decoded.pose, field.source_position, field.source_direction, decoded.placement)
	assert(visual.lantern.global_position.distance_to(field.source_position) < 0.0001)
	assert(visual.lantern.forward_direction().dot(field.source_direction) > 0.999)
	assert(visual.global_position.is_equal_approx(staff_pose.origin))
	assert(visual.collision_layer == 0 and visual.collision_mask == 0)
	visual.free()
	print("MULTIPLAYER_STAFF_POSE_CHECKS PASS")
	get_tree().quit()
