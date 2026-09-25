extends SceneTree

## Deterministic in-process link impairment test. It exercises the actual wire
## codec and display replica, but does not claim Iroh, GPU or headset timing.
const Codec = preload("res://scripts/multiplayer_snapshot.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scenario(100, 0.01, 1201)
	_scenario(200, 0.05, 1202)
	print("MULTIPLAYER_REPLICA_CHECKS %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _scenario(max_delay_ms: int, loss_rate: float, seed: int) -> void:
	var preset := HerdPreset.builtins()[0]
	var host := FlightSimulation.new()
	host.reset(1024, 40721, preset)
	var replica := RemoteFlightSimulation.new()
	replica.reset(1024, 40721, preset)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pending: Array[Dictionary] = []
	var epoch := 71
	var sequence := 0
	var sent_bytes := 0
	var dropped_packets := 0
	var errors := PackedFloat32Array()
	var biggest_frame_step := 0.0
	var dt := 1.0 / 60.0
	for frame: int in 600:
		var t := float(frame) * dt
		var motion_time := minf(t, 6.0)
		for id: int in 1024:
			var phase := float(id) * 0.059
			var x := float(id % 32) * 2.0 - 31.0 + sin(motion_time * 0.75 + phase) * 1.8
			var z := float(id / 32) * 2.0 - 31.0 + cos(motion_time * 0.64 + phase) * 1.5
			var y := 1.8 + sin(motion_time * 0.43 + phase) * 0.45
			host.positions[id] = Vector3(x, y, z)
			host.velocities[id] = Vector3(cos(motion_time * 0.75 + phase) * 1.35,
				cos(motion_time * 0.43 + phase) * 0.1935,
				-sin(motion_time * 0.64 + phase) * 0.96) if t < 6.0 else Vector3.ZERO
		if frame % 6 == 0:
			sequence += 1
			for packet: PackedByteArray in Codec.encode_chunks(epoch, sequence, frame / 2, host, 128):
				sent_bytes += packet.size()
				if rng.randf() < loss_rate:
					dropped_packets += 1
					continue
				pending.append({"at": t + rng.randf_range(0.0, float(max_delay_ms) / 1000.0), "bytes": packet})
		var remaining: Array[Dictionary] = []
		for item: Dictionary in pending:
			if item.at <= t:
				var chunk: Dictionary = Codec.decode_chunk(item.bytes)
				if chunk.is_empty() or not replica.apply_chunk(chunk):
					failures += 1
			else:
				remaining.append(item)
		pending = remaining
		var before := replica.positions[0]
		replica.advance_replica(dt)
		if t >= 2.0 and t <= 6.0:
			biggest_frame_step = maxf(biggest_frame_step, before.distance_to(replica.positions[0]))
		if t >= 2.0 and t <= 6.0 and frame % 3 == 0:
			for id: int in range(0, 1024, 16):
				errors.append(replica.positions[id].distance_to(host.positions[id]))
	var ordered := Array(errors)
	ordered.sort()
	var p95: float = ordered[int(float(ordered.size() - 1) * 0.95)]
	var final_max := 0.0
	for id: int in 1024:
		final_max = maxf(final_max, replica.positions[id].distance_to(host.positions[id]))
	var megabits_per_second := float(sent_bytes) * 8.0 / 10.0 / 1000000.0
	print("REPLICA_IMPAIRMENT jitter_ms=%d loss=%.2f packets_lost=%d p95_live_m=%.3f max_frame_step_m=%.3f final_max_m=%.4f send_Mbps=%.3f" % [max_delay_ms, loss_rate, dropped_packets, p95, biggest_frame_step, final_max, megabits_per_second])
	if replica.received_count != 1024 or final_max > 0.02 or p95 > 1.0 or biggest_frame_step > 0.2:
		failures += 1
