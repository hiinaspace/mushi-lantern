extends SceneTree

# Deterministic local force checks. Long-run geometry remains a visual judgement.
func _initialize() -> void:
	var preset := HerdPreset.new()
	preset.energy_dynamics = false
	preset.population_variation = 0.0
	preset.arousal_scatter_strength = 0.0
	var sim := FlightSimulation.new()
	sim.reset(5, 40721, preset)
	sim.positions = PackedVector3Array([
		Vector3(0, 1, 0), Vector3(-2, 1, 0), Vector3(-3.3, 1, 0),
		Vector3(12, 1, 0), Vector3(14, 1, 0)
	])
	sim.velocities = PackedVector3Array([
		Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT
	])
	sim.trait_types = PackedInt32Array([0, 1, 2, 0, 1])
	sim._build_neighbor_lists(sim.positions, sim.lifecycles)
	var plain_middle := sim._social_force(1, sim.positions, sim.velocities, sim.lifecycles)
	sim.preset.formation_follow_weight = 1.1
	sim.formation_predecessors = PackedInt32Array([-1, 0, 1, -1, 3])
	sim.formation_successors = PackedInt32Array([1, 2, -1, 4, -1])
	var following_middle := sim._social_force(1, sim.positions, sim.velocities, sim.lifecycles)
	if following_middle.x <= plain_middle.x + 0.1:
		push_error("Middle glyph did not steer toward head's trailing position")
		quit(1)
		return

	# All four neighbors are on one side. Crowd pressure must push the center
	# away, beyond the ordinary separation force.
	sim.positions = PackedVector3Array([
		Vector3(0, 1, 0), Vector3(0.5, 1, 0), Vector3(0.8, 1, 0),
		Vector3(1.1, 1, 0), Vector3(1.4, 1, 0)
	])
	sim.velocities.fill(Vector3.ZERO)
	sim.preset.formation_follow_weight = 0.0
	sim.formation_predecessors.fill(-1)
	sim.formation_successors.fill(-1)
	sim._build_neighbor_lists(sim.positions, sim.lifecycles)
	var plain_center := sim._social_force(0, sim.positions, sim.velocities, sim.lifecycles)
	sim.preset.cluster_target_neighbors = 2
	sim.preset.cluster_pressure_weight = 1.0
	var pressured_center := sim._social_force(0, sim.positions, sim.velocities, sim.lifecycles)
	if pressured_center.x >= plain_center.x - 0.1:
		push_error("Crowd pressure did not push away from crowded side")
		quit(1)
		return
	print("FORMATION_FORCE_OK follow_delta=%.3f pressure_delta=%.3f" % [following_middle.x - plain_middle.x, pressured_center.x - plain_center.x])
	quit()
