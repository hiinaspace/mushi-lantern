class_name LightField
extends RefCounted

enum Mode { CLEAR, BLUE, ORANGE }

var world_surface: Variant
var environment_obstacles: Array[Dictionary] = []

var source_position: Vector3 = Vector3.ZERO
var source_direction: Vector3 = Vector3(0.0, -0.35, -0.94).normalized()
var mode: Mode = Mode.CLEAR
var shutter_openness: float = 1.0
var range_m: float = 10.5
var half_angle_degrees: float = 38.0
var edge_softness: float = 0.18
var mode_strength: float = 1.0
var obstacle_centers: PackedVector2Array = PackedVector2Array()
var obstacle_radii: PackedFloat32Array = PackedFloat32Array()

func update_transform(position: Vector3, direction: Vector3) -> void:
	source_position = position
	source_direction = direction.normalized()

func ground_target(body_height: float = 0.42) -> Vector2:
	var direction := source_direction
	var distance_along: float = range_m * 0.62
	if direction.y < -0.03:
		distance_along = clampf((body_height - source_position.y) / direction.y, 1.0, range_m * 0.9)
	var point := source_position + direction * distance_along
	return Vector2(point.x, point.z)

func sample(world_position: Vector3) -> float:
	if shutter_openness <= 0.0001 or mode == Mode.CLEAR:
		return 0.0
	var offset := world_position - source_position
	var distance := offset.length()
	if distance <= 0.001 or distance >= range_m:
		return 0.0
	var cosine := source_direction.dot(offset / distance)
	var outer_cos := cos(deg_to_rad(half_angle_degrees))
	var inner_cos := cos(deg_to_rad(half_angle_degrees * (1.0 - edge_softness)))
	var angular := smoothstep(outer_cos, inner_cos, cosine)
	if angular <= 0.0:
		return 0.0
	var normalized_distance := distance / range_m
	var radial := 1.0 - smoothstep(0.18, 1.0, normalized_distance)
	if world_surface != null:
		if environment_occluded(source_position, world_position):
			return 0.0
	elif is_occluded(Vector2(source_position.x, source_position.z), Vector2(world_position.x, world_position.z)):
		return 0.0
	return clampf(mode_strength * shutter_openness * angular * radial, 0.0, 1.0)

func is_occluded(from: Vector2, to: Vector2) -> bool:
	for index: int in obstacle_centers.size():
		if _segment_circle_intersects(from, to, obstacle_centers[index], obstacle_radii[index]):
			return true
	return false

static func _segment_circle_intersects(from: Vector2, to: Vector2, center: Vector2, radius: float) -> bool:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return from.distance_squared_to(center) < radius * radius
	var t := clampf((center - from).dot(segment) / length_squared, 0.0, 1.0)
	var closest := from + segment * t
	return closest.distance_squared_to(center) < radius * radius

func flight_target(min_height: float, max_height: float) -> Vector3:
	var target := source_position + source_direction * 3.0
	target.y = clampf(target.y, min_height, max_height)
	return target


func environment_occluded(from: Vector3, to: Vector3) -> bool:
	# Debug overlay only; GPU flight independently samples the shared surface.
	var from_xz := Vector2(from.x, from.z)
	var segment := Vector2(to.x - from.x, to.z - from.z)
	var length_sq := segment.length_squared()
	for obstacle: Dictionary in environment_obstacles:
		var t := clampf((obstacle.center - from_xz).dot(segment) / maxf(length_sq, 0.000001), 0.0, 1.0)
		var nearest := from_xz + segment * t
		var y := lerpf(from.y, to.y, t)
		if nearest.distance_squared_to(obstacle.center) < float(obstacle.radius) * float(obstacle.radius) and y >= float(obstacle.bottom) and y <= float(obstacle.top):
			return true
	for step: int in range(1, 13):
		var p := from.lerp(to, float(step) / 13.0)
		if p.y < float(world_surface.get_height_at(Vector2(p.x, p.z))) + 0.04:
			return true
	return false
