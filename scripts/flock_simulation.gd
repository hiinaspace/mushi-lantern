class_name FlockSimulation
extends RefCounted

enum Lifecycle { ACTIVE, COMMITTED, ASCENDING, RELEASED }

const BODY_HEIGHT := 0.42
const BODY_RADIUS := 0.22
const WORLD_LIMIT := 13.5
const DEFAULT_SPAWN_CENTERS := [Vector2(-7.2, -6.6), Vector2(7.3, -6.0), Vector2(7.7, 6.8)]

var seed_value: int = 40721
var preset: HerdPreset = HerdPreset.new()
var positions: PackedVector2Array = PackedVector2Array()
var previous_positions: PackedVector2Array = PackedVector2Array()
var velocities: PackedVector2Array = PackedVector2Array()
var accelerations: PackedVector2Array = PackedVector2Array()
var arousals: PackedFloat32Array = PackedFloat32Array()
var exposures: PackedFloat32Array = PackedFloat32Array()
var mushroom_exposures: PackedFloat32Array = PackedFloat32Array()
var lifecycles: PackedInt32Array = PackedInt32Array()
var lifecycle_times: PackedFloat32Array = PackedFloat32Array()
var wander_phases: PackedFloat32Array = PackedFloat32Array()
var group_ids: PackedInt32Array = PackedInt32Array()
var goal_position := Vector2.ZERO
var goal_radius: float = 2.05
var goal_dwell_seconds: float = 0.45
var obstacle_centers: PackedVector2Array = PackedVector2Array()
var obstacle_radii: PackedFloat32Array = PackedFloat32Array()
var mushroom_centers: PackedVector2Array = PackedVector2Array()
var spawn_centers: PackedVector2Array = PackedVector2Array(DEFAULT_SPAWN_CENTERS)
var world_limit: float = WORLD_LIMIT
var score: int = 0
var _last_field_mode: int = -1
var committed_this_step: PackedInt32Array = PackedInt32Array()
var _goal_dwells: PackedFloat32Array = PackedFloat32Array()
var _energy_phases: PackedFloat32Array = PackedFloat32Array()
var _energy_time: float = 0.0

func reset(agent_count: int, new_seed: int, new_preset: HerdPreset) -> void:
	seed_value = new_seed
	preset = new_preset.copy_preset()
	positions = PackedVector2Array()
	previous_positions = PackedVector2Array()
	velocities = PackedVector2Array()
	accelerations = PackedVector2Array()
	arousals = PackedFloat32Array()
	exposures = PackedFloat32Array()
	mushroom_exposures = PackedFloat32Array()
	lifecycles = PackedInt32Array()
	lifecycle_times = PackedFloat32Array()
	wander_phases = PackedFloat32Array()
	group_ids = PackedInt32Array()
	_goal_dwells = PackedFloat32Array()
	_energy_phases = PackedFloat32Array()
	_energy_time = 0.0
	score = 0
	_last_field_mode = -1
	committed_this_step = PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	var energy_rng := RandomNumberGenerator.new()
	energy_rng.seed = new_seed ^ 0x5f3759df
	var centers := spawn_centers
	if centers.is_empty():
		centers = PackedVector2Array(DEFAULT_SPAWN_CENTERS)
	for index: int in agent_count:
		var group: int = 0 if agent_count == 3 else index / 8
		group = mini(group, centers.size() - 1)
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.45, 1.75)
		var position := centers[group] + Vector2.from_angle(angle) * radius
		var velocity := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.25, 0.7)
		positions.append(position)
		previous_positions.append(position)
		velocities.append(velocity)
		accelerations.append(Vector2.ZERO)
		var energy_phase := energy_rng.randf_range(0.0, TAU)
		_energy_phases.append(energy_phase)
		var mushroom_exposure := _mushroom_exposure_at(position) if preset.energy_dynamics else 0.0
		mushroom_exposures.append(mushroom_exposure)
		var initial_energy := preset.baseline_arousal
		if preset.energy_dynamics:
			var neutral := _individual_neutral_target(energy_phase)
			var initial_suppression := smoothstep(0.0, 0.7, mushroom_exposure)
			initial_energy = lerpf(neutral, preset.blue_energy_target, initial_suppression)
		arousals.append(clampf(initial_energy, 0.0, 1.0))
		exposures.append(0.0)
		lifecycles.append(Lifecycle.ACTIVE)
		lifecycle_times.append(0.0)
		wander_phases.append(rng.randf_range(0.0, TAU))
		group_ids.append(group)
		_goal_dwells.append(0.0)

func step(delta: float, field: LightField, social_multiplier: float = 1.0, wander_multiplier: float = 1.0) -> void:
	_energy_time += delta
	# Smoothed exposure belongs to a filter; do not reinterpret it after switching.
	if _last_field_mode != field.mode:
		exposures.fill(0.0)
		_last_field_mode = field.mode
	committed_this_step = PackedInt32Array()
	previous_positions = positions.duplicate()
	var old_positions := positions.duplicate()
	var old_velocities := velocities.duplicate()
	var old_lifecycles := lifecycles.duplicate()
	var next_positions := positions.duplicate()
	var next_velocities := velocities.duplicate()
	for index: int in positions.size():
		lifecycle_times[index] += delta
		if lifecycles[index] != Lifecycle.ACTIVE:
			_update_lifecycle(index, delta, next_positions)
			continue

		var force := _wander_force(index, delta, wander_multiplier)
		if preset.social_enabled:
			force += _social_force(index, old_positions, old_velocities, old_lifecycles) * social_multiplier
		var sample_position := Vector3(old_positions[index].x, BODY_HEIGHT, old_positions[index].y)
		var stimulus := field.sample(sample_position)
		exposures[index] = move_toward(exposures[index], stimulus, delta * 4.0)
		var mushroom_influence := _mushroom_influence(old_positions[index], old_velocities[index])
		mushroom_exposures[index] = mushroom_influence[0] if preset.energy_dynamics else 0.0
		_update_arousal(index, field.mode, exposures[index], mushroom_exposures[index], delta)
		force += _lantern_force(index, old_positions[index], old_velocities[index], field, exposures[index])
		if preset.energy_dynamics:
			var mushroom_force: Vector2 = mushroom_influence[1]
			if field.mode == LightField.Mode.ORANGE:
				mushroom_force *= 1.0 - exposures[index] * 0.85
			force += mushroom_force
		force += _boundary_force(old_positions[index])
		force += _goal_resistance(old_positions[index])
		# Reserve the steering budget for avoidance before behavioral forces.
		var avoidance := _obstacle_force(old_positions[index], old_velocities[index]).limit_length(preset.max_acceleration)
		force = avoidance + force.limit_length(maxf(0.0, preset.max_acceleration - avoidance.length()))
		var activity_scale := lerpf(0.88, 1.18, arousals[index])
		var applied_force := force
		var velocity := old_velocities[index] + force * delta
		if preset.energy_dynamics:
			var mobility := _energy_mobility(arousals[index])
			var sleep_amount := 1.0 - mobility
			applied_force *= mobility
			velocity = old_velocities[index] * exp(-delta * preset.sleep_velocity_damping * sleep_amount)
			velocity += applied_force * delta
			var sleepy_speed_scale := lerpf(0.035, activity_scale, mobility)
			velocity = velocity.limit_length(preset.max_speed * sleepy_speed_scale)
		else:
			velocity = velocity.limit_length(preset.max_speed * activity_scale)
		accelerations[index] = applied_force
		if not preset.energy_dynamics and velocity.length_squared() < 0.014:
			velocity += Vector2.from_angle(wander_phases[index]) * delta * 0.4
		var constrained := _constrain_motion(old_positions[index], velocity, delta)
		next_positions[index] = constrained[0]
		next_velocities[index] = constrained[1]
		_update_goal(index, next_positions[index], delta)
	positions = next_positions
	velocities = next_velocities

func _social_force(index: int, snapshot_positions: PackedVector2Array, snapshot_velocities: PackedVector2Array, snapshot_lifecycles: PackedInt32Array) -> Vector2:
	var separation := Vector2.ZERO
	var alignment := Vector2.ZERO
	var cohesion_center := Vector2.ZERO
	var neighbors := 0
	for other: int in snapshot_positions.size():
		if other == index or snapshot_lifecycles[other] != Lifecycle.ACTIVE:
			continue
		var offset := snapshot_positions[index] - snapshot_positions[other]
		var distance := offset.length()
		if distance <= 0.0001 or distance > preset.neighbor_radius:
			continue
		neighbors += 1
		alignment += snapshot_velocities[other]
		cohesion_center += snapshot_positions[other]
		if distance < preset.separation_radius:
			separation += offset.normalized() * (1.0 - distance / preset.separation_radius)
	if neighbors == 0:
		return Vector2.ZERO
	alignment = alignment / float(neighbors) - snapshot_velocities[index]
	cohesion_center = cohesion_center / float(neighbors)
	var cohesion := (cohesion_center - snapshot_positions[index]).limit_length(1.0)
	var social_retention := 1.0 - _arousal_scatter_amount(index) * 0.82
	return separation * preset.separation_weight + (alignment * preset.alignment_weight + cohesion * preset.cohesion_weight) * social_retention

func _wander_force(index: int, delta: float, multiplier: float) -> Vector2:
	var phase_speed := 0.52 + float((index * 17) % 9) * 0.035
	wander_phases[index] = fmod(wander_phases[index] + delta * phase_speed, TAU)
	var heading := wander_phases[index]
	var scatter := _arousal_scatter_amount(index)
	if scatter > 0.0:
		# Seeded, incommensurate harmonics keep excited agents from turning in
		# synchronous circles while remaining smooth and fixed-step deterministic.
		var seed_phase := _energy_phases[index]
		heading += scatter * (
			sin(_energy_time * 1.73 + seed_phase * 1.31) * 1.05
			+ sin(_energy_time * 0.47 + seed_phase * 2.17) * 0.62
		)
	var direction := Vector2.from_angle(heading)
	var scatter_gain := 1.0 + scatter * 3.2
	return direction * preset.wander_weight * multiplier * lerpf(0.55, 1.45, arousals[index]) * scatter_gain

func _arousal_scatter_amount(index: int) -> float:
	if not preset.energy_dynamics or preset.arousal_scatter_strength <= 0.0:
		return 0.0
	var neutral := preset.energy_neutral_target
	var high_energy := smoothstep(neutral, 1.0, arousals[index])
	return high_energy * clampf(preset.arousal_scatter_strength, 0.0, 1.0)

func _lantern_force(index: int, position: Vector2, velocity: Vector2, field: LightField, stimulus: float) -> Vector2:
	if stimulus <= 0.0001 or field.mode == LightField.Mode.CLEAR:
		return Vector2.ZERO
	var target := field.ground_target(BODY_HEIGHT)
	if field.mode == LightField.Mode.ORANGE:
		target = Vector2(field.source_position.x, field.source_position.z)
	var to_target := target - position
	var distance := to_target.length()
	if distance <= 0.001:
		return -velocity * 0.8
	var direction := to_target / distance
	if field.mode == LightField.Mode.ORANGE:
		direction = -direction
		return (direction * preset.max_speed - velocity) * preset.light_weight * stimulus * 0.62
	var desired_speed := preset.max_speed * smoothstep(0.0, preset.arrival_radius * 2.2, distance)
	# Allow a settled creature to stop; recover pursuit speed outside arrival.
	if distance >= preset.arrival_radius:
		desired_speed = maxf(desired_speed, 1.05)
	return (direction * desired_speed - velocity) * preset.light_weight * stimulus

func _update_arousal(index: int, field_mode: LightField.Mode, stimulus: float, mushroom_exposure: float, delta: float) -> void:
	if preset.energy_dynamics:
		var recovery_rate := maxf(0.0, preset.energy_recovery_rate)
		var total_rate := recovery_rate
		var weighted_target := recovery_rate * _individual_neutral_target(_energy_phases[index])
		var mushroom_rate := maxf(0.0, preset.mushroom_suppression_rate) * mushroom_exposure
		total_rate += mushroom_rate
		weighted_target += mushroom_rate * preset.blue_energy_target
		if field_mode == LightField.Mode.BLUE:
			var blue_rate := maxf(0.0, preset.blue_energy_response) * stimulus
			total_rate += blue_rate
			weighted_target += blue_rate * preset.blue_energy_target
		elif field_mode == LightField.Mode.ORANGE:
			var orange_rate := maxf(0.0, preset.orange_energy_response) * stimulus
			total_rate += orange_rate
			weighted_target += orange_rate * preset.orange_energy_target
		if total_rate > 0.00001:
			var target := weighted_target / total_rate
			arousals[index] = lerpf(arousals[index], target, 1.0 - exp(-delta * total_rate))
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

func _individual_neutral_target(phase: float) -> float:
	var cycle := sin(_energy_time * preset.energy_individuality_rate + phase)
	return clampf(preset.energy_neutral_target + cycle * preset.energy_individuality, 0.0, 1.0)

func _energy_mobility(energy: float) -> float:
	return smoothstep(preset.sleep_threshold, maxf(preset.sleep_threshold + 0.001, preset.energy_neutral_target), energy)

func _mushroom_exposure_at(position: Vector2) -> float:
	if preset.mushroom_radius <= 0.001:
		return 0.0
	var total := 0.0
	for center: Vector2 in mushroom_centers:
		var distance := position.distance_to(center)
		if distance < preset.mushroom_radius:
			total += 1.0 - smoothstep(preset.mushroom_radius * 0.18, preset.mushroom_radius, distance)
	return clampf(total, 0.0, 1.0)

func _mushroom_influence(position: Vector2, velocity: Vector2) -> Array:
	if not preset.energy_dynamics or mushroom_centers.is_empty() or preset.mushroom_radius <= 0.001:
		return [0.0, Vector2.ZERO]
	var total_weight := 0.0
	var weighted_center := Vector2.ZERO
	for center: Vector2 in mushroom_centers:
		var distance := position.distance_to(center)
		if distance >= preset.mushroom_radius:
			continue
		var weight := 1.0 - smoothstep(preset.mushroom_radius * 0.18, preset.mushroom_radius, distance)
		total_weight += weight
		weighted_center += center * weight
	var exposure := clampf(total_weight, 0.0, 1.0)
	if total_weight <= 0.00001:
		return [0.0, Vector2.ZERO]
	var to_center := weighted_center / total_weight - position
	var distance_to_center := to_center.length()
	if distance_to_center <= 0.001:
		return [exposure, -velocity * preset.mushroom_attraction_weight * exposure]
	var arrival := smoothstep(0.0, preset.arrival_radius * 1.5, distance_to_center)
	var desired_velocity := to_center / distance_to_center * preset.max_speed * 0.55 * arrival
	var force := (desired_velocity - velocity) * preset.mushroom_attraction_weight * exposure
	return [exposure, force]

func _obstacle_force(position: Vector2, velocity: Vector2) -> Vector2:
	var result := Vector2.ZERO
	for obstacle_index: int in obstacle_centers.size():
		var offset := position - obstacle_centers[obstacle_index]
		var distance := offset.length()
		var safe_radius := obstacle_radii[obstacle_index] + 1.25
		if distance < safe_radius and distance > 0.001:
			var urgency := 1.0 - distance / safe_radius
			result += offset.normalized() * preset.obstacle_weight * urgency * urgency
		var lookahead := position + velocity * 0.75
		var ahead_offset := lookahead - obstacle_centers[obstacle_index]
		if ahead_offset.length() < obstacle_radii[obstacle_index] + 0.62 and ahead_offset.length() > 0.001:
			result += ahead_offset.normalized() * preset.obstacle_weight * 0.75
	return result

func _boundary_force(position: Vector2) -> Vector2:
	var result := Vector2.ZERO
	if absf(position.x) > world_limit - 1.6:
		result.x = -signf(position.x) * (absf(position.x) - (world_limit - 1.6)) * 3.2
	if absf(position.y) > world_limit - 1.6:
		result.y = -signf(position.y) * (absf(position.y) - (world_limit - 1.6)) * 3.2
	return result

func _update_goal(index: int, position: Vector2, delta: float) -> void:
	if position.distance_to(goal_position) <= goal_radius:
		_goal_dwells[index] += delta
		if _goal_dwells[index] >= goal_dwell_seconds:
			lifecycles[index] = Lifecycle.COMMITTED
			lifecycle_times[index] = 0.0
			score += 1
			committed_this_step.append(index)
	else:
		_goal_dwells[index] = maxf(0.0, _goal_dwells[index] - delta * 2.0)

func _update_lifecycle(index: int, delta: float, next_positions: PackedVector2Array) -> void:
	if lifecycles[index] == Lifecycle.COMMITTED and lifecycle_times[index] >= 0.22:
		lifecycles[index] = Lifecycle.ASCENDING
		lifecycle_times[index] = 0.0
	elif lifecycles[index] == Lifecycle.ASCENDING:
		var blend := 1.0 - exp(-delta * 2.2)
		next_positions[index] = next_positions[index].lerp(goal_position, blend)
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
		if accelerations[index].length() > preset.max_acceleration + 0.001:
			return false
		if velocities[index].length() > preset.max_speed * 1.181:
			return false
	return true

# Analytic swept-circle contact: stop tunneling and slide along the trunk.
# This is collision response, separate from the bounded steering acceleration.
func _constrain_motion(start: Vector2, velocity: Vector2, delta: float) -> Array[Vector2]:
	var position := start
	var remaining := velocity * delta
	for _iteration: int in 3:
		var first_hit := 1.0
		var hit_normal := Vector2.ZERO
		var movement_sq := remaining.length_squared()
		if movement_sq < 0.00000001:
			break
		for obstacle_index: int in obstacle_centers.size():
			var offset := position - obstacle_centers[obstacle_index]
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
		position += remaining * maxf(0.0, first_hit - 0.00001)
		if hit_normal == Vector2.ZERO:
			break
		remaining *= 1.0 - first_hit
		remaining -= hit_normal * minf(remaining.dot(hit_normal), 0.0)
		velocity -= hit_normal * minf(velocity.dot(hit_normal), 0.0)
	var limit := world_limit - BODY_RADIUS
	var bounded := position.clamp(Vector2(-limit, -limit), Vector2(limit, limit))
	if bounded.x != position.x:
		velocity.x = 0.0
	if bounded.y != position.y:
		velocity.y = 0.0
	return [bounded, velocity]

# A local, optional threshold around the return circle; never attracts or scores.
# It fades inside the rim so a deliberate crossing can complete the dwell.
func _goal_resistance(position: Vector2) -> Vector2:
	var offset := position - goal_position
	var distance := offset.length()
	var outer_width := maxf(0.0, preset.goal_repulsion_outer_width)
	if distance < 0.001 or distance >= goal_radius + outer_width or outer_width <= 0.001:
		return Vector2.ZERO
	var inner := smoothstep(goal_radius - 0.8, goal_radius, distance)
	var outer := 1.0 - smoothstep(goal_radius, goal_radius + outer_width, distance)
	return offset / distance * inner * outer * preset.goal_repulsion_strength
