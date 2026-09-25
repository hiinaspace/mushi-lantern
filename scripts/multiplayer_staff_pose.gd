class_name MultiplayerStaffPose
extends RefCounted

## Optional visual tail on the combined lantern/avatar datagram. The lantern
## remains gameplay authority; this pose only places the remote shaft.
const OFFSET := MultiplayerAvatarPose.BYTES
const VERSION := 1
const BYTES := OFFSET + 32


static func append(packet: PackedByteArray, staff_world: Transform3D, placement: int) -> PackedByteArray:
	if packet.size() != OFFSET or not staff_world.origin.is_finite():
		return packet
	var q := staff_world.basis.orthonormalized().get_rotation_quaternion()
	if not q.is_finite():
		return packet
	var bytes := packet.duplicate()
	bytes.resize(BYTES)
	bytes.encode_u8(OFFSET, VERSION)
	bytes.encode_u8(OFFSET + 1, clampi(placement, 0, StaffTool.Placement.RECALL_HOVER))
	bytes.encode_u16(OFFSET + 2, 0)
	bytes.encode_float(OFFSET + 4, staff_world.origin.x)
	bytes.encode_float(OFFSET + 8, staff_world.origin.y)
	bytes.encode_float(OFFSET + 12, staff_world.origin.z)
	bytes.encode_float(OFFSET + 16, q.x)
	bytes.encode_float(OFFSET + 20, q.y)
	bytes.encode_float(OFFSET + 24, q.z)
	bytes.encode_float(OFFSET + 28, q.w)
	return bytes


static func decode(bytes: PackedByteArray, terrain_size: int) -> Dictionary:
	if bytes.size() != BYTES or bytes.decode_u8(OFFSET) != VERSION:
		return {}
	var p := Vector3(bytes.decode_float(OFFSET + 4), bytes.decode_float(OFFSET + 8), bytes.decode_float(OFFSET + 12))
	var q := Quaternion(bytes.decode_float(OFFSET + 16), bytes.decode_float(OFFSET + 20),
		bytes.decode_float(OFFSET + 24), bytes.decode_float(OFFSET + 28))
	var bound := float(terrain_size) * 0.6
	if not p.is_finite() or absf(p.x) > bound or absf(p.z) > bound or p.y < -8.0 or p.y > 100.0 \
			or not q.is_finite() or q.length_squared() < 0.5 or q.length_squared() > 1.5:
		return {}
	return {"pose": Transform3D(Basis(q.normalized()), p),
		"placement": clampi(bytes.decode_u8(OFFSET + 1), 0, StaffTool.Placement.RECALL_HOVER)}
