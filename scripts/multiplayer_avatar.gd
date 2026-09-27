class_name MushiMultiplayerAvatar
extends Node3D

## Ukon player presentation. The three tracked transforms are world-space camera,
## left hand and right hand poses. An untracked hand rests beside the torso.
## The VRM faces +Z; camera/controller tracking faces -Z.
const AVATAR_SCENE: PackedScene = preload("res://scenes/miko_avatar.tscn")
const SPINE = preload("res://addons/renik/renik_spine.gd")
const LIMB = preload("res://addons/renik/renik_limb.gd")
const LEG_ANIMATION = preload("res://scripts/miko_leg_animation.gd")
const FINGERS = preload("res://scripts/miko_fingers.gd")
const PLACEMENT = preload("res://addons/renik/renik_placement.gd")
const LEG_ANIMATION_SOURCE := "res://assets/animations/explosive_rpg_unarmed.glb"
const VIEW_OFFSET := Vector3(0.0, 0.023, -0.015)
const XR_EYE_HEIGHT := 1.65

var body: Node3D
var skeleton: Skeleton3D
var head_target: Node3D
var hand_targets: Array[Node3D] = []
var arm_modifiers: Array[SkeletonModifier3D] = []
var leg_modifiers: Array[SkeletonModifier3D] = []
var foot_targets: Array[Node3D] = []
var finger_modifier: SkeletonModifier3D
var placement: Node3D
var eye_height: float = 1.6
var model_scale: float = 1.0
var arm_reach_scale: float = 1.3
var local_first_person: bool = false
var _ready_pose: bool = false
var _last_head: Vector3 = Vector3.ZERO
var _leg_animation: Node
var _configured_hue: float = 0.0
var _target_body: Transform3D = Transform3D.IDENTITY
var _target_view: Transform3D = Transform3D.IDENTITY
var _target_left: Transform3D = Transform3D.IDENTITY
var _target_right: Transform3D = Transform3D.IDENTITY
var _target_tracking: int = 0
var _target_velocity: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _display_body: Transform3D = Transform3D.IDENTITY
var _display_view: Transform3D = Transform3D.IDENTITY
var _display_left: Transform3D = Transform3D.IDENTITY
var _display_right: Transform3D = Transform3D.IDENTITY
var _height_calibrated: bool = false
var _idle_planting: bool = false
var _foot_plant_weight: float = 0.0
var _flying: bool = false
var _last_tracking: int = 0
var _arm_rest_origins: Dictionary = {}
var _arm_reach_applied: float = -1.0
var _spring_center: Node3D


func _ready() -> void:
	body = AVATAR_SCENE.instantiate() as Node3D
	body.name = "Ukon"
	add_child(body)
	skeleton = _find_skeleton(body)
	if skeleton == null:
		push_error("Ukon VRM has no humanoid skeleton")
		return
	# The model used as the static world character is intentionally unrotated.
	# Player tracking needs the same world heading as Prim's avatar driver.
	body.rotation.y = PI
	_cache_arm_rests()
	set_arm_reach_scale(arm_reach_scale)
	set_eye_height(eye_height)
	head_target = _marker("HeadTarget", "Head")
	for side in ["Left", "Right"]:
		hand_targets.append(_marker(side + "HandTarget", side + "Hand"))
		foot_targets.append(_marker(side + "FootTarget", side + "Foot"))
	if ResourceLoader.exists(LEG_ANIMATION_SOURCE):
		var leg_helper = LEG_ANIMATION.new()
		leg_helper.animation_source_scene = load(LEG_ANIMATION_SOURCE) as PackedScene
		attach_leg_animation(leg_helper)
	var spine: SkeletonModifier3D = SPINE.new()
	spine.name = "TrackedSpine"
	spine.head_target = head_target
	spine.hip_target = _marker("HipsTarget", "Hips")
	skeleton.add_child(spine)
	for side in ["Left", "Right"]:
		var arm: SkeletonModifier3D = LIMB.new()
		arm.name = side + "TrackedArm"
		arm.preset = 0 if side == "Left" else 1
		arm.leaf_bone = side + "Hand"
		arm.lower_bone = side + "LowerArm"
		arm.upper_bone = side + "UpperArm"
		arm.mirror = side == "Right"
		arm.dynamic_pole_root_bone = "Hips"
		arm.dynamic_pole_head_bone = "Head"
		arm.target = hand_targets[0 if side == "Left" else 1]
		skeleton.add_child(arm)
		arm_modifiers.append(arm)
	_refresh_arm_lengths()
	for i in range(2):
		var side := "Left" if i == 0 else "Right"
		var leg: SkeletonModifier3D = LIMB.new()
		leg.name = side + "PlantedLeg"
		leg.preset = i + 2
		leg.leaf_bone = side + "Foot"
		leg.lower_bone = side + "LowerLeg"
		leg.upper_bone = side + "UpperLeg"
		leg.mirror = i == 1
		leg.target = foot_targets[i]
		leg.assign_leg_defaults.call()
		leg.has_shoulder = false
		leg.active = false
		skeleton.add_child(leg)
		leg_modifiers.append(leg)
	finger_modifier = FINGERS.new()
	finger_modifier.name = "TrackedFingers"
	skeleton.add_child(finger_modifier)
	placement = PLACEMENT.new()
	placement.name = "IdleFootPlacement"
	placement.armature_skeleton_path = NodePath("..")
	placement.armature_head_target = NodePath("../HeadTarget")
	placement.armature_hip_target = NodePath("../HipsTarget")
	placement.armature_left_foot_target = NodePath("../LeftFootTarget")
	placement.armature_right_foot_target = NodePath("../RightFootTarget")
	placement.enable_hip_placement = true
	placement.collision_mask = 1
	skeleton.add_child(placement)
	placement.set_process_internal(false)
	placement.set_physics_process_internal(false)
	# Follow body translation in the VRM's local frame. Spring motion still
	# responds to head turns and arm motion without dragging on every step.
	_spring_center = Node3D.new()
	_spring_center.name = "SpringCenter"
	_spring_center.top_level = true
	add_child(_spring_center)
	for node in body.find_children("*", "VRMTopLevel", true, false):
		(node as VRMTopLevel).override_springbone_center = true
		(node as VRMTopLevel).default_springbone_center = _spring_center
	# A small share of short head/body acceleration reaches the cloth while the
	# moving center still prevents the long trailing motion of world-anchored springs.
	for spring in body.find_children("*", "VRMSecondary", true, false):
		for state in (spring as VRMSecondary).spring_bones_internal:
			state.springbone = state.springbone.duplicate(true)
			state.springbone.drag_force_scale = minf(state.springbone.drag_force_scale, 0.9)
	set_local_first_person(local_first_person)
	set_hue(_configured_hue)


func configure(hue: float, is_local: bool) -> void:
	_configured_hue = hue
	local_first_person = is_local
	if is_node_ready():
		set_hue(hue)
		set_local_first_person(is_local)


func set_eye_height(height_m: float) -> void:
	eye_height = clampf(height_m, 1.1, 2.1)
	if skeleton == null or body == null:
		return
	var head_id := skeleton.find_bone("Head")
	if head_id < 0:
		return
	model_scale = eye_height / maxf(0.5, skeleton.get_bone_global_rest(head_id).origin.y + VIEW_OFFSET.y)
	body.scale = Vector3.ONE * model_scale


func _cache_arm_rests() -> void:
	for side in ["Left", "Right"]:
		for suffix in ["LowerArm", "Hand"]:
			var name: String = side + suffix
			var bone := skeleton.find_bone(name)
			if bone >= 0:
				_arm_rest_origins[name] = skeleton.get_bone_rest(bone).origin


func set_arm_reach_scale(value: float) -> void:
	arm_reach_scale = clampf(value, 0.9, 1.5)
	if skeleton == null or is_equal_approx(_arm_reach_applied, arm_reach_scale):
		return
	_arm_reach_applied = arm_reach_scale
	for name: String in _arm_rest_origins:
		var bone := skeleton.find_bone(name)
		var rest := skeleton.get_bone_rest(bone)
		rest.origin = _arm_rest_origins[name] * arm_reach_scale
		skeleton.set_bone_rest(bone, rest)
		# Imported VRM poses retain their original translations when the rest
		# length changes. RenIK solves using the new rest lengths, so keep the
		# displayed bone translations in the same geometry.
		skeleton.set_bone_pose_position(bone, rest.origin)
	_refresh_arm_lengths()


func _refresh_arm_lengths() -> void:
	for arm in arm_modifiers:
		arm.lower_id = -1
		arm.leaf_id = -1
		arm.upper_id = -1
		arm.update_bones.call()


func _set_arm_pose_length(side: String, scale: float) -> void:
	# The authored swing/rest animation owns an untracked arm. Its pose should
	# not grow with the IK reach tuning while the other arm holds the staff.
	for suffix in ["LowerArm", "Hand"]:
		var name: String = side + suffix
		var bone := skeleton.find_bone(name)
		if bone >= 0 and _arm_rest_origins.has(name):
			skeleton.set_bone_pose_position(bone, _arm_rest_origins[name] * scale)


func get_authored_eye_height() -> float:
	if skeleton == null:
		return 1.6
	var head_id := skeleton.find_bone("Head")
	return skeleton.get_bone_global_rest(head_id).origin.y + VIEW_OFFSET.y if head_id >= 0 else 1.6


func set_player_eye_height(_height_m: float) -> void:
	# The imported VRM's eye height is only about 1.25 m. Fit the local body
	# to an adult game-space height so the staff and lantern keep their scale.
	set_eye_height(XR_EYE_HEIGHT)
	_height_calibrated = true


func set_hue(hue_turns: float) -> void:
	if body != null:
		body.call("set_avatar_color", hue_turns, 2.5)


func set_local_first_person(enabled: bool) -> void:
	local_first_person = enabled
	if body == null or skeleton == null:
		return
	# Ukon is a single skinned mesh, so Prim's first/third mesh layers cannot
	# separate its face. Collapse the local head hierarchy at the neck instead;
	# the torso, hands and legs stay visible below the camera.
	var head_bone := skeleton.find_bone("Head")
	if head_bone >= 0:
		# Keep the basis invertible for VRM spring bones attached to the head.
		skeleton.set_bone_pose_scale(head_bone, Vector3.ONE * (0.01 if enabled else 1.0))
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		instance.visible = true
		for surface in instance.get_surface_override_material_count():
			var material := instance.get_active_material(surface)
			while material != null:
				if material is ShaderMaterial:
					(material as ShaderMaterial).set_shader_parameter("_MikoFirstPersonClip", 0.18 if enabled else 0.0)
				material = material.next_pass


func apply_pose(body_pose: Transform3D, view: Transform3D, left: Transform3D,
		right: Transform3D, tracked_hands: int, horizontal_velocity: Vector3,
		_delta: float) -> void:
	if not _valid_pose(view):
		return
	set_flying((tracked_hands & MultiplayerAvatarPose.FLYING_FLAG) != 0)
	if not _height_calibrated and _valid_pose(body_pose):
		var measured_height := view.origin.y - body_pose.origin.y
		if measured_height >= 1.1 and measured_height <= 2.1:
			set_eye_height(measured_height)
			_height_calibrated = true
	if not local_first_person:
		_target_body = body_pose
		_target_view = view
		_target_left = left
		_target_right = right
		_target_tracking = tracked_hands
		_target_velocity = horizontal_velocity
		if not _has_target or view.origin.distance_to(_display_view.origin) > 2.0:
			_display_body = body_pose
			_display_view = view
			_display_left = left
			_display_right = right
			_apply_display_pose(body_pose, view, left, right, tracked_hands, horizontal_velocity)
		_has_target = true
		return
	_apply_display_pose(body_pose, view, left, right, tracked_hands, horizontal_velocity)


func apply_fingers(rotations: Array[Quaternion], masks: PackedInt32Array,
		curls: PackedFloat32Array) -> void:
	if finger_modifier == null or masks.size() != 2 or curls.size() != 10:
		return
	finger_modifier.rotations = rotations
	finger_modifier.masks = masks
	var display_curls := curls.duplicate()
	# Desktop has no finger tracker or controller curls. Curl the staff hand
	# around the shaft while retaining live XR skeletal and controller input.
	if (_last_tracking & 2) != 0 and (_last_tracking & 28) == 0 and masks[1] == 0:
		for finger in range(5):
			display_curls[5 + finger] = [0.65, 0.85, 0.9, 0.9, 0.8][finger]
	finger_modifier.curls = display_curls


func _process(delta: float) -> void:
	_update_foot_plant_weight(delta)
	if local_first_person or not _has_target:
		return
	var weight := 1.0 - exp(-minf(delta, 0.1) * 24.0)
	_display_body = _display_body.interpolate_with(_target_body, weight)
	_display_view = _display_view.interpolate_with(_target_view, weight)
	_display_left = _display_left.interpolate_with(_target_left, weight)
	_display_right = _display_right.interpolate_with(_target_right, weight)
	_apply_display_pose(_display_body, _display_view, _display_left, _display_right,
		_target_tracking, _target_velocity)


func _apply_display_pose(body_pose: Transform3D, view: Transform3D, left: Transform3D,
		right: Transform3D, tracked_hands: int, horizontal_velocity: Vector3) -> void:
	if skeleton == null or head_target == null:
		return
	# RenIK's hip placement is useful for tracked XR poses, but its idle
	# desktop target can turn the whole pelvis sideways as foot planting fades in.
	# Use the calibrated rest spine length. RenIK's generic crouch ratio
	# lowers this VRM's pelvis even at its exact standing eye height.
	placement.enable_hip_placement = false
	var view_position := view.origin
	if _ready_pose and view_position.distance_to(_last_head) > 2.0:
		_ready_pose = false
	_last_head = view_position
	if _valid_pose(body_pose):
		global_transform = body_pose
	else:
		global_position = Vector3(view_position.x, view_position.y - eye_height, view_position.z)
	var head_basis := view.basis.orthonormalized() * Basis(Vector3.UP, PI)
	head_target.global_transform = Transform3D(head_basis.scaled(Vector3.ONE * model_scale),
		view_position - head_basis * (VIEW_OFFSET * model_scale))
	if (tracked_hands & 4) != 0:
		var head_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Head"))
		var hip_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Hips"))
		var facing := -view.basis.z
		facing.y = 0.0
		if facing.length_squared() < 0.001:
			facing = -global_basis.z
		var hip_basis := Basis.looking_at(facing.normalized()) * Basis(Vector3.UP, PI)
		var hip_target: Node3D = skeleton.get_node("HipsTarget")
		hip_target.global_transform = Transform3D(hip_basis,
			head_target.global_position + hip_basis * ((hip_rest.origin - head_rest.origin) * model_scale))
	for i in range(2):
		var is_tracked := (tracked_hands & (1 << i)) != 0
		_set_arm_pose_length("Left" if i == 0 else "Right", arm_reach_scale if is_tracked else 1.0)
		if i < arm_modifiers.size():
			arm_modifiers[i].active = is_tracked
		var source := left if i == 0 else right
		if not is_tracked or not _valid_pose(source):
			var facing := -view.basis.z
			facing.y = 0.0
			if facing.length_squared() < 0.01:
				facing = Vector3.FORWARD
			var yaw := Basis.looking_at(facing.normalized())
			var x := -0.22 if i == 0 else 0.22
			source = Transform3D(yaw * Basis(Vector3.FORWARD, PI * (0.5 if i == 0 else -0.5)),
				view_position + yaw * Vector3(x * eye_height / 1.6, -eye_height * 0.57, -0.04))
		elif tracked_hands & (8 if i == 0 else 16) == 0:
			# Desktop sends the staff grip center in the shaft frame. XR sends
			# controller wrist space separately (flag 8/16); align both to the
			# same humanoid hand convention before the arm IK runs.
			source.origin = MushiHandPose.staff_wrist_position(source, i == 0)
			source.basis = MushiHandPose.staff_wrist_basis(source.basis, i == 0)
		hand_targets[i].global_transform = source
	_ready_pose = true
	if _leg_animation != null:
		_leg_animation.call("set_tracked_hands", tracked_hands & 3)
	_last_tracking = tracked_hands
	set_locomotion(horizontal_velocity, -view.basis.z)
	var speed := Vector2(horizontal_velocity.x, horizontal_velocity.z).length()
	_idle_planting = speed < 0.65
	if _spring_center != null:
		# Keep translation in lockstep, but let turns excite a short spring transient.
		_spring_center.global_position = global_position
		var target_basis := global_basis.orthonormalized()
		_spring_center.global_basis = target_basis if not _ready_pose else \
			_spring_center.global_basis.orthonormalized().slerp(target_basis,
				1.0 - exp(-get_process_delta_time() * 12.0))


func _physics_process(delta: float) -> void:
	if not _ready_pose or placement == null or _flying:
		return
	placement.update_placement(minf(delta, 0.05))
	placement.interpolate_transforms(1.0)


func _update_foot_plant_weight(delta: float) -> void:
	var has_floor: bool = placement != null and placement.target_foot_is_valid and \
		(placement.left_ground != null or placement.right_ground != null)
	var target_weight := 1.0 if _idle_planting and has_floor and not _flying else 0.0
	_foot_plant_weight = move_toward(_foot_plant_weight, target_weight, minf(delta, 0.05) * 5.0)
	for modifier in leg_modifiers:
		modifier.influence = _foot_plant_weight
		modifier.active = _foot_plant_weight > 0.001


func set_flying(flying: bool) -> void:
	if _flying == flying:
		return
	_flying = flying
	if _leg_animation != null:
		_leg_animation.active = not flying
	if flying:
		# Leave the authored leg rest pose dangling below the tracked torso.
		# Ground contacts are recomputed after landing.
		_foot_plant_weight = 0.0
		for bone_name in ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left toe",
				"RightUpperLeg", "RightLowerLeg", "RightFoot", "Right toe"]:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				skeleton.set_bone_pose_rotation(bone,
					skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
		for modifier in leg_modifiers:
			modifier.influence = 0.0
			modifier.active = false
		if placement != null:
			placement.target_foot_is_valid = false
			placement.left_ground = null
			placement.right_ground = null


func set_locomotion(horizontal_velocity: Vector3, facing: Vector3) -> void:
	if _leg_animation == null or not is_instance_valid(_leg_animation):
		return
	var horizontal := Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z)
	var forward := Vector3(facing.x, 0.0, facing.z).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	_leg_animation.call("set_move_direction", Vector2(horizontal.dot(right), horizontal.dot(forward)))
	_leg_animation.call("set_locomotion_speed", horizontal.length())


func attach_leg_animation(helper: Node) -> void:
	if skeleton == null or helper == null:
		return
	_leg_animation = helper
	skeleton.add_child(helper)


func _marker(label: String, bone: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = label
	skeleton.add_child(marker)
	var index := skeleton.find_bone(bone)
	if index >= 0:
		marker.transform = skeleton.get_bone_global_rest(index)
	return marker


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D and (node as Skeleton3D).find_bone("Hips") >= 0:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _valid_pose(pose: Transform3D) -> bool:
	return pose.origin.is_finite() and pose.basis.x.is_finite() and pose.basis.y.is_finite() and pose.basis.z.is_finite()
