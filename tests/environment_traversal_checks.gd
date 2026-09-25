extends SceneTree

# Actual CharacterBody3D traversal on the baked Terrain3D ground collider.
# XDG_DATA_HOME=/tmp/mushi-traversal godot --headless --path . --script tests/environment_traversal_checks.gd

const SEED := 40721
const BOTTOM := Vector2(10.0, 0.0)
const TOP := Vector2(20.0, 0.0)
const BYPASS := [Vector2(10.0, 22.0), Vector2(37.0, 22.0), Vector2(37.0, 0.0), Vector2(26.0, 0.0), TOP]

var _failures: Array[String] = []


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/mushi-"):
		push_error("Use isolated XDG_DATA_HOME under /tmp/mushi- for this test")
		quit(2)
		return
	for action: String in ["move_left", "move_right", "move_forward", "move_back"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	call_deferred("_run")


func _run() -> void:
	for size: int in [128, 256]:
		await _check_size(size)
	if _failures.is_empty():
		print("ENVIRONMENT_TRAVERSAL_PASS")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check_size(size: int) -> void:
	var surface := EnvironmentSurface.create(size, SEED)
	var terrain := TerrainEnvironment.new()
	root.add_child(terrain)
	terrain.build(surface)
	var player := DesktopPlayer.new()
	player.name = "TraversalPlayer"
	player.world_surface = surface
	player.look_enabled = false
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.65
	collision.shape = capsule
	collision.position.y = 0.82
	player.add_child(collision)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, 1.62, 0.0)
	camera.current = true
	player.add_child(camera)
	root.add_child(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var held_staff := player.staff_hold_transform(Vector2.ZERO)
	var camera_origin := player.camera.global_position
	_expect(held_staff.origin.x > camera_origin.x + 0.3, size, "desktop staff is held to the right of the view")
	_expect(held_staff.origin.y > camera_origin.y - 0.5, size, "desktop staff stays above low waist level")
	_expect(held_staff.origin.distance_to(camera_origin) < 1.2, size, "desktop staff stays in near FPS reach")
	var drop_m := surface.get_height_at(TOP) - surface.get_height_at(BOTTOM)
	_expect(drop_m > 4.5, size, "cliff top is at least 4.5 m above bottom")
	await _place_player(player, surface, TOP)
	var descent: Dictionary = await _walk_to(player, BOTTOM, 300)
	await _settle(90)
	var descended_xz := Vector2(player.global_position.x, player.global_position.z)
	_expect(descent.reached and descended_xz.distance_to(BOTTOM) < 1.2, size, "can descend from top to bottom")
	_expect(player.is_on_floor(), size, "lands on real ground collider after drop")
	_expect(absf(player.global_position.y - surface.get_height_at(descended_xz)) < 0.25, size, "drop ends at ground height")
	await _place_player(player, surface, BOTTOM)
	var uphill: Dictionary = await _walk_to(player, TOP, 300)
	var uphill_xz := Vector2(player.global_position.x, player.global_position.z)
	_expect(not uphill.reached and uphill_xz.x < 17.5, size, "cannot climb cliff face directly")
	_expect(player.global_position.y < surface.get_height_at(TOP) - 2.0, size, "direct approach stays below upper terrace")
	await _place_player(player, surface, BOTTOM)
	var bypass_complete := true
	for waypoint: Vector2 in BYPASS:
		# The 27 m east leg needs room for the friend build's walking pace
		# (60% of sprint); the fixture checks reachability, not a speed target.
		var segment: Dictionary = await _walk_to(player, waypoint, 600)
		bypass_complete = bypass_complete and segment.reached
		if not segment.reached:
			print("TRAVERSAL_BLOCKED size=%d waypoint=%s position=%s" % [size, waypoint, player.global_position])
			break
	var bypass_xz := Vector2(player.global_position.x, player.global_position.z)
	_expect(bypass_complete and bypass_xz.distance_to(BYPASS[-1]) < 1.2, size, "walkable bypass reaches upper terrace")
	_expect(player.is_on_floor() and absf(player.global_position.y - surface.get_height_at(bypass_xz)) < 0.25, size, "bypass remains grounded")
	print("ENVIRONMENT_TRAVERSAL size=%d drop_m=%.2f downhill=%s uphill_x=%.2f bypass=%s final=%s" % [size, drop_m, descent.reached, uphill_xz.x, bypass_complete, player.global_position])
	Input.action_release("move_forward")
	player.free()
	terrain.free()
	await process_frame


func _place_player(player: DesktopPlayer, surface: EnvironmentSurface, xz: Vector2) -> void:
	Input.action_release("move_forward")
	player.global_position = Vector3(xz.x, surface.get_height_at(xz) + 0.12, xz.y)
	player.velocity = Vector3.ZERO
	for _frame: int in 8:
		await physics_frame
		await process_frame


func _walk_to(player: DesktopPlayer, target: Vector2, max_steps: int) -> Dictionary:
	var reached := false
	Input.action_press("move_forward")
	for _step: int in max_steps:
		var position := Vector2(player.global_position.x, player.global_position.z)
		var delta := target - position
		if delta.length() < 0.8:
			reached = true
			break
		player.rotation.y = atan2(-delta.x, -delta.y)
		await physics_frame
		await process_frame
	Input.action_release("move_forward")
	return {"reached": reached, "position": player.global_position}


func _settle(frames: int) -> void:
	Input.action_release("move_forward")
	for _frame: int in frames:
		await physics_frame
		await process_frame


func _expect(condition: bool, size: int, label: String) -> void:
	print("  %s size=%d %s" % ["PASS" if condition else "FAIL", size, label])
	if not condition:
		_failures.append("size=%d %s" % [size, label])
