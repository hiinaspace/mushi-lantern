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
	var director := TutorialDirector.new()
	director.begin_run(true, 1024)
	ui.update_director(director, true)
	assert(ui._xr_cue.visible, "3D XR tutorial cue should be visible while tutorial is active")
	assert(ui._xr_cue.get_parent().get_parent() == camera, "XR cue must be attached under the tracked camera")
	assert(ui._xr_cue.no_depth_test, "XR cue should draw in front of geometry")
	assert(not ui._desktop_skip.visible, "desktop K skip button should not appear in XR")
	assert(ui._xr_cue.text.contains("Y / B"))
	director.stage = TutorialDirector.Stage.ADAPTATION
	director.status_text = "Keep shutter closed to reveal the stream"
	ui.update_director(director, true)
	assert(ui._xr_cue.visible and ui._xr_cue.text.contains("Keep shutter closed"), "cue must remain visible through scripted stream reveal")
	assert(not ui._xr_cue.text.contains("Space") and not ui._xr_cue.text.contains("Continue"), "XR tutorial has no manual advance instructions")
	director.stage = TutorialDirector.Stage.FREE_PLAY
	ui.update_director(director, false)
	assert(ui._desktop_root.visible and ui._desktop_status.text == "Tutorial complete — explore!", "desktop shows completion cue after adaptation")
	ui.update_director(director, true)
	assert(ui._xr_cue.visible and ui._xr_cue.text == "Tutorial complete — explore!", "XR shows completion cue after adaptation")
	ui._process(2.9)
	assert(ui._xr_cue.visible, "completion cue remains visible for about three seconds")
	ui._process(0.2)
	assert(not ui._xr_cue.visible and not ui._desktop_root.visible, "completion cue hides after timeout")
	director.begin_run(true, 1024)
	ui.update_director(director, true)
	director.skip()
	ui.update_director(director, true)
	assert(not ui._xr_cue.visible, "skip from an early tutorial stage does not show completion cue")
	ui.free()
	menu_root.free()
	camera.free()
	print("PASS tutorial UI: XR/desktop adaptation completion cue, timed dismissal, early skip suppression")
	quit()
