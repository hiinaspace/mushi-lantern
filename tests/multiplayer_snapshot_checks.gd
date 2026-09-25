extends SceneTree

const SnapshotCodec = preload("res://scripts/multiplayer_snapshot.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_encode_decode_and_budget()
	_test_malformed_packets()
	_test_jitter_loss_and_ordering()
	if failures == 0:
		print("MULTIPLAYER_SNAPSHOT_CHECKS PASS checks=%d failures=0" % checks)
	else:
		printerr("MULTIPLAYER_SNAPSHOT_CHECKS FAIL checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_encode_decode_and_budget() -> void:
	var sim := FlightSimulation.new()
	sim.reset(1024, 49127, HerdPreset.builtins()[0])
	for i in sim.positions.size():
		var horizontal := 127.0 if i % 2 == 0 else -127.0
		sim.positions[i] = Vector3(horizontal, -48.0 if i % 3 == 0 else 80.0, -horizontal)
		sim.velocities[i] = Vector3(15.99, -2.125, -15.98)
		sim.arousals[i] = float(i % 101) / 100.0
		sim.lifecycles[i] = i % 4
	var chunks := SnapshotCodec.encode_chunks(42, 77, 930, sim, 256)
	_expect(chunks.size() == 16, "1024 agents split into 16 independent ranges")
	var total_bytes := 0
	var decoded_agents := 0
	for packet in chunks:
		total_bytes += packet.size()
		_expect(packet.size() <= 1100, "chunk respects datagram budget")
		var decoded := SnapshotCodec.decode_chunk(packet)
		_expect(not decoded.is_empty(), "encoded chunk decodes")
		if decoded.is_empty():
			continue
		decoded_agents += decoded.count
		_expect(decoded.epoch == 42 and decoded.sequence == 77 and decoded.tick == 930, "header carries session sequence and tick")
		for local_index in decoded.count:
			var source_index: int = decoded.start + local_index
			var p: Vector3 = decoded.positions[local_index]
			var v: Vector3 = decoded.velocities[local_index]
			_expect(absf(p.x - sim.positions[source_index].x) <= 0.004, "256 m horizontal position quantization stays within 4 mm")
			_expect(absf(p.y - sim.positions[source_index].y) <= 0.002, "underground/upper vertical quantization stays within 2 mm")
			_expect(absf(v.x - sim.velocities[source_index].x) <= 0.008, "velocity quantization stays within 8 mm/s")
			_expect(absf(decoded.arousals[local_index] - sim.arousals[source_index]) <= 1.0 / 255.0, "arousal quantization stays within one byte")
			_expect(decoded.lifecycles[local_index] == sim.lifecycles[source_index], "lifecycle survives round trip")
	_expect(decoded_agents == 1024, "all agents appear exactly once")
	_expect(total_bytes == 16 * (SnapshotCodec.HEADER_BYTES + 64 * SnapshotCodec.RECORD_BYTES), "wire-size accounting matches fixed records")
	var rate_10_hz := float(total_bytes) * 10.0 * 8.0 / 1_000_000.0
	var rate_60_hz := float(total_bytes) * 60.0 * 8.0 / 1_000_000.0
	print("SNAPSHOT_WIRE agents=1024 chunks=%d bytes=%d rate_10hz=%.3fMbps rate_60hz=%.3fMbps" % [chunks.size(), total_bytes, rate_10_hz, rate_60_hz])
	_expect(rate_10_hz < 2.0 and rate_60_hz < 10.0, "snapshot rate stays below 2 Mbps at 10 Hz and 10 Mbps at 60 Hz")
	var small_chunks := SnapshotCodec.encode_chunks(9, 1, 3, sim, 128)
	var small_decoded := SnapshotCodec.decode_chunk(small_chunks[0])
	_expect(small_decoded.terrain_size == 128, "128 m bounds are carried in the header")


func _test_malformed_packets() -> void:
	var sim := FlightSimulation.new()
	sim.reset(1, 12, HerdPreset.builtins()[0])
	var packet := SnapshotCodec.encode_chunks(1, 1, 1, sim, 128)[0]
	_expect(SnapshotCodec.decode_chunk(PackedByteArray()).is_empty(), "empty datagram rejected")
	var truncated := packet.slice(0, packet.size() - 1)
	_expect(SnapshotCodec.decode_chunk(truncated).is_empty(), "truncated datagram rejected")
	var oversized := packet.duplicate()
	oversized.resize(1101)
	_expect(SnapshotCodec.decode_chunk(oversized).is_empty(), "oversized datagram rejected")
	var bad_magic := packet.duplicate()
	bad_magic[0] = 0
	_expect(SnapshotCodec.decode_chunk(bad_magic).is_empty(), "bad magic rejected")
	var bad_lifecycle := packet.duplicate()
	bad_lifecycle[SnapshotCodec.HEADER_BYTES + SnapshotCodec.RECORD_BYTES - 1] = 255
	_expect(SnapshotCodec.decode_chunk(bad_lifecycle).is_empty(), "invalid lifecycle rejected")


func _test_jitter_loss_and_ordering() -> void:
	var sim := FlightSimulation.new()
	sim.reset(128, 88, HerdPreset.builtins()[0])
	var receiver := SnapshotCodec.new()
	receiver.begin_epoch(555)
	var chunks_by_seq: Dictionary = {}
	for sequence in range(1, 22):
		chunks_by_seq[sequence] = SnapshotCodec.encode_chunks(555, sequence, sequence * 3, sim, 128)
	# Synthetic 0-2 frame jitter reorders adjacent snapshots. Drop sequence 5;
	# duplicate 8 after its first delivery. Later snapshots must still converge.
	var arrival_order := [1, 3, 2, 4, 6, 7, 8, 8, 10, 9, 11, 13, 12, 14, 15, 16, 17, 18, 19, 20]
	var accepted_sequences: Array[int] = []
	for sequence in arrival_order:
		if sequence == 5:
			continue
		var packet: PackedByteArray = chunks_by_seq[sequence][0]
		var accepted := receiver.accept_chunk(packet)
		if not accepted.is_empty():
			accepted_sequences.append(accepted.sequence)
	_expect(accepted_sequences.has(1) and accepted_sequences.has(4), "jittered packets can be accepted")
	_expect(not accepted_sequences.has(2) and accepted_sequences.count(8) == 1, "older and duplicate snapshots are rejected")
	_expect(receiver.dropped_chunks == 4, "sequence gap counts losses and snapshots made stale by reordering")
	_expect(receiver.accept_chunk(chunks_by_seq[20][0]).is_empty(), "duplicate latest snapshot is rejected")
	_expect(receiver.accept_chunk(chunks_by_seq[21][0]).sequence == 21, "later state is accepted after loss and reordering")
	_expect(receiver.accept_chunk(SnapshotCodec.encode_chunks(556, 22, 66, sim, 128)[0]).is_empty(), "unexpected epoch is rejected")
	_expect(SnapshotCodec.sequence_is_newer(0, 0xffffffff), "sequence comparison handles uint32 wrap")
	_expect(not SnapshotCodec.sequence_is_newer(5, 5), "equal sequence is not newer")


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
