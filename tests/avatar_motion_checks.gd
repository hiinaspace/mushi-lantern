extends SceneTree

func _initialize() -> void:
	var avatar := MushiMultiplayerAvatar.new()
	get_root().add_child.call_deferred(avatar)
	await process_frame
	assert(avatar.skeleton != null)
	avatar.configure(0.0, true)
	var vrm_nodes := avatar.body.find_children("*", "Node3D", true, false)
	var centered := false
	for node in vrm_nodes:
		if node is VRMTopLevel:
			centered = node.override_springbone_center and node.default_springbone_center == avatar._spring_center
	assert(centered)
	print("UKON_AUTHORED_EYE_HEIGHT=%.4f" % avatar.get_authored_eye_height())
	var left_hand := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone("LeftHand")).origin
	var right_hand := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone("RightHand")).origin
	print("UKON_REST_WRIST_SPAN=%.4f" % left_hand.distance_to(right_hand))
	assert(avatar.finger_modifier.bones.filter(func(b: int) -> bool: return b >= 0).size() == 28)
	assert(avatar.leg_modifiers.size() == 2 and avatar.placement != null)
	var span := left_hand.distance_to(right_hand)
	avatar.set_arm_reach_scale(1.0)
	var base_span := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone("LeftHand")).origin.distance_to(
		avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone("RightHand")).origin)
	assert(base_span < span)
	avatar.set_arm_reach_scale(1.3)
	assert(is_equal_approx(avatar.arm_modifiers[0].leaf.origin.length(),
		avatar.skeleton.get_bone_rest(avatar.skeleton.find_bone("LeftHand")).origin.length()))
	assert(avatar.skeleton.get_bone_pose_position(avatar.skeleton.find_bone("RightHand")).is_equal_approx(
		avatar.skeleton.get_bone_rest(avatar.skeleton.find_bone("RightHand")).origin))
	avatar.set_player_eye_height(1.6)
	assert(absf(avatar.model_scale - 1.0) < 0.001)
	var view := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	var body := Transform3D.IDENTITY
	avatar.apply_pose(body, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 0, Vector3.ZERO, 0.016)
	assert(not avatar.arm_modifiers[0].active and not avatar.arm_modifiers[1].active)
	var leg = avatar._leg_animation
	assert(leg != null)
	for key in leg.ANIMATIONS:
		var anim_name: StringName = leg.ANIMATIONS[key]
		assert(leg._source_player.get_animation(anim_name).loop_mode == Animation.LOOP_LINEAR)
	avatar.apply_pose(body, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 0, Vector3.FORWARD * 2.0, 0.016)
	var anim: Animation = leg._source_player.get_animation(&"UnarmedRunForward")
	var sk := leg._source_skeleton as Skeleton3D
	var calf := sk.find_bone("B_L_Calf")
	leg._source_player.play(&"UnarmedRunForward")
	leg._source_player.seek(0.1, true)
	leg._source_player.advance(0.0)
	var early := sk.get_bone_pose(calf).basis
	leg._source_player.seek(0.1 + anim.length, true)
	leg._source_player.advance(0.0)
	var cycled := sk.get_bone_pose(calf).basis
	assert(early.is_equal_approx(cycled))
	avatar.apply_pose(body, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 4,
		Vector3.ZERO, 0.016)
	assert(not avatar.arm_modifiers[0].active and not avatar.arm_modifiers[1].active)
	avatar.apply_pose(body, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 7,
		Vector3.ZERO, 0.016)
	assert(avatar.arm_modifiers[0].active and avatar.arm_modifiers[1].active)
	for i in range(2):
		var wrist := avatar.hand_targets[i].global_basis.orthonormalized()
		assert(wrist.y.dot(Vector3.FORWARD) > 0.99)
		assert(wrist.z.dot(Vector3.RIGHT if i == 0 else Vector3.LEFT) > 0.99)
		assert(is_equal_approx(wrist.determinant(), 1.0))
	avatar.apply_pose(body, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 2,
		Vector3.ZERO, 0.016)
	var desktop_wrist := avatar.hand_targets[1].global_basis.orthonormalized()
	assert(desktop_wrist.y.dot(Vector3.FORWARD) > 0.99)
	assert(desktop_wrist.z.dot(Vector3.LEFT) > 0.99)
	avatar.apply_fingers([], PackedInt32Array([0, 0]), PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	assert(avatar.finger_modifier.curls[6] > 0.8)
	avatar.apply_pose(body, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 18,
		Vector3.ZERO, 0.016)
	avatar.apply_fingers([], PackedInt32Array([0, 0]), PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	assert(avatar.finger_modifier.curls[6] == 0.0)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.2, 8.0)
	shape.shape = box
	floor.position.y = -0.1
	floor.add_child(shape)
	get_root().add_child(floor)
	avatar.apply_pose(body, Transform3D(Basis.IDENTITY, Vector3(0.2, avatar.get_authored_eye_height(), 0)),
		Transform3D.IDENTITY, Transform3D.IDENTITY, 0, Vector3.ZERO, 0.016)
	for frame in range(5):
		await physics_frame
	assert(avatar.leg_modifiers[0].active and avatar.leg_modifiers[1].active)
	assert(avatar.placement.target_foot_is_valid)
	assert(avatar.placement.left_ground != null or avatar.placement.right_ground != null)
	for frame in range(10):
		avatar._update_foot_plant_weight(0.016)
	assert(avatar.leg_modifiers[0].influence > 0.5)
	avatar.apply_pose(body, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 0,
		Vector3.FORWARD * 2.0, 0.016)
	avatar._update_foot_plant_weight(0.016)
	assert(avatar.leg_modifiers[0].active and avatar.leg_modifiers[0].influence > 0.0)
	assert(avatar.foot_targets[0].global_position.is_finite())
	assert(avatar.foot_targets[1].global_position.is_finite())
	print("PASS avatar loop, untracked arm animation, spring center, XR palm basis")
	quit()
