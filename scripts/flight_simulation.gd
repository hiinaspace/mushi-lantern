class_name FlightSimulation
extends RefCounted

enum Lifecycle { ACTIVE, COMMITTED, ASCENDING, RELEASED }

const BODY_RADIUS := 0.10
const WORLD_LIMIT := 27.0
const DEFAULT_SPAWN_CENTERS := [Vector2(-14.4, -13.2), Vector2(14.6, -12.0), Vector2(15.4, 13.6)]

var seed_value: int = 40721
var preset: HerdPreset = HerdPreset.new()
var positions := PackedVector3Array()
var previous_positions := PackedVector3Array()
var velocities := PackedVector3Array()
var accelerations := PackedVector3Array()
var arousals := PackedFloat32Array()
var exposures := PackedFloat32Array()
var mushroom_exposures := PackedFloat32Array()
var lifecycles := PackedInt32Array()
var lifecycle_times := PackedFloat32Array()
var wander_phases := PackedFloat32Array()
var group_ids := PackedInt32Array()
var trait_types := PackedInt32Array()
var trait_sizes := PackedFloat32Array()
var trait_tints := PackedColorArray()
var speed_factors := PackedFloat32Array()
var cohesion_factors := PackedFloat32Array()
var alignment_factors := PackedFloat32Array()
var lantern_response_factors := PackedFloat32Array()
var mushroom_response_factors := PackedFloat32Array()
var neighbor_visits: int = 0
var goal_position := Vector2.ZERO
var goal_radius: float = 2.65
var goal_dwell_seconds: float = 0.45
## Tutorial gate: progress is accepted only after the scripted reveal completes.
var goal_accepting: bool = true
var obstacle_centers := PackedVector2Array()
var obstacle_radii := PackedFloat32Array()
var mushroom_centers := PackedVector2Array()
var spawn_centers := PackedVector2Array(DEFAULT_SPAWN_CENTERS)
var world_limit: float = WORLD_LIMIT
var min_height: float = 0.25
var max_height: float = 2.8
var score: int = 0
var committed_this_step := PackedInt32Array()
var _goal_dwells := PackedFloat32Array()
var _energy_phases := PackedFloat32Array()
var _vertical_phases := PackedFloat32Array()
var _energy_time: float = 0.0
var _last_field_mode: int = -1
var _neutral_offsets := PackedFloat32Array()
var _wake_waits := PackedFloat32Array()
var _wake_remaining := PackedFloat32Array()
var _wake_cycles := PackedInt32Array()
var _neighbor_lists: Array[PackedInt32Array] = []
var formation_predecessors := PackedInt32Array()
var formation_successors := PackedInt32Array()
var _formation_step: int = 0


func reset(agent_count: int, new_seed: int, new_preset: HerdPreset) -> void:
	seed_value = new_seed
	preset = new_preset.copy_preset()
	_sync_flight_height()
	positions = PackedVector3Array()
	previous_positions = PackedVector3Array()
	velocities = PackedVector3Array()
	accelerations = PackedVector3Array()
	arousals = PackedFloat32Array()
	exposures = PackedFloat32Array()
	mushroom_exposures = PackedFloat32Array()
	lifecycles = PackedInt32Array()
	lifecycle_times = PackedFloat32Array()
	wander_phases = PackedFloat32Array()
	group_ids = PackedInt32Array()
	trait_types = PackedInt32Array()
	trait_sizes = PackedFloat32Array()
	trait_tints = PackedColorArray()
	speed_factors = PackedFloat32Array()
	cohesion_factors = PackedFloat32Array()
	alignment_factors = PackedFloat32Array()
	lantern_response_factors = PackedFloat32Array()
	mushroom_response_factors = PackedFloat32Array()
	_neutral_offsets = PackedFloat32Array()
	_wake_waits = PackedFloat32Array()
	_wake_remaining = PackedFloat32Array()
	_wake_cycles = PackedInt32Array()
	_neighbor_lists = []
	formation_predecessors = PackedInt32Array()
	formation_successors = PackedInt32Array()
	_formation_step = 0
	neighbor_visits = 0
	_goal_dwells = PackedFloat32Array()
	_energy_phases = PackedFloat32Array()
	_vertical_phases = PackedFloat32Array()
	_energy_time = 0.0
	_last_field_mode = -1
	score = 0
	committed_this_step = PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	var energy_rng := RandomNumberGenerator.new()
	energy_rng.seed = new_seed ^ 0x5f3759df
	var trait_rng := RandomNumberGenerator.new()
	trait_rng.seed = new_seed ^ 0x2c1b3c6d
	var centers := spawn_centers
	if centers.is_empty():
		centers = PackedVector2Array(DEFAULT_SPAWN_CENTERS)
	for index: int in agent_count:
		# Round-robin assignment keeps each authored patch populated at 24 and 64.
		var group := 0 if agent_count == 3 else index % centers.size()
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.35, 1.55)
		var center := centers[group]
		var position := Vector3(center.x + cos(angle) * radius, rng.randf_range(0.35, 1.25), center.y + sin(angle) * radius)
		var velocity := Vector3(cos(angle), rng.randf_range(-0.18, 0.18), sin(angle)) * rng.randf_range(0.25, 0.7)
		var energy_phase := energy_rng.randf_range(0.0, TAU)
		var mushroom_exposure := _mushroom_exposure_at(position) if preset.energy_dynamics else 0.0
		var initial_energy := preset.baseline_arousal
		if preset.energy_dynamics:
			initial_energy = lerpf(_individual_neutral_target(energy_phase), preset.blue_energy_target, smoothstep(0.0, 0.7, mushroom_exposure))
		positions.append(position)
		previous_positions.append(position)
		velocities.append(velocity)
		accelerations.append(Vector3.ZERO)
		arousals.append(clampf(initial_energy, 0.0, 1.0))
		exposures.append(0.0)
		mushroom_exposures.append(mushroom_exposure)
		lifecycles.append(Lifecycle.ACTIVE)
		lifecycle_times.append(0.0)
		wander_phases.append(rng.randf_range(0.0, TAU))
		group_ids.append(group)
		_goal_dwells.append(0.0)
		_energy_phases.append(energy_phase)
		_vertical_phases.append(rng.randf_range(0.0, TAU))
		var variation := preset.population_variation
		var subtype := trait_rng.randi_range(0, 2)
		trait_types.append(subtype)
		trait_sizes.append(clampf(1.0 + trait_rng.randfn(0.0, 0.20) * variation, 0.58, 1.48))
		var subtype_tints := [Color(0.82, 1.0, 0.91), Color(0.88, 0.94, 1.0), Color(1.0, 0.90, 0.82)]
		trait_tints.append(Color.WHITE.lerp(subtype_tints[subtype], variation * 0.72))
		speed_factors.append(clampf(1.0 + trait_rng.randfn(0.0, 0.18) * variation, 0.62, 1.45))
		cohesion_factors.append(clampf(1.0 + trait_rng.randfn(0.0, 0.34) * variation, 0.35, 1.75))
		alignment_factors.append(clampf(1.0 + trait_rng.randfn(0.0, 0.30) * variation, 0.4, 1.7))
		lantern_response_factors.append(clampf(1.0 + trait_rng.randfn(0.0, 0.28) * variation, 0.45, 1.65))
		mushroom_response_factors.append(clampf(1.0 + trait_rng.randfn(0.0, 0.25) * variation, 0.5, 1.6))
		_neutral_offsets.append(trait_rng.randfn(0.0, 0.09) * variation)
		_wake_waits.append(trait_rng.randf_range(preset.spontaneous_wake_min_seconds, preset.spontaneous_wake_max_seconds))
		_wake_remaining.append(0.0)
		_wake_cycles.append(0)
		formation_predecessors.append(-1)
		formation_successors.append(-1)


func step(delta: float, field: LightField, social_multiplier: float = 1.0, wander_multiplier: float = 1.0) -> void:
	# The height control is live, so an authored ceiling change does not require
	# rebuilding the population. Motion constraints bring flyers back inside a
	# lowered band on this step.
	_sync_flight_height()
	_energy_time += delta
	if _last_field_mode != field.mode:
		exposures.fill(0.0)
		_last_field_mode = field.mode
	committed_this_step = PackedInt32Array()
	previous_positions = positions.duplicate()
	var old_positions := positions.duplicate()
	var old_velocities := velocities.duplicate()
	var old_lifecycles := lifecycles.duplicate()
	var old_arousals := arousals.duplicate()
	_build_neighbor_lists(old_positions, old_lifecycles)
	if preset.formation_follow_weight > 0.0 and _formation_step % 6 == 0:
		_refresh_formation_links(old_positions, old_velocities, old_lifecycles, old_arousals)
	elif preset.formation_follow_weight <= 0.0:
		formation_predecessors.fill(-1)
		formation_successors.fill(-1)
	_formation_step += 1
	var next_positions := positions.duplicate()
	var next_velocities := velocities.duplicate()
	for index: int in positions.size():
		lifecycle_times[index] += delta
		if lifecycles[index] != Lifecycle.ACTIVE:
			_update_lifecycle(index, delta, next_positions, next_velocities)
			continue
		var force := _wander_force(index, wander_multiplier)
		if preset.social_enabled:
			force += _social_force(index, old_positions, old_velocities, old_lifecycles) * social_multiplier
		var stimulus := field.sample(old_positions[index])
		exposures[index] = move_toward(exposures[index], stimulus, delta * 4.0)
		var mushroom_influence := _mushroom_influence(old_positions[index], old_velocities[index])
		mushroom_exposures[index] = mushroom_influence[0] if preset.energy_dynamics else 0.0
		_update_arousal(index, field.mode, exposures[index], mushroom_exposures[index], delta, old_arousals)
		var coupled := preset.formation_follow_weight > 0.0 and formation_predecessors[index] >= 0 and old_lifecycles[formation_predecessors[index]] == Lifecycle.ACTIVE
		var follower_scale := 0.5 if coupled else 1.0
		force += _lantern_force(old_positions[index], old_velocities[index], field, exposures[index]) * follower_scale
		if preset.energy_dynamics:
			var mushroom_force: Vector3 = mushroom_influence[1]
			mushroom_force *= mushroom_response_factors[index]
			if field.mode == LightField.Mode.ORANGE:
				mushroom_force *= 1.0 - exposures[index] * 0.85
			if _wake_remaining[index] > 0.0:
				mushroom_force *= 0.05
			force += mushroom_force * follower_scale
		force += _boundary_force(old_positions[index])
		force += _flight_band_force(index, old_positions[index])
		force += _goal_resistance(old_positions[index])
		var avoidance := _obstacle_force(old_positions[index], old_velocities[index]).limit_length(preset.max_acceleration)
		force = avoidance + force.limit_length(maxf(0.0, preset.max_acceleration - avoidance.length()))
		var applied_force := force
		var velocity := old_velocities[index] + force * delta
		if preset.energy_dynamics:
			var mobility := _energy_mobility(arousals[index])
			var sleep_amount := 1.0 - mobility
			applied_force *= mobility
			velocity = old_velocities[index] * exp(-delta * preset.sleep_velocity_damping * sleep_amount)
			velocity += applied_force * delta
			# Sleeping flyers settle instead of remaining suspended.
			velocity.y -= sleep_amount * 1.25 * delta
			var speed_cap := preset.max_speed * speed_factors[index] * lerpf(0.06, lerpf(0.88, 1.18, arousals[index]), mobility)
			if coupled and mobility > 0.35:
				speed_cap = minf(maxf(speed_cap, old_velocities[formation_predecessors[index]].length() + 0.35), preset.max_speed * 1.45 * 1.18 + 0.7)
			velocity = velocity.limit_length(speed_cap)
		else:
			velocity = velocity.limit_length(preset.max_speed * speed_factors[index] * lerpf(0.88, 1.18, arousals[index]))
		accelerations[index] = applied_force
		var constrained := _constrain_motion(old_positions[index], velocity, delta)
		next_positions[index] = constrained[0]
		next_velocities[index] = constrained[1]
		_update_goal(index, next_positions[index], delta)
	positions = next_positions
	velocities = next_velocities


func _build_neighbor_lists(snapshot_positions: PackedVector3Array, snapshot_lifecycles: PackedInt32Array) -> void:
	_neighbor_lists = []
	_neighbor_lists.resize(snapshot_positions.size())
	neighbor_visits = 0
	# Preserve the exact small-population behavior used by the original five presets.
	if snapshot_positions.size() <= 64:
		for index: int in snapshot_positions.size():
			var exact := PackedInt32Array()
			for other: int in snapshot_positions.size():
				if other != index and snapshot_lifecycles[other] == Lifecycle.ACTIVE:
					exact.append(other)
			_neighbor_lists[index] = exact
		return
	var cell_size := maxf(0.25, preset.neighbor_radius)
	var grid := {}
	for index: int in snapshot_positions.size():
		if snapshot_lifecycles[index] != Lifecycle.ACTIVE:
			continue
		var cell := _grid_cell(snapshot_positions[index], cell_size)
		if not grid.has(cell):
			grid[cell] = PackedInt32Array()
		var bucket: PackedInt32Array = grid[cell]
		bucket.append(index)
		grid[cell] = bucket
	var cap := maxi(4, preset.max_social_neighbors)
	# At most two probes per adjacent cell on the first pass, followed by a
	# deterministic rotated fill. Candidate enumeration itself remains bounded.
	for index: int in snapshot_positions.size():
		var selected := PackedInt32Array()
		if snapshot_lifecycles[index] != Lifecycle.ACTIVE:
			_neighbor_lists[index] = selected
			continue
		var origin := _grid_cell(snapshot_positions[index], cell_size)
		for sweep: int in 2:
			for x: int in range(-1, 2):
				for z: int in range(-1, 2):
					if selected.size() >= cap:
						break
					var cell := origin + Vector2i(x, z)
					if not grid.has(cell):
						continue
					var bucket: PackedInt32Array = grid[cell]
					if bucket.is_empty():
						continue
					var probes := mini(2 if sweep == 0 else 1, bucket.size())
					var start := posmod(index * 17 + cell.x * 11 + cell.y * 31 + sweep * 7, bucket.size())
					for probe: int in probes:
						var other := bucket[(start + probe * maxi(1, bucket.size() / probes)) % bucket.size()]
						if other != index and not selected.has(other):
							selected.append(other)
		_neighbor_lists[index] = selected


func _grid_cell(position: Vector3, cell_size: float) -> Vector2i:
	# The flight band is shorter than a neighbor cell, so XZ buckets plus the
	# exact 3D distance check cover all neighboring cells with fewer lookups.
	# Candidate sampling inside those cells is deliberately approximate.
	return Vector2i(floori(position.x / cell_size), floori(position.z / cell_size))


func _refresh_formation_links(snapshot_positions: PackedVector3Array, _snapshot_velocities: PackedVector3Array, snapshot_lifecycles: PackedInt32Array, snapshot_arousals: PackedFloat32Array) -> void:
	# Each role proposes the closest neighbor for each adjacent role. Keep an
	# existing link while it is nearby; the reciprocal test below makes slots
	# exclusive without a central group allocator or permanent creature IDs.
	var count := snapshot_positions.size()
	var before := PackedInt32Array()
	var after := PackedInt32Array()
	before.resize(count)
	after.resize(count)
	before.fill(-1)
	after.fill(-1)
	for index: int in count:
		if snapshot_lifecycles[index] != Lifecycle.ACTIVE or snapshot_arousals[index] <= preset.sleep_threshold + 0.04:
			continue
		var role := trait_types[index]
		var old_before := formation_predecessors[index]
		var old_after := formation_successors[index]
		if role > 0 and _valid_formation_partner(index, old_before, role - 1, 4.0, snapshot_positions, snapshot_lifecycles, snapshot_arousals):
			before[index] = old_before
		if role < 2 and _valid_formation_partner(index, old_after, role + 1, 4.0, snapshot_positions, snapshot_lifecycles, snapshot_arousals):
			after[index] = old_after
		var keep_before := before[index] >= 0
		var keep_after := after[index] >= 0
		var nearest_before := 3.2 * 3.2
		var nearest_after := 3.2 * 3.2
		for other: int in count:
			if other == index or snapshot_lifecycles[other] != Lifecycle.ACTIVE or snapshot_arousals[other] <= preset.sleep_threshold + 0.04:
				continue
			var other_role := trait_types[other]
			if other_role != role - 1 and other_role != role + 1:
				continue
			var occupied := formation_successors[other] if other_role == role - 1 else formation_predecessors[other]
			if occupied >= 0 and occupied != index and _valid_formation_partner(other, occupied, role, 4.0, snapshot_positions, snapshot_lifecycles, snapshot_arousals):
				continue
			var distance_sq := snapshot_positions[index].distance_squared_to(snapshot_positions[other])
			if not keep_before and other_role == role - 1 and distance_sq < nearest_before:
				nearest_before = distance_sq
				before[index] = other
			if not keep_after and other_role == role + 1 and distance_sq < nearest_after:
				nearest_after = distance_sq
				after[index] = other
	var next_before := PackedInt32Array()
	var next_after := PackedInt32Array()
	next_before.resize(count)
	next_after.resize(count)
	next_before.fill(-1)
	next_after.fill(-1)
	for index: int in count:
		if before[index] >= 0 and after[before[index]] == index:
			next_before[index] = before[index]
		if after[index] >= 0 and before[after[index]] == index:
			next_after[index] = after[index]
	formation_predecessors = next_before
	formation_successors = next_after


func _valid_formation_partner(index: int, other: int, target_role: int, radius: float, snapshot_positions: PackedVector3Array, snapshot_lifecycles: PackedInt32Array, snapshot_arousals: PackedFloat32Array) -> bool:
	return other >= 0 and other < snapshot_positions.size() and snapshot_lifecycles[other] == Lifecycle.ACTIVE and snapshot_arousals[other] > preset.sleep_threshold + 0.04 and trait_types[other] == target_role and snapshot_positions[index].distance_squared_to(snapshot_positions[other]) < radius * radius


func _social_force(index: int, snapshot_positions: PackedVector3Array, snapshot_velocities: PackedVector3Array, snapshot_lifecycles: PackedInt32Array) -> Vector3:
	var separation := Vector3.ZERO
	var alignment := Vector3.ZERO
	var cohesion_center := Vector3.ZERO
	var neighbors := 0
	var affinity_sum := 0.0
	var crowded_neighbors := 0
	var crowded_center := Vector3.ZERO
	var formation_enabled := preset.formation_follow_weight > 0.0 or preset.cluster_pressure_weight > 0.0
	var crowd_radius := minf(preset.neighbor_radius, preset.separation_radius * 2.0)
	var candidates := PackedInt32Array()
	if _neighbor_lists.size() == snapshot_positions.size():
		candidates = _neighbor_lists[index]
	else:
		for other: int in snapshot_positions.size():
			if other != index and snapshot_lifecycles[other] == Lifecycle.ACTIVE:
				candidates.append(other)
	for other: int in candidates:
		var offset := snapshot_positions[index] - snapshot_positions[other]
		var distance := offset.length()
		if distance <= 0.0001 or distance > preset.neighbor_radius:
			continue
		var same_trio := false
		if preset.formation_follow_weight > 0.0:
			same_trio = other == formation_predecessors[index] or other == formation_successors[index]
			if formation_predecessors[index] >= 0:
				same_trio = same_trio or other == formation_predecessors[formation_predecessors[index]]
			if formation_successors[index] >= 0:
				same_trio = same_trio or other == formation_successors[formation_successors[index]]
		if formation_enabled and distance < crowd_radius and not same_trio:
			crowded_neighbors += 1
			crowded_center += snapshot_positions[other]
		var affinity := 1.0
		var desired_offset := Vector3.ZERO
		if preset.population_variation > 0.0 and index < trait_types.size() and other < trait_types.size():
			# Small cyclic affinity biases social force without persistent links.
			var preferred_type := (trait_types[index] + 1) % 3
			var full_affinity := 1.24 if trait_types[other] == preferred_type else (1.08 if trait_types[other] == trait_types[index] else 0.76)
			affinity = lerpf(1.0, full_affinity, preset.population_variation)
			if snapshot_velocities[other].length_squared() > 0.01:
				desired_offset = -snapshot_velocities[other].normalized() * float(trait_types[index] - 1) * 0.22 * preset.population_variation
		neighbors += 1
		affinity_sum += affinity
		alignment += snapshot_velocities[other] * affinity
		cohesion_center += (snapshot_positions[other] + desired_offset) * affinity
		if distance < preset.separation_radius and not same_trio:
			separation += offset.normalized() * (1.0 - distance / preset.separation_radius)
	var cohesion := Vector3.ZERO
	if neighbors > 0:
		alignment = alignment / affinity_sum - snapshot_velocities[index]
		cohesion = (cohesion_center / affinity_sum - snapshot_positions[index]).limit_length(1.0)
	var social_retention := 1.0 - _arousal_scatter_amount(index) * 0.82
	var formation := Vector3.ZERO
	if preset.formation_follow_weight > 0.0 and formation_predecessors[index] >= 0 and snapshot_lifecycles[formation_predecessors[index]] == Lifecycle.ACTIVE:
		var leader := formation_predecessors[index]
		var leader_velocity := snapshot_velocities[leader]
		var heading := leader_velocity.normalized() if leader_velocity.length_squared() > 0.01 else Vector3.FORWARD
		var target := snapshot_positions[leader] - heading * 0.18
		formation = (target - snapshot_positions[index]).limit_length(2.0) * 4.0 + (leader_velocity - snapshot_velocities[index]) * 2.2
	var pressure := Vector3.ZERO
	var target_count := maxi(1, preset.cluster_target_neighbors)
	if crowded_neighbors > target_count:
		var away := snapshot_positions[index] - crowded_center / float(crowded_neighbors)
		if away.length_squared() > 0.0001:
			pressure = away.normalized() * minf(float(crowded_neighbors - target_count) / float(target_count), 1.5)
	var broad_cohesion := 1.0 - minf(preset.formation_follow_weight, 1.0) * 0.75
	var broad_social := separation * preset.separation_weight + pressure * preset.cluster_pressure_weight + (alignment * preset.alignment_weight * alignment_factors[index] + cohesion * preset.cohesion_weight * cohesion_factors[index] * broad_cohesion) * social_retention
	if preset.formation_follow_weight > 0.0 and formation_predecessors[index] >= 0:
		broad_social *= 0.18
	return broad_social + formation * preset.formation_follow_weight


func _wander_force(index: int, multiplier: float) -> Vector3:
	var scatter := _arousal_scatter_amount(index)
	var phase := wander_phases[index] + _energy_time * (0.48 + float((index * 17) % 9) * 0.035)
	phase += scatter * (sin(_energy_time * 1.73 + _energy_phases[index] * 1.31) * 1.05 + sin(_energy_time * 0.47 + _energy_phases[index] * 2.17) * 0.62)
	var vertical_energy := smoothstep(preset.energy_neutral_target, 1.0, arousals[index])
	var vertical := sin(_energy_time * (0.63 + float(index % 5) * 0.08) + _vertical_phases[index]) * 0.62 * lerpf(0.7, 1.65, vertical_energy)
	# A low-frequency shared curl gives a school a coherent bend without locking individuals together.
	var flow_phase := _energy_time * 0.16 + positions[index].x * 0.035 - positions[index].z * 0.027
	var direction := Vector3(cos(phase) + sin(flow_phase) * 0.38, vertical, sin(phase) + cos(flow_phase * 1.17) * 0.38).normalized()
	var wake_boost := 2.6 if index < _wake_remaining.size() and _wake_remaining[index] > 0.0 else 1.0
	var follower_scale := 0.35 if preset.formation_follow_weight > 0.0 and formation_predecessors[index] >= 0 and lifecycles[formation_predecessors[index]] == Lifecycle.ACTIVE else 1.0
	return direction * preset.wander_weight * multiplier * lerpf(0.55, 1.45, arousals[index]) * (1.0 + scatter * 3.2) * wake_boost * follower_scale


func _arousal_scatter_amount(index: int) -> float:
	if not preset.energy_dynamics or preset.arousal_scatter_strength <= 0.0:
		return 0.0
	return smoothstep(preset.energy_neutral_target, 1.0, arousals[index]) * clampf(preset.arousal_scatter_strength, 0.0, 1.0)


func _lantern_force(position: Vector3, velocity: Vector3, field: LightField, stimulus: float) -> Vector3:
	if stimulus <= 0.0001 or field.mode == LightField.Mode.CLEAR:
		return Vector3.ZERO
	var target := field.flight_target(min_height, max_height)
	if field.mode == LightField.Mode.ORANGE:
		target = field.source_position
	var to_target := target - position
	var distance := to_target.length()
	if distance <= 0.001:
		return -velocity * 0.8
	var direction := to_target / distance
	if field.mode == LightField.Mode.ORANGE:
		var desired := -direction * preset.max_speed
		# Preserve the 3D flee cue while avoiding a downward-pointed handheld
		# lantern pinning newly awakened agents to the floor.
		desired.y *= 0.35
		return (desired - velocity) * preset.light_weight * stimulus * 0.62
	var desired_speed := preset.max_speed * smoothstep(0.0, preset.arrival_radius * 2.2, distance)
	if distance >= preset.arrival_radius:
		desired_speed = maxf(desired_speed, 1.05)
	return (direction * desired_speed - velocity) * preset.light_weight * stimulus


func _update_arousal(index: int, field_mode: LightField.Mode, stimulus: float, mushroom_exposure: float, delta: float, old_arousals: PackedFloat32Array = PackedFloat32Array()) -> void:
	if preset.energy_dynamics:
		var recovery_rate := maxf(0.0, preset.energy_recovery_rate)
		var total_rate := recovery_rate
		var neutral := _individual_neutral_target(_energy_phases[index])
		if index < _neutral_offsets.size():
			neutral = clampf(neutral + _neutral_offsets[index], 0.0, 1.0)
		var weighted_target := recovery_rate * neutral
		var mushroom_response := mushroom_response_factors[index] if index < mushroom_response_factors.size() else 1.0
		var lamp_response := lantern_response_factors[index] if index < lantern_response_factors.size() else 1.0
		var mushroom_rate := maxf(0.0, preset.mushroom_suppression_rate) * mushroom_exposure * mushroom_response
		total_rate += mushroom_rate
		weighted_target += mushroom_rate * preset.blue_energy_target
		if field_mode == LightField.Mode.BLUE:
			var blue_rate := maxf(0.0, preset.blue_energy_response) * stimulus * lamp_response
			total_rate += blue_rate
			weighted_target += blue_rate * preset.blue_energy_target
		elif field_mode == LightField.Mode.ORANGE:
			var orange_rate := maxf(0.0, preset.orange_energy_response) * stimulus * lamp_response
			total_rate += orange_rate
			weighted_target += orange_rate * preset.orange_energy_target
		var contagion := _neighbor_arousal(index, old_arousals)
		if contagion > neutral:
			var contagion_rate := preset.arousal_contagion_strength * smoothstep(neutral, 1.0, contagion) * 1.35
			total_rate += contagion_rate
			weighted_target += contagion_rate * minf(0.78, contagion)
		_update_spontaneous_wake(index, mushroom_exposure, delta)
		if _wake_remaining[index] > 0.0:
			var wake_rate := 2.2
			total_rate += wake_rate
			weighted_target += wake_rate * preset.spontaneous_wake_energy
		if total_rate > 0.00001:
			arousals[index] = lerpf(arousals[index], weighted_target / total_rate, 1.0 - exp(-delta * total_rate))
		arousals[index] = clampf(arousals[index], 0.0, 1.0)
		return
	if not preset.arousal_memory:
		arousals[index] = preset.baseline_arousal
		return
	var target := preset.baseline_arousal
	if field_mode == LightField.Mode.BLUE:
		target = lerpf(target, 0.08, stimulus)
	elif field_mode == LightField.Mode.ORANGE:
		target = lerpf(target, 0.92, stimulus)
	var rate := preset.arousal_response if stimulus > 0.02 else preset.arousal_response * 0.32
	arousals[index] = lerpf(arousals[index], target, 1.0 - exp(-delta * rate))


func _neighbor_arousal(index: int, old_arousals: PackedFloat32Array) -> float:
	if preset.arousal_contagion_strength <= 0.0 or old_arousals.is_empty() or index >= _neighbor_lists.size():
		return 0.0
	var strongest := 0.0
	for other: int in _neighbor_lists[index]:
		neighbor_visits += 1
		var distance := positions[index].distance_to(positions[other])
		if distance > preset.neighbor_radius or distance <= 0.0001:
			continue
		var weight := 1.0 - distance / preset.neighbor_radius
		strongest = maxf(strongest, maxf(0.0, old_arousals[other] - preset.energy_neutral_target) * weight)
	if strongest <= 0.00001:
		return 0.0
	return preset.energy_neutral_target + strongest


func _update_spontaneous_wake(index: int, mushroom_exposure: float, delta: float) -> void:
	if not preset.spontaneous_waking_enabled:
		_wake_remaining[index] = 0.0
		return
	if _wake_remaining[index] > 0.0:
		_wake_remaining[index] = maxf(0.0, _wake_remaining[index] - delta)
		return
	# Timers advance only while actually dormant at a mushroom, preventing a
	# synchronized global pulse and avoiding surprise wakes during herding.
	if mushroom_exposure < 0.35 or arousals[index] > preset.sleep_threshold + 0.04:
		return
	_wake_waits[index] -= delta
	if _wake_waits[index] > 0.0:
		return
	_wake_remaining[index] = preset.spontaneous_wake_duration
	_wake_cycles[index] += 1
	var span := maxf(0.0, preset.spontaneous_wake_max_seconds - preset.spontaneous_wake_min_seconds)
	var phase := sin(float(seed_value + index * 7919 + _wake_cycles[index] * 104729)) * 0.5 + 0.5
	_wake_waits[index] = preset.spontaneous_wake_min_seconds + span * phase


func _individual_neutral_target(phase: float) -> float:
	return clampf(preset.energy_neutral_target + sin(_energy_time * preset.energy_individuality_rate + phase) * preset.energy_individuality, 0.0, 1.0)


func _energy_mobility(energy: float) -> float:
	return smoothstep(preset.sleep_threshold, maxf(preset.sleep_threshold + 0.001, preset.energy_neutral_target), energy)


func _mushroom_exposure_at(position: Vector3) -> float:
	if preset.mushroom_radius <= 0.001:
		return 0.0
	var total := 0.0
	for center: Vector2 in mushroom_centers:
		var cap := Vector3(center.x, 0.45, center.y)
		var distance := position.distance_to(cap)
		if distance < preset.mushroom_radius:
			total += 1.0 - smoothstep(preset.mushroom_radius * 0.18, preset.mushroom_radius, distance)
	return clampf(total, 0.0, 1.0)


func _mushroom_influence(position: Vector3, velocity: Vector3) -> Array:
	if not preset.energy_dynamics or mushroom_centers.is_empty() or preset.mushroom_radius <= 0.001:
		return [0.0, Vector3.ZERO]
	var total_weight := 0.0
	var weighted_center := Vector3.ZERO
	for center: Vector2 in mushroom_centers:
		var cap := Vector3(center.x, 0.45, center.y)
		var distance := position.distance_to(cap)
		if distance >= preset.mushroom_radius:
			continue
		var weight := 1.0 - smoothstep(preset.mushroom_radius * 0.18, preset.mushroom_radius, distance)
		total_weight += weight
		weighted_center += cap * weight
	var exposure := clampf(total_weight, 0.0, 1.0)
	if total_weight <= 0.00001:
		return [0.0, Vector3.ZERO]
	var to_center := weighted_center / total_weight - position
	var distance := to_center.length()
	if distance <= 0.001:
		return [exposure, -velocity * preset.mushroom_attraction_weight * exposure]
	var desired_velocity := to_center / distance * preset.max_speed * 0.55 * smoothstep(0.0, preset.arrival_radius * 1.5, distance)
	return [exposure, (desired_velocity - velocity) * preset.mushroom_attraction_weight * exposure]


func _obstacle_force(position: Vector3, velocity: Vector3) -> Vector3:
	var result := Vector3.ZERO
	var horizontal := Vector2(position.x, position.z)
	var ahead := horizontal + Vector2(velocity.x, velocity.z) * 0.75
	for index: int in obstacle_centers.size():
		var offset := horizontal - obstacle_centers[index]
		var distance := offset.length()
		var safe_radius := obstacle_radii[index] + 0.8
		if distance < safe_radius and distance > 0.001:
			var urgency := 1.0 - distance / safe_radius
			result += Vector3(offset.x, 0.0, offset.y).normalized() * preset.obstacle_weight * urgency * urgency
		var ahead_offset := ahead - obstacle_centers[index]
		if ahead_offset.length() < obstacle_radii[index] + 0.4 and ahead_offset.length() > 0.001:
			result += Vector3(ahead_offset.x, 0.0, ahead_offset.y).normalized() * preset.obstacle_weight * 0.75
	return result


func _boundary_force(position: Vector3) -> Vector3:
	var result := Vector3.ZERO
	if absf(position.x) > world_limit - 1.6:
		result.x = -signf(position.x) * (absf(position.x) - (world_limit - 1.6)) * 3.2
	if absf(position.z) > world_limit - 1.6:
		result.z = -signf(position.z) * (absf(position.z) - (world_limit - 1.6)) * 3.2
	if position.y < min_height + 0.45:
		result.y += (min_height + 0.45 - position.y) * 2.4
	elif position.y > max_height - 0.45:
		result.y -= (position.y - (max_height - 0.45)) * 2.4
	return result


func _flight_band_force(index: int, position: Vector3) -> Vector3:
	if preset.energy_dynamics and _energy_mobility(arousals[index]) < 0.08:
		return Vector3.ZERO
	# Keep ordinary schools near standing player height even when the ceiling is
	# raised. Energy opens a larger, mostly-upward orbit, allowing excited mushi
	# to use the volume before the gentle reference-height pull brings them back.
	var player_height := clampf(1.5, min_height + 0.35, max_height - 0.35)
	var vertical_energy := smoothstep(preset.energy_neutral_target, 1.0, arousals[index])
	var headroom := maxf(0.0, max_height - player_height - 0.25)
	var excursion := headroom * lerpf(0.08, 0.82, vertical_energy)
	var orbit := sin(_energy_time * lerpf(0.18, 0.34, vertical_energy) + _vertical_phases[index])
	var preferred := player_height + excursion * (0.25 + orbit * 0.75)
	return Vector3.UP * clampf((preferred - position.y) * lerpf(0.48, 0.72, vertical_energy), -1.25, 1.25)


func _sync_flight_height() -> void:
	max_height = maxf(min_height + 0.75, preset.flight_max_height)


func _goal_resistance(position: Vector3) -> Vector3:
	var offset := Vector2(position.x, position.z) - goal_position
	var distance := offset.length()
	var outer_width := maxf(0.0, preset.goal_repulsion_outer_width)
	if distance < 0.001 or distance >= goal_radius + outer_width or outer_width <= 0.001:
		return Vector3.ZERO
	var strength := smoothstep(goal_radius - 0.8, goal_radius, distance) * (1.0 - smoothstep(goal_radius, goal_radius + outer_width, distance)) * preset.goal_repulsion_strength
	return Vector3(offset.x, 0.0, offset.y).normalized() * strength


func _update_goal(index: int, position: Vector3, delta: float) -> void:
	if lifecycles[index] != Lifecycle.ACTIVE:
		return
	if not goal_accepting:
		_goal_dwells[index] = 0.0
		return
	if Vector2(position.x, position.z).distance_to(goal_position) <= goal_radius:
		_goal_dwells[index] += delta
		if _goal_dwells[index] >= goal_dwell_seconds:
			lifecycles[index] = Lifecycle.COMMITTED
			lifecycle_times[index] = 0.0
			score += 1
			committed_this_step.append(index)
	else:
		_goal_dwells[index] = maxf(0.0, _goal_dwells[index] - delta * 2.0)


func _update_lifecycle(index: int, delta: float, next_positions: PackedVector3Array, next_velocities: PackedVector3Array) -> void:
	if lifecycles[index] == Lifecycle.COMMITTED:
		var target := Vector3(goal_position.x, positions[index].y, goal_position.y)
		next_positions[index] = positions[index].lerp(target, 1.0 - exp(-delta * 4.0))
		next_velocities[index] = Vector3.ZERO
		if lifecycle_times[index] >= 0.22:
			lifecycles[index] = Lifecycle.ASCENDING
			lifecycle_times[index] = 0.0
	elif lifecycles[index] == Lifecycle.ASCENDING:
		var target := Vector3(goal_position.x, max_height + 1.0, goal_position.y)
		next_positions[index] = positions[index].lerp(target, 1.0 - exp(-delta * 2.2))
		next_velocities[index] = Vector3.UP
		if lifecycle_times[index] >= 2.35:
			lifecycles[index] = Lifecycle.RELEASED
			lifecycle_times[index] = 0.0


func active_count() -> int:
	var count := 0
	for state: int in lifecycles:
		if state == Lifecycle.ACTIVE:
			count += 1
	return count


func is_finite_and_bounded() -> bool:
	for index: int in positions.size():
		if not positions[index].is_finite() or not velocities[index].is_finite() or not accelerations[index].is_finite():
			return false
		if not is_finite(arousals[index]) or not is_finite(mushroom_exposures[index]):
			return false
		if arousals[index] < 0.0 or arousals[index] > 1.0 or mushroom_exposures[index] < 0.0 or mushroom_exposures[index] > 1.0:
			return false
		if lifecycles[index] == Lifecycle.ACTIVE and (positions[index].y < min_height - 0.001 or positions[index].y > max_height + 0.001):
			return false
		if absf(positions[index].x) > world_limit + 0.001 or absf(positions[index].z) > world_limit + 0.001:
			return false
		if accelerations[index].length() > preset.max_acceleration + 0.001:
			return false
		var speed_factor := speed_factors[index] if index < speed_factors.size() else 1.0
		var permitted_speed := preset.max_speed * speed_factor * 1.181
		if preset.formation_follow_weight > 0.0 and formation_predecessors[index] >= 0:
			permitted_speed = maxf(permitted_speed, preset.max_speed * 1.45 * 1.18 + 0.701)
		if lifecycles[index] == Lifecycle.ACTIVE and velocities[index].length() > permitted_speed:
			return false
	return true


# Trunks are conservative infinite vertical cylinders for this bounded spike.
func _constrain_motion(start: Vector3, velocity: Vector3, delta: float) -> Array:
	var horizontal := Vector2(start.x, start.z)
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	var remaining := horizontal_velocity * delta
	for _iteration: int in 3:
		var first_hit := 1.0
		var hit_normal := Vector2.ZERO
		var movement_sq := remaining.length_squared()
		if movement_sq < 0.00000001:
			break
		for obstacle_index: int in obstacle_centers.size():
			var offset := horizontal - obstacle_centers[obstacle_index]
			var radius := obstacle_radii[obstacle_index] + BODY_RADIUS
			var b := 2.0 * offset.dot(remaining)
			var c := offset.length_squared() - radius * radius
			var discriminant := b * b - 4.0 * movement_sq * c
			if discriminant < 0.0 or b >= 0.0:
				continue
			var hit := (-b - sqrt(discriminant)) / (2.0 * movement_sq)
			if hit >= -0.00001 and hit < first_hit:
				first_hit = maxf(hit, 0.0)
				hit_normal = (offset + remaining * first_hit).normalized()
		horizontal += remaining * maxf(0.0, first_hit - 0.00001)
		if hit_normal == Vector2.ZERO:
			break
		remaining *= 1.0 - first_hit
		remaining -= hit_normal * minf(remaining.dot(hit_normal), 0.0)
		horizontal_velocity -= hit_normal * minf(horizontal_velocity.dot(hit_normal), 0.0)
	var horizontal_limit := world_limit - BODY_RADIUS
	var bounded := horizontal.clamp(Vector2(-horizontal_limit, -horizontal_limit), Vector2(horizontal_limit, horizontal_limit))
	if bounded.x != horizontal.x:
		horizontal_velocity.x = 0.0
	if bounded.y != horizontal.y:
		horizontal_velocity.y = 0.0
	var height := clampf(start.y + velocity.y * delta, min_height, max_height)
	if height != start.y + velocity.y * delta:
		velocity.y = 0.0
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
	return [Vector3(bounded.x, height, bounded.y), velocity]
