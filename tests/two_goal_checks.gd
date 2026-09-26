extends SceneTree

var gpu: GpuFlightSimulation
var frames := 0
var requested := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var cpu := FlightSimulation.new()
	configure(cpu)
	cpu.reset(2, 40721, HerdPreset.builtins()[-1])
	for i in 2:
		var goal := cpu.goal_position if i == 0 else cpu.second_goal_position
		cpu.positions[i] = Vector3(goal.x, 1.0, goal.y)
		cpu._update_goal(i, cpu.positions[i], 0.5)
		cpu._update_goal(i, cpu.positions[i], 0.5)
	assert(cpu.score == 2 and cpu.goal_scores == PackedInt32Array([1, 1]))
	assert(cpu.committed_goals == PackedInt32Array([1, 2]))
	cpu.reset(2, 40721, HerdPreset.builtins()[-1])
	assert(cpu.score == 0 and cpu.goal_scores == PackedInt32Array([0, 0]))
	print("TWO_GOAL_CPU_OK")
	gpu = GpuFlightSimulation.new()
	configure(gpu)
	gpu.reset(64, 40721, HerdPreset.builtins()[-1])
	gpu.snapshot_interval = 999.0

func configure(sim: FlightSimulation) -> void:
	sim.goal_mode_two = true
	sim.goal_position = Vector2(-10.0, 0.0)
	sim.second_goal_position = Vector2(10.0, 0.0)
	sim.spawn_centers = PackedVector2Array([sim.goal_position, sim.second_goal_position])
	sim.goal_radius = 4.0

func _process(_delta: float) -> bool:
	if gpu == null:
		return false
	frames += 1
	if frames % 60 == 0:
		print("TWO_GOAL_PROGRESS frames=%d ready=%s rev=%d snapshot=%d score=%d" % [frames, gpu.gpu_ready, gpu.state_revision, gpu.snapshot_revision, gpu.score])
	if not gpu.gpu_error.is_empty():
		push_error(gpu.gpu_error)
		quit(1)
		return false
	if gpu.gpu_ready:
		if gpu.state_revision < 225:
			gpu.step(1.0 / 30.0, LightField.new())
		elif not requested:
			requested = true
			gpu.request_snapshot()
		if gpu.snapshot_revision == 225:
			assert(gpu.score == 64 and gpu.goal_scores == PackedInt32Array([32, 32]))
			for i in 64:
				assert(gpu.committed_goals[i] == i % 2 + 1)
				assert(gpu.lifecycles[i] == FlightSimulation.Lifecycle.RELEASED)
				var goal := gpu.goal_position if i % 2 == 0 else gpu.second_goal_position
				assert(Vector2(gpu.positions[i].x, gpu.positions[i].z).distance_to(goal) < 0.05)
				assert(gpu.positions[i].y < -21.5)
			print("TWO_GOAL_GPU_OK score=%d split=%s" % [gpu.score, gpu.goal_scores])
			var surface := EnvironmentSurface.create(128, 40721)
			gpu.configure_environment(surface)
			gpu.world_limit = 64.0
			gpu.spawn_centers = PackedVector2Array([Vector2(-2.0, 0.0), Vector2(2.0, 0.0)])
			gpu.mushroom_centers = gpu.spawn_centers
			gpu.reset(512, 40721, HerdPreset.builtins()[-1])
			for i in 512:
				assert(gpu.group_ids[i] >= 0)
				var xz := Vector2(gpu.positions[i].x, gpu.positions[i].z)
				assert(xz.distance_to(gpu.spawn_centers[gpu.group_ids[i]]) <= 1.56)
			print("TWO_GOAL_CENTRAL_SPAWN_OK count=512 free=0")
			assert(gpu.score == 0 and gpu.goal_scores == PackedInt32Array([0, 0]))
			gpu.dispose()
			quit()
	if frames > 600:
		push_error("Two-goal test timed out")
		gpu.dispose()
		quit(1)
	return false
