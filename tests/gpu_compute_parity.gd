extends SceneTree

const COUNTS := [64, 256, 1024, 256, 64, 256, 2048, 256]
const STEPS := 12
const DT := 1.0 / 30.0

var fixture := -1
var frame := 0
var sim: GpuFlightSimulation
var reference: FlightSimulation
var field: LightField
var stage := 0
var enqueue_us := 0
var preset_name := ""

func _initialize() -> void:
	call_deferred("_next_fixture")

func _next_fixture() -> void:
	if sim != null:
		sim.dispose()
	fixture += 1
	if fixture >= COUNTS.size():
		print("GPU_PARITY_OK")
		quit()
		return
	frame = 0
	stage = 0
	enqueue_us = 0
	var count: int = COUNTS[fixture]
	var preset: HerdPreset
	preset_name = "Drifting trains" if fixture >= 4 else "Living shoals"
	for candidate: HerdPreset in HerdPreset.builtins():
		if candidate.preset_name == preset_name:
			preset = candidate
			break
	if preset == null:
		push_error("Missing GPU parity preset: " + preset_name)
		quit(1)
		return
	if fixture >= 4 and preset.formation_follow_weight <= 0.0:
		push_error("Formation fixture has no follow force")
		quit(1)
		return
	if fixture >= 4 and fixture <= 6:
		# Exercise actual partner matching; mushroom populations are otherwise
		# mostly dormant throughout this short parity fixture.
		preset.energy_dynamics = false
		preset.spontaneous_waking_enabled = false
	if fixture == 3 or fixture == 7:
		preset.spontaneous_wake_min_seconds = 0.08
		preset.spontaneous_wake_max_seconds = 0.12
	field = LightField.new()
	field.mode = LightField.Mode.BLUE
	field.update_transform(Vector3(-13, 2.2, -13), Vector3(0.4, -0.25, 0.9))
	for flight in [0, 1]:
		var current: FlightSimulation = FlightSimulation.new() if flight == 0 else GpuFlightSimulation.new()
		current.mushroom_centers = PackedVector2Array([Vector2(-14.4, -13.2), Vector2(14.6, -12), Vector2(15.4, 13.6)])
		current.obstacle_centers = PackedVector2Array([Vector2(-2, -3)])
		current.obstacle_radii = PackedFloat32Array([1.2])
		current.reset(count, 40721, preset)
		if flight == 0: reference = current
		else: sim = current
	sim.snapshot_interval = 999.0

func _process(_delta: float) -> bool:
	if sim == null: return false
	frame += 1
	if not sim.gpu_error.is_empty():
		push_error(sim.gpu_error)
		sim.dispose()
		quit(1)
		return false
	if not sim.gpu_ready: return false
	if stage == 0:
		if fixture == 3 or fixture == 7:
			field.mode = ((sim.state_revision / 4) % 3) as LightField.Mode
		var start := Time.get_ticks_usec()
		sim.step(DT, field)
		enqueue_us += Time.get_ticks_usec() - start
		reference.step(DT, field)
		if sim.state_revision == STEPS:
			sim.request_snapshot()
			stage = 1
	if stage == 1 and sim.snapshot_revision == STEPS:
		var max_position := 0.0
		var max_id := -1
		var mean_position := 0.0
		var max_energy := 0.0
		var linked := 0
		for i: int in COUNTS[fixture]:
			var error := sim.positions[i].distance_to(reference.positions[i])
			if error > max_position:
				max_position = error
				max_id = i
			mean_position += error
			max_energy = maxf(max_energy, absf(sim.arousals[i] - reference.arousals[i]))
			if fixture >= 4 and sim.formation_predecessors[i] >= 0:
				linked += 1
			if sim.formation_predecessors[i] != reference.formation_predecessors[i] or sim.formation_successors[i] != reference.formation_successors[i]:
				push_error("CPU/GPU formation links disagree at ID %d" % i)
				sim.dispose()
				quit(1)
				return false
		mean_position /= float(COUNTS[fixture])
		print("GPU_PARITY preset=%s count=%d wake_and_modes=%s linked=%d mean_pos=%.5f max_pos=%.5f max_id=%d max_energy=%.5f enqueue_ms=%.3f" % [preset_name, COUNTS[fixture], fixture == 3 or fixture == 7, linked, mean_position, max_position, max_id, max_energy, float(enqueue_us) / STEPS / 1000.0])
		if max_position > 0.05:
			print("PARITY_DEBUG id=%d cpu_pos=%s gpu_pos=%s cpu_vel=%s gpu_vel=%s role=%d before=%d after=%d" % [max_id, reference.positions[max_id], sim.positions[max_id], reference.velocities[max_id], sim.velocities[max_id], sim.trait_types[max_id], sim.formation_predecessors[max_id], sim.formation_successors[max_id]])
		if fixture >= 4 and fixture <= 6 and linked < COUNTS[fixture] / 20:
			push_error("Awake formation fixture made too few links")
			sim.dispose()
			quit(1)
			return false
		if not sim.is_finite_and_bounded() or max_position > 0.05 or max_energy > 0.03:
			push_error("GPU parity/invariant failed")
			sim.dispose()
			quit(1)
			return false
		if (fixture == 3 or fixture == 7) and sim._wake_cycles.count(0) == sim._wake_cycles.size():
			push_error("Expedited wake fixture never woke")
			sim.dispose()
			quit(1)
			return false
		stage = 2
		call_deferred("_next_fixture")
	if frame > 300:
		push_error("GPU parity timeout")
		sim.dispose()
		quit(1)
	return false
