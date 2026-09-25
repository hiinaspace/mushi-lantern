extends SceneTree

func _initialize() -> void:
	var field := LightField.new()
	field.update_transform(Vector3(1, 2, 3), Vector3.FORWARD)
	var body := Transform3D(Basis.from_euler(Vector3(0, 0.3, 0)), Vector3(4, 1, 5))
	var head := Transform3D(Basis.from_euler(Vector3(0.2, 0.4, 0)), Vector3(4, 2.5, 5))
	var left := Transform3D(Basis.IDENTITY, Vector3(3.7, 2, 4.7))
	var right := Transform3D(Basis.IDENTITY, Vector3(4.3, 2, 4.7))
	var fingers: Array[Quaternion] = []
	for i in range(30):
		fingers.append(Quaternion(Vector3.RIGHT, float(i) * 0.01))
	var masks := PackedInt32Array([0x7fff, 0x7fff])
	var curls := PackedFloat32Array([0.2, 0.8, 0.4, 0.4, 0.4, 0.2, 0.8, 0.4, 0.4, 0.4])
	var bytes := MultiplayerAvatarPose.append(MultiplayerLantern.encode(17, field),
		body, head, left, right, 7, 0.45, Vector3(1, 0, -2), 1.6, fingers, masks, curls)
	assert(bytes.size() == MultiplayerAvatarPose.BYTES)
	assert(int(MultiplayerLantern.decode(bytes, 128).sequence) == 17)
	var pose := MultiplayerAvatarPose.decode(bytes, 128)
	assert(pose.tracking == 7)
	assert((pose.body.origin - body.origin).length() < 0.001)
	assert((pose.head.basis.get_rotation_quaternion().normalized().dot(head.basis.get_rotation_quaternion())) > 0.999)
	assert((pose.velocity - Vector3(1, 0, -2)).length() < 0.001)
	assert(absf(float(pose.hue) - 0.45) < 0.005)
	assert(absf(float(pose.eye_height) - 1.6) < 0.005)
	assert(pose.masks == masks)
	assert(pose.fingers.size() == 30)
	assert(absf(pose.fingers[12].dot(fingers[12])) > 0.999)
	assert(absf(pose.curls[1] - 0.8) < 0.005)
	assert(absf(pose.arm_reach - 1.3) < 0.005)
	bytes.encode_float(MultiplayerAvatarPose.OFFSET + 4, INF)
	assert(MultiplayerAvatarPose.decode(bytes, 128).is_empty())
	print("PASS multiplayer avatar pose codec")
	quit()
