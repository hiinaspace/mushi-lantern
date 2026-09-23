extends SceneTree

var sim: GpuFlightSimulation
var surface: EnvironmentSurface
var phase := 0
var ticks := 0
var pending := false
var checked_dormant := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	surface = EnvironmentSurface.create(128, 40721)
	var rim := Vector2(39.0, 0.0)
	var rock := Vector2(-6.0, -5.0)
	surface.props.append({"kind": "rock", "position": Vector3(rock.x, surface.get_height_at(rock), rock.y), "radius": 1.6, "height": 0.45})
	sim = GpuFlightSimulation.new()
	sim.configure_environment(surface)
	sim.world_limit = 64.0
	sim.spawn_centers = PackedVector2Array([rim, rock, Vector2(-14.4, -13.2)])
	sim.mushroom_centers = PackedVector2Array([rim])
	sim.reset(256, 40721, HerdPreset.builtins()[-1])
	if not sim.gpu_error.is_empty(): _fail(sim.gpu_error)

func _process(_delta: float) -> bool:
	if sim == null or not sim.gpu_ready:
		return false
	if not sim.gpu_error.is_empty():
		_fail(sim.gpu_error)
		return false
	if phase == 0:
		if ticks < 900:
			var light := LightField.new()
			light.mode = LightField.Mode.BLUE
			light.update_transform(Vector3(39.0, surface.get_height_at(Vector2(39.0, 0.0)) + 1.5, 0.0), Vector3.LEFT)
			sim.step(1.0 / 30.0, light)
			ticks += 1
		elif not pending:
			pending = true
			sim.request_snapshot()
		elif sim.snapshot_revision >= 900:
			if not _check_terrain_state(): return false
			phase = 1
			ticks = 0
			pending = false
			sim.configure_environment(null)
			sim.world_limit = 27.0
			sim.spawn_centers = PackedVector2Array([Vector2(0.0, 0.0)])
			sim.mushroom_centers = PackedVector2Array()
			sim.reset(64, 40722, HerdPreset.builtins()[-1])
	elif phase == 1:
		if ticks < 80:
			sim.step(1.0 / 30.0, LightField.new())
			ticks += 1
		elif not pending:
			pending = true
			sim.request_snapshot()
		elif sim.snapshot_revision >= 80:
			if not sim.is_finite_and_bounded():
				_fail("flat reset state invalid")
				return false
			print("GPU_TERRAIN_LIFECYCLE_OK terrain_ticks=900 flat_ticks=80 dormant=%s" % checked_dormant)
			sim.dispose()
			quit()
	return false

func _check_terrain_state() -> bool:
	if not sim.is_finite_and_bounded():
		_fail("terrain snapshot not finite and ground-relative")
		return false
	var near_rim := 0
	var above_rock := 0
	var awake := 0
	var dormant := 0
	for i: int in sim.positions.size():
		var at := sim.positions[i]
		var xz := Vector2(at.x, at.z)
		if sim.lifecycles[i] != FlightSimulation.Lifecycle.ACTIVE: continue
		if surface.basin_margin(xz) < 0.0:
			_fail("active agent escaped basin")
			return false
		if xz.x > 35.0: near_rim += 1
		if xz.distance_to(Vector2(-6.0, -5.0)) < 1.5 and at.y > surface.get_height_at(Vector2(-6.0, -5.0)) + 0.55: above_rock += 1
		if sim.arousals[i] < sim.preset.sleep_threshold + 0.02: dormant += 1
		else: awake += 1
	if awake == 0 or dormant == 0:
		_fail("expected awake and dormant energy states")
		return false
	checked_dormant = true
	print("TERRAIN_STATE rim=%d over_rock=%d awake=%d dormant=%d" % [near_rim, above_rock, awake, dormant])
	return true

func _fail(message: String) -> void:
	push_error(message)
	if sim != null: sim.dispose()
	quit(1)
