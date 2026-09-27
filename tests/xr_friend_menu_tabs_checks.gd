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
	assert(tabs != null and tabs.get_tab_count() == 8)
	assert(tabs.get_tab_title(0) == "Play")
	assert(tabs.get_tab_title(1) == "Session")
	assert(tabs.get_tab_title(2) == "Guide")
	assert(tabs.get_tab_title(3) == "Comfort")
	assert(tabs.get_tab_title(4) == "Settings")
	assert(tabs.get_tab_title(5) == "Voice")
	assert(tabs.get_tab_title(6) == "Mix")
	assert(tabs.get_tab_title(7) == "Mushi")
	var scroll := surface.find_child("AudioScroll", true, false) as ScrollContainer
	assert(scroll != null and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	var panel := surface.get_node("Panel") as PanelContainer
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert(style != null and style.bg_color.a >= 0.95)
	assert((tabs.get_child(3) as VBoxContainer).get_child_count() >= 4)
	assert((tabs.get_child(6) as VBoxContainer).get_child_count() >= 7)
	assert((tabs.get_child(7) as VBoxContainer).get_child_count() >= 4)
	print("XR_FRIEND_MENU_TABS_OK")
	quit(0)
