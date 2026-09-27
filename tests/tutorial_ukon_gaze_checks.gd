extends SceneTree

class LookProbe:
	extends Node3D
	var calls := 0
	var last_active := false

	func set_guide_look_target(_world_position: Vector3, active: bool, _delta: float) -> void:
		calls += 1
		last_active = active


func _initialize() -> void:
	var game = load("res://scripts/main.gd").new()
	game.tutorial_director = TutorialDirector.new()
	game.tutorial_director.begin_run(true, 100)
	game.tutorial_director.choose_tutorial()
	game._ukon_authored_yaw = 0.7
	var ukon := LookProbe.new()
	ukon.rotation.y = -1.4
	game._update_ukon_gaze(ukon, 1.0 / 60.0, Vector3(0.0, 1.7, 4.0))
	assert(is_equal_approx(ukon.rotation.y, 0.7), "tutorial holds Ukon's authored introduction yaw")
	assert(ukon.calls == 0, "tutorial does not request adaptive look-at")
	game.tutorial_director.skip()
	game._update_ukon_gaze(ukon, 1.0 / 60.0, Vector3(0.0, 1.7, 4.0))
	assert(ukon.calls == 1 and ukon.last_active, "skip restores adaptive look-at in free play")
	ukon.free()
	game.free()
	print("UKON_GAZE_CHECKS_OK")
	quit()
