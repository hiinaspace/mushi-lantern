extends Node3D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1100, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("10131b")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("646174")
	env.environment.ambient_light_energy = 0.42
	world.add_child(env)
	var staff := StaffTool.new()
	staff.position = Vector3(0, 1.12, 0)
	world.add_child(staff)
	staff.lantern.set_mode(LightField.Mode.ORANGE)
	staff.lantern.set_shutter(0.85)
	var key := OmniLight3D.new()
	key.position = Vector3(-0.65, 2.25, -0.8)
	key.omni_range = 5.0
	key.light_energy = 1.5
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.8, 1.8, 0.75)
	rim.light_color = Color("8caac9")
	rim.omni_range = 3.0
	rim.light_energy = 1.1
	world.add_child(rim)
	var camera := Camera3D.new()
	camera.position = Vector3(0.65, 1.55, -1.35)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0, 1.37, -0.18))
	for i in 30:
		await get_tree().process_frame
	var path := OS.get_environment("MUSHI_LANTERN_CAPTURE")
	if path.is_empty():
		path = "/tmp/mushi-lantern-audition.png"
	var image := viewport.get_texture().get_image()
	assert(image.save_png(path) == OK)
	var close_path := OS.get_environment("MUSHI_LANTERN_CLOSE_CAPTURE")
	if not close_path.is_empty():
		camera.position = Vector3(0.38, 1.55, -0.58)
		camera.look_at(Vector3(0.0, 1.38, -0.16))
		for i in 8:
			await get_tree().process_frame
		assert(viewport.get_texture().get_image().save_png(close_path) == OK)
	var draws := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var objects := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
	var primitives := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	print("LANTERN_AUDITION path=%s draws=%d objects=%d primitives=%d" % [path, draws, objects, primitives])
	get_tree().quit()
