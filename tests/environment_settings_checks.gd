extends SceneTree

# Run with an isolated user directory:
# XDG_DATA_HOME=/tmp/mushi-environment-settings-test godot --headless --path . --script tests/environment_settings_checks.gd

var _changes: Array[Dictionary] = []
var _resets: Array[int] = []
var _visibility: Array[bool] = []
var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use an isolated XDG_DATA_HOME under /tmp/mushi- for this test")
		quit(2)
		return
	var path := ProjectSettings.globalize_path(EnvironmentSettings.SAVE_PATH)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var settings := EnvironmentSettings.new()
	settings.settings_changed.connect(func(value: Dictionary) -> void: _changes.append(value))
	settings.population_reset_requested.connect(func(count: int) -> void: _resets.append(count))
	settings.panel_visibility_changed.connect(func(open: bool) -> void: _visibility.append(open))
	root.add_child.call_deferred(settings)
	_check.call_deferred(settings)


func _check(settings: EnvironmentSettings) -> void:
	_expect(settings.get_settings() == EnvironmentSettings.DEFAULT_SETTINGS, "fresh defaults")
	_expect(not settings.is_open(), "starts closed")
	settings.set_open(true)
	settings.set_open(false)
	_expect(_visibility == [true, false], "panel visibility signal")
	settings._population_choice.select(0)
	settings._on_population_selected(0)
	_expect(settings.get_settings()["population"] == 1024, "population selection is pending")
	_expect(_resets.is_empty() and _changes.is_empty(), "selection emits no reset or setting change")
	_expect(not settings._apply_population.disabled, "pending change enables apply")
	settings._apply_population_change()
	_expect(settings.get_settings()["population"] == 512, "explicit apply changes population")
	_expect(_resets == [512] and _changes.size() == 1, "one reset and one settings signal")
	settings._apply_population_change()
	_expect(_resets.size() == 1, "repeat apply is inert")
	settings._on_vegetation_selected(1)
	settings._on_shadows_selected(1)
	settings._on_scale_selected(1)
	settings._bloom_toggle.button_pressed = false
	var saved := settings.get_settings()
	_expect(saved["vegetation"] == "low" and saved["shadows"] == "low" and saved["render_scale"] == 0.8 and not saved["bloom"], "quality controls")
	_expect(_changes.size() == 5 and _resets.size() == 1, "render controls never reset simulation")
	var reloaded := EnvironmentSettings.new()
	_expect(reloaded.get_settings() == saved, "settings persist and reload")
	reloaded.sync_population(1024)
	_expect(reloaded.get_settings()["population"] == 1024, "external CLI or fixture count reflected")
	var persisted := EnvironmentSettings.new()
	_expect(persisted.get_settings()["population"] == 512, "external count override does not replace saved preference")
	settings.free()
	reloaded.free()
	persisted.free()
	if _failures.is_empty():
		print("ENVIRONMENT_SETTINGS_PASS")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
