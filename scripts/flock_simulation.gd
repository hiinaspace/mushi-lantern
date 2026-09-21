class_name FlockSimulation
extends RefCounted

enum Lifecycle { ACTIVE, COMMITTED, ASCENDING, RELEASED }

const BODY_HEIGHT := 0.42
const BODY_RADIUS := 0.22
const WORLD_LIMIT := 13.5

var seed_value: int = 40721
var preset: HerdPreset = HerdPreset.new()
var positions: PackedVector2Array = PackedVector2Array()
var previous_positions: PackedVector2Array = PackedVector2Array()
var velocities: PackedVector2Array = PackedVector2Array()
var accelerations: PackedVector2Array = PackedVector2Array()
var arousals: PackedFloat32Array = PackedFloat32Array()
var exposures: PackedFloat32Array = PackedFloat32Array()
var lifecycles: PackedInt32Array = PackedInt32Array()
var lifecycle_times: PackedFloat32Array = PackedFloat32Array()
var wander_phases: PackedFloat32Array = PackedFloat32Array()
var group_ids: PackedInt32Array = PackedInt32Array()
var goal_position := Vector2.ZERO
var goal_radius: float = 2.05
var goal_dwell_seconds: float = 0.45
var obstacle_centers: PackedVector2Array = PackedVector2Array()
var obstacle_radii: PackedFloat32Array = PackedFloat32Array()
var score: int = 0
var _last_field_mode: int = -1
var committed_this_step: PackedInt32Array = PackedInt32Array()
var _goal_dwells: PackedFloat32Array = PackedFloat32Array()

func reset(agent_count: int, new_seed: int, new_preset: HerdPreset) -> void:
	seed_value = new_seed
	preset = new_preset.copy_preset()
	positions = PackedVector2Array()
	previous_positions = PackedVector2Array()
	velocities = PackedVector2Array()
	accelerations = PackedVector2Array()
	arousals = PackedFloat32Array()
	exposures = PackedFloat32Array()
	lifecycles = PackedInt32Array()
	lifecycle_times = PackedFloat32Array()
	wander_phases = PackedFloat32Array()
	group_ids = PackedInt32Array()
	_goal_dwells = PackedFloat32Array()
	score = 0
	_last_field_mode = -1
	committed_this_step = PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	var centers: Array[Vector2] = [Vector2(-7.2, -6.6), Vector2(7.3, -6.0), Vector2(7.7, 6.8)]
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
		arousals.append(preset.baseline_arousal)
		exposures.append(0.0)
		lifecycles.append(Lifecycle.ACTIVE)
		lifecycle_times.append(0.0)
		wander_phases.append(rng.randf_range(0.0, TAU))
		group_ids.append(group)
		_goal_dwells.append(0.0)

func step(delta: float, field: LightField, social_multiplier: float = 1.0, wander_multiplier: float = 1.0) -> void:
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
		_update_arousal(index, field.mode, exposures[index], delta)
		force += _lantern_force(index, old_positions[index], old_velocities[index], field, exposures[index])
		force += _boundary_force(old_positions[index])
		force += _goal_resistance(old_positions[index])
		# Reserve the steering budget for avoidance before behavioral forces.
		var avoidance := _obstacle_force(old_positions[index], old_velocities[index]).limit_length(preset.max_acceleration)
		force = avoidance + force.limit_length(maxf(0.0, preset.max_acceleration - avoidance.length()))
		accelerations[index] = force
		var activity_scale := lerpf(0.88, 1.18, arousals[index])
		var velocity := (old_velocities[index] + force * delta).limit_length(preset.max_speed * activity_scale)
		if velocity.length_squared() < 0.014:
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
	return separation * preset.separation_weight + alignment * preset.alignment_weight + cohesion * preset.cohesion_weight

func _wander_force(index: int, delta: float, multiplier: float) -> Vector2:
	var phase_speed := 0.52 + float((index * 17) % 9) * 0.035
	wander_phases[index] = fmod(wander_phases[index] + delta * phase_speed, TAU)
	var direction := Vector2(cos(wander_phases[index]), sin(wander_phases[index]))
	return direction * preset.wander_weight * multiplier * lerpf(0.55, 1.45, arousals[index])

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

func _update_arousal(index: int, field_mode: LightField.Mode, stimulus: float, delta: float) -> void:
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
	if absf(position.x) > WORLD_LIMIT - 1.6:
		result.x = -signf(position.x) * (absf(position.x) - (WORLD_LIMIT - 1.6)) * 3.2
	if absf(position.y) > WORLD_LIMIT - 1.6:
		result.y = -signf(position.y) * (absf(position.y) - (WORLD_LIMIT - 1.6)) * 3.2
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
	var limit := WORLD_LIMIT - BODY_RADIUS
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
	if distance < 0.001 or distance >= goal_radius + 1.8:
		return Vector2.ZERO
	var inner := smoothstep(goal_radius - 0.8, goal_radius, distance)
	var outer := 1.0 - smoothstep(goal_radius, goal_radius + 1.8, distance)
	return offset / distance * inner * outer * preset.goal_repulsion_strength
