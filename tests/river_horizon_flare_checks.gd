extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var river := RiverMeshPrototype.new()
	root.add_child(river)
	var left := river.get_node("HorizonFlareLeft") as MeshInstance3D
	var right := river.get_node("HorizonFlareRight") as MeshInstance3D
	assert(left != null and right != null)
	assert(left.position.x < 0.0 and right.position.x > 0.0)
	assert(right.position.x - (right.mesh as QuadMesh).size.x * 0.5 < 2700.0,
		"the flare overlaps the distant tube before its fade begins")
	assert(left.position.x + (left.mesh as QuadMesh).size.x * 0.5 > -2700.0,
		"the western flare overlaps the distant tube")
	river.apply_tuning({"river_depth": 1.8, "horizon_flare_strength": 0.6,
		"horizon_flare_spread": 1.4, "far_scintillation_blend": 0.7})
	for flare in [left, right]:
		var material := flare.material_override as ShaderMaterial
		assert(is_equal_approx(flare.position.y + (flare.mesh as QuadMesh).size.y * 0.5, 0.0),
			"flare stays wholly below the ground horizon")
		assert(is_equal_approx(float(material.get_shader_parameter("horizon_flare_strength")), 0.6))
		assert(is_equal_approx(float(material.get_shader_parameter("horizon_flare_spread")), 1.4))
	assert(is_equal_approx(float((river.material_override as ShaderMaterial).get_shader_parameter("far_scintillation_blend")), 0.7))
	for shell in river.get_children():
		if shell.name.begins_with("ParticleShell"):
			assert(is_equal_approx(float(((shell as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("far_scintillation_blend")), 0.7))
	print("RIVER_HORIZON_FLARE_CHECKS_OK")
	quit(0)
