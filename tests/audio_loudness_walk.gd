extends SceneTree

## Rendered 40 second desktop walk for the local LUFS capture harness.
## Run through tools/measure-audio-loudness.sh; it isolates user data and audio output.

const WALK_SECONDS := 40.0
var _main: Node
var _selected_total := 0.0
var _selected_samples := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_main.set_process_unhandled_input(false)
	if _main.player != null:
		_main.player.set_process_unhandled_input(false)
		_main.player.look_enabled = false

	# Do not spend the recorded walk waiting for first-time GPU initialization.
	var gpu_wait_frames := 0
	while not _main.simulation.gpu_ready and gpu_wait_frames < 600:
		await process_frame
		gpu_wait_frames += 1
	if not _main.simulation.gpu_ready:
		push_error("Audio loudness walk requires the rendered GPU simulation to become ready")
		quit(2)
		return
	print("AUDIO_WALK_START population=%d renderer=%s" % [_main.fixture_count, RenderingServer.get_current_rendering_method()])

	var start_ms := Time.get_ticks_msec()
	var previous_action := ""
	while true:
		var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
		if elapsed >= WALK_SECONDS:
			break
		var wanted_action := ""
		if elapsed >= 10.0 and elapsed < 20.0:
			wanted_action = "move_forward"
		elif elapsed >= 30.0 and elapsed < 38.0:
			wanted_action = "move_back"
		if wanted_action != previous_action:
			if not previous_action.is_empty():
				Input.action_release(previous_action)
			if not wanted_action.is_empty():
				Input.action_press(wanted_action)
			previous_action = wanted_action
		_sample_selected_mushi()
		await process_frame
	if not previous_action.is_empty():
		Input.action_release(previous_action)
	print("AUDIO_SCENE_MEAN_SELECTED_MUSHI=%.2f samples=%d" % [
		_selected_total / maxf(float(_selected_samples), 1.0), _selected_samples
	])
	print("AUDIO_WALK_COMPLETE seconds=40 still=0-10,20-30 forward=10-20 back=30-38")
	quit(0)


func _sample_selected_mushi() -> void:
	if _main.grove_audio == null or not is_instance_valid(_main.grove_audio):
		return
	var selected := 0
	for slot: Dictionary in _main.grove_audio._mushi:
		if int(slot.get("id", -1)) >= 0:
			selected += 1
	_selected_total += float(selected)
	_selected_samples += 1
