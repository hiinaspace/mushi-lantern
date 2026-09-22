extends SceneTree

## Rendered, fixed-route comparison of the saved Longer drift tuning and the
## optional Drifting trains forces. This is a proximity diagnostic, not a
## judgement of composition or headset feel. Run with Vulkan/Mobile.
const SEED := 40721
const DT := 1.0 / 30.0
const STEPS := 900 # 30 simulated seconds per fixture.
const LAMP_STEPS := 300
const CLUSTER_RADIUS := 1.5
const SOCIAL_MULTIPLIER := 1.4
const WANDER_MULTIPLIER := 0.5
const LANTERN_STRENGTH := 0.8

var _gpu_times: Array[float] = []
var _snapshot_ms: Array[float] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("FORMATION_META engine=%s renderer=%s seed=%d dt=%.6f steps=%d orange_steps=%d social=%.2f wander=%.2f lantern=%.2f cluster_radius=%.2f" % [Engine.get_version_info().string, RenderingServer.get_current_rendering_method(), SEED, DT, STEPS, LAMP_STEPS, SOCIAL_MULTIPLIER, WANDER_MULTIPLIER, LANTERN_STRENGTH, CLUSTER_RADIUS])
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 13.0, 42.0)
	camera.rotation.x = deg_to_rad(-15.0)
	world.add_child(camera)
	camera.current = true
	var presets := HerdPreset.builtins()
	if presets.size() < 8:
		push_error("Longer drift and Drifting trains builtins are required")
		quit(1)
		return
	for count: int in [1024, 2048]:
		for preset_index: int in [6, 7]:
			var focus := OS.get_environment("MUSHI_FORMATION_FOCUS")
			if focus == "1" and (count != 1024 or preset_index != 7):
				continue
			if focus == "default" and (count != 1024 or preset_index != 6):
				continue
			if not await _fixture(world, count, presets[preset_index]):
				quit(1)
				return
	world.queue_free()
	await process_frame
	print("FORMATION_COMPARISON_DONE")
	quit()


func _fixture(world: Node3D, count: int, preset: HerdPreset) -> bool:
	_gpu_times.clear()
	_snapshot_ms.clear()
	var sim := GpuFlightSimulation.new()
	sim.profile_gpu = true
	sim.gpu_timing_sample.connect(func(ms: float) -> void: _gpu_times.append(ms))
	sim.snapshot_applied.connect(func(ms: float) -> void: _snapshot_ms.append(ms))
	sim.mushroom_centers = PackedVector2Array([Vector2(-14.4, -13.2), Vector2(14.6, -12.0), Vector2(15.4, 13.6)])
	sim.obstacle_centers = PackedVector2Array([Vector2(-8.0, -7.0), Vector2(8.0, -6.0), Vector2(8.0, 7.0)])
	sim.obstacle_radii = PackedFloat32Array([0.7, 0.8, 0.75])
	sim.goal_position = Vector2(0.0, 18.0)
	sim.reset(count, SEED, preset)
	for frame: int in 180:
		await process_frame
		if sim.gpu_ready or not sim.gpu_error.is_empty():
			break
	if not sim.gpu_ready:
		push_error("GPU fixture failed count=%d preset=%s error=%s" % [count, preset.preset_name, sim.gpu_error])
		sim.dispose()
		return false
	var glyphs := GlyphSwarm.new()
	world.add_child(glyphs)
	glyphs.configure(count)
	var field := LightField.new()
	field.obstacle_centers = sim.obstacle_centers
	field.obstacle_radii = sim.obstacle_radii
	field.source_position = Vector3(-14.4, 5.0, -13.2)
	field.source_direction = Vector3.DOWN
	field.mode_strength = LANTERN_STRENGTH
	var submit_ms: Array[float] = []
	var visual_ms: Array[float] = []
	var finite := true
	for tick: int in STEPS:
		# The fixed intervention awakens the first mushroom group. The remaining
		# 20 seconds let its pieces drift and either split or rejoin.
		field.mode = LightField.Mode.ORANGE if tick < LAMP_STEPS else LightField.Mode.CLEAR
		var started := Time.get_ticks_usec()
		sim.step(DT, field, SOCIAL_MULTIPLIER, WANDER_MULTIPLIER)
		if tick >= 90 and tick < STEPS - 10:
			submit_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		glyphs.update_swarm(sim, 0.5, preset)
		if tick >= 90 and tick < STEPS - 10:
			visual_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		await process_frame
		if tick + 1 in [450, 600, 750, STEPS]:
			if not await _current_snapshot(sim):
				push_error("Snapshot timed out count=%d preset=%s tick=%d revision=%d" % [count, preset.preset_name, tick + 1, sim.snapshot_revision])
				glyphs.queue_free()
				sim.dispose()
				return false
			print("FORMATION_CLUSTER count=%d preset=%s time_s=%.1f snapshot_lag_ticks=%d %s %s" % [count, preset.preset_name, (tick + 1) * DT, sim.state_revision - sim.snapshot_revision, _clusters(sim, preset), _trio_geometry(sim, preset)])
			finite = finite and sim.is_finite_and_bounded()
			if tick + 1 == STEPS and count == 1024:
				var capture_dir := OS.get_environment("MUSHI_FORMATION_CAPTURE_DIR")
				if not capture_dir.is_empty():
					DirAccess.make_dir_recursive_absolute(capture_dir)
					var capture_path := capture_dir.path_join(preset.preset_name.to_lower().replace(" ", "-") + ".png")
					var capture_error := root.get_texture().get_image().save_png(capture_path)
					if capture_error != OK:
						push_error("Screenshot failed: %s" % capture_path)
						finite = false
					else:
						print("FORMATION_CAPTURE path=%s" % capture_path)
					if preset.formation_follow_weight > 0.0:
						var trio := _first_shaped_trio(sim, preset)
						if trio.size() == 3:
							var center := (sim.positions[trio[0]] + sim.positions[trio[1]] + sim.positions[trio[2]]) / 3.0
							var camera := world.get_child(0) as Camera3D
							camera.position = center + Vector3(0.0, 0.25, 1.4)
							camera.look_at(center)
							await process_frame
							await process_frame
							var close_path := capture_dir.path_join("drifting-trains-close.png")
							if root.get_texture().get_image().save_png(close_path) != OK:
								push_error("Close screenshot failed: %s" % close_path)
								finite = false
							else:
								print("FORMATION_CLOSE_CAPTURE path=%s ids=%s" % [close_path, trio])
	# Timestamp publishing happens on following dispatches. Drain with a few
	# extra ticks, outside the fixed 30-second observation interval.
	for drain: int in 10:
		sim.step(DT, field, SOCIAL_MULTIPLIER, WANDER_MULTIPLIER)
		await process_frame
	await process_frame
	var warmup := mini(90, _gpu_times.size())
	var end := maxi(warmup, _gpu_times.size() - 10)
	var measured := _gpu_times.slice(warmup, end)
	print("FORMATION_TIMING count=%d preset=%s gpu_upload_compute_ms=%s cpu_submit_ms=%s glyph_update_ms=%s snapshot_apply_ms=%s score=%d finite=%s" % [count, preset.preset_name, _stats(measured), _stats(submit_ms), _stats(visual_ms), _stats(_snapshot_ms), sim.score, finite])
	glyphs.queue_free()
	sim.dispose()
	await process_frame
	await process_frame
	return measured.size() >= 600 and finite and sim.gpu_error.is_empty()


func _current_snapshot(sim: GpuFlightSimulation) -> bool:
	var wanted := sim.state_revision
	for frame: int in 120:
		if sim.snapshot_revision >= wanted:
			return true
		sim.request_snapshot()
		await process_frame
	return false


func _clusters(sim: GpuFlightSimulation, preset: HerdPreset) -> String:
	var awake: Array[int] = []
	var cutoff := preset.sleep_threshold + 0.05
	for i: int in sim.positions.size():
		if sim.lifecycles[i] == FlightSimulation.Lifecycle.ACTIVE and sim.arousals[i] > cutoff:
			awake.append(i)
	var parents: Array[int] = []
	parents.resize(awake.size())
	for k: int in awake.size():
		parents[k] = k
	var radius_squared := CLUSTER_RADIUS * CLUSTER_RADIUS
	for a: int in awake.size():
		var p := sim.positions[awake[a]]
		for b: int in range(a + 1, awake.size()):
			var q := sim.positions[awake[b]]
			if absf(p.x - q.x) > CLUSTER_RADIUS or absf(p.y - q.y) > CLUSTER_RADIUS or absf(p.z - q.z) > CLUSTER_RADIUS:
				continue
			if p.distance_squared_to(q) <= radius_squared:
				_join(parents, a, b)
	var sizes := {}
	for k: int in awake.size():
		var parent := _root(parents, k)
		sizes[parent] = int(sizes.get(parent, 0)) + 1
	var largest := 0
	var small_groups := 0
	var small_members := 0
	var nontrivial := 0
	for size: int in sizes.values():
		largest = maxi(largest, size)
		if size >= 2:
			nontrivial += 1
		if size >= 2 and size <= 12:
			small_groups += 1
			small_members += size
	return "awake=%d components=%d multi=%d small_2_12=%d small_members=%d largest=%d largest_fraction=%.3f" % [awake.size(), sizes.size(), nontrivial, small_groups, small_members, largest, float(largest) / maxf(1.0, float(awake.size()))]


func _trio_geometry(sim: GpuFlightSimulation, preset: HerdPreset) -> String:
	var awake := PackedByteArray()
	awake.resize(sim.positions.size())
	var awake_count := 0
	for i: int in sim.positions.size():
		if sim.lifecycles[i] == FlightSimulation.Lifecycle.ACTIVE and sim.arousals[i] > preset.sleep_threshold + 0.05:
			awake[i] = 1
			awake_count += 1
	var linked_heads := 0
	var shaped_linked := 0
	var raw_trios := 0
	var used_bodies := {}
	var used_tails := {}
	for head: int in sim.positions.size():
		if awake[head] == 0 or sim.trait_types[head] != 0:
			continue
		var body := sim.formation_successors[head]
		if body >= 0 and awake[body] != 0 and sim.formation_predecessors[body] == head:
			var tail := sim.formation_successors[body]
			if tail >= 0 and awake[tail] != 0 and sim.formation_predecessors[tail] == body:
				linked_heads += 1
				if _ordered_trio(sim, head, body, tail):
					shaped_linked += 1
		# Independent geometry count applies equally to the old rule, which
		# has no link metadata. Choose unique close, aligned body/tail slots.
		var nearest_body := -1
		var best_body := INF
		for candidate: int in sim.positions.size():
			if awake[candidate] == 0 or sim.trait_types[candidate] != 1 or used_bodies.has(candidate):
				continue
			var d := sim.positions[head].distance_squared_to(sim.positions[candidate])
			if d < best_body and _ordered_pair(sim, head, candidate):
				nearest_body = candidate
				best_body = d
		if nearest_body < 0:
			continue
		var nearest_tail := -1
		var best_tail := INF
		for candidate: int in sim.positions.size():
			if awake[candidate] == 0 or sim.trait_types[candidate] != 2 or used_tails.has(candidate):
				continue
			var d := sim.positions[nearest_body].distance_squared_to(sim.positions[candidate])
			if d < best_tail and _ordered_pair(sim, nearest_body, candidate):
				nearest_tail = candidate
				best_tail = d
		if nearest_tail >= 0 and _ordered_trio(sim, head, nearest_body, nearest_tail):
			used_bodies[nearest_body] = true
			used_tails[nearest_tail] = true
			raw_trios += 1
	return "trios=linked:%d,shaped_linked:%d,raw_ordered:%d,awake_fraction:%.3f" % [linked_heads, shaped_linked, raw_trios, float(raw_trios * 3) / maxf(1.0, float(awake_count))]


func _ordered_pair(sim: GpuFlightSimulation, lead: int, follower: int) -> bool:
	var heading := sim.velocities[lead]
	var next_heading := sim.velocities[follower]
	if heading.length_squared() < 0.04 or next_heading.length_squared() < 0.04:
		return false
	heading = heading.normalized()
	next_heading = next_heading.normalized()
	var delta := sim.positions[lead] - sim.positions[follower]
	var forward_gap := delta.dot(heading)
	var lateral := (delta - heading * forward_gap).length()
	return forward_gap >= 0.07 and forward_gap <= 0.23 and lateral <= 0.10 and heading.dot(next_heading) >= 0.75


func _ordered_trio(sim: GpuFlightSimulation, head: int, body: int, tail: int) -> bool:
	return _ordered_pair(sim, head, body) and _ordered_pair(sim, body, tail) and sim.positions[head].distance_to(sim.positions[tail]) >= 0.20


func _first_shaped_trio(sim: GpuFlightSimulation, preset: HerdPreset) -> PackedInt32Array:
	for head: int in sim.positions.size():
		if sim.lifecycles[head] != FlightSimulation.Lifecycle.ACTIVE or sim.trait_types[head] != 0 or sim.arousals[head] <= preset.sleep_threshold + 0.05:
			continue
		var body := sim.formation_successors[head]
		if body < 0 or sim.formation_predecessors[body] != head:
			continue
		var tail := sim.formation_successors[body]
		if tail < 0 or sim.formation_predecessors[tail] != body:
			continue
		if _ordered_trio(sim, head, body, tail):
			return PackedInt32Array([head, body, tail])
	return PackedInt32Array()


func _root(parents: Array[int], index: int) -> int:
	var result := index
	while parents[result] != result:
		result = parents[result]
	while parents[index] != index:
		var next := parents[index]
		parents[index] = result
		index = next
	return result


func _join(parents: Array[int], a: int, b: int) -> void:
	var ra := _root(parents, a)
	var rb := _root(parents, b)
	if ra != rb:
		parents[rb] = ra


func _stats(values: Array[float]) -> String:
	if values.is_empty():
		return "n/a"
	var ordered := values.duplicate()
	ordered.sort()
	return "n=%d,p50=%.4f,p95=%.4f,p99=%.4f,max=%.4f" % [ordered.size(), ordered[int(ceil(ordered.size() * 0.5)) - 1], ordered[int(ceil(ordered.size() * 0.95)) - 1], ordered[int(ceil(ordered.size() * 0.99)) - 1], ordered[-1]]
