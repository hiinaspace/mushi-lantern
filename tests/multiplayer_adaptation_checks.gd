extends SceneTree

func _initialize() -> void:
	var eye := Vector3(0.0, 1.6, 5.0)
	var clear_a := _field(LightField.Mode.CLEAR, Vector3.ZERO)
	clear_a.mode_strength = 0.5
	var clear_single := NightAdaptation.multiplayer_target(clear_a, [], eye)
	assert(clear_single < 1.0 and clear_single > 0.5, "nearby clear source adapts from radial proximity outside beam cone")

	var clear_b := _field(LightField.Mode.CLEAR, Vector3(0.0, 1.6, 0.0))
	clear_b.mode_strength = 0.5
	var clear_pair: Array[LightField] = [clear_b]
	var clear_multiple := NightAdaptation.multiplayer_target(clear_a, clear_pair, eye)
	assert(clear_multiple < clear_single, "multiple clear sources combine additively")

	var blue := _field(LightField.Mode.BLUE, Vector3.ZERO)
	blue.mode_strength = 0.5
	var blue_target := NightAdaptation.multiplayer_target(blue, [], eye)
	var filtered: Array[LightField] = []
	for i in 7:
		var field := _field(LightField.Mode.ORANGE if i % 2 == 0 else LightField.Mode.BLUE, Vector3.ZERO)
		field.mode_strength = 0.5
		filtered.append(field)
	var many_filtered_target := NightAdaptation.multiplayer_target(null, filtered, eye)
	assert(is_equal_approx(blue_target, many_filtered_target), "seven filtered lanterns cap at one filtered source")
	blue.mode_strength = 1.0
	var in_colored_light := Vector3(0.0, 1.6, 7.5)
	assert(is_zero_approx(NightAdaptation.multiplayer_target(blue, [], in_colored_light)),
		"fully open colored peer light hides the stream throughout its nearby beam")
	blue.shutter_openness = 0.5
	assert(is_equal_approx(NightAdaptation.multiplayer_target(blue, [], in_colored_light), 0.5),
		"colored peer adaptation follows partial shutter")
	blue.shutter_openness = 0.0
	assert(is_equal_approx(NightAdaptation.multiplayer_target(blue, [], in_colored_light), 1.0),
		"closed colored peer light restores night vision")
	print("MULTIPLAYER_ADAPTATION_OK clear=%.3f two_clear=%.3f filtered=%.3f" % [clear_single, clear_multiple, blue_target])
	quit()

func _field(mode: LightField.Mode, position: Vector3) -> LightField:
	var field := LightField.new()
	field.mode = mode
	field.shutter_openness = 1.0
	field.source_position = position
	# Deliberately point away from the viewer to exercise radial, non-cone exposure.
	field.source_direction = Vector3.FORWARD
	return field
