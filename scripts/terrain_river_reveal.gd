class_name TerrainRiverReveal
extends RefCounted

## Inject a per-eye, deep rope into Terrain3D's opaque shader. The ground is
## the reveal window and retains its ordinary depth/stencil behavior. The map
## stores a centerline distance in alpha so the shader can sample a round 3D
## tube instead of a flat projected ribbon.
const RIVER_PLANE_Y := -30.0
const MAP_DISTANCE_SCALE := 16.0
const MAP_EXTENT_MULTIPLIER := 5
const FAR_ARM_END_M := 3000.0
static var _path_maps: Dictionary = {}

const UNIFORMS := "#include \"res://shaders/river_volume.gdshaderinc\"\n"

const FRAGMENT := """
 vec3 river_eye = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
 vec3 river_ray = normalize(v_vertex - river_eye);
 vec4 river = river_evaluate(river_eye, river_ray, distance(v_vertex, river_eye));
 ALBEDO *= 1.0 - river.a * 0.06;
 EMISSION += river.rgb;
"""

static func install(material: Terrain3DMaterial, surface: EnvironmentSurface, goal: Vector2 = Vector2.ZERO) -> bool:
	if material == null or surface == null:
		return false
	# The headless dummy renderer has no compiled Terrain3D spatial shader to
	# extend. Surface/collision fixtures still build the terrain without a reveal.
	if DisplayServer.get_name() == "headless":
		return false
	var base_code := RenderingServer.shader_get_code(material.get_shader_rid())
	const ANCHOR := "ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;"
	const FRAGMENT_SIGNATURE := "void fragment() {"
	if not base_code.begins_with("shader_type spatial;"):
		push_error("Terrain3D shader override failed: expected spatial shader header")
		return false
	var fragment_start := base_code.find(FRAGMENT_SIGNATURE)
	if fragment_start < 0:
		push_error("Terrain3D shader override failed: fragment() signature changed")
		return false
	var fragment_open := fragment_start + FRAGMENT_SIGNATURE.length() - 1
	var fragment_close := _matching_closing_brace(base_code, fragment_open)
	if fragment_close < 0:
		push_error("Terrain3D shader override failed: fragment() closing brace not found")
		return false
	var anchor_at := base_code.find(ANCHOR)
	if anchor_at < fragment_open or anchor_at >= fragment_close:
		push_error("Terrain3D shader override failed: Terrain3D fragment anchor moved outside fragment()")
		return false
	var shader := Shader.new()
	var header_end := base_code.find("\n") + 1
	shader.code = base_code.substr(0, header_end) + UNIFORMS + base_code.substr(header_end, fragment_close - header_end) + FRAGMENT + base_code.substr(fragment_close)
	material.shader_override = shader
	material.shader_override_enabled = true
	material.set_shader_param("river_path_map", path_map(surface.size_m, goal))
	material.set_shader_param("river_size", float(path_extent(surface.size_m)))
	material.set_shader_param("river_length", path_length(surface.size_m, goal))
	material.set_shader_param("river_plane_y", RIVER_PLANE_Y)
	material.set_shader_param("river_goal_xz", goal)
	material.set_shader_param("river_night_vision", 0.0)
	return true

## Find the closing brace paired with the opening brace of fragment(). This
## deliberately avoids rfind("}"): Terrain3D appends helper functions after
## fragment(), and injection must remain inside this exact function.
static func _matching_closing_brace(code: String, opening_brace: int) -> int:
	if opening_brace < 0 or opening_brace >= code.length() or code[opening_brace] != "{":
		return -1
	var depth := 0
	var index := opening_brace
	var line_comment := false
	var block_comment := false
	var quote := ""
	while index < code.length():
		var character := code[index]
		var next_character := code[index + 1] if index + 1 < code.length() else ""
		if line_comment:
			if character == "\n":
				line_comment = false
		elif block_comment:
			if character == "*" and next_character == "/":
				block_comment = false
				index += 1
		elif not quote.is_empty():
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
		elif character == "/" and next_character == "/":
			line_comment = true
			index += 1
		elif character == "/" and next_character == "*":
			block_comment = true
			index += 1
		elif character == "\"" or character == "'":
			quote = character
		elif character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return index
		index += 1
	return -1

## Terrain and foliage must sample the same texture object and curve.
static func path_map(size_m: int, goal: Vector2 = Vector2.ZERO) -> ImageTexture:
	var key := "%d:%.4f:%.4f" % [size_m, goal.x, goal.y]
	if _path_maps.has(key):
		return _path_maps[key] as ImageTexture
	var texture := _build_path_map(size_m, goal)
	_path_maps[key] = texture
	return texture

static func path_extent(size_m: int) -> int:
	return size_m * MAP_EXTENT_MULTIPLIER

static func path_length(size_m: int, goal: Vector2 = Vector2.ZERO) -> float:
	var path := _curled_path(size_m, goal)
	var length_m := 0.0
	for index in range(1, path.size()):
		length_m += _route_point_3d(path[index], goal).distance_to(_route_point_3d(path[index - 1], goal))
	return length_m

static func _build_path_map(size_m: int, goal: Vector2) -> ImageTexture:
	var extent := path_extent(size_m)
	var resolution := extent + 1
	var pixel_count := resolution * resolution
	var progress := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var tangent_z := PackedFloat32Array()
	var distances := PackedFloat32Array()
	progress.resize(pixel_count)
	lateral.resize(pixel_count)
	tangent_z.resize(pixel_count)
	distances.resize(pixel_count)
	distances.fill(MAP_DISTANCE_SCALE)
	var path := _curled_path(size_m, goal)
	var lengths := PackedFloat32Array()
	lengths.resize(path.size())
	for index in range(1, path.size()):
		lengths[index] = lengths[index - 1] + _route_point_3d(path[index], goal).distance_to(_route_point_3d(path[index - 1], goal))
	var total_length := maxf(lengths[path.size() - 1], 0.001)
	var half := float(extent) * 0.5
	for segment in path.size() - 1:
		var a: Vector2 = path[segment]
		var b: Vector2 = path[segment + 1]
		var ab := b - a
		var ab_length_sq := maxf(ab.length_squared(), 0.00001)
		var margin := MAP_DISTANCE_SCALE
		var x0 := clampi(int(floorf(minf(a.x, b.x) + half - margin)), 0, extent)
		var x1 := clampi(int(ceilf(maxf(a.x, b.x) + half + margin)), 0, extent)
		var z0 := clampi(int(floorf(minf(a.y, b.y) + half - margin)), 0, extent)
		var z1 := clampi(int(ceilf(maxf(a.y, b.y) + half + margin)), 0, extent)
		for zi in range(z0, z1 + 1):
			for xi in range(x0, x1 + 1):
				var world := Vector2(float(xi) - half, float(zi) - half)
				var t := clampf((world - a).dot(ab) / ab_length_sq, 0.0, 1.0)
				var nearest := a + ab * t
				var distance := world.distance_to(nearest)
				var index := zi * resolution + xi
				if distance < distances[index]:
					distances[index] = distance
					progress[index] = (lengths[segment] + (lengths[segment + 1] - lengths[segment]) * t) / total_length
					lateral[index] = ab.normalized().cross(world - nearest)
					tangent_z[index] = ab.normalized().y
	var image := Image.create_empty(resolution, resolution, false, Image.FORMAT_RGBAF)
	for zi in resolution:
		for xi in resolution:
			var index := zi * resolution + xi
			image.set_pixel(xi, zi, Color(progress[index], lateral[index], tangent_z[index], distances[index]))
	return ImageTexture.create_from_image(image)

## The rise is vertical only; XZ stays a single line through the grove.
static func _curled_path(size_m: int, goal: Vector2) -> PackedVector2Array:
	return UndergroundStream.path_points(size_m, goal)

static func _route_point_3d(point: Vector2, goal: Vector2) -> Vector3:
	var offset := point - goal
	var unit := offset.x / 40.0
	var shoulder := maxf(1.0 - unit * unit, 0.0)
	var rise := 25.0 * shoulder * shoulder * shoulder
	return Vector3(point.x, RIVER_PLANE_Y + rise, point.y)
