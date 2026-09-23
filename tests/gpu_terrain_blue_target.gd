extends SceneTree

## A vertical translation must preserve the blue herding trajectory. This
## catches an absolute-Y blue target even when floor clearance hides clipping.
var base: GpuFlightSimulation
var raised: GpuFlightSimulation
var base_surface: EnvironmentSurface
var raised_surface: EnvironmentSurface
var ticks := 0
var pending := false
var initial_mean_x := 0.0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	base_surface = EnvironmentSurface.create(128, 40721)
	raised_surface = EnvironmentSurface.create(128, 40721)
	base_surface.props.clear()
	raised_surface.props.clear()
	for i in raised_surface.height_samples.size():
		raised_surface.height_samples[i] += 10.0
	var test_preset := HerdPreset.builtins()[-1].copy_preset()
	test_preset.energy_dynamics = false
	test_preset.social_enabled = false
	test_preset.formation_follow_weight = 0.0
	test_preset.wander_weight = 0.0
	for offset in [0.0, 10.0]:
		var sim := GpuFlightSimulation.new()
		sim.configure_environment(base_surface if offset == 0.0 else raised_surface)
		sim.world_limit = 64.0
		sim.spawn_centers = PackedVector2Array([Vector2(3.0, 0.0)])
		sim.goal_position = Vector2(25.0, 25.0)
		sim.reset(64, 40721, test_preset)
		if not sim.gpu_error.is_empty():
			_fail(sim.gpu_error)
			return
		if offset == 0.0:
			base = sim
			for position in sim.positions:
				initial_mean_x += position.x / float(sim.positions.size())
		else: raised = sim

func _process(_delta: float) -> bool:
	if base == null or raised == null or not base.gpu_ready or not raised.gpu_ready:
		return false
	if not base.gpu_error.is_empty() or not raised.gpu_error.is_empty():
		_fail("GPU creation failed")
		return false
	if ticks < 180:
		var source := Vector2(-3.0, 0.0)
		for sim in [base, raised]:
			var ground: float = sim._environment.get_height_at(source)
			var field := LightField.new()
			field.mode = LightField.Mode.BLUE
			field.update_transform(Vector3(source.x, ground + 2.0, source.y), Vector3(1.0, -0.3, 0.0))
			sim.step(1.0 / 30.0, field)
		ticks += 1
	elif not pending:
		pending = true
		base.request_snapshot()
		raised.request_snapshot()
	elif base.snapshot_revision >= 180 and raised.snapshot_revision >= 180:
		var maximum := 0.0
		var final_mean_x := 0.0
		for i in base.positions.size():
			var a := base.positions[i]
			var b := raised.positions[i] - Vector3.UP * 10.0
			maximum = maxf(maximum, a.distance_to(b))
			final_mean_x += a.x / float(base.positions.size())
		if maximum > 0.08 or final_mean_x > initial_mean_x - 0.4 or not raised.is_finite_and_bounded():
			_fail("blue target translation mismatch=%.3f mean_x %.3f -> %.3f" % [maximum, initial_mean_x, final_mean_x])
			return false
		print("GPU_BLUE_TERRAIN_OK max_translation_error=%.4f mean_x=%.3f->%.3f" % [maximum, initial_mean_x, final_mean_x])
		base.dispose()
		raised.dispose()
		quit()
	return false

func _fail(message: String) -> void:
	push_error(message)
	if base != null: base.dispose()
	if raised != null: raised.dispose()
	quit(1)
