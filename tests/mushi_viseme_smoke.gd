extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ClassDB.class_exists("MushiVisemes"):
		push_error("MushiVisemes extension missing")
		quit(1)
		return
	var analyzer: Node = ClassDB.instantiate("MushiVisemes")
	root.add_child(analyzer)
	var deadline := Time.get_ticks_msec() + 5000
	while analyzer.get_status() == "loading" and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	if analyzer.get_status() != "ready":
		push_error("MushiVisemes: " + analyzer.get_status())
		quit(1)
		return
	var samples := PackedFloat32Array()
	samples.resize(480)
	for frame in 120:
		for index in samples.size():
			samples[index] = 0.18 * sin(TAU * 200.0 * float(frame * 480 + index) / 48000.0)
		analyzer.push_test_pcm("test", samples, 48000)
		await create_timer(0.01).timeout
	var weights: PackedFloat32Array = analyzer.get_weights("test")
	var hops: int = analyzer.get_stats("test").get("hops", 0)
	if weights.size() != 15 or hops < 20:
		push_error("Viseme inference did not advance: hops=%d weights=%d" % [hops, weights.size()])
		quit(1)
		return
	for weight in weights:
		if not is_finite(weight) or weight < 0.0 or weight > 1.0:
			push_error("Invalid viseme weight")
			quit(1)
			return
	print("MUSHI_VISEME_SMOKE hops=%d status=%s" % [hops, analyzer.get_status()])
	quit()
