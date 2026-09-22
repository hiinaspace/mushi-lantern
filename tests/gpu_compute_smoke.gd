extends SceneTree

var sim: GpuFlightSimulation
var frame := 0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var shader: RDShaderFile = load("res://shaders/flight_compute.glsl")
	if shader == null or not shader.get_spirv().compile_error_compute.is_empty():
		push_error("compute shader import failed: %s" % ("null" if shader == null else shader.get_spirv().compile_error_compute))
		quit(1)
		return
	sim = GpuFlightSimulation.new()
	sim.mushroom_centers = PackedVector2Array([Vector2(-14.4, -13.2)])
	sim.reset(256, 40721, HerdPreset.builtins()[-1])
	if not sim.gpu_error.is_empty():
		push_error(sim.gpu_error)
		quit(1)

func _process(_delta: float) -> bool:
	frame += 1
	if sim == null:
		return false
	if not sim.gpu_error.is_empty():
		push_error(sim.gpu_error)
		quit(1)
		return false
	if sim.gpu_ready and frame < 40:
		var light := LightField.new()
		light.update_transform(Vector3(0, 2, 0), Vector3(1, -0.3, 0))
		light.mode = LightField.Mode.BLUE
		sim.step(1.0 / 30.0, light)
	if frame == 25:
		sim.request_snapshot()
	if frame == 60:
		if not sim.gpu_ready or sim.snapshot_revision < 0 or not sim.is_finite_and_bounded():
			push_error("GPU smoke: ready=%s snapshot=%d finite=%s error=%s" % [sim.gpu_ready, sim.snapshot_revision, sim.is_finite_and_bounded(), sim.gpu_error])
			sim.dispose()
			quit(1)
		else:
			print("GPU_SMOKE_OK count=%d revision=%d score=%d" % [sim.positions.size(), sim.snapshot_revision, sim.score])
			sim.dispose()
	if frame == 65:
		quit()
	return false
