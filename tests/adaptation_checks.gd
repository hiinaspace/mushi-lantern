extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model := NightAdaptation.new()
	_expect(is_equal_approx(model.target(LightField.Mode.CLEAR, 1.0), 0.0), "open clear adapts toward light")
	_expect(is_equal_approx(model.target(LightField.Mode.BLUE, 1.0), 0.75), "colored light preserves partial adaptation")
	_expect(is_equal_approx(model.target(LightField.Mode.ORANGE, 0.0), 1.0), "closed shutter adapts toward darkness")
	_expect(is_equal_approx(model.target(LightField.Mode.CLEAR, 1.0, 0.0), 1.0), "distant parked clear light permits dark adaptation")
	_expect(is_equal_approx(model.target(LightField.Mode.CLEAR, 1.0, 0.5), 0.5), "parked exposure blends smoothly with distance")
	var before := model.night_vision
	for i in 15:
		model.advance(0.1, LightField.Mode.CLEAR, 1.0)
		_expect(model.night_vision < before, "clear exposure decreases night vision monotonically")
		before = model.night_vision
	var one_step := NightAdaptation.new()
	one_step.advance(1.5, LightField.Mode.CLEAR, 1.0)
	_expect(absf(model.night_vision - one_step.night_vision) < 0.00001, "exponential adaptation is timestep independent")
	var after_clear := model.night_vision
	model.advance(6.0, LightField.Mode.BLUE, 0.0)
	_expect(model.night_vision > after_clear and model.night_vision < 1.0, "dark recovery is gradual")

	var lantern := Lantern.new()
	root.add_child(lantern)
	lantern.set_mode(LightField.Mode.CLEAR)
	lantern.shutter_openness = 1.0
	lantern.adjust_shutter(0.0)
	var flash := lantern.spot.light_energy
	_expect(lantern.spot.spot_angle == 65.0 and Lantern.BEHAVIOR_HALF_ANGLE_DEGREES == 55.0 and lantern.spot.spot_angle_attenuation == 0.25, "square projector preserves wide beam")
	_expect(lantern.spot.spot_range == 20.0 and flash > 10.0, "clear navigation beam begins brighter")
	lantern.advance_adaptation(9.0)
	_expect(lantern.spot.light_energy < flash and absf(lantern.spot.light_energy - 10.0) < 0.05, "clear beam settles after adaptation")
	lantern.set_mode(LightField.Mode.BLUE)
	_expect(lantern.spot.spot_range == 10.5, "colored beam has shorter range")
	lantern.advance_adaptation(6.0)
	_expect(lantern.night_vision > 0.0 and lantern.night_vision < 0.75, "colored mode recovers partial night vision")
	lantern.set_mode(LightField.Mode.ORANGE)
	_expect(lantern.spot.spot_range == 10.5, "orange beam keeps colored range")
	lantern.shutter_openness = 0.0
	lantern.adjust_shutter(0.0)
	_expect(is_zero_approx(lantern.spot.light_energy) and not lantern.spot.visible, "closed shutter has no spot emission")
	_expect((lantern.filter_mesh.material_override as ShaderMaterial).get_shader_parameter("glow_strength") > 0.0, "closed shutter retains a small face slit")
	lantern.advance_adaptation(6.0)
	_expect(lantern.night_vision > 0.75, "closed shutter restores dark adaptation")
	lantern.free()
	if failures == 0:
		print("ADAPTATION_OK")
	quit(0 if failures == 0 else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
