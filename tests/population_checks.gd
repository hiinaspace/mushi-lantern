extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	print("POPULATION_CHECKS Godot=%s" % Engine.get_version_info().string)
	_test_preset_contract()
	_test_seeded_traits()
	_test_small_neighbor_equivalence()
	_test_snapshot_contagion()
	_test_staggered_waking()
	_test_large_population_bounds_and_cost()
	if failures == 0:
		print("POPULATION_CHECKS PASS checks=%d failures=0" % checks)
	else:
		printerr("POPULATION_CHECKS FAIL checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_preset_contract() -> void:
	var presets := HerdPreset.builtins()
	_expect(presets.size() == 10 and presets[5].preset_name == "Living shoals" and presets[6].preset_name == "Longer drift" and presets[7].preset_name == "Drifting trains" and presets[8].preset_name == "Loose trains" and presets[9].preset_name == "Gentle herding", "friend preset follows the accepted historical presets")
	_expect(presets[9].goal_repulsion_strength < 0.0 and presets[9].blue_energy_response < presets[8].blue_energy_response and presets[9].energy_recovery_rate < presets[8].energy_recovery_rate, "friend preset adds goal attraction and eases blue slowdown while keeping recovery slower")
	var friend_sim := FlightSimulation.new()
	friend_sim.reset(3, 40721, presets[9])
	var approach := Vector3(friend_sim.goal_radius + 1.5, 0.0, 0.0)
	_expect(friend_sim._goal_resistance(approach).dot(approach) < 0.0, "friend goal field pulls approaching mushi inward")
	for index: int in 5:
		_expect(presets[index].population_variation == 0.0 and presets[index].arousal_contagion_strength == 0.0 and not presets[index].spontaneous_waking_enabled, "preset %d retains disabled ecology defaults" % index)
	var restored := HerdPreset.from_dict({"preset_name": "old", "max_speed": 1.7})
	_expect(restored.population_variation == 0.0 and not restored.spontaneous_waking_enabled, "old dictionaries retain compatible ecology defaults")
	var round_trip := HerdPreset.from_dict(presets[5].to_dict())
	_expect(round_trip.population_variation == presets[5].population_variation and round_trip.spontaneous_waking_enabled, "ecology controls survive serialization")
	var longer := presets[6]
	_expect(is_equal_approx(longer.glyph_render_scale, 0.4) and is_equal_approx(longer.blue_energy_response, 0.365489697300642) and is_equal_approx(longer.orange_energy_response, 1.457332337338), "Longer drift imports the saved response and visual tuning")
	_expect(is_equal_approx(longer.goal_repulsion_strength, 0.48) and is_equal_approx(longer.goal_repulsion_outer_width, 4.2) and is_equal_approx(longer.arousal_contagion_strength, 0.5), "Longer drift imports the saved movement and social tuning")
	var longer_round_trip := HerdPreset.from_dict(longer.to_dict())
	_expect(is_equal_approx(longer_round_trip.glyph_render_scale, longer.glyph_render_scale) and is_equal_approx(longer_round_trip.blue_energy_response, longer.blue_energy_response), "Longer drift snapshot values survive serialization")
	var trains := presets[7]
	var trains_round_trip := HerdPreset.from_dict(trains.to_dict())
	_expect(is_equal_approx(trains.formation_follow_weight, 1.35) and is_equal_approx(trains.cluster_pressure_weight, 1.0) and trains.cluster_target_neighbors == 2, "Drifting trains exposes a separate small-formation experiment")
	_expect(is_equal_approx(trains_round_trip.formation_follow_weight, trains.formation_follow_weight) and trains_round_trip.cluster_target_neighbors == trains.cluster_target_neighbors, "formation parameters survive preset serialization")


func _test_seeded_traits() -> void:
	var sim := FlightSimulation.new()
	var preset := HerdPreset.builtins()[5]
	sim.reset(256, 40721, preset)
	var types := sim.trait_types.duplicate()
	var sizes := sim.trait_sizes.duplicate()
	var tints := sim.trait_tints.duplicate()
	var waits := sim._wake_waits.duplicate()
	sim.reset(256, 40721, preset)
	_expect(sim.trait_types == types and sim.trait_sizes == sizes and sim.trait_tints == tints and sim._wake_waits == waits, "seed reproduces traits and wake schedule")
	var type_mask := 0
	var min_size := INF
	var max_size := -INF
	for index: int in sim.trait_types.size():
		type_mask |= 1 << sim.trait_types[index]
		min_size = minf(min_size, sim.trait_sizes[index])
		max_size = maxf(max_size, sim.trait_sizes[index])
	_expect(type_mask == 7 and min_size < 0.95 and max_size > 1.05, "seeded population spans subtype and size traits")


func _test_small_neighbor_equivalence() -> void:
	var preset := HerdPreset.builtins()[5].copy_preset()
	preset.arousal_contagion_strength = 0.0
	var sim := FlightSimulation.new()
	sim.reset(32, 88, preset)
	var states := sim.lifecycles.duplicate()
	sim._build_neighbor_lists(sim.positions, states)
	var grid_force := sim._social_force(7, sim.positions, sim.velocities, states)
	var saved := sim._neighbor_lists
	sim._neighbor_lists = []
	var brute_force := sim._social_force(7, sim.positions, sim.velocities, states)
	sim._neighbor_lists = saved
	_expect(grid_force.is_equal_approx(brute_force), "small-population neighbor path matches brute-force social force")
	var translated := sim.positions.duplicate()
	for index: int in translated.size():
		translated[index] += Vector3(13.0, 4.0, -9.0)
	sim._neighbor_lists = []
	var translated_force := sim._social_force(7, translated, sim.velocities, states)
	_expect(brute_force.is_equal_approx(translated_force), "heterogeneous social force is translation invariant")


func _test_snapshot_contagion() -> void:
	var preset := HerdPreset.builtins()[5].copy_preset()
	preset.population_variation = 0.0
	preset.spontaneous_waking_enabled = false
	preset.arousal_contagion_strength = 0.35
	preset.social_enabled = false
	preset.wander_weight = 0.0
	preset.goal_repulsion_strength = 0.0
	var sim := FlightSimulation.new()
	sim.spawn_centers = PackedVector2Array([Vector2.ZERO])
	sim.mushroom_centers = PackedVector2Array([Vector2.ZERO])
	sim.goal_position = Vector2(100.0, 100.0)
	sim.reset(3, 19, preset)
	sim.positions = PackedVector3Array([Vector3(0.0, 0.45, 0.0), Vector3(0.5, 0.45, 0.0), Vector3(-0.5, 0.45, 0.0)])
	sim.arousals = PackedFloat32Array([0.95, 0.04, 0.04])
	var control := FlightSimulation.new()
	control.spawn_centers = sim.spawn_centers
	control.mushroom_centers = sim.mushroom_centers
	control.goal_position = sim.goal_position
	var control_preset := preset.copy_preset()
	control_preset.arousal_contagion_strength = 0.0
	control.reset(3, 19, control_preset)
	control.positions = sim.positions.duplicate()
	control.arousals = sim.arousals.duplicate()
	var peak_delta := 0.0
	for _tick: int in 180:
		sim.step(1.0 / 60.0, _clear_field())
		control.step(1.0 / 60.0, _clear_field())
		peak_delta = maxf(peak_delta, (sim.arousals[1] + sim.arousals[2] - control.arousals[1] - control.arousals[2]) * 0.5)
	_expect(peak_delta > 0.025, "one aroused intruder produces a measurable local wake transient")
	_expect(absf(sim.arousals[1] - sim.arousals[2]) < 0.01, "contagion reads a same-step energy snapshot")
	for _tick: int in 1800:
		sim.step(1.0 / 60.0, _clear_field())
	var max_energy := 0.0
	for energy: float in sim.arousals:
		max_energy = maxf(max_energy, energy)
	_expect(max_energy < preset.sleep_threshold + 0.06, "mushroom suppression settles the local wake transient")


func _test_staggered_waking() -> void:
	var preset := HerdPreset.builtins()[5].copy_preset()
	preset.spontaneous_wake_min_seconds = 1.0
	preset.spontaneous_wake_max_seconds = 5.0
	preset.spontaneous_wake_duration = 3.5
	var sim := FlightSimulation.new()
	sim.spawn_centers = PackedVector2Array([Vector2.ZERO])
	sim.mushroom_centers = PackedVector2Array([Vector2.ZERO])
	sim.goal_position = Vector2(100.0, 100.0)
	sim.reset(64, 2201, preset)
	for _tick: int in 180:
		sim.step(1.0 / 60.0, _clear_field())
	var awake := 0
	for remaining: float in sim._wake_remaining:
		awake += 1 if remaining > 0.0 else 0
	_expect(awake > 0 and awake < 64, "seeded sleep timers wake a minority rather than the whole patch")
	var moved_out := 0
	for _tick: int in 240:
		sim.step(1.0 / 60.0, _clear_field())
	for position: Vector3 in sim.positions:
		moved_out += 1 if Vector2(position.x, position.z).length() > preset.mushroom_radius else 0
	_expect(moved_out > 0, "wake pulse lets some sleepers wander away from a mushroom center")

	# Turning the live control off must not freeze an in-progress pulse forever.
	sim._wake_remaining[0] = 2.0
	sim.preset.spontaneous_waking_enabled = false
	sim.step(1.0 / 30.0, _clear_field())
	_expect(sim._wake_remaining[0] == 0.0, "disabling spontaneous waking cancels an active pulse")


func _test_large_population_bounds_and_cost() -> void:
	for count: int in [256, 1024]:
		var sim := FlightSimulation.new()
		var preset := HerdPreset.builtins()[5]
		sim.reset(count, 40721, preset)
		var started := Time.get_ticks_usec()
		for _tick: int in 12:
			sim.step(1.0 / 30.0, _clear_field())
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var max_neighbors := 0
		for neighbors: PackedInt32Array in sim._neighbor_lists:
			max_neighbors = maxi(max_neighbors, neighbors.size())
		print("  BENCH population agents=%d ticks=12 total_ms=%.2f per_step_ms=%.2f neighbor_visits=%d" % [count, elapsed_ms, elapsed_ms / 12.0, sim.neighbor_visits])
		_expect(max_neighbors <= preset.max_social_neighbors, "%d-agent sampled neighbor list respects cap" % count)
		_expect(sim.neighbor_visits <= count * preset.max_social_neighbors, "%d-agent contagion visits remain linearly bounded" % count)
		_expect(sim.is_finite_and_bounded(), "%d-agent ecology run stays finite and bounded" % count)


func _clear_field() -> LightField:
	var field := LightField.new()
	field.mode = LightField.Mode.CLEAR
	field.shutter_openness = 0.0
	return field


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % message)
	else:
		failures += 1
		printerr("  FAIL  %s" % message)
