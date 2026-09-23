class_name EnvironmentSurface
extends RefCounted

## The authored basin grid. One red float pixel is one metre and all consumers
## (Terrain3D, CPU grounding, GPU flight) use this same row-major data.
var size_m: int = 128
var sample_count: int = 129
var seed: int = 40721
var height_samples: PackedFloat32Array
var patch_centers := PackedVector2Array()
var props: Array[Dictionary] = []

static func create(world_size_m: int = 128, world_seed: int = 40721) -> EnvironmentSurface:
	assert(world_size_m == 128 or world_size_m == 256)
	var surface := EnvironmentSurface.new()
	surface.size_m = world_size_m
	surface.sample_count = world_size_m + 1
	surface.seed = world_seed
	surface._generate()
	return surface

func _generate() -> void:
	height_samples.resize(sample_count * sample_count)
	for zi in sample_count:
		for xi in sample_count:
			var x := float(xi - size_m / 2)
			var z := float(zi - size_m / 2)
			height_samples[zi * sample_count + xi] = _height_function(Vector2(x, z))
	_generate_patches()
	_generate_props()

func _height_function(xz: Vector2) -> float:
	var x := xz.x
	var z := xz.y
	# The central ~6m clearing is level. The broader basin undulates enough to
	# expose flight and walking over height changes without hiding all routes.
	var floor_height := 0.90 * sin(x * 0.070 + 0.6) * cos(z * 0.058 - 0.3)
	floor_height += 0.70 * sin(x * 0.031 + z * 0.047)
	floor_height += 0.28 * sin(x * 0.17 - z * 0.10)
	floor_height *= smoothstep(5.0, 12.0, xz.length())
	# Three central terraces have a steep inside lip and a gentle rear ramp.
	# A group may drop off each lip; a player approaches its top by walking
	# around an end and up the back. Distinct intervening ridges hide the rim.
	var east := _terrace(xz, Vector2(14.0, 0.0), Vector2.RIGHT, 24.0, 16.0, 1.6, 12.0, 5.8)
	var west := _terrace(xz, Vector2(-15.0, 6.0), Vector2.LEFT, 23.0, 18.0, 2.0, 11.0, 5.1)
	var north := _terrace(xz, Vector2(0.0, -17.0), Vector2.UP, 21.0, 14.0, 2.1, 11.0, 6.4)
	var raised := maxf(east, maxf(west, north))
	if size_m == 256:
		# Surrounding 256m country adds another pair of visible height layers;
		# the original central passages and scale are unchanged.
		raised = maxf(raised, _terrace(xz, Vector2(49.0, 38.0), Vector2(0.78, 0.63), 28.0, 23.0, 3.4, 16.0, 6.8))
		raised = maxf(raised, _terrace(xz, Vector2(-45.0, -40.0), Vector2(-0.72, -0.69), 27.0, 22.0, 3.2, 15.0, 6.0))
	var radius := _effective_radius(xz)
	var rim_start := float(size_m) * 0.36
	var rim_width := minf(float(size_m) * 0.115, 16.0)
	var t := clampf((radius - rim_start) / rim_width, 0.0, 1.0)
	var smooth_t := t * t * (3.0 - 2.0 * t)
	var ridge := 15.0 * smooth_t
	return floor_height + maxf(raised, ridge) + 0.6 * smooth_t * sin(x * 0.23 + z * 0.13)

func _terrace(xz: Vector2, front: Vector2, inward: Vector2, depth: float, half_span: float, cliff_width: float, rear_width: float, height: float) -> float:
	var delta := xz - front
	var u := delta.dot(inward)
	var v := absf(delta.cross(inward))
	var cliff := smoothstep(0.0, cliff_width, u)
	var rear := 1.0 - smoothstep(depth - rear_width, depth, u)
	var ends := 1.0 - smoothstep(half_span - 5.0, half_span, v)
	return height * cliff * rear * ends

func _effective_radius(xz: Vector2) -> float:
	var scaled := Vector2(xz.x * 1.07, xz.y * 0.97)
	var angle := atan2(scaled.y, scaled.x)
	var irregularity := 1.0 + 0.075 * sin(angle * 3.0 + 0.3) + 0.055 * cos(angle * 7.0 - 0.4) + 0.025 * sin(angle * 11.0 + 1.0)
	return scaled.length() / irregularity

func basin_margin(xz: Vector2) -> float:
	return float(size_m) * 0.36 - _effective_radius(xz)

func is_playable(xz: Vector2, margin: float = 0.0) -> bool:
	return basin_margin(xz) >= margin

func inward_direction(xz: Vector2) -> Vector2:
	# A finite fallback at the centre also makes this safe for exact overlap.
	return -xz.normalized() if xz.length_squared() > 0.0001 else Vector2.RIGHT

func is_in_bounds(xz: Vector2) -> bool:
	var half := float(size_m) * 0.5
	return xz.x >= -half and xz.y >= -half and xz.x <= half and xz.y <= half

func get_height_at(xz: Vector2) -> float:
	# Terrain3D interpolates its imported float map. Bilinear sampling here
	# retains the same vertices; a conservative clearance covers triangle/LOD
	# interpolation differences between them.
	var half := float(size_m) * 0.5
	var gx := clampf(xz.x + half, 0.0, float(size_m))
	var gz := clampf(xz.y + half, 0.0, float(size_m))
	var x0 := mini(int(floorf(gx)), size_m - 1)
	var z0 := mini(int(floorf(gz)), size_m - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var a := lerpf(height_samples[z0 * sample_count + x0], height_samples[z0 * sample_count + x0 + 1], tx)
	var b := lerpf(height_samples[(z0 + 1) * sample_count + x0], height_samples[(z0 + 1) * sample_count + x0 + 1], tx)
	return lerpf(a, b, tz)

func get_height_image() -> Image:
	var img := Image.create_empty(sample_count, sample_count, false, Image.FORMAT_RF)
	for zi in sample_count:
		for xi in sample_count:
			img.set_pixel(xi, zi, Color(height_samples[zi * sample_count + xi], 0.0, 0.0, 1.0))
	return img

func get_terrain_height_image() -> Image:
	# Terrain3D regions are 64x64, so omit the positive-edge sample. It is
	# retained in get_height_image() for GPU bilinear sampling and CPU queries.
	# The omitted edge lies beyond the enclosing visible rim.
	var img := Image.create_empty(size_m, size_m, false, Image.FORMAT_RF)
	for zi in size_m:
		for xi in size_m:
			img.set_pixel(xi, zi, Color(height_samples[zi * sample_count + xi], 0.0, 0.0, 1.0))
	return img

func get_props() -> Array[Dictionary]:
	return props

func get_obstacles() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for prop in props:
		if prop.kind != "tree" and prop.kind != "rock":
			continue
		var pos: Vector3 = prop.position
		records.append({
			"center": Vector2(pos.x, pos.z),
			"radius": prop.radius,
			"bottom": pos.y,
			"top": pos.y + prop.height,
		})
	return records

func _terrain_grade(xz: Vector2) -> float:
	var dx := (get_height_at(xz + Vector2.RIGHT) - get_height_at(xz - Vector2.RIGHT)) * 0.5
	var dz := (get_height_at(xz + Vector2.DOWN) - get_height_at(xz - Vector2.DOWN)) * 0.5
	return Vector2(dx, dz).length()

func _generate_patches() -> void:
	# Candidate centers are authored around the main ledges and their bypasses.
	# Their locations precede prop generation, so all dressing excludes them.
	var central := [
		Vector2(-13.0, -12.0), Vector2(8.0, -10.0), Vector2(23.0, 9.0),
		Vector2(-25.0, 8.0), Vector2(26.0, -22.0), Vector2(-4.0, -28.0),
		Vector2(-31.0, 24.0), Vector2(3.0, 30.0), Vector2(29.0, 25.0),
	]
	for center: Vector2 in central:
		assert(is_playable(center, 5.0) and _terrain_grade(center) < 0.42, "Authored patch must be on a walkable terrace or floor: %s" % center)
		patch_centers.append(center)
	if size_m == 128:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 2917
	var attempts := 0
	while patch_centers.size() < 18 and attempts < 10000:
		attempts += 1
		var angle := rng.randf_range(-PI, PI)
		var radius := rng.randf_range(47.0, 78.0)
		var center := Vector2.from_angle(angle) * radius
		if not is_playable(center, 9.0) or _terrain_grade(center) > 0.36:
			continue
		var separated := true
		for prior: Vector2 in patch_centers:
			if center.distance_to(prior) < 12.0:
				separated = false
				break
		if separated:
			patch_centers.append(center)
	assert(patch_centers.size() == 18, "Could not place 18 walkable mushroom patches")

func _generate_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 773
	# Reachable test obstacles sit outside the mushroom patch footprints while
	# leaving the origin and direct gathering space clear.
	for xz in [Vector2(-7, -12), Vector2(6, 8), Vector2(28, 18), Vector2(-9, 23)]:
		_add_fixed_obstacle("tree", xz, 1.0)
	for xz in [Vector2(0, -10), Vector2(20, -23), Vector2(11, 26)]:
		_add_fixed_obstacle("rock", xz, 1.0)
	# Keep the revised 6m goal clearing and player starts readable while
	# surrounding them with terrain detail and collision-bearing props.
	var area_scale := float(size_m * size_m) / float(128 * 128)
	_add_kind(rng, "tree", roundi(110.0 * area_scale), 10.0)
	_add_kind(rng, "rock", roundi(65.0 * area_scale), 8.0)
	_add_kind(rng, "bush", roundi(210.0 * area_scale), 8.0)
	_add_kind(rng, "grass", roundi(12000.0 * area_scale), 6.0)

func _add_fixed_obstacle(kind: String, xz: Vector2, scale: float) -> void:
	if not _prop_location_ok(xz, kind, 0.95 if kind == "rock" else 0.46):
		push_warning("Skipping fixed %s at %s: patch, slope or clearing conflict" % [kind, xz])
		return
	props.append({"kind": kind, "position": Vector3(xz.x, get_height_at(xz), xz.y), "yaw": 0.0, "scale": scale, "radius": 0.46 if kind == "tree" else 0.95, "height": 4.2 if kind == "tree" else 1.4, "variant": 0})

func _prop_location_ok(xz: Vector2, kind: String, radius: float) -> bool:
	if basin_margin(xz) < 2.0:
		return false
	var slope_limit := 0.9 if kind == "rock" else (0.72 if kind == "grass" else 0.48)
	if _terrain_grade(xz) > slope_limit:
		return false
	for patch: Vector2 in patch_centers:
		if xz.distance_to(patch) < 4.0 + radius:
			return false
	if kind == "tree" or kind == "rock":
		if xz.distance_to(Vector2(0.0, 18.4)) < 4.0 + radius or xz.distance_to(Vector2(-14.4, -8.0)) < 4.0 + radius:
			return false
		# Keep the known east-cliff drop and its south/rear bypass usable by
		# the player; foliage and mushrooms can still occupy its margins.
		var route := [Vector2(10, 0), Vector2(10, 22), Vector2(37, 22), Vector2(37, 0), Vector2(20, 0)]
		for index in route.size() - 1:
			var start: Vector2 = route[index]
			var end: Vector2 = route[index + 1]
			var segment := end - start
			var t := clampf((xz - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
			if xz.distance_to(start + segment * t) < 2.0 + radius:
				return false
	return true

func _add_kind(rng: RandomNumberGenerator, kind: String, target: int, inner_radius: float) -> void:
	var count := 0
	var attempts := 0
	while count < target and attempts < target * 25:
		attempts += 1
		var xz := Vector2(rng.randf_range(-size_m * 0.43, size_m * 0.43), rng.randf_range(-size_m * 0.43, size_m * 0.43))
		if xz.length() < inner_radius or not _prop_location_ok(xz, kind, 0.95 if kind == "rock" else (0.46 if kind == "tree" else 0.0)):
			continue
		var scale := rng.randf_range(0.8, 1.25)
		var radius := 0.0
		var prop_height := 0.0
		match kind:
			"tree":
				radius = 0.46 * scale
				prop_height = 4.2 * scale
			"rock":
				radius = 0.95 * scale
				prop_height = 1.4 * scale
			"bush":
				prop_height = 1.3 * scale
			"grass":
				prop_height = 0.46 * scale
		props.append({"kind": kind, "position": Vector3(xz.x, get_height_at(xz), xz.y), "yaw": rng.randf_range(-PI, PI), "scale": scale, "radius": radius, "height": prop_height, "variant": rng.randi_range(0, 2)})
		count += 1
