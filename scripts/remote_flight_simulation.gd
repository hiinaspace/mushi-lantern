class_name RemoteFlightSimulation
extends FlightSimulation

## Display-only replica. The host owns forces and score; each received agent
## range updates its own interpolation target, so lost ranges do not stall the
## rest of the shoal.
const SAMPLE_SECONDS := 0.12

var _targets := PackedVector3Array()
var _starts := PackedVector3Array()
var _sample_ages := PackedFloat32Array()
var _last_sequences := PackedInt32Array()
var _received := PackedByteArray()
var _since_packet := PackedFloat32Array()
var received_count: int = 0


func reset(agent_count: int, new_seed: int, new_preset: HerdPreset) -> void:
	super.reset(agent_count, new_seed, new_preset)
	_targets = positions.duplicate()
	_starts = positions.duplicate()
	_sample_ages.resize(agent_count)
	_last_sequences.resize(agent_count)
	_last_sequences.fill(-1)
	_received.resize(agent_count)
	_received.fill(0)
	_since_packet.resize(agent_count)
	_since_packet.fill(0.0)
	received_count = 0


func apply_chunk(chunk: Dictionary) -> bool:
	var start: int = int(chunk.get("start", -1))
	var count: int = int(chunk.get("count", 0))
	var sequence: int = int(chunk.get("sequence", -1))
	var samples: PackedVector3Array = chunk.get("positions", PackedVector3Array())
	var speeds: PackedVector3Array = chunk.get("velocities", PackedVector3Array())
	var energy: PackedFloat32Array = chunk.get("arousals", PackedFloat32Array())
	var states: PackedInt32Array = chunk.get("lifecycles", PackedInt32Array())
	if start < 0 or count < 1 or sequence < 0 or start + count > positions.size():
		return false
	if samples.size() != count or speeds.size() != count or energy.size() != count or states.size() != count:
		return false
	for offset: int in count:
		var id := start + offset
		if sequence <= _last_sequences[id]:
			continue
		var sample := samples[offset]
		var speed := speeds[offset]
		if not sample.is_finite() or not speed.is_finite() or not is_finite(energy[offset]):
			continue
		_last_sequences[id] = sequence
		velocities[id] = speed
		arousals[id] = clampf(energy[offset], 0.0, 1.0)
		var next_lifecycle := clampi(states[offset], Lifecycle.ACTIVE, Lifecycle.RELEASED)
		if lifecycles[id] == Lifecycle.ACTIVE and next_lifecycle in [Lifecycle.COMMITTED, Lifecycle.ASCENDING]:
			committed_this_step.append(id)
		lifecycles[id] = next_lifecycle
		if _received[id] == 0:
			_received[id] = 1
			received_count += 1
			positions[id] = sample
			previous_positions[id] = sample
		_starts[id] = positions[id]
		_targets[id] = sample
		_sample_ages[id] = 0.0
		_since_packet[id] = 0.0
	_energy_time += 1.0 / 60.0
	return true


func advance_replica(delta: float) -> void:
	if delta <= 0.0:
		return
	for id: int in positions.size():
		if _received[id] == 0:
			continue
		_sample_ages[id] = minf(SAMPLE_SECONDS, _sample_ages[id] + delta)
		_since_packet[id] += delta
		positions[id] = _starts[id].lerp(_targets[id], _sample_ages[id] / SAMPLE_SECONDS)
		previous_positions[id] = positions[id]
	_energy_time += delta


func stale_agents(seconds: float) -> int:
	var result := 0
	for id: int in positions.size():
		if _received[id] != 0 and _since_packet[id] > seconds:
			result += 1
	return result


func has_fresh_agent(id: int, seconds: float) -> bool:
	return id >= 0 and id < _received.size() and _received[id] != 0 and _since_packet[id] <= seconds
