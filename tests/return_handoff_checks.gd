extends SceneTree

## CPU-side lifecycle check for the brief surface cue. This does not require a
## renderer and deliberately leaves blocker/depth rendering to the scene shader.
class FakeSimulation extends RefCounted:
	var committed_this_step: Array[int] = []
	var positions: Array[Vector3] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var cue := ReturnHandoffVisual.new()
	root.add_child(cue)
	cue.configure(2)
	var sim := FakeSimulation.new()
	sim.positions = [Vector3(2.0, 4.0, 6.0), Vector3(-1.0, 3.0, 2.0)]
	_check(cue._ages[0] >= ReturnHandoffVisual.CUE_SECONDS - 0.001, "cue starts expired", failures)
	cue.update_handoffs(sim, 0.0, Vector2(10.0, 12.0), 1.0)
	_check(cue._started[0] == 0, "no cue without a scored return", failures)

	sim.committed_this_step = [0]
	cue.update_handoffs(sim, 0.0, Vector2(10.0, 12.0), 1.0)
	sim.committed_this_step.clear()
	_check(cue._started[0] == 1 and cue._ages[0] == 0.0, "scoring starts one cue", failures)
	_check(cue._origins[0].is_equal_approx(Vector3(2.0, 4.0, 6.0)), "cue records the scored agent position", failures)

	cue.update_handoffs(sim, ReturnHandoffVisual.CUE_SECONDS * 0.5, Vector2(10.0, 12.0), 1.0)
	_check(is_equal_approx(cue._ages[0], ReturnHandoffVisual.CUE_SECONDS * 0.5), "cue remains active during travel", failures)
	var half_beam := ReturnHandoffVisual.beam_scale(0.5)
	_check(half_beam.y > 1.8 and half_beam.y < 2.0 and half_beam.x < 0.18,
		"return cue draws a long narrow vertical beam behind its ball", failures)

	cue.update_handoffs(sim, ReturnHandoffVisual.CUE_SECONDS, Vector2(10.0, 12.0), 1.0)
	_check(cue._ages[0] >= ReturnHandoffVisual.CUE_SECONDS - 0.001, "cue expires after its short lifetime", failures)
	cue.update_handoffs(sim, 1.0, Vector2(10.0, 12.0), 1.0)
	_check(cue._ages[0] >= ReturnHandoffVisual.CUE_SECONDS - 0.001, "completed cue does not restart without a new score", failures)

	cue.configure(2)
	_check(cue._started[0] == 0 and cue._ages[0] >= ReturnHandoffVisual.CUE_SECONDS - 0.001, "reconfiguration resets cue state", failures)
	sim.committed_this_step = [0]
	cue.update_handoffs(sim, 0.0, Vector2(10.0, 12.0), 1.0)
	_check(cue._started[0] == 1 and cue._ages[0] == 0.0, "reset cue can play on a later run", failures)
	_check(_shader_draws_through_terrain(), "surface cue shader draws return ball and beam through terrain", failures)

	for failure: String in failures:
		push_error(failure)
	print("RETURN_HANDOFF_CHECKS failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _shader_draws_through_terrain() -> bool:
	var source := FileAccess.get_file_as_string("res://shaders/return_handoff.gdshader")
	return source.contains("depth_test_disabled") and source.contains("depth_draw_never") and source.contains("float beam")
