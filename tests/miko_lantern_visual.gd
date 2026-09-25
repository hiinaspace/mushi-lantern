extends SceneTree

const AVATAR_SCENE: PackedScene = preload("res://scenes/miko_avatar.tscn")
var capture_path := "/tmp/mushi-ukon-lantern.png"

func _initialize() -> void:
	call_deferred("_render")

func _render() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("080b12")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("151a28")
	env.ambient_light_energy = 0.06
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	root.add_child(world)
	var avatar := AVATAR_SCENE.instantiate() as Node3D
	root.add_child(avatar)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.35, 3.6)
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0))
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0.0, 2.3, 1.7)
	lamp.spot_range = 8.0
	lamp.spot_angle = 55.0
	lamp.light_energy = 18.0
	lamp.shadow_enabled = true
	root.add_child(lamp)
	lamp.look_at(Vector3(0.0, 1.0, 0.0))
	for i in 6:
		await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(capture_path)
	print("UKON_LANTERN_RENDER size=%s file=%s error=%d" % [image.get_size(), capture_path, err])
	quit(0 if err == OK else 1)
