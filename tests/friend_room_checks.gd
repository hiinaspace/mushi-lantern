extends SceneTree


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var menu := FriendMenu.new()
	root.add_child(menu)
	var surface := load("res://scenes/xr_menu_content.tscn").instantiate() as Control
	root.add_child(surface)
	menu.attach_xr_menu(surface)
	var tabs := surface.find_child("FriendTabs", true, false) as TabContainer
	assert(tabs != null)
	var room := tabs.get_child(1).get_child(0) as VBoxContainer
	assert(room != null)
	assert(room.find_child("RoomKeyboard", true, false) != null)
	var keyboard := room.find_child("RoomKeyboard", true, false) as VBoxContainer
	var first_row := keyboard.get_child(0) as HBoxContainer
	(first_row.get_child(0) as Button).pressed.emit()
	assert(menu._room_code == "1")
	var edits := keyboard.get_child(keyboard.get_child_count() - 1) as HBoxContainer
	(edits.get_child(0) as Button).pressed.emit()
	assert(menu._room_code.is_empty())
	var hosts: Array[String] = []
	var joins: Array[String] = []
	var leaves := [0]
	menu.multiplayer_host_requested.connect(func(code: String) -> void: hosts.append(code))
	menu.multiplayer_join_requested.connect(func(code: String) -> void: joins.append(code))
	menu.multiplayer_leave_requested.connect(func() -> void: leaves[0] += 1)
	menu._submit_room(true)
	assert(hosts.is_empty())
	menu.set_room_code("ab")
	menu._submit_room(false)
	assert(joins.is_empty())
	menu.set_room_code("ab3-$")
	assert(menu._room_code == "AB3-")
	menu._submit_room(true)
	assert(hosts == ["AB3-"])
	menu._submit_room(false)
	assert(joins == ["AB3-"])
	menu.set_shared_role("host")
	assert(menu._room_leave_buttons[0].visible)
	menu._room_leave_buttons[0].pressed.emit()
	assert(leaves[0] == 1)
	menu.set_multiplayer_status("Hosting private game")
	assert(menu._xr_room_status.text == "Hosting private game")
	print("FRIEND_ROOM_CHECKS_OK")
	quit()
