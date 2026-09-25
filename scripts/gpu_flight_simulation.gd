class_name GpuFlightSimulation
extends FlightSimulation

## Experimental main-RenderingDevice flight backend. Instance index remains the
## durable agent ID. The CPU arrays are delayed snapshots for UI/networking;
## drawing reads the GPU-owned three-row state_texture instead.

const STATE_WORDS := 24 # six vec4 values per creature
const PARAM_WORDS := 128
const MAX_AGENTS := 2048
const GRID_SIDE := 32
const MAX_OBSTACLES := 16
const MAX_MUSHROOMS := 32
const MAX_TERRAIN_OBSTACLES := 1024
const OBSTACLE_GRID_SIDE := 32
const OBSTACLES_PER_CELL := 64
const SHADER_PATH := "res://shaders/flight_compute.glsl"

var state_texture: Texture2DRD = Texture2DRD.new()
var state_revision: int = 0
var gpu_ready: bool = false
var gpu_error: String = ""
var snapshot_revision: int = -1
var snapshot_interval: float = 0.12

# Optional diagnostics; never infer GPU work from CPU submission duration.
signal gpu_timing_sample(milliseconds: float)
signal gpu_phase_timing_sample(build_ms: float, simulate_ms: float)
signal snapshot_applied(milliseconds: float)
var profile_gpu: bool = false
var snapshot_apply_ms: float = 0.0
var _timing_frame: int = -1

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _state_buffers: Array[RID] = []
var _params_buffer: RID
var _events_buffer: RID
var _traits_buffer: RID
var _sources_buffer: RID
var _cell_counts_buffer: RID
var _cell_ids_buffer: RID
var _formation_choices_buffer: RID
var _height_texture: RID
var _terrain_obstacles_buffer: RID
var _obstacle_index_buffer: RID
var _environment: RefCounted
var _terrain_obstacle_count: int = 0
var _terrain_obstacle_bytes := PackedByteArray()
var _obstacle_index_bytes := PackedByteArray()
var _height_bytes := PackedByteArray()
var _height_side: int = 1
var _terrain_peak_height: float = 0.0
var _environment_error: String = ""
var _texture: RID
var _uniform_sets: Array[RID] = []
var _read_slot: int = 0
var _epoch: int = 0
var _pending_readback: bool = false
var _snapshot_clock: float = 0.0
var _gpu_time: float = 0.0
var _initialized_count: int = 0
var _committed_ids: Dictionary = {}
var _last_gpu_field_mode: int = -1


func configure_environment(surface: RefCounted) -> void:
	# The surface is immutable for a running population. Call reset after changing it.
	_environment = surface
	_terrain_obstacle_count = 0
	_environment_error = ""
	if surface == null:
		_height_side = 1
		_terrain_peak_height = 0.0
		var flat := Image.create(1, 1, false, Image.FORMAT_RF)
		flat.set_pixel(0, 0, Color(0.0, 0.0, 0.0))
		_height_bytes = flat.get_data()
		_terrain_obstacle_bytes = PackedFloat32Array().to_byte_array()
		_obstacle_index_bytes = PackedInt32Array().to_byte_array()
		return
	var image: Image = surface.get_height_image()
	_height_side = image.get_width()
	_height_bytes = image.get_data()
	_terrain_peak_height = -INF
	for height: float in surface.height_samples:
		_terrain_peak_height = maxf(_terrain_peak_height, height)
	var obstacles: Array[Dictionary] = surface.get_obstacles()
	if obstacles.size() > MAX_TERRAIN_OBSTACLES:
		_environment_error = "Terrain has %d coarse obstacles; GPU capacity is %d" % [obstacles.size(), MAX_TERRAIN_OBSTACLES]
		push_error(_environment_error)
		return
	_terrain_obstacle_count = obstacles.size()
	var records := PackedFloat32Array()
	records.resize(MAX_TERRAIN_OBSTACLES * 8)
	var index := PackedInt32Array()
	index.resize(OBSTACLE_GRID_SIDE * OBSTACLE_GRID_SIDE * (OBSTACLES_PER_CELL + 1))
	var cell_size := float(surface.size_m) / float(OBSTACLE_GRID_SIDE)
	for i: int in obstacles.size():
		var record: Dictionary = obstacles[i]
		var center: Vector2 = record.center
		var radius: float = record.radius
		var k := i * 8
		records[k] = center.x
		records[k + 1] = center.y
		records[k + 2] = radius
		records[k + 3] = record.bottom
		records[k + 4] = record.top
		# Insert across covered cells, including flight lookahead and body clearance.
		var reach := radius + 1.8
		var low := Vector2i(clampi(floori((center.x - reach + surface.size_m * 0.5) / cell_size), 0, OBSTACLE_GRID_SIDE - 1), clampi(floori((center.y - reach + surface.size_m * 0.5) / cell_size), 0, OBSTACLE_GRID_SIDE - 1))
		var high := Vector2i(clampi(floori((center.x + reach + surface.size_m * 0.5) / cell_size), 0, OBSTACLE_GRID_SIDE - 1), clampi(floori((center.y + reach + surface.size_m * 0.5) / cell_size), 0, OBSTACLE_GRID_SIDE - 1))
		for z: int in range(low.y, high.y + 1):
			for x: int in range(low.x, high.x + 1):
				var base := (z * OBSTACLE_GRID_SIDE + x) * (OBSTACLES_PER_CELL + 1)
				var count := index[base]
				if count >= OBSTACLES_PER_CELL:
					_environment_error = "Terrain obstacle cell %d,%d exceeds %d proxies" % [x, z, OBSTACLES_PER_CELL]
					push_error(_environment_error)
					continue
				index[base] = count + 1
				index[base + 1 + count] = i
	_terrain_obstacle_bytes = records.to_byte_array()
	_obstacle_index_bytes = index.to_byte_array()


func reset(agent_count: int, new_seed: int, new_preset: HerdPreset) -> void:
	# A fixed-size population avoids rendering a texture still referenced by a
	# previous frame. RenderingServer owns the actual RID lifetime.
	dispose()
	super.reset(agent_count, new_seed, new_preset)
	if _height_bytes.is_empty():
		configure_environment(null)
	if _environment != null:
		for i: int in positions.size():
			var at := positions[i]
			at.y += _environment.get_height_at(Vector2(at.x, at.z))
			positions[i] = at
			previous_positions[i] = at
		_distribute_terrain_spawn(new_seed)
	if agent_count < 1 or agent_count > MAX_AGENTS:
		gpu_error = "GPU flight supports 1–2048 agents"
		return
	if not _environment_error.is_empty():
		gpu_error = _environment_error
		return
	if obstacle_centers.size() > MAX_OBSTACLES or mushroom_centers.size() > MAX_MUSHROOMS:
		gpu_error = "GPU flight fixture exceeds the bounded source count"
		return
	var shader_file: RDShaderFile = load(SHADER_PATH)
	if shader_file == null:
		gpu_error = "GPU flight compute shader did not import"
		return
	var spirv := shader_file.get_spirv()
	if spirv == null or not spirv.compile_error_compute.is_empty():
		gpu_error = "GPU flight shader compile: %s" % ("no SPIR-V" if spirv == null else spirv.compile_error_compute)
		return
	_initialized_count = agent_count
	_committed_ids.clear()
	_gpu_time = 0.0
	_snapshot_clock = 0.0
	_last_gpu_field_mode = -1
	gpu_error = ""
	var initial := _encode_initial_state()
	var traits := _encode_traits()
	var pixels := _encode_initial_texture()
	var epoch := _epoch
	RenderingServer.call_on_render_thread(_create_gpu.bind(epoch, spirv, initial, traits, pixels, agent_count))


func _distribute_terrain_spawn(new_seed: int) -> void:
	# Preserve stable IDs and base trait seeding. Every tenth agent is a free,
	# initially awake flyer; the rest remain evenly assigned to authored patches.
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed ^ 0x53704157
	var obstacles: Array[Dictionary] = _environment.get_obstacles()
	var centers := spawn_centers if not spawn_centers.is_empty() else PackedVector2Array(DEFAULT_SPAWN_CENTERS)
	var half: float = _environment.size_m * 0.5
	var patch_ordinal := 0
	for i: int in positions.size():
		if i % 10 == 9:
			var found := false
			for attempt: int in 128:
				var candidate := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
				if not _environment.is_playable(candidate, 5.0):
					continue
				if candidate.distance_to(goal_position) < goal_radius + 3.0:
					continue
				var near_patch := false
				for center: Vector2 in centers:
					if candidate.distance_to(center) < maxf(5.0, preset.mushroom_radius + 2.0):
						near_patch = true
						break
				if near_patch:
					continue
				var blocked := false
				for obstacle: Dictionary in obstacles:
					if candidate.distance_to(obstacle.center) < float(obstacle.radius) + 0.45:
						blocked = true
						break
				if blocked:
					continue
				var at := positions[i]
				at.x = candidate.x
				at.z = candidate.y
				at.y = _environment.get_height_at(candidate) + rng.randf_range(0.8, 1.5)
				positions[i] = at
				previous_positions[i] = at
				group_ids[i] = -1
				found = true
				break
			if not found:
				_environment_error = "Could not place free terrain agent %d away from patches and props" % i
				return
			mushroom_exposures[i] = 0.0
			arousals[i] = clampf(maxf(preset.energy_neutral_target, preset.sleep_threshold + 0.18), 0.0, 1.0)
		else:
			# Free-ID selection has a period of ten. Assign patches from a
			# separate ordinal so 18 patches do not favor odd-numbered groups.
			var group := patch_ordinal % centers.size()
			patch_ordinal += 1
			var previous_group: int = group_ids[i]
			var at := positions[i]
			var offset := Vector2(at.x, at.z) - centers[previous_group]
			var xz := centers[group] + offset
			var previous_ground: float = _environment.get_height_at(Vector2(at.x, at.z))
			at = Vector3(xz.x, _environment.get_height_at(xz) + at.y - previous_ground, xz.y)
			positions[i] = at
			previous_positions[i] = at
			group_ids[i] = group
			if preset.energy_dynamics:
				var exposure := _terrain_mushroom_exposure(at)
				mushroom_exposures[i] = exposure
				arousals[i] = clampf(lerpf(_individual_neutral_target(_energy_phases[i]), preset.blue_energy_target, smoothstep(0.0, 0.7, exposure)), 0.0, 1.0)


func _terrain_mushroom_exposure(position: Vector3) -> float:
	if preset.mushroom_radius <= 0.001:
		return 0.0
	var total := 0.0
	for center: Vector2 in mushroom_centers:
		var cap := Vector3(center.x, _environment.get_height_at(center) + 0.45, center.y)
		var distance := position.distance_to(cap)
		if distance < preset.mushroom_radius:
			total += 1.0 - smoothstep(preset.mushroom_radius * 0.18, preset.mushroom_radius, distance)
	return clampf(total, 0.0, 1.0)


func dispose() -> void:
	_epoch += 1
	gpu_ready = false
	state_revision = 0
	snapshot_revision = -1
	_pending_readback = false
	state_texture.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_dispose_gpu)


func is_finite_and_bounded() -> bool:
	if _environment == null:
		return super.is_finite_and_bounded()
	for i: int in positions.size():
		var at := positions[i]
		if not at.is_finite() or not velocities[i].is_finite() or not is_finite(arousals[i]):
			return false
		if arousals[i] < 0.0 or arousals[i] > 1.0:
			return false
		if absf(at.x) > world_limit + 0.01 or absf(at.z) > world_limit + 0.01:
			return false
		if lifecycles[i] == Lifecycle.ACTIVE:
			var ground: float = _environment.get_height_at(Vector2(at.x, at.z))
			if at.y < ground + min_height - 0.02 or at.y > _terrain_peak_height + max_height + 8.02:
				return false
	return true


func step(delta: float, field: LightField, social_multiplier: float = 1.0, wander_multiplier: float = 1.0) -> void:
	if not gpu_ready:
		return
	_sync_flight_height()
	_gpu_time += delta
	var params := _encode_params(delta, field, social_multiplier, wander_multiplier)
	params.encode_float(73 * 4, 1.0 if preset.formation_follow_weight > 0.0 and state_revision % 6 == 0 else 0.0)
	var sources := _encode_sources(field)
	params.encode_float(67 * 4, 1.0 if _last_gpu_field_mode != field.mode else 0.0)
	_last_gpu_field_mode = field.mode
	var epoch := _epoch
	RenderingServer.call_on_render_thread(_dispatch.bind(epoch, params, sources))
	state_revision += 1
	_snapshot_clock += delta
	if _snapshot_clock >= snapshot_interval and not _pending_readback:
		_snapshot_clock = 0.0
		_pending_readback = true
		RenderingServer.call_on_render_thread(_request_readback.bind(epoch, state_revision))


func request_snapshot() -> void:
	if gpu_ready and not _pending_readback:
		_pending_readback = true
		RenderingServer.call_on_render_thread(_request_readback.bind(_epoch, state_revision))


func _encode_initial_state() -> PackedByteArray:
	var floats := PackedFloat32Array()
	floats.resize(positions.size() * STATE_WORDS)
	for i: int in positions.size():
		var k := i * STATE_WORDS
		floats[k] = positions[i].x
		floats[k + 1] = positions[i].y
		floats[k + 2] = positions[i].z
		floats[k + 3] = arousals[i]
		floats[k + 4] = velocities[i].x
		floats[k + 5] = velocities[i].y
		floats[k + 6] = velocities[i].z
		floats[k + 7] = exposures[i]
		floats[k + 8] = float(lifecycles[i])
		floats[k + 9] = _goal_dwells[i]
		floats[k + 10] = lifecycle_times[i]
		floats[k + 11] = _wake_remaining[i]
		floats[k + 12] = _energy_phases[i]
		floats[k + 13] = wander_phases[i]
		floats[k + 14] = _vertical_phases[i]
		floats[k + 15] = _wake_waits[i]
		floats[k + 16] = float(_wake_cycles[i])
		floats[k + 17] = mushroom_exposures[i]
		floats[k + 18] = 0.0
		floats[k + 19] = 0.0
		var heading := velocities[i]
		heading = heading.normalized() if heading.length_squared() > 0.0001 else Vector3.FORWARD
		floats[k + 20] = heading.x
		floats[k + 21] = heading.y
		floats[k + 22] = heading.z
		floats[k + 23] = 0.0
	return floats.to_byte_array()


func _encode_traits() -> PackedByteArray:
	var floats := PackedFloat32Array()
	floats.resize(positions.size() * 8)
	for i: int in positions.size():
		var k := i * 8
		floats[k] = float(trait_types[i])
		floats[k + 1] = trait_sizes[i]
		floats[k + 2] = speed_factors[i]
		floats[k + 3] = cohesion_factors[i]
		floats[k + 4] = alignment_factors[i]
		floats[k + 5] = lantern_response_factors[i]
		floats[k + 6] = mushroom_response_factors[i]
		floats[k + 7] = _neutral_offsets[i]
	return floats.to_byte_array()


func _encode_initial_texture() -> PackedByteArray:
	var pixels := PackedFloat32Array()
	pixels.resize(positions.size() * 3 * 4)
	for row: int in 3:
		for i: int in positions.size():
			var k := (row * positions.size() + i) * 4
			if row == 2:
				var heading := velocities[i]
				heading = heading.normalized() if heading.length_squared() > 0.0001 else Vector3.FORWARD
				pixels[k] = heading.x
				pixels[k + 1] = heading.y
				pixels[k + 2] = heading.z
			else:
				pixels[k] = positions[i].x
				pixels[k + 1] = positions[i].y
				pixels[k + 2] = positions[i].z
				pixels[k + 3] = arousals[i]
	return pixels.to_byte_array()


func _encode_params(delta: float, field: LightField, social_multiplier: float, wander_multiplier: float) -> PackedByteArray:
	var p := PackedFloat32Array()
	p.resize(PARAM_WORDS)
	p[0] = float(positions.size())
	p[1] = delta
	p[2] = _gpu_time
	p[3] = float(field.mode)
	p[4] = field.source_position.x
	p[5] = field.source_position.y
	p[6] = field.source_position.z
	p[7] = field.range_m
	p[8] = field.source_direction.x
	p[9] = field.source_direction.y
	p[10] = field.source_direction.z
	p[11] = field.half_angle_degrees
	p[12] = field.edge_softness
	p[13] = field.mode_strength * field.shutter_openness
	p[14] = social_multiplier
	p[15] = wander_multiplier
	p[16] = preset.max_speed
	p[17] = preset.max_acceleration
	p[18] = preset.neighbor_radius
	p[19] = preset.separation_radius
	p[20] = preset.separation_weight
	p[21] = preset.alignment_weight
	p[22] = preset.cohesion_weight
	p[23] = preset.wander_weight
	p[24] = preset.light_weight
	p[25] = preset.obstacle_weight
	p[26] = preset.arrival_radius
	p[27] = preset.goal_repulsion_strength
	p[28] = preset.goal_repulsion_outer_width
	p[29] = preset.baseline_arousal
	p[30] = preset.arousal_response
	p[31] = 1.0 if preset.energy_dynamics else 0.0
	p[32] = preset.energy_neutral_target
	p[33] = preset.energy_recovery_rate
	p[34] = preset.energy_individuality
	p[35] = preset.energy_individuality_rate
	p[36] = preset.mushroom_radius
	p[37] = preset.mushroom_attraction_weight
	p[38] = preset.mushroom_suppression_rate
	p[39] = preset.blue_energy_target
	p[40] = preset.blue_energy_response
	p[41] = preset.orange_energy_target
	p[42] = preset.orange_energy_response
	p[43] = preset.sleep_threshold
	p[44] = preset.sleep_velocity_damping
	p[45] = preset.arousal_scatter_strength
	p[46] = preset.population_variation
	p[47] = preset.arousal_contagion_strength
	p[48] = 1.0 if preset.spontaneous_waking_enabled else 0.0
	p[49] = preset.spontaneous_wake_min_seconds
	p[50] = preset.spontaneous_wake_max_seconds
	p[51] = preset.spontaneous_wake_duration
	p[52] = preset.spontaneous_wake_energy
	p[53] = float(preset.max_social_neighbors)
	p[54] = 1.0 if preset.social_enabled else 0.0
	p[55] = 1.0 if preset.arousal_memory else 0.0
	p[56] = world_limit
	p[57] = min_height
	p[58] = max_height
	p[59] = goal_position.x
	p[60] = goal_position.y
	p[61] = goal_radius
	p[62] = goal_dwell_seconds
	p[63] = float(seed_value)
	p[64] = float(mini(obstacle_centers.size(), MAX_OBSTACLES))
	p[65] = float(mini(mushroom_centers.size(), MAX_MUSHROOMS))
	p[66] = float(mini(field.obstacle_centers.size(), MAX_OBSTACLES))
	# A 32×32 address space covers signed cells [-15, 14] at the
	# smallest supported bucket width. Ordinary living-shoal radius 3.6 m
	# is unchanged; smaller tuned radii use coarser candidate buckets.
	var cell_size := maxf(maxf(0.25, preset.neighbor_radius), world_limit / 15.0)
	p[68] = cell_size
	p[69] = float(clampi(ceili(world_limit / cell_size), 1, 15))
	p[70] = preset.formation_follow_weight
	p[71] = preset.cluster_pressure_weight
	p[72] = float(preset.cluster_target_neighbors)
	p[73] = 0.0
	p[74] = 1.0 if _environment != null else 0.0
	p[75] = float(_environment.size_m) if _environment != null else 1.0
	p[76] = float(_terrain_obstacle_count)
	p[77] = _terrain_peak_height + max_height + 8.0
	# p[78] is reserved for tutorial-controlled goal acceptance.
	p[78] = 1.0 if goal_accepting else 0.0
	# Sources live in separate, fixed-size GPU storage buffer and can be moved
	# without rebuilding pipeline/uniform sets.
	return p.to_byte_array()


func _encode_sources(field: LightField) -> PackedByteArray:
	var p := PackedFloat32Array()
	p.resize(4 * (MAX_OBSTACLES * 2 + MAX_MUSHROOMS))
	for i: int in mini(obstacle_centers.size(), MAX_OBSTACLES):
		p[4 * i] = obstacle_centers[i].x
		p[4 * i + 1] = obstacle_centers[i].y
		p[4 * i + 2] = obstacle_radii[i]
	for i: int in mini(field.obstacle_centers.size(), MAX_OBSTACLES):
		var k := 4 * (MAX_OBSTACLES + i)
		p[k] = field.obstacle_centers[i].x
		p[k + 1] = field.obstacle_centers[i].y
		p[k + 2] = field.obstacle_radii[i]
	for i: int in mini(mushroom_centers.size(), MAX_MUSHROOMS):
		var k := 4 * (MAX_OBSTACLES * 2 + i)
		p[k] = mushroom_centers[i].x
		p[k + 1] = mushroom_centers[i].y
	return p.to_byte_array()


func _create_gpu(epoch: int, spirv: RDShaderSPIRV, initial: PackedByteArray, traits: PackedByteArray, pixels: PackedByteArray, count: int) -> void:
	if epoch != _epoch:
		return
	_read_slot = 0
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		call_deferred("_creation_failed", epoch, "No global RenderingDevice (Compatibility renderer?)")
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		call_deferred("_creation_failed", epoch, "Could not create compute shader")
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		call_deferred("_creation_failed", epoch, "Could not create compute pipeline")
		return
	_state_buffers = [_rd.storage_buffer_create(initial.size(), initial), _rd.storage_buffer_create(initial.size(), initial)]
	_params_buffer = _rd.storage_buffer_create(PARAM_WORDS * 4, PackedByteArray())
	var zero_events := PackedByteArray()
	zero_events.resize(count * 4)
	zero_events.fill(0)
	_events_buffer = _rd.storage_buffer_create(count * 4, zero_events)
	_traits_buffer = _rd.storage_buffer_create(count * 8 * 4, traits)
	_sources_buffer = _rd.storage_buffer_create((MAX_OBSTACLES * 2 + MAX_MUSHROOMS) * 16, PackedByteArray())
	_cell_counts_buffer = _rd.storage_buffer_create(GRID_SIDE * GRID_SIDE * 4, PackedByteArray())
	_cell_ids_buffer = _rd.storage_buffer_create(GRID_SIDE * GRID_SIDE * MAX_AGENTS * 4, PackedByteArray())
	_formation_choices_buffer = _rd.storage_buffer_create(count * 8, PackedByteArray())
	_terrain_obstacles_buffer = _rd.storage_buffer_create(MAX_TERRAIN_OBSTACLES * 8 * 4, _terrain_obstacle_bytes if not _terrain_obstacle_bytes.is_empty() else PackedByteArray())
	_obstacle_index_buffer = _rd.storage_buffer_create(OBSTACLE_GRID_SIDE * OBSTACLE_GRID_SIDE * (OBSTACLES_PER_CELL + 1) * 4, _obstacle_index_bytes if not _obstacle_index_bytes.is_empty() else PackedByteArray())
	var height_format := RDTextureFormat.new()
	height_format.width = _height_side
	height_format.height = _height_side
	height_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	height_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	_height_texture = _rd.texture_create(height_format, RDTextureView.new(), [_height_bytes])
	if not _height_texture.is_valid():
		call_deferred("_creation_failed", epoch, "Could not create terrain height texture")
		return
	var texture_format := RDTextureFormat.new()
	texture_format.width = count
	texture_format.height = 3
	texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_texture = _rd.texture_create(texture_format, RDTextureView.new(), [pixels])
	if not _texture.is_valid():
		call_deferred("_creation_failed", epoch, "Could not create state texture")
		return
	for read: int in 2:
		var uniforms: Array[RDUniform] = []
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, _state_buffers[read]))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, _state_buffers[1 - read]))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, _params_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 3, _traits_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 4, _events_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, _sources_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 6, _texture))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 7, _cell_counts_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 8, _cell_ids_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 9, _formation_choices_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 10, _height_texture))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 11, _terrain_obstacles_buffer))
		uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 12, _obstacle_index_buffer))
		_uniform_sets.append(_rd.uniform_set_create(uniforms, _shader, 0))
		if not _uniform_sets[-1].is_valid():
			call_deferred("_creation_failed", epoch, "Could not create compute uniform set")
			return
	call_deferred("_creation_ready", epoch, _texture)


func _uniform(kind: int, binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = kind
	u.binding = binding
	u.add_id(rid)
	return u


func _creation_ready(epoch: int, texture_rid: RID) -> void:
	if epoch != _epoch:
		return
	state_texture.texture_rd_rid = texture_rid
	gpu_ready = true
	gpu_error = ""


func _creation_failed(epoch: int, message: String) -> void:
	if epoch != _epoch:
		return
	gpu_error = message
	gpu_ready = false
	push_error(message)


func _dispatch(epoch: int, params: PackedByteArray, sources: PackedByteArray) -> void:
	if epoch != _epoch or _rd == null or not _pipeline.is_valid():
		return
	if profile_gpu:
		_collect_gpu_timing(epoch)
		_rd.capture_timestamp(_timing_prefix(epoch) + "begin")
	_rd.buffer_update(_params_buffer, 0, params.size(), params)
	_rd.buffer_update(_sources_buffer, 0, sources.size(), sources)
	var compute := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute, _pipeline)
	_rd.compute_list_bind_uniform_set(compute, _uniform_sets[_read_slot], 0)
	if _initialized_count > 64:
		var build_phase := PackedByteArray()
		build_phase.resize(4)
		build_phase.encode_u32(0, 0)
		_rd.compute_list_set_push_constant(compute, build_phase, 4)
		var cell_radius := roundi(params.decode_float(69 * 4))
		var cell_count := cell_radius * cell_radius * 4
		_rd.compute_list_dispatch(compute, ceili(float(cell_count) / 64.0), 1, 1)
		_rd.compute_list_add_barrier(compute)
		if profile_gpu:
			_rd.capture_timestamp(_timing_prefix(epoch) + "buildend")
	if params.decode_float(73 * 4) > 0.5:
		var match_phase := PackedByteArray()
		match_phase.resize(4)
		match_phase.encode_u32(0, 1)
		_rd.compute_list_set_push_constant(compute, match_phase, 4)
		_rd.compute_list_dispatch(compute, ceili(float(_initialized_count) / 64.0), 1, 1)
		_rd.compute_list_add_barrier(compute)
	var simulate_phase := PackedByteArray()
	simulate_phase.resize(4)
	simulate_phase.encode_u32(0, 2)
	_rd.compute_list_set_push_constant(compute, simulate_phase, 4)
	_rd.compute_list_dispatch(compute, ceili(float(_initialized_count) / 64.0), 1, 1)
	_rd.compute_list_end()
	if profile_gpu:
		_rd.capture_timestamp(_timing_prefix(epoch) + "end")
	_read_slot = 1 - _read_slot


func _timing_prefix(epoch: int) -> String:
	return "mushi_%d_%d_" % [get_instance_id(), epoch]


func _collect_gpu_timing(epoch: int) -> void:
	var captured_frame := _rd.get_captured_timestamps_frame()
	if captured_frame == _timing_frame:
		return
	_timing_frame = captured_frame
	var prefix := _timing_prefix(epoch)
	var begin: int = -1
	var buildend: int = -1
	for i: int in _rd.get_captured_timestamps_count():
		var marker := _rd.get_captured_timestamp_name(i)
		if marker == prefix + "begin":
			begin = _rd.get_captured_timestamp_gpu_time(i)
		elif marker == prefix + "buildend" and begin >= 0:
			buildend = _rd.get_captured_timestamp_gpu_time(i)
		elif marker == prefix + "end" and begin >= 0:
			var end := _rd.get_captured_timestamp_gpu_time(i)
			# Pinned ed1daf0bf Vulkan implementation returns nanoseconds, despite
			# the online class reference describing these as microseconds.
			if end >= begin:
				call_deferred("_publish_gpu_timing", epoch, float(end - begin) / 1000000.0)
				if buildend >= begin and end >= buildend:
					call_deferred("_publish_phase_timing", epoch, float(buildend - begin) / 1000000.0, float(end - buildend) / 1000000.0)
			begin = -1
			buildend = -1


func _publish_gpu_timing(epoch: int, milliseconds: float) -> void:
	if epoch == _epoch:
		gpu_timing_sample.emit(milliseconds)


func _publish_phase_timing(epoch: int, build_ms: float, simulate_ms: float) -> void:
	if epoch == _epoch:
		gpu_phase_timing_sample.emit(build_ms, simulate_ms)


func _request_readback(epoch: int, revision: int) -> void:
	if epoch != _epoch or _rd == null:
		return
	var selected := _state_buffers[_read_slot]
	_rd.buffer_get_data_async(selected, _state_readback.bind(epoch, revision))
	_rd.buffer_get_data_async(_events_buffer, _events_readback.bind(epoch))


func _state_readback(bytes: PackedByteArray, epoch: int, revision: int) -> void:
	call_deferred("_apply_state_readback", bytes, epoch, revision)


func _events_readback(bytes: PackedByteArray, epoch: int) -> void:
	call_deferred("_apply_events_readback", bytes, epoch)


func _apply_state_readback(bytes: PackedByteArray, epoch: int, revision: int) -> void:
	if epoch != _epoch:
		return
	_pending_readback = false
	if bytes.size() != _initialized_count * STATE_WORDS * 4:
		gpu_error = "GPU snapshot has unexpected size"
		return
	var started := Time.get_ticks_usec()
	var values := bytes.to_float32_array()
	for i: int in _initialized_count:
		var k := i * STATE_WORDS
		positions[i] = Vector3(values[k], values[k + 1], values[k + 2])
		arousals[i] = values[k + 3]
		velocities[i] = Vector3(values[k + 4], values[k + 5], values[k + 6])
		exposures[i] = values[k + 7]
		lifecycles[i] = roundi(values[k + 8])
		_goal_dwells[i] = values[k + 9]
		lifecycle_times[i] = values[k + 10]
		_wake_remaining[i] = values[k + 11]
		_wake_waits[i] = values[k + 15]
		_wake_cycles[i] = roundi(values[k + 16])
		mushroom_exposures[i] = values[k + 17]
		formation_predecessors[i] = roundi(values[k + 18]) - 1
		formation_successors[i] = roundi(values[k + 19]) - 1
	snapshot_revision = revision
	snapshot_apply_ms = float(Time.get_ticks_usec() - started) / 1000.0
	snapshot_applied.emit(snapshot_apply_ms)


func _apply_events_readback(bytes: PackedByteArray, epoch: int) -> void:
	if epoch != _epoch or bytes.size() != _initialized_count * 4:
		return
	var events := bytes.to_int32_array()
	committed_this_step = PackedInt32Array()
	for i: int in _initialized_count:
		if events[i] != 0 and not _committed_ids.has(i):
			_committed_ids[i] = true
			committed_this_step.append(i)
			score += 1


func _free_gpu(rd: RenderingDevice, shader: RID, pipeline: RID, states: Array, params: RID, events: RID, traits: RID, sources: RID, counts: RID, cell_ids: RID, choices: RID, texture: RID, height_texture: RID, terrain_obstacles: RID, obstacle_index: RID, sets: Array) -> void:
	for rid: RID in sets:
		if rid.is_valid(): rd.free_rid(rid)
	for rid: RID in states:
		if rid.is_valid(): rd.free_rid(rid)
	for rid: RID in [params, events, traits, sources, counts, cell_ids, choices, texture, height_texture, terrain_obstacles, obstacle_index, pipeline, shader]:
		if rid.is_valid(): rd.free_rid(rid)


func _dispose_gpu() -> void:
	if _rd == null:
		return
	_free_gpu(_rd, _shader, _pipeline, _state_buffers, _params_buffer, _events_buffer, _traits_buffer, _sources_buffer, _cell_counts_buffer, _cell_ids_buffer, _formation_choices_buffer, _texture, _height_texture, _terrain_obstacles_buffer, _obstacle_index_buffer, _uniform_sets)
	_rd = null
	_shader = RID()
	_pipeline = RID()
	_state_buffers.clear()
	_params_buffer = RID()
	_events_buffer = RID()
	_traits_buffer = RID()
	_sources_buffer = RID()
	_cell_counts_buffer = RID()
	_cell_ids_buffer = RID()
	_formation_choices_buffer = RID()
	_texture = RID()
	_height_texture = RID()
	_terrain_obstacles_buffer = RID()
	_obstacle_index_buffer = RID()
	_uniform_sets.clear()
