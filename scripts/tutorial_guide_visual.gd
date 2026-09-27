class_name TutorialGuideVisual
extends Node3D

## A purely decorative, non-population guide. Its flight never changes score.
const DORMANT_COLOR := Color(0.18, 0.58, 1.0)
const WAKING_COLOR := Color(1.0, 0.37, 0.11)
const NEUTRAL_COLOR := Color(0.58, 0.95, 0.84)
const GLYPH_SHADER: Shader = preload("res://shaders/mushi_glyph.gdshader")

var _jar: MeshInstance3D
var _jar_top: MeshInstance3D
var _jar_bottom: MeshInstance3D
var _glass_material: ShaderMaterial
var _glyph: MultiMeshInstance3D
var _glyph_image: Image
var _glyph_texture: ImageTexture
var _glyph_material: ShaderMaterial
var _glow: OmniLight3D
var _creature: Node3D
var _state: TutorialDirector.GuideState = TutorialDirector.GuideState.JARRED
var _released := false
var _age := 0.0
var _display_arousal := 0.45
var _release_tween: Tween
var _blue_pull := Vector3.ZERO
var _previous_glyph_world := Vector3.ZERO


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_age += delta
	if not _released:
		var waking := _state == TutorialDirector.GuideState.WAKING
		var dormant := _state == TutorialDirector.GuideState.DORMANT
		var flutter := 6.4 if waking else 1.6 if dormant else 5.2
		var height := 0.055 if waking else -0.075 if dormant else 0.0
		if _state == TutorialDirector.GuideState.JARRED:
			# Give blue light a clear before/after: an alert mushi hops and
			# wheels within the jar instead of hovering nearly still.
			_creature.position = Vector3(sin(_age * 2.9) * 0.085,
				0.025 + absf(sin(_age * flutter)) * 0.12,
				cos(_age * 2.3) * 0.07)
		else:
			var motion := 0.060 if waking else 0.008
			var drift := Vector3(sin(_age * flutter * 0.54) * motion,
				height + sin(_age * flutter) * motion, cos(_age * flutter * 0.46) * motion)
			_creature.position = _creature.position.lerp(drift + (_blue_pull if dormant else Vector3.ZERO),
				1.0 - exp(-delta * (1.3 if dormant else 3.0)))
		_glow.light_energy = (0.78 if waking else 0.12 if dormant else 0.32) * (0.88 + 0.12 * sin(_age * flutter))
	var target_arousal := 1.0 if _state == TutorialDirector.GuideState.WAKING else 0.0 if _state == TutorialDirector.GuideState.DORMANT else 0.45
	_display_arousal = move_toward(_display_arousal, target_arousal, delta * 1.8)
	_update_glyph()


func set_light_source(source_world_position: Vector3) -> void:
	var direction := source_world_position - global_position
	direction.y = 0.0
	_blue_pull = direction.normalized() * 0.21 if direction.length_squared() > 0.001 else Vector3.ZERO


func reset_guide(world_position: Vector3) -> void:
	if _release_tween != null and _release_tween.is_running():
		_release_tween.kill()
	_released = false
	_age = 0.0
	_display_arousal = 0.45
	_blue_pull = Vector3.ZERO
	scale = Vector3.ONE
	global_position = world_position
	_creature.position = Vector3.ZERO
	_creature.rotation = Vector3.ZERO
	_creature.scale = Vector3.ONE
	_creature.visible = true
	visible = true
	_jar.visible = true
	_jar.position.y = 0.0
	_jar_top.visible = true
	_jar_top.position.y = 0.967
	_jar_bottom.visible = true
	_jar_bottom.position.y = 0.085
	_set_cloche_opacity(1.0)
	_previous_glyph_world = _creature.global_position
	_set_state(TutorialDirector.GuideState.JARRED)
	_update_glyph()


func set_guide_state(state: TutorialDirector.GuideState) -> void:
	if _released:
		return
	_set_state(state)


func release_to(goal_above: Vector3, stream_below: Vector3) -> void:
	if _released:
		return
	_released = true
	_release_tween = create_tween()
	_release_tween.tween_property(_jar, "position:y", 0.5, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_release_tween.parallel().tween_property(_jar_top, "position:y", 1.467, 0.5)
	_release_tween.parallel().tween_property(_jar_bottom, "position:y", 0.585, 0.5)
	_release_tween.parallel().tween_method(_set_cloche_opacity, 1.0, 0.0, 0.5)
	_release_tween.tween_property(_creature, "global_position", global_position + Vector3.UP * 1.25, 0.48).set_trans(Tween.TRANS_SINE)
	_release_tween.tween_property(_creature, "global_position", goal_above, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_release_tween.tween_property(_creature, "global_position", stream_below, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_release_tween.parallel().tween_property(_creature, "scale", Vector3.ONE * 0.15, 0.85)
	_release_tween.parallel().tween_property(_glow, "light_energy", 0.0, 0.85)
	_release_tween.tween_callback(func() -> void: _creature.visible = false)


func hide_for_skip() -> void:
	if _release_tween != null and _release_tween.is_running():
		_release_tween.kill()
	_released = true
	visible = false


func _set_state(state: TutorialDirector.GuideState) -> void:
	_state = state
	var color := NEUTRAL_COLOR
	if state == TutorialDirector.GuideState.DORMANT:
		color = DORMANT_COLOR
	elif state == TutorialDirector.GuideState.WAKING:
		color = WAKING_COLOR
	_glow.light_color = color
	_glow.light_energy = 0.12 if state == TutorialDirector.GuideState.DORMANT else 0.78 if state == TutorialDirector.GuideState.WAKING else 0.32
	_update_glyph()


func _build() -> void:
	_creature = Node3D.new()
	_creature.name = "GuideMushi"
	add_child(_creature)
	_jar = _mesh_instance(_cloche_mesh(), "GuideJar")
	_glass_material = ShaderMaterial.new()
	var glass_shader := Shader.new()
	glass_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float fade = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.3);
	ALBEDO = vec3(0.065, 0.095, 0.11);
	ROUGHNESS = 0.16;
	METALLIC = 0.08;
	ALPHA = (0.045 + rim * 0.24) * fade;
	EMISSION = vec3(0.025, 0.045, 0.055) * rim;
}
"""
	_glass_material.shader = glass_shader
	_jar.material_override = _glass_material

	var knob := SphereMesh.new()
	knob.radius = 0.055
	knob.height = 0.075
	_jar_top = _mesh_instance(knob, "JarLid")
	_jar_top.position.y = 0.967
	_jar_top.material_override = _dark_jar_material(Color("252c29"))
	var open_rim := TorusMesh.new()
	open_rim.inner_radius = 0.357
	open_rim.outer_radius = 0.378
	_jar_bottom = _mesh_instance(open_rim, "JarBase")
	_jar_bottom.position.y = 0.085
	_jar_bottom.material_override = _dark_jar_material(Color("1f2523"))

	_build_glyph()
	_glow = OmniLight3D.new()
	_glow.position.y = 0.45
	_glow.omni_range = 1.5
	_glow.light_energy = 0.4
	_creature.add_child(_glow)
	_set_state(TutorialDirector.GuideState.JARRED)


func _cloche_mesh() -> ArrayMesh:
	# Rings form a gently tapered wall and rounded closed crown. The bottom
	# edge has no triangles across its center, so the guide can fly out below.
	var profile := [Vector2(0.37, 0.085), Vector2(0.37, 0.20),
		Vector2(0.355, 0.61), Vector2(0.33, 0.77), Vector2(0.28, 0.85),
		Vector2(0.20, 0.92), Vector2(0.105, 0.966), Vector2(0.008, 0.985)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 32
	for ring: int in profile.size() - 1:
		for side: int in sides:
			var angle_a := TAU * float(side) / float(sides)
			var angle_b := TAU * float(side + 1) / float(sides)
			var low: Vector2 = profile[ring]
			var high: Vector2 = profile[ring + 1]
			var a := Vector3(cos(angle_a) * low.x, low.y, sin(angle_a) * low.x)
			var b := Vector3(cos(angle_b) * low.x, low.y, sin(angle_b) * low.x)
			var c := Vector3(cos(angle_a) * high.x, high.y, sin(angle_a) * high.x)
			var d := Vector3(cos(angle_b) * high.x, high.y, sin(angle_b) * high.x)
			for vertex: Vector3 in [a, c, b, b, c, d]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()


func _mesh_instance(mesh: Mesh, node_name: String, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent == null:
		add_child(instance)
	else:
		parent.add_child(instance)
	return instance


func _dark_jar_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A dark unshaded value keeps the lid legible during full adaptation
	# without any emitted light or bloom.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _set_cloche_opacity(opacity: float) -> void:
	_glass_material.set_shader_parameter("fade", opacity)
	for piece: MeshInstance3D in [_jar_top, _jar_bottom]:
		var material := piece.material_override as StandardMaterial3D
		var color := material.albedo_color
		color.a = opacity
		material.albedo_color = color


func _build_glyph() -> void:
	# The gameplay swarm also draws one quad with this shader. A one-instance
	# MultiMesh gives the guide exactly the same head-and-tail glyph silhouette,
	# ring edge and energy palette while its scripted path stays decorative.
	_glyph_image = Image.create(1, 3, false, Image.FORMAT_RGBAF)
	_glyph_texture = ImageTexture.create_from_image(_glyph_image)
	_glyph_material = ShaderMaterial.new()
	_glyph_material.shader = GLYPH_SHADER
	_glyph_material.set_shader_parameter("state_texture", _glyph_texture)
	_glyph_material.set_shader_parameter("interpolation_alpha", 1.0)
	_glyph_material.set_shader_parameter("face_camera", false)
	_glyph_material.set_shader_parameter("glow_strength", 0.72)
	_glyph_material.set_shader_parameter("bloom_hdr_gain", 1.4)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = _glyph_material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = quad
	instances.instance_count = 1
	instances.set_instance_transform(0, Transform3D.IDENTITY)
	instances.set_instance_color(0, Color.WHITE)
	instances.set_instance_custom_data(0, Color(1.0, 0.17, 1.0, 1.0))
	instances.custom_aabb = AABB(Vector3(-128.0, -40.0, -128.0), Vector3(256.0, 90.0, 256.0))
	_glyph = MultiMeshInstance3D.new()
	_glyph.name = "GuideGameplayGlyph"
	_glyph.multimesh = instances
	_glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_creature.add_child(_glyph)


func _update_glyph() -> void:
	if _glyph_image == null or _glyph_texture == null or _creature == null:
		return
	var center := _creature.global_position + Vector3.UP * 0.43
	var state := Color(center.x, center.y, center.z, _display_arousal)
	_glyph_image.set_pixel(0, 0, state)
	_glyph_image.set_pixel(0, 1, state)
	# The gameplay shader uses row 2 as heading, including screen-plane glyph
	# rotation. Turning the old creature node had no visible effect because its
	# one-agent glyph faces the camera and writes clip-space vertices directly.
	var heading := Vector3.UP
	if not _released and _state in [TutorialDirector.GuideState.JARRED, TutorialDirector.GuideState.WAKING]:
		var turn := _age * (3.4 if _state == TutorialDirector.GuideState.WAKING else 2.8)
		heading = Vector3(0.52 * sin(turn * 0.7), 0.65 * cos(turn), sin(turn)).normalized()
	elif _released:
		var travel := _creature.global_position - _previous_glyph_world
		if travel.length_squared() > 0.000001:
			heading = travel.normalized()
	_glyph_image.set_pixel(0, 2, Color(heading.x, heading.y, heading.z, 0.0))
	_glyph_texture.update(_glyph_image)
	_previous_glyph_world = _creature.global_position
