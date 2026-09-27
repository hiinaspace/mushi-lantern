extends Node3D

const FIXED_STEP := 1.0 / 60.0
const DEFAULT_SEED := 40721
const GROVE_GOAL_RADIUS := 2.65
const PVP_LEFT_GOAL := Vector2(-38.0, 6.0)
const PVP_RIGHT_GOAL := Vector2(38.0, 6.0)
const PVP_CENTER_SPAWNS := [Vector2(0.0, -3.0), Vector2(0.0, 0.0), Vector2(0.0, 3.0)]
const TUTORIAL_XZ := Vector2(-3.0, 4.0)
const TUTORIAL_LOOK_XZ := Vector2(14.0, -2.0)
const PATCH_CENTERS := [Vector2(-14.4, -13.2), Vector2(14.6, -12.0), Vector2(15.4, 13.6)]
const ARENA_LAYOUT := "wide-60m-v1"
const SAVED_PRESETS_PATH := "user://m0_saved_presets.json"
const RUN_RECORDS_PATH := "user://m0_run_records.jsonl"
const AVATAR_FIT_PATH := "user://mushi_avatar_fit.json"
const VOICE_SETTINGS_PATH := "user://mushi_voice_settings.json"
const XR_COMFORT_PATH := "user://mushi_xr_comfort.json"
const BROOM_UNLOCK_PATH := "user://mushi_broom_unlock.json"
const UI_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
## Desktop palm contact corrections in staff-local metres. XR tracking has its
## own pose path and never uses these artist-tunable offsets.
@export var desktop_right_grip_offset := Vector3.ZERO
@export var desktop_left_control_offset := Vector3.ZERO

var environment_enabled: bool = true
var terrain_size: int = 128
var world_surface: Variant
var terrain_environment: Node3D
var quality_menu: CanvasLayer
var audio_mix_menu: Variant
var friend_menu: FriendMenu
var sun_light: DirectionalLight3D
var night_environment: Environment
var goal_shrine: GoalShrine
var second_goal_shrine: GoalShrine
var _game_mode := "classic"
var goal_beacon: Node3D
var _pvp_beacons: Array[Node3D] = []
var _last_shrine_score: int = -1
var _last_second_shrine_score: int = -1
var _milestone_times: Dictionary = {}
var _tutorial_movement_locked: bool = false
var _xr_tutorial_centered: bool = false
var _xr_recenter_cooldown: float = 0.0
var _tutorial_chain_label: Label3D
var _quality_settings: Dictionary = {}
var _menu_was_paused: bool = false
var _friend_was_paused: bool = false
var _xr_menu_was_paused: bool = false
var _desktop_tuning_open: bool = false
var _network: Variant
var _network_extension: Resource
var _voice: MushiVoice
var _voice_start_unmuted := false
var _broom_test_enabled := false
var _voice_input_device := ""
var _voice_gain_db := 0.0
var _voice_gate_db := -38.0
var _voice_receive_gain_db := 0.0
var _multiplayer_role := "offline" # offline, host, client
var _multiplayer_epoch: int = 0
var _multiplayer_sequence: int = 0
var _last_sent_snapshot_revision: int = -1
var _lantern_send_clock: float = 0.0
var _peer_fields: Dictionary = {}
var _peer_last_input_msec: Dictionary = {}
var _peer_last_sequence: Dictionary = {}
var _peer_lanterns: Dictionary = {}
var _peer_staffs: Dictionary = {}
var _peer_avatars: Dictionary = {}
var _local_avatar: MushiMultiplayerAvatar
var _local_avatar_hue: float = 0.0
var _avatar_eye_height_override: float = 0.0
var _avatar_arm_reach: float = 1.3
var _xr_avatar_scale_ready := false
var _xr_avatar_calibration_seconds := 0.0
var _xr_avatar_raw_eye_height := 0.0
var _xr_comfort := {"snap_turn": false, "move_hand": "left", "vignette_strength": 0.0, "haptics": true}
var _broom_permanently_unlocked := false
var _joined_peers: Dictionary = {}
var _network_status := "Offline"
var _last_sent_score: int = -1
var _multiplayer_cli_mode := ""
var _multiplayer_previous_skip := false
var _multiplayer_previous_force_tutorial := false
var _client_config_reset := false
var _network_diag_clock := 0.0
var _snapshot_payload_bytes := 0
var _snapshot_chunks_sent := 0
var _snapshot_chunks_received := 0
var _impaired_chunks: Array[Dictionary] = []
var _impair_rng := RandomNumberGenerator.new()
var _impair_jitter_ms := 0
var _impair_loss_percent := 0.0
var _impair_dropped := 0
var _max_remote_spots := 3

var simulation: Variant = FlockSimulation.new()
var flight_enabled: bool = true
var simulation_backend: String = "gpu"
var backend_picker: OptionButton
var _active_backend: String = "cpu"
var _backend_notice: String = ""
var flight_toggle: CheckBox
var flight_marker: MeshInstance3D
var sim_step_ms: float = 0.0
var visual_update_ms: float = 0.0
var flight_goal_volume: MeshInstance3D
var light_field := LightField.new()
var presets: Array[HerdPreset] = HerdPreset.builtins()
var current_preset: HerdPreset
var current_preset_index: int = 9
var current_seed: int = DEFAULT_SEED
var fixture_count: int = 1024
var accumulator: float = 0.0
var active_step: float = FIXED_STEP
var simulation_paused: bool = false
var _tutorial_swarm_alpha := 1.0
var top_down: bool = false
var debug_visible: bool = true
var elapsed: float = 0.0
var mode_times: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var config_changed: bool = false

var player: DesktopPlayer
var staff_tool: Variant
var xr_player: Variant
var xr_viewport: SubViewport
var xr_staff_interaction: Variant
var lantern: Lantern
var grove_audio: Node
var top_camera: Camera3D
var spectator_camera: MushiSpectatorCamera
var _spectator_adaptation: float = -1.0
var agent_nodes: Array[Node3D] = []
var glyph_swarm: GlyphSwarm
var return_handoff: ReturnHandoffVisual
var tutorial_director: TutorialDirector
var tutorial_guide: TutorialGuideVisual
var tutorial_ui: TutorialUI
var size_slider: HSlider
var height_slider: HSlider
var billboard_toggle: CheckBox
var variation_slider: HSlider
var contagion_slider: HSlider
var formation_follow_slider: HSlider
var cluster_pressure_slider: HSlider
var cluster_target_slider: HSlider
var waking_toggle: CheckBox
var population_rows: Array[Control] = []
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

var _saved_preset_arg: String = ""
var _count_override: int = -1
var _initial_mode: int = -1
var _screenshot_path: String = ""
var _screenshot_delay: float = 1.0
var _screenshot_elapsed: float = 0.0
var _want_xr: bool = false
var _desktop_aim: Vector2 = Vector2.ZERO
var _desktop_left_hand_pose := Transform3D.IDENTITY
var _desktop_left_hand_blend := 0.0
var _desktop_recall_held: bool = false
var _xr_recall_owner: XRController3D
var _skip_tutorial_requested := false
var _force_tutorial := false
var _visual_tuning_override := false
var _last_tutorial_score := -1
var _stream_visibility := 0.0
var _visual_sliders: Dictionary = {}
var _visual_tuning_defaults: Dictionary = {}
var _visual_tuning := {
	"dark_seconds": 6.0, "light_seconds": 1.5,
	"stream_start": 0.48, "stream_end": 0.90, "stream_seconds": 0.9,
	"star_start": 0.14, "star_end": 0.89, "milky_start": 0.64, "milky_end": 0.96,
	"foliage_start": 0.90, "foliage_end": 0.99,
	"clear_start": 0.10, "clear_end": 0.65, "clear_distance_start": 17.0, "clear_distance_end": 52.0,
	"river_width": 2.5, "river_depth": 1.0,
	"horizon_flare_strength": 0.25, "horizon_flare_spread": 1.0,
	"far_scintillation_blend": 1.0,
	"path_long": 1.0, "path_medium": 1.0, "path_long_speed": 1.0, "path_medium_speed": 1.0,
	"path_long_frequency": 1.0, "path_medium_frequency": 1.0,
	"surface_bump": 1.0, "surface_bump_speed": 1.0, "surface_bump_frequency": 1.0,
}

func _ready() -> void:
	process_physics_priority = 100
	_visual_tuning_defaults = _visual_tuning.duplicate()
	_setup_input()
	quality_menu = load("res://scripts/environment_settings.gd").new()
	_quality_settings = quality_menu.get_settings()
	fixture_count = int(_quality_settings.get("population", 1024))
	_parse_arguments()
	_load_avatar_fit()
	_load_voice_settings()
	_load_xr_comfort()
	_load_broom_unlock()
	_voice_start_unmuted = _voice_start_unmuted or OS.get_environment("MUSHI_VOICE_UNMUTED") == "1" or OS.get_environment("MUSHI_VOICE_TRANSMIT") == "1"
	_impair_rng.seed = 40721
	_impair_jitter_ms = maxi(0, int(OS.get_environment("MUSHI_NET_JITTER_MS")))
	_impair_loss_percent = clampf(float(OS.get_environment("MUSHI_NET_LOSS_PERCENT")), 0.0, 100.0)
	if not OS.get_environment("MUSHI_MAX_REMOTE_LIGHTS").is_empty():
		_max_remote_spots = clampi(int(OS.get_environment("MUSHI_MAX_REMOTE_LIGHTS")), 0, 7)
	if not OS.get_environment("MUSHI_AVATAR_EYE_HEIGHT").is_empty():
		_avatar_eye_height_override = clampf(float(OS.get_environment("MUSHI_AVATAR_EYE_HEIGHT")), 1.1, 2.1)
	if DisplayServer.get_name() == "headless":
		environment_enabled = false
		_want_xr = false
	if environment_enabled and RenderingServer.get_current_rendering_method() == "gl_compatibility":
		push_error("The terrain scene requires Vulkan Mobile GPU flight. Use --flat-lab for the legacy CPU lab.")
		get_tree().quit(1)
		return
	if environment_enabled:
		debug_visible = false
		flight_enabled = true
		simulation_backend = "gpu"
		simulation.goal_radius = GROVE_GOAL_RADIUS
		world_surface = load("res://scripts/environment_surface.gd").create(terrain_size, DEFAULT_SEED)
	_build_world()
	_build_player()
	if _want_xr:
		_build_xr_player()
	_ensure_local_avatar()
	_local_avatar.set_local_first_person(true)
	tutorial_director = TutorialDirector.new()
	tutorial_director.goal_acceptance_changed.connect(_on_tutorial_goal_acceptance_changed)
	tutorial_director.reveal_changed.connect(_on_tutorial_reveal_changed)
	tutorial_director.adaptation_started.connect(_on_tutorial_adaptation_started)
	tutorial_director.reward_unlocked.connect(_on_tutorial_reward_unlocked)
	tutorial_director.broom_reward_unlocked.connect(_on_tutorial_broom_reward_unlocked)
	tutorial_director.guide_released.connect(_on_tutorial_guide_released)
	tutorial_guide = TutorialGuideVisual.new()
	tutorial_guide.name = "TutorialGuide"
	add_child(tutorial_guide)
	tutorial_ui = TutorialUI.new()
	add_child(tutorial_ui)
	tutorial_ui.skip_requested.connect(_skip_tutorial)
	tutorial_ui.begin_requested.connect(tutorial_director.choose_tutorial)
	tutorial_ui.continue_requested.connect(tutorial_director.request_continue)
	tutorial_ui.sandbox_visibility_changed.connect(_on_tutorial_sandbox_visibility_changed)
	var ukon_anchor := get_node_or_null("MikoPresentation") as Node3D
	var tutorial_viewer: Camera3D = xr_player.camera if xr_player != null and xr_player.xr_active else player.camera
	tutorial_ui.attach_ukon(ukon_anchor, tutorial_viewer)
	if xr_player != null and xr_player.xr_active:
		tutorial_ui.attach_xr_camera(xr_player.camera)
		for controller: XRController3D in [xr_player.left_controller, xr_player.right_controller]:
			controller.button_pressed.connect(func(action: String) -> void:
				if action == "trigger_click" and not xr_player.is_menu_open():
					tutorial_ui.request_advance())
		var tutorial_surface := xr_player.get_node("Camera/MenuSurface") as XRToolsViewport2DIn3D
		if tutorial_surface.scene_node is Control:
			tutorial_ui.attach_xr_menu(tutorial_surface.scene_node as Control)
	_build_xr_tutorial_chain_cue()
	_build_audio()
	audio_mix_menu = load("res://scripts/audio_mix_panel.gd").new()
	add_child(audio_mix_menu)
	audio_mix_menu.panel_visibility_changed.connect(_on_audio_mix_visibility)
	var mushi_pitch_range: Vector2 = audio_mix_menu.get_mushi_pitch_range()
	grove_audio.set_mushi_pitch_range(mushi_pitch_range.x, mushi_pitch_range.y)
	audio_mix_menu.mushi_pitch_range_changed.connect(grove_audio.set_mushi_pitch_range)
	if xr_player != null and xr_player.xr_active:
		var xr_surface := xr_player.get_node("Camera/MenuSurface") as XRToolsViewport2DIn3D
		if xr_surface.scene_node is Control:
			audio_mix_menu.attach_xr_menu(xr_surface.scene_node as Control)
	_build_ui()
	_apply_visual_tuning()
	panel.visible = debug_visible
	if xr_player != null and xr_player.xr_active:
		tutorial_ui.attach_xr_sandbox(panel)
	_apply_preset(current_preset_index, false)
	_reset_run(false)
	_load_saved_preset_names()
	if not _saved_preset_arg.is_empty():
		var found := false
		for saved_index: int in range(1, saved_select.item_count):
			if saved_select.get_item_text(saved_index) == _saved_preset_arg:
				_load_named_preset(saved_index)
				found = true
				break
		if not found:
			push_warning("Saved preset not found: " + _saved_preset_arg)
		if _count_override > 0 and fixture_count != _count_override:
			fixture_count = _count_override
			_reset_run(false)
	add_child(quality_menu)
	quality_menu.settings_changed.connect(_apply_quality)
	quality_menu.population_reset_requested.connect(_set_fixture)
	quality_menu.panel_visibility_changed.connect(_on_quality_visibility)
	quality_menu.sync_population(fixture_count)
	_apply_quality(_quality_settings)
	friend_menu = FriendMenu.new()
	add_child(friend_menu)
	friend_menu.avatar_fit_changed.connect(_on_avatar_fit_changed)
	friend_menu.voice_mute_changed.connect(_on_voice_mute_changed)
	friend_menu.voice_input_device_changed.connect(_on_voice_input_device_changed)
	friend_menu.voice_gain_changed.connect(_on_voice_gain_changed)
	friend_menu.voice_gate_changed.connect(_on_voice_gate_changed)
	friend_menu.voice_receive_gain_changed.connect(_on_voice_receive_gain_changed)
	friend_menu.voice_devices_requested.connect(_refresh_voice_controls)
	friend_menu.comfort_changed.connect(_on_xr_comfort_changed)
	friend_menu.set_comfort_values(_xr_comfort)
	friend_menu.set_avatar_fit_values(
		_avatar_eye_height_override if _avatar_eye_height_override > 0.0 else 1.6,
		_avatar_arm_reach)
	friend_menu.new_game_requested.connect(_on_friend_new_game)
	friend_menu.mode_requested.connect(_on_friend_mode_requested)
	friend_menu.settings_requested.connect(_on_friend_settings)
	friend_menu.audio_settings_requested.connect(_on_friend_audio_settings)
	friend_menu.quit_requested.connect(_on_friend_quit)
	friend_menu.quality_profile_requested.connect(quality_menu.apply_profile)
	friend_menu.skip_requested.connect(_on_friend_skip)
	friend_menu.tuning_requested.connect(_on_friend_tuning)
	friend_menu.menu_visibility_changed.connect(_on_friend_menu_visibility)
	friend_menu.multiplayer_host_requested.connect(_on_multiplayer_host_requested)
	friend_menu.multiplayer_join_requested.connect(_on_multiplayer_join_requested)
	friend_menu.multiplayer_leave_requested.connect(_leave_multiplayer)
	if not _multiplayer_cli_mode.is_empty():
		_init_multiplayer_network()
		_start_multiplayer(OS.get_environment("MUSHI_ROOM_SECRET"), _multiplayer_cli_mode == "host")
	_refresh_voice_controls()
	if xr_player != null and xr_player.xr_active:
		var friend_xr_surface := xr_player.get_node("Camera/MenuSurface") as XRToolsViewport2DIn3D
		if friend_xr_surface.scene_node is Control:
			friend_menu.attach_xr_menu(friend_xr_surface.scene_node as Control)
	elif environment_enabled and _screenshot_path.is_empty() and OS.get_environment("MUSHI_TEST_DATA_ROOT").is_empty():
		friend_menu.set_open(true)
	if _initial_mode >= 0:
		lantern.set_mode(_initial_mode as LightField.Mode)
	if start_top_down:
		_toggle_top_down()
	if not _screenshot_path.is_empty():
		set_process_unhandled_input(false)
		player.set_process_unhandled_input(false)
		player.set_physics_process(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	_update_staff_pose(delta)

func _process(delta: float) -> void:
	if _voice != null and friend_menu != null:
		friend_menu.set_voice_meter(_voice.get_input_meter_db())
	if xr_player != null and xr_player.xr_active:
		_calibrate_xr_avatar_scale(delta)
		player.camera.global_transform = xr_player.camera.global_transform
	_update_local_avatar(delta)
	if spectator_camera != null and spectator_camera.active:
		spectator_camera.controls_enabled = not (friend_menu != null and friend_menu.is_open()) \
			and not (quality_menu != null and quality_menu.is_open()) \
			and not (audio_mix_menu != null and audio_mix_menu.is_open()) and not _desktop_tuning_open
	if _active_backend == "gpu":
		if not simulation.gpu_error.is_empty():
			if environment_enabled:
				_backend_notice = "Terrain requires GPU flight: " + simulation.gpu_error
				simulation_paused = true
				_update_hud()
				return
			_backend_notice = "GPU unavailable; CPU reference: " + simulation.gpu_error
			push_warning(_backend_notice)
			simulation_backend = "cpu"
			backend_picker.select(0)
			_reset_run(false)
		elif not simulation.gpu_ready:
			_update_hud()
			hud_label.text += "\nPreparing GPU simulation…"
			return
	if _tutorial_locks_shutter() and lantern.shutter_openness < 0.999:
		lantern.set_shutter(1.0, false)
	if not simulation_paused:
		elapsed += delta
		mode_times[int(lantern.mode)] += delta
		_recenter_xr_tutorial_if_needed(delta)
		if tutorial_director != null and (tutorial_director.stage == TutorialDirector.Stage.ADAPTATION \
				or tutorial_director.stage == TutorialDirector.Stage.REVEAL_WAIT and not tutorial_director.reveal_can_reopen()):
			# The eight-second guided reveal owns both shutter and adaptation so
			# other controls cannot interrupt the first sky/ground composition.
			lantern.set_shutter(0.0)
		elif environment_enabled:
			if _multiplayer_role == "offline":
				lantern.advance_adaptation(delta, _viewer_lantern_exposure())
			else:
				lantern.advance_adaptation_to(delta, _viewer_multiplayer_adaptation_target())
		var was_guided_adaptation := tutorial_director.stage == TutorialDirector.Stage.ADAPTATION
		tutorial_director.advance(delta, int(lantern.mode), lantern.shutter_openness, lantern.night_vision)
		if was_guided_adaptation:
			lantern.reset_adaptation(tutorial_director.adaptation_progress)
		if tutorial_director.stage == TutorialDirector.Stage.JAR_NEUTRAL:
			lantern.request_mode(LightField.Mode.CLEAR)
	if spectator_camera != null and spectator_camera.active and _spectator_adaptation >= 0.0:
		lantern.reset_adaptation(_spectator_adaptation)
	_sync_tutorial_movement_lock()
	if tutorial_guide != null:
		if lantern != null:
			tutorial_guide.set_light_source(lantern.global_position)
		tutorial_guide.set_guide_state(tutorial_director.guide_state)
		if tutorial_director.tutorial_enabled and tutorial_director.stage == TutorialDirector.Stage.FREE_PLAY:
			tutorial_guide.visible = false
	_update_stream_visibility(delta)
	if night_environment != null:
		NightEnvironment.set_night_vision(night_environment, lantern.night_vision)
		if glyph_swarm != null:
			glyph_swarm.update_visibility_context(lantern.night_vision, lantern.mode == LightField.Mode.CLEAR, lantern.shutter_openness, delta)
		if terrain_environment != null:
			terrain_environment.set_night_vision(lantern.night_vision)
		for mushroom_patch: MushroomPatch in mushroom_nodes:
			mushroom_patch.set_night_vision(lantern.night_vision)
		if goal_shrine != null:
			goal_shrine.set_night_vision(lantern.night_vision)
			var primary_score: int = simulation.goal_scores[0] if _game_mode == "two_shrines" and simulation is FlightSimulation else simulation.score
			if primary_score != _last_shrine_score:
				if GroveAudio.should_play_shrine_confirmation(_last_shrine_score, primary_score):
					grove_audio.play_shrine_return(0, goal_shrine.global_position)
				_last_shrine_score = primary_score
				goal_shrine.set_progress(primary_score, fixture_count)
		if second_goal_shrine != null and _game_mode == "two_shrines":
			second_goal_shrine.set_night_vision(lantern.night_vision)
			if simulation is FlightSimulation and simulation.goal_scores[1] != _last_second_shrine_score:
				if GroveAudio.should_play_shrine_confirmation(_last_second_shrine_score, simulation.goal_scores[1]):
					grove_audio.play_shrine_return(1, second_goal_shrine.global_position)
				_last_second_shrine_score = simulation.goal_scores[1]
				second_goal_shrine.set_progress(_last_second_shrine_score, fixture_count)
	light_field.update_transform(lantern.global_position, lantern.forward_direction())
	light_field.shutter_openness = lantern.shutter_openness
	light_field.mode = lantern.mode
	if environment_enabled:
		light_field.half_angle_degrees = lantern.BEHAVIOR_HALF_ANGLE_DEGREES
		light_field.range_m = lantern.spot.spot_range
	light_field.mode_strength = strength_slider.value if strength_slider != null else 1.0
	_update_multiplayer(delta)
	# The final explanation introduces the living grove, so let the swarm
	# appear and move while that line is still on screen.
	var tutorial_playing := tutorial_director != null and tutorial_director.tutorial_enabled \
		and tutorial_director.stage not in [TutorialDirector.Stage.GROUPS, TutorialDirector.Stage.FREE_PLAY]
	_tutorial_swarm_alpha = move_toward(_tutorial_swarm_alpha, 0.0 if tutorial_playing else 1.0, delta * 0.8)
	if glyph_swarm != null:
		glyph_swarm.set_scene_opacity(_tutorial_swarm_alpha)
	if not simulation_paused and not tutorial_playing and _multiplayer_role != "client":
		accumulator = minf(accumulator + delta, active_step * (4.0 if fixture_count >= 256 else 8.0))
		while accumulator >= active_step:
			var step_start := Time.get_ticks_usec()
			if _multiplayer_role == "host" and _active_backend == "gpu":
				var fields: Array[LightField] = [light_field]
				for peer_id: String in _peer_fields:
					if Time.get_ticks_msec() - int(_peer_last_input_msec.get(peer_id, 0)) <= 500:
						fields.append(_peer_fields[peer_id] as LightField)
				simulation.step(active_step, light_field, social_slider.value, wander_slider.value, fields)
			else:
				simulation.step(active_step, light_field, social_slider.value, wander_slider.value)
			sim_step_ms = lerpf(sim_step_ms, float(Time.get_ticks_usec() - step_start) / 1000.0, 0.05)
			accumulator -= active_step
	if _multiplayer_role == "client" and simulation is RemoteFlightSimulation:
		simulation.advance_replica(delta)
	_record_completion_milestones()
	if _multiplayer_role == "host":
		_broadcast_multiplayer_state()
	if tutorial_director != null and simulation.score != _last_tutorial_score:
		_last_tutorial_score = simulation.score
		tutorial_director.observe_score(simulation.score)
	if tutorial_ui != null and tutorial_director != null:
		tutorial_ui.update_director(tutorial_director, xr_player != null and xr_player.xr_active)
		var guide := get_node_or_null("MikoPresentation/Miko") as Node3D
		if guide != null:
			tutorial_ui.update_ukon_proximity(_viewer_eye_position().distance_to(guide.global_position),
				tutorial_director, xr_player != null and xr_player.xr_active)
			if guide.has_method("set_guide_look_target"):
				guide.call("set_guide_look_target", _viewer_eye_position(),
					tutorial_director.tutorial_enabled and tutorial_director.stage == TutorialDirector.Stage.FREE_PLAY, delta)
	_update_xr_tutorial_chain_cue()
	if friend_menu != null and tutorial_director != null:
		var session_status: String = tutorial_director.status_text + " · " + _network_status
		if _game_mode == "two_shrines" and simulation is FlightSimulation:
			session_status = "Two shrines · Amber %d / Blue %d · %d/%d returned · %s" % [simulation.goal_scores[0], simulation.goal_scores[1], simulation.score, fixture_count, _network_status]
		if not _milestone_times.is_empty():
			session_status += " · " + _milestone_caption()
		friend_menu.update_session(session_status, tutorial_director.tutorial_enabled and tutorial_director.stage != TutorialDirector.Stage.FREE_PLAY, _tutorial_sandbox_available())
		friend_menu.set_elapsed_time(elapsed)
	var visual_start := Time.get_ticks_usec()
	_update_agent_visuals(accumulator / active_step, delta)
	visual_update_ms = lerpf(visual_update_ms, float(Time.get_ticks_usec() - visual_start) / 1000.0, 0.05)
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
	if player != null and player.lamp_adjusting and event is InputEventMouseButton:
		var adjust_button := event as InputEventMouseButton
		if adjust_button.button_index == MOUSE_BUTTON_RIGHT and not adjust_button.pressed:
			_end_desktop_lamp_adjust()
			get_viewport().set_input_as_handled()
			return
	if xr_player == null or not xr_player.xr_active:
		if event.is_action_pressed("toggle_spectator") and not event.is_echo():
			_toggle_spectator()
			get_viewport().set_input_as_handled()
			return
		if spectator_camera != null and spectator_camera.active:
			if event.is_action_pressed("spectator_sweep") and not event.is_echo():
				var goal_xz: Vector2 = simulation.goal_position
				var target := Vector3(goal_xz.x, _ground_height(goal_xz) + 2.0, goal_xz.y)
				spectator_camera.toggle_sweep(target)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("spectator_darken") and not event.is_echo():
				_spectator_adaptation = clampf((_spectator_adaptation if _spectator_adaptation >= 0.0 else lantern.night_vision) - 0.2, 0.0, 1.0)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("spectator_brighten") and not event.is_echo():
				_spectator_adaptation = clampf((_spectator_adaptation if _spectator_adaptation >= 0.0 else lantern.night_vision) + 0.2, 0.0, 1.0)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("spectator_auto_adaptation") and not event.is_echo():
				_spectator_adaptation = -1.0
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("release_mouse") and friend_menu != null:
			if _desktop_tuning_open:
				_desktop_tuning_open = false
				panel.visible = false
				friend_menu.set_open(true)
				get_viewport().set_input_as_handled()
				return
			if quality_menu != null and quality_menu.is_open():
				quality_menu.set_open(false)
				get_viewport().set_input_as_handled()
				return
			if audio_mix_menu != null and audio_mix_menu.is_open():
				audio_mix_menu.set_open(false)
				get_viewport().set_input_as_handled()
				return
			friend_menu.toggle()
			get_viewport().set_input_as_handled()
			return
		if friend_menu != null and friend_menu.is_open():
			return
	if event.is_action_pressed("tutorial_skip") and tutorial_director != null and tutorial_director.tutorial_enabled:
		_skip_tutorial()
		get_viewport().set_input_as_handled()
		return
	if (quality_menu != null and quality_menu.is_open()) or (audio_mix_menu != null and audio_mix_menu.is_open()):
		return
	if (xr_player == null or not xr_player.xr_active) and event is InputEventMouseButton \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and staff_tool != null and staff_tool.desktop_can_control_lantern():
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and player.look_enabled:
			staff_tool.begin_desktop_adjust()
			player.lamp_adjusting = true
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			get_viewport().set_input_as_handled()
			return
	if xr_player == null or not xr_player.xr_active:
		if spectator_camera != null and spectator_camera.active:
			if event.is_action_pressed("toggle_debug"):
				debug_visible = not debug_visible
				hud_label.visible = debug_visible
				help_label.visible = debug_visible
				panel.visible = debug_visible and _tutorial_sandbox_available()
				footprint.visible = debug_visible
				field_overlay.visible = debug_visible
				_refresh_preset_visuals()
			elif event.is_action_pressed("toggle_fullscreen"):
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if event.is_action_pressed("staff_drop_pickup"):
			if tutorial_director != null and tutorial_director.tutorial_enabled and tutorial_director.stage != TutorialDirector.Stage.FREE_PLAY:
				get_viewport().set_input_as_handled()
				return
			if staff_tool.placement == StaffTool.Placement.HELD:
				staff_tool.release_final()
			elif player.camera.global_position.distance_to(staff_tool.global_position) < 2.5:
				staff_tool.set_held_world_pose(_desktop_staff_pose())
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("staff_recall"):
			_desktop_recall_held = true
			staff_tool.begin_recall(player.camera.global_transform)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("staff_recall"):
			_desktop_recall_held = false
			staff_tool.end_recall()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("reset_run"):
		_reset_run(true)
	elif event.is_action_pressed("toggle_pause"):
		simulation_paused = not simulation_paused
	elif event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible
		hud_label.visible = debug_visible
		help_label.visible = debug_visible
		panel.visible = debug_visible and _tutorial_sandbox_available()
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

func _exit_tree() -> void:
	if _xr_avatar_scale_ready:
		if xr_player != null:
			xr_player.world_scale = 1.0
		XRServer.world_scale = 1.0
	if simulation.has_method("dispose"):
		simulation.dispose()


func _calibrate_xr_avatar_scale(delta: float) -> void:
	if _xr_avatar_scale_ready or _local_avatar == null or xr_player == null:
		return
	# Sample the unscaled tracked height once the headset has a stable pose.
	# Reapplying a factor measured after XRServer.world_scale changes would feed
	# the mapping back into itself. The environment override is a standing-height
	# calibration for a session that begins while seated or crouched.
	var raw_height: float = xr_player.camera.transform.origin.y
	if not is_finite(raw_height) or raw_height < 1.1 or raw_height > 2.1:
		return
	_xr_avatar_raw_eye_height = maxf(_xr_avatar_raw_eye_height, raw_height)
	_xr_avatar_calibration_seconds += minf(delta, 0.1)
	if _xr_avatar_calibration_seconds < 0.5:
		return
	var player_height := _avatar_eye_height_override if _avatar_eye_height_override > 0.0 else _xr_avatar_raw_eye_height
	var authored_height := _local_avatar.get_authored_eye_height()
	xr_player.world_scale = clampf(authored_height / player_height, 0.6, 1.25)
	_xr_avatar_scale_ready = true
	if friend_menu != null and _avatar_eye_height_override <= 0.0:
		friend_menu.set_avatar_fit_values(player_height, _avatar_arm_reach)
	print("MUSHI_AVATAR_SCALE authored_eye=%.3f player_eye=%.3f world_scale=%.3f" % [
		authored_height, player_height, xr_player.world_scale])


func _load_avatar_fit() -> void:
	if not FileAccess.file_exists(AVATAR_FIT_PATH):
		return
	var file := FileAccess.open(AVATAR_FIT_PATH, FileAccess.READ)
	if file == null:
		return
	var saved: Variant = JSON.parse_string(file.get_as_text())
	if saved is Dictionary:
		_avatar_eye_height_override = clampf(float(saved.get("standing_height", 0.0)), 0.0, 2.1)
		if _avatar_eye_height_override > 0.0:
			_avatar_eye_height_override = maxf(_avatar_eye_height_override, 1.1)
		_avatar_arm_reach = clampf(float(saved.get("arm_reach", 1.3)), 0.9, 1.5)


func _on_avatar_fit_changed(standing_height: float, arm_reach: float) -> void:
	_avatar_eye_height_override = clampf(standing_height, 1.1, 2.1)
	_avatar_arm_reach = clampf(arm_reach, 0.9, 1.5)
	if _local_avatar != null:
		_local_avatar.set_arm_reach_scale(_avatar_arm_reach)
	if _xr_avatar_scale_ready and xr_player != null and xr_player.xr_active and _local_avatar != null:
		xr_player.world_scale = clampf(_local_avatar.get_authored_eye_height() /
			_avatar_eye_height_override, 0.6, 1.25)
	var file := FileAccess.open(AVATAR_FIT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"standing_height": _avatar_eye_height_override,
			"arm_reach": _avatar_arm_reach}))


func _load_voice_settings() -> void:
	if not FileAccess.file_exists(VOICE_SETTINGS_PATH):
		return
	var file := FileAccess.open(VOICE_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var saved: Variant = JSON.parse_string(file.get_as_text())
	if saved is Dictionary:
		_voice_input_device = str(saved.get("input_device", ""))
		_voice_gain_db = clampf(float(saved.get("gain_db", 0.0)), -24.0, 24.0)
		_voice_gate_db = clampf(float(saved.get("gate_db", -38.0)), -60.0, -20.0)
		_voice_receive_gain_db = clampf(float(saved.get("receive_gain_db", 0.0)), -30.0, 12.0)


func _load_xr_comfort() -> void:
	if not FileAccess.file_exists(XR_COMFORT_PATH):
		return
	var file := FileAccess.open(XR_COMFORT_PATH, FileAccess.READ)
	if file == null:
		return
	var saved: Variant = JSON.parse_string(file.get_as_text())
	if saved is Dictionary:
		_xr_comfort = _validated_xr_comfort(saved)


func _load_broom_unlock() -> void:
	if not FileAccess.file_exists(BROOM_UNLOCK_PATH):
		return
	var file := FileAccess.open(BROOM_UNLOCK_PATH, FileAccess.READ)
	if file == null:
		return
	var saved: Variant = JSON.parse_string(file.get_as_text())
	_broom_permanently_unlocked = saved is Dictionary and bool(saved.get("unlocked", false))


func _validated_xr_comfort(value: Dictionary) -> Dictionary:
	return {
		"snap_turn": bool(value.get("snap_turn", false)),
		"move_hand": "right" if str(value.get("move_hand", "left")) == "right" else "left",
		"vignette_strength": clampf(float(value.get("vignette_strength", 0.0)), 0.0, 1.0),
		"haptics": bool(value.get("haptics", true)),
	}


func _on_xr_comfort_changed(settings: Dictionary) -> void:
	_xr_comfort = _validated_xr_comfort(settings)
	_apply_xr_comfort()
	var file := FileAccess.open(XR_COMFORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_xr_comfort))


func _apply_xr_comfort() -> void:
	if xr_player == null:
		return
	xr_player.set_snap_turn(bool(_xr_comfort["snap_turn"]))
	xr_player.set_move_hand_left(_xr_comfort["move_hand"] == "left")
	xr_player.set_vignette_strength(float(_xr_comfort["vignette_strength"]))
	xr_player.set_haptics_enabled(bool(_xr_comfort["haptics"]))


func _save_voice_settings() -> void:
	var file := FileAccess.open(VOICE_SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"input_device": _voice_input_device,
			"gain_db": _voice_gain_db, "gate_db": _voice_gate_db,
			"receive_gain_db": _voice_receive_gain_db}))


func _refresh_voice_controls() -> void:
	if friend_menu == null:
		return
	friend_menu.set_voice_available(_voice != null)
	if _voice == null:
		friend_menu.set_voice_controls(true, "Default", PackedStringArray(["Default"]),
			_voice_gain_db, _voice_gate_db, _voice_receive_gain_db)
		return
	friend_menu.set_voice_controls(_voice.is_muted(), _voice.get_input_device(),
		_voice.get_input_devices(), _voice.get_input_gain_db(),
		_voice.get_gate_threshold_db(), _voice.get_receive_gain_db())


func _on_voice_mute_changed(muted: bool) -> void:
	if _voice != null:
		_voice.set_muted(muted)
	_refresh_voice_controls()


func _on_voice_input_device_changed(device: String) -> void:
	if _voice == null:
		return
	_voice.set_input_device(device)
	_voice_input_device = _voice.get_input_device()
	_save_voice_settings()
	_refresh_voice_controls()


func _on_voice_gain_changed(gain_db: float) -> void:
	if _voice == null:
		return
	_voice.set_input_gain_db(gain_db)
	_voice_gain_db = _voice.get_input_gain_db()
	_save_voice_settings()
	_refresh_voice_controls()


func _on_voice_gate_changed(threshold_db: float) -> void:
	if _voice == null:
		return
	_voice.set_gate_threshold_db(threshold_db)
	_voice_gate_db = _voice.get_gate_threshold_db()
	_save_voice_settings()
	_refresh_voice_controls()


func _on_voice_receive_gain_changed(gain_db: float) -> void:
	if _voice == null:
		return
	_voice.set_receive_gain_db(gain_db)
	_voice_receive_gain_db = _voice.get_receive_gain_db()
	_save_voice_settings()
	_refresh_voice_controls()

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("293640")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9cad5")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if environment_enabled:
		NightEnvironment.configure(environment)
		night_environment = environment
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun_light = sun
	sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	sun.light_color = Color("f4e8cf")
	sun.light_energy = 0.0 if environment_enabled else 1.25
	sun.shadow_enabled = not environment_enabled
	add_child(sun)

	if environment_enabled:
		terrain_environment = load("res://scripts/terrain_environment.gd").new()
		add_child(terrain_environment)
		terrain_environment.build(world_surface)
		_add_miko_presentation()
		light_field.world_surface = world_surface
		light_field.environment_obstacles = world_surface.get_obstacles()
	else:
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
	goal.position = Vector3(0.0, _ground_height(Vector2.ZERO) + 0.025, 0.0)
	var goal_material := _material(Color(0.29, 0.92, 0.75, 0.32), 0.42)
	goal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	goal_material.emission_enabled = true
	goal_material.emission = Color("56e8bc")
	goal_material.emission_energy_multiplier = 0.35
	goal.material_override = goal_material
	add_child(goal)
	goal.visible = not environment_enabled
	flight_goal_volume = MeshInstance3D.new()
	var goal_volume_mesh := CylinderMesh.new()
	goal_volume_mesh.top_radius = simulation.goal_radius
	goal_volume_mesh.bottom_radius = simulation.goal_radius
	goal_volume_mesh.height = 2.8
	flight_goal_volume.mesh = goal_volume_mesh
	flight_goal_volume.position.y = 1.4
	var volume_material := _material(Color(0.29, 0.92, 0.75, 0.045), 1.0)
	volume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	volume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flight_goal_volume.material_override = volume_material
	flight_goal_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flight_goal_volume)

	var beacon := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = simulation.goal_radius - 0.13
	torus.outer_radius = simulation.goal_radius
	beacon.mesh = torus
	beacon.position = Vector3(0.0, _ground_height(Vector2.ZERO) + 0.06, 0.0)
	beacon.material_override = _material(Color("78ffd8"), 0.45)
	add_child(beacon)
	beacon.visible = not environment_enabled
	if environment_enabled:
		goal_beacon = NightEnvironment.add_beacon(self, _ground_height(Vector2.ZERO))
		goal_beacon.visible = false # Comparison landmark for the headset navigation gate.
		goal_shrine = GoalShrine.new()
		goal_shrine.name = "GoalShrine"
		goal_shrine.configure(simulation.goal_radius, _ground_height(Vector2.ZERO), world_surface)
		add_child(goal_shrine)
		second_goal_shrine = GoalShrine.new()
		second_goal_shrine.name = "SecondGoalShrine"
		second_goal_shrine.position = Vector3(PVP_RIGHT_GOAL.x, 0.0, PVP_RIGHT_GOAL.y)
		second_goal_shrine.configure(simulation.goal_radius, _ground_height(PVP_RIGHT_GOAL), world_surface)
		second_goal_shrine.set_ring_color(Color("71aaff"))
		add_child(second_goal_shrine)
		second_goal_shrine.visible = false
		_pvp_beacons.append(NightEnvironment.add_pvp_beacon(self, PVP_LEFT_GOAL, _ground_height(PVP_LEFT_GOAL), Color("ffac55")))
		_pvp_beacons.append(NightEnvironment.add_pvp_beacon(self, PVP_RIGHT_GOAL, _ground_height(PVP_RIGHT_GOAL), Color("71aaff")))
		for pvp_beacon: Node3D in _pvp_beacons:
			pvp_beacon.visible = false

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
	flight_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.12
	marker_mesh.height = 0.24
	flight_marker.mesh = marker_mesh
	flight_marker.material_override = footprint_material
	add_child(flight_marker)

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
	top_camera.position = Vector3(0.0, float(terrain_size) if environment_enabled else 52.0, 0.0)
	top_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	top_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_camera.size = float(terrain_size) if environment_enabled else 62.0
	add_child(top_camera)
	spectator_camera = MushiSpectatorCamera.new()
	spectator_camera.name = "SpectatorCamera"
	add_child(spectator_camera)


func _add_miko_presentation() -> void:
	var avatar_scene := load("res://scenes/miko_avatar.tscn") as PackedScene
	if avatar_scene == null:
		push_warning("Miko avatar scene is unavailable; continuing without the scene character")
		return

	var presentation := Node3D.new()
	presentation.name = "MikoPresentation"
	var xz := Vector2(0.0, 2.0)
	presentation.position = Vector3(xz.x, _ground_height(xz), xz.y)
	# The imported VRM faces +Z. Turn Ukon toward the authored introduction.
	var avatar := avatar_scene.instantiate() as Node3D
	if avatar == null:
		push_warning("Miko avatar scene has no Node3D root")
		presentation.free()
		return
	avatar.name = "Miko"
	avatar.rotation.y = atan2(TUTORIAL_XZ.x - xz.x, TUTORIAL_XZ.y - xz.y)
	presentation.add_child(avatar)
	add_child(presentation)
	avatar.set_guide_idle(true)

func _build_player() -> void:
	player = DesktopPlayer.new()
	player.name = "DesktopPlayer"
	# RenIK foot rays use layer 1 for terrain. The player capsule only needs
	# a collision mask for movement, and should not be hit by foot rays or peers.
	player.collision_layer = 0
	player.world_surface = world_surface
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
	add_child(player)
	player.lamp_aim_motion.connect(_on_desktop_lamp_aim_motion)
	player.lamp_adjust_motion.connect(_on_desktop_lamp_adjust_motion)
	staff_tool = load("res://scripts/staff_tool.gd").new()
	staff_tool.name = "LanternStaff"
	add_child(staff_tool)
	staff_tool.set_world_surface(world_surface)
	lantern = staff_tool.lantern
	staff_tool.reset_to_pose(_desktop_staff_pose())


func _build_xr_player() -> void:
	xr_viewport = SubViewport.new()
	xr_viewport.name = "HeadsetViewport"
	xr_viewport.world_3d = get_world_3d()
	xr_viewport.size = Vector2i(1280, 720)
	xr_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	xr_viewport.msaa_3d = get_viewport().msaa_3d
	add_child(xr_viewport)
	var xr_scene: PackedScene = load("res://scenes/xr_player.tscn")
	xr_player = xr_scene.instantiate()
	xr_viewport.add_child(xr_player)
	_apply_xr_comfort()
	xr_player.set_world_surface(world_surface)
	xr_player.reset_pose(player.global_position)
	if not xr_player.xr_active:
		push_warning("OpenXR did not initialize; continuing in desktop mode")
		xr_viewport.queue_free()
		xr_player = null
		xr_viewport = null
		return
	xr_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	player.controls_enabled = false
	player.look_enabled = false
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.collision_layer = 0
	player.collision_mask = 0
	xr_player.current = true
	xr_player.camera.make_current()
	player.camera.global_transform = xr_player.camera.global_transform
	player.camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("MUSHI_XR_CAMERAS mirror=%s headset=%s origin_current=%s" % [get_viewport().get_camera_3d().get_path(), xr_viewport.get_camera_3d().get_path(), xr_player.is_current()])
	xr_player.recall_requested.connect(_on_xr_recall_requested)
	xr_player.recall_released.connect(_on_xr_recall_released)
	xr_player.menu_toggled.connect(_on_xr_menu_toggled)
	staff_tool.reset_to_pose(_xr_initial_staff_pose(), 1.0, false)
	xr_staff_interaction = load("res://scripts/xr_staff_interaction.gd").new()
	xr_staff_interaction.configure(staff_tool, xr_player)
	xr_staff_interaction.broom_test_override = _broom_test_enabled
	xr_staff_interaction.broom_unlocked = _broom_test_enabled or _broom_permanently_unlocked
	_ensure_local_avatar()


func _build_audio() -> void:
	grove_audio = load("res://scripts/grove_audio.gd").new()
	grove_audio.name = "GroveAudio"
	add_child(grove_audio)
	grove_audio.configure(simulation, world_surface, staff_tool, player, xr_player)
	grove_audio.set_listener_camera(xr_player.camera if xr_player != null and xr_player.xr_active else player.camera)


func _xr_initial_staff_pose() -> Transform3D:
	var start := Vector2(player.global_position.x + 0.65, player.global_position.z - 0.65)
	var ground := _ground_height(start)
	return Transform3D(Basis.IDENTITY, Vector3(start.x, ground + 0.79, start.y))


func _desktop_staff_pose() -> Transform3D:
	return player.staff_hold_transform(_desktop_aim, player.lamp_adjusting)


func _on_desktop_lamp_aim_motion(relative: Vector2) -> void:
	if xr_player != null and xr_player.xr_active or staff_tool == null \
			or not staff_tool.desktop_can_control_lantern():
		return
	_desktop_aim += Vector2(relative.x * 0.004, -relative.y * 0.004)
	_desktop_aim.x = clampf(_desktop_aim.x, -1.0, 1.0)
	_desktop_aim.y = clampf(_desktop_aim.y, -0.8, 0.8)


func _on_desktop_lamp_adjust_motion(relative: Vector2) -> void:
	if staff_tool != null and staff_tool.desktop_is_adjusting():
		staff_tool.update_desktop_adjust(relative, not _tutorial_locks_shutter(),
			tutorial_director == null or not tutorial_director.tutorial_enabled or tutorial_director.stage in [
				TutorialDirector.Stage.JAR_BLUE, TutorialDirector.Stage.JAR_ORANGE,
				TutorialDirector.Stage.GUIDE, TutorialDirector.Stage.GROUPS, TutorialDirector.Stage.FREE_PLAY])


func _end_desktop_lamp_adjust() -> void:
	if player != null:
		player.lamp_adjusting = false
	if staff_tool != null:
		staff_tool.end_desktop_adjust()


func _update_staff_pose(delta: float) -> void:
	if staff_tool == null:
		return
	if xr_player != null and xr_player.xr_active:
		staff_tool.clear_desktop_yaw_reference()
		if xr_staff_interaction != null:
			xr_staff_interaction.update(delta)
		staff_tool.set_flight_aim(xr_player.is_broom_flying(), -xr_player.camera.global_basis.z)
		if _xr_recall_owner != null and is_instance_valid(_xr_recall_owner):
			staff_tool.update_recall(_xr_recall_owner.global_transform, delta)
	else:
		if player.lamp_adjusting and (not staff_tool.desktop_can_control_lantern() or not player.look_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
			_end_desktop_lamp_adjust()
		player.staff_adjust_blend = move_toward(player.staff_adjust_blend,
			1.0 if player.lamp_adjusting else 0.0, delta * 5.0)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_desktop_aim = _desktop_aim.lerp(Vector2.ZERO, 1.0 - exp(-delta * 3.5))
		if _desktop_recall_held:
			staff_tool.clear_desktop_yaw_reference()
			staff_tool.update_recall(player.camera.global_transform, delta)
		elif staff_tool.placement == StaffTool.Placement.HELD:
			staff_tool.set_desktop_yaw_reference(player.camera.global_transform)
			staff_tool.set_held_world_pose(_desktop_staff_pose())
		else:
			staff_tool.clear_desktop_yaw_reference()
	staff_tool.advance(delta)


func _viewer_lantern_exposure() -> float:
	if staff_tool == null or staff_tool.placement == StaffTool.Placement.HELD:
		return 1.0
	var eye: Vector3 = _viewer_eye_position()
	return 1.0 - smoothstep(3.0, 14.0, eye.distance_to(lantern.global_position))


func _viewer_multiplayer_adaptation_target() -> float:
	var eye: Vector3 = _viewer_eye_position()
	var fresh_peers: Array[LightField] = []
	for peer_id: String in _peer_fields:
		if Time.get_ticks_msec() - int(_peer_last_input_msec.get(peer_id, 0)) > 500:
			continue
		fresh_peers.append(_peer_fields[peer_id] as LightField)
	return NightAdaptation.multiplayer_target(light_field, fresh_peers, eye)

func _viewer_eye_position() -> Vector3:
	if spectator_camera != null and spectator_camera.active:
		return spectator_camera.global_position
	return xr_player.camera.global_position if xr_player != null and xr_player.xr_active else player.camera.global_position


func _on_xr_recall_requested(controller: XRController3D) -> void:
	_xr_recall_owner = controller
	staff_tool.begin_recall(controller.global_transform)


func _on_xr_recall_released(controller: XRController3D) -> void:
	if _xr_recall_owner == controller:
		staff_tool.end_recall()
		_xr_recall_owner = null


func _skip_tutorial() -> void:
	if tutorial_director == null or not tutorial_director.tutorial_enabled:
		return
	tutorial_director.skip()
	if tutorial_guide != null:
		tutorial_guide.hide_for_skip()
	if environment_enabled and lantern.night_vision < 0.6:
		# Skip completes the adapted reveal immediately, then normal adaptation
		# resumes from that state on the next frame.
		lantern.reset_adaptation(0.6)
		NightEnvironment.set_night_vision(night_environment, lantern.night_vision)
		if terrain_environment != null:
			terrain_environment.set_night_vision(lantern.night_vision)
		if goal_shrine != null:
			goal_shrine.set_night_vision(lantern.night_vision)
	_sync_tutorial_movement_lock()


func _sync_tutorial_movement_lock() -> void:
	if tutorial_director == null:
		return
	var locked := tutorial_director.tutorial_enabled and tutorial_director.stage != TutorialDirector.Stage.FREE_PLAY
	var lock_changed := locked != _tutorial_movement_locked
	_tutorial_movement_locked = locked
	if player != null:
		player.movement_enabled = not locked and not (spectator_camera != null and spectator_camera.active)
	if lock_changed and xr_player != null and xr_player.xr_active:
		xr_player.set_interaction_lock(locked)


func _recenter_xr_tutorial_if_needed(delta: float) -> void:
	if xr_player == null or not xr_player.xr_active or tutorial_director == null or not tutorial_director.tutorial_enabled or tutorial_director.stage == TutorialDirector.Stage.FREE_PLAY:
		return
	var body := xr_player.get_node_or_null("PlayerBody") as XRToolsPlayerBody
	if body == null or not body.enabled:
		return
	_xr_recenter_cooldown = maxf(0.0, _xr_recenter_cooldown - delta)
	var head: Vector3 = xr_player.camera.global_position
	var offset: float = Vector2(head.x, head.z).distance_to(TUTORIAL_XZ)
	if _xr_recenter_cooldown > 0.0 or (_xr_tutorial_centered and offset <= 1.0):
		return
	var first_center: bool = not _xr_tutorial_centered
	var intro_forward := Vector3(TUTORIAL_LOOK_XZ.x - TUTORIAL_XZ.x, 0.0, TUTORIAL_LOOK_XZ.y - TUTORIAL_XZ.y).normalized()
	xr_player.snap_head_horizontal_to(TUTORIAL_XZ, intro_forward)
	if first_center and staff_tool != null and not staff_tool.is_picked_up():
		var forward: Vector3 = -xr_player.camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.RIGHT
		var staff_xz: Vector2 = TUTORIAL_XZ + Vector2(forward.x, forward.z) * 0.32
		var staff_ground: float = _ground_height(staff_xz)
		staff_tool.reset_to_pose(Transform3D(Basis.IDENTITY, Vector3(staff_xz.x, staff_ground + 0.9, staff_xz.y)), 1.0, false)
	_xr_tutorial_centered = true
	_xr_recenter_cooldown = 0.5


func _tutorial_locks_shutter() -> bool:
	return tutorial_director != null and tutorial_director.tutorial_enabled and tutorial_director.stage in [
		TutorialDirector.Stage.GUIDE,
		TutorialDirector.Stage.GROUPS,
	]


func _build_xr_tutorial_chain_cue() -> void:
	_tutorial_chain_label = Label3D.new()
	_tutorial_chain_label.name = "TutorialChainTooltip"
	_tutorial_chain_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tutorial_chain_label.font = UI_FONT
	_tutorial_chain_label.pixel_size = 0.00115
	_tutorial_chain_label.font_size = 27
	_tutorial_chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_chain_label.modulate = Color("ffdfa4")
	_tutorial_chain_label.outline_size = 10
	_tutorial_chain_label.outline_modulate = Color(0.015, 0.012, 0.01, 0.94)
	_tutorial_chain_label.no_depth_test = true
	_tutorial_chain_label.visible = false
	add_child(_tutorial_chain_label)


func _update_xr_tutorial_chain_cue() -> void:
	if _tutorial_chain_label == null:
		return
	var show: bool = tutorial_director != null and tutorial_director.tutorial_enabled
	var caption := ""
	if show:
		match tutorial_director.stage:
			TutorialDirector.Stage.JAR_ORANGE:
				caption = "Grip chain · twist to red" if xr_player != null and xr_player.xr_active else "Hold right mouse · drag right to red"
			TutorialDirector.Stage.JAR_BLUE:
				caption = "Grip chain · twist to blue" if xr_player != null and xr_player.xr_active else "Hold right mouse · drag left to blue"
			TutorialDirector.Stage.SHUTTER:
				caption = "Grip chain · pull down to close" if xr_player != null and xr_player.xr_active else "Hold right mouse · drag down to close"
	show = show and not caption.is_empty()
	_tutorial_chain_label.visible = show
	if not show:
		return
	var control: Vector3 = staff_tool.control_world_position()
	var viewer: Camera3D = xr_player.camera if xr_player != null and xr_player.xr_active else player.camera
	_tutorial_chain_label.global_position = control - viewer.global_basis.x * 0.42 + Vector3.UP * 0.13
	_tutorial_chain_label.text = caption


func _on_tutorial_goal_acceptance_changed(accepting: bool) -> void:
	if simulation is FlightSimulation:
		simulation.goal_accepting = accepting


func _on_tutorial_reveal_changed(amount: float) -> void:
	# Terrain, foliage and the river already share the lantern's head-center
	# adaptation value in _process. The director signal keeps this state boundary
	# explicit and lets the UI reflect the reveal stage without stepping physics.
	if tutorial_ui != null:
		tutorial_ui.update_reveal(amount)


func _on_tutorial_adaptation_started() -> void:
	lantern.set_shutter(0.0)
	lantern.reset_adaptation(0.0)


func _update_stream_visibility(delta: float) -> void:
	if terrain_environment == null or lantern == null:
		return
	if _game_mode == "two_shrines":
		_stream_visibility = 0.0
		terrain_environment.set_stream_visibility(0.0)
		return
	var tutorial_reveal_allowed := tutorial_director == null or not tutorial_director.tutorial_enabled
	if tutorial_director != null and tutorial_director.tutorial_enabled:
		tutorial_reveal_allowed = tutorial_director.reveal_amount > 0.0
	var target := TerrainEnvironment.stream_visibility_target(
		lantern.night_vision,
		lantern.shutter_openness,
		tutorial_reveal_allowed,
		float(_visual_tuning.stream_start),
		float(_visual_tuning.stream_end)
	)
	_stream_visibility = TerrainEnvironment.advance_stream_visibility(_stream_visibility, target, delta, float(_visual_tuning.stream_seconds))
	terrain_environment.set_stream_visibility(_stream_visibility)


func _set_visual_tuning(value: float, key: StringName) -> void:
	_visual_tuning[key] = value
	for pair: Array in [
		[&"stream_start", &"stream_end"], [&"star_start", &"star_end"],
		[&"milky_start", &"milky_end"], [&"foliage_start", &"foliage_end"],
		[&"clear_start", &"clear_end"], [&"clear_distance_start", &"clear_distance_end"],
	]:
		var companion: StringName = &""
		var adjusted := -1.0
		if key == pair[0] and value >= float(_visual_tuning[pair[1]]):
			companion = pair[1]
			adjusted = minf(100.0, value + 0.01)
		elif key == pair[1] and value <= float(_visual_tuning[pair[0]]):
			companion = pair[0]
			adjusted = maxf(0.0, value - 0.01)
		if companion != &"":
			_visual_tuning[companion] = adjusted
			var paired_slider := _visual_sliders.get(companion) as HSlider
			if paired_slider != null:
				paired_slider.set_value_no_signal(adjusted)
				var value_label := paired_slider.get_meta("value_label") as Label
				if value_label != null:
					value_label.text = "%.2f" % adjusted
	if lantern != null:
		lantern.set_adaptation_timing(float(_visual_tuning.dark_seconds), float(_visual_tuning.light_seconds))
	if night_environment != null:
		NightEnvironment.set_visual_tuning(night_environment, _visual_tuning)
	if terrain_environment != null:
		terrain_environment.set_visual_tuning(_visual_tuning)
	for mushroom_patch: MushroomPatch in mushroom_nodes:
		mushroom_patch.set_visual_tuning(_visual_tuning)
	if glyph_swarm != null:
		glyph_swarm.set_visual_tuning(_visual_tuning)


func _apply_visual_tuning() -> void:
	for key: Variant in _visual_tuning.keys():
		_set_visual_tuning(float(_visual_tuning[key]), StringName(key))


func _on_tutorial_guide_released() -> void:
	if tutorial_guide == null:
		return
	var ground := _ground_height(Vector2.ZERO)
	tutorial_guide.release_to(Vector3(0.0, ground + 0.8, 0.0), Vector3(0.0, ground - 1.5, 0.0))


func _on_tutorial_reward_unlocked() -> void:
	if panel != null and (xr_player == null or not xr_player.xr_active):
		panel.visible = debug_visible
	if tutorial_ui != null:
		tutorial_ui.show_reward_unlocked()
		tutorial_ui.set_sandbox_unlocked(true)


func _on_tutorial_broom_reward_unlocked() -> void:
	if tutorial_director == null or not tutorial_director.tutorial_enabled:
		return
	_broom_permanently_unlocked = true
	var file := FileAccess.open(BROOM_UNLOCK_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"unlocked": true}))
	_update_broom_access()
	if tutorial_ui != null:
		tutorial_ui.show_broom_unlocked()


func _on_tutorial_sandbox_visibility_changed(open: bool) -> void:
	if panel != null:
		panel.visible = open and _tutorial_sandbox_available()


func _tutorial_sandbox_available() -> bool:
	return _visual_tuning_override or tutorial_director == null or not tutorial_director.tutorial_enabled or tutorial_director.reward_is_unlocked

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud_label = Label.new()
	hud_label.add_theme_font_override("font", UI_FONT)
	hud_label.position = Vector2(24.0, 18.0)
	hud_label.add_theme_font_size_override("font_size", 22)
	hud_label.add_theme_color_override("font_color", Color("eaf6f4"))
	hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	hud_label.add_theme_constant_override("shadow_offset_x", 2)
	hud_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud_label)
	hud_label.visible = debug_visible

	help_label = Label.new()
	help_label.add_theme_font_override("font", UI_FONT)
	help_label.text = "WASD move · Space jump · mouse look · hold left mouse: wave staff · hold right mouse: drag filter/shutter\nG: drop/pick up · hold E: recall · K: skip intro · R: reset\nF1: debug · F2: quality · F3: audio · F6: spectator · Esc: menu\nSpectator: mouse look · WASD/Q/E fly · Shift fast · Ctrl slow · F7 sweep · F8/F9 eye adaptation · F10 auto"
	help_label.position = Vector2(24.0, 826.0)
	help_label.add_theme_font_size_override("font_size", 15)
	help_label.add_theme_color_override("font_color", Color("dceae8"))
	canvas.add_child(help_label)
	help_label.visible = debug_visible

	panel = PanelContainer.new()
	var font_theme := Theme.new()
	font_theme.default_font = UI_FONT
	panel.theme = font_theme
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
	title.text = "M1 · ENVIRONMENT SANDBOX" if environment_enabled else "M0f · DRIFT & FORMATIONS"
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
	flight_toggle = CheckBox.new()
	flight_toggle.text = "3D flight (off = ground fallback)"
	flight_toggle.button_pressed = flight_enabled
	flight_toggle.toggled.connect(_set_flight)
	stack.add_child(flight_toggle)
	flight_toggle.visible = not environment_enabled
	backend_picker = OptionButton.new()
	backend_picker.add_item("CPU reference", 0)
	backend_picker.add_item("GPU compute comparison", 1)
	backend_picker.select(1 if simulation_backend == "gpu" else 0)
	backend_picker.item_selected.connect(_set_backend)
	stack.add_child(backend_picker)
	population_rows.append(backend_picker)
	backend_picker.visible = not environment_enabled
	stack.add_child(HSeparator.new())
	strength_slider = _add_slider(stack, "Lantern influence", 0.25, 1.5, 1.0, 0.05)
	social_slider = _add_slider(stack, "Social force", 0.0, 1.8, 1.0, 0.05)
	wander_slider = _add_slider(stack, "Drift / wander", 0.0, 2.0, 1.0, 0.05)
	goal_slider = _add_slider(stack, "Goal pull (-) / resistance (+)", -2.0, 2.5, 0.8, 0.01)
	memory_slider = _add_slider(stack, "Memory recovery", 0.2, 2.0, 0.85, 0.05)
	goal_width_slider = _add_slider(stack, "Goal width (m)", 1.0, 7.0, 1.8, 0.1)
	var visual_title := Label.new()
	visual_title.text = "Visual audition · live"
	visual_title.add_theme_font_size_override("font_size", 15)
	visual_title.add_theme_color_override("font_color", Color("89e4cf"))
	stack.add_child(visual_title)
	_add_visual_group_label(stack, "Eye adaptation · light vein")
	_add_visual_slider(stack, "Dark adaptation (s)", 1.0, 18.0, 6.0, 0.1, &"dark_seconds")
	_add_visual_slider(stack, "Light adaptation (s)", 0.25, 8.0, 1.5, 0.05, &"light_seconds")
	_add_visual_slider(stack, "Light vein starts at NV", 0.0, 0.8, 0.48, 0.01, &"stream_start")
	_add_visual_slider(stack, "Light vein full at NV", 0.2, 1.0, 0.90, 0.01, &"stream_end")
	_add_visual_slider(stack, "Light vein fade-in (s)", 0.1, 6.0, 0.9, 0.1, &"stream_seconds")
	_add_visual_group_label(stack, "Sky · foliage · lantern")
	_add_visual_slider(stack, "Star detail starts", 0.0, 0.8, 0.14, 0.01, &"star_start")
	_add_visual_slider(stack, "Star detail completes", 0.2, 1.0, 0.89, 0.01, &"star_end")
	_add_visual_slider(stack, "Milky Way starts", 0.0, 0.9, 0.64, 0.01, &"milky_start")
	_add_visual_slider(stack, "Milky Way full", 0.2, 1.0, 0.96, 0.01, &"milky_end")
	_add_visual_slider(stack, "Foliage glow starts", 0.0, 0.95, 0.90, 0.01, &"foliage_start")
	_add_visual_slider(stack, "Foliage glow full", 0.1, 1.0, 0.99, 0.01, &"foliage_end")
	_add_visual_slider(stack, "Clear fade starts", 0.0, 0.8, 0.10, 0.01, &"clear_start")
	_add_visual_slider(stack, "Clear fade ends", 0.1, 1.0, 0.65, 0.01, &"clear_end")
	_add_visual_slider(stack, "Clear fade near (m)", 0.0, 60.0, 17.0, 1.0, &"clear_distance_start")
	_add_visual_slider(stack, "Clear fade far (m)", 5.0, 100.0, 52.0, 1.0, &"clear_distance_end")
	_add_visual_group_label(stack, "River mesh · path and surface")
	_add_visual_slider(stack, "River width scale", 0.6, 8.0, 2.5, 0.05, &"river_width")
	_add_visual_slider(stack, "River depth scale", 0.6, 3.5, 1.0, 0.05, &"river_depth")
	_add_visual_slider(stack, "Horizon gold flare", 0.0, 2.0, 0.25, 0.05, &"horizon_flare_strength")
	_add_visual_slider(stack, "Horizon flare spread", 0.2, 2.5, 1.0, 0.05, &"horizon_flare_spread")
	_add_visual_slider(stack, "Far light vein diffuse blend", 0.0, 1.0, 1.0, 0.05, &"far_scintillation_blend")
	_add_visual_slider(stack, "Path long wobble", 0.0, 5.0, 1.0, 0.05, &"path_long")
	_add_visual_slider(stack, "Path long frequency", 0.2, 6.0, 1.0, 0.05, &"path_long_frequency")
	_add_visual_slider(stack, "Path medium wobble", 0.0, 5.0, 1.0, 0.05, &"path_medium")
	_add_visual_slider(stack, "Path medium frequency", 0.2, 6.0, 1.0, 0.05, &"path_medium_frequency")
	_add_visual_slider(stack, "Long motion speed", 0.0, 5.0, 1.0, 0.05, &"path_long_speed")
	_add_visual_slider(stack, "Medium motion speed", 0.0, 5.0, 1.0, 0.05, &"path_medium_speed")
	_add_visual_slider(stack, "Surface bump", 0.0, 5.0, 1.0, 0.05, &"surface_bump")
	_add_visual_slider(stack, "Surface bump frequency", 0.2, 6.0, 1.0, 0.05, &"surface_bump_frequency")
	_add_visual_slider(stack, "Bump motion speed", 0.0, 5.0, 1.0, 0.05, &"surface_bump_speed")
	var energy_title := Label.new()
	energy_title.text = "Energy experiment · 90% response times"
	energy_title.add_theme_font_size_override("font_size", 13)
	stack.add_child(energy_title)
	energy_rows.append(energy_title)
	recovery_slider = _add_slider(stack, "Recover (s)", 3.0, 180.0, 30.0, 0.1)
	blue_sleep_slider = _add_slider(stack, "Blue sleep (s)", 1.0, 40.0, 10.0, 0.1)
	wake_slider = _add_slider(stack, "Red wake (s)", 0.1, 8.0, 1.0, 0.01)
	mushroom_pull_slider = _add_slider(stack, "Mushroom pull", 0.0, 4.0, 1.0, 0.1)
	scatter_slider = _add_slider(stack, "Arousal scatter", 0.0, 1.0, 1.0, 0.05)
	for slider: HSlider in [recovery_slider, blue_sleep_slider, wake_slider, mushroom_pull_slider, scatter_slider]:
		energy_rows.append(slider.get_parent())

	recovery_slider.value_changed.connect(_on_tuning_changed.bind(&"energy_recovery_rate"))
	blue_sleep_slider.value_changed.connect(_on_tuning_changed.bind(&"blue_energy_response"))
	wake_slider.value_changed.connect(_on_tuning_changed.bind(&"orange_energy_response"))
	scatter_slider.value_changed.connect(_on_tuning_changed.bind(&"arousal_scatter_strength"))
	mushroom_pull_slider.value_changed.connect(_on_tuning_changed.bind(&"mushroom_attraction_weight"))
	size_slider = _add_slider(stack, "Glyph size", 0.25, 2.0, 0.65, 0.05)
	height_slider = _add_slider(stack, "Max height (m)", 2.0, 8.0, 4.5, 0.1)
	billboard_toggle = CheckBox.new()
	billboard_toggle.text = "Camera-facing glyphs"
	stack.add_child(billboard_toggle)
	for control: Control in [size_slider.get_parent(), height_slider.get_parent(), billboard_toggle]:
		population_rows.append(control)
	size_slider.value_changed.connect(_on_tuning_changed.bind(&"glyph_render_scale"))
	height_slider.value_changed.connect(_on_tuning_changed.bind(&"flight_max_height"))
	billboard_toggle.toggled.connect(_on_billboard_changed)
	variation_slider = _add_slider(stack, "Trait variety", 0.0, 1.0, 0.65, 0.05)
	variation_slider.tooltip_text = "Changing variety resets the same seed to rebuild individual traits."
	contagion_slider = _add_slider(stack, "Neighbor arousal", 0.0, 1.0, 0.35, 0.05)
	formation_follow_slider = _add_slider(stack, "Formation follow", 0.0, 2.0, 0.0, 0.05)
	cluster_pressure_slider = _add_slider(stack, "Crowd splitting", 0.0, 2.0, 0.0, 0.05)
	cluster_target_slider = _add_slider(stack, "Crowd threshold", 1.0, 12.0, 6.0, 1.0)
	cluster_target_slider.tooltip_text = "Number of sampled nearby non-partners before outward pressure starts. Lower splits more; higher keeps larger clumps."
	for slider: HSlider in [formation_follow_slider, cluster_pressure_slider, cluster_target_slider]:
		population_rows.append(slider.get_parent())
	waking_toggle = CheckBox.new()
	waking_toggle.text = "Occasional waking from patches"
	stack.add_child(waking_toggle)
	population_rows.append(variation_slider.get_parent())
	population_rows.append(contagion_slider.get_parent())
	population_rows.append(waking_toggle)
	variation_slider.value_changed.connect(_on_variation_changed)
	contagion_slider.value_changed.connect(_on_tuning_changed.bind(&"arousal_contagion_strength"))
	waking_toggle.toggled.connect(_on_waking_changed)
	formation_follow_slider.value_changed.connect(_on_tuning_changed.bind(&"formation_follow_weight"))
	cluster_pressure_slider.value_changed.connect(_on_tuning_changed.bind(&"cluster_pressure_weight"))
	cluster_target_slider.value_changed.connect(_on_tuning_changed.bind(&"cluster_target_neighbors"))
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
	full.text = "24"
	full.pressed.connect(_set_fixture.bind(24))
	fixture_row.add_child(full)
	var larger := Button.new()
	larger.text = "64"
	larger.pressed.connect(_set_fixture.bind(64))
	fixture_row.add_child(larger)
	stack.add_child(fixture_row)
	var population_row := HBoxContainer.new()
	for count: int in [256, 512, 1024, 2048]:
		var choice := Button.new()
		choice.text = str(count)
		choice.pressed.connect(_set_fixture.bind(count))
		population_row.add_child(choice)
	stack.add_child(population_row)
	population_rows.append(population_row)
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


func _add_visual_slider(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, value: float, step: float, key: StringName) -> void:
	var slider := _add_slider(parent, label_text, minimum, maximum, value, step)
	_visual_sliders[key] = slider
	slider.value_changed.connect(_on_visual_tuning_changed.bind(key))


func _on_visual_tuning_changed(value: float, key: StringName) -> void:
	_set_visual_tuning(value, key)
	config_changed = true
	if not settings_history.is_empty():
		settings_history.append({"elapsed_seconds": elapsed, "settings": _current_settings()})


func _add_visual_group_label(parent: VBoxContainer, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("adbfbe"))
	parent.add_child(label)

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
	if glyph_swarm != null:
		glyph_swarm.queue_free()
		glyph_swarm = null
	if return_handoff != null:
		return_handoff.queue_free()
		return_handoff = null
	if flight_enabled:
		glyph_swarm = GlyphSwarm.new()
		glyph_swarm.glow_strength = 1.0 if environment_enabled else 0.72
		glyph_swarm.bloom_hdr_gain = 3.0 if environment_enabled else 1.0
		glyph_swarm.halo_strength = 0.8 if environment_enabled and bool(_quality_settings.get("bloom", true)) else 0.0
		add_child(glyph_swarm)
		glyph_swarm.configure(simulation.positions.size())
		glyph_swarm.set_visual_tuning(_visual_tuning)
		return_handoff = ReturnHandoffVisual.new()
		return_handoff.name = "ReturnHandoff"
		add_child(return_handoff)
		return_handoff.configure(simulation.positions.size())
		if environment_enabled:
			glyph_swarm.set_world_bounds(AABB(Vector3(-terrain_size * 0.5 - 2.0, -5.0, -terrain_size * 0.5 - 2.0), Vector3(terrain_size + 4.0, 90.0, terrain_size + 4.0)))
		return
	for index: int in simulation.positions.size():
		var agent := _create_agent_visual(index)
		agent_nodes.append(agent)
		add_child(agent)

func _create_agent_visual(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Mushi%02d" % index
	root.scale = Vector3.ONE * (0.45 if flight_enabled else 1.0)
	var colors: Array[Color] = [Color("a9eff0"), Color("cfb5ff"), Color("ffd39a")]
	var base_color: Color = colors[simulation.group_ids[index] % colors.size()]
	var body := MeshInstance3D.new()
	body.name = "Body"
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	if flight_enabled:
		sphere.radial_segments = 12
		sphere.rings = 6
	body.mesh = sphere
	body.scale = Vector3(1.0, 0.7, 1.45)
	body.material_override = _emissive_material(base_color, 0.3 if current_preset.energy_dynamics else 1.35)
	if current_preset.energy_dynamics:
		(body.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	root.add_child(body)
	for side: int in [-1, 1]:
		var wing := MeshInstance3D.new()
		wing.name = "WingL" if side < 0 else "WingR"
		var wing_mesh := SphereMesh.new()
		wing_mesh.radius = 0.13
		wing_mesh.height = 0.26
		if flight_enabled:
			wing_mesh.radial_segments = 8
			wing_mesh.rings = 4
			wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing.mesh = wing_mesh
		wing.position = Vector3(0.19 * side, 0.04, 0.02)
		wing.scale = Vector3(1.2, 0.16, 1.7)
		var wing_material := _material(Color(base_color, 0.72), 0.4)
		wing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if current_preset.energy_dynamics:
			wing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wing.material_override = wing_material
		root.add_child(wing)
	var eye := MeshInstance3D.new()
	eye.name = "FaceMark"
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.055
	eye_mesh.height = 0.11
	if flight_enabled:
		eye_mesh.radial_segments = 8
		eye_mesh.rings = 4
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 0.015, -0.31)
	eye.material_override = _emissive_material(Color("26313b"), 0.2)
	root.add_child(eye)
	return root

func _update_agent_visuals(alpha: float, delta: float) -> void:
	if flight_enabled:
		glyph_swarm.update_swarm(simulation, alpha, current_preset)
		if _game_mode != "two_shrines":
			return_handoff.update_handoffs(simulation, delta, simulation.goal_position, _ground_height(simulation.goal_position))
		if simulation is RemoteFlightSimulation:
			simulation.committed_this_step = PackedInt32Array()
		return
	for index: int in agent_nodes.size():
		var node := agent_nodes[index]
		if simulation.lifecycles[index] == FlockSimulation.Lifecycle.RELEASED:
			node.visible = false
			continue
		node.visible = true
		var phase: float = elapsed * (3.0 + simulation.arousals[index] * 3.0) + float(index) * 1.73
		var activity: float = smoothstep(0.0, current_preset.energy_neutral_target, simulation.arousals[index]) if current_preset.energy_dynamics else 1.0
		if flight_enabled:
			var point: Vector3 = simulation.previous_positions[index].lerp(simulation.positions[index], alpha)
			var velocity: Vector3 = simulation.velocities[index]
			node.position = point
			if velocity.length_squared() > 0.01:
				node.rotation.y = atan2(-velocity.x, -velocity.z)
				node.rotation.x = atan2(velocity.y, Vector2(velocity.x, velocity.z).length())
		else:
			var horizontal: Vector2 = simulation.previous_positions[index].lerp(simulation.positions[index], alpha)
			var height := FlockSimulation.BODY_HEIGHT + sin(phase) * 0.075 * activity
			if simulation.lifecycles[index] == FlockSimulation.Lifecycle.COMMITTED:
				height += simulation.lifecycle_times[index] * 0.7
			elif simulation.lifecycles[index] == FlockSimulation.Lifecycle.ASCENDING:
				height += simulation.lifecycle_times[index] * 2.5
			node.position = Vector3(horizontal.x, height, horizontal.y)
			var velocity: Vector2 = simulation.velocities[index]
			if velocity.length_squared() > 0.01:
				node.rotation.y = atan2(-velocity.x, -velocity.y)
		var flap := sin(phase * 2.4) * 0.55 * activity
		(node.get_node("WingL") as MeshInstance3D).rotation.z = -0.48 + flap
		(node.get_node("WingR") as MeshInstance3D).rotation.z = 0.48 - flap
		if current_preset.energy_dynamics:
			var color := EnergyVisual.color_for(simulation.arousals[index], current_preset.energy_neutral_target)
			var body_material := (node.get_node("Body") as MeshInstance3D).material_override as StandardMaterial3D
			body_material.albedo_color = color
			body_material.emission = color
			for wing_name: String in ["WingL", "WingR"]:
				var wing_material := (node.get_node(wing_name) as MeshInstance3D).material_override as StandardMaterial3D
				wing_material.albedo_color = Color(color, 0.72)

func _update_hud() -> void:
	for slider: HSlider in [strength_slider, social_slider, wander_slider, goal_slider, memory_slider, goal_width_slider, recovery_slider, blue_sleep_slider, wake_slider, mushroom_pull_slider, scatter_slider, variation_slider, contagion_slider, formation_follow_slider, cluster_pressure_slider, cluster_target_slider, size_slider, height_slider]:
		(slider.get_meta("value_label") as Label).text = "%.2f" % slider.value
	var shutter_text := "CLOSED" if lantern.shutter_openness <= 0.01 else "%d%% OPEN" % roundi(lantern.shutter_openness * 100.0)
	var pause_text := "  ·  PAUSED" if simulation_paused else ""
	var tuning_text := " · MODIFIED" if config_changed else ""
	hud_label.text = "%s  ·  %s\nReturned %d / %d  ·  Active %d\n%s%s%s" % [
		lantern.mode_label(), shutter_text, simulation.score, fixture_count,
		simulation.active_count(), current_preset.preset_name, tuning_text, pause_text
	]
	hud_label.text += "\n%s · %d Hz · %s %.2f ms · visuals %.2f ms · %d FPS" % [("3D glyphs · ceiling %.1f m" % current_preset.flight_max_height) if flight_enabled else "Ground fallback", roundi(1.0 / active_step), "CPU submit" if _active_backend == "gpu" else "CPU step", sim_step_ms, visual_update_ms, Engine.get_frames_per_second()]
	if _active_backend == "gpu":
		hud_label.text += "\nGPU flight · HUD state is delayed"
	if environment_enabled:
		hud_label.text += " · %dm basin" % terrain_size
	if not _backend_notice.is_empty():
		hud_label.text += "\n" + _backend_notice
	if debug_visible and not simulation.positions.is_empty():
		var i := mini(inspected_agent, simulation.positions.size() - 1)
		var force_note := "" if _active_backend == "gpu" else " · force %s" % str(simulation.accelerations[i])
		hud_label.text += "\nMarker = arrival target · tiles = ground slice\nID %d · e %.2f · light %.2f%s · %s" % [i, simulation.arousals[i], simulation.exposures[i], force_note, FlockSimulation.Lifecycle.keys()[simulation.lifecycles[i]]]
		if flight_enabled:
			hud_label.text += "\nHeight %.2f m · subtype %d" % [simulation.positions[i].y, simulation.trait_types[i]]
			if _active_backend == "cpu":
				hud_label.text += " · neighbors visited %d" % simulation.neighbor_visits
		if current_preset.energy_dynamics:
			hud_label.text += "\n%s · mushroom %.2f · blue → green → yellow → orange" % [EnergyVisual.state_name(simulation.arousals[i], current_preset.sleep_threshold), simulation.mushroom_exposures[i]]
	preset_label.text = "%s%s" % [current_preset.preset_name, " · modified" if config_changed else ""]

func _update_footprint() -> void:
	flight_marker.visible = debug_visible and flight_enabled
	footprint.visible = debug_visible and not flight_enabled
	if flight_enabled:
		var aim := light_field.source_position + light_field.source_direction * 3.0
		var target_ground := _ground_height(Vector2(aim.x, aim.z))
		flight_marker.position = light_field.flight_target(simulation.min_height + target_ground, simulation.max_height + target_ground)
	var target := light_field.ground_target(FlockSimulation.BODY_HEIGHT)
	footprint.position.x = target.x
	footprint.position.z = target.y
	footprint.position.y = _ground_height(target) + 0.045
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
		var longer_drift_globals := index >= 6
		strength_slider.set_value_no_signal(0.8 if longer_drift_globals else 1.0)
		social_slider.set_value_no_signal(1.4 if longer_drift_globals else 1.0)
		wander_slider.set_value_no_signal(0.8 if index >= 8 else (0.5 if longer_drift_globals else 1.0))
		goal_slider.set_value_no_signal(current_preset.goal_repulsion_strength)
		memory_slider.set_value_no_signal(current_preset.arousal_response)
		_sync_energy_controls()
	if restart:
		_reset_run(false)

func _reset_run(record_previous: bool) -> void:
	if _multiplayer_role == "client" and not _client_config_reset:
		return
	if record_previous and elapsed > 0.1:
		_write_run_record("reset")
	if not flight_enabled:
		fixture_count = mini(fixture_count, 64)
	_quality_settings["population"] = fixture_count
	if quality_menu != null:
		quality_menu.sync_population(fixture_count)
	for row: Control in population_rows:
		row.visible = flight_enabled
	backend_picker.visible = not environment_enabled
	active_step = 1.0 / 30.0 if flight_enabled and fixture_count >= 256 else FIXED_STEP
	current_seed = roundi(seed_box.value) if seed_box != null else current_seed
	var desired_backend := "remote" if _multiplayer_role == "client" else simulation_backend if flight_enabled else "cpu"
	if desired_backend == "gpu" and (DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() == "gl_compatibility"):
		desired_backend = "cpu"
		_backend_notice = "This renderer uses the CPU reference"
	if (flight_enabled and not simulation is FlightSimulation) or (not flight_enabled and not simulation is FlockSimulation) or desired_backend != _active_backend:
		var centers: PackedVector2Array = simulation.obstacle_centers
		var radii: PackedFloat32Array = simulation.obstacle_radii
		if simulation.has_method("dispose"):
			simulation.dispose()
		if desired_backend == "gpu":
			simulation = load("res://scripts/gpu_flight_simulation.gd").new()
		elif desired_backend == "remote":
			simulation = RemoteFlightSimulation.new()
		else:
			simulation = FlightSimulation.new() if flight_enabled else FlockSimulation.new()
		_active_backend = desired_backend
		simulation.obstacle_centers = centers
		simulation.obstacle_radii = radii
	simulation.world_limit = float(terrain_size) * 0.5 if environment_enabled else 27.0
	if environment_enabled and simulation.has_method("configure_environment"):
		simulation.configure_environment(world_surface)
	var active_patches := _patch_centers().duplicate()
	if _game_mode == "two_shrines":
		for center: Vector2 in PVP_CENTER_SPAWNS:
			active_patches.append(center)
	simulation.spawn_centers = PackedVector2Array(PVP_CENTER_SPAWNS) if _game_mode == "two_shrines" else active_patches
	simulation.mushroom_centers = active_patches.slice(0, 1) if fixture_count == 3 else active_patches.duplicate()
	if not current_preset.energy_dynamics:
		simulation.mushroom_centers = PackedVector2Array()
	var run_preset := current_preset.copy_preset()
	if _game_mode == "two_shrines":
		run_preset.spontaneous_waking_enabled = false
	if simulation is FlightSimulation:
		simulation.goal_mode_two = _game_mode == "two_shrines"
		simulation.goal_position = PVP_LEFT_GOAL if simulation.goal_mode_two else Vector2.ZERO
		simulation.second_goal_position = PVP_RIGHT_GOAL
	simulation.reset(fixture_count, current_seed, run_preset)
	_stream_visibility = 0.0
	if terrain_environment != null:
		terrain_environment.set_stream_visibility(0.0)
	if tutorial_director != null:
		var enable_tutorial := _game_mode != "two_shrines" and (_force_tutorial or (environment_enabled and not _skip_tutorial_requested))
		tutorial_director.begin_run(enable_tutorial, fixture_count)
		if simulation is FlightSimulation:
			simulation.goal_accepting = tutorial_director.goal_accepting
		_last_tutorial_score = -1
	_sync_tutorial_movement_lock()
	_last_shrine_score = -1
	_last_second_shrine_score = -1
	_configure_goal_shrines()
	if grove_audio != null:
		grove_audio.bind_simulation(simulation)
	_refresh_preset_visuals()
	_rebuild_agents()
	_tutorial_swarm_alpha = 0.0 if tutorial_director != null and tutorial_director.tutorial_enabled else 1.0
	if glyph_swarm != null:
		glyph_swarm.set_scene_opacity(_tutorial_swarm_alpha)
	accumulator = 0.0
	sim_step_ms = 0.0
	visual_update_ms = 0.0
	elapsed = 0.0
	_milestone_times.clear()
	mode_times = PackedFloat32Array([0.0, 0.0, 0.0])
	var authored_intro := tutorial_director != null and tutorial_director.tutorial_enabled and environment_enabled
	player.position = Vector3(TUTORIAL_XZ.x, 0.0, TUTORIAL_XZ.y) if authored_intro else Vector3(active_patches[0].x, 0.0, active_patches[0].y + 5.2) if fixture_count == 3 else Vector3(0.0, 0.0, 18.4)
	# The first two players need distinct starting positions: overlapping beams
	# made the other player's color and shutter look like local lamp state.
	if _multiplayer_role == "client" and fixture_count != 3:
		player.position.x += 3.5
	player.position.y = _ground_height(Vector2(player.position.x, player.position.z)) + (0.05 if environment_enabled else 0.0)
	player.reset_look()
	_xr_tutorial_centered = false
	_xr_recenter_cooldown = 0.0
	if authored_intro:
		player.look_at(Vector3(TUTORIAL_LOOK_XZ.x, player.position.y, TUTORIAL_LOOK_XZ.y), Vector3.UP)
		player.camera.rotation.x = -0.025
	if panel != null:
		if xr_player == null or not xr_player.xr_active:
			panel.visible = debug_visible and _tutorial_sandbox_available()
	if tutorial_ui != null and tutorial_director != null:
		tutorial_ui.set_sandbox_unlocked(_tutorial_sandbox_available())
	if tutorial_ui != null and tutorial_director != null:
		tutorial_ui.update_director(tutorial_director, xr_player != null and xr_player.xr_active)
	_desktop_aim = Vector2.ZERO
	_desktop_recall_held = false
	_end_desktop_lamp_adjust()
	if xr_player != null and xr_player.xr_active:
		if xr_staff_interaction != null:
			xr_staff_interaction.reset_for_run()
			_update_broom_access()
		_xr_recall_owner = null
		var intro_direction := TUTORIAL_LOOK_XZ - TUTORIAL_XZ
		xr_player.rotation.y = atan2(-intro_direction.x, -intro_direction.y) if authored_intro else 0.0
		xr_player.reset_pose(player.global_position)
		staff_tool.reset_to_pose(_xr_initial_staff_pose(), 1.0, false)
	else:
		staff_tool.reset_to_pose(_desktop_staff_pose())
	if tutorial_guide != null:
		if tutorial_director != null and tutorial_director.tutorial_enabled:
			var guide_camera: Camera3D = xr_player.camera if xr_player != null and xr_player.xr_active else player.camera
			var camera_origin := guide_camera.global_position
			var camera_forward := -guide_camera.global_basis.z
			var camera_left := -guide_camera.global_basis.x
			var guide_xz := Vector2(camera_origin.x + camera_forward.x * 1.65 + camera_left.x * 0.82, camera_origin.z + camera_forward.z * 1.65 + camera_left.z * 0.82)
			var guide_position := Vector3(guide_xz.x, _ground_height(guide_xz) + 0.1, guide_xz.y)
			tutorial_guide.reset_guide(guide_position)
		else:
			tutorial_guide.visible = false
	inspected_agent = 0
	settings_history = [{"elapsed_seconds": 0.0, "settings": _current_settings()}]
	run_id = "%s-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()]
	if run_notes != null:
		run_notes.clear()
	lantern.set_mode(LightField.Mode.CLEAR if current_preset.energy_dynamics else LightField.Mode.BLUE)
	lantern.shutter_openness = 1.0
	lantern.adjust_shutter(0.0)
	if environment_enabled:
		# A new run starts in clear light. The later tutorial can author its own
		# reveal, but must never inherit a fully adapted frame from the prior run.
		lantern.reset_adaptation(0.0)
		NightEnvironment.set_night_vision(night_environment, 0.0)
		terrain_environment.set_night_vision(0.0)
		goal_shrine.set_night_vision(0.0)
	if _multiplayer_role == "host" and not _joined_peers.is_empty():
		_multiplayer_epoch += 1
		_broadcast_multiplayer_config()

func _on_variation_changed(value: float) -> void:
	_write_run_record("population_variation_change")
	current_preset.population_variation = value
	config_changed = true
	_reset_run(false)

func _on_billboard_changed(enabled: bool) -> void:
	current_preset.glyph_billboard = enabled
	simulation.preset.glyph_billboard = enabled
	config_changed = true
	settings_history.append({"elapsed_seconds": elapsed, "settings": _current_settings()})

func _on_waking_changed(enabled: bool) -> void:
	current_preset.spontaneous_waking_enabled = enabled
	simulation.preset.spontaneous_waking_enabled = enabled
	config_changed = true
	settings_history.append({"elapsed_seconds": elapsed, "settings": _current_settings()})

func _set_backend(index: int) -> void:
	if environment_enabled:
		return
	_backend_notice = ""
	_write_run_record("backend_change")
	simulation_backend = "gpu" if index == 1 else "cpu"
	_reset_run(false)

func _set_flight(enabled: bool) -> void:
	if environment_enabled:
		return
	_write_run_record("simulation_mode_change")
	flight_enabled = enabled
	_reset_run(false)

func _set_fixture(count: int) -> void:
	if _multiplayer_role == "client":
		if quality_menu != null:
			quality_menu.sync_population(fixture_count)
		return
	_write_run_record("fixture_change")
	fixture_count = count
	if quality_menu != null:
		quality_menu.sync_population(count)
	if count > 64:
		flight_enabled = true
		flight_toggle.set_pressed_no_signal(true)
	_reset_run(false)

func _reset_from_seed_box() -> void:
	_reset_run(true)

func _on_tuning_changed(value: float, parameter: StringName = &"") -> void:
	if not parameter.is_empty():
		var coefficient: Variant = value
		if parameter in [&"energy_recovery_rate", &"blue_energy_response", &"orange_energy_response"]:
			coefficient = log(10.0) / maxf(value, 0.001)
		elif parameter == &"cluster_target_neighbors":
			coefficient = roundi(value)
		current_preset.set(parameter, coefficient)
		simulation.preset.set(parameter, coefficient)
	_refresh_preset_visuals()
	config_changed = true
	settings_history.append({"elapsed_seconds": elapsed, "settings": _current_settings()})

func _current_settings() -> Dictionary:
	return {"simulation_backend": _active_backend, "simulation_hz": roundi(1.0 / active_step), "flight_enabled": flight_enabled, "arena_layout": _arena_layout(), "world_limit": simulation.world_limit, "coefficients": current_preset.to_dict(), "lantern_strength": strength_slider.value,
		"social_multiplier": social_slider.value, "wander_multiplier": wander_slider.value, "environment_quality": _quality_settings, "visual_tuning": _visual_tuning.duplicate()}

func _toggle_top_down() -> void:
	if xr_player != null and xr_player.xr_active:
		return
	if spectator_camera != null and spectator_camera.active:
		_toggle_spectator()
	top_down = not top_down
	top_camera.current = top_down
	player.camera.current = not top_down
	player.look_enabled = not top_down
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if top_down else Input.MOUSE_MODE_CAPTURED

func _toggle_spectator() -> void:
	if xr_player != null and xr_player.xr_active or spectator_camera == null:
		return
	if spectator_camera.active:
		spectator_camera.leave()
		if _local_avatar != null:
			_local_avatar.set_local_first_person(true)
		_spectator_adaptation = -1.0
		player.movement_enabled = not _tutorial_movement_locked
		player.camera.make_current()
		player.look_enabled = not (friend_menu != null and friend_menu.is_open()) and not top_down
		grove_audio.set_listener_camera(player.camera)
		if _voice != null:
			_voice.set_listener_camera(player.camera)
	else:
		if top_down:
			_toggle_top_down()
		spectator_camera.enter_from(player.camera)
		if _local_avatar != null:
			_local_avatar.set_local_first_person(false)
		player.movement_enabled = false
		player.look_enabled = false
		grove_audio.set_listener_camera(spectator_camera)
		if _voice != null:
			_voice.set_listener_camera(spectator_camera)

func _save_named_preset() -> void:
	var name_value := save_name.text.strip_edges()
	if name_value.is_empty():
		return
	var data := _load_saved_data()
	data[name_value] = {
		"base_preset": current_preset.to_dict(),
		"seed": current_seed,
		"fixture_count": fixture_count,
		"flight_enabled": flight_enabled,
		"notes": run_notes.text.strip_edges() if run_notes != null else "",
		"lantern_strength": strength_slider.value,
		"social_multiplier": social_slider.value,
		"wander_multiplier": wander_slider.value,
		"visual_tuning": _visual_tuning.duplicate(),
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
	fixture_count = int(saved.get("fixture_count", 24))
	if fixture_count not in [3, 24, 64, 256, 512, 1024, 2048]:
		fixture_count = 24
	flight_enabled = true if environment_enabled else bool(saved.get("flight_enabled", false))
	flight_toggle.set_pressed_no_signal(flight_enabled)
	goal_slider.set_value_no_signal(current_preset.goal_repulsion_strength)
	memory_slider.set_value_no_signal(current_preset.arousal_response)
	_sync_energy_controls()
	preset_picker.select(-1)
	strength_slider.set_value_no_signal(float(saved.get("lantern_strength", 1.0)))
	social_slider.set_value_no_signal(float(saved.get("social_multiplier", 1.0)))
	wander_slider.set_value_no_signal(float(saved.get("wander_multiplier", 1.0)))
	_restore_visual_tuning(saved.get("visual_tuning", {}))
	config_changed = false
	_reset_run(false)
	saved_select.select(0)


func _restore_visual_tuning(saved_values: Variant) -> void:
	_visual_tuning = _visual_tuning_defaults.duplicate()
	if saved_values is Dictionary:
		for key: Variant in _visual_tuning.keys():
			var candidate: Variant = saved_values.get(key)
			if candidate is float or candidate is int:
				var slider := _visual_sliders.get(key) as HSlider
				_visual_tuning[key] = clampf(float(candidate), slider.min_value, slider.max_value) if slider != null else float(candidate)
	for key: Variant in _visual_tuning.keys():
		var slider := _visual_sliders.get(key) as HSlider
		if slider != null:
			slider.set_value_no_signal(float(_visual_tuning[key]))
			var value_label := slider.get_meta("value_label") as Label
			if value_label != null:
				value_label.text = "%.2f" % float(_visual_tuning[key])
	_apply_visual_tuning()

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


func _record_completion_milestones() -> void:
	if fixture_count <= 0 or simulation == null:
		return
	for percent: int in [25, 50, 75, 90, 100]:
		var key := str(percent)
		if not _milestone_times.has(key) and simulation.score * 100 >= fixture_count * percent:
			_milestone_times[key] = snappedf(elapsed, 0.01)


func _milestone_caption() -> String:
	var parts := PackedStringArray()
	for percent: int in [25, 50, 75, 90, 100]:
		var key := str(percent)
		if not _milestone_times.has(key):
			continue
		var seconds := int(float(_milestone_times[key]))
		parts.append("%d%% %02d:%02d" % [percent, seconds / 60, seconds % 60])
	return " · ".join(parts)

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
		"flight_enabled": flight_enabled,
		"arena_layout": _arena_layout(),
		"elapsed_seconds": snappedf(elapsed, 0.001),
		"game_mode": _game_mode,
		"completion_milestones_seconds": _milestone_times.duplicate(),
		"returns": simulation.score,
		"shrine_returns": [simulation.goal_scores[0], simulation.goal_scores[1]] if simulation is FlightSimulation else [simulation.score, 0],
		"returns_snapshot_delayed": _active_backend == "gpu",
		"state_snapshot_revision": simulation.snapshot_revision if _active_backend == "gpu" else -1,
		"mode_seconds": {
			"clear": snappedf(mode_times[LightField.Mode.CLEAR], 0.001),
			"blue": snappedf(mode_times[LightField.Mode.BLUE], 0.001),
			"orange": snappedf(mode_times[LightField.Mode.ORANGE], 0.001),
		},
		"config_modified": config_changed,
		"simulation_hz": roundi(1.0 / active_step),
		"simulation_backend": _active_backend,
		"step_timing_kind": "CPU submission" if _active_backend == "gpu" else "CPU simulation",
		"diagnostic_step_ema_ms": sim_step_ms,
		"diagnostic_visual_update_ema_ms": visual_update_ms,
		"coefficients": current_preset.to_dict(),
		"visual_tuning": _visual_tuning.duplicate(),
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
		if args[index] == "--xr":
			_want_xr = true
			index += 1
		elif args[index] == "--desktop":
			_want_xr = false
			index += 1
		elif args[index] == "--voice-unmuted":
			_voice_start_unmuted = true
			index += 1
		elif args[index] == "--broom-test":
			_broom_test_enabled = true
			index += 1
		elif args[index] == "--skip-tutorial":
			_skip_tutorial_requested = true
			_force_tutorial = false
			index += 1
		elif args[index] == "--host" or args[index] == "--join":
			_multiplayer_cli_mode = args[index].substr(2)
			_skip_tutorial_requested = true
			index += 1
		elif args[index] == "--tutorial":
			_force_tutorial = true
			_skip_tutorial_requested = false
			index += 1
		elif args[index] == "--visual-tuning":
			_visual_tuning_override = true
			index += 1
		elif args[index] == "--flat-lab":
			environment_enabled = false
			index += 1
		elif args[index] == "--terrain-size" and index + 1 < args.size():
			terrain_size = 256 if int(args[index + 1]) == 256 else 128
			index += 2
		elif args[index] == "--screenshot" and index + 1 < args.size():
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
		elif args[index] == "--simulation" and index + 1 < args.size():
			simulation_backend = "gpu" if args[index + 1] == "gpu" else "cpu"
			index += 2
		elif args[index] == "--ground":
			flight_enabled = false
			index += 1
		elif args[index] == "--saved-preset" and index + 1 < args.size():
			_saved_preset_arg = args[index + 1]
			index += 2
		elif args[index] == "--count" and index + 1 < args.size():
			fixture_count = int(args[index + 1])
			if fixture_count not in [3, 24, 64, 256, 512, 1024, 2048]:
				fixture_count = 24
			_count_override = fixture_count
			index += 2
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
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("staff_drop_pickup", KEY_G)
	_add_key_action("staff_recall", KEY_E)
	_add_key_action("reset_run", KEY_R)
	_add_key_action("tutorial_skip", KEY_K)
	_add_key_action("toggle_pause", KEY_P)
	_add_key_action("toggle_debug", KEY_F1)
	_add_key_action("inspect_next", KEY_I)
	_add_key_action("toggle_fullscreen", KEY_F11)
	_add_key_action("toggle_topdown", KEY_T)
	_add_key_action("toggle_spectator", KEY_F6)
	_add_key_action("spectator_sweep", KEY_F7)
	_add_key_action("spectator_darken", KEY_F8)
	_add_key_action("spectator_brighten", KEY_F9)
	_add_key_action("spectator_auto_adaptation", KEY_F10)
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
			point.y += _ground_height(Vector2(point.x, point.z))
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
				mesh.surface_add_vertex(Vector3(point.x + corner.x, _ground_height(Vector2(point.x + corner.x, point.z + corner.y)) + 0.065, point.z + corner.y))
	if begun:
		mesh.surface_end()

func _sync_energy_controls() -> void:
	size_slider.set_value_no_signal(current_preset.glyph_render_scale)
	height_slider.set_value_no_signal(current_preset.flight_max_height)
	billboard_toggle.set_pressed_no_signal(current_preset.glyph_billboard)
	variation_slider.set_value_no_signal(current_preset.population_variation)
	contagion_slider.set_value_no_signal(current_preset.arousal_contagion_strength)
	formation_follow_slider.set_value_no_signal(current_preset.formation_follow_weight)
	cluster_pressure_slider.set_value_no_signal(current_preset.cluster_pressure_weight)
	cluster_target_slider.set_value_no_signal(current_preset.cluster_target_neighbors)
	waking_toggle.set_pressed_no_signal(current_preset.spontaneous_waking_enabled)
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
	(flight_goal_volume.mesh as CylinderMesh).height = current_preset.flight_max_height
	flight_goal_volume.position.y = _ground_height(Vector2.ZERO) + current_preset.flight_max_height * 0.5
	flight_goal_volume.visible = debug_visible and flight_enabled
	if goal_halo == null:
		goal_halo = MeshInstance3D.new()
		goal_halo.position.y = _ground_height(Vector2.ZERO) + 0.045
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
	var visual_patches := _patch_centers().duplicate()
	if _game_mode == "two_shrines":
		for center: Vector2 in PVP_CENTER_SPAWNS:
			visual_patches.append(center)
	while mushroom_nodes.size() < visual_patches.size():
		var patch := MushroomPatch.new()
		var new_center: Vector2 = visual_patches[mushroom_nodes.size()]
		patch.position = Vector3(new_center.x, _ground_height(new_center), new_center.y)
		add_child(patch)
		mushroom_nodes.append(patch)
	for index: int in mushroom_nodes.size():
		var patch := mushroom_nodes[index]
		if index < visual_patches.size():
			var center: Vector2 = visual_patches[index]
			patch.position = Vector3(center.x, _ground_height(center), center.y)
		patch.visible = index < visual_patches.size() and current_preset.energy_dynamics and (fixture_count != 3 or index == 0)
		patch.set_radius(current_preset.mushroom_radius)
		patch.set_night_vision(lantern.night_vision if lantern != null else 0.0)
		patch.set_visual_tuning(_visual_tuning)
		patch.show_boundary(debug_visible)


func _patch_centers() -> PackedVector2Array:
	return world_surface.patch_centers if world_surface != null else PackedVector2Array(PATCH_CENTERS)


func _ground_height(point: Vector2) -> float:
	return float(world_surface.get_height_at(point)) if world_surface != null else 0.0


func _configure_goal_shrines() -> void:
	if goal_shrine == null:
		return
	var pvp := _game_mode == "two_shrines"
	var first: Vector2 = PVP_LEFT_GOAL if pvp else Vector2.ZERO
	goal_shrine.position = Vector3(first.x, 0.0, first.y)
	goal_shrine.configure(simulation.goal_radius, _ground_height(first), world_surface)
	goal_shrine.set_ring_color(Color("ffac55") if pvp else Color(1.0, 0.67, 0.27))
	if second_goal_shrine != null:
		second_goal_shrine.visible = pvp
		if pvp:
			second_goal_shrine.position = Vector3(PVP_RIGHT_GOAL.x, 0.0, PVP_RIGHT_GOAL.y)
			second_goal_shrine.configure(simulation.goal_radius, _ground_height(PVP_RIGHT_GOAL), world_surface)
	for pvp_beacon: Node3D in _pvp_beacons:
		pvp_beacon.visible = pvp


func _arena_layout() -> String:
	return "basin-%dm-v2" % terrain_size if environment_enabled else ARENA_LAYOUT


func _apply_quality(settings: Dictionary) -> void:
	_quality_settings = settings.duplicate()
	get_viewport().scaling_3d_scale = float(settings.get("render_scale", 1.0))
	if xr_viewport != null:
		xr_viewport.scaling_3d_scale = float(settings.get("render_scale", 1.0))
	var high_shadows := str(settings.get("shadows", "high")) == "high"
	if glyph_swarm != null:
		glyph_swarm.set_halo_strength(0.8 if environment_enabled and bool(settings.get("bloom", true)) else 0.0)
	if sun_light != null:
		sun_light.directional_shadow_max_distance = 65.0 if high_shadows else 28.0
	if lantern != null and lantern.spot != null:
		lantern.set_beam_shadows_enabled(high_shadows)
	if terrain_environment != null and terrain_environment.has_method("apply_quality"):
		terrain_environment.apply_quality(settings)
	if current_preset != null and elapsed > 0.0:
		settings_history.append({"elapsed_seconds": elapsed, "settings": _current_settings()})


func _on_quality_visibility(open: bool) -> void:
	if open and audio_mix_menu != null:
		audio_mix_menu.set_open(false)
	if open:
		_menu_was_paused = simulation_paused
		simulation_paused = true
	else:
		simulation_paused = _menu_was_paused
	if xr_player == null or not xr_player.xr_active:
		var menu_open := friend_menu != null and friend_menu.is_open()
		player.controls_enabled = not open and not menu_open
		player.look_enabled = not open and not menu_open and not top_down and not (spectator_camera != null and spectator_camera.active)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or menu_open or top_down else Input.MOUSE_MODE_CAPTURED


func _on_audio_mix_visibility(open: bool) -> void:
	if open and quality_menu != null:
		quality_menu.set_open(false)
	if open:
		_menu_was_paused = simulation_paused
		simulation_paused = true
	else:
		simulation_paused = _menu_was_paused
	if xr_player == null or not xr_player.xr_active:
		var menu_open := friend_menu != null and friend_menu.is_open()
		player.controls_enabled = not open and not menu_open
		player.look_enabled = not open and not menu_open and not top_down and not (spectator_camera != null and spectator_camera.active)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or menu_open or top_down else Input.MOUSE_MODE_CAPTURED


func _on_friend_new_game() -> void:
	if _multiplayer_role == "client":
		return
	_reset_run(true)
	if xr_player != null and xr_player.xr_active:
		xr_player.set_menu_open(false)


func _on_friend_quit() -> void:
	_write_run_record("quit")
	get_tree().quit()


func _on_friend_mode_requested(mode: String) -> void:
	if _multiplayer_role == "client":
		return
	_game_mode = "two_shrines" if mode == "two_shrines" else "classic"


func _on_friend_settings() -> void:
	if friend_menu != null and friend_menu.is_open():
		friend_menu.set_open(false)
	quality_menu.set_open(true)


func _on_friend_audio_settings() -> void:
	if friend_menu != null and friend_menu.is_open():
		friend_menu.set_open(false)
	audio_mix_menu.set_open(true)


func _on_friend_skip() -> void:
	_skip_tutorial()
	friend_menu.set_open(false)


func _on_friend_tuning() -> void:
	if not _tutorial_sandbox_available():
		return
	friend_menu.set_open(false)
	_desktop_tuning_open = true
	panel.visible = true
	player.controls_enabled = false
	player.look_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_friend_menu_visibility(open: bool) -> void:
	if xr_player != null and xr_player.xr_active:
		return
	if open:
		_friend_was_paused = simulation_paused
		if _multiplayer_role == "offline":
			simulation_paused = true
	else:
		if _multiplayer_role == "offline":
			simulation_paused = _friend_was_paused
	player.controls_enabled = not open
	player.look_enabled = not open and not top_down and not (spectator_camera != null and spectator_camera.active)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or top_down else Input.MOUSE_MODE_CAPTURED


func _on_xr_menu_toggled(open: bool) -> void:
	if open:
		_xr_menu_was_paused = simulation_paused
		if _multiplayer_role == "offline":
			simulation_paused = true
	else:
		if friend_menu != null:
			friend_menu.commit_avatar_fit()
		if _multiplayer_role == "offline":
			simulation_paused = _xr_menu_was_paused


func _init_multiplayer_network() -> void:
	_network_extension = load("res://multiplayer-native/mushi_multiplayer.gdextension")
	if not ClassDB.class_exists("MushiNetwork"):
		_network_status = "Multiplayer transport is not built"
		_show_multiplayer_status(false, false, _network_status)
		return
	_network = ClassDB.instantiate("MushiNetwork")
	add_child(_network)
	_network.session_ready.connect(_on_network_ready)
	_network.peer_joined.connect(_on_network_peer_joined)
	_network.peer_left.connect(_on_network_peer_left)
	_network.lantern_received.connect(_on_network_lantern)
	_network.snapshot_chunk_received.connect(_on_network_snapshot)
	_network.control_received.connect(_on_network_control)
	_network.network_error.connect(_on_network_error)
	_network.session_ended.connect(_on_network_session_ended)
	_voice = MushiVoice.new()
	_voice.name = "MultiplayerVoice"
	add_child(_voice)
	_voice.setup(_network, xr_player != null and xr_player.xr_active)
	_voice.set_input_gain_db(_voice_gain_db)
	_voice.set_gate_threshold_db(_voice_gate_db)
	_voice.set_receive_gain_db(_voice_receive_gain_db)
	if not _voice_input_device.is_empty():
		_voice.set_input_device(_voice_input_device)
	_voice.set_muted(not _voice_start_unmuted)
	_voice.set_listener_camera(xr_player.camera if xr_player != null and xr_player.xr_active else spectator_camera if spectator_camera != null and spectator_camera.active else player.camera)
	_refresh_voice_controls()
	_show_multiplayer_status(false, false, "Offline")


func _show_multiplayer_status(active: bool, hosting: bool, status: String) -> void:
	_network_status = status
	if friend_menu != null:
		friend_menu.set_shared_role("host" if active and hosting else "client" if active else "offline")
		friend_menu.set_multiplayer_status(status)
	print("MUSHI_NETWORK_STATUS: ", status)


func _on_multiplayer_host_requested(secret: String) -> void:
	_start_multiplayer(secret, true)


func _on_multiplayer_join_requested(secret: String) -> void:
	_start_multiplayer(secret, false)


func _update_broom_access() -> void:
	if xr_staff_interaction == null:
		return
	var enabled := _broom_test_enabled or _broom_permanently_unlocked or _multiplayer_role != "offline"
	xr_staff_interaction.broom_test_override = enabled
	xr_staff_interaction.broom_unlocked = enabled


func _ensure_local_avatar() -> void:
	if _local_avatar == null:
		_local_avatar = MushiMultiplayerAvatar.new()
		_local_avatar.name = "LocalPlayerAvatar"
		add_child(_local_avatar)
	_local_avatar.configure(_local_avatar_hue, true)
	_local_avatar.set_arm_reach_scale(_avatar_arm_reach)
	if xr_player != null and xr_player.xr_active:
		xr_player.set_controller_hand_meshes_visible(false)


func _update_local_avatar(delta: float) -> void:
	if _local_avatar == null:
		return
	var local_pose := _sample_local_avatar_pose()
	if xr_player == null or not xr_player.xr_active:
		var rest_pose := player.camera.global_transform * Transform3D(Basis.IDENTITY,
			Vector3(-0.28, -0.58, -0.34))
		var holding_rope: bool = player.lamp_adjusting and staff_tool != null \
			and staff_tool.placement == StaffTool.Placement.HELD
		var target_pose: Transform3D = local_pose.left if holding_rope else rest_pose
		if _desktop_left_hand_pose == Transform3D.IDENTITY:
			_desktop_left_hand_pose = rest_pose
		_desktop_left_hand_pose = _desktop_left_hand_pose.interpolate_with(target_pose,
			1.0 - exp(-delta * 6.0))
		_desktop_left_hand_blend = move_toward(_desktop_left_hand_blend,
			1.0 if holding_rope else 0.0, delta * 4.0)
		if _desktop_left_hand_blend > 0.01:
			local_pose.left = _desktop_left_hand_pose
			local_pose.tracking |= 1
	if xr_player != null and xr_player.xr_active:
		_local_avatar.set_player_eye_height(local_pose.eye_height)
	else:
		_local_avatar.set_eye_height(local_pose.eye_height)
	_local_avatar.apply_pose(local_pose.body, local_pose.head, local_pose.left,
		local_pose.right, local_pose.tracking, local_pose.velocity, delta)
	_local_avatar.apply_fingers(local_pose.fingers, local_pose.masks, local_pose.curls)
	_update_avatar_voice(_local_avatar, _voice.get_local_level() if _voice != null else 0.0,
		_voice.get_local_visemes() if _voice != null else PackedFloat32Array(), delta)


func _start_multiplayer(secret: String, hosting: bool) -> void:
	var room_code := secret.strip_edges().to_upper()
	if room_code.length() < 3:
		_network_status = "Use a room code of at least three characters"
		_show_multiplayer_status(false, false, _network_status)
		return
	if _network == null:
		_init_multiplayer_network()
	if _network == null:
		_network_status = "Multiplayer transport is not built"
		_show_multiplayer_status(false, false, _network_status)
		return
	_leave_multiplayer()
	_multiplayer_previous_skip = _skip_tutorial_requested
	_multiplayer_previous_force_tutorial = _force_tutorial
	_multiplayer_role = "host" if hosting else "client"
	_update_broom_access()
	_multiplayer_epoch = 1 if hosting else 0
	_multiplayer_sequence = 0
	_last_sent_snapshot_revision = -1
	_last_sent_score = -1
	_impaired_chunks.clear()
	_skip_tutorial_requested = true
	_force_tutorial = false
	_client_config_reset = not hosting
	_reset_run(false)
	_client_config_reset = false
	_local_avatar_hue = randf()
	staff_tool.set_identity_hue(_local_avatar_hue)
	_ensure_local_avatar()
	if spectator_camera != null and spectator_camera.active:
		_local_avatar.set_local_first_person(false)
	var presentation := get_node_or_null("MikoPresentation") as Node3D
	if presentation != null:
		presentation.visible = false
	simulation_paused = false
	if not _network.start(room_code, "Mushi player", hosting):
		_leave_multiplayer()
		_network_status = "Could not start private session"
	else:
		_network_status = "Hosting private game…" if hosting else "Joining private game…"
	_show_multiplayer_status(_multiplayer_role != "offline", hosting, _network_status)


func _leave_multiplayer() -> void:
	var was_active := _multiplayer_role != "offline"
	if _voice != null:
		_voice.stop_session()
	if _network != null:
		_network.stop()
	for peer_id: String in _peer_lanterns.keys():
		_remove_remote_staff_and_lantern(peer_id)
	for avatar: MushiMultiplayerAvatar in _peer_avatars.values():
		avatar.queue_free()
	_peer_avatars.clear()
	if _local_avatar != null:
		_local_avatar.set_local_first_person(spectator_camera == null or not spectator_camera.active)
	var presentation := get_node_or_null("MikoPresentation") as Node3D
	if presentation != null:
		presentation.visible = true
	_peer_fields.clear()
	_peer_last_input_msec.clear()
	_peer_last_sequence.clear()
	_joined_peers.clear()
	_impaired_chunks.clear()
	var was_client := _multiplayer_role == "client"
	_multiplayer_role = "offline"
	_update_broom_access()
	if was_active:
		_skip_tutorial_requested = _multiplayer_previous_skip
		_force_tutorial = _multiplayer_previous_force_tutorial
	_network_status = "Offline"
	if was_client:
		_reset_run(false)
	if friend_menu != null:
		_show_multiplayer_status(false, false, _network_status)


func _on_network_ready(_local_peer_id: String, hosting: bool) -> void:
	if _multiplayer_role == "offline":
		return
	if _voice != null:
		_voice.session_ready()
	_network_status = "Hosting private game" if hosting else "Connected; waiting for host state"
	_show_multiplayer_status(true, hosting, _network_status)
	if xr_player != null and xr_player.xr_active:
		xr_player.set_menu_open(false)
	else:
		friend_menu.set_open(false)


func _on_network_peer_joined(peer_id: String) -> void:
	if _multiplayer_role == "offline":
		return
	_joined_peers[peer_id] = true
	if _voice != null and _peer_avatars.has(peer_id):
		_voice.peer_joined(peer_id, (_peer_avatars[peer_id] as MushiMultiplayerAvatar).head_target)
	if _multiplayer_role == "host":
		_send_multiplayer_config(peer_id)
	_network_status = "Private game · %d players" % (_joined_peers.size() + 1)
	_show_multiplayer_status(true, _multiplayer_role == "host", _network_status)


func _on_network_peer_left(peer_id: String) -> void:
	if _multiplayer_role == "offline":
		return
	_joined_peers.erase(peer_id)
	_peer_fields.erase(peer_id)
	_peer_last_input_msec.erase(peer_id)
	_peer_last_sequence.erase(peer_id)
	if _voice != null:
		_voice.peer_left(peer_id)
	_remove_remote_staff_and_lantern(peer_id)
	if _peer_avatars.has(peer_id):
		(_peer_avatars[peer_id] as MushiMultiplayerAvatar).queue_free()
		_peer_avatars.erase(peer_id)
	if _multiplayer_role == "client":
		_leave_multiplayer()
		_show_multiplayer_status(false, false, "Host left; shared game ended")
		return
	_network_status = "Private game · %d players" % (_joined_peers.size() + 1)
	_show_multiplayer_status(true, true, _network_status)


func _remove_remote_staff_and_lantern(peer_id: String) -> void:
	if _peer_staffs.has(peer_id):
		(_peer_staffs[peer_id] as RemoteStaffVisual).queue_free()
		_peer_staffs.erase(peer_id)
	elif _peer_lanterns.has(peer_id):
		(_peer_lanterns[peer_id] as Lantern).queue_free()
	_peer_lanterns.erase(peer_id)


func _on_network_error(message: String) -> void:
	_network_status = "Network: " + message
	_show_multiplayer_status(_multiplayer_role != "offline", _multiplayer_role == "host", _network_status)


func _on_network_session_ended() -> void:
	if _multiplayer_role == "client":
		_leave_multiplayer()
		_show_multiplayer_status(false, false, "Host session ended")


func _update_multiplayer(delta: float) -> void:
	if _network == null or _multiplayer_role == "offline":
		return
	if not _impaired_chunks.is_empty():
		var now := Time.get_ticks_msec()
		var waiting: Array[Dictionary] = []
		for item: Dictionary in _impaired_chunks:
			if int(item.at) <= now:
				_apply_network_snapshot(item.bytes)
			else:
				waiting.append(item)
		_impaired_chunks = waiting
	_network_diag_clock += delta
	if _network_diag_clock >= 5.0:
		var seconds := _network_diag_clock
		_network_diag_clock = 0.0
		if _multiplayer_role == "host":
			var tick_lag := maxi(0, simulation.state_revision - simulation.snapshot_revision) if _active_backend == "gpu" else 0
			print("MUSHI_NET_DIAG role=host peers=%d chunks=%d payload_Mbps=%.3f readback_tick_lag=%d apply_ms=%.3f" % [
				_joined_peers.size(), _snapshot_chunks_sent,
				float(_snapshot_payload_bytes * _joined_peers.size()) * 8.0 / seconds / 1000000.0,
				tick_lag, simulation.snapshot_apply_ms if _active_backend == "gpu" else 0.0])
		else:
			print("MUSHI_NET_DIAG role=client chunks=%d received_agents=%d stale_500ms=%d dropped=%d score=%d" % [
				_snapshot_chunks_received, simulation.received_count if simulation is RemoteFlightSimulation else 0,
				simulation.stale_agents(0.5) if simulation is RemoteFlightSimulation else 0, _impair_dropped, simulation.score])
		_snapshot_payload_bytes = 0
		_snapshot_chunks_sent = 0
		_snapshot_chunks_received = 0
		_impair_dropped = 0
	_lantern_send_clock += delta
	if _lantern_send_clock >= 0.05:
		_lantern_send_clock = 0.0
		_multiplayer_sequence += 1
		var pose := _sample_local_avatar_pose()
		var packet := MultiplayerAvatarPose.append(MultiplayerLantern.encode(_multiplayer_sequence, light_field),
			pose.body, pose.head, pose.left, pose.right, pose.tracking, _local_avatar_hue,
			pose.velocity, pose.eye_height, pose.fingers, pose.masks, pose.curls, _avatar_arm_reach)
		packet = MultiplayerStaffPose.append(packet, staff_tool.global_transform, int(staff_tool.placement))
		_network.send_lantern(packet)
	if _voice != null:
		for peer_id: String in _peer_avatars:
			_update_avatar_voice(_peer_avatars[peer_id] as MushiMultiplayerAvatar,
				_voice.get_peer_level(peer_id), _voice.get_peer_visemes(peer_id), delta)
	for peer_id: String in _peer_staffs:
		(_peer_staffs[peer_id] as RemoteStaffVisual).advance_remote(delta)
	for peer_id: String in _peer_lanterns:
		var visual := _peer_lanterns[peer_id] as Lantern
		visual.reset_adaptation(lantern.night_vision)
	_limit_remote_lights()


func _update_avatar_voice(avatar: MushiMultiplayerAvatar, level: float,
		visemes: PackedFloat32Array, delta: float) -> void:
	if avatar == null or avatar.body == null:
		return
	avatar.body.call("set_voice_level", level)
	avatar.body.call("apply_voice_visemes", visemes, delta)


func _limit_remote_lights() -> void:
	if _peer_lanterns.is_empty():
		return
	var high_shadows := str(_quality_settings.get("shadows", "high")) == "high"
	# Give the local beam the positional shadow atlas while its shutter is open.
	# Remote beams remain lit, but their projector pattern requires a shadow slot.
	var local_shadow_priority := high_shadows and lantern != null and lantern.spot != null \
		and lantern.spot.visible and lantern.shutter_openness > 0.01
	var eye: Vector3 = _viewer_eye_position()
	var ranked: Array[Dictionary] = []
	for peer_id: String in _peer_lanterns:
		var visual := _peer_lanterns[peer_id] as Lantern
		ranked.append({"id": peer_id, "distance": eye.distance_squared_to(visual.global_position)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	for index: int in ranked.size():
		var visual := _peer_lanterns[ranked[index].id] as Lantern
		var beam_visible := index < _max_remote_spots and visual.shutter_openness > 0.01
		visual.set_beam_shadows_enabled(beam_visible and high_shadows and not local_shadow_priority)
		visual.spot.visible = beam_visible
		visual.housing_fill.visible = false


func _on_network_lantern(peer_id: String, bytes: PackedByteArray) -> void:
	if _multiplayer_role == "offline":
		return
	var sample := MultiplayerLantern.decode(bytes, terrain_size)
	if sample.is_empty() or int(sample.sequence) <= int(_peer_last_sequence.get(peer_id, -1)):
		return
	_peer_last_sequence[peer_id] = sample.sequence
	_peer_last_input_msec[peer_id] = Time.get_ticks_msec()
	var field: LightField = _peer_fields.get(peer_id)
	if field == null:
		field = LightField.new()
		field.world_surface = world_surface
		_peer_fields[peer_id] = field
	field.update_transform(sample.position, sample.direction)
	field.mode = sample.mode as LightField.Mode
	field.shutter_openness = sample.shutter
	field.half_angle_degrees = Lantern.BEHAVIOR_HALF_ANGLE_DEGREES
	field.range_m = 20.0 if field.mode == LightField.Mode.CLEAR else 10.5
	field.mode_strength = light_field.mode_strength
	var staff_pose := MultiplayerStaffPose.decode(bytes, terrain_size)
	if not staff_pose.is_empty() and not _peer_staffs.has(peer_id):
		_remove_remote_staff_and_lantern(peer_id)
		var staff_visual := RemoteStaffVisual.new()
		staff_visual.name = "PeerStaff"
		add_child(staff_visual)
		_peer_staffs[peer_id] = staff_visual
		_peer_lanterns[peer_id] = staff_visual.lantern
		print("MUSHI_PEER_STAFF: peer=%s" % peer_id)
	if not _peer_lanterns.has(peer_id):
		var visual := Lantern.new()
		visual.name = "PeerLantern"
		add_child(visual)
		visual.housing_fill.visible = false
		visual.set_beam_shadows_enabled(false)
		_peer_lanterns[peer_id] = visual
	var peer_visual := _peer_lanterns[peer_id] as Lantern
	if _peer_staffs.has(peer_id) and not staff_pose.is_empty():
		(_peer_staffs[peer_id] as RemoteStaffVisual).apply_remote_pose(
			staff_pose.pose, sample.position, sample.direction, staff_pose.placement)
	elif not _peer_staffs.has(peer_id):
		peer_visual.global_position = sample.position
		var up := Vector3.FORWARD if absf(sample.direction.y) > 0.98 else Vector3.UP
		peer_visual.global_basis = Basis.looking_at(sample.direction, up)
	if peer_visual.mode != field.mode:
		peer_visual.set_mode(field.mode)
	peer_visual.set_shutter(field.shutter_openness)
	peer_visual.housing_fill.visible = false
	var avatar_pose := MultiplayerAvatarPose.decode(bytes, terrain_size)
	if not avatar_pose.is_empty():
		if _peer_staffs.has(peer_id):
			(_peer_staffs[peer_id] as RemoteStaffVisual).set_identity_hue(avatar_pose.hue)
		if not _peer_avatars.has(peer_id):
			var avatar := MushiMultiplayerAvatar.new()
			avatar.name = "PeerAvatar"
			add_child(avatar)
			avatar.configure(avatar_pose.hue, false)
			_peer_avatars[peer_id] = avatar
			if _voice != null:
				_voice.peer_joined(peer_id, avatar.head_target)
			print("MUSHI_PEER_AVATAR: peer=%s hue=%.3f" % [peer_id, avatar_pose.hue])
		var remote_avatar := _peer_avatars[peer_id] as MushiMultiplayerAvatar
		remote_avatar.set_arm_reach_scale(avatar_pose.arm_reach)
		if avatar_pose.tracking & 4:
			remote_avatar.set_player_eye_height(avatar_pose.eye_height)
		else:
			remote_avatar.set_eye_height(avatar_pose.eye_height)
		remote_avatar.apply_pose(avatar_pose.body, avatar_pose.head, avatar_pose.left,
			avatar_pose.right, avatar_pose.tracking, avatar_pose.velocity, 0.05)
		remote_avatar.apply_fingers(avatar_pose.fingers, avatar_pose.masks, avatar_pose.curls)


func _sample_local_avatar_pose() -> Dictionary:
	if xr_player != null and xr_player.xr_active:
		var xr_body := xr_player.get_node("PlayerBody") as CharacterBody3D
		# Bit 4 marks the XR pose even if both hands temporarily lose tracking.
		var tracked := 4
		if xr_player.is_broom_flying():
			tracked |= MultiplayerAvatarPose.FLYING_FLAG
		var hands: Array[Transform3D] = []
		var fingers: Array[Quaternion] = []
		var masks := PackedInt32Array([0, 0])
		var curls := PackedFloat32Array()
		for index in range(2):
			var controller: XRController3D = xr_player.left_controller if index == 0 else xr_player.right_controller
			var tracker := XRServer.get_tracker("/user/hand_tracker/left" if index == 0 else "/user/hand_tracker/right") as XRHandTracker
			var hand := MushiHandPose.sample(tracker, controller.get_is_active())
			fingers.append_array(hand.rotations)
			masks[index] = hand.mask
			curls.append_array(MushiHandPose.curls(controller))
			var wrist := MushiHandPose.wrist(xr_player, controller, tracker, index == 0)
			hands.append(wrist.pose)
			if wrist.valid:
				tracked |= (1 << index) | (8 << index)
		var motion := xr_body.velocity
		motion.y = 0.0
		var measured_height := clampf(xr_player.camera.global_position.y - xr_body.global_position.y, 1.1, 2.1)
		return {"body": xr_body.global_transform, "head": xr_player.camera.global_transform,
			"left": hands[0], "right": hands[1],
			"tracking": tracked, "velocity": motion,
			"fingers": fingers, "masks": masks, "curls": curls,
			"eye_height": _avatar_eye_height_override if _avatar_eye_height_override > 0.0 else measured_height}
	var view := player.camera.global_transform
	var body := player.global_transform
	var left := Transform3D.IDENTITY
	var right := Transform3D.IDENTITY
	var tracked := 0
	if staff_tool != null and staff_tool.placement == StaffTool.Placement.HELD:
		right = Transform3D(staff_tool.global_basis,
			staff_tool.grip_world_position(staff_tool.grip_index) + staff_tool.global_basis * desktop_right_grip_offset)
		tracked = 2
		if player.lamp_adjusting:
			left = Transform3D(staff_tool.lantern.global_basis,
				staff_tool.control_world_position() + staff_tool.global_basis * desktop_left_control_offset)
			tracked = 3
	var motion := player.velocity
	motion.y = 0.0
	var empty_fingers: Array[Quaternion] = []
	var desktop_curls := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	if player.lamp_adjusting:
		for finger in range(5):
			desktop_curls[finger] = [0.65, 0.85, 0.9, 0.9, 0.8][finger]
	return {"body": body, "head": view, "left": left, "right": right,
		"tracking": tracked, "velocity": motion,
		"fingers": empty_fingers, "masks": PackedInt32Array([0, 0]),
		"curls": desktop_curls,
		# Saved XR standing height calibrates the device, never the fixed desktop camera.
		"eye_height": clampf(view.origin.y - body.origin.y, 1.1, 2.1)}


func _broadcast_multiplayer_state() -> void:
	if _network == null or _joined_peers.is_empty() or _active_backend != "gpu":
		return
	if simulation.snapshot_revision > _last_sent_snapshot_revision and simulation.snapshot_revision >= 0:
		_last_sent_snapshot_revision = simulation.snapshot_revision
		var chunks := MultiplayerSnapshot.encode_chunks(_multiplayer_epoch, simulation.snapshot_revision,
			simulation.state_revision, simulation, terrain_size)
		for chunk: PackedByteArray in chunks:
			_network.broadcast_snapshot_chunk(chunk)
			_snapshot_payload_bytes += chunk.size()
			_snapshot_chunks_sent += 1
	if simulation.score != _last_sent_score:
		_last_sent_score = simulation.score
		var score_message := JSON.stringify({"kind": "score", "epoch": _multiplayer_epoch, "score": simulation.score,
			"elapsed_seconds": elapsed, "milestones": _milestone_times,
			"goal_scores": [simulation.goal_scores[0], simulation.goal_scores[1]] if simulation is FlightSimulation else [simulation.score, 0]}).to_utf8_buffer()
		for peer_id: String in _joined_peers:
			_network.send_control(peer_id, score_message)


func _on_network_snapshot(_peer_id: String, bytes: PackedByteArray) -> void:
	if _multiplayer_role != "client" or not simulation is RemoteFlightSimulation:
		return
	if _impair_rng.randf() * 100.0 < _impair_loss_percent:
		_impair_dropped += 1
		return
	if _impair_jitter_ms > 0:
		if _impaired_chunks.size() >= 512:
			_impaired_chunks.pop_front()
			_impair_dropped += 1
		_impaired_chunks.append({"at": Time.get_ticks_msec() + _impair_rng.randi_range(0, _impair_jitter_ms), "bytes": bytes})
		return
	_apply_network_snapshot(bytes)


func _apply_network_snapshot(bytes: PackedByteArray) -> void:
	var chunk := MultiplayerSnapshot.decode_chunk(bytes)
	if chunk.is_empty() or int(chunk.get("epoch", -1)) != _multiplayer_epoch:
		return
	(simulation as RemoteFlightSimulation).apply_chunk(chunk)
	_snapshot_chunks_received += 1


func _send_multiplayer_config(peer_id: String) -> void:
	if _network == null:
		return
	var config := {"kind": "reset", "version": 1, "epoch": _multiplayer_epoch,
		"seed": current_seed, "count": fixture_count, "terrain_size": terrain_size,
		"preset": current_preset.to_dict(), "score": simulation.score,
		"elapsed_seconds": elapsed, "milestones": _milestone_times,
		"mode": _game_mode,
		"goal_scores": [simulation.goal_scores[0], simulation.goal_scores[1]] if simulation is FlightSimulation else [simulation.score, 0]}
	_network.send_control(peer_id, JSON.stringify(config).to_utf8_buffer())


func _broadcast_multiplayer_config() -> void:
	_last_sent_snapshot_revision = -1
	_last_sent_score = -1
	print("MUSHI_NET_RESET role=host epoch=%d count=%d peers=%d" % [_multiplayer_epoch, fixture_count, _joined_peers.size()])
	for peer_id: String in _joined_peers:
		_send_multiplayer_config(peer_id)


func _on_network_control(_peer_id: String, bytes: PackedByteArray) -> void:
	if _multiplayer_role != "client" or bytes.size() > 4096:
		return
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary:
		return
	if data.get("kind") == "reset":
		if int(data.get("version", 0)) != 1 or int(data.get("terrain_size", 0)) != terrain_size:
			_network_status = "Host map/version does not match this build"
			_show_multiplayer_status(true, false, _network_status)
			return
		var count := int(data.get("count", 0))
		if count not in [512, 1024]:
			return
		_multiplayer_epoch = int(data.get("epoch", 0))
		_game_mode = "two_shrines" if str(data.get("mode", "classic")) == "two_shrines" else "classic"
		_impaired_chunks.clear()
		fixture_count = count
		current_seed = int(data.get("seed", DEFAULT_SEED))
		seed_box.set_value_no_signal(current_seed)
		current_preset = HerdPreset.from_dict(data.get("preset", {}))
		_client_config_reset = true
		_reset_run(false)
		_client_config_reset = false
		simulation.score = int(data.get("score", 0))
		elapsed = maxf(0.0, float(data.get("elapsed_seconds", 0.0)))
		_apply_network_milestones(data)
		if simulation is FlightSimulation:
			_apply_network_goal_scores(data)
		print("MUSHI_NET_RESET role=client epoch=%d count=%d score=%d" % [_multiplayer_epoch, fixture_count, simulation.score])
	elif data.get("kind") == "score" and int(data.get("epoch", -1)) == _multiplayer_epoch:
		simulation.score = clampi(int(data.get("score", 0)), 0, fixture_count)
		elapsed = maxf(elapsed, float(data.get("elapsed_seconds", elapsed)))
		_apply_network_milestones(data)
		if simulation is FlightSimulation:
			_apply_network_goal_scores(data)


func _apply_network_goal_scores(data: Dictionary) -> void:
	var values: Variant = data.get("goal_scores", [])
	if values is Array and values.size() == 2:
		var first := clampi(int(values[0]), 0, fixture_count)
		var second := clampi(int(values[1]), 0, fixture_count - first)
		simulation.goal_scores = PackedInt32Array([first, second])
		simulation.score = first + second
	else:
		simulation.goal_scores = PackedInt32Array([simulation.score, 0])


func _apply_network_milestones(data: Dictionary) -> void:
	var values: Variant = data.get("milestones", {})
	if not values is Dictionary:
		return
	for percent: int in [25, 50, 75, 90, 100]:
		var key := str(percent)
		if values.has(key):
			_milestone_times[key] = maxf(0.0, float(values[key]))
