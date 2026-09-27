class_name TutorialDirector
extends RefCounted

## First-run flow controller. Simulation and presentation remain caller-owned.
signal goal_acceptance_changed(accepting: bool)
signal reveal_changed(amount: float)
signal adaptation_progress_changed(amount: float)
signal adaptation_started
signal reward_unlocked
signal broom_reward_unlocked
signal guide_released

enum Stage { WELCOME, SHUTTER, ADAPTATION, JAR_BLUE, JAR_ORANGE, GUIDE, GROUPS, FREE_PLAY }
enum GuideState { JARRED, DORMANT, WAKING, RELEASED }

const BLUE_MODE: int = LightField.Mode.BLUE
const ORANGE_MODE: int = LightField.Mode.ORANGE
const BLUE_DEMO_SECONDS := 0.8
const ORANGE_DEMO_SECONDS := 0.8
const COLOR_OBSERVATION_SECONDS := 0.45
const GUIDE_SECONDS := 3.5
const GROUPS_SECONDS := 3.0
const ADAPTATION_SECONDS := 8.0
const REWARD_RATIO := 0.60
const BROOM_REWARD_RATIO := 0.80
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
var broom_reward_is_unlocked: bool = false
var reveal_amount: float = 0.0
var adaptation_progress: float = 0.0
var _stage_elapsed := 0.0
var _orange_elapsed := 0.0
var _blue_elapsed := 0.0
var _guide_release_emitted := false


func begin_run(enabled: bool, run_total: int) -> void:
	tutorial_enabled = enabled
	total = maxi(0, run_total)
	score = 0
	progress_ratio = 0.0
	reward_is_unlocked = false
	broom_reward_is_unlocked = false
	reveal_amount = 0.0
	adaptation_progress = 0.0
	_stage_elapsed = 0.0
	_orange_elapsed = 0.0
	_blue_elapsed = 0.0
	_guide_release_emitted = false
	guide_state = GuideState.JARRED if enabled else GuideState.RELEASED
	guide_alpha = 1.0 if enabled else 0.0
	stage = Stage.WELCOME if enabled else Stage.FREE_PLAY
	_set_goal_accepting(not enabled, true)
	_set_reveal(0.0, true)
	_set_adaptation_progress(0.0, true)
	_update_status()


func choose_tutorial() -> void:
	if tutorial_enabled and stage == Stage.WELCOME:
		_change_stage(Stage.SHUTTER)
		_update_status()


func advance(delta: float, mode: int, shutter: float, _night_vision: float) -> void:
	if not tutorial_enabled or stage == Stage.FREE_PLAY:
		return
	var dt := maxf(0.0, delta)
	var shutter_open := shutter > ACTIVE_SHUTTER_THRESHOLD
	match stage:
		Stage.SHUTTER:
			if not shutter_open:
				_change_stage(Stage.ADAPTATION)
				adaptation_started.emit()
		Stage.ADAPTATION:
			_stage_elapsed += dt
			_set_adaptation_progress(_stage_elapsed / ADAPTATION_SECONDS)
			_set_reveal(adaptation_progress)
			if _stage_elapsed >= ADAPTATION_SECONDS:
				_change_stage(Stage.JAR_BLUE)
		Stage.JAR_BLUE:
			if shutter_open and mode == BLUE_MODE:
				guide_state = GuideState.DORMANT
				_blue_elapsed += dt
				if _blue_elapsed >= BLUE_DEMO_SECONDS + COLOR_OBSERVATION_SECONDS:
					_change_stage(Stage.JAR_ORANGE)
			else:
				_blue_elapsed = 0.0
		Stage.JAR_ORANGE:
			if shutter_open and mode == ORANGE_MODE:
				guide_state = GuideState.WAKING
				_orange_elapsed += dt
				if _orange_elapsed >= ORANGE_DEMO_SECONDS + COLOR_OBSERVATION_SECONDS:
					release_guide()
					_change_stage(Stage.GUIDE)
			else:
				_orange_elapsed = 0.0
		Stage.GUIDE:
			_stage_elapsed += dt
			if _stage_elapsed >= GUIDE_SECONDS:
				_change_stage(Stage.GROUPS)
		Stage.GROUPS:
			_stage_elapsed += dt
			if _stage_elapsed >= GROUPS_SECONDS:
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
	if not broom_reward_is_unlocked and total > 0 and progress_ratio >= BROOM_REWARD_RATIO:
		broom_reward_is_unlocked = true
		broom_reward_unlocked.emit()
	_update_status()


func ukon_nearby_line() -> String:
	if stage != Stage.FREE_PLAY:
		return ""
	if broom_reward_is_unlocked:
		return "Wonderful work! Try the broom gesture to fly together, or keep helping the mushi find their way."
	if reward_is_unlocked:
		return "You brought so many home. Thank you. You can keep exploring, or invite a friend through Session."
	if score > 0:
		return "That one found the stream. Blue draws mushi close; orange can nudge them toward a shrine."
	return "Take your time. The mushi won't hurt you. If you'd like help, open Session for a private peer-to-peer room."


func _change_stage(next_stage: Stage) -> void:
	if stage == next_stage:
		return
	stage = next_stage
	_stage_elapsed = 0.0
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
		Stage.WELCOME:
			status_text = "Ukon: Thanks for helping at the grove. Would you like a quick lesson, or explore on your own?"
		Stage.SHUTTER:
			status_text = "Ukon: First, close the lantern's shutter. Let your eyes settle into the dark."
		Stage.ADAPTATION:
			if adaptation_progress < 0.35:
				status_text = "Ukon: This grove follows a 光脈筋 (koumyakusuji), a light vein the mushi navigate."
			elif adaptation_progress < 0.72:
				status_text = "Ukon: Some mushi are left adrift from the golden stream below. See it beneath the stars?"
			else:
				status_text = "Ukon: It's dark here, but you're safe. No jumpscares; the mushi and other creatures won't hurt you."
		Stage.JAR_BLUE:
			status_text = "Ukon: Shine blue light into this jar. Watch the green mushi settle and draw toward it."
		Stage.JAR_ORANGE:
			status_text = "Ukon: Now orange. I'll lift the lid; watch how the light nudges it to the shrine."
		Stage.GUIDE:
			status_text = "Ukon: There it goes. The shrine leads it back into the stream."
		Stage.GROUPS:
			status_text = "Ukon: Groups gather with blue and stretch away from orange. Try guiding a few home."
		Stage.FREE_PLAY:
			status_text = "Free play · %d%% returned" % roundi(progress_ratio * 100.0)
