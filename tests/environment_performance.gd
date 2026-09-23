extends SceneTree

# Full-scene desktop diagnostic, run three times per configuration externally.
# XDG_DATA_HOME=/tmp/mushi-bench-1 MUSHI_BENCH_SECONDS=30 godot --path . --rendering-driver vulkan --rendering-method mobile --disable-vsync --script tests/environment_performance.gd
# MUSHI_BENCH_COUNT=512 and MUSHI_BENCH_QUALITY=low select the accessible preset.
# MUSHI_BENCH_CAPTURE_DIR=/absolute/path optionally saves route screenshots.
# These times are desktop diagnostics, not headset frame-delivery proof.

const WARMUP_SECONDS := 5.0
const ROUTES := ["central_wake", "wooded_view"]

var _compute_samples: Array[float] = []
var _phase_build_samples: Array[float] = []
var _phase_sim_samples: Array[float] = []
var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use isolated XDG_DATA_HOME under /tmp/mushi- for benchmarks")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Run environment benchmark in a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	lab.player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The same script can run in the frozen pre-environment checkout. Its main
	# has no terrain/quality API; record that mode and retain the same route intent.
	var environment_enabled: bool = lab.get("environment_enabled") == true
	var count := 512 if OS.get_environment("MUSHI_BENCH_COUNT") == "512" else 1024
	var quality_name := "low" if OS.get_environment("MUSHI_BENCH_QUALITY") == "low" else "high"
	if environment_enabled and lab.has_method("_apply_quality"):
		var quality: Dictionary = lab.quality_menu.get_settings()
		quality["vegetation"] = quality_name
		quality["shadows"] = quality_name
		quality["render_scale"] = 0.8 if quality_name == "low" else 1.0
		lab._apply_quality(quality)
	# Recreate the accepted private loose-trains values without reading its JSON.
	lab._apply_preset(7, false)
	lab.current_preset.formation_follow_weight = 0.55
	lab.current_preset.cluster_pressure_weight = 1.1
	lab.current_preset.cluster_target_neighbors = 2.0
	lab.current_preset.arousal_contagion_strength = 0.45
	lab.current_preset.arousal_scatter_strength = 0.65
	lab.current_preset.glyph_render_scale = 0.6
	lab.strength_slider.set_value_no_signal(0.8)
	lab.social_slider.set_value_no_signal(1.4)
	lab.wander_slider.set_value_no_signal(0.8)
	lab._set_fixture(count)
	await _wait_gpu(lab)
	if lab._active_backend != "gpu" or not lab.simulation.gpu_ready:
		_failures.append("GPU simulation unavailable: %s" % lab.simulation.gpu_error)
		await _finish(lab)
		return
	lab.debug_visible = false
	for node_name: String in ["panel", "field_overlay", "flight_goal_volume"]:
		var debug_node: Node = lab.get(node_name)
		if debug_node != null:
			debug_node.set("visible", false)
	lab.simulation.profile_gpu = true
	lab.simulation.gpu_timing_sample.connect(func(ms: float) -> void: _compute_samples.append(ms))
	lab.simulation.gpu_phase_timing_sample.connect(func(build_ms: float, sim_ms: float) -> void:
		_phase_build_samples.append(build_ms)
		_phase_sim_samples.append(sim_ms)
	)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var seconds := maxf(3.0, float(OS.get_environment("MUSHI_BENCH_SECONDS"))) if not OS.get_environment("MUSHI_BENCH_SECONDS").is_empty() else 30.0
	var terrain_size: int = int(lab.get("terrain_size")) if environment_enabled else 0
	print("M1_BENCH_META engine=%s renderer=%s count=%d quality=%s terrain=%d seed=%d seconds_per_route=%.1f warmup=%.1f resolution=%s viewport_scale=%.2f gpu=%s cpu=%s" % [Engine.get_version_info().string, RenderingServer.get_current_rendering_method(), count, quality_name, terrain_size, lab.current_seed, seconds, WARMUP_SECONDS, root.get_texture().get_size(), root.scaling_3d_scale, RenderingServer.get_video_adapter_name(), OS.get_processor_name()])
	for route: String in ROUTES:
		_place_route(lab, route)
		await _sample_route(lab, route, count, quality_name, seconds)
	await _finish(lab)


func _place_route(lab: Node, route: String) -> void:
	var environment_enabled: bool = lab.get("environment_enabled") == true
	# Identical static viewpoints in the frozen arena and the new basin.
	var xz := Vector2(-14.4, -8.0) if route == "central_wake" else Vector2(20.0, 20.0)
	var ground_height: float = lab.world_surface.get_height_at(xz) if environment_enabled else 0.0
	lab.player.position = Vector3(xz.x, ground_height + 0.05, xz.y)
	lab.player.reset_look()
	if route == "wooded_view":
		lab.player.rotate_y(2.3)
	lab.lantern.set_mode(LightField.Mode.ORANGE if route == "central_wake" else LightField.Mode.CLEAR)


func _sample_route(lab: Node, route: String, count: int, quality: String, seconds: float) -> void:
	var start_usec := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start_usec) < WARMUP_SECONDS * 1000000.0:
		await process_frame
	_compute_samples.clear()
	_phase_build_samples.clear()
	_phase_sim_samples.clear()
	var wall_frames: Array[float] = []
	var process_times: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var memory: Array[float] = []
	start_usec = Time.get_ticks_usec()
	var previous_usec := start_usec
	while float(Time.get_ticks_usec() - start_usec) < seconds * 1000000.0:
		await process_frame
		RenderingServer.call_on_render_thread(lab.simulation._collect_gpu_timing.bind(lab.simulation._epoch))
		var now_usec := Time.get_ticks_usec()
		wall_frames.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		process_times.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		memory.append(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0))
		if route == "central_wake" and float(now_usec - start_usec) > minf(10.0, seconds * 0.5) * 1000000.0:
			lab.lantern.set_mode(LightField.Mode.CLEAR)
	var capture_dir := OS.get_environment("MUSHI_BENCH_CAPTURE_DIR")
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)
		await RenderingServer.frame_post_draw
		var capture := capture_dir.path_join("m1-%s-%d-%s.png" % [route, count, quality])
		if root.get_texture().get_image().save_png(capture) != OK:
			_failures.append("capture failed: " + capture)
	var finite: bool = lab.simulation.is_finite_and_bounded()
	if not finite:
		_failures.append("non-finite simulation in " + route)
	if _compute_samples.is_empty():
		_failures.append("missing GPU timestamps in " + route)
	print("M1_BENCH route=%s count=%d quality=%s wall_ms=%s process_ms=%s viewport_render_cpu_ms=%s viewport_render_gpu_ms=%s gpu_upload_compute_ms=%s gpu_build_ms=%s gpu_simulate_ms=%s draws=%s primitives=%s video_mem_mib=%s finite=%s score=%d ticks=%d" % [route, count, quality, _stats(wall_frames), _stats(process_times), _stats(render_cpu), _stats(render_gpu), _stats(_compute_samples), _stats(_phase_build_samples), _stats(_phase_sim_samples), _stats(draw_calls), _stats(primitives), _stats(memory), finite, lab.simulation.score, lab.simulation.state_revision])


func _wait_gpu(lab: Node) -> void:
	for _frame: int in 240:
		await process_frame
		if lab._active_backend != "gpu" or lab.simulation.gpu_ready:
			return


func _stats(values: Array[float]) -> String:
	if values.is_empty():
		return "n=0"
	var ordered := values.duplicate()
	ordered.sort()
	return "n=%d,p50=%.3f,p95=%.3f,p99=%.3f,max=%.3f" % [ordered.size(), ordered[clampi(ceili(ordered.size() * 0.50) - 1, 0, ordered.size() - 1)], ordered[clampi(ceili(ordered.size() * 0.95) - 1, 0, ordered.size() - 1)], ordered[clampi(ceili(ordered.size() * 0.99) - 1, 0, ordered.size() - 1)], ordered[-1]]


func _finish(lab: Node) -> void:
	lab.queue_free()
	await process_frame
	await process_frame
	for failure: String in _failures:
		push_error(failure)
	print("M1_BENCH_DONE failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
