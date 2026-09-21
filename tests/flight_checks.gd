extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	print("FLIGHT_CHECKS Godot=%s" % Engine.get_version_info().string)
	_test_seeded_reset_and_cluster_balance()
	_test_true_3d_social_and_motion()
	_test_height_and_trunk_bounds()
	_test_sleep_settle_and_orange_wake()
	_test_blue_target_and_orange_direction()
	_test_goal_scores_once()
	_test_mixed_run_finite()
	_benchmark(24)
	_benchmark(64)
	if failures == 0:
		print("FLIGHT_CHECKS PASS checks=%d failures=0" % checks)
	else:
		printerr("FLIGHT_CHECKS FAIL checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_seeded_reset_and_cluster_balance() -> void:
	var sim := FlightSimulation.new()
	var preset := HerdPreset.builtins()[3]
	sim.reset(64, 40721, preset)
	var first := sim.positions.duplicate()
	var first_velocities := sim.velocities.duplicate()
	for _tick: int in 120:
		sim.step(1.0 / 60.0, _clear_field())
	var replay_positions := sim.positions.duplicate()
	var replay_velocities := sim.velocities.duplicate()
	sim.reset(64, 40721, preset)
	for _tick: int in 120:
		sim.step(1.0 / 60.0, _clear_field())
	_expect(sim.positions == replay_positions and sim.velocities == replay_velocities, "fixed-step 3D replay reproduces positions and velocities")
	var counts := [0, 0, 0]
	for group: int in sim.group_ids:
		counts[group] += 1
	sim.reset(64, 40721, preset)
	_expect(sim.positions == first and sim.velocities == first_velocities, "seeded 3D reset is deterministic")
	_expect(counts == [22, 21, 21], "64-agent spawn is balanced round-robin across three patches")
	sim.reset(3, 40721, preset)
	_expect(sim.group_ids == PackedInt32Array([0, 0, 0]), "tiny fixture stays together at its single active mushroom patch")


func _test_true_3d_social_and_motion() -> void:
	var preset := _isolated_preset()
	preset.social_enabled = true
	preset.cohesion_weight = 1.0
	preset.alignment_weight = 0.0
	preset.separation_weight = 0.0
	var sim := _single_agent_sim(preset)
	var positions := PackedVector3Array([Vector3(0.0, 0.4, 0.0), Vector3(0.0, 2.0, 0.0)])
	var velocities := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var states := PackedInt32Array([FlightSimulation.Lifecycle.ACTIVE, FlightSimulation.Lifecycle.ACTIVE])
	var force := sim._social_force(0, positions, velocities, states)
	_expect(force.y > 0.1 and absf(force.x) < 0.001 and absf(force.z) < 0.001, "social cohesion uses vertical neighbor separation")
	var start_y := sim.positions[0].y
	for _tick: int in 180:
		sim.step(1.0 / 60.0, _clear_field())
	_expect(absf(sim.positions[0].y - start_y) > 0.08, "awake clear-field motion evolves in height")


func _test_height_and_trunk_bounds() -> void:
	var sim := FlightSimulation.new()
	sim.obstacle_centers = PackedVector2Array([Vector2.ZERO])
	sim.obstacle_radii = PackedFloat32Array([1.0])
	var constrained := sim._constrain_motion(Vector3(-3.0, 1.4, 0.0), Vector3(12.0, 20.0, 0.0), 0.5)
	var position: Vector3 = constrained[0]
	_expect(Vector2(position.x, position.z).length() >= 1.0 + FlightSimulation.BODY_RADIUS - 0.001 and position.x < 0.0, "high-speed XZ sweep cannot tunnel through a trunk")
	_expect(position.y <= sim.max_height and position.y >= sim.min_height, "swept motion clamps exact floor and ceiling")


func _test_sleep_settle_and_orange_wake() -> void:
	var preset := _isolated_energy_preset()
	var sim := FlightSimulation.new()
	sim.spawn_centers = PackedVector2Array([Vector2.ZERO])
	sim.mushroom_centers = PackedVector2Array([Vector2.ZERO])
	sim.goal_position = Vector2(100.0, 100.0)
	sim.reset(1, 101, preset)
	sim.positions[0] = Vector3(0.0, 1.7, 0.0)
	sim.velocities[0] = Vector3.ZERO
	sim.arousals[0] = preset.blue_energy_target
	for _tick: int in 600:
		sim.step(1.0 / 60.0, _clear_field())
	_expect(sim.positions[0].y < 0.75 and sim.velocities[0].length() < 0.18, "dormant flyer settles near mushroom cap instead of freezing aloft")
	var orange := _field(LightField.Mode.ORANGE)
	orange.source_position = Vector3(0.0, 1.2, 2.0)
	orange.source_direction = (sim.positions[0] - orange.source_position).normalized()
	for _tick: int in 180:
		sim.step(1.0 / 60.0, orange)
	_expect(sim.arousals[0] > 0.6, "orange wakes a flyer despite simultaneous mushroom suppression")
	_expect(sim.positions[0].y > sim.min_height + 0.18, "awakened flyer lifts out of the floor band")


func _test_blue_target_and_orange_direction() -> void:
	var preset := _isolated_preset()
	var blue_sim := _single_agent_sim(preset)
	var blue := _field(LightField.Mode.BLUE)
	blue.source_position = Vector3(0.0, 2.5, 3.0)
	blue.source_direction = Vector3(0.0, -0.15, -1.0).normalized()
	blue_sim.step(0.1, blue)
	var blue_direction := (blue.flight_target(blue_sim.min_height, blue_sim.max_height) - Vector3(0.0, 1.0, 0.0)).normalized()
	_expect(blue_sim.accelerations[0].dot(blue_direction) > 0.01, "blue steering follows the clamped 3D flight target")
	var orange_sim := _single_agent_sim(preset)
	var orange := _field(LightField.Mode.ORANGE)
	orange.source_direction = (Vector3(0.0, 1.0, 0.0) - orange.source_position).normalized()
	orange_sim.step(0.1, orange)
	var horizontal_away := Vector2(-orange.source_position.x, -orange.source_position.z).normalized()
	var horizontal_force := Vector2(orange_sim.accelerations[0].x, orange_sim.accelerations[0].z)
	_expect(horizontal_force.dot(horizontal_away) > 0.01, "orange steering flees the lantern in the horizontal plane")


func _test_goal_scores_once() -> void:
	var preset := _isolated_preset()
	var sim := _single_agent_sim(preset)
	sim.goal_position = Vector2.ZERO
	sim.goal_radius = 2.0
	sim.goal_dwell_seconds = 0.02
	for _tick: int in 300:
		sim.step(1.0 / 60.0, _clear_field())
	_expect(sim.score == 1 and sim.lifecycles[0] == FlightSimulation.Lifecycle.RELEASED, "flight-band goal scores once and completes ascent")
	_expect(sim.active_count() == 0, "released flyer leaves social population")


func _test_mixed_run_finite() -> void:
	var sim := FlightSimulation.new()
	sim.obstacle_centers = PackedVector2Array([Vector2(-5.6, -4.4), Vector2(6.0, 4.0), Vector2(2.0, -14.0)])
	sim.obstacle_radii = PackedFloat32Array([1.05, 1.2, 0.85])
	sim.mushroom_centers = PackedVector2Array(FlightSimulation.DEFAULT_SPAWN_CENTERS)
	sim.reset(64, 9981, HerdPreset.builtins()[3])
	var field := _field(LightField.Mode.BLUE)
	for tick: int in 900:
		if tick == 300:
			field.mode = LightField.Mode.ORANGE
		elif tick == 600:
			field = _clear_field()
		field.source_position = sim.positions[tick % 64] + Vector3(0.0, 0.8, 3.0)
		field.source_direction = Vector3(0.0, -0.8, -3.0).normalized()
		sim.step(1.0 / 60.0, field)
	_expect(sim.is_finite_and_bounded(), "64-agent mixed field run stays finite and bounded")


func _benchmark(agent_count: int) -> void:
	var sim := FlightSimulation.new()
	sim.reset(agent_count, 40721, HerdPreset.builtins()[3])
	var field := _clear_field()
	var samples := PackedFloat32Array()
	for tick: int in 240:
		var started := Time.get_ticks_usec()
		sim.step(1.0 / 60.0, field)
		if tick >= 30:
			samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	samples.sort()
	var median := samples[samples.size() / 2]
	var p95 := samples[int(floor(float(samples.size() - 1) * 0.95))]
	print("  BENCH active_clear agents=%d ticks=%d median_ms=%.3f p95_ms=%.3f" % [agent_count, samples.size(), median, p95])
	_expect(median >= 0.0 and p95 >= median, "%d-agent benchmark produced ordered timing samples" % agent_count)


func _single_agent_sim(preset: HerdPreset) -> FlightSimulation:
	var sim := FlightSimulation.new()
	sim.spawn_centers = PackedVector2Array([Vector2.ZERO])
	sim.reset(1, 101, preset)
	sim.positions[0] = Vector3(0.0, 1.0, 0.0)
	sim.previous_positions[0] = sim.positions[0]
	sim.velocities[0] = Vector3.ZERO
	sim.goal_position = Vector2(100.0, 100.0)
	return sim


func _isolated_preset() -> HerdPreset:
	var preset := HerdPreset.builtins()[2].copy_preset()
	preset.wander_weight = 0.0
	preset.max_acceleration = 8.0
	preset.max_speed = 3.0
	preset.goal_repulsion_strength = 0.0
	return preset


func _isolated_energy_preset() -> HerdPreset:
	var preset := HerdPreset.builtins()[3].copy_preset()
	preset.social_enabled = false
	preset.separation_weight = 0.0
	preset.alignment_weight = 0.0
	preset.cohesion_weight = 0.0
	preset.wander_weight = 0.0
	preset.goal_repulsion_strength = 0.0
	return preset


func _field(mode: LightField.Mode) -> LightField:
	var field := LightField.new()
	field.mode = mode
	field.shutter_openness = 1.0
	field.range_m = 10.5
	field.half_angle_degrees = 55.0
	field.source_position = Vector3(0.0, 1.2, 3.0)
	field.source_direction = Vector3(0.0, -0.1, -1.0).normalized()
	return field


func _clear_field() -> LightField:
	var field := _field(LightField.Mode.CLEAR)
	field.shutter_openness = 0.0
	return field


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % message)
	else:
		failures += 1
		printerr("  FAIL  %s" % message)
