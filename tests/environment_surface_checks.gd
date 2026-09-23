extends SceneTree

const TEST_SEED := 40721

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 20, 20)
	root.add_child(camera)
	camera.current = true
	for world_size in [128, 256]:
		var a := EnvironmentSurface.create(world_size, TEST_SEED)
		var b := EnvironmentSurface.create(world_size, TEST_SEED)
		_assert(a.sample_count == world_size + 1, "sample dimensions")
		_assert(a.height_samples == b.height_samples, "seeded height repeat")
		_assert(a.get_obstacles() == b.get_obstacles(), "seeded prop repeat")
		_assert(a.patch_centers == b.patch_centers, "seeded patch repeat")
		var obstacles := a.get_obstacles()
		_assert(a.patch_centers.size() == (9 if world_size == 128 else 18), "dispersed patch count")
		_assert(a.is_playable(Vector2.ZERO), "origin playable")
		_assert(not a.is_playable(Vector2(world_size * 0.47, 0)), "rim excludes player")
		_assert(a.get_height_image().get_width() == world_size + 1, "GPU edge sample")
		for center: Vector2 in a.patch_centers:
			_assert(a.is_playable(center, 5.0), "patch inside walkable basin")
			_assert(a._terrain_grade(center) < 0.42, "patch off cliff face")
		_assert(a.get_height_at(Vector2(20, 0)) - a.get_height_at(Vector2(10, 0)) > 4.5, "east cliff has meaningful drop")
		var bypass: Array[Vector2] = [Vector2(10, 0), Vector2(10, 22), Vector2(37, 22), Vector2(37, 0), Vector2(26, 0), Vector2(20, 0)]
		for segment in bypass.size() - 1:
			for sample in 21:
				var point := bypass[segment].lerp(bypass[segment + 1], float(sample) / 20.0)
				_assert(a._terrain_grade(point) < 0.86, "east cliff bypass stays below player slope limit")
				_assert(a.is_playable(point, 1.0), "east cliff bypass inside basin")
				for obstacle: Dictionary in obstacles:
					_assert(point.distance_to(obstacle.center) - float(obstacle.radius) > 1.0, "bypass free of trunk/rock proxy")
		var world := TerrainEnvironment.new()
		root.add_child(world)
		world.build(a)
		await physics_frame
		_assert(world.terrain.data.get_region_count() == (world_size / 64) * (world_size / 64), "Terrain3D region count")
		var excluded: Array[RID] = []
		for child in world.get_node("CoarsePropCollision").get_children():
			excluded.append((child as StaticBody3D).get_rid())
		var tested := 0
		var maximum_query_error := 0.0
		var maximum_ray_error := 0.0
		# Grid crosses region seams and the original gathering pockets. Its rim
		# samples remain within actual imported Terrain3D regions.
		var scale := float(world_size) / 128.0
		for xi in [-56, -33, -14, -1, 0, 1, 15, 32, 40, 55]:
			for zi in [-55, -32, -13, -1, 0, 1, 16, 31, 42, 56]:
				var xz := Vector2(float(xi) * scale, float(zi) * scale)
				var expected := a.get_height_at(xz)
				var terrain_height := world.terrain.data.get_height(Vector3(xz.x, 0, xz.y))
				_assert(is_finite(terrain_height), "finite Terrain3D height")
				maximum_query_error = maxf(maximum_query_error, absf(expected - terrain_height))
				var ray := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 30, xz.y), Vector3(xz.x, -10, xz.y))
				ray.exclude = excluded
				var hit := root.get_world_3d().direct_space_state.intersect_ray(ray)
				_assert(not hit.is_empty(), "baked ground ray coverage")
				maximum_ray_error = maxf(maximum_ray_error, absf((hit.position as Vector3).y - terrain_height))
				tested += 1
		_assert(maximum_query_error < 0.16, "CPU and Terrain3D sample agreement")
		_assert(maximum_ray_error < 0.16, "static ground and Terrain3D agreement")
		print("ENVIRONMENT_SURFACE_PASS size=", world_size, " probes=", tested,
			" regions=", world.terrain.data.get_region_count(),
			" max_query_m=", maximum_query_error, " max_ray_m=", maximum_ray_error,
			" ground_triangles=", (world.get_node("BakedBasinCollision/CollisionShape3D") as CollisionShape3D).shape.get_faces().size() / 3)
		root.remove_child(world)
		world.free()
	quit()

func _assert(condition: bool, description: String) -> void:
	if not condition:
		push_error("ENVIRONMENT_SURFACE_FAIL " + description)
		quit(1)
		assert(false, description)
