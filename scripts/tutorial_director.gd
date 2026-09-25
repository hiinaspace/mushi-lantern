class_name TutorialDirector
extends RefCounted

## First-run flow controller. Simulation and presentation remain caller-owned.
signal goal_acceptance_changed(accepting: bool)
signal reveal_changed(amount: float)
signal adaptation_progress_changed(amount: float)
signal adaptation_started
signal reward_unlocked
signal guide_released

enum Stage { JAR_ORANGE, JAR_BLUE, GUIDE, GROUPS, SHUTTER, ADAPTATION, FREE_PLAY }
enum GuideState { JARRED, DORMANT, WAKING, RELEASED }

const BLUE_MODE: int = LightField.Mode.BLUE
const ORANGE_MODE: int = LightField.Mode.ORANGE
const BLUE_DEMO_SECONDS := 0.8
const ORANGE_DEMO_SECONDS := 0.8
const COLOR_OBSERVATION_SECONDS := 0.45
const GUIDE_SECONDS := 3.5
const GROUPS_SECONDS := 3.0
const ADAPTATION_SECONDS := 5.0
const REWARD_RATIO := 0.60
const ACTIVE_SHUTTER_THRESHOLD := 0.05

var stage: Stage = Stage.FREE_PLAY
var guide_state: GuideState = GuideState.RELEASED
var status_text: String = ""
var guide_alpha: float = 0.0
var progress_ratio: float = 0.0
var score: int = 0
var total: int = 0
var tutorial_enabled: bool = false
var goal_accepting: bool = true
var reward_is_unlocked: bool = false
var reveal_amount: float = 0.0
var adaptation_progress: float = 0.0
var _stage_elapsed := 0.0
var _orange_elapsed := 0.0
var _blue_elapsed := 0.0
var _orange_seen := false
var _blue_seen := false
var _shutter_open_seen := false
var _guide_release_emitted := false


func begin_run(enabled: bool, run_total: int) -> void:
	tutorial_enabled = enabled
	total = maxi(0, run_total)
	score = 0
	progress_ratio = 0.0
	reward_is_unlocked = false
	reveal_amount = 0.0
	adaptation_progress = 0.0
	_stage_elapsed = 0.0
	_orange_elapsed = 0.0
	_blue_elapsed = 0.0
	_orange_seen = false
	_blue_seen = false
	_shutter_open_seen = false
	_guide_release_emitted = false
	guide_state = GuideState.JARRED if enabled else GuideState.RELEASED
	guide_alpha = 1.0 if enabled else 0.0
	stage = Stage.JAR_ORANGE if enabled else Stage.FREE_PLAY
	_set_goal_accepting(not enabled, true)
	_set_reveal(0.0, true)
	_set_adaptation_progress(0.0, true)
	_update_status()


func advance(delta: float, mode: int, shutter: float, _night_vision: float) -> void:
	if not tutorial_enabled or stage == Stage.FREE_PLAY:
		return
	var dt := maxf(0.0, delta)
	var shutter_open := shutter > ACTIVE_SHUTTER_THRESHOLD
	match stage:
		Stage.JAR_ORANGE:
			if shutter_open and mode == ORANGE_MODE:
				guide_state = GuideState.WAKING
				_orange_elapsed += dt
				if _orange_elapsed >= ORANGE_DEMO_SECONDS + COLOR_OBSERVATION_SECONDS:
					_orange_seen = true
					_change_stage(Stage.JAR_BLUE)
			else:
				_orange_elapsed = 0.0
				guide_state = GuideState.JARRED
		Stage.JAR_BLUE:
			if _blue_seen:
				release_guide()
				_change_stage(Stage.GUIDE)
			elif shutter_open and mode == BLUE_MODE and _orange_seen:
				guide_state = GuideState.DORMANT
				_blue_elapsed += dt
				if _blue_elapsed >= BLUE_DEMO_SECONDS + COLOR_OBSERVATION_SECONDS:
					_blue_seen = true
			else:
				_blue_elapsed = 0.0
		Stage.GUIDE:
			_stage_elapsed += dt
			if _stage_elapsed >= GUIDE_SECONDS:
				_change_stage(Stage.GROUPS)
		Stage.GROUPS:
			_stage_elapsed += dt
			if _stage_elapsed >= GROUPS_SECONDS:
				_change_stage(Stage.SHUTTER)
		Stage.SHUTTER:
			if shutter_open:
				_shutter_open_seen = true
			elif _shutter_open_seen:
				_change_stage(Stage.ADAPTATION)
				adaptation_started.emit()
		Stage.ADAPTATION:
			_stage_elapsed += dt
			_set_adaptation_progress(_stage_elapsed / ADAPTATION_SECONDS)
			_set_reveal(adaptation_progress)
			if _stage_elapsed >= ADAPTATION_SECONDS:
				_change_stage(Stage.FREE_PLAY)
	_update_status()


## Both the normal demo and Skip share this idempotent release path.
func release_guide() -> void:
	if _guide_release_emitted:
		return
	_guide_release_emitted = true
	guide_state = GuideState.RELEASED
	guide_alpha = 0.0
	guide_released.emit()


func skip() -> void:
	if not tutorial_enabled:
		return
	release_guide()
	_change_stage(Stage.FREE_PLAY)
	_set_reveal(1.0)
	_set_adaptation_progress(1.0)
	_update_status()


func observe_score(new_score: int) -> void:
	score = maxi(0, new_score)
	progress_ratio = 0.0 if total <= 0 else clampf(float(score) / float(total), 0.0, 1.0)
	if not reward_is_unlocked and total > 0 and progress_ratio >= REWARD_RATIO:
		reward_is_unlocked = true
		reward_unlocked.emit()
	_update_status()


func _change_stage(next_stage: Stage) -> void:
	if stage == next_stage:
		return
	stage = next_stage
	_stage_elapsed = 0.0
	if stage == Stage.SHUTTER:
		_shutter_open_seen = false
	if stage == Stage.ADAPTATION:
		_set_adaptation_progress(0.0, true)
		_set_reveal(0.0, true)
	if stage == Stage.FREE_PLAY:
		_set_goal_accepting(true)
		_set_reveal(1.0)
		_set_adaptation_progress(1.0, true)


func _set_goal_accepting(value: bool, force_signal: bool = false) -> void:
	if goal_accepting == value and not force_signal:
		return
	goal_accepting = value
	goal_acceptance_changed.emit(value)


func _set_reveal(value: float, force_signal: bool = false) -> void:
	var next_value := clampf(value, 0.0, 1.0)
	if is_equal_approx(reveal_amount, next_value) and not force_signal:
		return
	reveal_amount = next_value
	reveal_changed.emit(reveal_amount)


func _set_adaptation_progress(value: float, force_signal: bool = false) -> void:
	var next_value := clampf(value, 0.0, 1.0)
	if is_equal_approx(adaptation_progress, next_value) and not force_signal:
		return
	adaptation_progress = next_value
	adaptation_progress_changed.emit(adaptation_progress)


func _update_status() -> void:
	match stage:
		Stage.JAR_ORANGE:
			status_text = "Open the shutter and hold orange light on the jarred mushi; switch to blue when it wakes."
		Stage.JAR_BLUE:
			status_text = "Hold blue light on the jar to calm the mushi."
		Stage.GUIDE:
			status_text = "With the jar open, watch the mushi fly into the goal."
		Stage.GROUPS:
			status_text = "Groups gather and stretch as they follow the lantern."
		Stage.SHUTTER:
			status_text = "Close the shutter to begin eye adaptation."
		Stage.ADAPTATION:
			status_text = "Keep the shutter closed. Your eyes adapt to the dark and reveal the mushi stream."
		Stage.FREE_PLAY:
			status_text = "Free play · %d%% returned" % roundi(progress_ratio * 100.0)
