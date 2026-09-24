extends SceneTree

# Full rendered-grove audio budget fixture. Run with a real audio driver and
# -- --desktop --count 1024. MUSHI_AUDIO_STRESS_VOICES selects 0..24; use
# MUSHI_AUDIO_DISABLED=1 for the otherwise identical zero-audio baseline.

var _snapshot_ms: Array[float] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		push_error("Audio performance requires a rendered window and real audio driver")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var voices := clampi(int(OS.get_environment("MUSHI_AUDIO_STRESS_VOICES")), 0, 24)
	var seconds := maxf(float(OS.get_environment("MUSHI_AUDIO_STRESS_SECONDS")), 4.0)
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if lab._active_backend != "gpu" or lab.fixture_count != 1024:
		push_error("Expected 1024 GPU agents in the terrain scene")
		quit(2)
		return
	var started := Time.get_ticks_msec()
	while not lab.simulation.gpu_ready and Time.get_ticks_msec() - started < 15000:
		await process_frame
	if not lab.simulation.gpu_ready:
		push_error("GPU simulation did not become ready")
		quit(2)
		return
	lab.simulation.snapshot_applied.connect(_on_snapshot)
	lab.grove_audio.start_stress_voices(voices)
	for frame: int in 120:
		await process_frame
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0, capture)
	var frame_ms: Array[float] = []
	var process_ms: Array[float] = []
	var peak := 0.0
	var capture_clock := 0.0
	var end_usec := Time.get_ticks_usec() + int(seconds * 1000000.0)
	var last_usec := Time.get_ticks_usec()
	while Time.get_ticks_usec() < end_usec:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var wall_ms := float(now_usec - last_usec) / 1000.0
		last_usec = now_usec
		frame_ms.append(wall_ms)
		process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		capture_clock += wall_ms / 1000.0
		if capture_clock >= 0.4:
			capture_clock = 0.0
			var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
			for index: int in range(0, frames.size(), 16):
				peak = maxf(peak, maxf(absf(frames[index].x), absf(frames[index].y)))
	var tail: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	for index: int in range(0, tail.size(), 16):
		peak = maxf(peak, maxf(absf(tail[index].x), absf(tail[index].y)))
	frame_ms.sort()
	process_ms.sort()
	_snapshot_ms.sort()
	var discarded := capture.get_discarded_frames()
	print("AUDIO_PERF voices=%d seconds=%.1f frames=%d wall_p50=%.3f wall_p95=%.3f wall_p99=%.3f process_p95=%.3f snapshots=%d snapshot_p95=%.3f peak=%.6f discarded=%d" % [voices, seconds, frame_ms.size(), _percentile(frame_ms, 0.50), _percentile(frame_ms, 0.95), _percentile(frame_ms, 0.99), _percentile(process_ms, 0.95), _snapshot_ms.size(), _percentile(_snapshot_ms, 0.95), peak, discarded])
	lab.grove_audio.stop_stress_voices()
	lab.queue_free()
	await process_frame
	if frame_ms.is_empty() or discarded != 0 or (voices > 0 and peak <= 0.00001):
		push_error("Audio performance fixture had no frames, lost capture, or silent output")
		quit(1)
	else:
		print("AUDIO_PERF_PASS")
		quit()


func _on_snapshot(milliseconds: float) -> void:
	_snapshot_ms.append(milliseconds)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	return values[clampi(roundi(float(values.size() - 1) * fraction), 0, values.size() - 1)]
