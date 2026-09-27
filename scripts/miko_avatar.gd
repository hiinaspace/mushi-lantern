extends Node3D

const VOICE_EXPRESSIONS = preload("res://scripts/miko_voice_expressions.gd")
const RENIK_LIMB = preload("res://addons/renik/renik_limb.gd")
const RENIK_PLACEMENT = preload("res://addons/renik/renik_placement.gd")

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
var _idle_head := -1
var _idle_head_rest := Quaternion.IDENTITY
var _idle_spine := -1
var _idle_spine_rest := Quaternion.IDENTITY
var _guide_look_engaged := false
var _guide_body_turning := false
var _guide_head_yaw := 0.0
var _guide_head_pitch := 0.0
var _guide_placement: RenIKPlacement3D
var _guide_leg_modifiers: Array[SkeletonModifier3D] = []
var _guide_foot_weight := 0.0
const GUIDE_ARM_DROP := 1.16
const GUIDE_LOOK_ENTER_DISTANCE := 4.2
const GUIDE_LOOK_EXIT_DISTANCE := 5.6
const GUIDE_BODY_TURN_START := 1.12
const GUIDE_BODY_TURN_STOP := 0.30
const GUIDE_STEP_ANGLE := PI / 6.0


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
			_idle_head = _idle_skeleton.find_bone("Head")
			_idle_spine = _idle_skeleton.find_bone("Spine")
			if _idle_left_arm >= 0:
				_idle_left_rest = _idle_skeleton.get_bone_pose_rotation(_idle_left_arm)
			if _idle_right_arm >= 0:
				_idle_right_rest = _idle_skeleton.get_bone_pose_rotation(_idle_right_arm)
			if _idle_head >= 0:
				_idle_head_rest = _idle_skeleton.get_bone_pose_rotation(_idle_head)
			if _idle_spine >= 0:
				_idle_spine_rest = _idle_skeleton.get_bone_pose_rotation(_idle_spine)
			_setup_guide_feet()


func _guide_marker(label: String, bone: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = label
	_idle_skeleton.add_child(marker)
	var index := _idle_skeleton.find_bone(bone)
	if index >= 0:
		marker.transform = _idle_skeleton.get_bone_global_rest(index)
	return marker


func _setup_guide_feet() -> void:
	# The placement head target follows the guide's root, not the expressive
	# head look bone. RenIK can therefore plant steps during a full body turn.
	_guide_marker("GuideHeadTarget", "Head")
	_guide_marker("GuideHipsTarget", "Hips")
	for side in ["Left", "Right"]:
		var foot := _guide_marker("Guide%sFootTarget" % side, side + "Foot")
		var leg: SkeletonModifier3D = RENIK_LIMB.new()
		leg.name = "Guide%sLeg" % side
		leg.preset = 2 if side == "Left" else 3
		leg.leaf_bone = side + "Foot"
		leg.lower_bone = side + "LowerLeg"
		leg.upper_bone = side + "UpperLeg"
		leg.mirror = side == "Right"
		leg.target = foot
		leg.assign_leg_defaults.call()
		leg.has_shoulder = false
		leg.active = false
		_idle_skeleton.add_child(leg)
		_guide_leg_modifiers.append(leg)
	_guide_placement = RENIK_PLACEMENT.new()
	_guide_placement.name = "GuideFootPlacement"
	_guide_placement.armature_skeleton_path = NodePath("..")
	_guide_placement.armature_head_target = NodePath("../GuideHeadTarget")
	_guide_placement.armature_hip_target = NodePath("../GuideHipsTarget")
	_guide_placement.armature_left_foot_target = NodePath("../GuideLeftFootTarget")
	_guide_placement.armature_right_foot_target = NodePath("../GuideRightFootTarget")
	_guide_placement.enable_hip_placement = false
	_guide_placement.collision_mask = 1
	# A turn of about 30 degrees warrants a small planted step.
	_guide_placement.rotation_threshold = GUIDE_STEP_ANGLE
	_idle_skeleton.add_child(_guide_placement)
	_guide_placement.set_process_internal(false)
	_guide_placement.set_physics_process_internal(false)


func set_guide_idle(enabled: bool) -> void:
	_guide_idle = enabled
	if enabled:
		_apply_guide_arm_pose(0.0)
	else:
		_guide_look_engaged = false
		_guide_body_turning = false
		_guide_foot_weight = 0.0
		for leg in _guide_leg_modifiers:
			leg.active = false
		_guide_head_yaw = 0.0
		_guide_head_pitch = 0.0
		if _idle_skeleton != null and _idle_spine >= 0:
			_idle_skeleton.set_bone_pose_rotation(_idle_spine, _idle_spine_rest)
		if _idle_skeleton != null and _idle_head >= 0:
			_idle_skeleton.set_bone_pose_rotation(_idle_head, _idle_head_rest)
	if not enabled and _idle_model != null:
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
	var has_floor := _guide_placement != null and _guide_placement.target_foot_is_valid and \
		(_guide_placement.left_ground != null or _guide_placement.right_ground != null)
	_guide_foot_weight = move_toward(_guide_foot_weight, 1.0 if has_floor else 0.0,
		minf(delta, 0.05) * 5.0)
	for leg in _guide_leg_modifiers:
		leg.influence = _guide_foot_weight
		leg.active = _guide_foot_weight > 0.001


func _physics_process(delta: float) -> void:
	if not _guide_idle or _guide_placement == null:
		return
	_guide_placement.update_placement(minf(delta, 0.05))
	_guide_placement.interpolate_transforms(1.0)


## The guide turns toward a nearby visitor. A wider exit radius prevents
## repeated turn/settle changes while the player crosses the threshold.
func set_guide_look_target(world_position: Vector3, active: bool, delta: float) -> void:
	if not _guide_idle or _idle_model == null:
		return
	var distance := Vector2(world_position.x - global_position.x,
		world_position.z - global_position.z).length()
	if _guide_look_engaged:
		_guide_look_engaged = active and distance < GUIDE_LOOK_EXIT_DISTANCE
	else:
		_guide_look_engaged = active and distance < GUIDE_LOOK_ENTER_DISTANCE
	var desired_yaw := rotation.y
	var desired_head_pitch := 0.0
	if _guide_look_engaged:
		var toward := world_position - (global_position + Vector3.UP * 1.45)
		var horizontal := Vector2(toward.x, toward.z).length()
		if horizontal > 0.1:
			var target_yaw := atan2(toward.x, toward.z)
			desired_yaw = target_yaw
			desired_head_pitch = clampf(atan2(toward.y, horizontal), -0.23, 0.22)
	var step := maxf(delta, 0.0)
	var remaining_yaw := wrapf(desired_yaw - rotation.y, -PI, PI)
	if not _guide_look_engaged:
		_guide_body_turning = false
	elif _guide_body_turning:
		if absf(remaining_yaw) < GUIDE_BODY_TURN_STOP:
			_guide_body_turning = false
	elif absf(remaining_yaw) > GUIDE_BODY_TURN_START:
		_guide_body_turning = true
	# Small shifts stay in her head. A visitor behind her triggers a grounded
	# body turn that settles inside the head's comfortable look range; the root
	# keeps that heading after the visitor leaves.
	if _guide_body_turning:
		rotation.y = rotate_toward(rotation.y, desired_yaw, step * 1.1)
	if _guide_look_engaged:
		_guide_head_yaw = move_toward(_guide_head_yaw,
			clampf(wrapf(desired_yaw - rotation.y, -PI, PI), -0.52, 0.52), step * 2.2)
	else:
		_guide_head_yaw = move_toward(_guide_head_yaw, 0.0, step * 1.7)
	_guide_head_pitch = move_toward(_guide_head_pitch, desired_head_pitch, step * 1.2)
	if _idle_skeleton != null and _idle_spine >= 0:
		_idle_skeleton.set_bone_pose_rotation(_idle_spine, _idle_spine_rest)
	if _idle_skeleton != null and _idle_head >= 0:
		_idle_skeleton.set_bone_pose_rotation(_idle_head, _idle_head_rest *
			Quaternion(Vector3.UP, _guide_head_yaw) * Quaternion(Vector3.RIGHT, -_guide_head_pitch))


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
