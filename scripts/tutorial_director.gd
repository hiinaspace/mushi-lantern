class_name TutorialDirector
extends RefCounted

## First-run flow controller. Simulation and presentation remain caller-owned.
signal goal_acceptance_changed(accepting: bool)
signal reveal_changed(amount: float)
signal adaptation_progress_changed(amount: float)
signal adaptation_started
signal reward_unlocked
signal near_complete_reached
signal guide_released

enum Stage { WELCOME, PICKUP, SHUTTER, ADAPTATION, REVEAL_WAIT, JAR_NEUTRAL, JAR_BLUE, JAR_ORANGE, GUIDE, GROUPS, FREE_PLAY }
enum GuideState { JARRED, DORMANT, WAKING, RELEASED }

const BLUE_MODE: int = LightField.Mode.BLUE
const ORANGE_MODE: int = LightField.Mode.ORANGE
const JAR_OBSERVATION_SECONDS := 5.0
const GUIDE_SECONDS := 5.0
const GROUPS_SECONDS := 5.0
const ADAPTATION_SECONDS := 8.0
const REVEAL_HOLD_SECONDS := 5.0
const DIALOGUE_PAUSE_SECONDS := 5.0
const REWARD_RATIO := 0.60
const NEAR_COMPLETE_RATIO := 0.80
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
var near_complete_milestone_reached: bool = false
var reveal_amount: float = 0.0
var adaptation_progress: float = 0.0
var _stage_elapsed := 0.0
var _orange_elapsed := 0.0
var _blue_elapsed := 0.0
var _guide_release_emitted := false
var _adaptation_page := 0
var _page_elapsed := 0.0


func begin_run(enabled: bool, run_total: int) -> void:
	tutorial_enabled = enabled
	total = maxi(0, run_total)
	score = 0
	progress_ratio = 0.0
	reward_is_unlocked = false
	near_complete_milestone_reached = false
	reveal_amount = 0.0
	adaptation_progress = 0.0
	_stage_elapsed = 0.0
	_orange_elapsed = 0.0
	_blue_elapsed = 0.0
	_guide_release_emitted = false
	_adaptation_page = 0
	_page_elapsed = 0.0
	guide_state = GuideState.JARRED if enabled else GuideState.RELEASED
	guide_alpha = 1.0 if enabled else 0.0
	stage = Stage.WELCOME if enabled else Stage.FREE_PLAY
	_set_goal_accepting(not enabled, true)
	_set_reveal(0.0, true)
	_set_adaptation_progress(0.0, true)
	_update_status()


func choose_tutorial(xr_active: bool = false) -> void:
	if tutorial_enabled and stage == Stage.WELCOME:
		_change_stage(Stage.PICKUP if xr_active else Stage.SHUTTER)
		_update_status()


func request_continue() -> void:
	if not tutorial_enabled or not can_continue():
		return
	match stage:
		Stage.ADAPTATION:
			if _adaptation_page < 2:
				_adaptation_page += 1
				_page_elapsed = 0.0
			elif _stage_elapsed >= ADAPTATION_SECONDS:
				_change_stage(Stage.REVEAL_WAIT)
		Stage.JAR_NEUTRAL:
			if _stage_elapsed >= JAR_OBSERVATION_SECONDS:
				_change_stage(Stage.JAR_BLUE)
		Stage.JAR_BLUE:
			if _blue_elapsed >= JAR_OBSERVATION_SECONDS:
				_change_stage(Stage.JAR_ORANGE)
		Stage.JAR_ORANGE:
			if _orange_elapsed >= JAR_OBSERVATION_SECONDS:
				release_guide()
				_change_stage(Stage.GUIDE)
		Stage.GUIDE:
			if _stage_elapsed >= GUIDE_SECONDS:
				_change_stage(Stage.GROUPS)
		Stage.GROUPS:
			if _stage_elapsed >= GROUPS_SECONDS:
				_change_stage(Stage.FREE_PLAY)
	_update_status()


func can_continue() -> bool:
	match stage:
		Stage.ADAPTATION:
			return _page_elapsed >= DIALOGUE_PAUSE_SECONDS and (_adaptation_page < 2 or _stage_elapsed >= ADAPTATION_SECONDS)
		Stage.JAR_NEUTRAL:
			return _stage_elapsed >= JAR_OBSERVATION_SECONDS
		Stage.JAR_BLUE:
			return _blue_elapsed >= JAR_OBSERVATION_SECONDS
		Stage.JAR_ORANGE:
			return _orange_elapsed >= JAR_OBSERVATION_SECONDS
		Stage.GUIDE:
			return _stage_elapsed >= GUIDE_SECONDS
		Stage.GROUPS:
			return _stage_elapsed >= GROUPS_SECONDS
	return false


func reveal_can_reopen() -> bool:
	return stage == Stage.REVEAL_WAIT and _stage_elapsed >= REVEAL_HOLD_SECONDS


func advance(delta: float, mode: int, shutter: float, _night_vision: float, staff_held: bool = false) -> void:
	if not tutorial_enabled or stage == Stage.FREE_PLAY:
		return
	var dt := maxf(0.0, delta)
	var shutter_open := shutter > ACTIVE_SHUTTER_THRESHOLD
	match stage:
		Stage.PICKUP:
			if staff_held:
				_change_stage(Stage.SHUTTER)
		Stage.SHUTTER:
			_stage_elapsed += dt
			if not shutter_open and _stage_elapsed >= DIALOGUE_PAUSE_SECONDS:
				_change_stage(Stage.ADAPTATION)
				adaptation_started.emit()
		Stage.ADAPTATION:
			_stage_elapsed += dt
			_page_elapsed += dt
			_set_adaptation_progress(_stage_elapsed / ADAPTATION_SECONDS)
			_set_reveal(adaptation_progress)
		Stage.REVEAL_WAIT:
			_stage_elapsed += dt
			if reveal_can_reopen() and shutter_open:
				_change_stage(Stage.JAR_NEUTRAL)
		Stage.JAR_NEUTRAL:
			_stage_elapsed += dt
		Stage.JAR_BLUE:
			if shutter_open and mode == BLUE_MODE:
				guide_state = GuideState.DORMANT
				_blue_elapsed += dt
		Stage.JAR_ORANGE:
			if shutter_open and mode == ORANGE_MODE:
				guide_state = GuideState.WAKING
				_orange_elapsed += dt
		Stage.GUIDE:
			_stage_elapsed += dt
		Stage.GROUPS:
			_stage_elapsed += dt
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
	if not near_complete_milestone_reached and total > 0 and progress_ratio >= NEAR_COMPLETE_RATIO:
		near_complete_milestone_reached = true
		near_complete_reached.emit()
	_update_status()


func ukon_nearby_line(tip_index: int = 0) -> String:
	if not tutorial_enabled or stage != Stage.FREE_PLAY:
		return ""
	var tip := posmod(tip_index, 3)
	if progress_ratio >= 1.0:
		return "Every mushi found its way home. What a wonderful migration! Your completion time is in the Play menu."
	if progress_ratio >= 0.95:
		return "Nearly everyone is home. The last few are optional; your completion time is in the Play menu."
	if progress_ratio >= 0.80:
		return "Most mushi have found their way back. Finding all is optional; your time is saved in Play."
	if progress_ratio >= 0.50:
		var mid_tips := [
			"Half the grove has come home. Blue gathers them; red can nudge them toward a shrine.",
			"Wonderful progress. Close the lantern shutter to spot strays along the light vein.",
			"So many have returned. You can keep wandering, or rest here a while."
		]
		return mid_tips[tip]
	if progress_ratio >= 0.25:
		var early_tips := [
			"Good work bringing them home. Blue draws mushi close; red can guide them toward a shrine.",
			"The light vein is still flowing beneath us. Close the shutter to help spot strays.",
			"The light vein bends beneath the earth. A few returns at a time is plenty."
		]
		return early_tips[tip]
	var opening_tips := [
		"Take your time; the mushi won't hurt you. Blue draws them close, and red can guide them home.",
		"With the lantern shutter closed, strays shine more clearly. The light vein is patient; there is no rush.",
		"Some mushi have strayed among the trees. Help a few find the shrine when you like."
	]
	return opening_tips[tip]


func _change_stage(next_stage: Stage) -> void:
	if stage == next_stage:
		return
	stage = next_stage
	_stage_elapsed = 0.0
	_page_elapsed = 0.0
	if stage == Stage.ADAPTATION:
		_adaptation_page = 0
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
		Stage.WELCOME:
			status_text = "Welcome to the grove. Shall I show you the lantern, or would you like to explore?"
		Stage.PICKUP:
			status_text = "First, grip the staff shaft beside you to pick up the lantern."
		Stage.SHUTTER:
			status_text = "First, pull the control rope down to close the shutter. Give your eyes a moment to settle into the dark."
		Stage.ADAPTATION:
			if _adaptation_page == 0:
				status_text = "This little light is a mushi. They belong to a hidden world of living things."
			elif _adaptation_page == 1:
				status_text = "光脈筋 (koumyakusuji) is the light vein beneath this grove. Some mushi stray from it and are left adrift."
			else:
				status_text = "You can see it through the earth, but the ground is solid. We'll guide the strays back through the shrine."
		Stage.REVEAL_WAIT:
			status_text = "Take a moment to watch, then open the shutter when ready. You're safe here: no jumpscares, and nothing will hurt you."
		Stage.JAR_NEUTRAL:
			status_text = "Watch the mushi in the glass. While it's green, it wanders on its own."
		Stage.JAR_BLUE:
			status_text = "Shine blue light into the glass. Blue quiets its energy and draws it close."
		Stage.JAR_ORANGE:
			status_text = "Now try red light. It wakes the mushi and nudges it away. I'll lift the glass so it can reach the shrine."
		Stage.GUIDE:
			status_text = "There it goes. The shrine leads it back into the light vein."
		Stage.GROUPS:
			status_text = "Blue gathers a group; red sends it drifting away. Guide a few toward the shrine. There is no rush."
		Stage.FREE_PLAY:
			status_text = "Free play · %d%% returned" % roundi(progress_ratio * 100.0)
