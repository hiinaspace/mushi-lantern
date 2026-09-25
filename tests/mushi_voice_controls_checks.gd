extends SceneTree

func _initialize() -> void:
	var voice := MushiVoice.new()
	root.add_child.call_deferred(voice)
	_check.call_deferred(voice)

func _check(voice: MushiVoice) -> void:
	voice.setup(null, false)
	assert(voice.is_muted())
	assert(is_equal_approx(voice.get_gate_threshold_db(), -38.0))
	voice.set_gate_threshold_db(-47.0)
	assert(is_equal_approx(voice.get_gate_threshold_db(), -47.0))
	assert(is_equal_approx(float(voice.sender.get_gate_threshold_db()), -47.0))
	voice.set_gate_threshold_db(1.0)
	assert(is_equal_approx(voice.get_gate_threshold_db(), -20.0))
	voice.set_receive_gain_db(-6.0)
	assert(is_equal_approx(voice.get_receive_gain_db(), -6.0))
	assert(absf(voice.receive_gain - 0.5012) < 0.001)
	assert(is_equal_approx(voice.get_input_meter_db(), -80.0))
	assert(is_zero_approx(voice.get_input_meter_level()))
	assert(is_equal_approx(float(voice.sender.get_gated_rms_db()), -80.0))
	assert(is_zero_approx(voice.get_local_level()))
	voice.stop_session()
	voice.queue_free()
	print("MUSHI_VOICE_CONTROLS_OK")
	quit()
