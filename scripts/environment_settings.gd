class_name EnvironmentSettings
extends CanvasLayer

signal settings_changed(settings: Dictionary)
signal population_reset_requested(count: int)
signal panel_visibility_changed(open: bool)

const SAVE_PATH := "user://m1_quality.json"
const UI_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
const DEFAULT_SETTINGS := {
	"population": 1024,
	"vegetation": "high",
	"shadows": "high",
	"render_scale": 1.0,
	"bloom": true,
}

var _settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var _pending_population: int = 1024
var _panel: PanelContainer
var _population_choice: OptionButton
var _vegetation_choice: OptionButton
var _shadow_choice: OptionButton
var _bloom_toggle: CheckButton
var _scale_choice: OptionButton
var _apply_population: Button


func _init() -> void:
	_load_settings()
	_pending_population = int(_settings["population"])


func _ready() -> void:
	_build_panel()
	_sync_controls()
	_panel.visible = false


func get_settings() -> Dictionary:
	return _settings.duplicate()


func apply_profile(profile: String) -> void:
	if profile not in ["default", "performance"]:
		return
	var low := profile == "performance"
	var target_population := 512 if low else 1024
	_settings["vegetation"] = "low" if low else "high"
	_settings["shadows"] = "low" if low else "high"
	_settings["render_scale"] = 0.8 if low else 1.0
	_settings["population"] = target_population
	_pending_population = target_population
	_sync_controls()
	_save_settings()
	settings_changed.emit(get_settings())
	population_reset_requested.emit(target_population)


func is_open() -> bool:
	return _panel != null and _panel.visible


func sync_population(count: int, persist: bool = false) -> void:
	# Used when an external fixture or command-line option explicitly resets the run.
	if count <= 0:
		return
	_settings["population"] = count
	_pending_population = count
	if _population_choice != null:
		_select_value(_population_choice, count)
		_update_population_button()
	if persist:
		_save_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F2:
			set_open(not is_open())
			get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	if _panel == null or _panel.visible == open:
		return
	_panel.visible = open
	panel_visibility_changed.emit(open)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "QualityPanel"
	_panel.position = Vector2(24.0, 90.0)
	_panel.custom_minimum_size = Vector2(340.0, 0.0)
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
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var title := Label.new()
	title.text = "Environment quality"
	title.add_theme_font_size_override("font_size", 21)
	stack.add_child(title)
	var note := Label.new()
	note.text = "F2 closes · settings save locally"
	note.add_theme_font_size_override("font_size", 13)
	stack.add_child(note)
	_population_choice = _add_choice(stack, "Mushi", ["512", "1024"], [512, 1024])
	_population_choice.item_selected.connect(_on_population_selected)
	_apply_population = Button.new()
	_apply_population.text = "Apply mushi count & reset run"
	_apply_population.pressed.connect(_apply_population_change)
	stack.add_child(_apply_population)
	var reset_note := Label.new()
	reset_note.text = "Count changes start a new run with the current seed."
	reset_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reset_note.add_theme_font_size_override("font_size", 12)
	stack.add_child(reset_note)
	stack.add_child(HSeparator.new())
	_vegetation_choice = _add_choice(stack, "Vegetation", ["High", "Low"], ["high", "low"])
	_vegetation_choice.item_selected.connect(_on_vegetation_selected)
	_shadow_choice = _add_choice(stack, "Shadows", ["High", "Low"], ["high", "low"])
	_shadow_choice.item_selected.connect(_on_shadows_selected)
	_bloom_toggle = CheckButton.new()
	_bloom_toggle.text = "Mushi halo"
	_bloom_toggle.toggled.connect(func(enabled: bool) -> void: _change_setting("bloom", enabled))
	stack.add_child(_bloom_toggle)
	_scale_choice = _add_choice(stack, "3D render scale", ["100%", "80%"], [1.0, 0.8])
	_scale_choice.item_selected.connect(_on_scale_selected)
	var scale_note := Label.new()
	scale_note.text = "Render scale changes 3D resolution; headset runtime scale is separate."
	scale_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scale_note.add_theme_font_size_override("font_size", 12)
	stack.add_child(scale_note)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: set_open(false))
	stack.add_child(close)


func _add_choice(parent: VBoxContainer, title: String, names: Array[String], values: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 125.0
	row.add_child(label)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in names.size():
		choice.add_item(names[index])
		choice.set_item_metadata(index, values[index])
	row.add_child(choice)
	return choice


func _sync_controls() -> void:
	_select_value(_population_choice, _pending_population)
	_select_value(_vegetation_choice, _settings["vegetation"])
	_select_value(_shadow_choice, _settings["shadows"])
	_select_value(_scale_choice, _settings["render_scale"])
	_bloom_toggle.set_pressed_no_signal(bool(_settings["bloom"]))
	_update_population_button()


func _select_value(choice: OptionButton, value: Variant) -> void:
	for index: int in choice.item_count:
		if choice.get_item_metadata(index) == value:
			choice.select(index)
			return
	choice.select(-1)


func _on_population_selected(index: int) -> void:
	_pending_population = int(_population_choice.get_item_metadata(index))
	_update_population_button()


func _update_population_button() -> void:
	_apply_population.disabled = _pending_population == int(_settings["population"])


func _apply_population_change() -> void:
	if _pending_population == int(_settings["population"]):
		return
	_settings["population"] = _pending_population
	_save_settings()
	_update_population_button()
	settings_changed.emit(get_settings())
	population_reset_requested.emit(_pending_population)


func _on_vegetation_selected(index: int) -> void:
	_change_setting("vegetation", _vegetation_choice.get_item_metadata(index))


func _on_shadows_selected(index: int) -> void:
	_change_setting("shadows", _shadow_choice.get_item_metadata(index))


func _on_scale_selected(index: int) -> void:
	_change_setting("render_scale", _scale_choice.get_item_metadata(index))


func _change_setting(key: String, value: Variant) -> void:
	if _settings[key] == value:
		return
	_settings[key] = value
	_save_settings()
	settings_changed.emit(get_settings())


func _load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var saved := parsed as Dictionary
	if saved.get("bloom") is bool:
		_settings["bloom"] = saved["bloom"]
	var saved_population: Variant = saved.get("population")
	if (saved_population is int or saved_population is float) and int(saved_population) in [512, 1024] and float(saved_population) == float(int(saved_population)):
		_settings["population"] = int(saved_population)
	if saved.get("vegetation") in ["high", "low"]:
		_settings["vegetation"] = saved["vegetation"]
	if saved.get("shadows") in ["high", "low"]:
		_settings["shadows"] = saved["shadows"]
	if saved.get("render_scale") in [1.0, 0.8]:
		_settings["render_scale"] = float(saved["render_scale"])


func _save_settings() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save environment quality settings: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_settings, "\t") + "\n")
