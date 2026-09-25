extends SceneTree

## Standalone desktop render of the fruit ring at both adaptation endpoints.
## Run with: MUSHROOM_CAPTURE_DIR=/tmp/mushroom ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan --rendering-method mobile --script tests/mushroom_patch_visual.gd

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requires a rendered window")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var failures := 0
	var capture_dir := OS.get_environment("MUSHROOM_CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = "/tmp/mushi-mushroom-preview"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var stage := Node3D.new()
	stage.name = "MushroomPatchPreview"
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.002, 0.003, 0.006)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.08, 0.10, 0.16)
	world.environment.ambient_light_energy = 0.12
	stage.add_child(world)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(9.0, 9.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.018, 0.024, 0.018)
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	ground.position.y = -0.018
	stage.add_child(ground)
	var light := DirectionalLight3D.new()
	light.light_energy = 0.65
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.62, 5.2)
	camera.fov = 48.0
	stage.add_child(camera)
	camera.current = true
	camera.look_at(Vector3(0.0, 0.24, 2.35), Vector3.UP)
	var patch := MushroomPatch.new()
	patch.position = Vector3.ZERO
	patch.set_radius(3.4)
	stage.add_child(patch)
	patch.show_boundary(false)
	var ring_mesh := patch.get_node("Mushrooms") as MultiMeshInstance3D
	for index in [0, 5, 10, 15, 20]:
		var instance_transform := ring_mesh.multimesh.get_instance_transform(index)
		print("MUSHROOM_INSTANCE %d up=%s position=%s" % [index, str(instance_transform.basis.y.normalized()), str(instance_transform.origin)])
	var unadapted_image: Image
	for state: Dictionary in [{"label": "night-vision-off", "value": 0.0}, {"label": "night-vision-on", "value": 1.0}]:
		patch.set_night_vision(float(state.value))
		for _frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/%s.png" % [capture_dir, state.label]
		if image.save_png(path) != OK:
			push_error("Could not save " + path)
			quit(1)
			return
		print("MUSHROOM_CAPTURE ", path)
		if float(state.value) == 0.0:
			unadapted_image = image.duplicate()
		else:
			var changed_pixels := _count_changed_pixels(unadapted_image, image, 0.025)
			print("MUSHROOM_NV_COMPARISON changed_pixels=", changed_pixels)
			if changed_pixels < 100:
				push_error("Maximum night vision did not produce a perceptible edge-emission change")
				failures += 1
	# The production adaptation cue must read on unlit pale fruit, rather than
	# borrowing visibility from the preview's directional key light.
	light.light_energy = 0.0
	world.environment.ambient_light_energy = 0.0
	camera.position = Vector3(0.0, 1.62, 5.2)
	camera.fov = 48.0
	camera.look_at(Vector3(0.0, 0.24, 2.35), Vector3.UP)
	var dark_unadapted: Image
	for state: Dictionary in [{"label": "dark-walk-nv0", "value": 0.0}, {"label": "dark-walk-nv1", "value": 1.0}]:
		patch.set_night_vision(float(state.value))
		for _frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/%s.png" % [capture_dir, state.label]
		if image.save_png(path) != OK:
			push_error("Could not save " + path)
			quit(1)
			return
		print("MUSHROOM_CAPTURE ", path)
		if float(state.value) == 0.0:
			dark_unadapted = image.duplicate()
		else:
			var dark_changed_pixels := _count_changed_pixels(dark_unadapted, image, 0.025)
			print("MUSHROOM_DARK_WALK_COMPARISON changed_pixels=", dark_changed_pixels)
			if dark_changed_pixels < 80:
				push_error("Maximum night vision edge cue is not visible in the dark walking-height view")
				failures += 1
	patch.set_night_vision(1.0)
	var fruit_node := patch.get_node("Mushrooms") as MultiMeshInstance3D
	fruit_node.visible = false
	var detail := MeshInstance3D.new()
	detail.mesh = fruit_node.multimesh.mesh
	detail.material_override = fruit_node.material_override
	detail.scale = Vector3.ONE * 0.091
	stage.add_child(detail)
	light.light_energy = 0.65
	world.environment.ambient_light_energy = 0.12
	camera.position = Vector3(0.0, 0.12, 0.38)
	camera.fov = 40.0
	camera.look_at(Vector3(0.0, 0.075, 0.0), Vector3.UP)
	for _frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var close_path := "%s/fruit-detail.png" % capture_dir
	if root.get_texture().get_image().save_png(close_path) != OK:
		push_error("Could not save " + close_path)
		quit(1)
		return
	print("MUSHROOM_CAPTURE ", close_path)
	quit(1 if failures > 0 else 0)

func _count_changed_pixels(before: Image, after: Image, threshold: float) -> int:
	var changed := 0
	for y in before.get_height():
		for x in before.get_width():
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > threshold:
				changed += 1
	return changed
