extends SceneTree

func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child.call_deferred(viewport)
	await process_frame
	var world := Node3D.new()
	viewport.add_child(world)
	var avatar := MushiMultiplayerAvatar.new()
	world.add_child(avatar)
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(8.0, 0.2, 8.0)
	floor_shape.shape = floor_box
	floor.position.y = -0.1
	floor.add_child(floor_shape)
	world.add_child(floor)
	avatar.configure(0.0, false)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.0, -2.5)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 1.0
	world.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.11, 0.12, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.3, 0.3, 0.3)
	world.add_child(env)
	var base := Transform3D.IDENTITY
	var view := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	for warmup in range(30):
		avatar.apply_pose(base, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 0,
			Vector3.ZERO, 0.016)
		await process_frame
	for scenario in [{"name": "idle", "velocity": Vector3.ZERO},
			{"name": "forward", "velocity": Vector3.FORWARD * 1.8},
			{"name": "strafe", "velocity": Vector3.RIGHT * 1.8}]:
		for step in range(36):
			avatar.apply_pose(base, view, Transform3D.IDENTITY, Transform3D.IDENTITY, 0,
				scenario.velocity, 0.016)
			await process_frame
			if step in [10, 30]:
				var path := "/tmp/mushi-avatar-%s-%d.png" % [scenario.name, step]
				assert(viewport.get_texture().get_image().save_png(path) == OK)
				print("CAPTURE ", path)
	quit()
