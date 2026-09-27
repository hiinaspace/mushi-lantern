extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var ui := TutorialUI.new()
	root.add_child(ui)
	await process_frame
	var menu_root := Control.new()
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.name = "Margin"
	var contents := VBoxContainer.new()
	contents.name = "Contents"
	root.add_child(menu_root)
	menu_root.add_child(panel)
	panel.add_child(margin)
	margin.add_child(contents)
	ui.attach_xr_menu(menu_root)
	var camera := XRCamera3D.new()
	root.add_child(camera)
	ui.attach_xr_camera(camera)
	var ukon := Node3D.new()
	root.add_child(ukon)
	ui.attach_ukon(ukon, camera)
	camera.position = Vector3(3.0, 1.7, 4.0)
	ui._process(0.0)
	var panel_forward: Vector3 = _world_panel_forward(ui._world_root)
	var toward_viewer := Vector3(camera.position.x, 0.0, camera.position.z).normalized()
	assert(panel_forward.dot(toward_viewer) > 0.99, "Ukon dialogue yaws toward the viewer")
	var director := TutorialDirector.new()
	director.begin_run(true, 1024)
	ui.update_director(director, true)
	assert(ui._xr_begin.visible and ui._xr_skip.visible, "XR menu offers tutorial or explore choice")
	assert(ui._xr_status.visible_characters == 0, "XR menu dialogue starts unrevealed")
	ui.finish_text()
	assert(ui._xr_status.visible_characters == -1, "XR menu can fast-forward dialogue")
	assert(ui._world_root.visible, "Ukon's world dialogue should be visible while tutorial is active")
	assert(ui._world_root.get_parent() == ukon, "dialogue must be attached to Ukon, not the tracked headset")
	assert(not ui._desktop_skip.visible, "desktop K skip button should not appear in XR")
	assert(ui._world_hint.text.contains("Y / B"))
	director.stage = TutorialDirector.Stage.ADAPTATION
	director.status_text = "Keep shutter closed to reveal the stream"
	ui.update_director(director, true)
	var full_line := ui._world_line.text
	ui._process(0.2)
	assert(ui._world_line.text == full_line and ui._world_line.visible_characters > 0
		and ui._world_line.visible_characters < full_line.length(),
		"typewriter reveals a fixed full line without changing wrapping")
	ui.finish_text()
	assert(ui._world_root.visible and ui._world_line.text.contains("Keep shutter closed"), "dialogue must remain visible through scripted stream reveal")
	assert(ui._world_line.visible_characters == -1, "world line can be fully revealed without changing its layout")
	director.stage = TutorialDirector.Stage.GROUPS
	ui.update_director(director, true)
	director.stage = TutorialDirector.Stage.FREE_PLAY
	ui.update_director(director, false)
	assert(ui._world_root.visible and ui._world_line.text == "Tutorial complete — explore!", "desktop shows world completion cue after adaptation")
	ui.update_director(director, true)
	assert(ui._world_root.visible and ui._world_line.text == "Tutorial complete — explore!", "XR shows world completion cue after adaptation")
	ui._process(2.9)
	assert(ui._world_root.visible, "completion cue remains visible for about three seconds")
	ui._process(0.2)
	assert(not ui._world_root.visible and not ui._desktop_root.visible, "completion cue hides after timeout")
	ui.update_ukon_proximity(2.0, director, true)
	assert(ui._world_root.visible and ui._world_line.get_parsed_text() == director.ukon_nearby_line(), "nearby dialogue has no speaker prefix")
	assert(ui._world_line.text.contains("[color=#91dda3]mushi[/color]"), "mushi keyword uses dialogue color")
	assert(ui._world_line.get_total_character_count() == director.ukon_nearby_line().length(),
		"dialogue markup must not change typewriter length")
	var first_visit := ui._world_line.get_parsed_text()
	ui.update_ukon_proximity(7.0, director, true)
	ui.update_ukon_proximity(2.0, director, true)
	assert(ui._world_line.get_parsed_text() == director.ukon_nearby_line(1)
		and ui._world_line.get_parsed_text() != first_visit,
		"Ukon rotates general tips between visits without restarting them each frame")
	director.begin_run(true, 1024)
	ui.update_director(director, true)
	director.skip()
	ui.update_director(director, true)
	assert(not ui._world_root.visible, "skip from an early tutorial stage does not show completion cue")
	ui.free()
	menu_root.free()
	camera.free()
	ukon.free()
	print("PASS tutorial UI: XR/desktop adaptation completion cue, timed dismissal, early skip suppression")
	quit()


func _world_panel_forward(panel: Node3D) -> Vector3:
	var forward := panel.global_basis.z
	forward.y = 0.0
	return forward.normalized()
