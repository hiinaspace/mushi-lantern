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
signal mode_requested(mode: String)
signal comfort_changed(settings: Dictionary)

var _desktop_root: Control
var _desktop_panel: PanelContainer
var _desktop_tabs: TabContainer
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
var _mode_selectors: Array[OptionButton] = []
var _selected_mode := "classic"
var _elapsed_labels: Array[Label] = []
var _comfort := {"snap_turn": false, "move_hand": "left", "vignette_strength": 0.0, "haptics": true}
var _comfort_turns: Array[OptionButton] = []
var _comfort_hands: Array[OptionButton] = []
var _comfort_vignettes: Array[HSlider] = []
var _comfort_vignette_labels: Array[Label] = []
var _comfort_haptics: Array[CheckButton] = []
var _desktop_comfort: VBoxContainer


func _ready() -> void:
	_font_theme = Theme.new()
	_font_theme.default_font = load("res://assets/fonts/KleeOne-SemiBold.ttf") as Font
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
	for selector in _mode_selectors:
		selector.visible = role != "client"
	_refresh_room_ui()


func set_multiplayer_status(status: String) -> void:
	_room_note = status
	_refresh_room_ui()


func set_elapsed_time(seconds: float) -> void:
	var elapsed := maxi(0, int(seconds))
	var hours := elapsed / 3600
	var minutes := (elapsed / 60) % 60
	var remainder := elapsed % 60
	var formatted := "%02d:%02d:%02d" % [hours, minutes, remainder] if hours > 0 else "%02d:%02d" % [minutes, remainder]
	for label in _elapsed_labels:
		label.text = "Elapsed: " + formatted


func set_room_code(code: String) -> void:
	_room_code = _normalize_room_code(code)
	_refresh_room_ui()


func _normalize_room_code(code: String) -> String:
	var normalized := ""
	for character in code.to_upper():
		if (character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character == "-":
			normalized += character
		if normalized.length() >= 24:
			break
	return normalized


func _on_desktop_room_text_changed(value: String) -> void:
	# Keep the authoritative code in sync without replacing LineEdit.text on every
	# keystroke; set_text resets the native caret position on some desktop builds.
	_room_code = _normalize_room_code(value)
	_refresh_room_ui()


func _submit_room(hosting: bool) -> void:
	if _shared_role != "offline":
		return
	if _desktop_room_edit != null and _desktop_tabs != null and _desktop_tabs.current_tab == 1:
		set_room_code(_desktop_room_edit.text)
	if _room_code.length() < 3:
		_room_note = "Code needs at least 3 letters or numbers."
		_refresh_room_ui()
		return
	_room_note = "Hosting private game…" if hosting else "Joining private game…"
	_refresh_room_ui()
	if hosting:
		mode_requested.emit(_selected_mode)
		multiplayer_host_requested.emit(_room_code)
	else:
		multiplayer_join_requested.emit(_room_code)


func _refresh_room_ui() -> void:
	if _desktop_room_edit != null and not _desktop_room_edit.has_focus() and _desktop_room_edit.text != _room_code:
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
		_update_mute_button(button)
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


func set_comfort_values(settings: Dictionary) -> void:
	_comfort["snap_turn"] = bool(settings.get("snap_turn", _comfort["snap_turn"]))
	_comfort["move_hand"] = "right" if settings.get("move_hand", _comfort["move_hand"]) == "right" else "left"
	_comfort["vignette_strength"] = clampf(float(settings.get("vignette_strength", _comfort["vignette_strength"])), 0.0, 1.0)
	_comfort["haptics"] = bool(settings.get("haptics", _comfort["haptics"]))
	for selector in _comfort_turns:
		selector.select(1 if _comfort["snap_turn"] else 0)
	for selector in _comfort_hands:
		selector.select(1 if _comfort["move_hand"] == "right" else 0)
	for slider in _comfort_vignettes:
		slider.set_value_no_signal(_comfort["vignette_strength"])
	for label in _comfort_vignette_labels:
		label.text = "%d%%" % roundi(float(_comfort["vignette_strength"]) * 100.0)
	for button in _comfort_haptics:
		button.set_pressed_no_signal(_comfort["haptics"])


func _set_comfort_value(key: String, value: Variant) -> void:
	var next := _comfort.duplicate()
	next[key] = value
	set_comfort_values(next)
	comfort_changed.emit(_comfort.duplicate())


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
	var session := _create_xr_tab("Play")
	var room := _create_xr_tab("Session")
	var intro := _create_xr_tab("Guide")
	for child in intro_nodes:
		child.reparent(intro)
	var comfort := _create_xr_tab("Comfort")
	_xr_settings = _create_xr_tab("Settings")
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
	var xr_elapsed := Label.new()
	xr_elapsed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	session.add_child(xr_elapsed)
	_elapsed_labels.append(xr_elapsed)
	session.add_child(HSeparator.new())
	var start := _add_xr_button(session, "Start / restart", _on_new_game)
	start.name = "XRStartButton"
	_xr_start = start
	_xr_start.disabled = _shared_role == "client"
	_add_mode_selector(session)
	var session_hint := Label.new()
	session_hint.text = "Play solo here, or use Session for a private game."
	session_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	session.add_child(session_hint)
	var quit := _add_xr_button(session, "Quit", _on_quit)
	quit.name = "XRQuitButton"
	_build_xr_room(room)
	_add_voice_mute_button(room)
	_add_comfort_controls(comfort)
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
	heading.text = "SESSION · EXPERIMENTAL"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	room.add_child(heading)
	var info := Label.new()
	info.text = "Private peer-to-peer game for two. Host shares a code; friend joins with the same code. The host runs the grove."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room.add_child(info)
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
		margin.add_theme_constant_override(side, 24)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	_desktop_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	margin.add_child(stack)
	var title := Label.new()
	title.text = "MUSHI LANTERN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 31)
	title.add_theme_color_override("font_color", Color("e2d8f1"))
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A quiet night walk through the grove"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("bdc9c5"))
	stack.add_child(subtitle)
	_desktop_tabs = TabContainer.new()
	_desktop_tabs.name = "DesktopTabs"
	_desktop_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desktop_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_desktop_tabs)
	var play := _create_desktop_tab("Play")
	var session := _create_desktop_tab("Session")
	var guide := _create_desktop_tab("Guide")
	var comfort := _create_desktop_tab("Comfort")
	var settings := _create_desktop_tab("Settings")
	var voice := _create_desktop_tab("Voice")
	_desktop_status = Label.new()
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_status.add_theme_font_size_override("font_size", 16)
	play.add_child(_desktop_status)
	var desktop_elapsed := Label.new()
	desktop_elapsed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play.add_child(desktop_elapsed)
	_elapsed_labels.append(desktop_elapsed)
	play.add_child(HSeparator.new())
	_desktop_start = _add_desktop_button(play, "Start / restart", _on_new_game)
	_desktop_start.disabled = _shared_role == "client"
	_add_mode_selector(play)
	var play_hint := Label.new()
	play_hint.text = "Play solo here, or use Session for a private game."
	play_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	play.add_child(play_hint)
	_add_desktop_button(play, "Quit", _on_quit)
	_build_desktop_room(session)
	var guide_intro := Label.new()
	guide_intro.text = "Controls"
	guide_intro.add_theme_font_size_override("font_size", 21)
	guide.add_child(guide_intro)
	var controls := Label.new()
	controls.text = "Move: WASD · Look: mouse · Aim lamp: hold left mouse\nHold right mouse: drag down/up for shutter, sideways for filter\nDrop / pick up staff: G · Recall: hold E"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_child(controls)
	_desktop_skip = _add_desktop_button(guide, "Skip introduction", func() -> void: skip_requested.emit())
	_desktop_skip.visible = false
	_desktop_tuning = _add_desktop_button(guide, "Open tuning sandbox", func() -> void: tuning_requested.emit())
	_desktop_tuning.visible = false
	_add_comfort_controls(comfort)
	_add_desktop_button(settings, "Visual quality", _on_settings)
	_add_desktop_button(settings, "Audio mix", func() -> void: audio_settings_requested.emit())
	var fit_heading := Label.new()
	fit_heading.text = "Avatar fit"
	settings.add_child(fit_heading)
	_desktop_avatar_fit = VBoxContainer.new()
	settings.add_child(_desktop_avatar_fit)
	_add_avatar_fit_sliders(_desktop_avatar_fit)
	_desktop_comfort = comfort
	var voice_note := Label.new()
	voice_note.text = "Voice chat is experimental in private sessions."
	voice_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voice.add_child(voice_note)
	_add_voice_mute_button(voice)
	_desktop_voice_button = _add_desktop_button(voice, "Microphone settings", func() -> void:
		_desktop_voice_settings.visible = not _desktop_voice_settings.visible
		if _desktop_voice_settings.visible:
			voice_devices_requested.emit())
	_desktop_voice_button.visible = _voice_available
	_desktop_voice_settings = VBoxContainer.new()
	_desktop_voice_settings.visible = false
	voice.add_child(_desktop_voice_settings)
	_add_voice_settings(_desktop_voice_settings)
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
		mode_requested.emit(_selected_mode)
		new_game_requested.emit()
		set_open(false)
	)
	add_child(_restart_confirm)
	get_viewport().size_changed.connect(_fit_desktop_panel)
	_fit_desktop_panel()
	_desktop_tabs.current_tab = 0
	_refresh_room_ui()


func _fit_desktop_panel() -> void:
	if _desktop_panel == null:
		return
	var available := get_viewport().get_visible_rect().size
	_desktop_panel.custom_minimum_size = Vector2(maxf(280.0, minf(660.0, available.x - 28.0)),
		maxf(260.0, minf(630.0, available.y - 28.0)))


func _create_desktop_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_desktop_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.name = "Contents"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	scroll.add_child(page)
	return page

func _build_desktop_room(parent: VBoxContainer) -> void:
	_desktop_room_panel = PanelContainer.new()
	_desktop_room_panel.name = "PrivateRoom"
	_desktop_room_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_desktop_room_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.064, 0.98)
	style.border_color = Color(0.48, 0.39, 0.62, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	_desktop_room_panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_desktop_room_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var heading := Label.new()
	heading.text = "PRIVATE SESSION · EXPERIMENTAL"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 21)
	stack.add_child(heading)
	var info := Label.new()
	info.text = "Private peer-to-peer game for two. Host shares a code; friend joins with the same code. The host runs the grove."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(info)
	_desktop_room_status = Label.new()
	_desktop_room_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_desktop_room_status)
	_desktop_room_edit = LineEdit.new()
	_desktop_room_edit.placeholder_text = "Room code (3–24 characters)"
	_desktop_room_edit.max_length = 24
	_desktop_room_edit.custom_minimum_size.y = 42
	_desktop_room_edit.text_changed.connect(_on_desktop_room_text_changed)
	_desktop_room_edit.text_submitted.connect(func(_value: String) -> void: _submit_room(false))
	stack.add_child(_desktop_room_edit)
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	var host := Button.new()
	host.text = "Host"
	host.custom_minimum_size.y = 42
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(func() -> void: _submit_room(true))
	actions.add_child(host)
	_room_host_buttons.append(host)
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size.y = 42
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(func() -> void: _submit_room(false))
	actions.add_child(join)
	_room_join_buttons.append(join)
	var leave := _add_desktop_button(stack, "Leave private room", func() -> void: multiplayer_leave_requested.emit())
	_room_leave_buttons.append(leave)


func _show_desktop_room(show: bool) -> void:
	_desktop_tabs.current_tab = 1 if show else 0
	if show and _shared_role == "offline":
		_desktop_room_edit.grab_focus()


func _add_section_label(parent: VBoxContainer, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("b0cfc4"))
	parent.add_child(label)


func _add_comfort_controls(parent: VBoxContainer) -> void:
	var explanation := Label.new()
	explanation.text = "VR comfort · one-controller move/turn fallback is automatic."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(explanation)
	var turn := OptionButton.new()
	turn.add_item("Smooth turn", 0)
	turn.add_item("Snap turn", 1)
	turn.item_selected.connect(func(index: int) -> void: _set_comfort_value("snap_turn", index == 1))
	parent.add_child(turn)
	_comfort_turns.append(turn)
	var hand := OptionButton.new()
	hand.add_item("Move: left hand · Turn: right hand", 0)
	hand.add_item("Move: right hand · Turn: left hand", 1)
	hand.item_selected.connect(func(index: int) -> void: _set_comfort_value("move_hand", "right" if index == 1 else "left"))
	parent.add_child(hand)
	_comfort_hands.append(hand)
	var vignette_row := HBoxContainer.new()
	parent.add_child(vignette_row)
	var vignette_title := Label.new()
	vignette_title.text = "Move vignette"
	vignette_row.add_child(vignette_title)
	var vignette := HSlider.new()
	vignette.min_value = 0.0
	vignette.max_value = 1.0
	vignette.step = 0.05
	vignette.custom_minimum_size.x = 130.0
	vignette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vignette.value_changed.connect(func(value: float) -> void: _set_comfort_value("vignette_strength", value))
	vignette_row.add_child(vignette)
	_comfort_vignettes.append(vignette)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 45.0
	vignette_row.add_child(value_label)
	_comfort_vignette_labels.append(value_label)
	var haptics := CheckButton.new()
	haptics.text = "Controller vibration"
	haptics.toggled.connect(func(enabled: bool) -> void: _set_comfort_value("haptics", enabled))
	parent.add_child(haptics)
	_comfort_haptics.append(haptics)
	set_comfort_values(_comfort)


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


func _add_mode_selector(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "Host mode"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_item("Classic", 0)
	selector.add_item("Two shrines · PvP", 1)
	selector.select(0)
	selector.item_selected.connect(func(index: int) -> void:
		_selected_mode = "two_shrines" if selector.get_item_id(index) == 1 else "classic"
		for other in _mode_selectors:
			if other != selector:
				other.select(index))
	row.add_child(selector)
	parent.add_child(row)
	_mode_selectors.append(selector)
	selector.visible = _shared_role != "client"


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
	mode_requested.emit(_selected_mode)
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
	button.visible = _voice_available
	button.custom_minimum_size.y = 60.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		_voice_muted = not _voice_muted
		for other in _voice_buttons:
			_update_mute_button(other)
		voice_mute_changed.emit(_voice_muted))
	parent.add_child(button)
	_voice_buttons.append(button)
	_update_mute_button(button)


func _update_mute_button(button: Button) -> void:
	button.text = "MIC MUTED · TAP TO UNMUTE" if _voice_muted else "MIC LIVE · TAP TO MUTE"
	button.add_theme_font_size_override("font_size", 19)
	var color := Color("287f55") if _voice_muted else Color("a9343c")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.12) if state == "hover" else color.darkened(0.08) if state == "pressed" else color
		style.set_corner_radius_all(8)
		style.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color.WHITE)


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
