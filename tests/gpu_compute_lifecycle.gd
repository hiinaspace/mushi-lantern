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
		if sim.snapshot_revision == 20 and sim.score == 256:
			for life: int in sim.lifecycles:
				if life == FlightSimulation.Lifecycle.ACTIVE:
					push_error("Active agent left in goal fixture")
					sim.dispose()
					quit(1)
					return false
			print("GPU_LIFECYCLE committed=%d revision=%d" % [sim.score, sim.snapshot_revision])
			stage = 1
			snapshot_requested = false
	elif stage == 1 and sim.gpu_ready:
		if sim.state_revision < 100:
			sim.step(DT, LightField.new())
		elif not snapshot_requested:
			snapshot_requested = true
			sim.request_snapshot()
		if sim.snapshot_revision == 100:
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
			print("GPU_RELEASE_OK score=%d revision=%d" % [sim.score, sim.snapshot_revision])
			stage = 2
			# Exercise queued destruction/creation and stale callbacks from a
			# previous epoch; only the last seeded population may publish.
			sim.reset(2048, 123, HerdPreset.builtins()[7])
			sim.reset(64, 40721, HerdPreset.builtins()[7])
			sim.snapshot_interval = 999.0
	elif stage == 2 and sim.gpu_ready:
		if sim.positions.size() != 64 or sim.score != 0:
			push_error("Reset leaked old population/accounting")
			sim.dispose()
			quit(1)
			return false
		if sim.state_revision < 2:
			sim.step(DT, LightField.new())
		else:
			stage = 3
			sim.request_snapshot()
	elif stage == 3 and sim.snapshot_revision == 2:
		if not sim.is_finite_and_bounded():
			push_error("Reset population is not finite/bounded")
			sim.dispose()
			quit(1)
			return false
		print("GPU_RESET_OK count=%d revision=%d" % [sim.positions.size(), sim.snapshot_revision])
		sim.dispose()
		stage = 4
	elif stage == 4 and frame > 110:
		quit()
	if frame > 300:
		push_error("GPU lifecycle/reset timeout: stage=%d ready=%s snapshot=%d score=%d life0=%d pos0=%s" % [stage, sim.gpu_ready, sim.snapshot_revision, sim.score, sim.lifecycles[0], sim.positions[0]])
		sim.dispose()
		quit(1)
	return false
