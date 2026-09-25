extends SceneTree

var sim: GpuFlightSimulation
var fields: Array[LightField] = []
var frame := 0
var initial_mean := 0.0


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var shader: RDShaderFile = load("res://shaders/flight_compute.glsl")
	if shader == null or not shader.get_spirv().compile_error_compute.is_empty():
		push_error("Multi-lantern shader import failed")
		quit(1)
		return
	sim = GpuFlightSimulation.new()
	sim.spawn_centers = PackedVector2Array([Vector2.ZERO])
	sim.goal_position = Vector2(20.0, 20.0)
	sim.reset(64, 40721, HerdPreset.builtins()[-1])
	for value: float in sim.arousals:
		initial_mean += value / float(sim.arousals.size())
	for i: int in 8:
		var field := LightField.new()
		field.update_transform(Vector3(0.0, 5.0, 0.0), Vector3.DOWN)
		field.range_m = 20.0
		field.half_angle_degrees = 80.0
		field.mode = LightField.Mode.BLUE if i < 4 else LightField.Mode.ORANGE
		fields.append(field)
	var encoded := sim._encode_sources(fields[0], fields)
	assert(encoded.size() == (GpuFlightSimulation.LANTERN_SOURCE_OFFSET * 4 + GpuFlightSimulation.MAX_LANTERNS * GpuFlightSimulation.LANTERN_WORDS) * 4)
	assert(is_equal_approx(encoded.decode_float((GpuFlightSimulation.LANTERN_SOURCE_OFFSET * 4 + 4 * GpuFlightSimulation.LANTERN_WORDS + 10) * 4), float(LightField.Mode.ORANGE)))


func _process(_delta: float) -> bool:
	frame += 1
	if sim == null:
		return false
	if not sim.gpu_error.is_empty():
		push_error(sim.gpu_error)
		sim.dispose()
		quit(1)
		return false
	if sim.gpu_ready and frame < 48:
		sim.step(1.0 / 30.0, fields[0], 1.0, 1.0, fields)
	if frame == 70:
		if sim.snapshot_revision < 0 or not sim.is_finite_and_bounded():
			push_error("Multi-lantern GPU state invalid: revision=%d" % sim.snapshot_revision)
			quit(1)
		else:
			var mean := 0.0
			for value: float in sim.arousals:
				mean += value / float(sim.arousals.size())
			var exposure_mean := 0.0
			for value: float in sim.exposures:
				exposure_mean += value / float(sim.exposures.size())
			if exposure_mean < 0.5:
				push_error("Multi-lantern exposure too low: %.3f" % exposure_mean)
				quit(1)
			if mean <= initial_mean + 0.03:
				push_error("Overlapping orange failed to wake agents: initial=%.3f after=%.3f" % [initial_mean, mean])
				quit(1)
			else:
				print("MULTI_LANTERN_GPU_OK initial=%.3f after=%.3f revision=%d" % [initial_mean, mean, sim.snapshot_revision])
			sim.dispose()
	if frame == 75:
		quit()
	return false
