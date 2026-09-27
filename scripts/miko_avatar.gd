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
var _guide_idle := false
var _idle_model: Node3D
var _idle_origin: Vector3
var _idle_rotation: Vector3
var _idle_seconds := 0.0
var _idle_skeleton: Skeleton3D
var _idle_left_arm := -1
var _idle_right_arm := -1
var _idle_left_rest := Quaternion.IDENTITY
var _idle_right_rest := Quaternion.IDENTITY
const GUIDE_ARM_DROP := 1.16


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
	_idle_model = get_node_or_null("Model") as Node3D
	if _idle_model != null:
		_idle_origin = _idle_model.position
		_idle_rotation = _idle_model.rotation
		var skeletons := _idle_model.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_idle_skeleton = skeletons[0] as Skeleton3D
			_idle_left_arm = _idle_skeleton.find_bone("LeftUpperArm")
			_idle_right_arm = _idle_skeleton.find_bone("RightUpperArm")
			if _idle_left_arm >= 0:
				_idle_left_rest = _idle_skeleton.get_bone_pose_rotation(_idle_left_arm)
			if _idle_right_arm >= 0:
				_idle_right_rest = _idle_skeleton.get_bone_pose_rotation(_idle_right_arm)


func set_guide_idle(enabled: bool) -> void:
	_guide_idle = enabled
	if enabled:
		_apply_guide_arm_pose(0.0)
	elif _idle_model != null:
		_idle_model.position = _idle_origin
		_idle_model.rotation = _idle_rotation
		if _idle_skeleton != null:
			if _idle_left_arm >= 0:
				_idle_skeleton.set_bone_pose_rotation(_idle_left_arm, _idle_left_rest)
			if _idle_right_arm >= 0:
				_idle_skeleton.set_bone_pose_rotation(_idle_right_arm, _idle_right_rest)


func _process(delta: float) -> void:
	if not _guide_idle or _idle_model == null:
		return
	_idle_seconds += delta
	# A small whole-body breath and weight shift avoids retargeting a foreign
	# humanoid skeleton during the jam. The feet move less than a centimetre.
	_idle_model.position = _idle_origin + Vector3(0.003 * sin(_idle_seconds * 1.1), 0.004 * sin(_idle_seconds * 2.0), 0.0)
	_idle_model.rotation = _idle_rotation + Vector3(0.0, 0.007 * sin(_idle_seconds * 0.6), 0.003 * sin(_idle_seconds * 1.1))
	_apply_guide_arm_pose(_idle_seconds)


func _apply_guide_arm_pose(seconds: float) -> void:
	if _idle_skeleton == null:
		return
	# Both upper-arm local +X axes lower their respective outward T-pose arms.
	# Keep the angle well short of vertical so the hands clear the sleeves/skirt.
	var breath := 0.014 * sin(seconds * 2.0)
	if _idle_left_arm >= 0:
		_idle_skeleton.set_bone_pose_rotation(_idle_left_arm,
			_idle_left_rest * Quaternion(Vector3.RIGHT, GUIDE_ARM_DROP + breath))
	if _idle_right_arm >= 0:
		_idle_skeleton.set_bone_pose_rotation(_idle_right_arm,
			_idle_right_rest * Quaternion(Vector3.RIGHT, GUIDE_ARM_DROP + breath))


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
