extends SceneTree

## Isolated Poly Haven understory audition. Existing live forest assets remain
## unchanged; the audition captures the current forest and a cleared patch with
## four imported CC0 candidates under the same Vulkan/mobile lighting.
##
## XDG_DATA_HOME=/tmp/mushi-groundcover MUSHI_GROUNDCOVER_CAPTURE=/tmp/groundcover \
##   ./.local/godot/bin/godot4 --xr-mode off --path . --rendering-driver vulkan \
##   --rendering-method mobile --script tests/groundcover_audition_visual.gd

const CANDIDATES := [
	{"id": "weed_plant_02", "label": "Weed Plant 02", "scale": 3.0, "offset": Vector2(-3.2, -1.8)},
	{"id": "shrub_01", "label": "Shrub 01", "scale": 1.15, "offset": Vector2(3.2, -1.8)},
	{"id": "grass_medium_02", "label": "Grass Medium 02", "scale": 2.8, "offset": Vector2(-3.2, 2.0)},
	{"id": "shrub_02", "label": "Shrub 02", "scale": 0.9, "offset": Vector2(3.2, 2.0)},
]

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Run rendered with isolated /tmp/mushi-* XDG_DATA_HOME")
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
	if lab.staff_tool != null:
		lab.staff_tool.visible = false
	lab.set_process(false)
	if lab.tutorial_ui != null and lab.tutorial_ui._world_root != null:
		lab.tutorial_ui._world_root.visible = false
	var target := Vector3(-8.0, lab.world_surface.get_height_at(Vector2(-8.0, 0.0)), 0.0)
	var eye := target + Vector3(0.0, 1.9, -5.5)
	lab.player.global_position = eye
	lab.player.look_at(target + Vector3(0.0, 0.3, 0.0), Vector3.UP)
	lab.player.camera.rotation = Vector3.ZERO
	for child in lab.player.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).visible = false
	if lab._local_avatar != null:
		lab._local_avatar.visible = false
	if lab.goal_shrine != null:
		lab.goal_shrine.visible = false
	var intro_model := lab.get_node_or_null("MikoPresentation") as Node3D
	if intro_model != null:
		intro_model.visible = false
	lab.lantern.set_shutter(0.0)
	lab.lantern.reset_adaptation(0.86)
	NightEnvironment.set_night_vision(lab.night_environment, 0.86)
	lab.terrain_environment.set_night_vision(0.86)
	lab.terrain_environment.set_stream_visibility(0.8)
	# Keep the game's night palette, with a weak neutral audition fill so plant
	# albedo and silhouette remain legible in desktop captures.
	var fill := DirectionalLight3D.new()
	fill.name = "AuditionFill"
	fill.light_energy = 1.2
	fill.light_color = Color(0.76, 0.82, 0.72)
	fill.rotation_degrees = Vector3(-48.0, -26.0, 0.0)
	fill.shadow_enabled = false
	lab.add_child(fill)
	var audition_environment := lab.night_environment as Environment
	audition_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	audition_environment.ambient_light_color = Color(0.30, 0.34, 0.30)
	audition_environment.ambient_light_energy = 0.55
	var capture_prefix := OS.get_environment("MUSHI_GROUNDCOVER_CAPTURE")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport().get_viewport_rid(), true)
	await _settle_frames()
	if not capture_prefix.is_empty():
		root.get_texture().get_image().save_png(capture_prefix + "-baseline.png")
		_print_render_stats("baseline")
	# Clear only the two existing visual dressing meshes for a like-for-like
	# view. Terrain, rocks, trees, collisions and all production scripts persist.
	var terrain: Terrain3D = lab.terrain_environment.terrain
	terrain.instancer.clear_by_mesh(2)
	terrain.instancer.clear_by_mesh(3)
	var candidate_root := Node3D.new()
	candidate_root.name = "GroundcoverAuditionOnly"
	lab.add_child(candidate_root)
	var tri_total := 0
	for candidate: Dictionary in CANDIDATES:
		var asset_id: String = candidate.id
		var scene_path := "res://assets/forest/polyhaven/groundcover_audition/%s/%s_audition.glb" % [asset_id, asset_id]
		var source := (load(scene_path) as PackedScene).instantiate()
		var plot := Node3D.new()
		plot.name = asset_id
		candidate_root.add_child(plot)
		plot.position = Vector3(target.x + candidate.offset.x, lab.world_surface.get_height_at(Vector2(target.x + candidate.offset.x, target.z + candidate.offset.y)), target.z + candidate.offset.y)
		plot.scale = Vector3.ONE
		source.scale = Vector3.ONE * float(candidate.scale)
		plot.add_child(source)
		var mesh_count := _configure_patch(source)
		var source_tris := _count_triangles(source)
		tri_total += source_tris
		var label := Label3D.new()
		label.text = "%s\n%d tris / %d meshes" % [candidate.label, source_tris, mesh_count]
		label.font_size = 48
		label.pixel_size = 0.003
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(0.84, 0.76, 1.0)
		label.position = Vector3(0.0, 1.4, 0.0)
		plot.add_child(label)
	print("GROUNDCOVER_AUDITION candidates=%d source_triangles=%d" % [CANDIDATES.size(), tri_total])
	await _settle_frames()
	if not capture_prefix.is_empty():
		root.get_texture().get_image().save_png(capture_prefix + "-candidates.png")
		_print_render_stats("candidates")
		# Close reviews isolate one source bundle at a time at the same ground
		# point, using an identical camera and night fill for each asset.
		for plot in candidate_root.get_children():
			for other_plot in candidate_root.get_children():
				other_plot.visible = other_plot == plot
			plot.position = target
			await _settle_frames()
			root.get_texture().get_image().save_png("%s-%s.png" % [capture_prefix, plot.name])
			_print_render_stats(plot.name)
	lab.queue_free()
	quit()

func _configure_patch(node: Node) -> int:
	var meshes := 0
	if node is GeometryInstance3D:
		var instance := node as GeometryInstance3D
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 28.0
		instance.visibility_range_end_margin = 3.0
		meshes += 1
	for child in node.get_children():
		meshes += _configure_patch(child)
	return meshes

func _count_triangles(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			total += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	for child in node.get_children():
		total += _count_triangles(child)
	return total

func _settle_frames() -> void:
	for frame in 28:
		await process_frame
	await RenderingServer.frame_post_draw

func _print_render_stats(view: String) -> void:
	var viewport_rid := root.get_viewport().get_viewport_rid()
	print("GROUNDCOVER_RENDER view=%s draws=%.0f primitives=%.0f viewport_gpu_ms=%.3f" % [view, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)])
