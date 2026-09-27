extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var surface := load("res://scenes/xr_menu_content.tscn").instantiate() as Control
	root.add_child(surface)
	var mix := AudioMixPanel.new()
	root.add_child(mix)
	await process_frame
	mix.attach_xr_menu(surface)
	var friend := FriendMenu.new()
	root.add_child(friend)
	await process_frame
	friend.attach_xr_menu(surface)
	var tabs := surface.find_child("FriendTabs", true, false) as TabContainer
	assert(tabs != null and tabs.get_tab_count() == 4)
	assert(tabs.get_tab_title(0) == "Play")
	assert(tabs.get_tab_title(1) == "Multiplayer")
	var room := tabs.get_node("Multiplayer") as ScrollContainer
	var room_page := room.get_node("Multiplayer") as VBoxContainer
	assert((room_page.get_child(0) as Label).text.contains("EXPERIMENTAL"))
	assert((room_page.get_child(1) as Label).text.contains("up to 8 players"))
	assert(friend._xr_mode_buttons.size() == 2 and friend._xr_mode_buttons[0].button_pressed)
	assert(friend._xr_mode_buttons[0].get_parent() == friend._xr_mode_buttons[1].get_parent())
	friend._xr_mode_buttons[1].pressed.emit()
	assert(friend._selected_mode == "two_shrines" and friend._xr_mode_buttons[1].button_pressed
		and friend._mode_selectors[0].selected == 1, "XR mode buttons select and sync the hosting mode")
	friend._mode_selectors[0].item_selected.emit(0)
	assert(friend._selected_mode == "classic" and friend._xr_mode_buttons[0].button_pressed,
		"desktop mode selection updates the XR buttons")
	assert(tabs.get_tab_title(2) == "Settings")
	assert(tabs.get_tab_title(3) == "Controls")
	var settings := tabs.find_child("SettingsTabs", true, false) as TabContainer
	assert(settings != null and settings.get_tab_count() == 4)
	assert(settings.get_tab_title(0) == "Comfort")
	assert(settings.get_tab_title(1) == "Graphics")
	assert(settings.get_tab_title(2) == "Audio")
	assert(settings.get_tab_title(3) == "Voice")
	var scroll := surface.find_child("AudioScroll", true, false) as ScrollContainer
	assert(scroll != null and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	var panel := surface.get_node("Panel") as PanelContainer
	assert(panel.size == Vector2(900, 550) and panel.scale == Vector2(2, 2),
		"XR menu keeps its logical layout at double raster resolution")
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert(style != null and style.bg_color.a >= 0.95)
	friend.update_session("test", true, false)
	assert(friend._xr_skip != null and friend._xr_skip.visible)
	assert(friend._xr_skip.get_index() < friend._xr_start.get_index())
	for button in [friend._xr_skip, friend._xr_start, friend._room_host_buttons[0]]:
		var button_style := button.get_theme_stylebox("normal") as StyleBoxFlat
		assert(button_style != null and button_style.bg_color.a > 0.9
			and button_style.border_width_left >= 2 and button_style.border_color != style.border_color,
			"XR actions have a distinct filled button surface and border")
	friend._comfort_turns[-1].pressed.emit()
	assert(friend._comfort.snap_turn)
	friend._comfort_hands[-1].pressed.emit()
	assert(friend._comfort.move_hand == "right")
	assert((surface.theme.default_font as FontFile).oversampling >= 2.0)
	print("XR_FRIEND_MENU_TABS_OK")
	quit(0)
