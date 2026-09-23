extends SceneTree

var sim: GpuFlightSimulation
var surface: EnvironmentSurface
var world_sizes := [128, 256]
var case_index := 0
var ticks := 0
var pending := false

func _initialize() -> void:
	call_deferred("_start_case")

func _start_case() -> void:
	var size: int = world_sizes[case_index]
	surface = EnvironmentSurface.create(size, 40721)
	sim = GpuFlightSimulation.new()
	sim.configure_environment(surface)
	sim.world_limit = size * 0.5
	sim.spawn_centers = surface.patch_centers
	sim.mushroom_centers = surface.patch_centers
	var count := 512 if size == 128 else 1024
	sim.reset(count, 40721, HerdPreset.builtins()[-1])
	if not sim.gpu_error.is_empty():
		_fail(sim.gpu_error)
		return
	var first_positions := sim.positions.duplicate()
	var free := 0
	var per_patch := PackedInt32Array()
	per_patch.resize(surface.patch_centers.size())
	var obstacles := surface.get_obstacles()
	for i: int in sim.positions.size():
		var at := sim.positions[i]
		var xz := Vector2(at.x, at.z)
		if at.y < surface.get_height_at(xz) + sim.min_height:
			_fail("spawn below terrain flight band")
			return
		if i % 10 == 9:
			free += 1
			if sim.group_ids[i] != -1 or sim.arousals[i] <= sim.preset.sleep_threshold:
				_fail("free agent group/energy invalid")
				return
			if not surface.is_playable(xz, 5.0):
				_fail("free agent placed on rim")
				return
			for center: Vector2 in surface.patch_centers:
				if xz.distance_to(center) < maxf(5.0, sim.preset.mushroom_radius + 2.0):
					_fail("free agent overlaps patch")
					return
			for obstacle: Dictionary in obstacles:
				if xz.distance_to(obstacle.center) < float(obstacle.radius) + 0.44:
					_fail("free agent overlaps prop proxy")
					return
		else:
			if sim.group_ids[i] < 0 or sim.group_ids[i] >= per_patch.size():
				_fail("patch agent group invalid")
				return
			per_patch[sim.group_ids[i]] += 1
	var minimum := count
	var maximum := 0
	for patch_count: int in per_patch:
		minimum = mini(minimum, patch_count)
		maximum = maxi(maximum, patch_count)
	if free != count / 10 or maximum - minimum > 1 or sim.mushroom_centers.size() != (9 if size == 128 else 18):
		_fail("free/patch count mismatch")
		return
	# Explicit reset must regenerate the same stable-ID positions and source count.
	sim.reset(count, 40721, HerdPreset.builtins()[-1])
	if not sim.gpu_error.is_empty() or sim.positions != first_positions:
		_fail("seeded terrain reset drifted")
		return
	if roundi(sim._encode_params(1.0 / 30.0, LightField.new(), 1.0, 1.0).decode_float(65 * 4)) != sim.mushroom_centers.size():
		_fail("GPU source packet lost a mushroom patch")
		return
	print("TERRAIN_SPAWN_READY size=%d count=%d patches=%d free=%d" % [size, count, per_patch.size(), free])
	ticks = 0
	pending = false

func _process(_delta: float) -> bool:
	if sim == null or not sim.gpu_ready:
		return false
	if not sim.gpu_error.is_empty():
		_fail(sim.gpu_error)
		return false
	if ticks < 90:
		var field := LightField.new()
		field.mode = LightField.Mode.BLUE
		var center := surface.patch_centers[0]
		field.update_transform(Vector3(center.x, surface.get_height_at(center) + 2.0, center.y), Vector3(1.0, -0.3, 0.0))
		sim.step(1.0 / 30.0, field)
		ticks += 1
	elif not pending:
		pending = true
		sim.request_snapshot()
	elif sim.snapshot_revision >= 90:
		if not sim.is_finite_and_bounded():
			_fail("spawn fixture became nonfinite or clipped terrain")
			return false
		sim.dispose()
		case_index += 1
		if case_index == world_sizes.size():
			print("GPU_TERRAIN_SPAWN_OK")
			quit()
		else:
			call_deferred("_start_case")
	return false

func _fail(message: String) -> void:
	push_error(message)
	if sim != null: sim.dispose()
	quit(1)
