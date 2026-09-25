extends SceneTree

## Captures the final Skeleton3D result after Renik and finger modifiers have
## run. This intentionally observes the signal output rather than target nodes.
const CASES := [
	{"mode": "desktop", "tracking": 0},
	{"mode": "desktop_staff", "tracking": 2},
	{"mode": "xr_controller", "tracking": 18},
	{"mode": "xr_fingers", "tracking": 7},
]
const YAWS := [0.0, PI * 0.5, PI]
const REACHES := [0.9, 1.5]
const BONES := ["Head", "Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]

var _capture_avatar: MushiMultiplayerAvatar
var _capture_count := 0
var _capture: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16.0, 0.2, 16.0)
	shape.shape = box
	floor.position.y = -0.1
	floor.add_child(shape)
	root.add_child(floor)

	var avatar := MushiMultiplayerAvatar.new()
	root.add_child(avatar)
	_capture_avatar = avatar
	avatar.skeleton.skeleton_updated.connect(_on_skeleton_updated)

	for local in [true, false]:
		avatar.configure(0.0, local)
		for yaw in YAWS:
			for reach in REACHES:
				avatar.set_arm_reach_scale(reach)
				for mode in CASES:
					var body_pose := Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, 0.0, 0.0))
					var head_pose := Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, 1.60, 0.0))
					var left := Transform3D(Basis(Vector3.UP, yaw), Vector3(-0.32, 1.12, -0.25))
					var right := Transform3D(Basis(Vector3.UP, yaw), Vector3(0.32, 1.12, -0.25))
					avatar.apply_pose(body_pose, head_pose, left, right,
						int(mode.tracking), Vector3.ZERO, 1.0 / 60.0)
					for _frame in range(5):
						await process_frame
						await physics_frame
					assert(_capture_count > 0, "Skeleton3D did not emit skeleton_updated")
					var key := "%s local=%s yaw=%.0f reach=%.1f" % [mode.mode, local, rad_to_deg(yaw), reach]
					_report_case(key, yaw, reach, int(mode.tracking))

	print("AVATAR_POST_MODIFIER_FIXTURE_OK captures=%d" % _capture_count)
	quit()


func _on_skeleton_updated() -> void:
	if _capture_avatar == null or _capture_avatar.skeleton == null:
		return
	_capture_count += 1
	var skeleton: Skeleton3D = _capture_avatar.skeleton
	var poses: Dictionary = {}
	for bone_name in BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var world_pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		poses[bone_name] = world_pose
	_capture = poses


func _report_case(label: String, yaw: float, reach: float, tracking: int) -> void:
	assert(_capture.size() == BONES.size(), "missing post-modifier bones: " + label)
	var head: Transform3D = _capture.Head
	var hips: Transform3D = _capture.Hips
	var left_hand: Transform3D = _capture.LeftHand
	var right_hand: Transform3D = _capture.RightHand
	var left_foot: Transform3D = _capture.LeftFoot
	var right_foot: Transform3D = _capture.RightFoot
	for pose in [head, hips, left_hand, right_hand, left_foot, right_foot]:
		assert(pose.origin.is_finite() and pose.basis.x.is_finite() and
			pose.basis.y.is_finite() and pose.basis.z.is_finite(), "non-finite pose: " + label)
		assert(absf(pose.basis.orthonormalized().determinant() - 1.0) < 0.03,
			"bad orientation basis: " + label)
	var expected_forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	assert(head.basis.z.normalized().dot(expected_forward) > 0.90,
		"head yaw diverged from requested heading: " + label)
	if tracking & 3 == 0:
		assert(left_hand.origin.distance_to(right_hand.origin) > 0.2,
			"untracked hands collapsed: " + label)
	# Report post-modifier geometry in world coordinates. The 0.3 m allowance
	# accommodates authored shoe depth and idle planting blend while flagging a
	# clearly floating or buried stance.
	assert(left_foot.origin.y > -0.05 and left_foot.origin.y < 0.35,
		"left ankle outside ground envelope: " + label)
	assert(right_foot.origin.y > -0.05 and right_foot.origin.y < 0.35,
		"right ankle outside ground envelope: " + label)
	print("POSE %s tracking=%d head=%s hips=%s Lwrist=%s Rwrist=%s Lankle=%s Rankle=%s span=%.3f" % [
		label, tracking, _fmt(head.origin), _fmt(hips.origin), _fmt(left_hand.origin),
		_fmt(right_hand.origin), _fmt(left_foot.origin), _fmt(right_foot.origin),
		left_hand.origin.distance_to(right_hand.origin)])


func _fmt(value: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [value.x, value.y, value.z]
