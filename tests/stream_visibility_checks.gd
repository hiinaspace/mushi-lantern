extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for mode: int in [LightField.Mode.CLEAR, LightField.Mode.BLUE, LightField.Mode.ORANGE]:
		var open_target := TerrainEnvironment.stream_visibility_target(1.0, 1.0, true)
		var opened := TerrainEnvironment.advance_stream_visibility(0.92, open_target, 0.016)
		_check(is_zero_approx(open_target) and is_zero_approx(opened), "%s open shutter hides stream immediately" % LightField.Mode.keys()[mode], failures)

	_check(is_zero_approx(TerrainEnvironment.stream_visibility_target(1.0, 0.0, false)), "tutorial gate keeps stream hidden before reveal", failures)
	_check(is_zero_approx(TerrainEnvironment.stream_visibility_target(0.0, 0.0, true)), "closed shutter alone does not reveal before adaptation", failures)
	var partial := TerrainEnvironment.stream_visibility_target(0.40, 0.0, true)
	_check(partial > 0.0 and partial < 1.0, "dark adaptation produces gradual partial reveal", failures)
	var adapted := TerrainEnvironment.stream_visibility_target(0.60, 0.0, true)
	_check(adapted > 0.75 and adapted < 1.0, "stream reaches visibility ahead of foliage threshold", failures)
	var halfway := TerrainEnvironment.advance_stream_visibility(0.0, adapted, 1.2)
	_check(halfway > 0.5 and halfway < adapted, "stream reveal eases in over time", failures)
	_check(is_zero_approx(TerrainEnvironment.advance_stream_visibility(halfway, 0.0, 0.016)), "opening the shutter bypasses fade-out", failures)
	_check(is_equal_approx(TerrainEnvironment.advance_stream_visibility(halfway, adapted, 0.0), halfway), "zero delta leaves easing state unchanged", failures)

	for failure in failures:
		push_error(failure)
	print("STREAM_VISIBILITY_CHECKS failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String, errors: Array[String]) -> void:
	if not condition:
		errors.append(message)
