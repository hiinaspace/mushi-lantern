extends SceneTree

var failures: Array[String] = []
var release_count := 0
var reward_count := 0
var gate_events: Array[bool] = []
var reveal_events: Array[float] = []
var adaptation_events: Array[float] = []
var adaptation_start_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var director := TutorialDirector.new()
	director.guide_released.connect(_on_guide_released)
	director.reward_unlocked.connect(_on_reward_unlocked)
	director.goal_acceptance_changed.connect(_on_gate_changed)
	director.reveal_changed.connect(_on_reveal_changed)
	director.adaptation_progress_changed.connect(_on_adaptation_changed)
	director.adaptation_started.connect(_on_adaptation_started)

	director.begin_run(true, 100)
	_check(director.stage == TutorialDirector.Stage.JAR_ORANGE, "enabled run starts at orange jar demo", failures)
	_check(not director.goal_accepting, "goal is closed during tutorial", failures)
	_check(gate_events == [false], "begin emits initial closed goal state", failures)
	director.advance(100.0, LightField.Mode.ORANGE, 0.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.JAR_ORANGE, "orange demo requires open shutter", failures)
	director.advance(TutorialDirector.ORANGE_DEMO_SECONDS, LightField.Mode.ORANGE, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.JAR_ORANGE, "orange demo includes a brief observation wait", failures)
	director.advance(TutorialDirector.COLOR_OBSERVATION_SECONDS, LightField.Mode.ORANGE, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.JAR_BLUE and director.guide_state == TutorialDirector.GuideState.WAKING, "sustained orange auto-advances while restless state persists", failures)
	director.advance(100.0, LightField.Mode.ORANGE, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.JAR_BLUE and director.guide_state == TutorialDirector.GuideState.WAKING, "orange keeps the mushi restless during blue stage", failures)
	director.advance(TutorialDirector.BLUE_DEMO_SECONDS, LightField.Mode.BLUE, 1.0, 1.0)
	_check(director.guide_state == TutorialDirector.GuideState.DORMANT and director.stage == TutorialDirector.Stage.JAR_BLUE, "blue exposure calms mushi before observation finishes", failures)
	director.advance(TutorialDirector.COLOR_OBSERVATION_SECONDS, LightField.Mode.BLUE, 1.0, 1.0)
	_check(director.guide_state == TutorialDirector.GuideState.DORMANT and director.stage == TutorialDirector.Stage.JAR_BLUE, "blue calms the mushi before release", failures)
	director.advance(0.01, LightField.Mode.BLUE, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.GUIDE and release_count == 1, "calmed guide releases into neutral green flight", failures)
	director.advance(TutorialDirector.GUIDE_SECONDS - 0.01, LightField.Mode.CLEAR, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.GUIDE, "guide flight remains visible for its duration", failures)
	director.advance(0.01, LightField.Mode.CLEAR, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.GROUPS, "guide flight automatically advances to groups tip", failures)
	director.advance(TutorialDirector.GROUPS_SECONDS - 0.01, LightField.Mode.CLEAR, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.GROUPS, "groups tip remains for a brief automatic timeout", failures)
	director.advance(0.01, LightField.Mode.CLEAR, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.SHUTTER, "groups tip automatically advances to shutter step", failures)
	director.advance(1.0, LightField.Mode.CLEAR, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.SHUTTER, "shutter stage waits while open", failures)
	director.advance(1.0, LightField.Mode.CLEAR, 0.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.ADAPTATION and adaptation_start_count == 1, "fresh shutter close immediately begins adaptation", failures)
	director.advance(TutorialDirector.ADAPTATION_SECONDS - 0.01, LightField.Mode.CLEAR, 0.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.ADAPTATION, "adaptation holds for the full five seconds", failures)
	director.advance(0.01, LightField.Mode.CLEAR, 0.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.FREE_PLAY, "adaptation countdown ends automatically even at high NV", failures)
	_check(is_equal_approx(director.adaptation_progress, 1.0), "adaptation progress reaches completion", failures)
	_check(director.goal_accepting, "free play opens goal", failures)
	_check(gate_events == [false, true], "goal gate emits each transition once", failures)
	_check(reveal_events.size() >= 3, "reveal emits initial, adaptation and completed values", failures)

	var rounding_director := TutorialDirector.new()
	rounding_director.begin_run(true, 0)
	rounding_director.stage = TutorialDirector.Stage.ADAPTATION
	rounding_director._stage_elapsed = TutorialDirector.ADAPTATION_SECONDS - 0.001
	rounding_director.adaptation_progress = 0.999999
	rounding_director.advance(0.001, LightField.Mode.CLEAR, 0.0, 1.0)
	_check(rounding_director.stage == TutorialDirector.Stage.FREE_PLAY, "adaptation completes from elapsed time when progress update is approximately equal to one", failures)
	_check(rounding_director.adaptation_progress == 1.0, "free play forces adaptation progress to exactly one", failures)

	director.observe_score(59)
	_check(not director.reward_is_unlocked and reward_count == 0, "reward stays locked before 60 percent", failures)
	director.observe_score(60)
	director.observe_score(75)
	_check(director.reward_is_unlocked and reward_count == 1, "reward unlocks once at 60 percent", failures)
	director.observe_score(1000)
	_check(is_equal_approx(director.progress_ratio, 1.0), "progress clamps at total", failures)

	director.begin_run(true, 20)
	_check(director.stage == TutorialDirector.Stage.JAR_ORANGE, "new enabled run resets stage", failures)
	_check(director.score == 0 and is_zero_approx(director.progress_ratio), "new run resets score progress", failures)
	_check(not director.reward_is_unlocked, "new run resets reward state", failures)
	_check(is_zero_approx(director.reveal_amount) and is_zero_approx(director.adaptation_progress), "new run resets reveal and adaptation", failures)
	director.skip()
	director.skip()
	_check(director.stage == TutorialDirector.Stage.FREE_PLAY, "skip completes from any stage", failures)
	_check(release_count == 2, "skip shares idempotent guide release", failures)
	_check(director.goal_accepting and is_equal_approx(director.reveal_amount, 1.0), "skip opens goal and completes reveal", failures)

	director.begin_run(false, 10)
	_check(director.stage == TutorialDirector.Stage.FREE_PLAY and director.goal_accepting, "disabled run starts in free play", failures)
	director.skip()
	_check(release_count == 2, "skip on disabled run does not release again", failures)
	director.observe_score(6)
	_check(director.reward_is_unlocked and reward_count == 2, "milestone can unlock in disabled tutorial path", failures)

	for failure in failures:
		push_error(failure)
	print("TUTORIAL_DIRECTOR_CHECKS failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String, errors: Array[String]) -> void:
	if not condition:
		errors.append(message)


func _on_guide_released() -> void:
	release_count += 1


func _on_reward_unlocked() -> void:
	reward_count += 1


func _on_gate_changed(accepting: bool) -> void:
	gate_events.append(accepting)


func _on_reveal_changed(value: float) -> void:
	reveal_events.append(value)


func _on_adaptation_changed(value: float) -> void:
	adaptation_events.append(value)


func _on_adaptation_started() -> void:
	adaptation_start_count += 1
