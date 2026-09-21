extends Node3D

const FIXED_STEP := 1.0 / 60.0
const DEFAULT_SEED := 40721
const PATCH_CENTERS := [Vector2(-14.4, -13.2), Vector2(14.6, -12.0), Vector2(15.4, 13.6)]
const ARENA_LAYOUT := "wide-60m-v1"
const SAVED_PRESETS_PATH := "user://m0_saved_presets.json"
const RUN_RECORDS_PATH := "user://m0_run_records.jsonl"

var simulation := FlockSimulation.new()
var light_field := LightField.new()
var presets: Array[HerdPreset] = HerdPreset.builtins()
var current_preset: HerdPreset
var current_preset_index: int = 3
var current_seed: int = DEFAULT_SEED
var fixture_count: int = 24
var accumulator: float = 0.0
var simulation_paused: bool = false
var top_down: bool = false
var debug_visible: bool = true
var elapsed: float = 0.0
var mode_times: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var config_changed: bool = false

var player: DesktopPlayer
var lantern: Lantern
var top_camera: Camera3D
var agent_nodes: Array[Node3D] = []
var field_overlay: MeshInstance3D
var field_overlay_elapsed: float = 0.0
var start_top_down: bool = false
var footprint: MeshInstance3D
var hud_label: Label
var help_label: Label
var panel: PanelContainer
var preset_label: Label
var seed_box: SpinBox
var strength_slider: HSlider
var social_slider: HSlider
var wander_slider: HSlider
var goal_slider: HSlider
var memory_slider: HSlider
var goal_width_slider: HSlider
var recovery_slider: HSlider
var blue_sleep_slider: HSlider
var wake_slider: HSlider
var mushroom_pull_slider: HSlider
var scatter_slider: HSlider
var energy_rows: Array[Control] = []
var preset_picker: OptionButton
var mushroom_nodes: Array[MushroomPatch] = []
var goal_halo: MeshInstance3D
var settings_history: Array[Dictionary] = []
var run_id: String = ""
var inspected_agent: int = 0
var saved_select: OptionButton
var save_name: LineEdit
var run_notes: LineEdit

var _initial_mode: int = -1
var _screenshot_path: String = ""
var _screenshot_delay: float = 1.0
var _screenshot_elapsed: float = 0.0

func _ready() -> void:
	_setup_input()
	_parse_arguments()
	_build_world()
	_build_player()
	_build_ui()
	_apply_preset(current_preset_index, false)
	_reset_run(false)
	_load_saved_preset_names()
	if _initial_mode >= 0:
		lantern.set_mode(_initial_mode as LightField.Mode)
	if start_top_down:
		_toggle_top_down()
	if not _screenshot_path.is_empty():
		player.set_process_unhandled_input(false)
		player.set_physics_process(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var shutter_delta := Input.get_axis("shutter_close", "shutter_open")
		if shutter_delta != 0.0:
			lantern.adjust_shutter(shutter_delta * delta * 0.6)
	if not simulation_paused:
		elapsed += delta
		mode_times[int(lantern.mode)] += delta
	light_field.update_transform(lantern.global_position, lantern.forward_direction())
	light_field.shutter_openness = lantern.shutter_openness
	light_field.mode = lantern.mode
	light_field.mode_strength = strength_slider.value if strength_slider != null else 1.0
	if not simulation_paused:
		accumulator = minf(accumulator + delta, FIXED_STEP * 8.0)
		while accumulator >= FIXED_STEP:
			simulation.step(FIXED_STEP, light_field, social_slider.value, wander_slider.value)
			accumulator -= FIXED_STEP
	_update_agent_visuals(accumulator / FIXED_STEP)
	_update_hud()
	_update_footprint()
	field_overlay_elapsed += delta
	if field_overlay_elapsed >= 0.1:
		field_overlay_elapsed = 0.0
		_update_field_overlay()
	if not _screenshot_path.is_empty():
		_screenshot_elapsed += delta
		if _screenshot_elapsed >= _screenshot_delay:
			_capture_and_quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mode_clear"):
		lantern.set_mode(LightField.Mode.CLEAR)
	elif event.is_action_pressed("mode_blue"):
		lantern.set_mode(LightField.Mode.BLUE)
	elif event.is_action_pressed("mode_orange"):
		lantern.set_mode(LightField.Mode.ORANGE)
	elif event.is_action_pressed("shutter_toggle"):
		lantern.toggle_shutter()
	elif event.is_action_pressed("reset_run"):
		_reset_run(true)
	elif event.is_action_pressed("toggle_pause"):
		simulation_paused = not simulation_paused
	elif event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible
		panel.visible = debug_visible
		footprint.visible = debug_visible
		field_overlay.visible = debug_visible
		_refresh_preset_visuals()
	elif event.is_action_pressed("toggle_topdown"):
		_toggle_top_down()
	elif event.is_action_pressed("toggle_fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("inspect_next"):
		inspected_agent = (inspected_agent + 1) % fixture_count
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree() and elapsed > 0.1:
		_write_run_record("window_close")

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("293640")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9cad5")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	sun.light_color = Color("f4e8cf")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var floor_material := _material(Color("64706c"), 0.92)
	_create_box_body("Ground", Vector3(60.0, 0.18, 60.0), Vector3(0.0, -0.1, 0.0), floor_material)
	_create_box_body("NorthWall", Vector3(60.0, 2.0, 0.35), Vector3(0.0, 1.0, -28.4), _material(Color("475250"), 0.95))
	_create_box_body("SouthWall", Vector3(60.0, 2.0, 0.35), Vector3(0.0, 1.0, 28.4), _material(Color("475250"), 0.95))
	_create_box_body("WestWall", Vector3(0.35, 2.0, 60.0), Vector3(-28.4, 1.0, 0.0), _material(Color("475250"), 0.95))
	_create_box_body("EastWall", Vector3(0.35, 2.0, 60.0), Vector3(28.4, 1.0, 0.0), _material(Color("475250"), 0.95))

	var obstacle_positions := PackedVector2Array([Vector2(-5.6, -4.4), Vector2(6.0, 4.0), Vector2(2.0, -14.0)])
	var obstacle_radii := PackedFloat32Array([1.05, 1.2, 0.85])
	for index: int in obstacle_positions.size():
		_create_trunk(index, obstacle_positions[index], obstacle_radii[index])
	simulation.obstacle_centers = obstacle_positions
	simulation.obstacle_radii = obstacle_radii
	light_field.obstacle_centers = obstacle_positions
	light_field.obstacle_radii = obstacle_radii

	var goal := MeshInstance3D.new()
	goal.name = "ReturnCircle"
	var goal_mesh := CylinderMesh.new()
	goal_mesh.top_radius = simulation.goal_radius
	goal_mesh.bottom_radius = simulation.goal_radius
	goal_mesh.height = 0.035
	goal.mesh = goal_mesh
	goal.position = Vector3(0.0, 0.025, 0.0)
	var goal_material := _material(Color(0.29, 0.92, 0.75, 0.32), 0.42)
	goal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	goal_material.emission_enabled = true
	goal_material.emission = Color("56e8bc")
	goal_material.emission_energy_multiplier = 0.35
	goal.material_override = goal_material
	add_child(goal)

	var beacon := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = simulation.goal_radius - 0.13
	torus.outer_radius = simulation.goal_radius
	beacon.mesh = torus
	beacon.position = Vector3(0.0, 0.06, 0.0)
	beacon.material_override = _material(Color("78ffd8"), 0.45)
	add_child(beacon)

	footprint = MeshInstance3D.new()
	var footprint_mesh := CylinderMesh.new()
	footprint_mesh.top_radius = 1.7
	footprint_mesh.bottom_radius = 1.7
	footprint_mesh.height = 0.025
	footprint.mesh = footprint_mesh
	var footprint_material := _material(Color(0.35, 0.75, 1.0, 0.16), 0.8)
	footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	footprint.material_override = footprint_material
	footprint.position.y = 0.045
	add_child(footprint)

	field_overlay = MeshInstance3D.new()
	field_overlay.mesh = ImmediateMesh.new()
	var field_material := StandardMaterial3D.new()
	field_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	field_material.vertex_color_use_as_albedo = true
	field_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	field_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	field_overlay.material_override = field_material
	field_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field_overlay)

	top_camera = Camera3D.new()
	top_camera.name = "TopDownCamera"
	top_camera.position = Vector3(0.0, 52.0, 0.0)
	top_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	top_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_camera.size = 62.0
	add_child(top_camera)

func _build_player() -> void:
	player = DesktopPlayer.new()
	player.name = "DesktopPlayer"
	player.position = Vector3(0.0, 0.0, 9.2)
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
	lantern = Lantern.new()
	lantern.name = "OffsetLantern"
	lantern.position = Vector3(0.72, -0.43, -1.05)
	lantern.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	camera.add_child(lantern)
	add_child(player)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud_label = Label.new()
	hud_label.position = Vector2(24.0, 18.0)
	hud_label.add_theme_font_size_override("font_size", 22)
	hud_label.add_theme_color_override("font_color", Color("eaf6f4"))
	hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	hud_label.add_theme_constant_override("shadow_offset_x", 2)
	hud_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud_label)

	help_label = Label.new()
	help_label.text = "WASD move · Shift slow · mouse look · 1 clear · 2 blue · 3 orange · F shutter · [ ] openness\nR reset same seed · P pause · T top-down · F1 debug · F11 fullscreen · I inspect next · Esc free mouse"
	help_label.position = Vector2(24.0, 826.0)
	help_label.add_theme_font_size_override("font_size", 15)
	help_label.add_theme_color_override("font_color", Color("dceae8"))
	canvas.add_child(help_label)

	panel = PanelContainer.new()
	panel.position = Vector2(1080.0, 18.0)
	panel.size = Vector2(336.0, 782.0)
	canvas.add_child(panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.075, 0.09, 0.93)
	panel_style.border_color = Color(0.28, 0.56, 0.58, 0.65)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 296.0
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 7)
	scroll.add_child(stack)
	var title := Label.new()
	title.text = "M0b · ENERGY LAB"
	title.add_theme_font_size_override("font_size", 21)
	stack.add_child(title)
	preset_label = Label.new()
	preset_label.add_theme_color_override("font_color", Color("89e4cf"))
	stack.add_child(preset_label)
	preset_picker = OptionButton.new()
	for index: int in presets.size():
		preset_picker.add_item(presets[index].preset_name, index)
	preset_picker.item_selected.connect(func(index: int) -> void: _apply_preset(index, true))
	stack.add_child(preset_picker)
	stack.add_child(HSeparator.new())
	strength_slider = _add_slider(stack, "Lantern influence", 0.25, 1.5, 1.0, 0.05)
	social_slider = _add_slider(stack, "Social force", 0.0, 1.8, 1.0, 0.05)
	wander_slider = _add_slider(stack, "Drift / wander", 0.0, 2.0, 1.0, 0.05)
	goal_slider = _add_slider(stack, "Goal resistance", 0.0, 2.5, 0.8, 0.01)
	memory_slider = _add_slider(stack, "Memory recovery", 0.2, 2.0, 0.85, 0.05)
	goal_width_slider = _add_slider(stack, "Goal width (m)", 1.0, 7.0, 1.8, 0.1)
	var energy_title := Label.new()
	energy_title.text = "Energy experiment · 90% response times"
	energy_title.add_theme_font_size_override("font_size", 13)
	stack.add_child(energy_title)
	energy_rows.append(energy_title)
	recovery_slider = _add_slider(stack, "Recover (s)", 3.0, 180.0, 30.0, 0.1)
	blue_sleep_slider = _add_slider(stack, "Blue sleep (s)", 1.0, 40.0, 10.0, 0.1)
	wake_slider = _add_slider(stack, "Orange wake (s)", 0.1, 8.0, 1.0, 0.01)
	mushroom_pull_slider = _add_slider(stack, "Mushroom pull", 0.0, 4.0, 1.0, 0.1)
	scatter_slider = _add_slider(stack, "Arousal scatter", 0.0, 1.0, 1.0, 0.05)
	for slider: HSlider in [recovery_slider, blue_sleep_slider, wake_slider, mushroom_pull_slider, scatter_slider]:
		energy_rows.append(slider.get_parent())

	recovery_slider.value_changed.connect(_on_tuning_changed.bind(&"energy_recovery_rate"))
	blue_sleep_slider.value_changed.connect(_on_tuning_changed.bind(&"blue_energy_response"))
	wake_slider.value_changed.connect(_on_tuning_changed.bind(&"orange_energy_response"))
	scatter_slider.value_changed.connect(_on_tuning_changed.bind(&"arousal_scatter_strength"))
	mushroom_pull_slider.value_changed.connect(_on_tuning_changed.bind(&"mushroom_attraction_weight"))
	goal_width_slider.value_changed.connect(_on_tuning_changed.bind(&"goal_repulsion_outer_width"))
	goal_slider.value_changed.connect(_on_tuning_changed.bind(&"goal_repulsion_strength"))
	memory_slider.value_changed.connect(_on_tuning_changed.bind(&"arousal_response"))
	strength_slider.value_changed.connect(_on_tuning_changed)
	social_slider.value_changed.connect(_on_tuning_changed)
	wander_slider.value_changed.connect(_on_tuning_changed)
	stack.add_child(HSeparator.new())
	var fixture_row := HBoxContainer.new()
	var tiny := Button.new()
	tiny.text = "Tiny fixture · 3"
	tiny.pressed.connect(_set_fixture.bind(3))
	fixture_row.add_child(tiny)
	var full := Button.new()
	full.text = "Full · 24"
	full.pressed.connect(_set_fixture.bind(24))
	fixture_row.add_child(full)
	stack.add_child(fixture_row)
	var seed_row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	seed_box = SpinBox.new()
	seed_box.min_value = 1
	seed_box.max_value = 99999999
	seed_box.value = current_seed
	seed_box.custom_minimum_size.x = 165.0
	seed_row.add_child(seed_box)
	var seed_apply := Button.new()
	seed_apply.text = "Reset"
	seed_apply.pressed.connect(_reset_from_seed_box)
	seed_row.add_child(seed_apply)
	stack.add_child(seed_row)
	stack.add_child(HSeparator.new())
	var save_title := Label.new()
	save_title.text = "Named tuning snapshot"
	stack.add_child(save_title)
	var save_row := HBoxContainer.new()
	save_name = LineEdit.new()
	save_name.placeholder_text = "name"
	save_name.custom_minimum_size.x = 205.0
	save_row.add_child(save_name)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_save_named_preset)
	save_row.add_child(save_button)
	stack.add_child(save_row)
	saved_select = OptionButton.new()
	saved_select.add_item("Load saved…")
	saved_select.item_selected.connect(_load_named_preset)
	stack.add_child(saved_select)
	run_notes = LineEdit.new()
	run_notes.placeholder_text = "Optional run note (saved on reset / quit)"
	stack.add_child(run_notes)
	var note := Label.new()
	note.text = "Blue: dormant · green: neutral · yellow/orange: aroused.\nResponse seconds are unopposed at full stimulus. Live changes are recorded; scroll for saves."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("adbfbe"))
	stack.add_child(note)

func _add_slider(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, value: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 135.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = value
	slider.step = step
	slider.custom_minimum_size.x = 96.0
	row.add_child(slider)
	var number := Label.new()
	number.text = "%.2f" % value
	number.custom_minimum_size.x = 40.0
	row.add_child(number)
	slider.set_meta("value_label", number)
	slider.value_changed.connect(func(next_value: float) -> void: number.text = "%.2f" % next_value)
	parent.add_child(row)
	return slider

func _create_trunk(index: int, horizontal_position: Vector2, radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = "OccludingTrunk%d" % (index + 1)
	body.position = Vector3(horizontal_position.x, 1.6, horizontal_position.y)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.72
	mesh.bottom_radius = radius
	mesh.height = 3.2
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(Color("5f493b"), 0.96)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 3.2
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _create_box_body(name_value: String, size: Vector3, position_value: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = name_value
	body.position = position_value
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _rebuild_agents() -> void:
	for node: Node3D in agent_nodes:
		node.queue_free()
	agent_nodes.clear()
	for index: int in simulation.positions.size():
		var agent := _create_agent_visual(index)
		agent_nodes.append(agent)
		add_child(agent)

func _create_agent_visual(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Mushi%02d" % index
	var colors: Array[Color] = [Color("a9eff0"), Color("cfb5ff"), Color("ffd39a")]
	var base_color: Color = colors[simulation.group_ids[index] % colors.size()]
	var body := MeshInstance3D.new()
	body.name = "Body"
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	body.mesh = sphere
	body.scale = Vector3(1.0, 0.7, 1.45)
	body.material_override = _emissive_material(base_color, 1.35)
	root.add_child(body)
	for side: int in [-1, 1]:
		var wing := MeshInstance3D.new()
		wing.name = "WingL" if side < 0 else "WingR"
		var wing_mesh := SphereMesh.new()
		wing_mesh.radius = 0.13
		wing_mesh.height = 0.26
		wing.mesh = wing_mesh
		wing.position = Vector3(0.19 * side, 0.04, 0.02)
		wing.scale = Vector3(1.2, 0.16, 1.7)
		var wing_material := _material(Color(base_color, 0.72), 0.4)
		wing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wing.material_override = wing_material
		root.add_child(wing)
	var eye := MeshInstance3D.new()
	eye.name = "FaceMark"
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.055
	eye_mesh.height = 0.11
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 0.015, -0.31)
	eye.material_override = _emissive_material(Color("26313b"), 0.2)
	root.add_child(eye)
	return root

func _update_agent_visuals(alpha: float) -> void:
	for index: int in agent_nodes.size():
		var node := agent_nodes[index]
		if simulation.lifecycles[index] == FlockSimulation.Lifecycle.RELEASED:
			node.visible = false
			continue
		node.visible = true
		var horizontal := simulation.previous_positions[index].lerp(simulation.positions[index], alpha)
		var phase := elapsed * (3.0 + simulation.arousals[index] * 3.0) + float(index) * 1.73
		var activity := smoothstep(0.0, current_preset.energy_neutral_target, simulation.arousals[index]) if current_preset.energy_dynamics else 1.0
		var height := FlockSimulation.BODY_HEIGHT + sin(phase) * 0.075 * activity
		if simulation.lifecycles[index] == FlockSimulation.Lifecycle.COMMITTED:
			height += simulation.lifecycle_times[index] * 0.7
		elif simulation.lifecycles[index] == FlockSimulation.Lifecycle.ASCENDING:
			height += simulation.lifecycle_times[index] * 2.5
		node.position = Vector3(horizontal.x, height, horizontal.y)
		var velocity := simulation.velocities[index]
		if velocity.length_squared() > 0.01:
			node.rotation.y = atan2(-velocity.x, -velocity.y)
		var flap := sin(phase * 2.4) * 0.55 * activity
		(node.get_node("WingL") as MeshInstance3D).rotation.z = -0.48 + flap
		(node.get_node("WingR") as MeshInstance3D).rotation.z = 0.48 - flap
		if current_preset.energy_dynamics:
			var color := EnergyVisual.color_for(simulation.arousals[index], current_preset.energy_neutral_target)
			var body_material := (node.get_node("Body") as MeshInstance3D).material_override as StandardMaterial3D
			body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			body_material.albedo_color = color
			body_material.emission = color
			body_material.emission_energy_multiplier = 0.3
			for wing_name: String in ["WingL", "WingR"]:
				var wing_material := (node.get_node(wing_name) as MeshInstance3D).material_override as StandardMaterial3D
				wing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				wing_material.albedo_color = Color(color, 0.72)

func _update_hud() -> void:
	for slider: HSlider in [strength_slider, social_slider, wander_slider, goal_slider, memory_slider, goal_width_slider, recovery_slider, blue_sleep_slider, wake_slider, mushroom_pull_slider, scatter_slider]:
		(slider.get_meta("value_label") as Label).text = "%.2f" % slider.value
	var shutter_text := "CLOSED" if lantern.shutter_openness <= 0.01 else "%d%% OPEN" % roundi(lantern.shutter_openness * 100.0)
	var pause_text := "  ·  PAUSED" if simulation_paused else ""
	var tuning_text := " · MODIFIED" if config_changed else ""
	hud_label.text = "%s  ·  %s\nReturned %d / %d  ·  Active %d\n%s%s%s" % [
		lantern.mode_label(), shutter_text, simulation.score, fixture_count,
		simulation.active_count(), current_preset.preset_name, tuning_text, pause_text
	]
	if debug_visible and not simulation.positions.is_empty():
		var i := mini(inspected_agent, simulation.positions.size() - 1)
		hud_label.text += "\nDisc = arrival target · tiles = sampled influence\nID %d · e %.2f · light %.2f · force (%.2f, %.2f) · %s" % [i, simulation.arousals[i], simulation.exposures[i], simulation.accelerations[i].x, simulation.accelerations[i].y, FlockSimulation.Lifecycle.keys()[simulation.lifecycles[i]]]
		if current_preset.energy_dynamics:
			hud_label.text += "\n%s · mushroom %.2f · blue → green → yellow → orange" % [EnergyVisual.state_name(simulation.arousals[i], current_preset.sleep_threshold), simulation.mushroom_exposures[i]]
	preset_label.text = "%s%s" % [current_preset.preset_name, " · modified" if config_changed else ""]

func _update_footprint() -> void:
	var target := light_field.ground_target(FlockSimulation.BODY_HEIGHT)
	footprint.position.x = target.x
	footprint.position.z = target.y
	var footprint_material := footprint.material_override as StandardMaterial3D
	var color := Color(0.95, 0.84, 0.52, 0.15)
	if lantern.mode == LightField.Mode.BLUE:
		color = Color(0.3, 0.75, 1.0, 0.18)
	elif lantern.mode == LightField.Mode.ORANGE:
		color = Color(1.0, 0.42, 0.18, 0.18)
	if lantern.shutter_openness <= 0.01:
		color.a = 0.035
	footprint_material.albedo_color = color

func _apply_preset(index: int, restart: bool) -> void:
	if restart and elapsed > 0.1:
		_write_run_record("preset_change")
	current_preset_index = index
	current_preset = presets[index].copy_preset()
	preset_picker.select(index)
	config_changed = false
	if strength_slider != null:
		strength_slider.set_value_no_signal(1.0)
		social_slider.set_value_no_signal(1.0)
		wander_slider.set_value_no_signal(1.0)
		goal_slider.set_value_no_signal(current_preset.goal_repulsion_strength)
		memory_slider.set_value_no_signal(current_preset.arousal_response)
		_sync_energy_controls()
	if restart:
		_reset_run(false)

func _reset_run(record_previous: bool) -> void:
	if record_previous and elapsed > 0.1:
		_write_run_record("reset")
	current_seed = roundi(seed_box.value) if seed_box != null else current_seed
	simulation.world_limit = 27.0
	simulation.spawn_centers = PackedVector2Array(PATCH_CENTERS)
	simulation.mushroom_centers = PackedVector2Array(PATCH_CENTERS.slice(0, 1 if fixture_count == 3 else 3)) if current_preset.energy_dynamics else PackedVector2Array()
	simulation.reset(fixture_count, current_seed, current_preset)
	_refresh_preset_visuals()
	_rebuild_agents()
	accumulator = 0.0
	elapsed = 0.0
	mode_times = PackedFloat32Array([0.0, 0.0, 0.0])
	player.position = Vector3(PATCH_CENTERS[0].x, 0.0, PATCH_CENTERS[0].y + 5.2) if fixture_count == 3 else Vector3(0.0, 0.0, 18.4)
	player.reset_look()
	inspected_agent = 0
	settings_history = [{"elapsed_seconds": 0.0, "settings": _current_settings()}]
	run_id = "%s-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()]
	if run_notes != null:
		run_notes.clear()
	lantern.set_mode(LightField.Mode.CLEAR if current_preset.energy_dynamics else LightField.Mode.BLUE)
	lantern.shutter_openness = 1.0
	lantern.adjust_shutter(0.0)

func _set_fixture(count: int) -> void:
	_write_run_record("fixture_change")
	fixture_count = count
	_reset_run(false)

func _reset_from_seed_box() -> void:
	_reset_run(true)

func _on_tuning_changed(value: float, parameter: StringName = &"") -> void:
	if not parameter.is_empty():
		var coefficient := value
		if parameter in [&"energy_recovery_rate", &"blue_energy_response", &"orange_energy_response"]:
			coefficient = log(10.0) / maxf(value, 0.001)
		current_preset.set(parameter, coefficient)
		simulation.preset.set(parameter, coefficient)
	_refresh_preset_visuals()
	config_changed = true
	settings_history.append({"elapsed_seconds": elapsed, "settings": _current_settings()})

func _current_settings() -> Dictionary:
	return {"arena_layout": ARENA_LAYOUT, "world_limit": simulation.world_limit, "coefficients": current_preset.to_dict(), "lantern_strength": strength_slider.value,
		"social_multiplier": social_slider.value, "wander_multiplier": wander_slider.value}

func _toggle_top_down() -> void:
	top_down = not top_down
	top_camera.current = top_down
	player.camera.current = not top_down
	player.look_enabled = not top_down
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if top_down else Input.MOUSE_MODE_CAPTURED

func _save_named_preset() -> void:
	var name_value := save_name.text.strip_edges()
	if name_value.is_empty():
		return
	var data := _load_saved_data()
	data[name_value] = {
		"base_preset": current_preset.to_dict(),
		"seed": current_seed,
		"fixture_count": fixture_count,
		"notes": run_notes.text.strip_edges() if run_notes != null else "",
		"lantern_strength": strength_slider.value,
		"social_multiplier": social_slider.value,
		"wander_multiplier": wander_slider.value,
	}
	var file := FileAccess.open(SAVED_PRESETS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()
	save_name.clear()
	_load_saved_preset_names()

func _load_named_preset(index: int) -> void:
	if index <= 0:
		return
	var preset_name := saved_select.get_item_text(index)
	var data := _load_saved_data()
	if not data.has(preset_name):
		return
	_write_run_record("saved_preset_load")
	var saved: Dictionary = data[preset_name]
	current_preset = HerdPreset.from_dict(saved.get("base_preset", {}))
	current_preset.preset_name = preset_name
	seed_box.value = int(saved.get("seed", current_seed))
	fixture_count = 3 if int(saved.get("fixture_count", fixture_count)) == 3 else 24
	goal_slider.set_value_no_signal(current_preset.goal_repulsion_strength)
	memory_slider.set_value_no_signal(current_preset.arousal_response)
	_sync_energy_controls()
	preset_picker.select(-1)
	strength_slider.set_value_no_signal(float(saved.get("lantern_strength", 1.0)))
	social_slider.set_value_no_signal(float(saved.get("social_multiplier", 1.0)))
	wander_slider.set_value_no_signal(float(saved.get("wander_multiplier", 1.0)))
	config_changed = false
	_reset_run(false)
	saved_select.select(0)

func _load_saved_preset_names() -> void:
	saved_select.clear()
	saved_select.add_item("Load saved…")
	var names: Array = _load_saved_data().keys()
	names.sort()
	for name_value: Variant in names:
		saved_select.add_item(str(name_value))

func _load_saved_data() -> Dictionary:
	if not FileAccess.file_exists(SAVED_PRESETS_PATH):
		return {}
	var file := FileAccess.open(SAVED_PRESETS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}

func _write_run_record(reason: String) -> void:
	if elapsed <= 0.01 or current_preset == null:
		return
	var record := {
		"recorded_at": Time.get_datetime_string_from_system(true),
		"run_id": run_id,
		"settings_history": settings_history,
		"reason": reason,
		"notes": run_notes.text.strip_edges() if run_notes != null else "",
		"seed": current_seed,
		"preset": current_preset.preset_name,
		"fixture_count": fixture_count,
		"arena_layout": ARENA_LAYOUT,
		"elapsed_seconds": snappedf(elapsed, 0.001),
		"returns": simulation.score,
		"mode_seconds": {
			"clear": snappedf(mode_times[LightField.Mode.CLEAR], 0.001),
			"blue": snappedf(mode_times[LightField.Mode.BLUE], 0.001),
			"orange": snappedf(mode_times[LightField.Mode.ORANGE], 0.001),
		},
		"config_modified": config_changed,
		"coefficients": current_preset.to_dict(),
		"live_multipliers": {
			"lantern_strength": strength_slider.value,
			"social": social_slider.value,
			"wander": wander_slider.value,
		},
	}
	var file := FileAccess.open(RUN_RECORDS_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RUN_RECORDS_PATH, FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(record))

func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		if args[index] == "--screenshot" and index + 1 < args.size():
			_screenshot_path = args[index + 1]
			index += 2
		elif args[index] == "--screenshot-delay" and index + 1 < args.size():
			_screenshot_delay = maxf(0.15, float(args[index + 1]))
			index += 2
		elif args[index] == "--mode" and index + 1 < args.size():
			_initial_mode = ["clear", "blue", "orange"].find(args[index + 1].to_lower())
			index += 2
		elif args[index] == "--top-down":
			start_top_down = true
			index += 1
		elif args[index] == "--tiny":
			fixture_count = 3
			index += 1
		elif args[index] == "--preset" and index + 1 < args.size():
			current_preset_index = clampi(int(args[index + 1]), 0, presets.size() - 1)
			index += 2
		else:
			index += 1

func _capture_and_quit() -> void:
	if DisplayServer.get_name() == "headless":
		_screenshot_path = ""
		push_error("Screenshot requires a rendered window, not --headless")
		get_tree().quit(1)
		return
	var image := get_viewport().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(_screenshot_path)
	var directory := absolute_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var error := image.save_png(absolute_path)
	print("M0_SCREENSHOT path=%s error=%s" % [absolute_path, error_string(error)])
	_write_run_record("screenshot")
	get_tree().quit(0 if error == OK else 1)

func _setup_input() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("mode_clear", KEY_1)
	_add_key_action("mode_blue", KEY_2)
	_add_key_action("mode_orange", KEY_3)
	_add_key_action("shutter_toggle", KEY_F)
	_add_key_action("shutter_close", KEY_BRACKETLEFT)
	_add_key_action("shutter_open", KEY_BRACKETRIGHT)
	_add_key_action("reset_run", KEY_R)
	_add_key_action("toggle_pause", KEY_P)
	_add_key_action("toggle_debug", KEY_F1)
	_add_key_action("inspect_next", KEY_I)
	_add_key_action("toggle_fullscreen", KEY_F11)
	_add_key_action("toggle_topdown", KEY_T)
	_add_key_action("release_mouse", KEY_ESCAPE)

func _add_key_action(action: StringName, keycode: Key, require_ctrl: bool = false) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.ctrl_pressed = require_ctrl
	InputMap.action_add_event(action, event)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.56)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _update_field_overlay() -> void:
	var mesh := field_overlay.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if not debug_visible:
		return
	var begun := false
	for x: int in range(-13, 14):
		for z: int in range(-13, 14):
			var point := Vector3(light_field.source_position.x + x * 0.8, FlockSimulation.BODY_HEIGHT, light_field.source_position.z + z * 0.8)
			var sample := light_field.sample(point)
			if sample < 0.035:
				continue
			if not begun:
				mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				begun = true
			var color := Color(0.25, 0.7, 1.0, sample * 0.5)
			if light_field.mode == LightField.Mode.ORANGE:
				color = Color(1.0, 0.45, 0.15, sample * 0.5)
			mesh.surface_set_color(color)
			for corner: Vector2 in [Vector2(-0.18,-0.18), Vector2(0.18,-0.18), Vector2(0.18,0.18), Vector2(-0.18,-0.18), Vector2(0.18,0.18), Vector2(-0.18,0.18)]:
				mesh.surface_add_vertex(Vector3(point.x + corner.x, 0.065, point.z + corner.y))
	if begun:
		mesh.surface_end()

func _sync_energy_controls() -> void:
	goal_width_slider.set_value_no_signal(current_preset.goal_repulsion_outer_width)
	recovery_slider.set_value_no_signal(log(10.0) / maxf(0.001, current_preset.energy_recovery_rate))
	blue_sleep_slider.set_value_no_signal(log(10.0) / maxf(0.001, current_preset.blue_energy_response))
	wake_slider.set_value_no_signal(log(10.0) / maxf(0.001, current_preset.orange_energy_response))
	mushroom_pull_slider.set_value_no_signal(current_preset.mushroom_attraction_weight)
	scatter_slider.set_value_no_signal(current_preset.arousal_scatter_strength)
	memory_slider.get_parent().visible = not current_preset.energy_dynamics
	for row: Control in energy_rows:
		row.visible = current_preset.energy_dynamics

func _refresh_preset_visuals() -> void:
	if goal_halo == null:
		goal_halo = MeshInstance3D.new()
		goal_halo.position.y = 0.045
		var halo_material := _material(Color(0.9, 0.55, 0.25, 0.2), 1.0)
		halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		goal_halo.material_override = halo_material
		goal_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(goal_halo)
	var ring := TorusMesh.new()
	ring.inner_radius = simulation.goal_radius + current_preset.goal_repulsion_outer_width - 0.025
	ring.outer_radius = ring.inner_radius + 0.05
	goal_halo.mesh = ring
	goal_halo.visible = debug_visible and current_preset.goal_repulsion_strength > 0.0
	if mushroom_nodes.is_empty():
		for center: Vector2 in PATCH_CENTERS:
			var patch := MushroomPatch.new()
			patch.position = Vector3(center.x, 0.0, center.y)
			add_child(patch)
			mushroom_nodes.append(patch)
	for index: int in mushroom_nodes.size():
		var patch := mushroom_nodes[index]
		patch.visible = current_preset.energy_dynamics and (fixture_count != 3 or index == 0)
		patch.set_radius(current_preset.mushroom_radius)
		patch.show_boundary(debug_visible)
