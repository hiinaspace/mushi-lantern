class_name GroveAudio
extends Node3D

## Direct-HRTF, fixed-size source pool. Simulation indices are durable IDs.
const MUSHI_CAP := 12
const FOREST_CAP := 6
const TOOL_CAP := 4
const STEP_CAP := 2
const AUDIBLE_RADIUS := 10.0
const RELEASE_RADIUS := 12.0
const STALE_SECONDS := 0.55
const HOLD_SECONDS := 4.0
const FADE_RATE := 5.0
const AUDIO := "res://assets/audio/placeholders/"
const FIELD_AUDIO := "res://assets/audio/field/"
const FILTER_TRANSIENTS := ["lantern_shutter_variant_a", "lantern_shutter_variant_b", "lantern_shutter_open", "lantern_shutter_variant_c", "lantern_shutter_close"]

var mushi_limit := 6
var forest_limit := 3
var tool_limit := TOOL_CAP
var step_limit := STEP_CAP

var _simulation: FlightSimulation
var _surface: EnvironmentSurface
var _staff: Variant
var _desktop: DesktopPlayer
var _xr: Variant
var _listener_camera: Camera3D
var _listener: Node3D
var _config: Node
var _stress_active := false
var _enabled := false
var _clock := 0.0
var _last_snapshot := -100.0
var _revision := -1
var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _mushi: Array[Dictionary] = []
var _forest: Array[Dictionary] = []
var _tool: Array[Dictionary] = []
var _steps: Array[Dictionary] = []
var _last_head := Vector3.ZERO
var _last_swing_local := Vector3.ZERO
var _staff_speed := 0.0
var _last_shutter := -1.0
var _last_requested_mode := -1
var _shutter_quiet_time := 1.0
var _filter_cooldown := 0.0
var _filter_transition_was_active := false
var _filter_variant := 0
var _forest_sites: Array[Vector3] = []


func _ready() -> void:
	_rng.seed = 514933
	var disabled := OS.get_environment("MUSHI_AUDIO_DISABLED") == "1"
	_enabled = not disabled and ClassDB.class_exists("SteamAudioPlayer")
	if not _enabled:
		if not disabled:
			push_warning("GroveAudio: SteamAudioPlayer is unavailable; sound cues disabled")
		return
	if ClassDB.class_exists("SteamAudioConfig"):
		_config = ClassDB.instantiate("SteamAudioConfig")
		_config.name = "SteamAudioConfig"
		add_child(_config)
	_load_streams()
	for bus_name: String in ["Mushi", "Forest", "Tool", "Steps"]:
		_ensure_bus(bus_name)
	_mushi = _make_pool("Mushi", MUSHI_CAP)
	_forest = _make_pool("Forest", FOREST_CAP)
	_tool = _make_pool("Tool", TOOL_CAP)
	_steps = _make_pool("Footstep", STEP_CAP)
	if _listener_camera != null:
		set_listener_camera(_listener_camera)


func configure(simulation: Variant, world_surface: EnvironmentSurface, staff_tool: Variant, desktop_player: DesktopPlayer, xr_player: Variant) -> void:
	_surface = world_surface
	_staff = staff_tool
	_desktop = desktop_player
	_xr = xr_player
	_build_forest_sites()
	bind_simulation(simulation)
	_reset_polled_state()


func bind_simulation(new_simulation: Variant) -> void:
	if _simulation is GpuFlightSimulation and (_simulation as GpuFlightSimulation).snapshot_applied.is_connected(_on_snapshot):
		(_simulation as GpuFlightSimulation).snapshot_applied.disconnect(_on_snapshot)
	_simulation = new_simulation if new_simulation is GpuFlightSimulation else null
	_revision = -1
	_last_snapshot = -100.0
	for slot: Dictionary in _mushi:
		_release(slot)
	if _simulation is GpuFlightSimulation:
		(_simulation as GpuFlightSimulation).snapshot_applied.connect(_on_snapshot)
	_reset_polled_state()


func set_listener_camera(camera: Camera3D) -> void:
	if _listener_camera == camera and _listener != null:
		return
	_listener_camera = camera
	if _listener != null:
		_listener.queue_free()
		_listener = null
	if camera == null or not is_instance_valid(camera) or not _enabled:
		return
	if not ClassDB.class_exists("SteamAudioListener"):
		return
	_listener = ClassDB.instantiate("SteamAudioListener")
	_listener.name = "GroveAudioListener"
	_camera_attach(camera)


func _camera_attach(camera: Camera3D) -> void:
	camera.add_child(_listener)


func _load_streams() -> void:
	for stem: String in ["mushi_resonance_01", "mushi_resonance_02", "mushi_resonance_03", "mushi_resonance_04", "forest_insects_01", "forest_insects_02", "forest_insects_03", "footstep_ground_01", "footstep_ground_02", "footstep_ground_03", "footstep_ground_04", "lantern_flame_bed", "lantern_rope_creak_01", "lantern_rope_creak_02", "lantern_metal_swing_01", "lantern_metal_swing_02", "shutter_detent_01", "shutter_detent_02", "shutter_detent_03", "filter_detent_01", "filter_detent_02"]:
		var source: AudioStream = load(AUDIO + stem + ".wav")
		if source != null:
			_streams[stem] = source
	for stem: String in ["forest_crickets_owl", "forest_cicadas_kyles", "footsteps_foliage", "lantern_swing", "lantern_shutter_open", "lantern_shutter_close", "lantern_shutter_variant_a", "lantern_shutter_variant_b", "lantern_shutter_variant_c", "lantern_wick"]:
		var source: AudioStream = load(FIELD_AUDIO + stem + ".wav")
		if source != null:
			_streams[stem] = source


func _make_pool(label: String, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i: int in count:
		var player: AudioStreamPlayer3D = ClassDB.instantiate("SteamAudioPlayer")
		player.name = "%s_%02d" % [label, i]
		player.set("point_source_binaural", true)
		player.set("ambisonics", true)
		player.set("distance_attenuation", false)
		player.set("air_absorption", false)
		player.set("occlusion", false)
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.panning_strength = 0.0
		player.attenuation_filter_db = 0.0
		player.volume_linear = 0.0
		player.bus = "Steps" if label == "Footstep" else label
		add_child(player)
		result.append({"player": player, "id": -1, "gain": 0.0, "base_gain": 1.0, "target": 0.0, "held_until": 0.0, "next_call": 0.0, "stream": "", "position": Vector3.ZERO})
	return result


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(index, bus_name)


func _process(delta: float) -> void:
	if not _enabled:
		return
	if _stress_active:
		return
	var dt := minf(delta, 0.1)
	_clock += dt
	_shutter_quiet_time += dt
	_filter_cooldown = maxf(0.0, _filter_cooldown - dt)
	var camera := _listener_camera
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		_fade_all(dt)
		return
	_update_mushi(dt)
	_update_forest(dt)
	_update_tool(dt)
	_update_footsteps(dt)


func _on_snapshot(_milliseconds: float) -> void:
	if _simulation == null:
		return
	_revision = (_simulation as GpuFlightSimulation).snapshot_revision
	_last_snapshot = _clock
	_select_mushi()


func _select_mushi() -> void:
	if _listener_camera == null or not is_instance_valid(_listener_camera) or _simulation == null:
		return
	var head := _listener_camera.global_position
	var candidates: Array[Dictionary] = []
	var count := mini(_simulation.positions.size(), _simulation.lifecycles.size())
	for id: int in count:
		if _simulation.lifecycles[id] != FlightSimulation.Lifecycle.ACTIVE:
			continue
		var at: Vector3 = _simulation.positions[id]
		if not at.is_finite():
			continue
		var distance := at.distance_to(head)
		if distance > RELEASE_RADIUS:
			continue
		var activity := _mushi_activity(_simulation.arousals[id] if id < _simulation.arousals.size() else 0.0)
		var velocity: Vector3 = _simulation.velocities[id] if id < _simulation.velocities.size() else Vector3.ZERO
		var motion := smoothstep(0.06, 0.55, velocity.length()) if velocity.is_finite() else 0.0
		var score := (0.2 + maxf(activity, motion) * 0.9) / (2.0 + distance)
		for slot: Dictionary in _mushi:
			if int(slot.id) == id:
				score *= 1.28
				if _clock < float(slot.held_until):
					score *= 2.0
				break
		candidates.append({"id": id, "position": at, "score": score, "cell": Vector2i(floori(at.x / 5.0), floori(at.z / 5.0))})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	var selected: Array[Dictionary] = []
	var used_cells: Dictionary = {}
	for candidate: Dictionary in candidates:
		if selected.size() >= mini(mushi_limit, MUSHI_CAP):
			break
		if used_cells.has(candidate.cell):
			continue
		if candidate.position.distance_to(head) > AUDIBLE_RADIUS and not _is_incumbent(int(candidate.id)):
			continue
		selected.append(candidate)
		used_cells[candidate.cell] = true
	for candidate: Dictionary in candidates:
		if selected.size() >= mini(mushi_limit, MUSHI_CAP):
			break
		if selected.has(candidate):
			continue
		if candidate.position.distance_to(head) <= AUDIBLE_RADIUS or _is_incumbent(int(candidate.id)):
			selected.append(candidate)
	var selected_ids: Dictionary = {}
	for candidate: Dictionary in selected:
		selected_ids[candidate.id] = candidate
	for slot: Dictionary in _mushi:
		if int(slot.id) >= 0 and selected_ids.has(slot.id):
			slot.position = selected_ids[slot.id].position
			selected_ids.erase(slot.id)
		elif int(slot.id) >= 0:
			_release(slot)
	for candidate: Dictionary in selected_ids.values():
		for slot: Dictionary in _mushi:
			if int(slot.id) < 0 and float(slot.gain) <= 0.01 and not (slot.player as AudioStreamPlayer3D).playing:
				slot.id = int(candidate.id)
				slot.position = candidate.position
				(slot.player as Node3D).global_position = candidate.position
				slot.held_until = _clock + HOLD_SECONDS
				slot.next_call = _clock + _rng.randf_range(0.0, 2.5)
				break


func _is_incumbent(id: int) -> bool:
	for slot: Dictionary in _mushi:
		if int(slot.id) == id:
			return true
	return false


func _mushi_activity(arousal: float) -> float:
	# Most unperturbed agents sit near 0.08. This changes pitch and can keep an
	# aroused visitor audible even as it slows, without changing simulation state.
	return smoothstep(0.07, 0.70, clampf(arousal, 0.0, 1.0))


func _update_mushi(dt: float) -> void:
	var fresh := _clock - _last_snapshot <= STALE_SECONDS and _simulation is GpuFlightSimulation and (_simulation as GpuFlightSimulation).snapshot_revision == _revision
	for slot: Dictionary in _mushi:
		if int(slot.id) >= 0 and fresh:
			var id: int = slot.id
			if id >= _simulation.positions.size() or id >= _simulation.lifecycles.size() or _simulation.lifecycles[id] != FlightSimulation.Lifecycle.ACTIVE:
				_release(slot)
			else:
				var at: Vector3 = _simulation.positions[id]
				if at.is_finite():
					var velocity: Vector3 = _simulation.velocities[id] if id < _simulation.velocities.size() else Vector3.ZERO
					var age := clampf(_clock - _last_snapshot, 0.0, 0.18)
					var predicted := at + velocity * age if velocity.is_finite() else at
					slot.position = predicted
					var source_node := slot.player as Node3D
					source_node.global_position = source_node.global_position.lerp(predicted, 1.0 - exp(-dt * 14.0))
					var proximity := 1.0 - smoothstep(2.0, AUDIBLE_RADIUS, at.distance_to(_listener_camera.global_position))
					var activity := _mushi_activity(_simulation.arousals[id] if id < _simulation.arousals.size() else 0.0)
					var speed := velocity.length() if velocity.is_finite() else 0.0
					var motion := smoothstep(0.06, 0.55, speed)
					var presence := maxf(motion, activity * 0.7)
					if _clock >= float(slot.next_call) and proximity > 0.02:
						var variant := 1 + posmod(id * 7 + _rng.randi_range(0, 3), 4)
						var pitch := clampf(0.86 + float(posmod(id * 41, 101)) * 0.0025 + activity * 0.30 + _rng.randf_range(-0.035, 0.035), 0.78, 1.5)
						_play(slot, "mushi_resonance_%02d" % variant, -29.0, pitch)
						slot.next_call = _clock + lerpf(_rng.randf_range(12.0, 18.0), _rng.randf_range(2.9, 3.5), presence)
					if (slot.player as AudioStreamPlayer3D).playing:
						slot.target = proximity * lerpf(0.08, 1.0, presence)
						if float(slot.gain) > proximity:
							slot.gain = slot.target
		if not fresh:
			_release(slot)
		_fade(slot, dt)


func _build_forest_sites() -> void:
	_forest_sites.clear()
	if _surface == null:
		return
	for prop: Dictionary in _surface.props:
		if str(prop.get("kind", "")) == "tree":
			var at: Vector3 = prop.position
			if _forest_sites.is_empty() or _forest_sites.back().distance_to(at) > 12.0:
				_forest_sites.append(at + Vector3(0.0, 2.0, 0.0))


func _update_forest(dt: float) -> void:
	var head := _listener_camera.global_position
	var nearby: Array[Dictionary] = []
	for id: int in _forest_sites.size():
		var site: Vector3 = _forest_sites[id]
		var distance := head.distance_to(site)
		if distance < 32.0:
			nearby.append({"id": id, "distance": distance})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var wanted: Dictionary = {}
	# Existing sites remain stable until they leave range; nearby newcomers do
	# not cause the pool's source positions to jump between trees.
	for slot: Dictionary in _forest:
		var id: int = slot.id
		if id >= 0 and id < _forest_sites.size() and head.distance_to(_forest_sites[id]) < 32.0 and wanted.size() < forest_limit:
			wanted[id] = true
	for candidate: Dictionary in nearby:
		if wanted.size() >= mini(forest_limit, FOREST_CAP):
			break
		wanted[int(candidate.id)] = true
	for slot: Dictionary in _forest:
		var id: int = slot.id
		if id >= 0 and not wanted.has(id):
			_release(slot)
		_fade(slot, dt)
	for candidate: Dictionary in nearby:
		var id: int = candidate.id
		if not wanted.has(id):
			continue
		var already_assigned := false
		for slot: Dictionary in _forest:
			if int(slot.id) == id:
				already_assigned = true
				break
		if already_assigned:
			continue
		for slot: Dictionary in _forest:
			if int(slot.id) < 0 and float(slot.gain) <= 0.01 and not (slot.player as AudioStreamPlayer3D).playing:
				slot.id = id
				slot.position = _forest_sites[id]
				(slot.player as Node3D).global_position = _forest_sites[id]
				var stem := "forest_crickets_owl" if id % 2 == 0 else "forest_cicadas_kyles"
				var offset := fposmod(float(id) * 13.37, _streams[stem].get_length())
				_play(slot, stem, -26.0, 1.0, true, offset)
				break
	for slot: Dictionary in _forest:
		if int(slot.id) >= 0:
			var distance := head.distance_to(_forest_sites[int(slot.id)])
			slot.target = clampf((32.0 - distance) / 15.0, 0.0, 1.0) * 0.65
			_fade(slot, dt)


func _update_tool(dt: float) -> void:
	if _staff == null or not is_instance_valid(_staff) or _staff.lantern == null:
		for slot: Dictionary in _tool:
			_release(slot)
			_fade(slot, dt)
		return
	var flame := _tool[0]
	var pos: Vector3 = _staff.lantern.global_position
	var proximity := 1.0 - smoothstep(1.5, 12.0, pos.distance_to(_listener_camera.global_position))
	for slot: Dictionary in _tool:
		(slot.player as Node3D).global_position = pos
	if str(flame.stream) == "":
		_play(flame, "lantern_wick", -21.0, 1.0, true)
	flame.target = proximity * (0.65 if _staff.lantern.shutter_openness > 0.02 else 0.28)
	var shutter: float = _staff.lantern.shutter_openness
	var requested_mode: int = int(_staff.lantern.get("_requested_mode"))
	var filter_transition: bool = int(_staff.lantern.get("_transition_phase")) != 0
	if _last_shutter >= 0.0 and absf(shutter - _last_shutter) > 0.003 and not filter_transition and not _filter_transition_was_active:
		if _shutter_quiet_time >= 0.14 and proximity > 0.02:
			_play(_tool[1], "lantern_shutter_open" if shutter > _last_shutter else "lantern_shutter_close", -17.0)
			_tool[1].gain = proximity
			_tool[1].target = proximity
		_shutter_quiet_time = 0.0
	_last_shutter = shutter
	_filter_transition_was_active = filter_transition
	if _last_requested_mode >= 0 and requested_mode != _last_requested_mode and _filter_cooldown <= 0.0:
		if proximity > 0.02:
			_play(_tool[2], FILTER_TRANSIENTS[_filter_variant], -17.0)
			_filter_variant = posmod(_filter_variant + 1, FILTER_TRANSIENTS.size())
			_tool[2].gain = proximity
			_tool[2].target = proximity
		_filter_cooldown = 0.14
	_last_requested_mode = requested_mode
	var swing_local: Vector3 = _staff.global_transform.affine_inverse() * pos
	var velocity: float = swing_local.distance_to(_last_swing_local) / maxf(dt, 0.001)
	_staff_speed = lerpf(_staff_speed, velocity, minf(1.0, dt * 5.0))
	var swing_gain := proximity * smoothstep(0.25, 1.1, _staff_speed)
	if swing_gain > 0.02 and str(_tool[3].stream) == "":
		_play(_tool[3], "lantern_swing", -20.0, 1.0, true)
	_tool[3].target = swing_gain
	_last_swing_local = swing_local
	for index: int in range(1, 3):
		if (_tool[index].player as AudioStreamPlayer3D).playing:
			_tool[index].target = proximity
	for slot: Dictionary in _tool:
		_fade(slot, dt)


func _update_footsteps(dt: float) -> void:
	var player: Node3D = _xr if _xr != null and _xr.xr_active else _desktop
	if player == null or not is_instance_valid(player):
		return
	var feet := player.global_position
	if player == _xr and _xr.has_node("PlayerBody"):
		feet = _xr.get_node("PlayerBody").global_position
	var travel := Vector2(feet.x - _last_head.x, feet.z - _last_head.z).length()
	var grounded := false
	if player is CharacterBody3D:
		grounded = (player as CharacterBody3D).is_on_floor()
	elif _surface != null:
		grounded = absf(feet.y - _surface.get_height_at(Vector2(feet.x, feet.z))) < 0.5
	_last_head = feet
	var slot: Dictionary = _steps[0]
	(slot.player as Node3D).global_position = feet
	var speed := travel / maxf(dt, 0.001) if travel < 0.9 else 0.0
	var step_gain := smoothstep(0.35, 1.4, speed) if grounded and step_limit > 0 else 0.0
	if step_gain > 0.02 and str(slot.stream) == "":
		_play(slot, "footsteps_foliage", -19.0, 1.0, true)
	slot.target = step_gain * 0.85
	_fade(slot, dt)


func _play(slot: Dictionary, stem: String, volume_db: float, pitch: float = 1.0, looped: bool = false, offset: float = 0.0) -> void:
	if not _streams.has(stem):
		return
	var stream: AudioStream = _streams[stem]
	if looped and stream is AudioStreamWAV:
		stream = stream.duplicate()
		# Imported WAVs have loop_end=0. A forward loop with that endpoint is silent.
		(stream as AudioStreamWAV).loop_end = maxi(1, roundi(stream.get_length() * float((stream as AudioStreamWAV).mix_rate)))
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var player: AudioStreamPlayer3D = slot.player
	player.call("play_stream", stream, offset, 0.0, pitch)
	slot.stream = stem
	slot.base_gain = db_to_linear(volume_db)
	slot.gain = 0.0 if looped else 1.0
	player.volume_linear = float(slot.gain) * float(slot.base_gain)


func _release(slot: Dictionary) -> void:
	slot.id = -1
	slot.target = 0.0
	slot.held_until = 0.0


func _fade(slot: Dictionary, dt: float) -> void:
	var player: AudioStreamPlayer3D = slot.player
	if not player.playing and str(slot.stream) != "":
		slot.stream = ""
		slot.target = 0.0
		slot.gain = 0.0
	var gain := move_toward(float(slot.gain), float(slot.target), FADE_RATE * dt)
	slot.gain = gain
	player.volume_linear = gain * float(slot.base_gain)
	if gain <= 0.001 and float(slot.target) <= 0.0 and player.playing:
		player.stop()
		slot.stream = ""


func _fade_all(dt: float) -> void:
	for pool: Array[Dictionary] in [_mushi, _forest, _tool, _steps]:
		for slot: Dictionary in pool:
			_release(slot)
			_fade(slot, dt)


func _reset_polled_state() -> void:
	_last_head = _desktop.global_position if _desktop != null else Vector3.ZERO
	_last_swing_local = _staff.global_transform.affine_inverse() * _staff.lantern.global_position if _staff != null and _staff.lantern != null else Vector3.ZERO
	_last_shutter = _staff.lantern.shutter_openness if _staff != null and _staff.lantern != null else -1.0
	_last_requested_mode = int(_staff.lantern.get("_requested_mode")) if _staff != null and _staff.lantern != null else -1
	_shutter_quiet_time = 1.0
	_filter_transition_was_active = false


func start_stress_voices(count: int) -> void:
	if not _enabled:
		return
	_stress_active = true
	var all_slots: Array[Dictionary] = []
	for pool: Array[Dictionary] in [_mushi, _forest, _tool, _steps]:
		all_slots.append_array(pool)
	var head := _listener_camera.global_position if _listener_camera != null else Vector3.ZERO
	for i: int in all_slots.size():
		var slot: Dictionary = all_slots[i]
		var player: AudioStreamPlayer3D = slot.player
		if i < clampi(count, 0, all_slots.size()):
			player.global_position = head + Vector3(cos(float(i) * TAU / 24.0) * 3.0, 0.0, sin(float(i) * TAU / 24.0) * 3.0)
			_play(slot, "forest_insects_%02d" % (i % 3 + 1), -30.0, 1.0, true)
			slot.target = 1.0
			player.volume_linear = float(slot.base_gain)
		else:
			player.stop()
			slot.stream = ""


func stop_stress_voices() -> void:
	_stress_active = false
	for pool: Array[Dictionary] in [_mushi, _forest, _tool, _steps]:
		for slot: Dictionary in pool:
			(slot.player as AudioStreamPlayer3D).stop()
			slot.stream = ""
			slot.gain = 0.0
			_release(slot)
