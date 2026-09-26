extends SceneTree

var sim: GpuFlightSimulation
var field: LightField
var ticks := 0
var pending := false
var escaped := {}
var next_sample := 30
var multiplayer_case := false
var dark_field := LightField.new()

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	multiplayer_case = "--multiplayer" in OS.get_cmdline_user_args()
	var preset := HerdPreset.builtins()[-1].copy_preset()
	preset.spontaneous_waking_enabled = false
	# Worst allowed opposing traits must wake under sustained orange too.
	var cpu := FlightSimulation.new()
	cpu.spawn_centers = PackedVector2Array([Vector2.ZERO])
	cpu.mushroom_centers = cpu.spawn_centers
	cpu.reset(1, 40721, preset)
	cpu.lantern_response_factors[0] = 0.45
	cpu.mushroom_response_factors[0] = 1.6
	for tick in 210:
		cpu._update_arousal(0, LightField.Mode.ORANGE, 0.2, 1.0, 1.0 / 30.0)
	assert(cpu.arousals[0] > 0.75, "Sustained orange overcomes worst-case mushroom/lamp traits")
	assert(cpu._orange_patch_seconds[0] <= 5.0)
	cpu.reset(1, 40721, preset)
	assert(cpu._orange_patch_seconds[0] == 0.0)
	print("ORANGE_CPU_WORST_TRAITS_OK")
	sim = GpuFlightSimulation.new()
	sim.spawn_centers = PackedVector2Array([Vector2.ZERO])
	sim.mushroom_centers = sim.spawn_centers
	sim.goal_accepting = false
	sim.reset(256, 40721, preset)
	sim.snapshot_interval = 999.0
	field = LightField.new()
	field.mode = LightField.Mode.ORANGE
	field.half_angle_degrees = 55.0
	field.update_transform(Vector3(-4.0, 1.4, 0.0), Vector3.RIGHT)

func _process(_delta: float) -> bool:
	if sim == null or not sim.gpu_ready:
		return false
	if not sim.gpu_error.is_empty():
		push_error(sim.gpu_error)
		quit(1)
	if ticks < next_sample:
		if multiplayer_case:
			var lamps: Array[LightField] = [dark_field, field]
			sim.step(1.0 / 30.0, dark_field, 1.0, 1.0, lamps)
		else:
			sim.step(1.0 / 30.0, field)
		ticks += 1
	elif not pending:
		pending = true
		sim.request_snapshot()
	elif sim.snapshot_revision >= ticks:
		for i in sim.positions.size():
			if sim.mushroom_exposures[i] <= 0.001:
				escaped[i] = true
		print("ORANGE_ESCAPE t=%d escaped=%d min_energy=%.3f" % [ticks / 30, escaped.size(), sim.arousals[0]])
		if ticks < 300:
			next_sample += 30
			pending = false
		else:
			for i in sim.positions.size():
				if not escaped.has(i):
					print("ORANGE_STUCK id=%d p=%s exposure=%.3f mush=%.3f seconds=%.2f" % [i, sim.positions[i], field.sample(sim.positions[i]), sim.mushroom_exposures[i], sim._orange_patch_seconds[i]])
			var passed := escaped.size() == sim.positions.size() and sim.is_finite_and_bounded()
			sim.dispose()
			quit(0 if passed else 1)
	return false
