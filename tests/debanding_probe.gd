extends SceneTree

# Rendered Mobile comparison of the engine's built-in debanding path.
# XDG_DATA_HOME=/tmp/mushi-deband-probe godot --path . --rendering-driver vulkan --rendering-method mobile --script tests/debanding_probe.gd
# Captures and prints pixel differences; it does not use the game scene.

const CAPTURE_DIR := "res://artifacts/m1-night/debanding-probe"


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Debanding probe needs a rendered Vulkan Mobile window")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var startup_debanding: bool = root.use_debanding
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.current = true
	world.add_child(camera)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.0
	environment_node.environment = environment
	world.add_child(environment_node)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	quad.position.z = -1.0
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_test_disabled; void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); } void fragment() { float x = SCREEN_UV.x; ALBEDO = vec3(x < 0.2 ? 0.0 : 0.045 + (x - 0.2) * 0.040); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	quad.material_override = material
	world.add_child(quad)
	RenderingServer.material_set_use_debanding(false)
	root.use_debanding = false
	var off := await _capture("off.png")
	RenderingServer.material_set_use_debanding(true)
	root.use_debanding = true
	var on := await _capture("on.png")
	var changed := 0
	var total := 0
	var black_max_off := 0.0
	var black_max_on := 0.0
	var off_levels: Dictionary = {}
	var on_levels: Dictionary = {}
	for y: int in range(50, 310):
		for x: int in range(20, 620):
			var a := off.get_pixel(x, y).r
			var b := on.get_pixel(x, y).r
			if x < 100:
				black_max_off = maxf(black_max_off, a)
				black_max_on = maxf(black_max_on, b)
			elif x > 150:
				total += 1
				if absf(a - b) > 0.0001:
					changed += 1
				off_levels[roundi(a * 255.0)] = true
				on_levels[roundi(b * 255.0)] = true
	print("DEBAND_PROBE renderer=%s viewport=%s changed=%d/%d off_levels=%d on_levels=%d black_max_off=%.6f black_max_on=%.6f startup_viewport=%s project_setting=%s" % [RenderingServer.get_current_rendering_method(), off.get_size(), changed, total, off_levels.size(), on_levels.size(), black_max_off, black_max_on, startup_debanding, ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding", false)])
	world.free()
	quit(0 if startup_debanding and changed > total / 100 and black_max_on <= black_max_off + 0.004 else 1)


func _capture(name: String) -> Image:
	var output := ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(output)
	for _frame: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output.path_join(name)
	var result := image.save_png(path)
	if result != OK:
		push_error("Failed to save debanding probe: " + path)
	return image
