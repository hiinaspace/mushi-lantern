extends Node

var failures: int = 0
var checks: int = 0

func _ready() -> void:
	print("M0_CHECKS Godot=%s" % Engine.get_version_info().string)
	_test_deterministic_reset()
	_test_field_shutter_and_occlusion()
	_test_field_aperture_and_range()
	_test_light_response_signs()
	_test_blue_settle_and_moving_catchup()
	_test_finite_bounded_all_presets()
	_test_obstacle_sweep_guard()
	_test_same_step_neighbor_snapshot()
	_test_goal_resistance_is_local_and_repellent()
	_test_lifecycle_accounting_and_neighbor_exclusion()
	_test_short_unattended_control()
	if failures == 0:
		print("M0_CHECKS PASS checks=%d failures=0" % checks)
	else:
		printerr("M0_CHECKS FAIL checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_deterministic_reset() -> void:
	var sim := FlockSimulation.new()
	var preset := HerdPreset.builtins()[0]
	sim.reset(24, 40721, preset)
	var first_positions := sim.positions.duplicate()
	var first_velocities := sim.velocities.duplicate()
	sim.reset(24, 40721, preset)
	_expect(sim.positions == first_positions, "same seed restores positions")
	_expect(sim.velocities == first_velocities, "same seed restores velocities")
	_expect(sim.active_count() == 24 and sim.score == 0, "reset restores finite active population and score")
	_expect(sim.committed_this_step.is_empty(), "reset clears transient commit events")

func _test_field_shutter_and_occlusion() -> void:
	var field := _forward_field(LightField.Mode.BLUE)
	var sample_point := Vector3(0.0, FlockSimulation.BODY_HEIGHT, 0.0)
	_expect(field.sample(sample_point) > 0.1, "open blue field reaches unobstructed agent")
	field.shutter_openness = 0.0
	_expect(is_zero_approx(field.sample(sample_point)), "closed shutter field is zero")
	field.shutter_openness = 1.0
	field.obstacle_centers = PackedVector2Array([Vector2(0.0, 1.5)])
	field.obstacle_radii = PackedFloat32Array([0.8])
	_expect(is_zero_approx(field.sample(sample_point)), "broad trunk blocks gameplay field")

func _test_field_aperture_and_range() -> void:
	var field := _forward_field(LightField.Mode.BLUE)
	var outside_cone := Vector3(5.0, FlockSimulation.BODY_HEIGHT, 0.0)
	var beyond_range := field.source_position + field.source_direction * (field.range_m + 1.0)
	_expect(is_zero_approx(field.sample(outside_cone)), "angular mask rejects agent outside lamp aperture")
	_expect(is_zero_approx(field.sample(beyond_range)), "radial mask rejects agent beyond lamp range")

func _test_light_response_signs() -> void:
	var preset := _isolated_preset()
	var blue_sim := _single_agent_sim(preset)
	var blue := _forward_field(LightField.Mode.BLUE)
	blue_sim.step(0.1, blue)
	var blue_target := blue.ground_target(FlockSimulation.BODY_HEIGHT)
	var blue_direction := (blue_target - Vector2.ZERO).normalized()
	_expect(blue_sim.accelerations[0].dot(blue_direction) > 0.01, "blue acceleration points toward footprint")

	var orange_sim := _single_agent_sim(preset)
	var orange := _forward_field(LightField.Mode.ORANGE)
	orange_sim.step(0.1, orange)
	var away := (Vector2.ZERO - Vector2(orange.source_position.x, orange.source_position.z)).normalized()
	_expect(orange_sim.accelerations[0].dot(away) > 0.01, "orange acceleration points away from lamp source")

	blue_sim.step(0.1, orange)
	_expect(blue_sim.exposures[0] <= orange.sample(Vector3(0.0, FlockSimulation.BODY_HEIGHT, 0.0)) + 0.0001, "filter transition does not reinterpret stale exposure")

func _test_blue_settle_and_moving_catchup() -> void:
	var preset := _isolated_preset()
	var sim := _single_agent_sim(preset)
	var field := _forward_field(LightField.Mode.BLUE)
	var initial_target := field.ground_target(FlockSimulation.BODY_HEIGHT)
	sim.positions[0] = initial_target
	sim.previous_positions[0] = initial_target
	sim.velocities[0] = Vector2.ZERO
	for _step: int in 40:
		sim.step(1.0 / 60.0, field)
	_expect(sim.velocities[0].length() < 0.22, "blue arrival settles near stationary footprint")
	field.source_position.x += 1.6
	for _step: int in 45:
		sim.step(1.0 / 60.0, field)
	var toward_moved_target := (field.ground_target(FlockSimulation.BODY_HEIGHT) - sim.positions[0]).normalized()
	_expect(sim.velocities[0].dot(toward_moved_target) > 0.25, "settled agent resumes pursuit when blue footprint moves")

func _test_finite_bounded_all_presets() -> void:
	var obstacles := PackedVector2Array([Vector2(-2.8, -2.2), Vector2(3.0, 2.0), Vector2(1.0, -7.0)])
	var radii := PackedFloat32Array([1.05, 1.2, 0.85])
	for preset: HerdPreset in HerdPreset.builtins():
		var sim := FlockSimulation.new()
		sim.obstacle_centers = obstacles
		sim.obstacle_radii = radii
		sim.reset(24, 40721, preset)
		var field := _forward_field(LightField.Mode.BLUE)
		field.obstacle_centers = obstacles
		field.obstacle_radii = radii
		for tick: int in 600:
			if tick == 200:
				field.mode = LightField.Mode.ORANGE
			elif tick == 400:
				field.shutter_openness = 0.0
			sim.step(1.0 / 60.0, field)
		_expect(sim.is_finite_and_bounded(), "%s stays finite with capped speed/acceleration" % preset.preset_name)

func _test_obstacle_sweep_guard() -> void:
	var sim := FlockSimulation.new()
	sim.obstacle_centers = PackedVector2Array([Vector2.ZERO])
	sim.obstacle_radii = PackedFloat32Array([1.0])
	var constrained := sim._constrain_motion(Vector2(-3.0, 0.0), Vector2(12.0, 0.0), 0.5)
	var position: Vector2 = constrained[0]
	_expect(position.distance_to(Vector2.ZERO) >= 1.0 + FlockSimulation.BODY_RADIUS - 0.001, "high-speed swept motion cannot tunnel through trunk")
	_expect(position.x < 0.0, "sweep stops on entry side of trunk")

func _test_same_step_neighbor_snapshot() -> void:
	var preset := _isolated_preset()
	preset.social_enabled = true
	preset.cohesion_weight = 1.0
	preset.separation_weight = 0.0
	preset.alignment_weight = 0.0
	preset.max_acceleration = 20.0
	var field := _forward_field(LightField.Mode.CLEAR)
	field.shutter_openness = 0.0
	var committing := _two_agent_sim(preset)
	committing.goal_position = Vector2.ZERO
	committing.goal_radius = 0.25
	committing.goal_dwell_seconds = 0.0
	committing.step(1.0 / 60.0, field)
	var comparison := _two_agent_sim(preset)
	comparison.goal_position = Vector2(50.0, 50.0)
	comparison.step(1.0 / 60.0, field)
	_expect(committing.lifecycles[0] == FlockSimulation.Lifecycle.COMMITTED, "fixture commits first agent during step")
	_expect(committing.accelerations[1].is_equal_approx(comparison.accelerations[1]), "later agents use start-of-step lifecycle snapshot")

func _test_goal_resistance_is_local_and_repellent() -> void:
	var sim := FlockSimulation.new()
	sim.reset(3, 40721, HerdPreset.builtins()[0])
	var near_rim := Vector2(sim.goal_radius + 0.5, 0.0)
	var force := sim._goal_resistance(near_rim)
	_expect(force.dot(near_rim.normalized()) > 0.0, "goal resistance points outward at return rim")
	_expect(sim._goal_resistance(Vector2(sim.goal_radius + 2.0, 0.0)).is_zero_approx(), "goal resistance is local and has no long-range force")
	_expect(sim._goal_resistance(Vector2.ZERO).is_zero_approx(), "goal resistance fades after deliberate crossing")
	sim.preset.goal_repulsion_strength = 0.0
	_expect(sim._goal_resistance(near_rim).is_zero_approx(), "zero goal resistance preserves original control")

func _test_lifecycle_accounting_and_neighbor_exclusion() -> void:
	var preset := _isolated_preset()
	preset.social_enabled = true
	preset.cohesion_weight = 1.0
	var sim := _single_agent_sim(preset)
	sim.goal_position = Vector2.ZERO
	sim.goal_radius = 1.0
	sim.goal_dwell_seconds = 0.03
	var field := _forward_field(LightField.Mode.CLEAR)
	field.shutter_openness = 0.0
	for _step: int in 240:
		sim.step(1.0 / 60.0, field)
	_expect(sim.score == 1, "goal increments score exactly once")
	_expect(sim.lifecycles[0] == FlockSimulation.Lifecycle.RELEASED, "committed agent completes finite ascent lifecycle")
	_expect(sim.active_count() == 0, "committed/ascending agent leaves active flock")

	var positions := PackedVector2Array([Vector2.ZERO, Vector2(1.0, 0.0)])
	var velocities := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	var states := PackedInt32Array([FlockSimulation.Lifecycle.ACTIVE, FlockSimulation.Lifecycle.ASCENDING])
	var neighbor_force := sim._social_force(0, positions, velocities, states)
	_expect(neighbor_force.is_zero_approx(), "ascending agent no longer contributes neighbor force")

func _test_short_unattended_control() -> void:
	var field := _forward_field(LightField.Mode.CLEAR)
	field.shutter_openness = 0.0
	for preset: HerdPreset in HerdPreset.builtins():
		var sim := FlockSimulation.new()
		sim.obstacle_centers = PackedVector2Array([Vector2(-2.8, -2.2), Vector2(3.0, 2.0), Vector2(1.0, -7.0)])
		sim.obstacle_radii = PackedFloat32Array([1.05, 1.2, 0.85])
		sim.reset(24, 40721, preset)
		for _step: int in 720:
			sim.step(1.0 / 60.0, field)
		_expect(sim.score == 0, "%s has no automatic returns in 12-second unattended control" % preset.preset_name)

func _forward_field(mode: LightField.Mode) -> LightField:
	var field := LightField.new()
	field.mode = mode
	field.shutter_openness = 1.0
	field.range_m = 10.5
	field.half_angle_degrees = 38.0
	field.source_position = Vector3(0.0, 1.1, 3.0)
	field.source_direction = Vector3(0.0, -0.4, -1.0).normalized()
	return field

func _isolated_preset() -> HerdPreset:
	var preset := HerdPreset.builtins()[2].copy_preset()
	preset.wander_weight = 0.0
	preset.max_acceleration = 8.0
	preset.max_speed = 3.0
	preset.goal_repulsion_strength = 0.0
	return preset

func _single_agent_sim(preset: HerdPreset) -> FlockSimulation:
	var sim := FlockSimulation.new()
	sim.reset(1, 101, preset)
	sim.positions[0] = Vector2.ZERO
	sim.previous_positions[0] = Vector2.ZERO
	sim.velocities[0] = Vector2.ZERO
	sim.goal_position = Vector2(100.0, 100.0)
	return sim

func _two_agent_sim(preset: HerdPreset) -> FlockSimulation:
	var sim := FlockSimulation.new()
	sim.reset(2, 202, preset)
	sim.positions = PackedVector2Array([Vector2.ZERO, Vector2(2.0, 0.0)])
	sim.previous_positions = sim.positions.duplicate()
	sim.velocities = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	sim.accelerations = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	sim.lifecycles = PackedInt32Array([FlockSimulation.Lifecycle.ACTIVE, FlockSimulation.Lifecycle.ACTIVE])
	sim.lifecycle_times = PackedFloat32Array([0.0, 0.0])
	sim.exposures = PackedFloat32Array([0.0, 0.0])
	sim.arousals = PackedFloat32Array([preset.baseline_arousal, preset.baseline_arousal])
	sim.wander_phases = PackedFloat32Array([0.0, 0.0])
	sim.group_ids = PackedInt32Array([0, 0])
	# reset initialized the private goal dwell array to the correct size.
	return sim

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % message)
	else:
		failures += 1
		printerr("  FAIL  %s" % message)
