class_name MultiplayerAvatarPose
extends RefCounted

## Optional pose tail on a lantern datagram. The transport's peer ID owns both
## records, so a lamp and its avatar cannot be attributed to different people.
const OFFSET := MultiplayerLantern.BYTES
const VERSION := 3
const BASE_BYTES := OFFSET + 4 + 4 * 28 + 8
const V2_BYTES := BASE_BYTES + 4 + 30 * 8 + 10
const BYTES := V2_BYTES + 1


static func append(lantern_bytes: PackedByteArray, body: Transform3D, head: Transform3D,
		left: Transform3D, right: Transform3D, tracking: int, hue: float,
		velocity: Vector3, eye_height: float = 1.6, fingers: Array[Quaternion] = [],
		masks: PackedInt32Array = PackedInt32Array([0, 0]),
		curls: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
		arm_reach: float = 1.3) -> PackedByteArray:
	if lantern_bytes.size() != OFFSET:
		return lantern_bytes
	var bytes := lantern_bytes.duplicate()
	bytes.resize(BYTES)
	bytes.encode_u8(OFFSET, VERSION)
	bytes.encode_u8(OFFSET + 1, tracking & 31)
	bytes.encode_u8(OFFSET + 2, roundi(fposmod(hue, 1.0) * 255.0))
	bytes.encode_u8(OFFSET + 3, roundi((clampf(eye_height, 1.1, 2.1) - 1.1) * 255.0))
	var transforms := [body, head, left, right]
	for index: int in transforms.size():
		var pose: Transform3D = transforms[index]
		var p := pose.origin
		var q := pose.basis.orthonormalized().get_rotation_quaternion()
		var at := OFFSET + 4 + index * 28
		bytes.encode_float(at, p.x)
		bytes.encode_float(at + 4, p.y)
		bytes.encode_float(at + 8, p.z)
		bytes.encode_float(at + 12, q.x)
		bytes.encode_float(at + 16, q.y)
		bytes.encode_float(at + 20, q.z)
		bytes.encode_float(at + 24, q.w)
	bytes.encode_float(BASE_BYTES - 8, velocity.x)
	bytes.encode_float(BASE_BYTES - 4, velocity.z)
	var finger_at := BASE_BYTES
	for side in range(2):
		bytes.encode_u16(finger_at + side * 2, (masks[side] if masks.size() == 2 else 0) & 0x7fff)
	finger_at += 4
	for i in range(30):
		var q := fingers[i].normalized() if fingers.size() == 30 and fingers[i].is_finite() else Quaternion.IDENTITY
		for component in [q.x, q.y, q.z, q.w]:
			bytes.encode_s16(finger_at, roundi(clampf(component, -1.0, 1.0) * 32767.0))
			finger_at += 2
	for i in range(10):
		bytes.encode_u8(finger_at + i, roundi(clampf(curls[i] if curls.size() == 10 else 0.0, 0.0, 1.0) * 255.0))
	bytes.encode_u8(V2_BYTES, roundi((clampf(arm_reach, 0.9, 1.5) - 0.9) / 0.6 * 255.0))
	return bytes


static func decode(bytes: PackedByteArray, terrain_size: int) -> Dictionary:
	if bytes.size() < BASE_BYTES or bytes.decode_u8(OFFSET) not in [1, 2, VERSION]:
		return {}
	var version := bytes.decode_u8(OFFSET)
	if version >= 2 and bytes.size() < (BYTES if version == VERSION else V2_BYTES):
		return {}
	var poses: Array[Transform3D] = []
	for index: int in 4:
		var at := OFFSET + 4 + index * 28
		var position := Vector3(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8))
		var q := Quaternion(bytes.decode_float(at + 12), bytes.decode_float(at + 16),
			bytes.decode_float(at + 20), bytes.decode_float(at + 24))
		var bound := float(terrain_size) * 0.6
		if not position.is_finite() or absf(position.x) > bound or absf(position.z) > bound \
				or position.y < -8.0 or position.y > 100.0 or not q.is_finite() \
				or q.length_squared() < 0.5 or q.length_squared() > 1.5:
			return {}
		poses.append(Transform3D(Basis(q.normalized()), position))
	var velocity := Vector3(bytes.decode_float(BASE_BYTES - 8), 0.0, bytes.decode_float(BASE_BYTES - 4))
	if not velocity.is_finite() or velocity.length_squared() > 100.0:
		return {}
	var fingers: Array[Quaternion] = []
	var masks := PackedInt32Array([0, 0])
	var curls := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	if version >= 2:
		masks[0] = bytes.decode_u16(BASE_BYTES)
		masks[1] = bytes.decode_u16(BASE_BYTES + 2)
		var finger_at := BASE_BYTES + 4
		for i in range(30):
			var q := Quaternion(float(bytes.decode_s16(finger_at)) / 32767.0,
				float(bytes.decode_s16(finger_at + 2)) / 32767.0,
				float(bytes.decode_s16(finger_at + 4)) / 32767.0,
				float(bytes.decode_s16(finger_at + 6)) / 32767.0)
			if not q.is_finite() or q.length_squared() < 0.5 or q.length_squared() > 1.5:
				return {}
			fingers.append(q.normalized())
			finger_at += 8
		for i in range(10):
			curls[i] = float(bytes.decode_u8(finger_at + i)) / 255.0
	var arm_reach := 0.9 + float(bytes.decode_u8(V2_BYTES)) / 255.0 * 0.6 if version == VERSION else 1.3
	return {"body": poses[0], "head": poses[1], "left": poses[2], "right": poses[3],
		"tracking": bytes.decode_u8(OFFSET + 1) & 31,
		"hue": float(bytes.decode_u8(OFFSET + 2)) / 255.0,
		"eye_height": 1.1 + float(bytes.decode_u8(OFFSET + 3)) / 255.0,
		"velocity": velocity, "fingers": fingers, "masks": masks, "curls": curls,
		"arm_reach": arm_reach}
