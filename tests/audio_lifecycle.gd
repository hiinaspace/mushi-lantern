extends SceneTree

# Repeated full-scene audio stop/reset/restart and clean extension teardown.

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		push_error("Audio lifecycle check requires rendering and a real audio driver")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(0, capture)
	for cycle: int in 4:
		if cycle > 0:
			lab._reset_run(false)
		var started := Time.get_ticks_msec()
		while not lab.simulation.gpu_ready and Time.get_ticks_msec() - started < 15000:
			await process_frame
		if not lab.simulation.gpu_ready:
			push_error("GPU unavailable after audio cycle %d" % cycle)
			quit(2)
			return
		lab.grove_audio.start_stress_voices(24)
		await create_timer(1.4).timeout
		var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
		var peak := 0.0
		for index: int in range(0, frames.size(), 16):
			peak = maxf(peak, maxf(absf(frames[index].x), absf(frames[index].y)))
		print("AUDIO_LIFECYCLE cycle=%d peak=%.6f snapshots=%d" % [cycle, peak, lab.simulation.snapshot_revision])
		if peak <= 0.00001 or capture.get_discarded_frames() != 0:
			push_error("Audio silent or capture overflow during cycle %d" % cycle)
			quit(1)
			return
		lab.grove_audio.stop_stress_voices()
		await create_timer(0.2).timeout
	lab.queue_free()
	await process_frame
	print("AUDIO_LIFECYCLE_PASS")
	quit()
