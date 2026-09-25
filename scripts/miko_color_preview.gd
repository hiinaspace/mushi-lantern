extends Node3D

const AVATAR_SCENE: PackedScene = preload("res://scenes/miko_avatar.tscn")
const HUES: Array[float] = [0.0, 0.13, 0.32, 0.49, 0.65, 0.83]
const NAMES: Array[String] = ["Red", "Gold", "Green", "Cyan", "Blue", "Pink"]

var _dark: bool = false
var _close: bool = false
var _capture_path: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--dark":
			_dark = true
		elif arg == "--close":
			_close = true
		elif arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
	_build_preview()
	if not _capture_path.is_empty():
		_capture_later.call_deferred()


func _build_preview() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.008, 0.018) if _dark else Color(0.13, 0.16, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.04, 0.06, 0.08) if _dark else Color(0.45, 0.48, 0.55)
	env.ambient_light_energy = 0.06 if _dark else 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Match the grove: eye emission is visible without global image bloom.
	env.glow_enabled = false
	world.environment = env
	add_child(world)

	if not _dark:
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-25, -25, 0)
		key.light_energy = 0.45
		add_child(key)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.30, 1.05) if _close else Vector3(0, 1.35, 6.8)
	camera.fov = 20.0 if _close else 47.0
	camera.current = true
	add_child(camera)

	for index in HUES.size():
		if _close and index > 0:
			break
		var avatar := AVATAR_SCENE.instantiate() as Node3D
		avatar.name = NAMES[index]
		avatar.position = Vector3.ZERO if _close else Vector3((float(index) - 2.5) * 1.55, 0.0, 0.0)
		add_child(avatar)
		avatar.call("set_avatar_color", HUES[index], 2.7 if _dark else 1.5)
		if _close:
			continue
		var label := Label3D.new()
		label.text = NAMES[index]
		label.font_size = 44
		label.pixel_size = 0.004
		label.position = avatar.position + Vector3(0, -0.25, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.9, 0.92, 1.0)
		add_child(label)


func _capture_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_capture_path)
	print("Miko preview capture: ", _capture_path, " error=", err)
	get_tree().quit(0 if err == OK else 1)
