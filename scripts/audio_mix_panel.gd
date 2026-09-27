class_name AudioMixPanel
extends CanvasLayer

signal panel_visibility_changed(open: bool)
signal mushi_pitch_range_changed(calm: float, excited: float)

const SAVE_PATH := "user://audio_mix.json"
const UI_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
const BUS_NAMES: Array[String] = ["Master", "Mushi", "Forest", "Tool", "Steps"]
const MAX_LEVEL := 1.5
const MASTER_MAX_LEVEL := 6.0
const DEFAULT_LEVELS := {"Master": 5.88, "Mushi": 0.27, "Forest": 1.0, "Tool": 0.63, "Steps": 1.23}
const PITCH_MIN := 0.35
const PITCH_MAX := 1.6
const DEFAULT_CALM_PITCH := 0.5
const DEFAULT_EXCITED_PITCH := 1.0
const CALM_PITCH_KEY := "MushiCalmPitch"
const EXCITED_PITCH_KEY := "MushiExcitedPitch"

var _levels: Dictionary = {}
var _calm_pitch := DEFAULT_CALM_PITCH
var _excited_pitch := DEFAULT_EXCITED_PITCH
var _panel: PanelContainer
var _desktop_sliders: Dictionary = {}
var _xr_sliders: Dictionary = {}
var _desktop_pitch_sliders: Dictionary = {}
var _xr_pitch_sliders: Dictionary = {}
var _status_labels: Array[Label] = []


func _init() -> void:
	for bus_name: String in BUS_NAMES:
		_levels[bus_name] = DEFAULT_LEVELS[bus_name]
	_load_preset()


func _ready() -> void:
	_build_desktop_panel()
	_panel.visible = false
	_apply_levels()


func is_open() -> bool:
	return _panel != null and _panel.visible


func set_open(open: bool) -> void:
	if _panel == null or _panel.visible == open:
		return
	_panel.visible = open
	panel_visibility_changed.emit(open)


func get_levels() -> Dictionary:
	return _levels.duplicate()


func get_mushi_pitch_range() -> Vector2:
	return Vector2(_calm_pitch, _excited_pitch)


func set_mushi_pitch_range(calm: float, excited: float) -> void:
	if not is_finite(calm) or not is_finite(excited):
		return
	var new_calm := clampf(calm, PITCH_MIN, PITCH_MAX)
	var new_excited := clampf(excited, new_calm, PITCH_MAX)
	if is_equal_approx(new_calm, _calm_pitch) and is_equal_approx(new_excited, _excited_pitch):
		return
	_calm_pitch = new_calm
	_excited_pitch = new_excited
	_sync_sliders()
	mushi_pitch_range_changed.emit(_calm_pitch, _excited_pitch)
	_set_status("Unsaved mix · Save preset to keep it")


func set_level(bus_name: String, level: float) -> void:
	if not BUS_NAMES.has(bus_name) or not is_finite(level):
		return
	_levels[bus_name] = clampf(level, 0.0, MASTER_MAX_LEVEL if bus_name == "Master" else MAX_LEVEL)
	_apply_level(bus_name)
	_sync_sliders()
	_set_status("Unsaved mix · Save preset to keep it")


func attach_xr_menu(menu_root: Control) -> void:
	var contents := menu_root.get_node_or_null("Panel/Margin/Contents") as VBoxContainer
	if contents == null:
		return
	# The 900x550 menu needs scrolling once the live audio controls are attached.
	var scroll := ScrollContainer.new()
	scroll.name = "AudioScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contents.get_parent().add_child(scroll)
	contents.reparent(scroll)
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 4)
	contents.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Audio mix · point and drag"
	title.add_theme_font_size_override("font_size", 23)
	contents.add_child(title)
	for bus_name: String in BUS_NAMES:
		_xr_sliders[bus_name] = _add_slider(contents, bus_name, true)
	_add_pitch_controls(contents, true)
	var actions := HBoxContainer.new()
	contents.add_child(actions)
	_add_action_buttons(actions)
	var status := Label.new()
	status.text = "Levels are live · Save preset keeps them locally"
	contents.add_child(status)
	_status_labels.append(status)
	_sync_sliders()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F3:
			set_open(not is_open())
			get_viewport().set_input_as_handled()


func _build_desktop_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "AudioMixPanel"
	_panel.position = Vector2(24.0, 90.0)
	_panel.custom_minimum_size = Vector2(350.0, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var font_theme := Theme.new()
	font_theme.default_font = UI_FONT
	_panel.theme = font_theme
	add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.09, 0.96)
	style.border_color = Color(0.28, 0.56, 0.58, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var title := Label.new()
	title.text = "Audio mix"
	title.add_theme_font_size_override("font_size", 21)
	stack.add_child(title)
	var note := Label.new()
	note.text = "F3 closes · levels change while listening"
	stack.add_child(note)
	for bus_name: String in BUS_NAMES:
		_desktop_sliders[bus_name] = _add_slider(stack, bus_name, false)
	_add_pitch_controls(stack, false)
	_add_action_buttons(stack)
	var status := Label.new()
	status.text = "Loaded mix · Save preset keeps it locally"
	stack.add_child(status)
	_status_labels.append(status)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: set_open(false))
	stack.add_child(close)
	_sync_sliders()


func _add_slider(parent: BoxContainer, bus_name: String, xr: bool) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = "Overall" if bus_name == "Master" else bus_name
	label.custom_minimum_size.x = 105.0 if xr else 75.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 600.0 if bus_name == "Master" else 150.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 170.0
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 48.0
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%%" % roundi(value)
		set_level(bus_name, value / 100.0)
	)
	value_label.text = "%d%%" % roundi(float(_levels[bus_name]) * 100.0)
	return slider


func _add_pitch_controls(parent: BoxContainer, xr: bool) -> void:
	var caption := Label.new()
	caption.text = "Mushi pitch · calm to excited"
	parent.add_child(caption)
	for calm: bool in [true, false]:
		var row := HBoxContainer.new()
		parent.add_child(row)
		var label := Label.new()
		label.text = "Calm" if calm else "Excited"
		label.custom_minimum_size.x = 105.0 if xr else 75.0
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = PITCH_MIN * 100.0
		slider.max_value = PITCH_MAX * 100.0
		slider.step = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.x = 170.0
		row.add_child(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 48.0
		row.add_child(value_label)
		slider.value_changed.connect(func(value: float) -> void:
			if calm:
				set_mushi_pitch_range(minf(value / 100.0, _excited_pitch), _excited_pitch)
			else:
				set_mushi_pitch_range(_calm_pitch, maxf(value / 100.0, _calm_pitch))
		)
		(_xr_pitch_sliders if xr else _desktop_pitch_sliders)["calm" if calm else "excited"] = slider
	_sync_sliders()


func _add_action_buttons(parent: BoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var save := Button.new()
	save.text = "Save preset"
	save.pressed.connect(_save_preset)
	row.add_child(save)
	var reset := Button.new()
	reset.text = "Restore defaults"
	reset.pressed.connect(_restore_defaults)
	row.add_child(reset)


func _sync_sliders() -> void:
	for bus_name: String in BUS_NAMES:
		for sliders: Dictionary in [_desktop_sliders, _xr_sliders]:
			if sliders.has(bus_name):
				var slider := sliders[bus_name] as HSlider
				slider.set_value_no_signal(float(_levels[bus_name]) * 100.0)
				(slider.get_parent().get_child(2) as Label).text = "%d%%" % roundi(float(_levels[bus_name]) * 100.0)
	for sliders: Dictionary in [_desktop_pitch_sliders, _xr_pitch_sliders]:
		for key: String in ["calm", "excited"]:
			if sliders.has(key):
				var slider := sliders[key] as HSlider
				var pitch := _calm_pitch if key == "calm" else _excited_pitch
				slider.set_value_no_signal(pitch * 100.0)
				(slider.get_parent().get_child(2) as Label).text = "%.2fx" % pitch


func _apply_levels() -> void:
	for bus_name: String in BUS_NAMES:
		_apply_level(bus_name)


func _apply_level(bus_name: String) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(_levels[bus_name]), 0.00001)))
		AudioServer.set_bus_mute(index, float(_levels[bus_name]) <= 0.0)


func _load_preset() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	for bus_name: String in BUS_NAMES:
		var saved: Variant = (parsed as Dictionary).get(bus_name)
		if (saved is float or saved is int) and is_finite(float(saved)):
			_levels[bus_name] = clampf(float(saved), 0.0, MASTER_MAX_LEVEL if bus_name == "Master" else MAX_LEVEL)
	var saved_calm: Variant = (parsed as Dictionary).get(CALM_PITCH_KEY)
	if (saved_calm is float or saved_calm is int) and is_finite(float(saved_calm)):
		_calm_pitch = clampf(float(saved_calm), PITCH_MIN, PITCH_MAX)
	var saved_excited: Variant = (parsed as Dictionary).get(EXCITED_PITCH_KEY)
	if (saved_excited is float or saved_excited is int) and is_finite(float(saved_excited)):
		_excited_pitch = clampf(float(saved_excited), _calm_pitch, PITCH_MAX)
	else:
		_calm_pitch = minf(_calm_pitch, _excited_pitch)


func _save_preset() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("Could not save preset: %s" % error_string(FileAccess.get_open_error()))
		return
	var preset := _levels.duplicate()
	preset[CALM_PITCH_KEY] = _calm_pitch
	preset[EXCITED_PITCH_KEY] = _excited_pitch
	file.store_string(JSON.stringify(preset, "\t") + "\n")
	_set_status("Mix preset saved locally")


func _restore_defaults() -> void:
	for bus_name: String in BUS_NAMES:
		_levels[bus_name] = DEFAULT_LEVELS[bus_name]
	_calm_pitch = DEFAULT_CALM_PITCH
	_excited_pitch = DEFAULT_EXCITED_PITCH
	_apply_levels()
	_sync_sliders()
	mushi_pitch_range_changed.emit(_calm_pitch, _excited_pitch)
	_set_status("Defaults restored · Save preset to keep them")


func _set_status(message: String) -> void:
	for label: Label in _status_labels:
		label.text = message
