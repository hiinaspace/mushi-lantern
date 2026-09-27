extends SceneTree

## Rendered opaque-terrain reveal check for the actual Terrain3D basin. This is a
## desktop two-eye proxy, not an OpenXR stereo or artistic acceptance test.
## XDG_DATA_HOME=/tmp/mushi-stream-check godot --xr-mode off --path . \
##   --rendering-driver vulkan --rendering-method mobile \
##   --script res://tests/underground_reveal_checks.gd -- --terrain-size 128

func _initialize() -> void:
	if not _injection_parser_checks():
		push_error("Terrain shader fragment-brace parser check failed")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Underground reveal check requires a rendered Vulkan window")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var size := 128
	var args := OS.get_cmdline_user_args()
	for index in args.size() - 1:
		if args[index] == "--terrain-size":
			size = int(args[index + 1])
	if size != 128 and size != 256:
		push_error("Expected --terrain-size 128 or 256")
		quit(2)
		return
	var route := TerrainRiverReveal._curled_path(size, Vector2.ZERO)
	for index in range(1, route.size()):
		if route[index].x <= route[index - 1].x:
			push_error("River route folds backward at sample %d" % index)
			quit(2)
			return
	print("STREAM_ROUTE_MONOTONIC size=%d samples=%d" % [size, route.size()])
	var surface := EnvironmentSurface.create(size)
	var level := Node3D.new()
	root.add_child(level)
	var environment := TerrainEnvironment.new()
	level.add_child(environment)
	environment.build(surface)
	assert(environment.terrain_reveal_active)
	# Freeze only the moving-fleck phase while measuring disparity. This leaves
	# the depth shell intact and makes the test independent of capture timing.
	environment.terrain.material.set_shader_param("river_mote_motion", 0.0)
	if environment._river_mesh_active:
		for mesh_node: Node in [environment._river_mesh] + environment._river_mesh.get_children():
			if mesh_node is MeshInstance3D:
				var river_material := (mesh_node as MeshInstance3D).material_override as ShaderMaterial
				river_material.set_shader_parameter("river_animation_rate", 0.0)
	var world := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.02, 0.03, 0.04)
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(0.4, 0.45, 0.5)
	sky.ambient_light_energy = 0.3
	world.environment = sky
	level.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	level.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 75.0
	level.add_child(camera)
	camera.current = true
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.position = Vector3(0.0, surface.get_height_at(Vector2(0.0, 7.0)) + 1.4, 7.0)
	blocker.scale = Vector3(2.0, 2.8, 1.0)
	var blocker_material := StandardMaterial3D.new()
	blocker_material.albedo_color = Color(0.8, 0.05, 0.04)
	blocker.material_override = blocker_material
	level.add_child(blocker)
	# This opaque, horizontal foliage card sits over the ground-crossing part
	# of the ray. The reveal must be composited by the foliage shader itself,
	# while the red box above remains a depth-writing foreground blocker.
	var foliage_card := MeshInstance3D.new()
	var foliage_mesh := PlaneMesh.new()
	foliage_mesh.size = Vector2(10.0, 10.0)
	foliage_card.mesh = foliage_mesh
	foliage_card.position = Vector3(0.0, surface.get_height_at(Vector2(0.0, 14.0)) + 0.18, 14.0)
	var foliage_material: ShaderMaterial = environment._foliage_material(Color(0.18, 0.32, 0.18), false)
	foliage_material.set_shader_parameter("river_night_vision", 0.0)
	foliage_card.material_override = foliage_material
	level.add_child(foliage_card)
	var passed := true
	var stereo_centroids: Array[float] = []
	var local_stereo_centroids: Array[float] = []
	for eye_offset: float in [-0.032, 0.032]:
		camera.position = Vector3(eye_offset, 8.0, 19.0)
		# Aim at the virtual rope depth so the test samples its full 3D span.
		camera.look_at(Vector3(eye_offset, -27.0, 0.0))
		environment.set_night_vision(0.0)
		environment.set_stream_visibility(0.0)
		for foliage: ShaderMaterial in environment._foliage_materials:
			foliage.set_shader_parameter("night_vision", 0.0)
		var hidden := await _capture()
		environment.set_night_vision(1.0)
		environment.set_stream_visibility(1.0)
		for foliage: ShaderMaterial in environment._foliage_materials:
			foliage.set_shader_parameter("night_vision", 0.0)
			foliage.set_shader_parameter("river_night_vision", 0.0)
		var revealed := await _capture()
		var red_top := hidden.get_height()
		var red_bottom := 0
		for y in range(0, hidden.get_height(), 3):
			for x in range(0, hidden.get_width(), 3):
				var pixel := hidden.get_pixel(x, y)
				if pixel.r > 0.25 and pixel.r > pixel.g * 2.5 and pixel.r > pixel.b * 2.5:
					red_top = mini(red_top, y)
					red_bottom = maxi(red_bottom, y)
		var changed := 0
		var gold_changed := 0
		var blocker_changed := 0
		var blocker_core_changed := 0
		var gold_weight := 0.0
		var gold_x_weight := 0.0
		var local_gold_weight := 0.0
		var local_gold_x_weight := 0.0
		var local_left := float(revealed.get_width()) * 0.5 - 180.0
		var local_right := float(revealed.get_width()) * 0.5 + 180.0
		for y in range(0, revealed.get_height(), 3):
			for x in range(0, revealed.get_width(), 3):
				var before := hidden.get_pixel(x, y)
				var after := revealed.get_pixel(x, y)
				var delta := maxi(absf(after.r - before.r) * 255.0, absf(after.g - before.g) * 255.0)
				delta = maxi(delta, absf(after.b - before.b) * 255.0)
				if delta > 8.0:
					changed += 1
					if after.r - before.r > 0.03 and after.g - before.g > 0.025 and after.r - before.r > (after.b - before.b) * 1.3:
						gold_changed += 1
						var weight := maxf(after.r - before.r, after.g - before.g)
						gold_weight += weight
						gold_x_weight += float(x) * weight
						if float(x) >= local_left and float(x) <= local_right:
							local_gold_weight += weight
							local_gold_x_weight += float(x) * weight
					if before.r > 0.25 and before.r > before.g * 2.5 and before.r > before.b * 2.5:
						blocker_changed += 1
						if y < red_bottom - (red_bottom - red_top) * 0.25:
							blocker_core_changed += 1
		var gold_centroid_x := gold_x_weight / maxf(gold_weight, 0.0001)
		var local_gold_centroid_x := local_gold_x_weight / maxf(local_gold_weight, 0.0001)
		stereo_centroids.append(gold_centroid_x)
		local_stereo_centroids.append(local_gold_centroid_x)
		print("STREAM_REVEAL size=%d eye=%+.3f changed=%d gold_changed=%d blocker_changed=%d blocker_core_changed=%d gold_centroid_x=%.2f local_gold_centroid_x=%.2f local_gold_weight=%.3f" % [size, eye_offset, changed, gold_changed, blocker_changed, blocker_core_changed, gold_centroid_x, local_gold_centroid_x, local_gold_weight])
		passed = passed and changed > 500 and gold_changed > 400 and blocker_changed == 0
		# Compare foliage-on against terrain-only at this same eye. The card
		# masks the terrain fragment, so gold pixels here prove the shader on
		# foliage carries the stream across foliage-covered ground.
		for foliage: ShaderMaterial in environment._foliage_materials:
			foliage.set_shader_parameter("river_night_vision", 1.0)
		var with_foliage := await _capture()
		var card_bounds := _foliage_card_screen_bounds(camera, foliage_card)
		var foliage_gold := 0
		for y in range(0, with_foliage.get_height(), 2):
			for x in range(0, with_foliage.get_width(), 2):
				if not card_bounds.has_point(Vector2(x, y)):
					continue
				var base_pixel := revealed.get_pixel(x, y)
				var foliage_pixel := with_foliage.get_pixel(x, y)
				if foliage_pixel.r - base_pixel.r > 0.03 and foliage_pixel.g - base_pixel.g > 0.025 and foliage_pixel.r - base_pixel.r > (foliage_pixel.b - base_pixel.b) * 1.3:
					foliage_gold += 1
		print("STREAM_FOLIAGE size=%d eye=%+.3f gold_pixels=%d" % [size, eye_offset, foliage_gold])
		passed = passed and foliage_gold > 20
		if stereo_centroids.size() == 2:
			# Broad emission-shell centroids are stable across TIME-driven mote
			# animation. A centroid shift between parallel eye views is the
			# disparity signal; raw pixel mismatch is not used as evidence.
			var disparity_pixels := absf(stereo_centroids[1] - stereo_centroids[0])
			print("STREAM_EYE_PAIR size=%d gold_centroid_disparity_pixels=%.3f" % [size, disparity_pixels])
			var local_disparity_pixels := absf(local_stereo_centroids[1] - local_stereo_centroids[0])
			print("STREAM_EYE_PAIR size=%d local_roi=x[%.0f,%.0f],y[all] local_gold_centroid_disparity_pixels=%.3f" % [size, local_left, local_right, local_disparity_pixels])
			# Left and right arms can cancel in a full-frame centroid. With
			# animation frozen, local-crest motion is the stereo witness.
			passed = passed and local_disparity_pixels > 0.2
		var capture_dir := OS.get_environment("MUSHI_STREAM_CAPTURE_DIR")
		if not capture_dir.is_empty():
			DirAccess.make_dir_recursive_absolute(capture_dir)
			var eye_name := "left" if eye_offset < 0.0 else "right"
			hidden.save_png(capture_dir.path_join("stream-%d-%s-clear.png" % [size, eye_name]))
			revealed.save_png(capture_dir.path_join("stream-%d-%s-adapted.png" % [size, eye_name]))
	var capture_dir := OS.get_environment("MUSHI_STREAM_CAPTURE_DIR")
	if not capture_dir.is_empty():
		for side: float in [-1.0, 1.0]:
			camera.position = Vector3(0.0, 6.0, 11.0)
			camera.look_at(Vector3(side * 600.0, -7.0, -4.0))
			var horizon := await _capture()
			var arm := "west" if side < 0.0 else "east"
			horizon.save_png(capture_dir.path_join("stream-%d-horizon-%s.png" % [size, arm]))
	level.queue_free()
	await process_frame
	if passed:
		print("UNDERGROUND_REVEAL_PASS size=%d" % size)
	else:
		push_error("Underground reveal or foreground occlusion failed")
	quit(0 if passed else 1)

func _capture() -> Image:
	for frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _foliage_card_screen_bounds(camera: Camera3D, card: MeshInstance3D) -> Rect2:
	var plane := card.mesh as PlaneMesh
	var half := plane.size * 0.5
	var points: Array[Vector2] = []
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		var world_point := card.global_position + Vector3(corner.x, 0.0, corner.y)
		points.append(camera.unproject_position(world_point))
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum).grow(-2.0)

func _injection_parser_checks() -> bool:
	var source := "void fragment() { /* } is not the close */ if (true) { COLOR = vec4(1.0); } // } also ignored\n}\nvoid helper() { return; }"
	var opening := source.find("void fragment() {") + "void fragment() ".length()
	var close := TerrainRiverReveal._matching_closing_brace(source, opening)
	return close == source.find("}\nvoid helper()")
