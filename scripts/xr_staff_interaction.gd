class_name MushiXRStaffInteraction
extends RefCounted

## Gives the lantern control zone priority over XR Tools shaft pickup.
## XR Tools owns the staff pose while grabbed; StaffTool owns it otherwise.
const CONTROL_RADIUS := 0.23
const RECALL_GRAB_RADIUS := 0.55
const PICKUP_HAPTIC := 0.065
const RELEASE_HAPTIC := 0.05
const ADJUST_HAPTIC_MIN_INTERVAL := 0.065
const ADJUST_SHUTTER_TICK := 0.08
const ADJUST_DIAL_TICK := 0.07
const ADJUST_HAPTIC_MIN_SPEED := 0.15
const ADJUST_HAPTIC_MAX_SPEED := 1.4
const RECALL_HAPTIC_INTERVAL := 0.62
const RECALL_HAPTIC := 0.045
const GRIP_THRESHOLD := 0.65
const BROOM_ARM_SECONDS := 1.0
const BROOM_SEAT_BELOW_HEAD := 0.8
const BROOM_SEAT_RADIUS := 0.29
const BROOM_MAX_VERTICAL_AXIS := 0.42

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
var broom_unlocked := false
var broom_active := false
var _broom_arm_elapsed := 0.0
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
var _shaft_highlight_requested := false
var _highlight_phase := 0.0
var _adjust_haptic_elapsed := 0.0
var _adjust_haptic_shutter := 0.0
var _adjust_haptic_dial := 0.0
var _recall_haptic_elapsed := 0.0
var _recall_haptic_owner: XRController3D


func configure(tool: StaffTool, player_rig: MushiXRPlayer) -> void:
	staff = tool
	rig = player_rig
	_controllers = [rig.left_controller, rig.right_controller]
	_pickups = [rig.left_pickup, rig.right_pickup]
	staff.dropped.connect(_on_staff_dropped)
	staff.highlight_updated.connect(_on_shaft_highlight_updated)
	_hint = ControlHighlight.new()
	_hint.name = "LanternControlGripHint"
	rig.add_child(_hint)


func update(delta: float) -> void:
	if staff == null or rig == null or not rig.xr_active:
		return
	_update_broom(delta)
	_resolve_drop()
	if staff.is_picked_up():
		var has_tracked_grab := false
		for index: int in _controllers.size():
			if _pickups[index].picked_up_object == staff and _controllers[index].get_has_tracking_data():
				has_tracked_grab = true
		var lost := not has_tracked_grab
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
		# XR Tools' probe can miss the shaft while it follows the recall hand.
		# A held recall button makes a nearby grip an explicit mid-shaft pickup.
		if grip_down and not rig.is_menu_open() and staff.placement == StaffTool.Placement.RECALL_HOVER and rig._recall_active.has(controller) and pickup.picked_up_object == null:
			if controller.global_position.distance_to(staff.grip_world_position(StaffTool.MID_GRIP_INDEX)) <= RECALL_GRAB_RADIUS:
				pickup.enabled = true
				pickup.grip_pressed = true
				pickup.picked_up_ranged = false
				staff.force_next_grip(StaffTool.MID_GRIP_INDEX)
				pickup._pick_up_object(staff)
				if pickup.picked_up_object != staff:
					staff.force_next_grip(-1)
		var is_shaft_owner := pickup.picked_up_object == staff
		var near_control := tracked and not broom_active and not rig.is_menu_open() and not is_shaft_owner and controller.global_position.distance_to(staff.control_world_position()) <= CONTROL_RADIUS
		if controller == _adjust_owner:
			pickup.enabled = false
			if grip_down and not rig.is_menu_open():
				staff.update_adjust(controller.global_transform)
				_update_adjust_haptic(controller, delta)
				_snap_hand(controller)
			else:
				_end_adjust()
		elif is_shaft_owner:
			# Suppress XR Tools' grip-release polling while high above the terrain.
			# The pickable retains both grab points and snaps both hands to the shaft.
			pickup.enabled = tracked and not (broom_active and rig.broom_release_locked())
		elif near_control:
			pickup.enabled = false
			show_hint = true
			if _adjust_owner == null and grip_down and not _was_gripped[index]:
				_adjust_owner = controller
				_consumed_grip[index] = true
				_saved_hand_pose = (controller.get_node("Hand") as Node3D).transform
				staff.begin_adjust(controller.global_transform)
				_adjust_haptic_elapsed = 0.0
				_adjust_haptic_shutter = staff.lantern.shutter_openness
				_adjust_haptic_dial = staff.lantern._dial_preview
				_one_shot_haptic(controller, PICKUP_HAPTIC * 0.7, 0.018)
				_snap_hand(controller)
		else:
			pickup.enabled = tracked and not rig.is_menu_open() and not _consumed_grip[index]
		_was_gripped[index] = grip_down
	if staff.is_picked_up():
		var current_owner := staff.get_picked_up_by_controller()
		if current_owner != null and current_owner != _last_shaft_owner:
			_one_shot_haptic(current_owner, PICKUP_HAPTIC, 0.020)
		_last_shaft_owner = current_owner
	_hint.set_hovered(show_hint and _adjust_owner == null)
	if _hint.hovered:
		_hint.global_position = staff.control_world_position()
	_highlight_phase = fposmod(_highlight_phase + maxf(delta, 0.0) * 5.0, TAU)
	var pulse := 0.28 + 0.32 * (0.5 + 0.5 * sin(_highlight_phase))
	var shaft_hint := _shaft_highlight_requested and not rig.is_menu_open() and not show_hint and _adjust_owner == null
	var control_hint := _hint.hovered and not rig.is_menu_open() and _adjust_owner == null
	staff.set_interaction_hint(pulse if shaft_hint else 0.0, pulse if control_hint else 0.0)
	_update_recall_haptics(delta)


func _update_broom(delta: float) -> void:
	if broom_active:
		if not rig.is_broom_flying():
			broom_active = false
			return
		rig.set_broom_forward(_broom_forward())
		if not rig.broom_release_locked():
			# A released grip at landing exits flight. The normal XR Tools pickup
			# release then handles the shaft and its usual float/park transition.
			for index: int in _controllers.size():
				if _pickups[index].picked_up_object == staff and _controllers[index].get_float("grip") <= GRIP_THRESHOLD:
					_stop_broom()
					break
		return
	if not broom_unlocked or rig.is_menu_open() or _adjust_owner != null or not _both_hands_on_shaft():
		_broom_arm_elapsed = 0.0
		return
	if not _staff_points_at_seat():
		_broom_arm_elapsed = 0.0
		return
	_broom_arm_elapsed += maxf(delta, 0.0)
	if _broom_arm_elapsed < BROOM_ARM_SECONDS:
		return
	_broom_arm_elapsed = 0.0
	if rig.start_broom_flight(_broom_forward()):
		broom_active = true
		for controller: XRController3D in _controllers:
			_one_shot_haptic(controller, 0.13, 0.09)


func _both_hands_on_shaft() -> bool:
	return _pickups[0].picked_up_object == staff and _pickups[1].picked_up_object == staff


func _staff_points_at_seat() -> bool:
	# The lantern hangs from the local +Y end of the staff. The seat is
	# behind it, toward local -Y.
	# Checking a short shaft segment near the inferred seat accepts a staff
	# between the legs or beside the hips without prescribing arm positions.
	var axis: Vector3 = staff.global_transform.basis.y.normalized()
	if absf(axis.y) > BROOM_MAX_VERTICAL_AXIS:
		return false
	var seat := rig.camera.global_position - Vector3.UP * BROOM_SEAT_BELOW_HEAD
	var local_seat := staff.to_local(seat)
	return local_seat.y >= StaffTool.SHAFT_BOTTOM_Y - 0.16 and local_seat.y <= 0.14 \
		and Vector2(local_seat.x, local_seat.z).length() <= BROOM_SEAT_RADIUS


func _broom_forward() -> Vector3:
	var axis := staff.global_transform.basis.y
	var horizontal := Vector3(axis.x, 0.0, axis.z)
	if horizontal.length_squared() < 0.01:
		return Vector3.FORWARD
	return horizontal.normalized()


func _stop_broom() -> void:
	if not broom_active:
		return
	rig.stop_broom_flight()
	broom_active = false
	_broom_arm_elapsed = 0.0


func _on_shaft_highlight_updated(_pickable: XRToolsPickable, enabled: bool) -> void:
	_shaft_highlight_requested = enabled


func _snap_hand(controller: XRController3D) -> void:
	var hand := controller.get_node("Hand") as Node3D
	hand.global_position = staff.control_world_position()


func _end_adjust(with_haptic: bool = true) -> void:
	if _adjust_owner == null:
		return
	var hand := _adjust_owner.get_node_or_null("Hand") as Node3D
	if hand != null:
		hand.transform = _saved_hand_pose
	staff.end_adjust()
	if with_haptic:
		_one_shot_haptic(_adjust_owner, RELEASE_HAPTIC * 0.7, 0.018)
	_adjust_haptic_elapsed = 0.0
	_adjust_owner = null


func _update_adjust_haptic(controller: XRController3D, delta: float) -> void:
	# Small control-space detents stay quiet at rest and feel like separate ticks
	# as either setting actually travels, independent of headset locomotion.
	_adjust_haptic_elapsed = minf(_adjust_haptic_elapsed + maxf(delta, 0.0), 0.25)
	var shutter := staff.lantern.shutter_openness
	var dial := staff.lantern._dial_preview
	var shutter_travel := absf(shutter - _adjust_haptic_shutter)
	var dial_travel := absf(dial - _adjust_haptic_dial)
	if shutter_travel < ADJUST_SHUTTER_TICK and dial_travel < ADJUST_DIAL_TICK:
		return
	if _adjust_haptic_elapsed < ADJUST_HAPTIC_MIN_INTERVAL:
		return
	var adjustment_speed := maxf(
		shutter_travel, dial_travel) / _adjust_haptic_elapsed
	_adjust_haptic_shutter = shutter
	_adjust_haptic_dial = dial
	_adjust_haptic_elapsed = 0.0
	var amount := clampf(inverse_lerp(ADJUST_HAPTIC_MIN_SPEED, ADJUST_HAPTIC_MAX_SPEED, adjustment_speed), 0.0, 1.0)
	_one_shot_haptic(controller, lerpf(0.025, 0.10, amount), 0.018)


func _one_shot_haptic(controller: XRController3D, magnitude: float, duration: float) -> void:
	if controller == null or not controller.get_has_tracking_data() or XRServer.primary_interface == null:
		return
	# XR Tools resends each event as a 100 ms pulse every frame. Direct OpenXR
	# keeps a setting detent or grip event brief and at the requested strength.
	XRServer.primary_interface.trigger_haptic_pulse(
		&"haptic", controller.tracker, 0.0,
		clampf(magnitude * XRToolsUserSettings.haptics_scale, 0.0, 1.0), duration, 0.0)


func _update_recall_haptics(delta: float) -> void:
	var active_owner: XRController3D
	if staff.placement == StaffTool.Placement.RECALL_HOVER:
		for controller: XRController3D in _controllers:
			if rig._recall_active.has(controller) and controller.get_has_tracking_data():
				active_owner = controller
				break
	if _recall_haptic_owner != active_owner:
		_clear_pulse(_recall_haptic_owner, &"recall")
		_recall_haptic_owner = active_owner
		_recall_haptic_elapsed = RECALL_HAPTIC_INTERVAL
	if active_owner == null:
		return
	_recall_haptic_elapsed += delta
	if _recall_haptic_elapsed >= RECALL_HAPTIC_INTERVAL:
		_pulse(active_owner, RECALL_HAPTIC, 45, &"recall")
		_recall_haptic_elapsed = 0.0


func _pulse(controller: XRController3D, magnitude: float, duration_ms: int, key: StringName) -> void:
	if controller == null or not controller.get_has_tracking_data() or XRServer.primary_interface == null:
		return
	var event := XRToolsRumbleEvent.new()
	event.magnitude = clampf(magnitude, 0.0, 1.0)
	event.duration_ms = duration_ms
	XRToolsRumbleManager.add(StringName("mushi_staff_%s_%s" % [key, controller.tracker]), event, [controller.tracker])


func _clear_pulse(controller: XRController3D, key: StringName) -> void:
	if controller != null:
		XRToolsRumbleManager.clear(StringName("mushi_staff_%s_%s" % [key, controller.tracker]), [controller.tracker])


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
	_stop_broom()
	if _adjust_owner != null:
		_end_adjust()
	var intentional := _last_shaft_owner != null and _last_shaft_owner.get_has_tracking_data()
	if intentional:
		_one_shot_haptic(_last_shaft_owner, RELEASE_HAPTIC, 0.018)
	staff.release_external_grab(intentional)
	_last_shaft_owner = null


func reset_for_run() -> void:
	_stop_broom()
	broom_unlocked = false
	_clear_pulse(_recall_haptic_owner, &"recall")
	_recall_haptic_owner = null
	_recall_haptic_elapsed = 0.0
	_end_adjust(false)
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
	if staff != null:
		staff.set_interaction_hint(0.0, 0.0)
