extends SceneTree

# XDG_DATA_HOME=/tmp/mushi-fern-capture MUSHI_FERN_CAPTURE=/tmp/mushi-fern \
#   ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan \
#   --rendering-method mobile --script tests/fern_groundcover_audition_visual.gd

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use a rendered window with isolated /tmp/mushi-* XDG_DATA_HOME")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	lab.set_process_unhandled_input(false)
	lab.player.set_process_unhandled_input(false)
	lab.player.set_physics_process(false)
	lab.simulation_paused = true
	if lab.tutorial_ui != null:
		lab.tutorial_ui.visible = false
	if lab.tutorial_guide != null:
		lab.tutorial_guide.visible = false
	if lab.friend_menu != null:
		lab.friend_menu.set_open(false)
	var tutorial_view := OS.get_environment("MUSHI_FERN_VIEW") == "tutorial"
	var night_vision := 1.0 if tutorial_view else 0.80
	lab.lantern.set_shutter(0.0)
	lab.lantern.reset_adaptation(night_vision)
	NightEnvironment.set_night_vision(lab.night_environment, night_vision)
	lab.terrain_environment.set_night_vision(night_vision)
	lab.terrain_environment.set_stream_visibility(1.0 if tutorial_view else 0.75)
	var cover: FernGroundcoverAudition = lab.terrain_environment._fern_groundcover
	cover.visible = false
	cover.set_night_vision(night_vision)
	print("FERN_AUDITION cells=%d instances=%d triangles_total=%d" % [cover.cell_total, cover.instance_total, cover.instance_total * 784])
	if cover.instance_total < 100 or cover.instance_total > 1300:
		push_error("Fern scatter count outside bounded prototype range")
		quit(2)
		return
	var target := Vector3.ZERO
	var grass_index := 0
	var best_distance := INF
	for prop: Dictionary in lab.world_surface.get_props():
		if prop.kind != "grass":
			continue
		grass_index += 1
		if grass_index % 30 != 0:
			continue
		var distance := Vector2(prop.position.x, prop.position.z).distance_to(Vector2(25.0, 8.0))
		if distance < best_distance:
			best_distance = distance
			target = prop.position
	if target == Vector3.ZERO:
		target = Vector3(25.0, lab.world_surface.get_height_at(Vector2(25.0, 8.0)), 8.0)
	if not tutorial_view:
		var eye := target + Vector3(-1.5, 2.1, -1.8)
		lab.player.global_position = eye
		lab.player.look_at(target + Vector3(0.0, 0.08, 0.0), Vector3.UP)
		lab.player.camera.rotation = Vector3.ZERO
	if lab.staff_tool != null:
		lab.staff_tool.visible = false
	lab.set_process(false)
	if lab.tutorial_ui != null and lab.tutorial_ui._world_root != null:
		lab.tutorial_ui._world_root.visible = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var prefix := OS.get_environment("MUSHI_FERN_CAPTURE")
	for enabled in [false, true]:
		cover.visible = enabled
		for frame in 22:
			await process_frame
		await RenderingServer.frame_post_draw
		var name := "fern" if enabled else "baseline"
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		print("FERN_AUDITION view=%s draws=%.0f primitives=%.0f viewport_gpu_ms=%.3f" % [name, draws, primitives, gpu_ms])
		if not prefix.is_empty():
			root.get_texture().get_image().save_png("%s-%s.png" % [prefix, name])
	lab.queue_free()
	quit()
