extends SceneTree

## Rendered Vulkan/Mobile diagnostic. GPU markers bracket parameter upload and
## compute; glyph drawing, presentation and CPU snapshot application are separate.
const WARMUP := 30
const SAMPLES := 150
const DT := 1.0 / 30.0
var gpu_samples: Array[float] = []
var snapshot_samples: Array[float] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("GPU_BENCH_META engine=%s renderer=%s" % [Engine.get_version_info().string, RenderingServer.get_current_rendering_method()])
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 12.0, 38.0)
	camera.rotation.x = deg_to_rad(-15.0)
	world.add_child(camera)
	camera.current = true
	for count: int in [256, 1024]:
		gpu_samples.clear()
		snapshot_samples.clear()
		var cpu_submit: Array[float] = []
		var visual_cpu: Array[float] = []
		var sim := GpuFlightSimulation.new()
		sim.profile_gpu = true
		sim.gpu_timing_sample.connect(func(ms: float) -> void: gpu_samples.append(ms))
		sim.snapshot_applied.connect(func(ms: float) -> void: snapshot_samples.append(ms))
		sim.mushroom_centers = PackedVector2Array([Vector2(-14.4, -13.2), Vector2(14.6, -12.0), Vector2(15.4, 13.6)])
		sim.obstacle_centers = PackedVector2Array([Vector2(-8.0, -7.0), Vector2(8.0, -6.0), Vector2(8.0, 7.0)])
		sim.obstacle_radii = PackedFloat32Array([0.7, 0.8, 0.75])
		sim.goal_position = Vector2(0.0, 18.0)
		var preset := HerdPreset.builtins()[5]
		sim.reset(count, 40721, preset)
		for _frame: int in 180:
			await process_frame
			if sim.gpu_ready or not sim.gpu_error.is_empty(): break
		if not sim.gpu_ready:
			push_error("GPU benchmark initialization failed: " + sim.gpu_error)
			sim.dispose()
			quit(1)
			return
		var swarm := GlyphSwarm.new()
		world.add_child(swarm)
		swarm.configure(count)
		var field := LightField.new()
		field.obstacle_centers = sim.obstacle_centers
		field.obstacle_radii = sim.obstacle_radii
		field.source_position = Vector3(-14.4, 5.0, -13.2)
		field.source_direction = Vector3.DOWN
		# Ten extra ticks allow delayed timestamp queries to reach the CPU.
		for tick: int in WARMUP + SAMPLES + 10:
			field.mode = ((tick / 60) % 3) as LightField.Mode
			var started := Time.get_ticks_usec()
			sim.step(DT, field)
			var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
			if tick >= WARMUP and tick < WARMUP + SAMPLES: cpu_submit.append(elapsed_ms)
			started = Time.get_ticks_usec()
			swarm.update_swarm(sim, 0.5, preset)
			elapsed_ms = float(Time.get_ticks_usec() - started) / 1000.0
			if tick >= WARMUP and tick < WARMUP + SAMPLES: visual_cpu.append(elapsed_ms)
			await process_frame
		if gpu_samples.size() < WARMUP + SAMPLES:
			push_error("GPU timestamp samples missing: %d" % gpu_samples.size())
			sim.dispose()
			quit(1)
			return
		var measured_gpu: Array[float] = gpu_samples.slice(WARMUP, WARMUP + SAMPLES)
		print("GPU_BENCH count=%d gpu_upload_compute_ms=%s cpu_submit_ms=%s visual_cpu_ms=%s snapshot_apply_ms=%s finite=%s" % [count, _stats(measured_gpu), _stats(cpu_submit), _stats(visual_cpu), _stats(snapshot_samples), sim.is_finite_and_bounded()])
		swarm.queue_free()
		sim.dispose()
		await process_frame
		await process_frame
	world.queue_free()
	await process_frame
	print("GPU_BENCH_DONE")
	quit()

func _stats(values: Array[float]) -> String:
	if values.is_empty(): return "n/a"
	var ordered := values.duplicate()
	ordered.sort()
	return "n=%d,p50=%.4f,p95=%.4f,p99=%.4f,max=%.4f" % [ordered.size(), ordered[int(ceil(ordered.size() * 0.5)) - 1], ordered[int(ceil(ordered.size() * 0.95)) - 1], ordered[int(ceil(ordered.size() * 0.99)) - 1], ordered[-1]]
