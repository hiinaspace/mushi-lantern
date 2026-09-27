class_name ReturnHandoffVisual
extends MultiMeshInstance3D

## Brief, depth-tested gold motes mark the point where scored flyers enter the
## underground route. The GPU simulation owns their actual six-second descent.
const HANDOFF_SHADER := preload("res://shaders/return_handoff.gdshader")
const CUE_SECONDS := 0.9

var _ages := PackedFloat32Array()
var _started := PackedByteArray()
var _origins := PackedVector3Array()
var _material := ShaderMaterial.new()


static func beam_scale(progress: float) -> Vector2:
	var t := clampf(progress, 0.0, 1.0)
	return Vector2(lerpf(0.22, 0.11, t), lerpf(0.95, 2.8, t))


func configure(count: int) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_material.shader = HANDOFF_SHADER
	quad.material = _material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = quad
	instances.instance_count = maxi(0, count)
	instances.custom_aabb = AABB(Vector3(-5.0, -2.0, -5.0), Vector3(10.0, 5.0, 10.0))
	for i in instances.instance_count:
		instances.set_instance_transform(i, Transform3D.IDENTITY)
		instances.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
	multimesh = instances
	_ages.resize(instances.instance_count)
	_started.resize(instances.instance_count)
	_origins.resize(instances.instance_count)
	for i in instances.instance_count:
		_ages[i] = CUE_SECONDS
		_started[i] = 0


func update_handoffs(sim: Variant, delta: float, goal: Vector2, ground_y: float) -> void:
	if sim == null or multimesh == null:
		return
	for id_value: int in sim.committed_this_step:
		if id_value < 0 or id_value >= multimesh.instance_count or _started[id_value] != 0:
			continue
		_started[id_value] = 1
		_ages[id_value] = 0.0
		_origins[id_value] = sim.positions[id_value]
	for i in multimesh.instance_count:
		if _ages[i] >= CUE_SECONDS:
			continue
		_ages[i] = minf(CUE_SECONDS, _ages[i] + delta)
		var t := clampf(_ages[i] / CUE_SECONDS, 0.0, 1.0)
		var start := _origins[i]
		var side := sin(float(i) * 8.17) * 0.22
		var end := Vector3(goal.x + side, ground_y + 0.06, goal.y + cos(float(i) * 5.13) * 0.22)
		var pos := start.lerp(end, smoothstep(0.0, 1.0, t))
		var camera_basis := Basis.IDENTITY
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			camera_basis = camera.global_transform.basis.orthonormalized()
		var dimensions := beam_scale(t)
		var instance_basis := camera_basis * Basis.from_scale(Vector3(dimensions.x, dimensions.y, 1.0))
		multimesh.set_instance_transform(i, Transform3D(instance_basis, pos))
		var fade := 1.0 - smoothstep(0.48, 1.0, t)
		multimesh.set_instance_color(i, Color(1.0, 0.88, 0.44, fade))
