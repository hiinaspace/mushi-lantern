extends SceneTree

# Run with a real audio driver and the patched Godot build. A private null
# sink is suitable; a headless Dummy driver does not prove audible output.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("SteamAudioPlayer"):
		push_error("SteamAudioPlayer is unavailable")
		quit(2)
		return
	if AudioServer.get_driver_name() == "Dummy":
		push_error("Audio spatial smoke requires a real audio driver")
		quit(2)
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var config: Node = ClassDB.instantiate("SteamAudioConfig")
	scene.add_child(config)
	var camera := Camera3D.new()
	scene.add_child(camera)
	var listener: Node = ClassDB.instantiate("SteamAudioListener")
	camera.add_child(listener)
	var player: Node3D = ClassDB.instantiate("SteamAudioPlayer")
	scene.add_child(player)
	player.set("point_source_binaural", true)
	player.set("panning_strength", 0.0)
	player.set("attenuation_model", AudioStreamPlayer3D.ATTENUATION_DISABLED)
	player.set("attenuation_filter_db", 0.0)
	player.set("distance_attenuation", false)
	var stream: AudioStreamWAV = (load("res://assets/audio/placeholders/forest_insects_01.wav") as AudioStreamWAV).duplicate()
	stream.loop_end = roundi(stream.get_length() * float(stream.mix_rate))
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, capture)
	player.call("play_stream", stream)
	player.position = Vector3(2.0, 0.0, 0.0)
	var right_ears: Vector2 = await _measure(capture)
	player.position = Vector3(-2.0, 0.0, 0.0)
	var left_ears: Vector2 = await _measure(capture)
	player.position = Vector3(2.0, 0.0, 0.0)
	camera.rotation.y = PI
	var turned_ears: Vector2 = await _measure(capture)
	var valid := right_ears.is_finite() and left_ears.is_finite() and turned_ears.is_finite()
	valid = valid and right_ears.x > 0.00001 and right_ears.y > right_ears.x * 1.3
	valid = valid and left_ears.y > 0.00001 and left_ears.x > left_ears.y * 1.3
	valid = valid and turned_ears.y > 0.00001 and turned_ears.x > turned_ears.y * 1.3
	valid = valid and capture.get_discarded_frames() == 0
	print("AUDIO_SPATIAL ears_right=%s ears_left=%s ears_turned=%s discarded=%d" % [right_ears, left_ears, turned_ears, capture.get_discarded_frames()])
	player.call("stop")
	scene.queue_free()
	await process_frame
	if valid:
		print("AUDIO_SPATIAL_PASS")
		quit()
	else:
		push_error("Steam Audio left/right or listener-turn check failed")
		quit(1)


func _measure(capture: AudioEffectCapture) -> Vector2:
	await create_timer(0.25).timeout
	AudioServer.lock()
	capture.clear_buffer()
	AudioServer.unlock()
	await create_timer(0.6).timeout
	var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	var sum_left := 0.0
	var sum_right := 0.0
	for frame: Vector2 in frames:
		sum_left += frame.x * frame.x
		sum_right += frame.y * frame.y
	var divisor := maxf(float(frames.size()), 1.0)
	return Vector2(sqrt(sum_left / divisor), sqrt(sum_right / divisor))
