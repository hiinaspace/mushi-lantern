extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(is_equal_approx(TerrainEnvironment.stream_visibility_target(0.18, 0.0), 0.0), "stream begins at configured default threshold", failures)
	_check(is_equal_approx(TerrainEnvironment.stream_visibility_target(0.68, 0.0), 1.0), "stream reaches full reveal at configured default threshold", failures)
	var shifted := TerrainEnvironment.stream_visibility_target(0.5, 0.0, true, 0.4, 0.6)
	_check(is_equal_approx(shifted, 0.5), "stream threshold parameters update target immediately", failures)
	var fast := TerrainEnvironment.advance_stream_visibility(0.0, 1.0, 0.5, 0.5)
	_check(fast > 0.62 and fast < 0.64, "stream fade duration parameter is live", failures)

	var lantern := Lantern.new()
	root.add_child(lantern)
	lantern.set_adaptation_timing(0.5, 0.5)
	lantern.reset_adaptation(0.0)
	lantern.mode = LightField.Mode.CLEAR
	lantern.shutter_openness = 0.0
	lantern.advance_adaptation(0.5)
	_check(lantern.night_vision > 0.62 and lantern.night_vision < 0.64, "dark adaptation timing changes without reset", failures)
	lantern.shutter_openness = 1.0
	lantern.advance_adaptation(0.5)
	_check(lantern.night_vision < 0.24, "light adaptation timing changes without reset", failures)

	var river := RiverMeshPrototype.new()
	river.set_tuning({"path_long": 1.7, "path_medium_speed": 2.2, "surface_bump": 0.4})
	var river_material := river.material_override as ShaderMaterial
	_check(is_equal_approx(float(river_material.get_shader_parameter("path_long_scale")), 1.7), "river long path amplitude reaches material live", failures)
	_check(is_equal_approx(float(river_material.get_shader_parameter("path_medium_speed")), 2.2), "river path speed reaches material live", failures)
	_check(is_equal_approx(float(river_material.get_shader_parameter("surface_bump_scale")), 0.4), "river surface bump amplitude reaches material live", failures)
	river.free()

	var environment := Environment.new()
	NightEnvironment.configure(environment)
	NightEnvironment.set_visual_tuning(environment, {"star_start": 0.2, "star_end": 0.8, "milky_start": 0.7, "milky_end": 0.9})
	var sky_material := environment.sky.sky_material as ShaderMaterial
	_check(is_equal_approx(float(sky_material.get_shader_parameter("star_reveal_start")), 0.2), "star reveal threshold reaches sky shader", failures)
	_check(is_equal_approx(float(sky_material.get_shader_parameter("milky_way_reveal_start")), 0.7), "Milky Way threshold reaches sky shader", failures)

	var swarm := GlyphSwarm.new()
	root.add_child(swarm)
	swarm.set_visual_tuning({"clear_start": 0.2, "clear_end": 0.7, "clear_distance_start": 22.0, "clear_distance_end": 61.0})
	var glyph_material := swarm.get("_material") as ShaderMaterial
	_check(is_equal_approx(float(glyph_material.get_shader_parameter("clear_fade_distance_end")), 61.0), "clear fade distance reaches glyph material", failures)
	swarm.free()

	for failure in failures:
		push_error(failure)
	print("VISUAL_TUNING_CHECKS failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String, errors: Array[String]) -> void:
	if not condition:
		errors.append(message)
