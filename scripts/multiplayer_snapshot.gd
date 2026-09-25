class_name MultiplayerSnapshot
extends RefCounted

## Independent, unreliable snapshot chunks for host-authoritative GPU state.
## Each chunk contains a contiguous agent ID range and can be dropped/reordered
## independently. No transport dependency is required by this codec.

const MAGIC_A := 0x4D # M
const MAGIC_B := 0x53 # S
const VERSION := 1
const HEADER_BYTES := 24
const RECORD_BYTES := 13
const AGENTS_PER_CHUNK := 64
const MAX_AGENTS := 2048
const MAX_DATAGRAM_BYTES := 1100
const MIN_TERRAIN_SIZE := 128
const MAX_TERRAIN_SIZE := 256
const MIN_Y := -64.0
const MAX_Y := 96.0
const MAX_VELOCITY_COMPONENT := 16.0
const LIFECYCLE_COUNT := 4

var expected_epoch: int = -1
var last_sequence_by_range: Dictionary = {}
var dropped_chunks: int = 0


static func encode_chunks(epoch: int, seq: int, tick: int, sim: FlightSimulation, terrain_size: int) -> Array[PackedByteArray]:
	var chunks: Array[PackedByteArray] = []
	if sim == null or not _valid_terrain_size(terrain_size):
		push_error("Snapshot encode requires a simulation and 128 m or 256 m terrain")
		return chunks
	var agent_count := sim.positions.size()
	if agent_count < 1 or agent_count > MAX_AGENTS or sim.velocities.size() != agent_count or sim.arousals.size() != agent_count or sim.lifecycles.size() != agent_count:
		push_error("Snapshot arrays have invalid or mismatched lengths")
		return chunks
	for start in range(0, agent_count, AGENTS_PER_CHUNK):
		var count := mini(AGENTS_PER_CHUNK, agent_count - start)
		var stream := StreamPeerBuffer.new()
		stream.big_endian = false
		stream.put_u8(MAGIC_A)
		stream.put_u8(MAGIC_B)
		stream.put_u8(VERSION)
		stream.put_u8(0) # flags reserved
		stream.put_u32(epoch & 0xffffffff)
		stream.put_u32(seq & 0xffffffff)
		stream.put_u32(tick & 0xffffffff)
		stream.put_u16(start)
		stream.put_u16(count)
		stream.put_u16(terrain_size)
		stream.put_u16(0) # reserved
		var horizontal_limit := float(terrain_size) * 0.5
		for index in range(start, start + count):
			var p := sim.positions[index]
			var v := sim.velocities[index]
			if not p.is_finite() or not v.is_finite() or not is_finite(sim.arousals[index]):
				push_error("Snapshot state contains a non-finite value at agent %d" % index)
				return []
			stream.put_u16(_quantize(p.x, -horizontal_limit, horizontal_limit, 65535))
			stream.put_u16(_quantize(p.y, MIN_Y, MAX_Y, 65535))
			stream.put_u16(_quantize(p.z, -horizontal_limit, horizontal_limit, 65535))
			var qx := _quantize(v.x, -MAX_VELOCITY_COMPONENT, MAX_VELOCITY_COMPONENT, 4095)
			var qy := _quantize(v.y, -MAX_VELOCITY_COMPONENT, MAX_VELOCITY_COMPONENT, 4095)
			var qz := _quantize(v.z, -MAX_VELOCITY_COMPONENT, MAX_VELOCITY_COMPONENT, 4095)
			var packed_velocity: int = qx | (qy << 12) | (qz << 24)
			for byte_index in 5:
				stream.put_u8((packed_velocity >> (byte_index * 8)) & 0xff)
			stream.put_u8(_quantize(sim.arousals[index], 0.0, 1.0, 255))
			var lifecycle: int = sim.lifecycles[index]
			if lifecycle < 0 or lifecycle >= LIFECYCLE_COUNT:
				push_error("Snapshot lifecycle is invalid at agent %d" % index)
				return []
			stream.put_u8(lifecycle)
		var packet := stream.data_array
		if packet.size() > MAX_DATAGRAM_BYTES:
			push_error("Snapshot chunk exceeded the datagram budget")
			return []
		chunks.append(packet)
	return chunks


static func decode_chunk(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER_BYTES or packet.size() > MAX_DATAGRAM_BYTES:
		return {}
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = packet
	if stream.get_u8() != MAGIC_A or stream.get_u8() != MAGIC_B or stream.get_u8() != VERSION:
		return {}
	var flags := stream.get_u8()
	var epoch := stream.get_u32()
	var sequence := stream.get_u32()
	var tick := stream.get_u32()
	var start := stream.get_u16()
	var count := stream.get_u16()
	var terrain_size := stream.get_u16()
	var reserved := stream.get_u16()
	if flags != 0 or reserved != 0 or not _valid_terrain_size(terrain_size):
		return {}
	if count < 1 or count > AGENTS_PER_CHUNK or start + count > MAX_AGENTS:
		return {}
	if packet.size() != HEADER_BYTES + count * RECORD_BYTES:
		return {}
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var arousals := PackedFloat32Array()
	var lifecycles := PackedInt32Array()
	var horizontal_limit := float(terrain_size) * 0.5
	for _i in count:
		var px := _dequantize(stream.get_u16(), -horizontal_limit, horizontal_limit, 65535)
		var py := _dequantize(stream.get_u16(), MIN_Y, MAX_Y, 65535)
		var pz := _dequantize(stream.get_u16(), -horizontal_limit, horizontal_limit, 65535)
		var packed_velocity: int = 0
		for byte_index in 5:
			packed_velocity |= stream.get_u8() << (byte_index * 8)
		var qx: int = packed_velocity & 0xfff
		var qy: int = (packed_velocity >> 12) & 0xfff
		var qz: int = (packed_velocity >> 24) & 0xfff
		var vx := _dequantize(qx, -MAX_VELOCITY_COMPONENT, MAX_VELOCITY_COMPONENT, 4095)
		var vy := _dequantize(qy, -MAX_VELOCITY_COMPONENT, MAX_VELOCITY_COMPONENT, 4095)
		var vz := _dequantize(qz, -MAX_VELOCITY_COMPONENT, MAX_VELOCITY_COMPONENT, 4095)
		var arousal := float(stream.get_u8()) / 255.0
		var lifecycle := stream.get_u8()
		if lifecycle >= LIFECYCLE_COUNT:
			return {}
		positions.append(Vector3(px, py, pz))
		velocities.append(Vector3(vx, vy, vz))
		arousals.append(arousal)
		lifecycles.append(lifecycle)
	return {
		"start": start,
		"count": count,
		"positions": positions,
		"velocities": velocities,
		"arousals": arousals,
		"lifecycles": lifecycles,
		"sequence": sequence,
		"epoch": epoch,
		"tick": tick,
		"terrain_size": terrain_size,
	}


## Reset ordering state when a session/restart epoch changes. Callers should
## establish the expected epoch from the lobby/host before accepting packets.
func begin_epoch(epoch: int) -> void:
	expected_epoch = epoch & 0xffffffff
	last_sequence_by_range.clear()
	dropped_chunks = 0


## Returns the decoded chunk when it is current and in order, otherwise {}.
## Sequence tracking is per range because independently dropped chunks need
## not invalidate other ranges in the same snapshot.
func accept_chunk(packet: PackedByteArray) -> Dictionary:
	var chunk := decode_chunk(packet)
	if chunk.is_empty() or expected_epoch < 0 or int(chunk.epoch) != expected_epoch:
		return {}
	var range_start: int = chunk.start
	var sequence: int = chunk.sequence
	if last_sequence_by_range.has(range_start):
		var previous: int = last_sequence_by_range[range_start]
		if not sequence_is_newer(sequence, previous):
			return {}
		var delta: int = (sequence - previous) & 0xffffffff
		if delta > 1:
			dropped_chunks += delta - 1
	last_sequence_by_range[range_start] = sequence
	return chunk


## RFC-1982-style comparison for wrapping uint32 sequence numbers. A difference
## of exactly half the range is intentionally considered ambiguous/old.
static func sequence_is_newer(candidate: int, previous: int) -> bool:
	var delta: int = (candidate - previous) & 0xffffffff
	return delta != 0 and delta < 0x80000000


static func _valid_terrain_size(size: int) -> bool:
	return size == MIN_TERRAIN_SIZE or size == MAX_TERRAIN_SIZE


static func _quantize(value: float, low: float, high: float, maximum: int) -> int:
	return clampi(roundi((clampf(value, low, high) - low) / (high - low) * maximum), 0, maximum)


static func _dequantize(value: int, low: float, high: float, maximum: int) -> float:
	return low + float(value) / float(maximum) * (high - low)
