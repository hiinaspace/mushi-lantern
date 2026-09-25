extends SceneTree

class FlatSurface:
	func is_in_bounds(xz: Vector2) -> bool:
		return absf(xz.x) < 5.0 and absf(xz.y) < 5.0

	func get_height_at(_xz: Vector2) -> float:
		return 2.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var ground := StaticBody3D.new()
	ground.name = "BakedBasinCollision"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.2, 10.0)
	shape.shape = box
	shape.position.y = 1.9
	ground.add_child(shape)
	root.add_child(ground)
	var rig: Variant = load("res://scenes/xr_player.tscn").instantiate()
	root.add_child(rig)
	assert(rig._controller_active_mask == -1, "locomotion starts with an unobserved controller state")
	rig._update_locomotion_route()
	assert(rig._controller_active_mask == 0, "first route poll refreshes movement even when both controllers are initially inactive")
	rig.set_world_surface(FlatSurface.new())
	rig.reset_pose(Vector3.ZERO)
	assert(not rig.get_node("PlayerBody").enabled)
	assert(rig.get_node("PlayerBody").global_position.y >= 2.25)
	await physics_frame
	assert(rig._terrain_collision_ready(Vector2.ZERO, 2.0))
	rig.camera.position.y = 0.0
	rig._try_activate_body()
	assert(not rig.get_node("PlayerBody").enabled)
	rig.camera.position.y = 1.6
	shape.set_deferred("disabled", true)
	await physics_frame
	rig._try_activate_body()
	assert(not rig.get_node("PlayerBody").enabled)
	shape.set_deferred("disabled", false)
	await physics_frame
	rig._try_activate_body()
	assert(rig.get_node("PlayerBody").enabled)
	assert(not rig.get_node("PlayerBody").player_calibrate_height)
	rig.get_node("PlayerBody").global_position.y = 0.0
	rig.xr_active = true
	rig._physics_process(1.0 / 90.0)
	assert(rig.get_node("PlayerBody").global_position.y >= 2.25)
	for tick: int in 5:
		await physics_frame
		assert(rig.get_node("PlayerBody").global_position.y >= 1.7)
	rig.get_node("PlayerBody").global_position.y = 5.0
	rig._physics_process(1.0 / 90.0)
	assert(is_equal_approx(rig.get_node("PlayerBody").global_position.y, 5.0))
	print("XR_GROUNDING_PASS")
	quit()
