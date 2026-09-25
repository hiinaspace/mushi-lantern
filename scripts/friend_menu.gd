class_name FriendMenu
extends CanvasLayer

## Small player-facing menu for friend builds. Game-specific reset/settings
## behavior stays in the main scene and is connected through these signals.
signal new_game_requested
signal settings_requested
signal audio_settings_requested
signal quality_profile_requested(profile: String)
signal skip_requested
signal tuning_requested
signal quit_requested
signal menu_visibility_changed(open: bool)
signal avatar_fit_changed(standing_height: float, arm_reach: float)
signal voice_mute_changed(muted: bool)
signal voice_input_device_changed(device: String)
signal voice_gain_changed(gain_db: float)
signal voice_gate_changed(threshold_db: float)
signal voice_receive_gain_changed(gain_db: float)
signal voice_devices_requested
signal multiplayer_host_requested(secret: String)
signal multiplayer_join_requested(secret: String)
signal multiplayer_leave_requested

var _desktop_root: Control
var _desktop_panel: PanelContainer
var _desktop_visible: bool = false
var _desktop_status: Label
var _desktop_skip: Button
var _desktop_tuning: Button
var _xr_contents: VBoxContainer
var _xr_tabs: TabContainer
var _xr_settings: VBoxContainer
var _xr_audio: VBoxContainer
var _xr_voice: VBoxContainer
var _xr_audio_scroll: ScrollContainer
var _xr_status: Label
var _font_theme: Theme
var _shared_role := "offline"
var _desktop_start: Button
var _xr_start: Button
var _restart_confirm: ConfirmationDialog
var _xr_restart_armed := false
var _desktop_avatar_fit: VBoxContainer
var _avatar_fit_height := 1.6
var _avatar_fit_reach := 1.3
var _avatar_fit_controls: Array[Dictionary] = []
var _avatar_fit_pending := false
var _voice_muted := true
var _voice_device := "Default"
var _voice_devices: PackedStringArray = PackedStringArray(["Default"])
var _voice_gain_db := 0.0
var _voice_gate_db := -38.0
var _voice_receive_gain_db := 0.0
var _voice_buttons: Array[Button] = []
var _voice_device_options: Array[OptionButton] = []
var _voice_device_cycle_buttons: Array[Button] = []
var _voice_gain_sliders: Array[HSlider] = []
var _voice_gain_labels: Array[Label] = []
var _voice_gate_sliders: Array[HSlider] = []
var _voice_gate_labels: Array[Label] = []
var _voice_receive_sliders: Array[HSlider] = []
var _voice_receive_labels: Array[Label] = []
var _voice_meter_bars: Array[ProgressBar] = []
var _voice_meter_labels: Array[Label] = []
var _desktop_voice_settings: VBoxContainer
var _desktop_voice_button: Button
var _voice_settings_sections: Array[VBoxContainer] = []
var _voice_available := false
var _room_code := ""
var _room_note := "Enter the same private code on each computer."
var _desktop_room_panel: PanelContainer
var _desktop_room_edit: LineEdit
var _desktop_room_status: Label
var _xr_room_code: Label
var _xr_room_status: Label
var _room_entry_controls: Array[Control] = []
var _room_host_buttons: Array[Button] = []
var _room_join_buttons: Array[Button] = []
var _room_leave_buttons: Array[Button] = []


func _ready() -> void:
	_font_theme = Theme.new()
	_font_theme.default_font = load("res://assets/fonts/DejaVuSans.ttf") as Font
	_build_desktop_menu()
	_desktop_root.theme = _font_theme
	_desktop_root.visible = _desktop_visible


func set_open(open: bool) -> void:
	if _desktop_root == null or _desktop_visible == open:
		return
	if not open:
		commit_avatar_fit()
	_desktop_visible = open
	_desktop_root.visible = open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_visibility_changed.emit(open)


func is_open() -> bool:
	return _desktop_visible


func toggle() -> void:
	set_open(not _desktop_visible)


func update_session(status: String, tutorial_active: bool, tuning_unlocked: bool) -> void:
	if _desktop_status != null:
		_desktop_status.text = status
		_desktop_skip.visible = tutorial_active
		_desktop_tuning.visible = tuning_unlocked
	if _xr_status != null:
		_xr_status.text = "Paused · " + status


func set_shared_role(role: String) -> void:
	_shared_role = role
	_xr_restart_armed = false
	if _desktop_start != null:
		_desktop_start.disabled = role == "client"
	if _xr_start != null:
		_xr_start.disabled = role == "client"
		_xr_start.text = "Start / restart"
	_refresh_room_ui()


func set_multiplayer_status(status: String) -> void:
	_room_note = status
	_refresh_room_ui()


func set_room_code(code: String) -> void:
	var normalized := ""
	for character in code.to_upper():
		if (character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character == "-":
			normalized += character
		if normalized.length() >= 24:
			break
	_room_code = normalized
	_refresh_room_ui()


func _submit_room(hosting: bool) -> void:
	if _shared_role != "offline":
		return
	if _desktop_room_edit != null and _desktop_room_panel.visible:
		set_room_code(_desktop_room_edit.text)
	if _room_code.length() < 3:
		_room_note = "Code needs at least 3 letters or numbers."
		_refresh_room_ui()
		return
	_room_note = "Hosting private game…" if hosting else "Joining private game…"
	_refresh_room_ui()
	if hosting:
		multiplayer_host_requested.emit(_room_code)
	else:
		multiplayer_join_requested.emit(_room_code)


func _refresh_room_ui() -> void:
	if _desktop_room_edit != null and _desktop_room_edit.text != _room_code:
		_desktop_room_edit.text = _room_code
	if _desktop_room_edit != null:
		_desktop_room_edit.editable = _shared_role == "offline"
	if _xr_room_code != null:
		_xr_room_code.text = _room_code if not _room_code.is_empty() else "Tap the keys below"
	if _desktop_room_status != null:
		_desktop_room_status.text = _room_note
	if _xr_room_status != null:
		_xr_room_status.text = _room_note
	for control in _room_entry_controls:
		control.visible = _shared_role == "offline"
	for button in _room_host_buttons:
		button.disabled = _shared_role != "offline" or _room_code.length() < 3
	for button in _room_join_buttons:
		button.disabled = _shared_role != "offline" or _room_code.length() < 3
	for button in _room_leave_buttons:
		button.visible = _shared_role != "offline"


func set_avatar_fit_values(standing_height: float, arm_reach: float) -> void:
	_avatar_fit_height = clampf(standing_height, 1.1, 2.1)
	_avatar_fit_reach = clampf(arm_reach, 0.9, 1.5)
	_avatar_fit_pending = false
	for control in _avatar_fit_controls:
		var current := _avatar_fit_height if control.key == "height" else _avatar_fit_reach
		(control.slider as HSlider).set_value_no_signal(current)
		(control.value_label as Label).text = "%.2f" % current


func commit_avatar_fit() -> void:
	if not _avatar_fit_pending:
		return
	_avatar_fit_pending = false
	avatar_fit_changed.emit(_avatar_fit_height, _avatar_fit_reach)


func set_voice_controls(muted: bool, device: String, devices: PackedStringArray,
		gain_db: float, gate_db: float = -38.0, receive_gain_db: float = 0.0) -> void:
	_voice_muted = muted
	_voice_device = device
	_voice_devices = devices if not devices.is_empty() else PackedStringArray(["Default"])
	_voice_gain_db = clampf(gain_db, -24.0, 24.0)
	_voice_gate_db = clampf(gate_db, -60.0, -20.0)
	_voice_receive_gain_db = clampf(receive_gain_db, -30.0, 12.0)
	for button in _voice_buttons:
		button.text = "Unmute mic" if _voice_muted else "Mute mic"
	for option in _voice_device_options:
		option.clear()
		var selected := 0
		for index in _voice_devices.size():
			option.add_item(_voice_devices[index])
			if _voice_devices[index] == _voice_device:
				selected = index
		option.select(selected)
	for button in _voice_device_cycle_buttons:
		button.text = "Mic: " + _voice_device
	for slider in _voice_gain_sliders:
		slider.set_value_no_signal(_voice_gain_db)
	for label in _voice_gain_labels:
		label.text = "%+.0f dB" % _voice_gain_db
	for slider in _voice_gate_sliders:
		slider.set_value_no_signal(_voice_gate_db)
	for label in _voice_gate_labels:
		label.text = "%.0f dBFS" % _voice_gate_db
	for slider in _voice_receive_sliders:
		slider.set_value_no_signal(_voice_receive_gain_db)
	for label in _voice_receive_labels:
		label.text = "%+.0f dB" % _voice_receive_gain_db


func set_voice_meter(level_db: float) -> void:
	var db := clampf(level_db, -80.0, 0.0)
	for bar in _voice_meter_bars:
		bar.value = db
	for label in _voice_meter_labels:
		label.text = "Mic level: %.0f dBFS" % db


func set_voice_available(available: bool) -> void:
	_voice_available = available
	for button in _voice_buttons:
		button.visible = available
	if _desktop_voice_button != null:
		_desktop_voice_button.visible = available
		if not available and _desktop_voice_settings != null:
			_desktop_voice_settings.visible = false
	for section in _voice_settings_sections:
		section.visible = available


## Adds the same actions to the existing world-anchored XR Tools menu.
## The XR rig owns menu placement, pointer visibility, and close behavior.
func attach_xr_menu(menu_root: Control) -> void:
	if menu_root == null:
		return
	# AudioMixPanel wraps the original Contents in AudioScroll. Find it under
	# either structure so the friend menu always lands on the live XR surface.
	var contents := menu_root.get_node_or_null("Panel/Margin/Contents") as VBoxContainer
	if contents == null:
		contents = menu_root.get_node_or_null("Panel/Margin/AudioScroll/Contents") as VBoxContainer
	if contents == null:
		contents = menu_root.find_child("Contents", true, false) as VBoxContainer
	if contents == null or _xr_contents == contents:
		return
	_xr_contents = contents
	menu_root.theme = _font_theme
	_xr_audio_scroll = contents.get_parent() as ScrollContainer
	_remove_legacy_xr_header(contents)
	_wrap_xr_audio_section(contents)
	_build_xr_session(contents)


func _remove_legacy_xr_header(contents: VBoxContainer) -> void:
	for child in contents.get_children():
		if child.name in ["Title", "Description"]:
			contents.remove_child(child)
			child.queue_free()


func _wrap_xr_audio_section(contents: VBoxContainer) -> void:
	var audio_title: Control
	for child in contents.get_children():
		if child is Label and (child as Label).text.begins_with("Audio mix ·"):
			audio_title = child
			break
	if audio_title == null:
		return
	_xr_audio = VBoxContainer.new()
	_xr_audio.name = "FriendAudioControls"
	_xr_audio.visible = false
	_xr_audio.add_theme_constant_override("separation", 5)
	var start_index := audio_title.get_index()
	if start_index > 0 and contents.get_child(start_index - 1) is HSeparator:
		start_index -= 1
	var moving: Array[Node] = []
	for index in range(start_index, contents.get_child_count()):
		moving.append(contents.get_child(index))
	for child in moving:
		contents.remove_child(child)
		_xr_audio.add_child(child)


func _build_xr_session(contents: VBoxContainer) -> void:
	var intro_nodes := contents.get_children()
	_xr_tabs = TabContainer.new()
	_xr_tabs.name = "FriendTabs"
	_xr_tabs.custom_minimum_size.y = 455.0
	_xr_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xr_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(_xr_tabs)
	if _xr_audio_scroll != null:
		_xr_audio_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var session := _create_xr_tab("Session")
	var room := _create_xr_tab("Room")
	var intro := _create_xr_tab("Intro")
	for child in intro_nodes:
		child.reparent(intro)
	_xr_settings = _create_xr_tab("Avatar")
	_xr_voice = _create_xr_tab("Voice")
	var mix := _create_xr_tab("Mix")
	var mushi := _create_xr_tab("Mushi")
	var title := Label.new()
	title.text = "MUSHI LANTERN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("e2d8f1"))
	session.add_child(title)
	_xr_status = Label.new()
	_xr_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xr_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xr_status.text = "Paused"
	session.add_child(_xr_status)
	session.add_child(HSeparator.new())
	var start := _add_xr_button(session, "Start / restart", _on_new_game)
	start.name = "XRStartButton"
	_xr_start = start
	_xr_start.disabled = _shared_role == "client"
	_add_voice_mute_button(session)
	var quit := _add_xr_button(session, "Quit", _on_quit)
	quit.name = "XRQuitButton"
	_build_xr_room(room)
	_add_xr_button(_xr_settings, "Quality: Default", func() -> void: quality_profile_requested.emit("default"))
	_add_xr_button(_xr_settings, "Quality: Performance", func() -> void: quality_profile_requested.emit("performance"))
	_add_avatar_fit_sliders(_xr_settings)
	if _xr_audio != null:
		var bus_rows := 0
		for child in _xr_audio.get_children():
			var bus_row := child is HBoxContainer and bus_rows < 5
			if bus_row:
				bus_rows += 1
			child.reparent(mix if bus_rows < 5 or bus_row else mushi)
		_xr_audio.queue_free()
		_xr_audio = null
	_add_voice_settings(_xr_voice, true)
	_xr_tabs.current_tab = 0
	_refresh_room_ui()


func _create_xr_tab(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.add_theme_constant_override("separation", 7)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_xr_tabs.add_child(page)
	return page


func _build_xr_room(room: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "PRIVATE ROOM"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	room.add_child(heading)
	_xr_room_status = Label.new()
	_xr_room_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xr_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xr_room_status.custom_minimum_size.y = 35
	room.add_child(_xr_room_status)
	_xr_room_code = Label.new()
	_xr_room_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xr_room_code.add_theme_font_size_override("font_size", 24)
	_xr_room_code.custom_minimum_size.y = 35
	room.add_child(_xr_room_code)
	var keyboard := VBoxContainer.new()
	keyboard.name = "RoomKeyboard"
	keyboard.add_theme_constant_override("separation", 3)
	room.add_child(keyboard)
	_room_entry_controls.append(keyboard)
	for keys in ["1234567890", "QWERTYUIOP", "ASDFGHJKL-", "ZXCVBNM"]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 3)
		keyboard.add_child(row)
		for character in keys:
			var key := Button.new()
			key.text = character
			key.custom_minimum_size = Vector2(39, 41)
			key.pressed.connect(func() -> void: set_room_code(_room_code + character))
			row.add_child(key)
	var edits := HBoxContainer.new()
	edits.alignment = BoxContainer.ALIGNMENT_CENTER
	keyboard.add_child(edits)
	var backspace := Button.new()
	backspace.text = "⌫ Backspace"
	backspace.custom_minimum_size = Vector2(145, 40)
	backspace.pressed.connect(func() -> void: set_room_code(_room_code.substr(0, maxi(0, _room_code.length() - 1))))
	edits.add_child(backspace)
	var clear := Button.new()
	clear.text = "Clear"
	clear.custom_minimum_size = Vector2(110, 40)
	clear.pressed.connect(func() -> void: set_room_code(""))
	edits.add_child(clear)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	room.add_child(actions)
	var host := Button.new()
	host.text = "Host"
	host.custom_minimum_size.y = 44
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(func() -> void: _submit_room(true))
	actions.add_child(host)
	_room_host_buttons.append(host)
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size.y = 44
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(func() -> void: _submit_room(false))
	actions.add_child(join)
	_room_join_buttons.append(join)
	var leave := _add_xr_button(room, "Leave private room", func() -> void: multiplayer_leave_requested.emit())
	_room_leave_buttons.append(leave)


func _move_existing_button(source: VBoxContainer, destination: VBoxContainer, wanted_text: String) -> void:
	var button := _find_button_text(source, wanted_text)
	if button == null:
		return
	button.get_parent().remove_child(button)
	destination.add_child(button)


func _find_button_text(parent: Node, wanted_text: String) -> Button:
	for child in parent.get_children():
		if child is Button and (child as Button).text == wanted_text:
			return child as Button
		var found := _find_button_text(child, wanted_text)
		if found != null:
			return found
	return null


func _toggle_xr_audio() -> void:
	if _xr_audio == null:
		return
	_xr_audio.visible = not _xr_audio.visible
	if _xr_audio.visible and _xr_audio_scroll != null:
		voice_devices_requested.emit()
		_xr_audio_scroll.call_deferred("ensure_control_visible", _xr_audio)


func _build_desktop_menu() -> void:
	_desktop_root = Control.new()
	_desktop_root.name = "FriendMenu"
	_desktop_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desktop_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_desktop_root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.012, 0.02, 0.026, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_desktop_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desktop_root.add_child(center)
	_desktop_panel = PanelContainer.new()
	_desktop_panel.custom_minimum_size = Vector2(520.0, 0.0)
	_desktop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_desktop_panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.064, 0.98)
	panel_style.border_color = Color(0.48, 0.39, 0.62, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	_desktop_panel.add_theme_stylebox_override("panel", panel_style)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 34)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	_desktop_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	var title := Label.new()
	title.text = "MUSHI LANTERN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("e2d8f1"))
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A quiet night walk through the grove"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color("bdc9c5"))
	stack.add_child(subtitle)
	stack.add_child(HSeparator.new())
	_desktop_start = _add_desktop_button(stack, "Start / restart", _on_new_game)
	_desktop_start.disabled = _shared_role == "client"
	_add_desktop_button(stack, "Private room", func() -> void: _show_desktop_room(true))
	_add_desktop_button(stack, "Settings", _on_settings)
	_add_desktop_button(stack, "Avatar fit", func() -> void:
		_desktop_avatar_fit.visible = not _desktop_avatar_fit.visible)
	_desktop_avatar_fit = VBoxContainer.new()
	_desktop_avatar_fit.visible = false
	stack.add_child(_desktop_avatar_fit)
	_add_avatar_fit_sliders(_desktop_avatar_fit)
	_add_desktop_button(stack, "Audio", func() -> void: audio_settings_requested.emit())
	_add_voice_mute_button(stack)
	_desktop_voice_button = _add_desktop_button(stack, "Microphone", func() -> void:
		_desktop_voice_settings.visible = not _desktop_voice_settings.visible
		if _desktop_voice_settings.visible:
			voice_devices_requested.emit())
	_desktop_voice_button.visible = _voice_available
	_desktop_voice_settings = VBoxContainer.new()
	_desktop_voice_settings.visible = false
	stack.add_child(_desktop_voice_settings)
	_add_voice_settings(_desktop_voice_settings)
	_add_desktop_button(stack, "Quit", _on_quit)
	stack.add_child(HSeparator.new())
	_desktop_status = Label.new()
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_status.add_theme_font_size_override("font_size", 16)
	stack.add_child(_desktop_status)
	_desktop_skip = Button.new()
	_desktop_skip.text = "Skip introduction"
	_desktop_skip.pressed.connect(func() -> void: skip_requested.emit())
	_desktop_skip.visible = false
	stack.add_child(_desktop_skip)
	_desktop_tuning = Button.new()
	_desktop_tuning.text = "Open tuning sandbox"
	_desktop_tuning.pressed.connect(func() -> void: tuning_requested.emit())
	_desktop_tuning.visible = false
	stack.add_child(_desktop_tuning)
	var controls := Label.new()
	controls.text = "Move: WASD · Look: mouse · Aim lamp: hold left mouse\nShutter: mouse wheel · Drop / pick up staff: G · Recall: hold E"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size", 14)
	controls.add_theme_color_override("font_color", Color("a7b5b2"))
	stack.add_child(controls)
	var close_hint := Label.new()
	close_hint.text = "Esc closes this menu"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 13)
	close_hint.add_theme_color_override("font_color", Color("8b9b98"))
	stack.add_child(close_hint)
	_restart_confirm = ConfirmationDialog.new()
	_restart_confirm.title = "Restart shared game?"
	_restart_confirm.dialog_text = "Reset the mushi and score for everyone in this session?"
	_restart_confirm.confirmed.connect(func() -> void:
		new_game_requested.emit()
		set_open(false)
	)
	add_child(_restart_confirm)
	_build_desktop_room(center)
	_refresh_room_ui()


func _build_desktop_room(center: CenterContainer) -> void:
	_desktop_room_panel = PanelContainer.new()
	_desktop_room_panel.name = "PrivateRoom"
	_desktop_room_panel.custom_minimum_size.x = 520
	_desktop_room_panel.visible = false
	center.add_child(_desktop_room_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.064, 0.98)
	style.border_color = Color(0.48, 0.39, 0.62, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	_desktop_room_panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	_desktop_room_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	var heading := Label.new()
	heading.text = "PRIVATE ROOM"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	stack.add_child(heading)
	_desktop_room_status = Label.new()
	_desktop_room_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_desktop_room_status)
	_desktop_room_edit = LineEdit.new()
	_desktop_room_edit.placeholder_text = "Room code (3–24 characters)"
	_desktop_room_edit.max_length = 24
	_desktop_room_edit.custom_minimum_size.y = 48
	_desktop_room_edit.text_changed.connect(func(value: String) -> void: set_room_code(value))
	_desktop_room_edit.text_submitted.connect(func(_value: String) -> void: _submit_room(false))
	stack.add_child(_desktop_room_edit)
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	var host := Button.new()
	host.text = "Host"
	host.custom_minimum_size.y = 48
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(func() -> void: _submit_room(true))
	actions.add_child(host)
	_room_host_buttons.append(host)
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size.y = 48
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(func() -> void: _submit_room(false))
	actions.add_child(join)
	_room_join_buttons.append(join)
	var leave := _add_desktop_button(stack, "Leave private room", func() -> void: multiplayer_leave_requested.emit())
	_room_leave_buttons.append(leave)
	_add_desktop_button(stack, "Back", func() -> void: _show_desktop_room(false))


func _show_desktop_room(show: bool) -> void:
	_desktop_panel.visible = not show
	_desktop_room_panel.visible = show
	if show and _shared_role == "offline":
		_desktop_room_edit.grab_focus()


func _add_desktop_button(parent: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_xr_button(parent: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _on_new_game() -> void:
	if _shared_role == "client":
		return
	if _shared_role == "host":
		if _desktop_visible:
			_restart_confirm.popup_centered()
			return
		if not _xr_restart_armed:
			_xr_restart_armed = true
			_xr_start.text = "Confirm restart for everyone"
			return
		_xr_restart_armed = false
		_xr_start.text = "Start / restart"
	new_game_requested.emit()
	if _desktop_visible:
		set_open(false)


func _on_settings() -> void:
	settings_requested.emit()


func _add_avatar_fit_sliders(parent: VBoxContainer) -> void:
	_add_avatar_fit_slider(parent, "XR standing eye height (m)", "height", 1.1, 2.1, _avatar_fit_height)
	_add_avatar_fit_slider(parent, "Arm reach", "reach", 0.9, 1.5, _avatar_fit_reach)


func _add_avatar_fit_slider(parent: VBoxContainer, title: String, key: String,
		minimum: float, maximum: float, initial: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 190.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size.x = 135.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "%.2f" % initial
	value_label.custom_minimum_size.x = 38.0
	row.add_child(value_label)
	_avatar_fit_controls.append({"key": key, "slider": slider, "value_label": value_label})
	slider.value_changed.connect(_on_avatar_fit_slider_changed.bind(key))


func _on_avatar_fit_slider_changed(value: float, key: String) -> void:
	if key == "height":
		_avatar_fit_height = value
	else:
		_avatar_fit_reach = value
	_avatar_fit_pending = true
	for control in _avatar_fit_controls:
		var current := _avatar_fit_height if control.key == "height" else _avatar_fit_reach
		(control.slider as HSlider).set_value_no_signal(current)
		(control.value_label as Label).text = "%.2f" % current


func _add_voice_mute_button(parent: VBoxContainer) -> void:
	var button := Button.new()
	button.text = "Unmute mic" if _voice_muted else "Mute mic"
	button.visible = _voice_available
	button.custom_minimum_size.y = 46.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		_voice_muted = not _voice_muted
		for other in _voice_buttons:
			other.text = "Unmute mic" if _voice_muted else "Mute mic"
		voice_mute_changed.emit(_voice_muted))
	parent.add_child(button)
	_voice_buttons.append(button)


func _add_voice_settings(parent: VBoxContainer, xr_cycle: bool = false) -> void:
	var section := VBoxContainer.new()
	section.visible = _voice_available
	parent.add_child(section)
	_voice_settings_sections.append(section)
	var title := Label.new()
	title.text = "Microphone input"
	section.add_child(title)
	if xr_cycle:
		var cycle := Button.new()
		cycle.text = "Mic: " + _voice_device
		cycle.custom_minimum_size.y = 46.0
		cycle.pressed.connect(func() -> void:
			var index := _voice_devices.find(_voice_device)
			_voice_device = _voice_devices[(index + 1) % _voice_devices.size()]
			voice_input_device_changed.emit(_voice_device))
		section.add_child(cycle)
		_voice_device_cycle_buttons.append(cycle)
	else:
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_child(option)
		_voice_device_options.append(option)
		option.item_selected.connect(func(index: int) -> void:
			_voice_device = option.get_item_text(index)
			voice_input_device_changed.emit(_voice_device))
	var refresh := Button.new()
	refresh.text = "Refresh microphones"
	refresh.pressed.connect(func() -> void: voice_devices_requested.emit())
	section.add_child(refresh)
	var row := HBoxContainer.new()
	section.add_child(row)
	var label := Label.new()
	label.text = "Input gain"
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = -24.0
	slider.max_value = 24.0
	slider.step = 1.0
	slider.custom_minimum_size.x = 160.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	_voice_gain_sliders.append(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 55.0
	row.add_child(value_label)
	_voice_gain_labels.append(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		_voice_gain_db = value
		for other in _voice_gain_sliders:
			other.set_value_no_signal(value)
		for other in _voice_gain_labels:
			other.text = "%+.0f dB" % value
		voice_gain_changed.emit(value))
	var gate_row := HBoxContainer.new()
	section.add_child(gate_row)
	var gate_title := Label.new()
	gate_title.text = "Noise gate"
	gate_row.add_child(gate_title)
	var gate := HSlider.new()
	gate.min_value = -60.0
	gate.max_value = -20.0
	gate.step = 1.0
	gate.custom_minimum_size.x = 160.0
	gate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gate_row.add_child(gate)
	_voice_gate_sliders.append(gate)
	var gate_value := Label.new()
	gate_value.custom_minimum_size.x = 75.0
	gate_row.add_child(gate_value)
	_voice_gate_labels.append(gate_value)
	gate.value_changed.connect(func(value: float) -> void:
		_voice_gate_db = value
		for other in _voice_gate_sliders:
			other.set_value_no_signal(value)
		for other in _voice_gate_labels:
			other.text = "%.0f dBFS" % value
		voice_gate_changed.emit(value))
	var receive_row := HBoxContainer.new()
	section.add_child(receive_row)
	var receive_title := Label.new()
	receive_title.text = "Other voices"
	receive_row.add_child(receive_title)
	var receive := HSlider.new()
	receive.min_value = -30.0
	receive.max_value = 12.0
	receive.step = 1.0
	receive.custom_minimum_size.x = 160.0
	receive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	receive_row.add_child(receive)
	_voice_receive_sliders.append(receive)
	var receive_value := Label.new()
	receive_value.custom_minimum_size.x = 55.0
	receive_row.add_child(receive_value)
	_voice_receive_labels.append(receive_value)
	receive.value_changed.connect(func(value: float) -> void:
		_voice_receive_gain_db = value
		for other in _voice_receive_sliders:
			other.set_value_no_signal(value)
		for other in _voice_receive_labels:
			other.text = "%+.0f dB" % value
		voice_receive_gain_changed.emit(value))
	var meter := ProgressBar.new()
	meter.min_value = -80.0
	meter.max_value = 0.0
	meter.show_percentage = false
	meter.custom_minimum_size.y = 18.0
	section.add_child(meter)
	_voice_meter_bars.append(meter)
	var meter_label := Label.new()
	section.add_child(meter_label)
	_voice_meter_labels.append(meter_label)
	var hint := Label.new()
	hint.text = "Meter is local even while muted. Set the gate above room noise."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(hint)
	set_voice_controls(_voice_muted, _voice_device, _voice_devices, _voice_gain_db,
		_voice_gate_db, _voice_receive_gain_db)
	set_voice_meter(-80.0)


func _toggle_xr_settings() -> void:
	if _xr_settings != null:
		_xr_settings.visible = not _xr_settings.visible


func _on_quit() -> void:
	quit_requested.emit()
