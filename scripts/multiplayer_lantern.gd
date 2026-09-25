class_name MultiplayerLantern
extends RefCounted

## Latest-value lantern input. A packet is a visual/gameplay command, never an
## authority over score, agent state or another player's lamp.
const VERSION := 1
const BYTES := 32


static func encode(sequence: int, field: LightField) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(BYTES)
	bytes.encode_u8(0, VERSION)
	bytes.encode_u8(1, int(field.mode))
	bytes.encode_u8(2, roundi(clampf(field.shutter_openness, 0.0, 1.0) * 255.0))
	bytes.encode_u8(3, 0)
	bytes.encode_u32(4, sequence)
	var values := [field.source_position.x, field.source_position.y, field.source_position.z,
		field.source_direction.x, field.source_direction.y, field.source_direction.z]
	for i: int in values.size():
		bytes.encode_float(8 + i * 4, values[i])
	return bytes


static func decode(bytes: PackedByteArray, terrain_size: int) -> Dictionary:
	if bytes.size() < BYTES or bytes.decode_u8(0) != VERSION:
		return {}
	var mode := bytes.decode_u8(1)
	if mode > LightField.Mode.ORANGE:
		return {}
	var at := Vector3(bytes.decode_float(8), bytes.decode_float(12), bytes.decode_float(16))
	var direction := Vector3(bytes.decode_float(20), bytes.decode_float(24), bytes.decode_float(28))
	if not at.is_finite() or not direction.is_finite() or direction.length_squared() < 0.5:
		return {}
	var horizontal_limit := float(terrain_size) * 0.55
	if absf(at.x) > horizontal_limit or absf(at.z) > horizontal_limit or at.y < -8.0 or at.y > 100.0:
		return {}
	return {"sequence": bytes.decode_u32(4), "position": at,
		"direction": direction.normalized(), "mode": mode,
		"shutter": float(bytes.decode_u8(2)) / 255.0}
