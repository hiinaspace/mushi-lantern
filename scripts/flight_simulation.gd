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
var goal_position := Vector2.ZERO
var goal_radius: float = 2.05
var goal_dwell_seconds: float = 0.45
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


func reset(agent_count: int, new_seed: int, new_preset: HerdPreset) -> void:
	seed_value = new_seed
	preset = new_preset.copy_preset()
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


func step(delta: float, field: LightField, social_multiplier: float = 1.0, wander_multiplier: float = 1.0) -> void:
	_energy_time += delta
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
			_update_lifecycle(index, delta, next_positions, next_velocities)
			continue
		var force := _wander_force(index, wander_multiplier)
		if preset.social_enabled:
			force += _social_force(index, old_positions, old_velocities, old_lifecycles) * social_multiplier
		var stimulus := field.sample(old_positions[index])
		exposures[index] = move_toward(exposures[index], stimulus, delta * 4.0)
		var mushroom_influence := _mushroom_influence(old_positions[index], old_velocities[index])
		mushroom_exposures[index] = mushroom_influence[0] if preset.energy_dynamics else 0.0
		_update_arousal(index, field.mode, exposures[index], mushroom_exposures[index], delta)
		force += _lantern_force(old_positions[index], old_velocities[index], field, exposures[index])
		if preset.energy_dynamics:
			var mushroom_force: Vector3 = mushroom_influence[1]
			if field.mode == LightField.Mode.ORANGE:
				mushroom_force *= 1.0 - exposures[index] * 0.85
			force += mushroom_force
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
			velocity = velocity.limit_length(preset.max_speed * lerpf(0.06, lerpf(0.88, 1.18, arousals[index]), mobility))
		else:
			velocity = velocity.limit_length(preset.max_speed * lerpf(0.88, 1.18, arousals[index]))
		accelerations[index] = applied_force
		var constrained := _constrain_motion(old_positions[index], velocity, delta)
		next_positions[index] = constrained[0]
		next_velocities[index] = constrained[1]
		_update_goal(index, next_positions[index], delta)
	positions = next_positions
	velocities = next_velocities


func _social_force(index: int, snapshot_positions: PackedVector3Array, snapshot_velocities: PackedVector3Array, snapshot_lifecycles: PackedInt32Array) -> Vector3:
	var separation := Vector3.ZERO
	var alignment := Vector3.ZERO
	var cohesion_center := Vector3.ZERO
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
		return Vector3.ZERO
	alignment = alignment / float(neighbors) - snapshot_velocities[index]
	var cohesion := (cohesion_center / float(neighbors) - snapshot_positions[index]).limit_length(1.0)
	var social_retention := 1.0 - _arousal_scatter_amount(index) * 0.82
	return separation * preset.separation_weight + (alignment * preset.alignment_weight + cohesion * preset.cohesion_weight) * social_retention


func _wander_force(index: int, multiplier: float) -> Vector3:
	var scatter := _arousal_scatter_amount(index)
	var phase := wander_phases[index] + _energy_time * (0.48 + float((index * 17) % 9) * 0.035)
	phase += scatter * (sin(_energy_time * 1.73 + _energy_phases[index] * 1.31) * 1.05 + sin(_energy_time * 0.47 + _energy_phases[index] * 2.17) * 0.62)
	var vertical := sin(_energy_time * (0.63 + float(index % 5) * 0.08) + _vertical_phases[index]) * 0.62
	# A low-frequency shared curl gives a school a coherent bend without locking individuals together.
	var flow_phase := _energy_time * 0.16 + positions[index].x * 0.035 - positions[index].z * 0.027
	var direction := Vector3(cos(phase) + sin(flow_phase) * 0.38, vertical, sin(phase) + cos(flow_phase * 1.17) * 0.38).normalized()
	return direction * preset.wander_weight * multiplier * lerpf(0.55, 1.45, arousals[index]) * (1.0 + scatter * 3.2)


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
	var center := lerpf(min_height, max_height, 0.48)
	var preferred := center + sin(_energy_time * 0.21 + _vertical_phases[index]) * (max_height - min_height) * 0.18
	return Vector3.UP * clampf((preferred - position.y) * 0.9, -1.4, 1.4)


func _goal_resistance(position: Vector3) -> Vector3:
	var offset := Vector2(position.x, position.z) - goal_position
	var distance := offset.length()
	var outer_width := maxf(0.0, preset.goal_repulsion_outer_width)
	if distance < 0.001 or distance >= goal_radius + outer_width or outer_width <= 0.001:
		return Vector3.ZERO
	var strength := smoothstep(goal_radius - 0.8, goal_radius, distance) * (1.0 - smoothstep(goal_radius, goal_radius + outer_width, distance)) * preset.goal_repulsion_strength
	return Vector3(offset.x, 0.0, offset.y).normalized() * strength


func _update_goal(index: int, position: Vector3, delta: float) -> void:
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
		if lifecycles[index] == Lifecycle.ACTIVE and velocities[index].length() > preset.max_speed * 1.181:
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
