class_name MushiXRStaffInteraction
extends RefCounted

## Gives the lantern control zone priority over XR Tools shaft pickup.
## XR Tools owns the staff pose while grabbed; StaffTool owns it otherwise.
const CONTROL_RADIUS := 0.34
const GRIP_THRESHOLD := 0.65
const HIGHLIGHT_RING := preload("res://addons/godot-xr-tools/objects/highlight/highlight_ring.tscn")

class ControlHighlight extends Node3D:
	signal highlight_updated(pickable: Node3D, enabled: bool)

	var hovered := false

	func set_hovered(on: bool) -> void:
		if hovered == on:
			return
		hovered = on
		highlight_updated.emit(self, on)

var staff: StaffTool
var rig: MushiXRPlayer
var _controllers: Array[XRController3D] = []
var _pickups: Array[XRToolsFunctionPickup] = []
var _was_gripped := [false, false]
var _consumed_grip := [false, false]
var _adjust_owner: XRController3D
var _last_shaft_owner: XRController3D
var _pending_drop: bool = false
var _tracking_suspended: bool = false
var _saved_hand_pose: Transform3D = Transform3D.IDENTITY
var _hint: ControlHighlight
var _shaft_ring: XRToolsHighlightRing
var _shaft_highlight_requested := false


func configure(tool: StaffTool, player_rig: MushiXRPlayer) -> void:
	staff = tool
	rig = player_rig
	_controllers = [rig.left_controller, rig.right_controller]
	_pickups = [rig.left_pickup, rig.right_pickup]
	staff.dropped.connect(_on_staff_dropped)
	_shaft_ring = HIGHLIGHT_RING.instantiate() as XRToolsHighlightRing
	_shaft_ring.name = "ShaftGripHighlight"
	_shaft_ring.mesh = _shaft_ring.mesh.duplicate()
	(_shaft_ring.mesh as QuadMesh).size = Vector2(0.17, 0.17)
	staff.add_child(_shaft_ring)
	staff.highlight_updated.connect(_on_shaft_highlight_updated)
	_hint = ControlHighlight.new()
	_hint.name = "LanternControlGripHint"
	var control_ring := HIGHLIGHT_RING.instantiate() as XRToolsHighlightRing
	control_ring.name = "ControlGripHighlight"
	control_ring.mesh = control_ring.mesh.duplicate()
	(control_ring.mesh as QuadMesh).size = Vector2(0.13, 0.13)
	_hint.add_child(control_ring)
	rig.add_child(_hint)


func update(_delta: float) -> void:
	if staff == null or rig == null or not rig.xr_active:
		return
	_resolve_drop()
	if staff.is_picked_up():
		var owner := staff.get_picked_up_by_controller()
		var lost := owner == null or not owner.get_has_tracking_data()
		if lost and not _tracking_suspended:
			staff.tracking_lost()
		elif not lost and _tracking_suspended:
			staff.tracking_restored()
		_tracking_suspended = lost
	else:
		_tracking_suspended = false
	var show_hint := false
	for index: int in _controllers.size():
		var controller := _controllers[index]
		var pickup := _pickups[index]
		var tracked := controller.get_has_tracking_data()
		var grip_down := tracked and controller.get_float("grip") > GRIP_THRESHOLD
		if not grip_down:
			_consumed_grip[index] = false
		var is_shaft_owner := pickup.picked_up_object == staff
		var near_control := tracked and not rig.is_menu_open() and not is_shaft_owner and controller.global_position.distance_to(staff.control_world_position()) <= CONTROL_RADIUS
		if controller == _adjust_owner:
			pickup.enabled = false
			if grip_down and not rig.is_menu_open():
				staff.update_adjust(controller.global_transform)
				_snap_hand(controller)
			else:
				_end_adjust()
		elif is_shaft_owner:
			# The owning pickup must keep polling grip so it can release the staff.
			pickup.enabled = tracked
		elif near_control:
			pickup.enabled = false
			show_hint = true
			if _adjust_owner == null and grip_down and not _was_gripped[index]:
				_adjust_owner = controller
				_consumed_grip[index] = true
				_saved_hand_pose = (controller.get_node("Hand") as Node3D).transform
				staff.begin_adjust(controller.global_transform)
				rig.set_interaction_lock(true)
				_snap_hand(controller)
		else:
			pickup.enabled = tracked and not rig.is_menu_open() and not _consumed_grip[index]
		_was_gripped[index] = grip_down
	if staff.is_picked_up():
		_last_shaft_owner = staff.get_picked_up_by_controller()
	_hint.set_hovered(show_hint and _adjust_owner == null)
	if _hint.hovered:
		_hint.global_position = staff.control_world_position()
	_shaft_ring.visible = _shaft_highlight_requested and not rig.is_menu_open() and not show_hint and _adjust_owner == null


func _on_shaft_highlight_updated(_pickable: XRToolsPickable, enabled: bool) -> void:
	_shaft_highlight_requested = enabled


func _snap_hand(controller: XRController3D) -> void:
	var hand := controller.get_node("Hand") as Node3D
	hand.global_position = staff.control_world_position()


func _end_adjust() -> void:
	if _adjust_owner == null:
		return
	var hand := _adjust_owner.get_node_or_null("Hand") as Node3D
	if hand != null:
		hand.transform = _saved_hand_pose
	staff.end_adjust()
	_adjust_owner = null
	rig.set_interaction_lock(false)


func _on_staff_dropped(_pickable: XRToolsPickable) -> void:
	# SWAP emits dropped before the replacement hand grabs in the same call.
	# Reconcile on the next Main update rather than parking from this signal.
	_pending_drop = true


func _resolve_drop() -> void:
	if not _pending_drop:
		return
	_pending_drop = false
	if staff.is_picked_up():
		return
	if _adjust_owner != null:
		_end_adjust()
	var intentional := _last_shaft_owner != null and _last_shaft_owner.get_has_tracking_data()
	staff.release_external_grab(intentional)
	_last_shaft_owner = null


func reset_for_run() -> void:
	_end_adjust()
	if staff != null and staff.is_picked_up():
		staff.drop()
	_pending_drop = false
	_tracking_suspended = false
	_last_shaft_owner = null
	_adjust_owner = null
	_was_gripped = [false, false]
	_consumed_grip = [false, false]
	if rig != null:
		rig.set_pickups_enabled(true)
	if _hint != null:
		_hint.set_hovered(false)
	if _shaft_ring != null:
		_shaft_ring.visible = false
