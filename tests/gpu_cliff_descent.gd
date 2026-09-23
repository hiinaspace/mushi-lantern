extends SceneTree

## A flyer crossing a sharp 8 m drop must descend under the normal velocity
## limit. The old local-ceiling clamp teleported it down in one GPU tick.
const DT := 1.0 / 30.0
const TICKS := 600

var surface: EnvironmentSurface
var sim: GpuFlightSimulation
var field: LightField
var ticks := 0
var pending := false
var previous_position := Vector3.ZERO
var seen_over_band := false
var seen_lowland := false
var seen_settle := false
var biggest_drop := 0.0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	surface = EnvironmentSurface.create(128, 40721)
	surface.props.clear()
	for z in surface.sample_count:
		for x in surface.sample_count:
			var world_x := float(x) - surface.size_m * 0.5
			surface.height_samples[z * surface.sample_count + x] = 8.0 * (1.0 - smoothstep(-0.5, 0.5, world_x))
	sim = GpuFlightSimulation.new()
	sim.configure_environment(surface)
	sim.world_limit = 64.0
	sim.spawn_centers = PackedVector2Array([Vector2(-3.0, 0.0)])
	sim.mushroom_centers = PackedVector2Array()
	sim.goal_position = Vector2(25.0, 25.0)
	sim.snapshot_interval = 1000.0
	var preset := HerdPreset.builtins()[-1].copy_preset()
	preset.energy_dynamics = false
	preset.social_enabled = false
	preset.formation_follow_weight = 0.0
	preset.wander_weight = 0.0
	preset.max_speed = 4.0
	preset.max_acceleration = 8.0
	preset.light_weight = 8.0
	preset.flight_max_height = 4.5
	sim.reset(1, 40721, preset)
	if not sim.gpu_error.is_empty():
		_fail(sim.gpu_error)
		return
	previous_position = sim.positions[0]
	field = LightField.new()
	field.mode = LightField.Mode.BLUE
	field.range_m = 20.0
	field.half_angle_degrees = 55.0
	field.update_transform(Vector3(7.0, 8.6, 0.0), Vector3(-1.0, 0.1, 0.0))

func _process(_delta: float) -> bool:
	if sim == null or not sim.gpu_ready:
		return false
	if not sim.gpu_error.is_empty():
		_fail(sim.gpu_error)
		return false
	if pending:
		if sim.snapshot_revision < ticks:
			return false
		pending = false
		var at := sim.positions[0]
		var ground := surface.get_height_at(Vector2(at.x, at.z))
		var drop := previous_position.y - at.y
		biggest_drop = maxf(biggest_drop, drop)
		if drop > preset_step_limit() or at.y < ground + sim.min_height - 0.02 or not sim.is_finite_and_bounded():
			_fail("cliff discontinuity at tick %d: x=%.2f y=%.2f drop=%.3f ground=%.2f" % [ticks, at.x, at.y, drop, ground])
			return false
		if at.x > 1.0 and at.y > ground + sim.max_height + 0.5:
			seen_over_band = true
		if at.x > 3.0:
			seen_lowland = true
			if at.y < ground + sim.max_height + 0.35:
				seen_settle = true
		previous_position = at
	if not pending and ticks < TICKS:
		sim.step(DT, field)
		ticks += 1
		sim.request_snapshot()
		pending = true
	elif not pending:
		if not seen_over_band or not seen_lowland or not seen_settle:
			_fail("cliff route incomplete: over=%s lowland=%s settle=%s x=%.2f" % [seen_over_band, seen_lowland, seen_settle, previous_position.x])
			return false
		print("GPU_CLIFF_DESCENT_OK ticks=%d max_drop=%.3f over_band=%s settled=%s" % [ticks, biggest_drop, seen_over_band, seen_settle])
		sim.dispose()
		quit()
	return false

func preset_step_limit() -> float:
	return sim.preset.max_speed * 1.5 * DT + 0.035

func _fail(message: String) -> void:
	push_error(message)
	if sim != null: sim.dispose()
	quit(1)
