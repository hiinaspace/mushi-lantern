extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var guide := TutorialGuideVisual.new()
	root.add_child(guide)
	guide.reset_guide(Vector3.ZERO)
	var lid := guide.get_node("JarLid") as MeshInstance3D
	var base := guide.get_node("JarBase") as MeshInstance3D
	assert(not (lid.material_override as StandardMaterial3D).emission_enabled)
	assert(not (base.material_override as StandardMaterial3D).emission_enabled)
	assert(guide.get_node("GuideJar").material_override is ShaderMaterial)
	guide._process(0.3)
	var neutral_position: Vector3 = guide.get_node("GuideMushi").position
	var neutral_heading: Color = guide._glyph_image.get_pixel(0, 2)
	assert(neutral_position.length() > 0.07 and absf(neutral_heading.g) < 0.8,
		"neutral mushi should visibly bounce and rotate")
	guide.set_guide_state(TutorialDirector.GuideState.DORMANT)
	guide._process(0.3)
	var dormant_position: Vector3 = guide.get_node("GuideMushi").position
	var dormant_heading: Color = guide._glyph_image.get_pixel(0, 2)
	assert(absf(dormant_position.x) < 0.01 and absf(dormant_position.z) < 0.01)
	assert(dormant_heading.g > 0.99, "blue-lit mushi should settle upright")
	print("TUTORIAL_GUIDE_VISUAL_CHECKS_OK")
	quit(0)
