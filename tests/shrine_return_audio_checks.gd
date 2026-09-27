extends SceneTree

const GroveAudioScript = preload("res://scripts/grove_audio.gd")


func _initialize() -> void:
	var failures := 0
	for path: Array in [
		["classic score increment", 0, 1, true],
		["first two-shrine goal increment", 0, 1, true],
		["second two-shrine goal increment", 3, 4, true],
		["unchanged score", 2, 2, false],
		["score reset", 5, 0, false],
		["initial or late-join baseline", -1, 4, false],
	]:
		if GroveAudioScript.should_play_shrine_confirmation(path[1], path[2]) != path[3]:
			push_error("Score confirmation gate failed: %s" % path[0])
			failures += 1
	var audio := GroveAudioScript.new()
	var pulse: AudioStreamWAV = audio._make_shrine_return_stream()
	var expected_bytes := int(pulse.mix_rate * 0.34 * 2.0)
	if pulse.format != AudioStreamWAV.FORMAT_16_BITS or pulse.mix_rate != 24000 or pulse.data.size() != expected_bytes:
		push_error("Shrine pulse must be 24 kHz mono 16-bit PCM with 340 ms duration")
		failures += 1
	else:
		var peak := 0
		for offset in range(0, pulse.data.size(), 2):
			peak = maxi(peak, absi(pulse.data.decode_s16(offset)))
		if peak < 1000 or absi(pulse.data.decode_s16(pulse.data.size() - 2)) > peak * 0.08:
			push_error("Shrine pulse waveform must have a glassy peak and short decaying tail")
			failures += 1
	audio.free()
	if failures == 0:
		print("SHRINE_RETURN_AUDIO_CHECKS PASS checks=7")
	else:
		push_error("SHRINE_RETURN_AUDIO_CHECKS FAIL failures=%d" % failures)
	quit(0 if failures == 0 else 1)
	return
