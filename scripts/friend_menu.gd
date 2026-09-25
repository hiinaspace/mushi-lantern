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

var _desktop_root: Control
var _desktop_panel: PanelContainer
var _desktop_visible: bool = false
var _desktop_status: Label
var _desktop_skip: Button
var _desktop_tuning: Button
var _xr_contents: VBoxContainer
var _xr_settings: VBoxContainer
var _xr_audio: VBoxContainer
var _xr_audio_scroll: ScrollContainer
var _xr_status: Label
var _font_theme: Theme


func _ready() -> void:
	_font_theme = Theme.new()
	_font_theme.default_font = load("res://assets/fonts/DejaVuSans.ttf") as Font
	_build_desktop_menu()
	_desktop_root.theme = _font_theme
	_desktop_root.visible = _desktop_visible


func set_open(open: bool) -> void:
	if _desktop_root == null or _desktop_visible == open:
		return
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
	var session := VBoxContainer.new()
	session.name = "FriendSession"
	session.add_theme_constant_override("separation", 8)
	contents.add_child(session)
	contents.move_child(session, 0)
	var title := Label.new()
	title.text = "MUSHI LANTERN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("e2d8f1"))
	session.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A quiet night walk through the grove"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	session.add_child(subtitle)
	_xr_status = Label.new()
	_xr_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xr_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xr_status.text = "Paused"
	session.add_child(_xr_status)
	session.add_child(HSeparator.new())
	var start := _add_xr_button(session, "Start / restart", _on_new_game)
	start.name = "XRStartButton"
	var settings := _add_xr_button(session, "Settings", _toggle_xr_settings)
	settings.name = "XRSettingsButton"
	var audio := _add_xr_button(session, "Audio", _toggle_xr_audio)
	audio.name = "XRAudioButton"
	var quit := _add_xr_button(session, "Quit", _on_quit)
	quit.name = "XRQuitButton"
	_move_existing_button(contents, session, "Skip introduction")
	_move_existing_button(contents, session, "Open tuning sandbox")
	_move_existing_button(contents, session, "Close tuning sandbox")
	_xr_settings = VBoxContainer.new()
	_xr_settings.name = "XRQualitySettings"
	_xr_settings.visible = false
	_xr_settings.add_theme_constant_override("separation", 6)
	session.add_child(_xr_settings)
	_add_xr_button(_xr_settings, "Quality: Default", func() -> void: quality_profile_requested.emit("default"))
	_add_xr_button(_xr_settings, "Quality: Performance", func() -> void: quality_profile_requested.emit("performance"))
	if _xr_audio != null:
		session.add_child(_xr_audio)


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
	_add_desktop_button(stack, "Start / restart", _on_new_game)
	_add_desktop_button(stack, "Settings", _on_settings)
	_add_desktop_button(stack, "Audio", func() -> void: audio_settings_requested.emit())
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


func _add_desktop_button(parent: VBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_xr_button(parent: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _on_new_game() -> void:
	new_game_requested.emit()
	if _desktop_visible:
		set_open(false)


func _on_settings() -> void:
	settings_requested.emit()


func _toggle_xr_settings() -> void:
	if _xr_settings != null:
		_xr_settings.visible = not _xr_settings.visible


func _on_quit() -> void:
	quit_requested.emit()
