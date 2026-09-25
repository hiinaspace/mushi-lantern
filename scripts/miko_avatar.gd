extends Node3D

const VOICE_EXPRESSIONS = preload("res://scripts/miko_voice_expressions.gd")

## Per-instance atlas hue offset, measured in turns. Zero keeps the authored red.
@export_range(0.0, 1.0, 0.001) var hue_shift: float = 0.0:
	set(value):
		hue_shift = fposmod(value, 1.0)
		_update_materials()

## Pupil/iris glow for dark scenes. Zero preserves the authored NPC appearance.
@export_range(0.0, 8.0, 0.1) var eye_glow: float = 0.0:
	set(value):
		eye_glow = maxf(value, 0.0)
		_update_materials()

var voice_glow: float = 0.0:
	set(value):
		voice_glow = clampf(value, 0.0, 1.0)
		_update_materials()


var _instance_materials: Array[ShaderMaterial] = []
var _voice_expressions: RefCounted


func _ready() -> void:
	# Imported resources are shared globally; override each surface on this instance.
	for mesh_node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			if source is ShaderMaterial:
				var local := (source as ShaderMaterial).duplicate() as ShaderMaterial
				if source.next_pass is ShaderMaterial:
					var local_outline := (source.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
					local.next_pass = local_outline
					_instance_materials.append(local_outline)
				mesh_instance.set_surface_override_material(surface, local)
				_instance_materials.append(local)
	_update_materials()
	_voice_expressions = VOICE_EXPRESSIONS.new()
	_voice_expressions.call("configure", self)


func set_avatar_color(hue_turns: float, glow_strength: float = 2.5) -> void:
	## Deterministic API for preview instances and later player color choices.
	hue_shift = hue_turns
	eye_glow = glow_strength


func set_voice_level(level: float) -> void:
	voice_glow = level




func apply_voice_visemes(weights: PackedFloat32Array, delta: float) -> void:
	if _voice_expressions != null:
		_voice_expressions.call("apply", weights, delta)


func _exit_tree() -> void:
	if _voice_expressions != null:
		_voice_expressions.call("reset")


func _update_materials() -> void:
	for material in _instance_materials:
		material.set_shader_parameter("_MikoHueShift", hue_shift)
		material.set_shader_parameter("_MikoEyeGlow", eye_glow)
		material.set_shader_parameter("_MikoVoiceGlow", pow(voice_glow, 0.7) * 1.5)
		material.set_shader_parameter("_MikoLightCompression", 0.8)
