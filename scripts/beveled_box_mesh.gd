class_name BeveledBoxMesh
extends RefCounted

## One lightweight chamfer per edge. The box stays inside the requested size;
## callers keep their existing transforms, attachment points and collision.
static func create(size: Vector3, bevel: float) -> ArrayMesh:
	var half := size * 0.5
	var cut := clampf(bevel, 0.001, minf(size.x, minf(size.y, size.z)) * 0.35)
	var inner := half - Vector3.ONE * cut
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var corners: Array[Vector3] = []
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = sign_value * half[axis]
				point[a] = uv.x * inner[a]
				point[b] = uv.y * inner[b]
				corners.append(point)
			_quad(tool, corners, _axis(axis, sign_value), size)
	for first in 3:
		for second in range(first + 1, 3):
			var length_axis := 3 - first - second
			for first_sign in [-1.0, 1.0]:
				for second_sign in [-1.0, 1.0]:
					var corners: Array[Vector3] = []
					for pair in [Vector2(0, -1), Vector2(0, 1), Vector2(1, 1), Vector2(1, -1)]:
						var point := Vector3.ZERO
						point[first] = first_sign * (inner[first] if pair.x > 0.5 else half[first])
						point[second] = second_sign * (half[second] if pair.x > 0.5 else inner[second])
						point[length_axis] = pair.y * inner[length_axis]
						corners.append(point)
					_quad(tool, corners, (_axis(first, first_sign) + _axis(second, second_sign)).normalized(), size)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_triangle(tool,
					Vector3(sx * half.x, sy * inner.y, sz * inner.z),
					Vector3(sx * inner.x, sy * half.y, sz * inner.z),
					Vector3(sx * inner.x, sy * inner.y, sz * half.z),
					Vector3(sx, sy, sz).normalized(), size)
	tool.generate_tangents()
	return tool.commit()

static func _axis(index: int, sign_value: float) -> Vector3:
	var axis := Vector3.ZERO
	axis[index] = sign_value
	return axis

static func _quad(tool: SurfaceTool, corners: Array[Vector3], outward: Vector3, size: Vector3) -> void:
	_triangle(tool, corners[0], corners[1], corners[2], outward, size)
	_triangle(tool, corners[0], corners[2], corners[3], outward, size)

static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, size: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for point in [a, b, c]:
		tool.set_normal(outward)
		tool.set_uv(_uv(point, outward, size))
		tool.add_vertex(point)

static func _uv(point: Vector3, normal: Vector3, size: Vector3) -> Vector2:
	var absolute := normal.abs()
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		return Vector2(point.z / size.z + 0.5, point.y / size.y + 0.5)
	if absolute.y >= absolute.z:
		return Vector2(point.x / size.x + 0.5, point.z / size.z + 0.5)
	return Vector2(point.x / size.x + 0.5, point.y / size.y + 0.5)
