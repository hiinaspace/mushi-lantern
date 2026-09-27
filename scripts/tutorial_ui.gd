class_name TutorialUI
extends CanvasLayer

const DIALOGUE_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

signal skip_requested
signal begin_requested
signal sandbox_visibility_changed(open: bool)

var _desktop_root: Control
var _desktop_status: Label
var _desktop_skip: Button
var _desktop_begin: Button
var _desktop_nearby: Label
var _xr_cue: Label3D
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


func _ready() -> void:
	_build_desktop_ui()


func attach_xr_camera(camera: XRCamera3D) -> void:
	if camera == null or _xr_cue != null:
		return
	var cue_root := Node3D.new()
	cue_root.name = "TutorialCue3D"
	camera.add_child(cue_root)
	cue_root.position = Vector3(0.0, -0.24, -1.5)
	_xr_cue = Label3D.new()
	_xr_cue.name = "TutorialCueLabel"
	_xr_cue.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_xr_cue.pixel_size = 0.0012
	_xr_cue.font_size = 30
	_xr_cue.font = DIALOGUE_FONT
	_xr_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xr_cue.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xr_cue.modulate = Color("f0f3e9")
	_xr_cue.outline_size = 10
	_xr_cue.outline_modulate = Color(0.008, 0.018, 0.018, 0.94)
	_xr_cue.no_depth_test = true
	_xr_cue.text = ""
	_xr_cue.visible = false
	cue_root.add_child(_xr_cue)


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
	_xr_continue.text = "Show full line"
	_xr_continue.pressed.connect(finish_text)
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
	if director.status_text != _last_spoken_line:
		_last_spoken_line = director.status_text
		_spoken_characters = 0.0
	var active := director.tutorial_enabled and director.stage != TutorialDirector.Stage.FREE_PLAY
	if director.tutorial_enabled and _last_tutorial_stage == TutorialDirector.Stage.GROUPS \
			and director.stage == TutorialDirector.Stage.FREE_PLAY:
		_completion_remaining = 3.0
	if active:
		_completion_remaining = 0.0
	_last_tutorial_stage = director.stage
	var completion_visible := _completion_remaining > 0.0
	_tutorial_active = active
	if _desktop_root != null:
		_desktop_status.text = "Tutorial complete — explore!" if completion_visible else director.status_text
		if director.stage == TutorialDirector.Stage.JAR_ORANGE or director.stage == TutorialDirector.Stage.JAR_BLUE:
			_desktop_status.text += "\n2: blue · 3: orange"
		elif director.stage == TutorialDirector.Stage.ADAPTATION or director.stage == TutorialDirector.Stage.SHUTTER:
			_desktop_status.text += "\nF: shutter · wheel: adjust"
		_desktop_skip.visible = active and not xr_active
		_desktop_skip.text = "Explore myself · K" if director.stage == TutorialDirector.Stage.WELCOME else "Skip introduction · K"
		_desktop_begin.visible = director.stage == TutorialDirector.Stage.WELCOME and not xr_active
		if director.stage == TutorialDirector.Stage.WELCOME:
			_desktop_status.text += "\nEnter: quick lesson · K: explore"
		_desktop_root.visible = not xr_active and (active or completion_visible)
		if director.stage == TutorialDirector.Stage.ADAPTATION:
			_desktop_status.text += " · %d%%" % roundi(director.adaptation_progress * 100.0)
		_desktop_status.visible_characters = -1 if completion_visible else int(_spoken_characters)
	if _xr_cue != null:
		_xr_cue.visible = xr_active and (active or completion_visible)
		if _xr_cue.visible:
			var status := "Tutorial complete — explore!" if completion_visible else director.status_text
			if director.stage == TutorialDirector.Stage.ADAPTATION:
				status += " · %d%%" % roundi(director.adaptation_progress * 100.0)
			_xr_cue.text = status if completion_visible else "%s\nY / B opens menu" % status
	if _xr_status != null:
		_xr_status.text = director.status_text
		_xr_status.visible_characters = int(_spoken_characters)
		if director.stage == TutorialDirector.Stage.ADAPTATION:
			_xr_status.text += " · %d%%" % roundi(director.adaptation_progress * 100.0)
		_xr_skip.visible = active
		_xr_skip.text = "Explore myself" if director.stage == TutorialDirector.Stage.WELCOME else "Skip introduction"
		_xr_begin.visible = director.stage == TutorialDirector.Stage.WELCOME
		_xr_continue.visible = active and _spoken_characters < float(_last_spoken_line.length())
		set_sandbox_unlocked(not director.tutorial_enabled or director.reward_is_unlocked)
		if _xr_reward != null and _reward_remaining <= 0.0:
			_xr_reward.text = ""
	if _reward_toast != null:
		_reward_toast.visible = _reward_remaining > 0.0 and not xr_active
	if _desktop_nearby != null and active:
		_desktop_nearby.visible = false


func update_ukon_proximity(distance: float, director: TutorialDirector, xr_active: bool = false) -> void:
	var nearby := director.tutorial_enabled and director.stage == TutorialDirector.Stage.FREE_PLAY and distance <= 4.5
	var line := director.ukon_nearby_line() if nearby else ""
	if _desktop_nearby != null:
		_desktop_nearby.text = "Ukon: " + line
		_desktop_nearby.visible = nearby and not xr_active
	if _xr_cue != null and xr_active and nearby:
		_xr_cue.text = "Ukon: " + line
		_xr_cue.visible = true
	elif _xr_cue != null and xr_active and director.stage == TutorialDirector.Stage.FREE_PLAY and _completion_remaining <= 0.0:
		_xr_cue.visible = false


func finish_text() -> void:
	_spoken_characters = float(_last_spoken_line.length() + 80)
	if _desktop_status != null:
		_desktop_status.visible_characters = -1
	if _xr_status != null:
		_xr_status.visible_characters = -1
	if _xr_continue != null:
		_xr_continue.visible = false


func show_reward_unlocked() -> void:
	_reward_remaining = 8.0
	if _reward_toast != null:
		_reward_toast.text = "60% returned · Sandbox controls unlocked (F1)"
		_reward_toast.visible = true
	if _xr_reward != null:
		_xr_reward.text = "60% returned · Sandbox controls unlocked"


func show_broom_unlocked() -> void:
	_reward_remaining = 9.0
	if _reward_toast != null:
		_reward_toast.text = "Ukon: Wonderful work! Broom flight unlocked."
		_reward_toast.visible = true
	if _xr_reward != null:
		_xr_reward.text = "Ukon: Wonderful work! Broom flight unlocked."


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
	if _tutorial_active and _spoken_characters < float(_last_spoken_line.length() + 80):
		_spoken_characters += delta * 90.0
		if _desktop_status != null:
			_desktop_status.visible_characters = int(_spoken_characters)
		if _xr_status != null:
			_xr_status.visible_characters = int(_spoken_characters)
	if _completion_remaining > 0.0:
		_completion_remaining = maxf(0.0, _completion_remaining - delta)
		if _completion_remaining <= 0.0:
			if _desktop_root != null and not _tutorial_active:
				_desktop_root.visible = false
			if _xr_cue != null and not _tutorial_active:
				_xr_cue.visible = false
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
	if _desktop_root == null or not _desktop_root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			skip_requested.emit()
			get_viewport().set_input_as_handled()
		elif _desktop_begin.visible and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			begin_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			finish_text()
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
