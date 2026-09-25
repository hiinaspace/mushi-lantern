class_name NightEnvironment
extends RefCounted

const NIGHT_SKY: Shader = preload("res://shaders/night_sky.gdshader")
const BEACON_HEIGHT_M := 300.0


static func configure(environment: Environment) -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = NIGHT_SKY
	sky_material.set_shader_parameter("night_vision", 1.0)
	var sky := Sky.new()
	# TIME animates only a few bright stars. The radiance cubemap is unused for
	# illumination here, so keep its unavoidable refresh tiny and incremental.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.background_energy_multiplier = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.18, 0.28)
	environment.ambient_light_energy = 0.012
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# The glyph shader draws its own halo so lit grass and avatars stay crisp.
	environment.glow_enabled = false


static func set_night_vision(environment: Environment, value: float) -> void:
	if environment.sky == null:
		return
	var sky_material := environment.sky.sky_material as ShaderMaterial
	if sky_material != null:
		sky_material.set_shader_parameter("night_vision", clampf(value, 0.0, 1.0))


static func set_visual_tuning(environment: Environment, values: Dictionary) -> void:
	if environment.sky == null:
		return
	var material := environment.sky.sky_material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("star_reveal_start", float(values.get("star_start", 0.14)))
	material.set_shader_parameter("star_reveal_end", float(values.get("star_end", 0.89)))
	material.set_shader_parameter("milky_way_reveal_start", float(values.get("milky_start", 0.64)))
	material.set_shader_parameter("milky_way_reveal_end", float(values.get("milky_end", 0.96)))


static func add_beacon(parent: Node3D, ground_height: float) -> Node3D:
	var beacon := Node3D.new()
	beacon.name = "GoalSkyBeacon"
	beacon.position = Vector3(0.0, ground_height, 0.0)
	parent.add_child(beacon)

	# Even when a ridge hides the ground marker, the upper beam remains above it.
	# These meshes emit visible color only; neither creates light or casts shadows.
	var core := _beam_mesh("Core", 0.20, Color(0.22, 1.0, 0.43, 1.0), false)
	beacon.add_child(core)
	var halo := _beam_mesh("Halo", 0.82, Color(0.10, 0.72, 0.28, 0.075), true)
	beacon.add_child(halo)
	return beacon


static func _beam_mesh(mesh_name: String, radius: float, color: Color, transparent: bool) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = BEACON_HEIGHT_M
	cylinder.radial_segments = 12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	# Keep the navigation beam readable without giving it the strongest HDR halo.
	material.emission_energy_multiplier = 0.3
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = cylinder
	instance.material_override = material
	instance.position.y = BEACON_HEIGHT_M * 0.5
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
