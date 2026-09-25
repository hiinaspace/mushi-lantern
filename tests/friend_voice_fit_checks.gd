extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var menu := FriendMenu.new()
	root.add_child(menu)
	await process_frame
	var fit_changes := [0]
	menu.avatar_fit_changed.connect(func(_height: float, _reach: float) -> void:
		fit_changes[0] += 1)
	menu.set_open(true)
	var sliders := menu.find_children("*", "HSlider", true, false)
	if sliders.size() < 3:
		_fail("Avatar fit and microphone gain sliders were not built")
		return
	(sliders[0] as HSlider).value = 1.72
	(sliders[1] as HSlider).value = 1.38
	if fit_changes[0] != 0:
		_fail("Avatar fit applied while the menu was open")
		return
	menu.set_open(false)
	if fit_changes[0] != 1:
		_fail("Avatar fit did not apply once on menu close")
		return
	var mute_changes: Array[bool] = []
	menu.voice_mute_changed.connect(func(muted: bool) -> void:
		mute_changes.append(muted))
	menu.set_voice_controls(true, "Default", PackedStringArray(["Default", "Test mic"]),
		3.0, -42.0, -6.0)
	menu.set_voice_meter(-34.0)
	assert(menu._voice_gate_sliders[0].value == -42.0)
	assert(menu._voice_receive_sliders[0].value == -6.0)
	assert(menu._voice_meter_bars[0].value == -34.0)
	var mute_button: Button
	for button: Node in menu.find_children("*", "Button", true, false):
		if (button as Button).text == "Unmute mic":
			mute_button = button as Button
			break
	if mute_button == null:
		_fail("Mute button missing")
		return
	mute_button.emit_signal("pressed")
	if mute_changes != [false]:
		_fail("Mute button did not unmute")
		return
	print("FRIEND_VOICE_FIT_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
