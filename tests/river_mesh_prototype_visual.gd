extends SceneTree

## Isolated raster-tube comparison; the live receiver shaders stay untouched.
## XDG_DATA_HOME=/tmp/mushi-mesh-probe MUSHI_MESH_CAPTURE_DIR=/tmp/mushi-mesh-probe-captures \
##   ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan \
##   --rendering-method mobile --script res://tests/river_mesh_prototype_visual.gd -- --terrain-size 128

const MASK_SHADER: Shader = preload("res://shaders/river_mesh_blocker_mask.gdshader")
var _failed := false


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The mesh probe needs a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var size := 128
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--terrain-size":
			size = int(args[index + 1])
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	lab.simulation_paused = true
	if not lab.environment_enabled or not lab.terrain_environment.terrain_reveal_active:
		push_error("Expected live opaque river receiver for comparison")
		quit(2)
		return
	for node: Node in [lab.panel, lab.hud_label, lab.help_label, lab.field_overlay,
		lab.flight_goal_volume, lab.tutorial_ui, lab.tutorial_guide]:
		if node is CanvasItem or node is Node3D:
			node.visible = false
	lab.lantern.set_mode(LightField.Mode.CLEAR)
	if lab.lantern.shutter_openness > 0.5:
		lab.lantern.toggle_shutter()
	lab.lantern.reset_adaptation(1.0)
	NightEnvironment.set_night_vision(lab.night_environment, 1.0)
	lab.terrain_environment.set_night_vision(1.0)
	var viewpoints := [
		{"name": "oblique", "eye": Vector3(15.0, 5.0, 12.0), "target": Vector3(0.0, -9.0, -2.0)},
		{"name": "grazing", "eye": Vector3(7.0, 2.8, 7.0), "target": Vector3(0.0, -5.0, -2.0)},
	]
	for view: Dictionary in viewpoints:
		_place(lab, view)
		await _capture("mesh-%d-%s-current.png" % [size, view.name])
	# The sky/foliage remain adapted, while their old river contribution is
	# switched off so the mesh alone proves its compositing behavior.
	lab.terrain_environment.terrain.material.set_shader_param("river_night_vision", 0.0)
	for material: ShaderMaterial in lab.terrain_environment._foliage_materials:
		material.set_shader_parameter("river_night_vision", 0.0)
	lab.terrain_environment._river_far_receiver.set_night_vision(0.0)
	var tube: MeshInstance3D = load("res://scripts/river_mesh_prototype.gd").new()
	lab.add_child(tube)
	for view: Dictionary in viewpoints:
		_place(lab, view)
		await _capture("mesh-%d-%s-unmasked.png" % [size, view.name])
	var mask := ShaderMaterial.new()
	mask.shader = MASK_SHADER
	mask.render_priority = -20
	var count := _attach_mask(lab.goal_shrine, mask)
	count += _attach_mask(lab.staff_tool, mask)
	print("RIVER_MESH_MASKED_MESHES count=%d" % count)
	for view: Dictionary in viewpoints:
		_place(lab, view)
		await _capture("mesh-%d-%s-masked.png" % [size, view.name])
	for eye in [-0.032, 0.032]:
		var stereo_view: Dictionary = viewpoints[1].duplicate()
		stereo_view.eye += Vector3(eye, 0.0, 0.0)
		stereo_view.target += Vector3(eye, 0.0, 0.0)
		_place(lab, stereo_view)
		await _capture("mesh-%d-grazing-%s-eye.png" % [size, "left" if eye < 0.0 else "right"])
	tube.visible = false
	mask.set_shader_parameter("debug_mask", true)
	_place(lab, viewpoints[1])
	await _capture("mesh-%d-grazing-mask-debug.png" % size)
	lab.queue_free()
	await process_frame
	print("RIVER_MESH_PROTOTYPE_%s" % ["FAIL" if _failed else "PASS"])
	quit(1 if _failed else 0)


func _attach_mask(node: Node, material: ShaderMaterial) -> int:
	var count := 0
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = material
		count += 1
	for child: Node in node.get_children():
		count += _attach_mask(child, material)
	return count


func _place(lab: Node, view: Dictionary) -> void:
	lab.player.global_position = view.eye
	lab.player.look_at(view.target, Vector3.UP)
	lab.player.camera.rotation.x = 0.0


func _capture(name: String) -> void:
	var directory := OS.get_environment("MUSHI_MESH_CAPTURE_DIR")
	if directory.is_empty():
		directory = "/tmp/mushi-mesh-probe-captures"
	DirAccess.make_dir_recursive_absolute(directory)
	for _frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := directory.path_join(name)
	if root.get_texture().get_image().save_png(path) != OK:
		_failed = true
		push_error("Capture failed: " + path)
	else:
		print("RIVER_MESH_CAPTURE " + path)
