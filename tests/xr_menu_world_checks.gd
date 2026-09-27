extends SceneTree

func _initialize() -> void:
	var player_source := FileAccess.get_file_as_string("res://scripts/xr_player.gd")
	var scene_source := FileAccess.get_file_as_string("res://scenes/xr_player.tscn")
	var tutorial_source := FileAccess.get_file_as_string("res://scripts/tutorial_ui.gd")
	var friend_source := FileAccess.get_file_as_string("res://scripts/friend_menu.gd")
	var failures := 0
	failures += _expect(player_source.contains("_menu_surface.reparent(world_root, true)"), "menu is reparented into the world scene")
	failures += _expect(player_source.contains("_menu_surface.global_transform = Transform3D(Basis(Vector3.UP, yaw), panel_position)"), "menu transform is set once from opening head pose")
	failures += _expect(player_source.contains("MENU_POINTER_CUTOFF_M: float = 1.0") and player_source.contains("MENU_STANDOFF_M: float = 0.78"), "world menu stays within one-meter pointer cutoff")
	failures += _expect(player_source.contains("func snap_head_horizontal_to(world_xz: Vector2, desired_forward: Vector3 = Vector3.ZERO) -> void"), "tracked-head recenter API supports optional facing")
	failures += _expect(player_source.contains("_body.rotate_player(-yaw_delta)"), "enabled XR body turns around tracked head")
	failures += _expect(player_source.contains('if action == "by_button":') and player_source.contains("set_menu_open(not _menu_open)"), "either controller Y/B toggles the friend menu surface")
	failures += _expect(player_source.contains("_left_pointer.enabled = open") and player_source.contains("_right_pointer.enabled = open"), "menu toggling routes both laser pointers")
	failures += _expect(scene_source.count("laser_length = 1") == 2, "both pointers use collision-limited laser length")
	failures += _expect(tutorial_source.contains("text_material.no_depth_test = false")
		and tutorial_source.contains("_world_root.global_rotation.y"),
		"Ukon dialogue is depth tested and faces the viewer in world space")
	failures += _expect(friend_source.contains("AudioScroll/Contents")
		and friend_source.contains('_create_xr_tab("Play")')
		and friend_source.contains('_create_xr_tab("Multiplayer")')
		and friend_source.contains('child.reparent(mushi if is_tuning else session if is_skip else intro)'),
		"friend menu attaches after XR audio and groups session, rooms, and tutorial actions")
	quit(1 if failures > 0 else 0)

func _expect(condition: bool, description: String) -> int:
	if condition:
		print("PASS: ", description)
		return 0
	push_error("FAIL: " + description)
	return 1
