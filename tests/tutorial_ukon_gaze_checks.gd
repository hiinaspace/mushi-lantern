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
	var ukon := LookProbe.new()
	ukon.rotation.y = -1.4
	game._update_ukon_gaze(ukon, 1.0 / 60.0, Vector3(0.0, 1.7, 4.0))
	assert(ukon.calls == 1 and ukon.last_active, "tutorial Ukon follows the actual viewer")
	game.tutorial_director.skip()
	game._update_ukon_gaze(ukon, 1.0 / 60.0, Vector3(0.0, 1.7, 4.0))
	assert(ukon.calls == 2 and ukon.last_active, "free play retains adaptive look-at")
	ukon.free()
	game.free()
	print("UKON_GAZE_CHECKS_OK")
	quit()
