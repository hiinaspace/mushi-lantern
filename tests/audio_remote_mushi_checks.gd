extends SceneTree

## Confirms guest audio accepts and expires host-authoritative replica snapshots.
func _initialize() -> void:
	var replica := RemoteFlightSimulation.new()
	replica.reset(2, 17, HerdPreset.new())
	var audio := GroveAudio.new()
	audio.bind_simulation(replica)
	assert(audio._simulation == replica, "guest replica remains bound to GroveAudio")
	assert(not audio._remote_snapshot_complete(), "audio waits for the first complete replica snapshot")

	var chunk := {
		"start": 0,
		"count": 2,
		"sequence": 1,
		"positions": PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 1, 1)]),
		"velocities": PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		"arousals": PackedFloat32Array([0.1, 0.2]),
		"lifecycles": PackedInt32Array([FlightSimulation.Lifecycle.ACTIVE, FlightSimulation.Lifecycle.ACTIVE]),
	}
	assert(replica.apply_chunk(chunk), "replica accepts snapshot chunk")
	assert(audio._remote_snapshot_complete(), "complete fresh replica enables mushi selection")
	replica.advance_replica(GroveAudio.STALE_SECONDS + 0.01)
	assert(not audio._remote_snapshot_complete(), "stale replica stops sustaining guest audio")
	var refreshed := chunk.duplicate()
	refreshed["start"] = 0
	refreshed["count"] = 1
	refreshed["sequence"] = 2
	for field in ["positions", "velocities", "arousals", "lifecycles"]:
		refreshed[field] = chunk[field].slice(0, 1)
	assert(replica.apply_chunk(refreshed))
	assert(audio._remote_snapshot_complete(), "partial fresh data resumes sampling")
	assert(replica.has_fresh_agent(0, GroveAudio.STALE_SECONDS) and not replica.has_fresh_agent(1, GroveAudio.STALE_SECONDS), "stale individual source is excluded")
	audio.free()
	quit()
