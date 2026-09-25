extends SkeletonModifier3D
"""Retargets the RPG pack's lower-body locomotion onto the Miko VRM skeleton.

Attach this node under the target Skeleton3D. The source animation scene stays
hidden and supplies a directional blend space; only hips and leg rotations are
copied, leaving the head and arms available to VR tracking and IK.
"""

@export var animation_source_scene: PackedScene
@export_range(0.1, 3.0, 0.05) var full_speed_mps: float = 1.8

const ANIMATIONS := {
	"idle": &"UnarmedIdle",
	"forward": &"UnarmedRunForward",
	"back": &"UnarmedRunBackward",
	"left": &"UnarmedStrafeLeft",
	"right": &"UnarmedStrafeRight",
	"forward_left": &"UnarmedStrafeForwardLeft",
	"forward_right": &"UnarmedStrafeForwardRight",
	"back_left": &"UnarmedStrafeBackwardLeft",
	"back_right": &"UnarmedStrafeBackwardRight",
}

const BONE_MAP := [
	[&"B_Pelvis", &"Hips", true],
	[&"B_L_Thigh", &"LeftUpperLeg", false],
	[&"B_L_Calf", &"LeftLowerLeg", false],
	[&"B_L_Foot", &"LeftFoot", false],
	[&"B_L_Toe0", &"Left toe", false],
	[&"B_R_Thigh", &"RightUpperLeg", false],
	[&"B_R_Calf", &"RightLowerLeg", false],
	[&"B_R_Foot", &"RightFoot", false],
	[&"B_R_Toe0", &"Right toe", false],
	[&"B_L_UpperArm", &"LeftUpperArm", false],
	[&"B_L_Forearm", &"LeftLowerArm", false],
	[&"B_L_Hand", &"LeftHand", false],
	[&"B_R_UpperArm", &"RightUpperArm", false],
	[&"B_R_Forearm", &"RightLowerArm", false],
	[&"B_R_Hand", &"RightHand", false],
]

var _source_root: Node3D
var _source_skeleton: Skeleton3D
var _source_player: AnimationPlayer
var _animation_tree: AnimationTree
var _blend_space: AnimationNodeBlendSpace2D
var _blend_tree: AnimationNodeBlendTree
var _move_direction := Vector2.ZERO
var _locomotion_speed := 0.0
var _bone_pairs: Array[Dictionary] = []
var _warned_missing_asset := false
var _tracked_hands: int = 0
var _gait_phase: float = 0.0
var _run_cycle_length: float = 0.7


func _process(delta: float) -> void:
	var intensity := clampf(_locomotion_speed / maxf(full_speed_mps, 0.01), 0.0, 1.0)
	var rate := clampf(intensity, 0.35, 1.0) if intensity > 0.01 else 0.0
	_gait_phase = fposmod(_gait_phase + minf(delta, 0.05) * rate * TAU / _run_cycle_length, TAU)


func _ready() -> void:
	if animation_source_scene == null:
		if not _warned_missing_asset:
			push_warning("Miko leg animation source is not assigned; avatar will keep its default pose.")
			_warned_missing_asset = true
		return
	_source_root = animation_source_scene.instantiate() as Node3D
	if _source_root == null:
		push_warning("Miko leg animation source root must be Node3D.")
		return
	add_child(_source_root)
	_source_root.name = "AnimationSource"
	_source_root.visible = false
	_source_skeleton = _find_skeleton(_source_root)
	_source_player = _find_animation_player(_source_root)
	if _source_skeleton == null or _source_player == null:
		push_warning("Miko leg animation source needs a Skeleton3D and AnimationPlayer.")
		return
	_build_bone_pairs()
	_build_blend_tree()


func set_move_direction(direction: Vector2) -> void:
	## Local movement direction: +X is right, +Y is forward.
	_move_direction = direction.limit_length(1.0)
	_update_blend_position()


func set_locomotion_speed(speed_mps: float) -> void:
	_locomotion_speed = maxf(speed_mps, 0.0)
	_update_blend_position()


func set_tracked_hands(mask: int) -> void:
	_tracked_hands = mask


func _build_blend_tree() -> void:
	_blend_space = AnimationNodeBlendSpace2D.new()
	_blend_space.min_space = Vector2(-1.0, -1.0)
	_blend_space.max_space = Vector2(1.0, 1.0)
	_blend_space.snap = Vector2(0.0, 0.0)
	var positions := {
		"idle": Vector2.ZERO,
		"forward": Vector2(0.0, 1.0),
		"back": Vector2(0.0, -1.0),
		"left": Vector2(-1.0, 0.0),
		"right": Vector2(1.0, 0.0),
		"forward_left": Vector2(-1.0, 1.0),
		"forward_right": Vector2(1.0, 1.0),
		"back_left": Vector2(-1.0, -1.0),
		"back_right": Vector2(1.0, -1.0),
	}
	var animation_library := _source_player.get_animation_library(&"")
	if animation_library.has_animation(ANIMATIONS["forward"]):
		_run_cycle_length = maxf(animation_library.get_animation(ANIMATIONS["forward"]).length, 0.1)
	for key in ANIMATIONS:
		var animation_name: StringName = ANIMATIONS[key]
		if not animation_library.has_animation(animation_name):
			continue
		# Imported glTF clips do not carry a loop flag. Without this, the blend
		# space holds its last frame after one stride.
		animation_library.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
		var animation_node := AnimationNodeAnimation.new()
		animation_node.animation = animation_name
		_blend_space.add_blend_point(animation_node, positions[key], -1, key)
	if _blend_space.get_blend_point_count() == 0:
		push_warning("Miko leg animation source contains none of the expected Unarmed clips.")
		return
	_animation_tree = AnimationTree.new()
	_animation_tree.name = "LocomotionBlendTree"
	_blend_tree = AnimationNodeBlendTree.new()
	_blend_tree.add_node("Locomotion", _blend_space, Vector2(0, 0))
	_blend_tree.add_node("StrideRate", AnimationNodeTimeScale.new(), Vector2(240, 0))
	_blend_tree.connect_node("StrideRate", 0, "Locomotion")
	_blend_tree.connect_node("output", 0, "StrideRate")
	_animation_tree.tree_root = _blend_tree
	_animation_tree.anim_player = NodePath("../AnimationSource/AnimationPlayer")
	_animation_tree.root_node = NodePath("../AnimationSource")
	_animation_tree.process_priority = -100
	add_child(_animation_tree)
	_animation_tree.active = true
	_update_blend_position()


func _update_blend_position() -> void:
	if _animation_tree == null:
		return
	var intensity := clampf(_locomotion_speed / maxf(full_speed_mps, 0.01), 0.0, 1.0)
	var blend := _move_direction * intensity
	# The blend space is the AnimationTree root, so its parameter is not nested
	# under the node type name.
	_animation_tree.set("parameters/Locomotion/blend_position", blend)
	# The pack provides run cycles, so slow the cycle to match game movement.
	_animation_tree.set("parameters/StrideRate/scale", 1.0 if intensity <= 0.01 else clampf(intensity, 0.35, 1.0))


func _build_bone_pairs() -> void:
	var target := get_skeleton()
	if target == null:
		push_warning("Miko leg animation helper must be a child of target Skeleton3D.")
		return
	for mapping in BONE_MAP:
		var source_index := _source_skeleton.find_bone(mapping[0])
		var target_index := target.find_bone(mapping[1])
		if source_index < 0 or target_index < 0:
			continue
		_bone_pairs.append({
			"source": source_index,
			"target": target_index,
			"hips": mapping[2],
			"side": 1 if String(mapping[1]).begins_with("Left") else 2 if String(mapping[1]).begins_with("Right") else 0,
			"arm": String(mapping[1]).contains("Arm") or String(mapping[1]).ends_with("Hand"),
		})
	if _bone_pairs.size() < 8:
		push_warning("Miko leg animation retarget map is incomplete; found %d lower body bones." % _bone_pairs.size())


func _process_modification() -> void:
	var target := get_skeleton()
	if target == null or _source_skeleton == null or _bone_pairs.is_empty():
		return
	var amount := clampf(_locomotion_speed / maxf(full_speed_mps, 0.01), 0.0, 1.0)
	# These are athletic run clips; on Ukon's shorter limbs their full angular
	# range reads as kicks or splits. Preserve cadence while halving amplitude.
	var influence := smoothstep(0.0, 0.18, amount) * 0.5
	for pair in _bone_pairs:
		if pair.arm and (int(pair.side) & _tracked_hands) != 0:
			continue
		var source_index: int = pair.source
		var target_index: int = pair.target
		var source_rest := _source_skeleton.get_bone_rest(source_index)
		var source_pose := _source_skeleton.get_bone_pose(source_index)
		var target_rest := target.get_bone_rest(target_index)
		var current_pose := target.get_bone_pose(target_index)
		# The two rigs have different local bone axes. Convert the source rest
		# orientation into the target bone frame before applying the pose delta.
		var source_delta := source_rest.basis.inverse() * source_pose.basis
		var source_global_rest := _source_skeleton.get_bone_global_rest(source_index)
		var target_global_rest := target.get_bone_global_rest(target_index)
		# The pack faces -Z (its toe is in -Z), while Ukon faces +Z. Apply
		# that heading change before transferring the rest-space rotation.
		# Without it, the calf's forward flex becomes a backward knee bend.
		var source_to_target := target_global_rest.basis.inverse() * Basis(Vector3.UP, PI) * source_global_rest.basis
		var target_delta := source_to_target * source_delta * source_to_target.inverse()
		var retargeted_basis := (target_rest.basis * target_delta).orthonormalized()
		var bone_influence := 1.0 if pair.arm else influence
		if String(target.get_bone_name(target_index)).ends_with("UpperLeg"):
			# Side-run clips abduct the source thighs almost into a split. Limit
			# lateral spread in body space while retaining fore/aft stride.
			var child_index := target.find_bone(String(target.get_bone_name(target_index)).replace("UpperLeg", "LowerLeg"))
			if child_index >= 0:
				var parent_id := target.get_bone_parent(target_index)
				var parent_basis := target.get_bone_global_rest(parent_id).basis if parent_id >= 0 else Basis.IDENTITY
				var original_dir := (parent_basis * retargeted_basis * target.get_bone_rest(child_index).origin).normalized()
				var limited_dir := Vector3(clampf(original_dir.x, -0.18, 0.18), original_dir.y, original_dir.z).normalized()
				if original_dir.dot(limited_dir) < 0.9999:
					var correction := parent_basis.inverse() * Basis(Quaternion(original_dir, limited_dir)) * parent_basis
					retargeted_basis = (correction * retargeted_basis).orthonormalized()
		if pair.arm:
			var bone_name := String(target.get_bone_name(target_index))
			var relaxed := target_rest.basis
			if bone_name.ends_with("UpperArm"):
				var lower_name := bone_name.replace("UpperArm", "LowerArm")
				var lower_index := target.find_bone(lower_name)
				if lower_index >= 0:
					var parent_index := target.get_bone_parent(target_index)
					var parent_rest := target.get_bone_global_rest(parent_index).basis if parent_index >= 0 else Basis.IDENTITY
					var arm_vector := (target_rest.basis * target.get_bone_rest(lower_index).origin).normalized()
					var down_vector := (parent_rest.inverse() * Vector3.DOWN).normalized()
					relaxed = Basis(Quaternion(arm_vector, down_vector)) * target_rest.basis
			# The source upper-body clips keep both hands raised for combat.
			# Use a modest gait swing around the relaxed arm instead.
			if bone_name.ends_with("UpperArm"):
				var parent_index := target.get_bone_parent(target_index)
				var parent_rest := target.get_bone_global_rest(parent_index).basis if parent_index >= 0 else Basis.IDENTITY
				var side_phase := PI if bone_name.begins_with("Left") else 0.0
				var swing := sin(_gait_phase + side_phase) * 0.22 * smoothstep(0.1, 1.6, _locomotion_speed)
				retargeted_basis = (parent_rest.inverse() * Basis(Vector3.RIGHT, swing) * parent_rest * relaxed).orthonormalized()
			else:
				retargeted_basis = relaxed
		if pair.hips:
			# Keep Hips translation under locomotion/root placement control.
			target.set_bone_pose_rotation(target_index, current_pose.basis.get_rotation_quaternion().slerp(retargeted_basis.get_rotation_quaternion(), bone_influence))
		else:
			target.set_bone_pose_rotation(target_index, target_rest.basis.get_rotation_quaternion().slerp(retargeted_basis.get_rotation_quaternion(), bone_influence))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
