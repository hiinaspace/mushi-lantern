extends SceneTree

var started := 0
var profiles: Array[String] = []


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var menu := FriendMenu.new()
	root.add_child(menu)
	await process_frame
	var surface := Control.new()
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.name = "Margin"
	var scroll := ScrollContainer.new()
	scroll.name = "AudioScroll"
	var contents := VBoxContainer.new()
	contents.name = "Contents"
	root.add_child(surface)
	surface.add_child(panel)
	panel.add_child(margin)
	margin.add_child(scroll)
	scroll.add_child(contents)
	var old_title := Label.new()
	old_title.name = "Title"
	old_title.text = "Old debug menu"
	contents.add_child(old_title)
	var old_description := Label.new()
	old_description.name = "Description"
	old_description.text = "Old debug controls"
	contents.add_child(old_description)
	var intro := Label.new()
	intro.text = "Introduction"
	contents.add_child(intro)
	var skip := Button.new()
	skip.text = "Skip introduction"
	contents.add_child(skip)
	var tuning := Button.new()
	tuning.text = "Open tuning sandbox"
	contents.add_child(tuning)
	var close_tuning := Button.new()
	close_tuning.text = "Close tuning sandbox"
	contents.add_child(close_tuning)
	var audio_divider := HSeparator.new()
	contents.add_child(audio_divider)
	var audio_title := Label.new()
	audio_title.text = "Audio mix · point and drag"
	contents.add_child(audio_title)
	var audio_control := HSlider.new()
	audio_control.name = "LiveAudioSlider"
	contents.add_child(audio_control)

	menu.new_game_requested.connect(_on_started)
	menu.quality_profile_requested.connect(_on_profile)
	menu.attach_xr_menu(surface)
	assert(menu._xr_contents == contents, "FriendMenu finds Contents nested below AudioScroll")
	assert(contents.find_child("Title", false, false) == null, "legacy debug title is removed")
	assert(contents.find_child("Description", true, false) == old_description, "controller reference remains available")
	assert(contents.find_child("XRStartButton", true, false) is Button, "XR exposes restart")
	assert(contents.find_child("XRQuitButton", true, false) is Button, "XR exposes quit")
	assert(skip.get_parent().name == "Controls", "skip remains in Controls")
	assert(tuning.get_parent().name == "Advanced", "tuning lives under Settings / Advanced")
	assert(audio_control.get_parent().name == "Audio", "live mix controls stay attached under Settings / Audio")
	var performance := _find_button_text(menu._xr_settings, "Quality: Performance")
	performance.pressed.emit()
	assert(profiles == ["performance"], "quality profiles retain their signal")
	var start_button := contents.find_child("XRStartButton", true, false) as Button
	start_button.pressed.emit()
	assert(started == 1, "Start / restart routes to game signal")
	menu.update_session("Tutorial: close the shutter", true, true)
	assert(menu._xr_status.text == "Paused · Tutorial: close the shutter", "XR pause menu shows current session status")
	menu.free()
	surface.free()
	print("PASS XR friend menu: nested surface, session actions, audio and quality access")
	quit()


func _find_button_text(parent: Node, wanted_text: String) -> Button:
	for child in parent.get_children():
		if child is Button and (child as Button).text == wanted_text:
			return child as Button
		var nested := _find_button_text(child, wanted_text)
		if nested != null:
			return nested
	return null


func _on_started() -> void:
	started += 1


func _on_profile(profile: String) -> void:
	profiles.append(profile)
