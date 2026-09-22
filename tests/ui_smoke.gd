extends SceneTree
func _initialize() -> void:
	if OS.get_environment("MUSHI_TEST_DATA_ROOT").is_empty():
		push_error("Run this isolated UI test through check.sh")
		quit(1)
		return
	call_deferred("run_checks")
func run_checks() -> void:
	var lab = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	assert(lab.current_preset.preset_name == "Arousal memory")
	assert(lab.simulation.world_limit == 27.0)
	assert(lab.simulation.spawn_centers[0] == Vector2(-14.4, -13.2))
	assert(lab.get_node("Ground").get_child(0).mesh.size.x == 60.0)
	lab.seed_box.value = 12345
	lab._set_fixture(3)
	lab.goal_slider.value = 1.5
	assert(lab.current_preset.goal_repulsion_strength == 1.5)
	assert(lab.simulation.preset.goal_repulsion_strength == 1.5)
	assert(lab.settings_history.size() == 2)
	lab.save_name.text = "smoke-saved"
	lab._save_named_preset()
	lab.seed_box.value = 1
	lab._set_fixture(24)
	lab.goal_slider.value = 0.0
	lab._load_named_preset(1)
	assert(lab.current_seed == 12345)
	assert(lab.fixture_count == 3)
	assert(lab.goal_slider.value == 1.5)
	assert(lab.current_preset.arousal_memory)
	lab.player.camera.rotation.x = 1.0
	lab._reset_run(false)
	assert(is_equal_approx(lab.player.camera.rotation.x, -0.12))
	lab._apply_preset(3, true)
	assert(lab.current_preset.energy_dynamics)
	assert(lab.simulation.mushroom_centers.size() == 1)
	assert(lab.mushroom_nodes[0].visible and not lab.mushroom_nodes[1].visible)
	var unchanged_rate: float = lab.current_preset.energy_recovery_rate
	lab.social_slider.value = 0.65
	assert(lab.current_preset.energy_recovery_rate == unchanged_rate)
	lab.recovery_slider.value = 30.0
	assert(is_equal_approx(lab.current_preset.energy_recovery_rate, log(10.0) / 30.0))
	assert(is_equal_approx(lab.simulation.preset.energy_recovery_rate, log(10.0) / 30.0))
	lab.scatter_slider.value = 0.35
	assert(is_equal_approx(lab.simulation.preset.arousal_scatter_strength, 0.35))
	lab.save_name.text = "smoke-saved"
	lab._save_named_preset()
	lab._apply_preset(0, true)
	assert(lab.simulation.mushroom_centers.is_empty() and not lab.mushroom_nodes[0].visible)
	lab._load_named_preset(1)
	assert(lab.current_preset.energy_dynamics and lab.simulation.mushroom_centers.size() == 1)
	assert(is_equal_approx(lab.recovery_slider.value, 30.0))
	assert(is_equal_approx(lab.scatter_slider.value, 0.35))
	var blue := EnergyVisual.color_for(0.0)
	var green := EnergyVisual.color_for(0.45)
	var yellow := EnergyVisual.color_for(0.75)
	var orange := EnergyVisual.color_for(1.0)
	assert(blue.b > blue.g and blue.b > blue.r)
	assert(green.g > green.r and green.g > green.b)
	assert(yellow.r > 0.8 and yellow.g > 0.7 and yellow.b < 0.3)
	assert(orange.r > 0.8 and orange.g < 0.5 and orange.b < 0.3)
	lab.flight_toggle.button_pressed = true
	lab._set_fixture(64)
	assert(lab.simulation is FlightSimulation and lab.simulation.positions.size() == 64)
	lab.save_name.text = "smoke-flight"
	lab._save_named_preset()
	lab.flight_toggle.button_pressed = false
	assert(lab.simulation is FlockSimulation)
	lab._load_named_preset(1) # Alphabetically smoke-flight before smoke-saved.
	assert(lab.flight_enabled and lab.flight_toggle.button_pressed)
	assert(lab.fixture_count == 64 and lab.simulation is FlightSimulation)
	lab._update_agent_visuals(1.0)
	assert(lab.agent_nodes.is_empty())
	assert(lab.glyph_swarm != null)
	assert(lab.glyph_swarm.instance_count == 64)
	lab._apply_preset(5, true)
	lab._set_fixture(1024)
	assert(lab.simulation.positions.size() == 1024)
	assert(is_equal_approx(lab.active_step, 1.0 / 30.0))
	assert(lab.agent_nodes.is_empty() and lab.glyph_swarm != null)
	lab.variation_slider.value = 0.4
	lab.contagion_slider.value = 0.2
	lab.waking_toggle.button_pressed = false
	lab.save_name.text = "smoke-flight"
	lab._save_named_preset()
	lab._apply_preset(3, true)
	lab._set_fixture(24)
	lab._load_named_preset(1)
	assert(lab.fixture_count == 1024 and lab.flight_enabled)
	assert(is_equal_approx(lab.current_preset.population_variation, 0.4))
	assert(is_equal_approx(lab.simulation.preset.arousal_contagion_strength, 0.2))
	assert(not lab.current_preset.spontaneous_waking_enabled)
	assert(lab.simulation.trait_sizes.size() == 1024)
	lab.run_notes.text = "UI persistence check"
	lab.elapsed = 1.0
	lab._write_run_record("ui_smoke")
	var f := FileAccess.open("user://m0_run_records.jsonl", FileAccess.READ)
	assert(f != null)
	var last_record := ""
	while not f.eof_reached():
		var line := f.get_line()
		if not line.is_empty():
			last_record = line
	var record: Dictionary = JSON.parse_string(last_record)
	assert(record.has("settings_history") and record.has("run_id"))
	assert(record.get("notes") == "UI persistence check")
	assert(record.get("arena_layout") == "wide-60m-v1")
	assert(record.get("flight_enabled") == true and record.get("fixture_count") == 1024)
	print("PASS UI: CLI preset, live tuning, config history, named save/load with seed/fixture, camera reset, run record serialization; energy presets, mushroom visibility, independent tuning, energy save/load and color anchors")
	quit()
