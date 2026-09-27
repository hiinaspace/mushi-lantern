extends SceneTree

var failures: Array[String] = []
var release_count := 0
var reward_count := 0
var broom_reward_count := 0
var gate_events: Array[bool] = []
var adaptation_start_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var director := TutorialDirector.new()
	director.guide_released.connect(func() -> void: release_count += 1)
	director.reward_unlocked.connect(func() -> void: reward_count += 1)
	director.broom_reward_unlocked.connect(func() -> void: broom_reward_count += 1)
	director.goal_acceptance_changed.connect(func(value: bool) -> void: gate_events.append(value))
	director.adaptation_started.connect(func() -> void: adaptation_start_count += 1)
	director.begin_run(true, 100)
	_check(director.stage == TutorialDirector.Stage.WELCOME, "tutorial offers a choice", failures)
	_check(not director.goal_accepting and gate_events == [false], "goal starts closed", failures)
	director.advance(20.0, LightField.Mode.CLEAR, 1.0, 0.0)
	_check(director.stage == TutorialDirector.Stage.WELCOME, "choice waits for player", failures)
	director.choose_tutorial()
	_check(director.stage == TutorialDirector.Stage.SHUTTER, "choice starts shutter lesson", failures)
	director.advance(0.1, LightField.Mode.CLEAR, 1.0, 0.0)
	director.advance(0.1, LightField.Mode.CLEAR, 0.0, 0.0)
	_check(director.stage == TutorialDirector.Stage.ADAPTATION and adaptation_start_count == 1, "closing shutter starts reveal", failures)
	director.advance(TutorialDirector.ADAPTATION_SECONDS * 0.4, LightField.Mode.CLEAR, 0.0, 0.0)
	_check(director.status_text.contains("adrift"), "reveal mentions jam theme", failures)
	director.advance(TutorialDirector.ADAPTATION_SECONDS * 0.4, LightField.Mode.CLEAR, 0.0, 0.0)
	_check(director.status_text.contains("jumpscares"), "reveal reassures player", failures)
	director.advance(TutorialDirector.ADAPTATION_SECONDS * 0.2, LightField.Mode.CLEAR, 0.0, 0.0)
	_check(director.stage == TutorialDirector.Stage.JAR_BLUE and director.adaptation_progress == 1.0, "full reveal precedes blue demo", failures)
	director.advance(TutorialDirector.BLUE_DEMO_SECONDS + TutorialDirector.COLOR_OBSERVATION_SECONDS, LightField.Mode.BLUE, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.JAR_ORANGE and director.guide_state == TutorialDirector.GuideState.DORMANT, "blue calms guide before orange", failures)
	director.advance(TutorialDirector.ORANGE_DEMO_SECONDS + TutorialDirector.COLOR_OBSERVATION_SECONDS, LightField.Mode.ORANGE, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.GUIDE and release_count == 1, "orange releases guide once", failures)
	director.advance(TutorialDirector.GUIDE_SECONDS, LightField.Mode.ORANGE, 1.0, 1.0)
	director.advance(TutorialDirector.GROUPS_SECONDS, LightField.Mode.ORANGE, 1.0, 1.0)
	_check(director.stage == TutorialDirector.Stage.FREE_PLAY and director.goal_accepting, "lesson enters free play and opens goal", failures)
	_check(gate_events == [false, true], "goal gate emits only transitions", failures)
	_check(director.ukon_nearby_line().contains("hurt"), "free-play Ukon reassures", failures)
	director.observe_score(60)
	_check(director.reward_is_unlocked and reward_count == 1 and director.ukon_nearby_line().contains("Thank you"), "progress changes Ukon response", failures)
	director.observe_score(80)
	director.observe_score(90)
	_check(director.broom_reward_is_unlocked and broom_reward_count == 1 and director.ukon_nearby_line().contains("broom gesture"), "80 percent unlocks broom tip once", failures)
	director.begin_run(true, 20)
	director.skip()
	director.skip()
	_check(director.stage == TutorialDirector.Stage.FREE_PLAY and release_count == 2, "skip is idempotent", failures)
	director.begin_run(true, 20)
	director.choose_tutorial()
	director.advance(0.1, LightField.Mode.CLEAR, 0.0, 0.0)
	_check(director.stage == TutorialDirector.Stage.ADAPTATION, "already closed shutter starts adaptation after choice", failures)
	director.begin_run(false, 10)
	_check(director.stage == TutorialDirector.Stage.FREE_PLAY and director.goal_accepting, "disabled tutorial begins in free play", failures)
	for failure in failures:
		push_error(failure)
	print("TUTORIAL_DIRECTOR_CHECKS failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String, errors: Array[String]) -> void:
	if not condition:
		errors.append(message)
