extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig: Variant = load("res://scenes/xr_player.tscn").instantiate()
	get_root().add_child(rig)
	# In ordinary two-hand play the turn stick's upper direction is free.
	assert(rig._jump_input_pressed(true, true, 0.79, false, false) == false)
	assert(rig._jump_input_pressed(true, true, 0.81, false, false) == true)
	assert(rig._jump_input_pressed(true, true, -1.0, false, false) == false)
	# In one-hand play, that same vertical axis must remain walking input.
	assert(rig._jump_input_pressed(false, true, 1.0, false, false) == false)
	assert(rig._jump_input_pressed(false, true, 1.0, false, true) == true)
	assert(rig._jump_input_pressed(true, false, 1.0, true, false) == true)
	assert(rig._jump_input_pressed(false, false, 1.0, true, true) == false)
	print("XR_JUMP_MAPPING_PASS")
	quit()
