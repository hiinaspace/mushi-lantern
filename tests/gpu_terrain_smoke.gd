extends SceneTree

var sim: GpuFlightSimulation
var surface: EnvironmentSurface
var frame := 0
var sample_count := 0
var terrain_ms := 0.0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var world_size := 256 if OS.get_cmdline_user_args().has("256") else 128
	surface = EnvironmentSurface.create(world_size, 40721)
	# A shared placement directly over a spawn pocket exercises static proxy
	# correction, not merely upload of distant trees.
	var spawn := Vector2(-14.4, -13.2)
	surface.props.append({"kind": "tree", "position": Vector3(spawn.x, surface.get_height_at(spawn), spawn.y), "radius": 2.3, "height": 3.2})
	sim = GpuFlightSimulation.new()
	sim.configure_environment(surface)
	sim.world_limit = surface.size_m * 0.5
	sim.mushroom_centers = PackedVector2Array([Vector2(-14.4, -13.2)])
	sim.reset(1024, 40721, HerdPreset.builtins()[-1])
	if not sim.gpu_error.is_empty():
		_fail(sim.gpu_error)
		return
	for at in sim.positions:
		var ground := surface.get_height_at(Vector2(at.x, at.z))
		if at.y < ground + sim.min_height or at.y > ground + sim.max_height:
			_fail("initial spawn not ground-relative")
			return
	sim.gpu_timing_sample.connect(func(ms: float) -> void:
		terrain_ms += ms
		sample_count += 1)
	sim.profile_gpu = true

func _process(_delta: float) -> bool:
	frame += 1
	if sim == null:
		return false
	if not sim.gpu_error.is_empty():
		_fail(sim.gpu_error)
		return false
	if sim.gpu_ready and frame <= 130:
		var light := LightField.new()
		light.update_transform(Vector3(0, surface.get_height_at(Vector2.ZERO) + 2.0, 0), Vector3(1, -0.3, 0))
		light.mode = LightField.Mode.ORANGE
		sim.step(1.0 / 30.0, light)
	if frame == 145:
		sim.request_snapshot()
	if frame == 165:
		if sim.snapshot_revision < 0 or not sim.is_finite_and_bounded():
			_fail("terrain GPU snapshot invalid, revision=%d" % sim.snapshot_revision)
			return false
		for i: int in sim.positions.size():
			if sim.lifecycles[i] == FlightSimulation.Lifecycle.ACTIVE and Vector2(sim.positions[i].x, sim.positions[i].z).distance_to(Vector2(-14.4, -13.2)) < 2.29 and sim.positions[i].y < surface.get_height_at(Vector2(-14.4, -13.2)) + 3.2:
				_fail("agent %d remains inside large shared trunk proxy" % i)
				return false
		print("GPU_TERRAIN_OK obstacles=%d count=%d revision=%d score=%d compute_mean_ms=%.3f samples=%d" % [surface.get_obstacles().size(), sim.positions.size(), sim.snapshot_revision, sim.score, terrain_ms / max(1, sample_count), sample_count])
		sim.dispose()
	if frame >= 170:
		quit()
	return false

func _fail(message: String) -> void:
	push_error(message)
	if sim != null:
		sim.dispose()
	quit(1)
