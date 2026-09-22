extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var preset := HerdPreset.builtins()[5]
	var sim := FlightSimulation.new()
	sim.reset(2, 40721, preset)
	var swarm := GlyphSwarm.new()
	root.add_child(swarm)
	swarm.configure(2)
	sim.previous_positions[0] = Vector3(-1.0, 0.8, 0.0)
	sim.positions[0] = Vector3(1.0, 0.8, 0.0)
	sim.velocities[0] = Vector3.RIGHT
	sim.arousals[0] = 0.82
	sim.lifecycles[1] = FlightSimulation.Lifecycle.RELEASED
	swarm.update_swarm(sim, 0.25, preset)
	var texture := swarm._cpu_texture
	_check(texture != null and texture.get_size() == Vector2(2.0, 3.0), "compact 3-row texture created")
	_check(swarm._cpu_image.get_pixel(0, 0).r == -1.0 and swarm._cpu_image.get_pixel(0, 1).r == 1.0, "previous and current positions occupy separate rows")
	_check(is_equal_approx(swarm._cpu_image.get_pixel(0, 1).a, 0.82), "arousal is uploaded")
	_check(swarm._cpu_image.get_pixel(1, 1).a < 0.0 and not swarm.debug_instance_visible(1), "release is encoded in state texture")
	_check(swarm._cpu_image.get_pixel(0, 2).r > 0.99, "heading row follows velocity")
	_check(swarm._material.get_shader_parameter("interpolation_alpha") == 0.25, "display interpolation stays a shader uniform")
	var first_trait := swarm.debug_instance_custom_data(0)
	var first_texture := swarm._cpu_texture
	sim.positions[0] = Vector3(2.0, 0.8, 0.0)
	swarm.update_swarm(sim, 0.75, preset)
	_check(swarm._cpu_texture == first_texture and swarm._cpu_image.get_pixel(0, 1).r == 1.0, "unchanged simulation tick skips texture upload")
	_check(swarm.debug_instance_custom_data(0) == first_trait, "display update leaves static trait data alone")
	sim._energy_time += 1.0 / 30.0
	sim.velocities[0] = Vector3.ZERO
	swarm.update_swarm(sim, 0.5, preset)
	_check(swarm._cpu_image.get_pixel(0, 1).r == 2.0, "new simulation tick uploads state")
	_check(swarm._cpu_image.get_pixel(0, 2).r > 0.99, "rest keeps the last useful heading")
	swarm.queue_free()
	print("GLYPH_TEXTURE_CHECKS %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		printerr("GLYPH_TEXTURE_CHECKS FAIL: ", label)
		failures += 1
		return
	checks += 1
