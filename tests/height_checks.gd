extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	print("HEIGHT_CHECKS Godot=%s" % Engine.get_version_info().string)
	_test_ceiling_sync_and_energy_excursion()
	_test_energy_opens_higher_trajectory()
	_test_live_lowered_ceiling_constrains_motion()
	if failures == 0:
		print("HEIGHT_CHECKS PASS checks=%d failures=0" % checks)
		quit(0)
	else:
		push_error("HEIGHT_CHECKS FAIL checks=%d failures=%d" % [checks, failures])
		quit(1)


func _test_ceiling_sync_and_energy_excursion() -> void:
	var preset := HerdPreset.builtins()[5]
	preset.flight_max_height = 6.0
	var sim := FlightSimulation.new()
	sim.reset(1, 40721, preset)
	_expect(is_equal_approx(sim.max_height, 6.0), "reset adopts the preset flight ceiling")
	sim._energy_time = 0.0
	sim._vertical_phases[0] = PI * 0.5
	var sample_position := Vector3(0.0, 2.5, 0.0)
	sim.arousals[0] = preset.energy_neutral_target
	var neutral_force := sim._flight_band_force(0, sample_position).y
	sim.arousals[0] = 1.0
	var energized_force := sim._flight_band_force(0, sample_position).y
	_expect(neutral_force < 0.0, "neutral flyer above player height is gently pulled down")
	_expect(energized_force > 0.0, "energized flyer can orbit upward into raised headroom")


func _test_live_lowered_ceiling_constrains_motion() -> void:
	var preset := HerdPreset.builtins()[5]
	preset.flight_max_height = 6.0
	var sim := FlightSimulation.new()
	sim.reset(1, 40721, preset)
	sim.positions[0] = Vector3(8.0, 4.0, 8.0)
	sim.previous_positions[0] = sim.positions[0]
	sim.velocities[0] = Vector3.UP
	sim.preset.flight_max_height = 2.2
	var field := LightField.new()
	field.mode = LightField.Mode.CLEAR
	sim.step(1.0 / 30.0, field)
	_expect(is_equal_approx(sim.max_height, 2.2), "live preset change updates the simulation ceiling")
	_expect(sim.positions[0].y <= 2.2001, "lowered ceiling constrains an already-high flyer on the next step")
	_expect(sim.is_finite_and_bounded(), "height adjustment remains finite and bounded")


func _test_energy_opens_higher_trajectory() -> void:
	var neutral_preset := HerdPreset.builtins()[5]
	neutral_preset.flight_max_height = 6.0
	neutral_preset.energy_dynamics = false
	neutral_preset.arousal_memory = false
	neutral_preset.social_enabled = false
	neutral_preset.baseline_arousal = neutral_preset.energy_neutral_target
	var energized_preset := neutral_preset.copy_preset()
	energized_preset.baseline_arousal = 1.0
	var neutral := FlightSimulation.new()
	var energized := FlightSimulation.new()
	neutral.reset(1, 81173, neutral_preset)
	energized.reset(1, 81173, energized_preset)
	for sim: FlightSimulation in [neutral, energized]:
		sim.positions[0] = Vector3(8.0, 1.5, 8.0)
		sim.previous_positions[0] = sim.positions[0]
		sim.velocities[0] = Vector3.ZERO
	var field := LightField.new()
	field.mode = LightField.Mode.CLEAR
	var neutral_peak := neutral.positions[0].y
	var energized_peak := energized.positions[0].y
	for _tick: int in 600:
		neutral.step(1.0 / 30.0, field)
		energized.step(1.0 / 30.0, field)
		neutral_peak = maxf(neutral_peak, neutral.positions[0].y)
		energized_peak = maxf(energized_peak, energized.positions[0].y)
	print("  OBSERVE height neutral_peak=%.3f energized_peak=%.3f ceiling=%.1f" % [neutral_peak, energized_peak, energized.max_height])
	_expect(energized_peak > neutral_peak + 0.7, "energized trajectory uses materially more raised headroom")
	_expect(energized_peak <= energized.max_height and neutral.is_finite_and_bounded() and energized.is_finite_and_bounded(), "raised trajectories remain inside the authored ceiling")


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		failures += 1
		push_error("  FAIL  %s" % label)
