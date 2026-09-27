class_name TutorialUI
extends CanvasLayer

const DIALOGUE_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

signal skip_requested
signal begin_requested
signal continue_requested
signal sandbox_visibility_changed(open: bool)

var _desktop_root: Control
var _desktop_status: Label
var _desktop_skip: Button
var _desktop_begin: Button
var _desktop_nearby: Label
var _reward_toast: Label
var _xr_status: Label
var _xr_skip: Button
var _xr_begin: Button
var _xr_continue: Button
var _xr_reward: Label
var _xr_menu_contents: VBoxContainer
var _xr_sandbox_button: Button
var _xr_sandbox_close: Button
var _xr_sandbox_scroll: ScrollContainer
var _reward_remaining := 0.0
var _completion_remaining := 0.0
var _last_tutorial_stage := -1
var _reveal_amount := 0.0
var _sandbox_unlocked := false
var _tutorial_active := false
var _last_spoken_line := ""
var _spoken_characters := 0.0
var _ukon_nearby := false
var _ukon_visit_index := 0
var _world_root: Node3D
var _world_viewer: Camera3D
var _ukon_avatar: Node3D
var _world_line: RichTextLabel
var _world_hint: Label3D
var _mouth_seconds := 0.0
var _panel_material: ShaderMaterial
var _world_alpha := 1.0


func _ready() -> void:
	_build_desktop_ui()


func attach_ukon(ukon_anchor: Node3D, viewer: Camera3D) -> void:
	if ukon_anchor == null or viewer == null or _world_root != null:
		return
	_world_viewer = viewer
	_ukon_avatar = ukon_anchor.get_node_or_null("Miko") as Node3D
	_world_root = Node3D.new()
	_world_root.name = "UkonDialogue"
	ukon_anchor.add_child(_world_root)
	_world_root.position = Vector3(0.0, 2.34, 0.0)
	var back := MeshInstance3D.new()
	back.name = "DialoguePanel"
	var quad := QuadMesh.new()
	quad.size = Vector2(3.65, 0.88)
	back.mesh = quad
	_panel_material = ShaderMaterial.new()
	_panel_material.shader = preload("res://shaders/ukon_dialogue_panel.gdshader")
	_panel_material.render_priority = -20
	back.material_override = _panel_material
	_world_root.add_child(back)
	var text_viewport := SubViewport.new()
	text_viewport.name = "DialogueTextViewport"
	text_viewport.size = Vector2i(1500, 310)
	text_viewport.transparent_bg = true
	text_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_world_root.add_child(text_viewport)
	_world_line = RichTextLabel.new()
	_world_line.name = "UkonLine"
	_world_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_line.bbcode_enabled = true
	_world_line.scroll_active = false
	_world_line.add_theme_font_override("normal_font", DIALOGUE_FONT)
	_world_line.add_theme_font_size_override("normal_font_size", 68)
	_world_line.add_theme_color_override("default_color", Color("f3f4e8"))
	_world_line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	_world_line.add_theme_constant_override("outline_size", 7)
	_world_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_viewport.add_child(_world_line)
	_world_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_line.offset_left = 45.0
	_world_line.offset_right = -45.0
	var text_quad := MeshInstance3D.new()
	text_quad.name = "DialogueText"
	var text_mesh := QuadMesh.new()
	text_mesh.size = Vector2(3.5, 0.72)
	text_quad.mesh = text_mesh
	text_quad.position = Vector3(0.0, 0.10, 0.015)
	var text_material := StandardMaterial3D.new()
	text_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	text_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	text_material.albedo_texture = text_viewport.get_texture()
	text_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	text_material.no_depth_test = false
	text_material.render_priority = -19
	text_quad.material_override = text_material
	_world_root.add_child(text_quad)
	_world_hint = Label3D.new()
	_world_hint.name = "UkonHint"
	_world_hint.position = Vector3(0.0, -0.31, 0.015)
	_world_hint.pixel_size = 0.0022
	_world_hint.font = DIALOGUE_FONT
	_world_hint.font_size = 44
	_world_hint.width = 1450.0
	_world_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_hint.modulate = Color("c3dfd6")
	_world_hint.no_depth_test = false
	_world_root.add_child(_world_hint)
	_world_root.visible = false


func attach_xr_camera(camera: XRCamera3D) -> void:
	# Dialogue is attached to Ukon in world space by attach_ukon().
	_world_viewer = camera


func attach_xr_menu(menu_root: Control) -> void:
	if menu_root == null:
		return
	var contents := menu_root.get_node_or_null("Panel/Margin/Contents") as VBoxContainer
	if contents == null:
		return
	_xr_menu_contents = contents
	contents.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Introduction"
	title.add_theme_font_size_override("font_size", 22)
	contents.add_child(title)
	_xr_status = Label.new()
	_xr_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xr_status.visible = false
	contents.add_child(_xr_status)
	_xr_skip = Button.new()
	_xr_skip.text = "Skip introduction"
	_xr_skip.pressed.connect(func() -> void: skip_requested.emit())
	contents.add_child(_xr_skip)
	_xr_begin = Button.new()
	_xr_begin.text = "Show me"
	_xr_begin.pressed.connect(func() -> void: begin_requested.emit())
	contents.add_child(_xr_begin)
	_xr_continue = Button.new()
	_xr_continue.text = "Continue / show full line"
	_xr_continue.pressed.connect(request_advance)
	_xr_continue.visible = false
	contents.add_child(_xr_continue)
	_xr_reward = Label.new()
	_xr_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xr_reward.add_theme_color_override("font_color", Color("f4d59a"))
	contents.add_child(_xr_reward)
	_xr_sandbox_button = Button.new()
	_xr_sandbox_button.text = "Open tuning sandbox"
	_xr_sandbox_button.visible = false
	_xr_sandbox_button.pressed.connect(_open_xr_sandbox)
	contents.add_child(_xr_sandbox_button)
	_xr_sandbox_close = Button.new()
	_xr_sandbox_close.text = "Close tuning sandbox"
	_xr_sandbox_close.visible = false
	_xr_sandbox_close.pressed.connect(_close_xr_sandbox)
	contents.add_child(_xr_sandbox_close)
	_xr_sandbox_scroll = ScrollContainer.new()
	_xr_sandbox_scroll.name = "TuningSandboxScroll"
	_xr_sandbox_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xr_sandbox_scroll.custom_minimum_size.y = 360.0
	_xr_sandbox_scroll.visible = false
	contents.add_child(_xr_sandbox_scroll)


func attach_xr_sandbox(panel: PanelContainer) -> void:
	if _xr_sandbox_scroll == null or panel == null:
		return
	panel.reparent(_xr_sandbox_scroll)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2.ZERO
	panel.size = Vector2(790.0, 780.0)
	panel.custom_minimum_size = Vector2(790.0, 780.0)
	panel.visible = false


func set_sandbox_unlocked(unlocked: bool) -> void:
	_sandbox_unlocked = unlocked
	if not unlocked and _xr_sandbox_scroll != null and _xr_sandbox_scroll.visible:
		_xr_sandbox_scroll.visible = false
		_xr_sandbox_close.visible = false
		sandbox_visibility_changed.emit(false)
	if _xr_sandbox_button != null:
		_xr_sandbox_button.visible = unlocked and not (_xr_sandbox_scroll != null and _xr_sandbox_scroll.visible)


func update_director(director: TutorialDirector, xr_active: bool) -> void:
	var active := director.tutorial_enabled and director.stage != TutorialDirector.Stage.FREE_PLAY
	if active and director.status_text != _last_spoken_line:
		_last_spoken_line = director.status_text
		_spoken_characters = 0.0
	if director.tutorial_enabled and _last_tutorial_stage == TutorialDirector.Stage.GROUPS \
			and director.stage == TutorialDirector.Stage.FREE_PLAY:
		_completion_remaining = 3.0
	if active:
		_completion_remaining = 0.0
	_last_tutorial_stage = director.stage
	var completion_visible := _completion_remaining > 0.0
	_tutorial_active = active
	if _world_root != null:
		_world_root.visible = active or completion_visible
		if _world_root.visible:
			_world_line.text = "Tutorial complete — explore!" if completion_visible else _styled_dialogue(director.status_text)
			_world_line.visible_characters = -1 if completion_visible else int(_spoken_characters)
			_world_hint.text = _world_prompt(director, xr_active) if active else ""
	if _desktop_root != null:
		_desktop_status.text = "Tutorial complete — explore!" if completion_visible else director.status_text
		if director.stage == TutorialDirector.Stage.JAR_ORANGE or director.stage == TutorialDirector.Stage.JAR_BLUE:
			_desktop_status.text += "\nHold right mouse and drag sideways to twist the rope"
		elif director.stage == TutorialDirector.Stage.ADAPTATION or director.stage == TutorialDirector.Stage.SHUTTER:
			_desktop_status.text += "\nHold right mouse and drag down to close the shutter"
		_desktop_skip.visible = active and not xr_active
		_desktop_skip.text = "Explore myself · K" if director.stage == TutorialDirector.Stage.WELCOME else "Skip introduction · K"
		_desktop_begin.visible = director.stage == TutorialDirector.Stage.WELCOME and not xr_active
		if director.stage == TutorialDirector.Stage.WELCOME:
			_desktop_status.text += "\nEnter: quick lesson · K: explore"
		_desktop_root.visible = false
		if director.stage == TutorialDirector.Stage.ADAPTATION:
			_desktop_status.text += " · %d%%" % roundi(director.adaptation_progress * 100.0)
		_desktop_status.visible_characters = -1 if completion_visible else int(_spoken_characters)
	if _xr_status != null:
		_xr_status.text = director.status_text
		_xr_status.visible_characters = int(_spoken_characters)
		if director.stage == TutorialDirector.Stage.ADAPTATION:
			_xr_status.text += " · %d%%" % roundi(director.adaptation_progress * 100.0)
		_xr_skip.visible = active
		_xr_skip.text = "Explore myself" if director.stage == TutorialDirector.Stage.WELCOME else "Skip introduction"
		_xr_begin.visible = director.stage == TutorialDirector.Stage.WELCOME
		_xr_continue.visible = active and director.stage != TutorialDirector.Stage.WELCOME
		set_sandbox_unlocked(not director.tutorial_enabled or director.reward_is_unlocked)
		if _xr_reward != null and _reward_remaining <= 0.0:
			_xr_reward.text = ""
	if _reward_toast != null:
		_reward_toast.visible = _reward_remaining > 0.0 and not xr_active
	if _desktop_nearby != null:
		_desktop_nearby.visible = false


func update_ukon_proximity(distance: float, director: TutorialDirector, xr_active: bool = false) -> void:
	var nearby := director.tutorial_enabled and director.stage == TutorialDirector.Stage.FREE_PLAY and distance <= 6.0
	if nearby and not _ukon_nearby:
		_ukon_visit_index += 1
	elif not nearby:
		_ukon_nearby = false
	var line := director.ukon_nearby_line(_ukon_visit_index - 1) if nearby else ""
	_ukon_nearby = nearby
	_world_alpha = clampf((6.0 - distance) / 1.5, 0.0, 1.0) if nearby else 0.0
	if _world_root != null and not _tutorial_active and _completion_remaining <= 0.0:
		_world_root.visible = nearby
		if nearby:
			var full_line := line
			if full_line != _last_spoken_line:
				_last_spoken_line = full_line
				_spoken_characters = 0.0
			_world_line.text = _styled_dialogue(full_line)
			_world_line.visible_characters = int(_spoken_characters)
			_world_hint.text = ""
		else:
			_last_spoken_line = ""
			_spoken_characters = 0.0
	if _desktop_nearby != null:
		_desktop_nearby.visible = false


func _styled_dialogue(line: String) -> String:
	var styled := line
	for word in ["mushi", "Mushi"]:
		styled = styled.replace(word, "[color=#91dda3]%s[/color]" % word)
	for word in ["blue", "Blue"]:
		styled = styled.replace(word, "[color=#91baff]%s[/color]" % word)
	for word in ["red", "Red"]:
		styled = styled.replace(word, "[color=#ffb477]%s[/color]" % word)
	for word in ["光脈筋", "koumyakusuji", "light vein"]:
		styled = styled.replace(word, "[color=#e9cc80]%s[/color]" % word)
	return styled


func _world_prompt(director: TutorialDirector, xr_active: bool) -> String:
	if director.stage == TutorialDirector.Stage.WELCOME:
		return "Y / B: menu · Show me / Explore myself" if xr_active else "Enter: quick lesson · K: explore"
	if director.stage == TutorialDirector.Stage.SHUTTER:
		return "Close the lantern shutter" if xr_active else "Hold right mouse and drag down to close"
	if director.stage == TutorialDirector.Stage.ADAPTATION:
		var action := "trigger to continue" if xr_active else "Enter / click to continue"
		return "Eyes adapting · %d%% · %s" % [roundi(director.adaptation_progress * 100.0), action if director.can_continue() else "look for a moment"]
	if director.stage == TutorialDirector.Stage.REVEAL_WAIT:
		return "Open the shutter when ready" if director.reveal_can_reopen() else "Keep the shutter closed for a moment"
	if director.stage == TutorialDirector.Stage.JAR_NEUTRAL:
		if not director.can_continue():
			return "Watch it wander for a moment"
		return "Trigger to continue" if xr_active else "Enter / click to continue"
	if director.stage == TutorialDirector.Stage.JAR_BLUE or director.stage == TutorialDirector.Stage.JAR_ORANGE:
		if not director.can_continue():
			return "Shine blue and watch" if director.stage == TutorialDirector.Stage.JAR_BLUE else "Shine red and watch"
		return "Trigger to continue" if xr_active else "Enter / click to continue"
	if director.stage == TutorialDirector.Stage.GUIDE or director.stage == TutorialDirector.Stage.GROUPS:
		if not director.can_continue():
			return "Watch the mushi for a moment"
	return "Trigger to continue · Y / B: menu" if xr_active else "Enter / click to continue · K: skip"


func finish_text() -> void:
	_spoken_characters = float(_last_spoken_line.length())
	if _desktop_status != null:
		_desktop_status.visible_characters = -1
	if _xr_status != null:
		_xr_status.visible_characters = -1
	if _world_line != null:
		_world_line.text = _styled_dialogue(_last_spoken_line)
		_world_line.visible_characters = -1
	if _xr_continue != null:
		_xr_continue.visible = _tutorial_active


func request_advance() -> void:
	if not _tutorial_active:
		return
	if _spoken_characters < float(_last_spoken_line.length()):
		finish_text()
	else:
		continue_requested.emit()


func show_reward_unlocked() -> void:
	_reward_remaining = 8.0
	if _reward_toast != null:
		_reward_toast.text = "60% returned · Sandbox controls unlocked (F1)"
		_reward_toast.visible = true
	if _xr_reward != null:
		_xr_reward.text = "60% returned · Sandbox controls unlocked"


func show_progress_congratulations() -> void:
	_reward_remaining = 7.0
	if _reward_toast != null:
		_reward_toast.text = "Wonderful work! Most mushi have found their way home."
		_reward_toast.visible = true
	if _xr_reward != null:
		_xr_reward.text = "Wonderful work! Most mushi have found their way home."


func update_reveal(amount: float) -> void:
	_reveal_amount = clampf(amount, 0.0, 1.0)


func _open_xr_sandbox() -> void:
	if not _sandbox_unlocked:
		return
	_xr_sandbox_scroll.visible = true
	_xr_sandbox_close.visible = true
	_xr_sandbox_button.visible = false
	sandbox_visibility_changed.emit(true)


func _close_xr_sandbox() -> void:
	_xr_sandbox_scroll.visible = false
	_xr_sandbox_close.visible = false
	_xr_sandbox_button.visible = _sandbox_unlocked
	sandbox_visibility_changed.emit(false)


func _process(delta: float) -> void:
	_mouth_seconds += delta
	if is_instance_valid(_ukon_avatar) and _ukon_avatar.has_method("apply_voice_visemes"):
		var speaking := _world_root != null and _world_root.visible \
			and _spoken_characters < float(_last_spoken_line.length())
		var mouth := PackedFloat32Array()
		if speaking:
			# Quiet text has a small syllabic mouth motion. Reuse the VRM's existing
			# viseme driver without pretending there is recorded dialogue audio.
			mouth.resize(15)
			mouth[10] = 0.16 + 0.22 * pow(maxf(0.0, sin(_mouth_seconds * 37.0)), 1.5)
		_ukon_avatar.call("apply_voice_visemes", mouth, delta)
	if _world_root != null and is_instance_valid(_world_viewer):
		var toward := _world_viewer.global_position - _world_root.global_position
		toward.y = 0.0
		if toward.length_squared() > 0.001:
			_world_root.global_rotation.y = atan2(toward.x, toward.z)
		var distance := _world_viewer.global_position.distance_to(_world_root.global_position)
		var near_alpha := smoothstep(0.65, 1.4, distance)
		var far_alpha := 1.0 - smoothstep(12.0, 18.0, distance)
		var alpha := near_alpha * far_alpha * (1.0 if _tutorial_active or _completion_remaining > 0.0 else _world_alpha)
		_panel_material.set_shader_parameter("opacity", alpha)
		_world_line.modulate.a = alpha
		_world_hint.modulate.a = alpha
	if _world_root != null and _world_root.visible and _spoken_characters < float(_last_spoken_line.length()):
		_spoken_characters += delta * 45.0
		if _desktop_status != null:
			_desktop_status.visible_characters = int(_spoken_characters)
		if _xr_status != null:
			_xr_status.visible_characters = int(_spoken_characters)
		if _world_line != null:
			_world_line.visible_characters = int(_spoken_characters)
	if _completion_remaining > 0.0:
		_completion_remaining = maxf(0.0, _completion_remaining - delta)
		if _completion_remaining <= 0.0:
			if _desktop_root != null and not _tutorial_active:
				_desktop_root.visible = false
			if _world_root != null and not _tutorial_active:
				_world_root.visible = false
	if _reward_remaining > 0.0:
		_reward_remaining = maxf(0.0, _reward_remaining - delta)
		if _reward_remaining <= 0.0:
			if _reward_toast != null:
				_reward_toast.visible = false
			if _xr_reward != null:
				_xr_reward.text = ""


func _input(event: InputEvent) -> void:
	if not _tutorial_active:
		return
	if _world_root == null or not _world_root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			skip_requested.emit()
			get_viewport().set_input_as_handled()
		elif _desktop_begin.visible and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			begin_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			request_advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _desktop_begin.visible:
			begin_requested.emit()
		else:
			request_advance()
		get_viewport().set_input_as_handled()


func _build_desktop_ui() -> void:
	_desktop_root = Control.new()
	_desktop_root.name = "TutorialStatus"
	var dialogue_theme := Theme.new()
	dialogue_theme.default_font = DIALOGUE_FONT
	_desktop_root.theme = dialogue_theme
	_desktop_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_desktop_root.offset_top = 14.0
	_desktop_root.offset_bottom = 112.0
	_desktop_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desktop_root)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -440.0
	panel.offset_right = 440.0
	panel.offset_top = 0.0
	panel.offset_bottom = 94.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			finish_text())
	_desktop_root.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.075, 0.88)
	style.border_color = Color(0.36, 0.66, 0.62, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	_desktop_status = Label.new()
	_desktop_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desktop_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.add_theme_font_size_override("font_size", 18)
	_desktop_status.add_theme_color_override("font_color", Color("ecf3e8"))
	row.add_child(_desktop_status)
	_desktop_begin = Button.new()
	_desktop_begin.text = "Show me"
	_desktop_begin.pressed.connect(func() -> void: begin_requested.emit())
	row.add_child(_desktop_begin)
	_desktop_skip = Button.new()
	_desktop_skip.text = "Skip introduction · K"
	_desktop_skip.pressed.connect(func() -> void: skip_requested.emit())
	row.add_child(_desktop_skip)
	_reward_toast = Label.new()
	_reward_toast.anchor_left = 0.5
	_reward_toast.anchor_right = 0.5
	_reward_toast.offset_left = -280.0
	_reward_toast.offset_right = 280.0
	_reward_toast.offset_top = 94.0
	_reward_toast.offset_bottom = 132.0
	_reward_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_toast.add_theme_font_size_override("font_size", 21)
	_reward_toast.add_theme_font_override("font", DIALOGUE_FONT)
	_reward_toast.add_theme_color_override("font_color", Color("f4d59a"))
	_reward_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_reward_toast.add_theme_constant_override("shadow_offset_x", 2)
	_reward_toast.add_theme_constant_override("shadow_offset_y", 2)
	_reward_toast.visible = false
	add_child(_reward_toast)
	_desktop_nearby = Label.new()
	_desktop_nearby.name = "UkonNearbyDialogue"
	_desktop_nearby.anchor_left = 0.5
	_desktop_nearby.anchor_right = 0.5
	_desktop_nearby.anchor_top = 1.0
	_desktop_nearby.anchor_bottom = 1.0
	_desktop_nearby.offset_left = -440.0
	_desktop_nearby.offset_right = 440.0
	_desktop_nearby.offset_top = -128.0
	_desktop_nearby.offset_bottom = -46.0
	_desktop_nearby.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_nearby.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desktop_nearby.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_nearby.add_theme_font_size_override("font_size", 19)
	_desktop_nearby.add_theme_font_override("font", DIALOGUE_FONT)
	_desktop_nearby.add_theme_color_override("font_color", Color("f5eacb"))
	_desktop_nearby.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.96))
	_desktop_nearby.add_theme_constant_override("shadow_offset_x", 2)
	_desktop_nearby.add_theme_constant_override("shadow_offset_y", 2)
	_desktop_nearby.visible = false
	add_child(_desktop_nearby)
	_desktop_root.visible = false
