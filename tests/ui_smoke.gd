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
	print("PASS UI: CLI preset, live tuning, config history, named save/load with seed/fixture, camera reset, run record serialization")
	quit()
