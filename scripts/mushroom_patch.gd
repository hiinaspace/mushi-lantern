class_name MushroomPatch
extends Node3D

var boundary: MeshInstance3D

func _ready() -> void:
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(-0.5, 0.0, 0.3), Vector3(0.4, 0.0, 0.5)]
	for index: int in offsets.size():
		var size := 1.0 if index == 0 else 0.55
		var stem := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.06 * size
		cylinder.bottom_radius = 0.09 * size
		cylinder.height = 0.22 * size
		stem.mesh = cylinder
		stem.position = offsets[index] + Vector3(0.0, cylinder.height * 0.5, 0.0)
		stem.material_override = _blue_material(Color("568fae"), 0.1)
		add_child(stem)
		var cap := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.4 * size
		sphere.height = 0.22 * size
		cap.mesh = sphere
		cap.position = offsets[index] + Vector3(0.0, 0.24 * size, 0.0)
		cap.material_override = _blue_material(Color("348bf0"), 0.45)
		add_child(cap)
	boundary = MeshInstance3D.new()
	boundary.position.y = 0.04
	boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _blue_material(Color(0.15, 0.4, 0.85, 0.2), 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	boundary.material_override = material
	add_child(boundary)

func set_radius(radius: float) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(0.1, radius - 0.025)
	ring.outer_radius = radius + 0.025
	ring.rings = 48
	boundary.mesh = ring

func show_boundary(enabled: bool) -> void:
	boundary.visible = enabled

func _blue_material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = emission > 0.0
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = emission
	return material
