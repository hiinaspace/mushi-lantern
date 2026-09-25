class_name RemoteStaffVisual
extends StaffTool

## Render a remote pendulum from the staff pose between network samples. The
## packet lamp remains the gameplay authority; its pose gently corrects this
## visual pendulum once the shaft settles.
const STAFF_FOLLOW_RATE := 15.0
const MOVING_SPEED := 0.15
const SETTLE_RATE := 2.8
const MOVING_RATE := 14.0

var _target_staff := Transform3D.IDENTITY
var _target_lamp_position := Vector3.ZERO
var _target_lamp_direction := Vector3.FORWARD
var _has_remote_pose := false
var _authority_blend := 1.0

func _ready() -> void:
	super._ready()
	collision_layer = 0
	collision_mask = 0
	for child: Node in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
		elif child is XRToolsGrabPointHand:
			(child as XRToolsGrabPointHand).set_process(false)
	set_interaction_hint(0.0, 0.0)
	lantern.housing_fill.visible = false
	lantern.set_beam_shadows_enabled(false)


func apply_remote_pose(staff_world: Transform3D, lamp_position: Vector3, lamp_direction: Vector3,
		remote_placement: int) -> void:
	_target_staff = staff_world
	placement = clampi(remote_placement, Placement.HELD, Placement.RECALL_HOVER)
	_target_lamp_position = lamp_position
	_target_lamp_direction = lamp_direction
	if not _has_remote_pose:
		global_transform = staff_world
		_reset_swing()
		_swing.global_basis = _authority_basis()
		_has_remote_pose = true


func advance_remote(delta: float) -> void:
	if not _has_remote_pose or delta <= 0.0:
		return
	var dt := clampf(delta, 0.0, 0.1)
	var previous_pivot := to_global(SUSPENSION_PIVOT_LOCAL)
	if global_position.distance_to(_target_staff.origin) > 2.0:
		global_transform = _target_staff
		_reset_swing()
	else:
		global_transform = global_transform.interpolate_with(_target_staff, 1.0 - exp(-STAFF_FOLLOW_RATE * dt))
	var pivot_speed := previous_pivot.distance_to(to_global(SUSPENSION_PIVOT_LOCAL)) / dt
	_update_swing(dt)
	var moving := pivot_speed > MOVING_SPEED
	var blend_target := 0.0 if moving else 1.0
	var rate := MOVING_RATE if moving else SETTLE_RATE
	_authority_blend = lerpf(_authority_blend, blend_target, 1.0 - exp(-rate * dt))
	_swing.global_basis = _swing.global_basis.slerp(_authority_basis(), _authority_blend)
	lantern.advance_flame(dt)
	lantern.advance_transition(dt)


func _authority_basis() -> Basis:
	var down := _target_lamp_position - _swing.global_position
	if down.length_squared() < 0.01:
		down = Vector3.DOWN
	var up := -down.normalized()
	var forward := _target_lamp_direction - up * _target_lamp_direction.dot(up)
	if forward.length_squared() < 0.0001:
		forward = -_swing.global_basis.z
		forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	var z_axis := -forward.normalized()
	return Basis(up.cross(z_axis).normalized(), up, z_axis)
