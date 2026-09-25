extends SceneTree

const DT := 1.0 / 30.0
var sim: GpuFlightSimulation
var frame := 0
var stage := 0
var snapshot_requested := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	sim = GpuFlightSimulation.new()
	sim.spawn_centers = PackedVector2Array([Vector2.ZERO])
	# Keep the whole spawn cloud inside the goal despite formation pressure.
	# This fixture tests accounting, not successful herding into a small goal.
	sim.goal_radius = 4.0
	sim.goal_dwell_seconds = 0.45
	sim.goal_accepting = false
	sim.reset(256, 40721, HerdPreset.builtins()[7])
	sim.snapshot_interval = 999.0

func _process(_delta: float) -> bool:
	if sim == null: return false
	frame += 1
	if not sim.gpu_error.is_empty():
		push_error(sim.gpu_error)
		sim.dispose()
		quit(1)
		return false
	if stage == 0 and sim.gpu_ready:
		var field := LightField.new()
		if sim.state_revision < 20:
			sim.step(DT, field)
		elif not snapshot_requested:
			snapshot_requested = true
			sim.request_snapshot()
		if sim.snapshot_revision == 20:
			if sim.score != 0:
				push_error("Closed goal gate accepted a return")
				sim.dispose()
				quit(1)
				return false
			for life: int in sim.lifecycles:
				if life != FlightSimulation.Lifecycle.ACTIVE:
					push_error("Closed goal gate changed an active lifecycle")
					sim.dispose()
					quit(1)
					return false
			for dwell: float in sim._goal_dwells:
				if dwell != 0.0:
					push_error("Closed goal gate accumulated dwell")
					sim.dispose()
					quit(1)
					return false
			print("GPU_GOAL_GATE_CLOSED score=%d revision=%d" % [sim.score, sim.snapshot_revision])
			sim.goal_accepting = true
			stage = 1
			snapshot_requested = false
	elif stage == 1 and sim.gpu_ready:
		if sim.state_revision < 33:
			sim.step(DT, LightField.new())
		elif not snapshot_requested:
			snapshot_requested = true
			sim.request_snapshot()
		if sim.snapshot_revision == 33:
			if sim.score != 0 or sim.lifecycles[0] != FlightSimulation.Lifecycle.ACTIVE:
				push_error("Reopened goal committed before a fresh 0.45 s dwell")
				sim.dispose()
				quit(1)
				return false
			print("GPU_GOAL_GATE_FRESH_DWELL score=%d revision=%d" % [sim.score, sim.snapshot_revision])
			stage = 2
			snapshot_requested = false
	elif stage == 2 and sim.gpu_ready:
		if sim.state_revision < 34:
			sim.step(DT, LightField.new())
		elif not snapshot_requested:
			snapshot_requested = true
			sim.request_snapshot()
		if sim.snapshot_revision == 34:
			if sim.score != 256:
				push_error("Fresh open-gate dwell failed to commit all in-goal agents")
				sim.dispose()
				quit(1)
				return false
			for life: int in sim.lifecycles:
				if life != FlightSimulation.Lifecycle.COMMITTED:
					push_error("Agent did not enter COMMITTED after accepted dwell")
					sim.dispose()
					quit(1)
					return false
			print("GPU_GOAL_GATE_OPEN score=%d revision=%d" % [sim.score, sim.snapshot_revision])
			stage = 3
			snapshot_requested = false
	elif stage == 3 and sim.gpu_ready:
		if sim.state_revision < 244:
			sim.step(DT, LightField.new())
		elif not snapshot_requested:
			snapshot_requested = true
			sim.request_snapshot()
		if sim.snapshot_revision == 244:
			if sim.score != 256:
				push_error("Committed score changed on later snapshots")
				sim.dispose()
				quit(1)
				return false
			for life: int in sim.lifecycles:
				if life != FlightSimulation.Lifecycle.RELEASED:
					push_error("Committed agent failed to release")
					sim.dispose()
					quit(1)
					return false
			var highest_returned_y := -INF
			for position: Vector3 in sim.positions:
				highest_returned_y = maxf(highest_returned_y, position.y)
				if position.y > -21.5:
					push_error("Returned agent released before reaching deep stream crest (highest y=%.3f)" % highest_returned_y)
					sim.dispose()
					quit(1)
					return false
			print("GPU_RELEASE_OK score=%d revision=%d highest_y=%.2f" % [sim.score, sim.snapshot_revision, highest_returned_y])
			stage = 4
			# Exercise queued destruction/creation and stale callbacks from a
			# previous epoch; only the last seeded population may publish.
			sim.reset(2048, 123, HerdPreset.builtins()[7])
			sim.reset(64, 40721, HerdPreset.builtins()[7])
			sim.snapshot_interval = 999.0
	elif stage == 4 and sim.gpu_ready:
		if sim.positions.size() != 64 or sim.score != 0:
			push_error("Reset leaked old population/accounting")
			sim.dispose()
			quit(1)
			return false
		if sim.state_revision < 2:
			sim.step(DT, LightField.new())
		else:
			stage = 5
			sim.request_snapshot()
	elif stage == 5 and sim.snapshot_revision == 2:
		if not sim.is_finite_and_bounded():
			push_error("Reset population is not finite/bounded")
			sim.dispose()
			quit(1)
			return false
		print("GPU_RESET_OK count=%d revision=%d" % [sim.positions.size(), sim.snapshot_revision])
		sim.dispose()
		stage = 6
	elif stage == 6 and frame > 110:
		quit()
	if frame > 600:
		push_error("GPU lifecycle/reset timeout: stage=%d ready=%s snapshot=%d score=%d life0=%d pos0=%s" % [stage, sim.gpu_ready, sim.snapshot_revision, sim.score, sim.lifecycles[0], sim.positions[0]])
		sim.dispose()
		quit(1)
	return false
