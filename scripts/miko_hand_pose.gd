class_name MushiHandPose
extends RefCounted

## Wrist-relative OpenXR finger orientations, ordered as thumb through little
## finger with three joints each. The avatar modifier handles missing joints.
const JOINTS := [2, 3, 4, 7, 8, 9, 12, 13, 14, 17, 18, 19, 22, 23, 24]
# The XR Tools hand *node* and its Wrist bone are different frames. The
# imported Wrist rest points +Y toward the fingers and is already in the
# humanoid wrist convention used by Ukon. Only a hand-node/grab-point pose
# needs this conversion; applying it to the Wrist bone twists the palm.
const WRIST_FROM_HAND_NODE := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
const WRIST_ORIGIN_FROM_HAND_NODE := Vector3(0.0, 0.0, 0.027176)
# Ukon's fingers point along the hand bone's +Y, as on XR Tools, but its
# index-to-little axis lies on local +X instead of XR Tools local +Z. Rotate
# around the finger axis so the palm plane and thumb side coincide.
static func xr_wrist_to_ukon(left_hand: bool) -> Basis:
	return Basis(Vector3.UP, PI * (0.5 if left_hand else -0.5))


static func sample(tracker: XRHandTracker, _controller_active: bool = false) -> Dictionary:
	var rotations: Array[Quaternion] = []
	rotations.resize(15)
	rotations.fill(Quaternion.IDENTITY)
	var mask := 0
	if tracker != null and tracker.has_tracking_data \
			and tracker.get_hand_joint_flags(1) & XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID:
		var wrist := tracker.get_hand_joint_transform(1).basis.orthonormalized()
		for i in range(15):
			if tracker.get_hand_joint_flags(JOINTS[i]) & XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID:
				var relative := wrist.inverse() * tracker.get_hand_joint_transform(JOINTS[i]).basis.orthonormalized()
				var rotation := relative.get_rotation_quaternion()
				if rotation.is_finite():
					rotations[i] = rotation.normalized()
					mask |= 1 << i
	return {"rotations": rotations, "mask": mask}


static func staff_wrist_basis(staff_basis: Basis, _left_hand: bool) -> Basis:
	# Staff grab points are in the XR Tools hand-node frame.
	return (staff_basis.orthonormalized() * WRIST_FROM_HAND_NODE *
		xr_wrist_to_ukon(_left_hand)).orthonormalized()


static func staff_wrist_position(grip: Transform3D, left_hand: bool) -> Vector3:
	return grip.origin + grip.basis.orthonormalized() * WRIST_ORIGIN_FROM_HAND_NODE


static func wrist(rig: XROrigin3D, controller: XRController3D,
		tracker: XRHandTracker, left_hand: bool) -> Dictionary:
	var side := 1.0 if left_hand else -1.0
	var ukon_rest_correction := Basis(Vector3.FORWARD, -side * PI * 0.5)
	# Controller grip tracking owns the wrist while a controller is active;
	# its rendered hand can be snapped to a staff grab point. Optical hand
	# tracking uses the OpenXR joint basis and keeps its existing correction.
	if tracker != null and tracker.has_tracking_data and not controller.get_is_active():
		var flags := tracker.get_hand_joint_flags(1)
		if flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID \
				and flags & XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID:
			# XRHandTracker stores native metre positions; XRController3D nodes
			# already apply the origin's world scale to their scene transforms.
			var joint_pose := tracker.get_hand_joint_transform(1)
			joint_pose.origin *= rig.world_scale
			var tracked_pose := rig.global_transform * joint_pose
			tracked_pose.basis = tracked_pose.basis * ukon_rest_correction
			return {"pose": tracked_pose,
				"valid": true, "humanoid": true}
	# Follow the rendered XR Tools wrist. It snaps to a grab point while the
	# controller keeps its tracked pose, so controller-only targets drift away
	# from the hand as soon as the staff is picked up.
	var hand := controller.get_node_or_null("Hand") as Node3D
	if hand != null:
		var sk := hand.get_node_or_null("Hand_Nails_low_L/Armature/Skeleton3D" if left_hand else
			"Hand_Nails_low_R/Armature/Skeleton3D") as Skeleton3D
		if sk != null:
			var wrist_id := sk.find_bone("Wrist_L" if left_hand else "Wrist_R")
			if wrist_id >= 0:
				var rendered_wrist := sk.global_transform * sk.get_bone_global_pose(wrist_id)
				var pose := Transform3D((rendered_wrist.basis.orthonormalized() *
					xr_wrist_to_ukon(left_hand)).orthonormalized(), rendered_wrist.origin)
				return {"pose": pose, "valid": controller.get_has_tracking_data(), "humanoid": true}
	var pose := controller.global_transform
	pose.origin += pose.basis * WRIST_ORIGIN_FROM_HAND_NODE
	pose.basis = pose.basis * WRIST_FROM_HAND_NODE * xr_wrist_to_ukon(left_hand)
	return {"pose": pose, "valid": controller.get_has_tracking_data(), "humanoid": true}


static func curls(controller: XRController3D) -> PackedFloat32Array:
	var grip := clampf(controller.get_float("grip"), 0.0, 1.0)
	var trigger := clampf(controller.get_float("trigger"), 0.0, 1.0)
	var thumb := controller.is_button_pressed("ax_button") \
		or controller.is_button_pressed("by_button") \
		or controller.is_button_pressed("primary_touch")
	return PackedFloat32Array([0.7 if thumb else 0.0, trigger, grip, grip, grip])
