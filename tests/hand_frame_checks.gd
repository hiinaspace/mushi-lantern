extends SceneTree

func _initialize() -> void:
	var avatar := MushiMultiplayerAvatar.new()
	root.add_child.call_deferred(avatar)
	_check.call_deferred(avatar)

func _check(avatar: MushiMultiplayerAvatar) -> void:
	for side in ["Left", "Right"]:
		var xr_scene_path := "res://addons/godot-xr-tools/hands/scenes/lowpoly/%s_hand_low.tscn" % side.to_lower()
		var xr_hand := (load(xr_scene_path) as PackedScene).instantiate()
		var xr_skeleton := xr_hand.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var xr_suffix := "_L" if side == "Left" else "_R"
		var ukon_hand_rest := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(side + "Hand"))
		var xr_wrist_rest := xr_skeleton.get_bone_global_rest(xr_skeleton.find_bone("Wrist" + xr_suffix))
		var ukon_middle := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(side + "MiddleProximal")).origin
		var xr_middle := xr_skeleton.get_bone_global_rest(xr_skeleton.find_bone("Middle_Proximal" + xr_suffix)).origin
		var ukon_forward := ukon_hand_rest.basis.inverse() * (ukon_middle - ukon_hand_rest.origin).normalized()
		var xr_forward := xr_wrist_rest.basis.inverse() * (xr_middle - xr_wrist_rest.origin).normalized()
		var correction := MushiHandPose.xr_wrist_to_ukon(side == "Left")
		assert((correction * ukon_forward).dot(xr_forward) > 0.95)
		var ukon_index := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(side + "IndexProximal")).origin
		var ukon_little := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(side + "LittleProximal")).origin
		var xr_index := xr_skeleton.get_bone_global_rest(xr_skeleton.find_bone("Index_Proximal" + xr_suffix)).origin
		var xr_little := xr_skeleton.get_bone_global_rest(xr_skeleton.find_bone("Little_Proximal" + xr_suffix)).origin
		var ukon_side := ukon_hand_rest.basis.inverse() * (ukon_index - ukon_little).normalized()
		var xr_side := xr_wrist_rest.basis.inverse() * (xr_index - xr_little).normalized()
		assert((correction * ukon_side).dot(xr_side) > 0.9)
		xr_hand.free()
	print("HAND_FRAME_CHECKS_OK")
	quit()
