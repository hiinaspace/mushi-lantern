extends SceneTree

## Short, deterministic diagnostic for the 256/1024 Living shoals fixtures.
## Run from the project root with:
##   godot --path . --headless --script tests/performance_compare.gd
## For the optional rendered frame/draw-call sample, omit --headless, pass --rendering-method mobile, and set
## MUSHI_RENDERED_BENCH=1. Godot exposes draw counts and CPU process time here,
## but not portable GPU execution time; do not interpret these as GPU timings.

const SEED := 40721
const STEP := 1.0 / 30.0
const WARMUP_TICKS := 30
const SAMPLES := 150
const COUNTS := [256, 1024]
const PRESET_INDEX := 5

var _visual: GlyphSwarm
var _simulation: FlightSimulation
var _preset: HerdPreset
var _field := LightField.new()
var _rendered := false


func _initialize() -> void:
	_rendered = OS.get_environment("MUSHI_RENDERED_BENCH") == "1"
	_preset = HerdPreset.builtins()[PRESET_INDEX]
	if _rendered:
		_setup_render_scene()
	await _run()


func _setup_render_scene() -> void:
	var world := Node3D.new()
	world.name = "BenchmarkWorld"
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 12.0, 38.0)
	camera.rotation.x = deg_to_rad(-15.0)
	camera.current = true
	world.add_child(camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("161d24")
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	_visual = GlyphSwarm.new()
	world.add_child(_visual)


func _run() -> void:
	print("BENCH_META godot=%s renderer=%s seed=%d preset=%s step_hz=30 warmup=%d samples=%d scenarios=clear_blue_orange_60_ticks_lamp_over_patch rendered=%s" % [Engine.get_version_info().string, ProjectSettings.get_setting("rendering/renderer/rendering_method"), SEED, _preset.preset_name, WARMUP_TICKS, SAMPLES, str(_rendered)])
	for count: int in COUNTS:
		await _run_count(count)
	print("BENCH_DONE")
	quit()


func _run_count(count: int) -> void:
	_simulation = FlightSimulation.new()
	_field = LightField.new()
	_field.obstacle_centers = PackedVector2Array([Vector2(-8.0, -7.0), Vector2(8.0, -6.0), Vector2(8.0, 7.0)])
	_field.obstacle_radii = PackedFloat32Array([0.7, 0.8, 0.75])
	_simulation.obstacle_centers = _field.obstacle_centers
	_simulation.obstacle_radii = _field.obstacle_radii
	_simulation.mushroom_centers = PackedVector2Array([Vector2(-14.4, -13.2), Vector2(14.6, -12.0), Vector2(15.4, 13.6)])
	_simulation.goal_position = Vector2(0.0, 18.0)
	_simulation.reset(count, SEED, _preset)
	if _rendered:
		_visual.configure(count)
		await process_frame
		_visual.update_swarm(_simulation, 0.0, _preset)

	var sim_samples: Array[float] = []
	var neighbor_samples: Array[float] = []
	var visual_samples: Array[float] = []
	var frames: Array[float] = []
	var cpu_process_samples: Array[float] = []
	var visual_only_cpu_samples: Array[float] = []
	var visual_only_process_samples: Array[float] = []
	var draw_calls := 0
	for tick: int in WARMUP_TICKS + SAMPLES:
		_set_scenario(tick)
		var start := Time.get_ticks_usec()
		_simulation.step(STEP, _field)
		var duration := float(Time.get_ticks_usec() - start) / 1000.0
		if tick >= WARMUP_TICKS:
			sim_samples.append(duration)

		start = Time.get_ticks_usec()
		_simulation._build_neighbor_lists(_simulation.positions, _simulation.lifecycles)
		duration = float(Time.get_ticks_usec() - start) / 1000.0
		if tick >= WARMUP_TICKS:
			neighbor_samples.append(duration)

		if _visual != null:
			start = Time.get_ticks_usec()
			_visual.update_swarm(_simulation, 0.5, _preset)
			duration = float(Time.get_ticks_usec() - start) / 1000.0
			if tick >= WARMUP_TICKS:
				visual_samples.append(duration)
			await process_frame
			if tick >= WARMUP_TICKS:
				frames.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
				cpu_process_samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
				draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _visual != null:
		# Paired control: hold the simulation state fixed and measure only glyph
		# upload/update plus rendered frame processing at the same population.
		for _frame: int in SAMPLES:
			var start := Time.get_ticks_usec()
			_visual.update_swarm(_simulation, 0.5, _preset)
			var duration := float(Time.get_ticks_usec() - start) / 1000.0
			visual_only_cpu_samples.append(duration)
			await process_frame
			visual_only_process_samples.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
			draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

	print("BENCH_RESULT count=%d active=%d sim_tick_ms=%s neighbor_build_ms=%s visual_cpu_with_step_ms=%s rendered_process_with_step_ms=%s physics_process_ms=%s visual_cpu_no_step_ms=%s rendered_process_no_step_ms=%s draw_calls=%d finite=%s" % [count, _simulation.active_count(), _stats(sim_samples), _stats(neighbor_samples), _stats(visual_samples), _stats(frames), _stats(cpu_process_samples), _stats(visual_only_cpu_samples), _stats(visual_only_process_samples), draw_calls, str(_simulation.is_finite_and_bounded())])


func _set_scenario(tick: int) -> void:
	# Fixed 2-second clear, blue and orange phases over the first mushroom patch.
	# This gives the scripted lamp meaningful exposure of seeded residents.
	var phase := (tick / 60) % 3
	_field.source_position = Vector3(-14.4, 5.0, -13.2)
	_field.source_direction = Vector3(0.0, -1.0, 0.0)
	_field.shutter_openness = 1.0
	_field.mode = phase as LightField.Mode
	_field.mode_strength = 1.0


func _stats(input: Array[float]) -> String:
	if input.is_empty():
		return "n/a"
	var values := input.duplicate()
	values.sort()
	var total := 0.0
	for value: float in values:
		total += value
	return "n=%d mean=%.4f p50=%.4f p95=%.4f p99=%.4f max=%.4f" % [values.size(), total / values.size(), _percentile(values, 0.50), _percentile(values, 0.95), _percentile(values, 0.99), values[values.size() - 1]]


func _percentile(sorted: Array[float], quantile: float) -> float:
	var index := clampi(int(ceil(quantile * sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[index]
