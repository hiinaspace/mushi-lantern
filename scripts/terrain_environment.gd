class_name TerrainEnvironment
extends Node3D

const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage_luminescence.gdshader")
const FOREST_EDGE_SHADER: Shader = preload("res://shaders/forest_edge_emission.gdshader")
const RIVER_MESH_SCRIPT: Script = preload("res://scripts/river_mesh_prototype.gd")
const RIVER_MESH_MASK_SHADER: Shader = preload("res://shaders/river_mesh_blocker_mask.gdshader")

## Runtime Terrain3D basin and a small original static nature kit. Placement
## records live in EnvironmentSurface so rendering, physics and GPU avoidance
## agree even when decorative density is reduced.
var surface: EnvironmentSurface
var terrain: Terrain3D
var _mesh_assets: Dictionary = {}
var _quality: Dictionary = {"vegetation": "high", "shadows": "high"}
var _prop_bodies: Node3D
var _instanced_vegetation_mode: String = ""
var _foliage_materials: Array[ShaderMaterial] = []
var _opaque_foliage_mask: ImageTexture
var _leaf_foliage_mask: ImageTexture
var _grass_foliage_mask: ImageTexture
var _night_vision: float = 0.0
var _stream_visibility: float = 0.0
var terrain_reveal_active: bool = false
var _river_far_receiver: RiverFarReceiver
var _river_mesh: MeshInstance3D
var _river_mesh_active := false
## Optional naturalistic audition. "procedural" keeps the shipped greybox kit.
## Oak and pine use the same seeded prop records and differ only in tree and
## ground materials, so visual captures can be compared in the same framing.
var forest_style: String = "pine"

func build(world_surface: EnvironmentSurface) -> void:
	surface = world_surface
	forest_style = OS.get_environment("MUSHI_FOREST_STYLE").strip_edges().to_lower()
	if forest_style not in ["oak", "pine", "procedural"]:
		forest_style = "pine"
	_foliage_materials.clear()
	terrain = Terrain3D.new()
	terrain.name = "BasinTerrain3D"
	add_child(terrain)
	# The GDExtension initializes defaults on entering the tree.
	terrain.region_size = Terrain3D.SIZE_64
	terrain.vertex_spacing = 1.0
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.assets = Terrain3DAssets.new()
	if forest_style == "oak":
		terrain.assets.set_texture(0, _file_texture_asset(
			"Oak leaf litter",
			"res://assets/forest/polyhaven/forrest_ground_01_diff_1k.jpg",
			"res://assets/forest/polyhaven/forrest_ground_01_nor_gl_1k.jpg",
			0.50
		))
	elif forest_style == "pine":
		terrain.assets.set_texture(0, _file_texture_asset(
			"Pine needles",
			"res://assets/forest/polyhaven/forrest_ground_03_diff_1k.jpg",
			"res://assets/forest/polyhaven/forrest_ground_03_nor_gl_1k.jpg",
			0.50
		))
	else:
		terrain.assets.set_texture(0, _texture_asset("Meadow earth", Color(0.18, 0.24, 0.14)))
	if forest_style in ["oak", "pine"]:
		terrain.assets.set_texture(1, _file_texture_asset(
			"Weathered rock",
			"res://assets/forest/polyhaven/rock_01_diff_1k.jpg",
			"res://assets/forest/polyhaven/rock_01_nor_gl_1k.jpg",
			1.0 / 1.5
		))
	else:
		terrain.assets.set_texture(1, _texture_asset("Rim stone", Color(0.24, 0.25, 0.22)))
	_mesh_assets = {
		"tree": _forest_tree_asset(forest_style) if forest_style in ["oak", "pine"] else _mesh_asset("Meadow tree", _tree_mesh(), _distant_tree_mesh()),
		"rock": _mesh_asset("Boulders", _rock_mesh(forest_style)),
		"bush": _forest_fern_asset() if forest_style in ["oak", "pine"] else _mesh_asset("Understory", _bush_mesh()),
		"grass": _forest_grass_asset() if forest_style == "pine" else _mesh_asset("Meadow tufts", _grass_mesh()),
	}
	terrain.assets.set_mesh_asset(0, _mesh_assets.tree)
	terrain.assets.set_mesh_asset(1, _mesh_assets.rock)
	terrain.assets.set_mesh_asset(2, _mesh_assets.bush)
	terrain.assets.set_mesh_asset(3, _mesh_assets.grass)
	var origin := Vector3(-surface.size_m * 0.5, 0.0, -surface.size_m * 0.5)
	var control_image: Image = _pine_ground_control_image() if forest_style == "pine" else null
	terrain.data.import_images([surface.get_terrain_height_image(), control_image, null], origin, 0.0, 1.0)
	terrain_reveal_active = TerrainRiverReveal.install(terrain.material, surface)
	if forest_style == "pine" and terrain_reveal_active:
		_install_smooth_moss_blend()
	if terrain_reveal_active:
		var river_map: ImageTexture = TerrainRiverReveal.path_map(surface.size_m)
		var river_length: float = TerrainRiverReveal.path_length(surface.size_m)
		for material in _foliage_materials:
			material.set_shader_parameter("river_path_map", river_map)
			material.set_shader_parameter("river_size", float(TerrainRiverReveal.path_extent(surface.size_m)))
			material.set_shader_parameter("river_length", river_length)
			material.set_shader_parameter("river_plane_y", TerrainRiverReveal.RIVER_PLANE_Y)
			material.set_shader_parameter("river_goal_xz", Vector2.ZERO)
			material.set_shader_parameter("river_night_vision", _stream_visibility)
		_river_far_receiver = RiverFarReceiver.new()
		add_child(_river_far_receiver)
		_river_far_receiver.configure(surface, river_map, river_length)
		# The headset-approved mesh is the normal path. Preserve the receiver for
		# quick A/B checks and as a fallback during this visual pass.
		_river_mesh_active = OS.get_environment("MUSHI_RIVER_LEGACY") != "1"
		# The sparse receiver is a large, collisionless grid outside the basin.
		# With the river tube active it can read as isolated flat panels at the
		# grove edge, so reserve that fallback surface for the legacy path.
		_river_far_receiver.visible = not _river_mesh_active
		if _river_mesh_active:
			_river_mesh = RIVER_MESH_SCRIPT.new()
			add_child(_river_mesh)
			_set_mesh_night_vision(_river_mesh, _stream_visibility)
			terrain.material.set_shader_param("river_tube_enabled", 0.0)
			_river_far_receiver.set_tube_enabled(false)
			for material in _foliage_materials:
				material.set_shader_parameter("river_tube_enabled", 0.0)
			call_deferred("_attach_river_mesh_blockers")
	# Godot 4.7.2's HeightMapShape3D ray/character collision has repeated
	# rectangular misses inside valid Terrain3D regions. A static triangle
	# shape baked from Terrain3D's own height data is reliable here.
	terrain.collision.mode = Terrain3DCollision.DISABLED
	var ground := StaticBody3D.new()
	ground.name = "BakedBasinCollision"
	var ground_shape := CollisionShape3D.new()
	ground_shape.name = "CollisionShape3D"
	ground_shape.shape = terrain.bake_mesh(0).create_trimesh_shape()
	ground.add_child(ground_shape)
	add_child(ground)
	_prop_bodies = Node3D.new()
	_prop_bodies.name = "CoarsePropCollision"
	add_child(_prop_bodies)
	for prop in surface.get_props():
		if prop.kind == "tree" or prop.kind == "rock":
			_add_prop_collision(prop)
	apply_quality(_quality)

func set_night_vision(value: float) -> void:
	_night_vision = clampf(value, 0.0, 1.0)
	for material in _foliage_materials:
		material.set_shader_parameter("night_vision", _night_vision)


func set_stream_visibility(value: float) -> void:
	_stream_visibility = clampf(value, 0.0, 1.0)
	if terrain_reveal_active:
		terrain.material.set_shader_param("river_night_vision", _stream_visibility)
		if _river_far_receiver != null:
			_river_far_receiver.set_night_vision(_stream_visibility)
		if _river_mesh_active and _river_mesh != null:
			_set_mesh_night_vision(_river_mesh, _stream_visibility)
	for material in _foliage_materials:
		material.set_shader_parameter("river_night_vision", _stream_visibility if terrain_reveal_active else 0.0)


static func stream_visibility_target(night_vision: float, shutter_openness: float, tutorial_reveal_allowed: bool = true, reveal_start: float = 0.18, reveal_end: float = 0.68) -> float:
	if not tutorial_reveal_allowed or shutter_openness > 0.01:
		return 0.0
	var low := clampf(reveal_start, 0.0, 0.98)
	var high := clampf(reveal_end, low + 0.01, 1.0)
	var adapted := clampf((clampf(night_vision, 0.0, 1.0) - low) / (high - low), 0.0, 1.0)
	return adapted * adapted * (3.0 - 2.0 * adapted)


static func advance_stream_visibility(current: float, target: float, delta: float, fade_seconds: float = 1.2) -> float:
	if target <= 0.0:
		return 0.0
	var blend := 1.0 - exp(-maxf(0.0, delta) / maxf(fade_seconds, 0.05))
	return lerpf(clampf(current, 0.0, 1.0), clampf(target, 0.0, 1.0), blend)


func set_visual_tuning(values: Dictionary) -> void:
	if _river_mesh_active and _river_mesh != null:
		_river_mesh.set_tuning(values)
	var depth := clampf(float(values.get("river_depth", 1.0)), 0.1, 3.0)
	if terrain_reveal_active:
		terrain.material.set_shader_param("river_plane_y", TerrainRiverReveal.RIVER_PLANE_Y * depth)
		terrain.material.set_shader_param("river_depth", depth)
		if _river_far_receiver != null:
			_river_far_receiver.set_depth(depth)
	for material in _foliage_materials:
		material.set_shader_parameter("foliage_reveal_start", float(values.get("foliage_start", 0.90)))
		material.set_shader_parameter("foliage_reveal_end", float(values.get("foliage_end", 0.99)))
		material.set_shader_parameter("river_plane_y", TerrainRiverReveal.RIVER_PLANE_Y * depth)
		material.set_shader_parameter("river_depth", depth)

func _set_mesh_night_vision(node: Node, value: float) -> void:
	if node is MeshInstance3D:
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("river_night_vision", value)
	for child: Node in node.get_children():
		_set_mesh_night_vision(child, value)

func _attach_river_mesh_blockers() -> void:
	if not _river_mesh_active:
		return
	var lab := get_parent()
	if lab == null or not lab.has_method("_build_player"):
		return
	var mask := ShaderMaterial.new()
	mask.shader = RIVER_MESH_MASK_SHADER
	mask.render_priority = -20
	var count := 0
	for property_name in ["goal_shrine", "staff_tool", "xr_player"]:
		var blocker: Variant = lab.get(property_name)
		if blocker is Node:
			count += _attach_river_mesh_mask(blocker, mask)
			if property_name == "xr_player":
				for hand_path in ["LeftController/Hand", "RightController/Hand"]:
					var hand: Node = blocker.get_node_or_null(hand_path)
					var hand_meshes := _count_river_mesh_blocker_meshes(hand) if hand != null else 0
					print("RIVER_MESH_HAND_MASK path=%s meshes=%d" % [hand_path, hand_meshes])
					if hand_meshes == 0:
						push_warning("River mesh stencil has no hand mesh at %s" % hand_path)
	var ukon := lab.get_node_or_null("MikoPresentation")
	if ukon != null:
		count += _attach_river_mesh_mask(ukon, mask)
	print("RIVER_MESH_BLOCKERS count=%d" % count)

func _attach_river_mesh_mask(node: Node, material: ShaderMaterial) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var previous_overlay := mesh.material_overlay
		if previous_overlay != null:
			var chained_mask := material.duplicate() as ShaderMaterial
			chained_mask.next_pass = previous_overlay
			mesh.material_overlay = chained_mask
		else:
			mesh.material_overlay = material
		count += 1
	for child: Node in node.get_children():
		count += _attach_river_mesh_mask(child, material)
	return count

func _count_river_mesh_blocker_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		count += _count_river_mesh_blocker_meshes(child)
	return count

func apply_quality(settings: Dictionary) -> void:
	_quality.merge(settings, true)
	if terrain == null:
		return
	var low_vegetation: bool = str(_quality.get("vegetation", "high")) == "low"
	var low_shadows: bool = str(_quality.get("shadows", "high")) == "low"
	var vegetation_mode := "low" if low_vegetation else "high"
	if _instanced_vegetation_mode != vegetation_mode:
		var groups: Array[Array] = [[], [], [], []]
		var decorative_index := 0
		for prop in surface.get_props():
			var kind: String = prop.kind
			if kind == "grass" or kind == "bush":
				decorative_index += 1
				if forest_style == "pine" and kind == "grass":
					# Pine needles read best as a fine, intermittent carpet. Keep
					# half the high-quality density available as a practical fallback.
					var stride := 8 if low_vegetation else 4
					if decorative_index % stride != 0:
						continue
				elif low_vegetation and decorative_index % 3 != 0:
					continue
			var mesh_id := 0
			match kind:
				"rock": mesh_id = 1
				"bush": mesh_id = 2
				"grass": mesh_id = 3
			var sc: float = prop.scale
			var prop_scale := Vector3.ONE * sc
			var variant: int = int(prop.get("variant", 0))
			if kind == "rock":
				# The same rock mesh gets visibly different silhouettes from
				# deterministic nonuniform scaling and a wider yaw spread.
				match variant % 3:
					0:
						prop_scale *= Vector3(1.18, 0.78, 0.90)
					1:
						prop_scale *= Vector3(0.82, 1.16, 1.08)
					2:
						prop_scale *= Vector3(1.04, 0.96, 0.76)
			elif kind == "bush" or kind == "grass":
				match variant % 3:
					0:
						prop_scale *= Vector3(1.12, 0.92, 0.88)
					1:
						prop_scale *= Vector3(0.88, 1.06, 1.12)
					2:
						prop_scale *= Vector3(1.02, 1.12, 0.94)
			var yaw_spread := (float(variant) - 1.0) * (0.42 if kind == "rock" else 0.08)
			var yaw := float(prop.yaw) + yaw_spread
			var basis := Basis(Vector3.UP, yaw).scaled(prop_scale)
			groups[mesh_id].append(Transform3D(basis, prop.position))
		for mesh_id in 4:
			terrain.instancer.clear_by_mesh(mesh_id)
			terrain.instancer.add_transforms(mesh_id, groups[mesh_id])
		_instanced_vegetation_mode = vegetation_mode
	(_mesh_assets.grass as Terrain3DMeshAsset).cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_mesh_assets.bush as Terrain3DMeshAsset).cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	(_mesh_assets.tree as Terrain3DMeshAsset).cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	(_mesh_assets.tree as Terrain3DMeshAsset).lod0_range = 20.0 if low_vegetation else 32.0
	(_mesh_assets.tree as Terrain3DMeshAsset).lod1_range = 55.0 if low_vegetation else 80.0
	(_mesh_assets.tree as Terrain3DMeshAsset).lod2_range = 115.0 if low_vegetation else 144.0
	(_mesh_assets.grass as Terrain3DMeshAsset).lod0_range = (10.0 if low_vegetation else 12.0) if forest_style == "pine" else (18.0 if low_vegetation else 32.0)
	if forest_style == "pine":
		(_mesh_assets.grass as Terrain3DMeshAsset).lod1_range = 24.0 if low_vegetation else 32.0
	(_mesh_assets.bush as Terrain3DMeshAsset).lod0_range = 32.0 if low_vegetation else 60.0

func _texture_asset(label: String, color: Color) -> Terrain3DTextureAsset:
	# A deterministic, tileable multi-scale grain gives soil and exposed stone
	# broad mottling without adding mesh/material batches or runtime animation.
	const TEXTURE_SIZE := 128
	var albedo := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var normal := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var stone := label == "Rim stone"
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var broad := _tileable_noise(float(x), float(y), 5, 13)
			var medium := _tileable_noise(float(x), float(y), 17, 29)
			var fine := _tileable_noise(float(x), float(y), 43, 47)
			var shade := 0.91 + broad * 0.12 + medium * 0.075 + fine * 0.035
			var warm_cool := (medium - 0.5) * (0.035 if stone else 0.018)
			albedo.set_pixel(x, y, Color(
				color.r * shade + warm_cool,
				color.g * shade,
				color.b * shade - warm_cool * 0.45,
				0.5
			))
			normal.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.92))
	var asset := Terrain3DTextureAsset.new()
	asset.name = label
	albedo.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	normal.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	asset.albedo_texture = ImageTexture.create_from_image(albedo)
	asset.normal_texture = ImageTexture.create_from_image(normal)
	asset.uv_scale = 0.075
	return asset


func _file_texture_asset(label: String, albedo_path: String, normal_path: String, uv_scale: float) -> Terrain3DTextureAsset:
	var asset := Terrain3DTextureAsset.new()
	asset.name = label
	asset.albedo_texture = _normalized_texture(load(albedo_path) as Texture2D)
	asset.normal_texture = _normalized_texture(load(normal_path) as Texture2D)
	asset.uv_scale = uv_scale
	return asset


func _pine_ground_control_image() -> Image:
	# Keep encoded control data for Terrain3D's slope autoshader only. The moss
	# overlay uses a filtered world-space coverage texture below; encoded RF
	# control pixels are one metre apart and produce visible stair steps.
	var image := Image.create_empty(surface.size_m, surface.size_m, false, Image.FORMAT_RF)
	var default_control := Terrain3DUtil.enc_base(0) | Terrain3DUtil.enc_auto(true)
	for z in surface.size_m:
		for x in surface.size_m:
			image.set_pixel(x, z, Color(Terrain3DUtil.as_float(default_control), 0.0, 0.0, 1.0))
	return image


func _install_smooth_moss_blend() -> void:
	var terrain_shader := terrain.material.shader_override
	if terrain_shader == null:
		return
	var code := terrain_shader.code
	const HEADER := "shader_type spatial;\n"
	const BASE_ALBEDO := "ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;"
	const MOSS_UNIFORMS := "uniform sampler2D mushi_moss_albedo : source_color, filter_linear_mipmap, repeat_enable;\nuniform sampler2D mushi_moss_coverage : filter_linear_mipmap, repeat_disable;\nuniform float mushi_moss_world_extent = 128.0;\n"
	const MOSS_BLEND := "\n vec2 mushi_moss_uv = (v_vertex.xz + vec2(mushi_moss_world_extent * 0.5)) / mushi_moss_world_extent;\n float mushi_moss_weight = texture(mushi_moss_coverage, mushi_moss_uv).r;\n vec3 mushi_moss_color = texture(mushi_moss_albedo, v_vertex.xz / 3.0).rgb;\n ALBEDO = mix(ALBEDO, mushi_moss_color, mushi_moss_weight);"
	if not code.begins_with(HEADER) or not code.contains(BASE_ALBEDO):
		push_warning("Pine moss blend skipped: Terrain3D shader anchor changed")
		return
	code = code.replace(HEADER, HEADER + MOSS_UNIFORMS)
	code = code.replace(BASE_ALBEDO, BASE_ALBEDO + MOSS_BLEND)
	terrain_shader.code = code
	terrain.material.shader_override = terrain_shader
	terrain.material.shader_override_enabled = true
	terrain.material.set_shader_param("mushi_moss_albedo", _mipmapped_texture("res://assets/forest/polyhaven/mossy_rock_diff_1k.jpg"))
	terrain.material.set_shader_param("mushi_moss_coverage", _moss_coverage_texture())
	terrain.material.set_shader_param("mushi_moss_world_extent", float(surface.size_m))


func _moss_coverage_texture() -> ImageTexture:
	var extent := surface.size_m
	var half := float(extent) * 0.5
	var image := Image.create_empty(extent, extent, false, Image.FORMAT_R8)
	for y in extent:
		for x in extent:
			var world := Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half)
			var slope_fade := 1.0 - smoothstep(0.30, 0.48, _ground_grade(world))
			var coverage := 0.0
			if surface.is_playable(world, 1.0):
				coverage = _moss_coverage(world) * _moss_clearance(world) * slope_fade
			image.set_pixel(x, y, Color(coverage, 0.0, 0.0, 1.0))
	# Preserve the same inexpensive per-metre field computation as the control
	# map, then resample it to half-metre texels for filtered transitions.
	image.resize(extent * 2, extent * 2, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _ground_grade(world: Vector2) -> float:
	var dx := (surface.get_height_at(world + Vector2.RIGHT) - surface.get_height_at(world - Vector2.RIGHT)) * 0.5
	var dz := (surface.get_height_at(world + Vector2.DOWN) - surface.get_height_at(world - Vector2.DOWN)) * 0.5
	return Vector2(dx, dz).length()


func _moss_coverage(world: Vector2) -> float:
	var broad := sin(world.x * 0.21 + sin(world.y * 0.13) * 1.4) * 0.5 + 0.5
	var medium := sin(world.y * 0.47 + world.x * 0.17 + sin(world.x * 0.31) * 0.8) * 0.5 + 0.5
	return smoothstep(0.53, 0.79, broad * 0.62 + medium * 0.38) * 0.78


func _moss_clearance(world: Vector2) -> float:
	var clear := smoothstep(6.0, 9.0, world.distance_to(Vector2(0.0, 18.4)))
	clear *= smoothstep(5.5, 8.0, world.distance_to(Vector2(-14.4, -8.0)))
	for center: Vector2 in surface.patch_centers:
		clear *= smoothstep(5.2, 7.2, world.distance_to(center))
	var known_route := [Vector2(10, 0), Vector2(10, 22), Vector2(37, 22), Vector2(37, 0), Vector2(20, 0)]
	for index in known_route.size() - 1:
		clear *= _distance_from_segment_fade(world, known_route[index], known_route[index + 1], 3.0, 5.0)
	clear *= _distance_from_segment_fade(world, Vector2(-14.4, -8.0), Vector2(0.0, 18.4), 2.5, 4.5)
	return clear


func _distance_from_segment_fade(point: Vector2, start: Vector2, end: Vector2, inner: float, outer: float) -> float:
	var segment := end - start
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return smoothstep(inner, outer, point.distance_to(start + segment * t))


func _normalized_texture(texture: Texture2D) -> ImageTexture:
	var image := texture.get_image()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != 1024 or image.get_height() != 1024:
		image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _mipmapped_texture(path: String) -> ImageTexture:
	var image := (load(path) as Texture2D).get_image()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _forest_tree_asset(style: String) -> Terrain3DMeshAsset:
	var root := Node3D.new()
	root.name = "OakForestTree" if style == "oak" else "PineForestTree"
	var scale_factor := 9.5 / (67.46274 if style == "oak" else 49.77322)
	var leaf_texture_path := "res://assets/forest/ez-tree/source-textures/oak-leaves.png" if style == "oak" else "res://assets/forest/ez-tree/source-textures/pine-leaves.png"
	var edge_mask_path := "res://assets/forest/ez-tree/edge-masks/oak_leaf_alpha_edges_3px.png" if style == "oak" else "res://assets/forest/ez-tree/edge-masks/pine_leaf_alpha_edges_3px.png"
	var leaf_texture := _mipmapped_texture(leaf_texture_path)
	var edge_mask := _mipmapped_texture(edge_mask_path)
	var bark_albedo: Texture2D = _normalized_texture(load("res://assets/forest/polyhaven/pine_bark_diff_1k.jpg") as Texture2D) if style == "pine" else null
	var bark_normal: Texture2D = _normalized_texture(load("res://assets/forest/polyhaven/pine_bark_nor_gl_1k.jpg") as Texture2D) if style == "pine" else null
	var prefix := "oak" if style == "oak" else "pine"
	for lod_index in 3:
		var lod_path := "res://assets/forest/ez-tree/%s-medium-lod%d.glb" % [prefix, lod_index]
		var source_scene := (load(lod_path) as PackedScene).instantiate()
		var combined_mesh := ArrayMesh.new()
		_append_forest_tree_meshes(combined_mesh, source_scene, Transform3D.IDENTITY, scale_factor, style, leaf_texture, edge_mask, bark_albedo, bark_normal)
		source_scene.free()
		var lod_mesh_instance := MeshInstance3D.new()
		lod_mesh_instance.name = "LOD%d" % lod_index
		lod_mesh_instance.mesh = combined_mesh
		root.add_child(lod_mesh_instance)
		lod_mesh_instance.owner = root
	_set_owner_recursive(root, root)
	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(root)
	assert(pack_error == OK)
	root.free()
	var asset := Terrain3DMeshAsset.new()
	asset.name = "EZ-Tree Oak Medium" if style == "oak" else "EZ-Tree Pine Medium"
	asset.scene_file = packed_scene
	asset.lod0_range = 32.0
	asset.lod1_range = 80.0
	asset.lod2_range = 144.0
	asset.last_lod = 2
	return asset


func _forest_fern_asset() -> Terrain3DMeshAsset:
	var source := (load("res://assets/forest/cc0-flora/royal-fern.glb") as PackedScene).instantiate()
	var root := Node3D.new()
	root.name = "CC0RoyalFern"
	var lod_root := Node3D.new()
	lod_root.name = "LOD0"
	root.add_child(lod_root)
	# Keep the imported GLB as a nested scene instance and preserve Terrain3D's
	# direct LOD0 child structure.
	source.scale *= 0.52
	lod_root.add_child(source)
	# Owning the imported scene root keeps its internal GLB ownership boundary.
	source.owner = root
	lod_root.owner = root
	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(root)
	assert(pack_error == OK)
	root.free()
	var asset := Terrain3DMeshAsset.new()
	asset.name = "CC0 Royal Fern"
	asset.scene_file = packed_scene
	asset.last_lod = 0
	asset.lod0_range = 42.0
	return asset


func _forest_grass_asset() -> Terrain3DMeshAsset:
	var source := (load("res://assets/forest/cc0-flora/meadow-grass-clump.glb") as PackedScene).instantiate()
	var detailed_mesh := ArrayMesh.new()
	_append_forest_grass_meshes(detailed_mesh, source, Transform3D.IDENTITY)
	source.free()
	var asset := _mesh_asset("CC0 Meadow Grass Clump", detailed_mesh, _grass_mesh())
	asset.lod0_range = 12.0
	asset.lod1_range = 32.0
	asset.last_lod = 1
	return asset


func _append_forest_grass_meshes(mesh_out: ArrayMesh, node: Node, parent_transform: Transform3D) -> void:
	var composed := parent_transform
	if node is Node3D:
		composed *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := _foliage_material(Color(0.16, 0.23, 0.12))
			material.set_shader_parameter("fleck_frequency", 5.0)
			material.set_shader_parameter("fleck_strength", 0.26)
			var surface_tool := SurfaceTool.new()
			surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Give the forest floor grass enough height and width to read as small
			# natural clumps at the player's lantern range. The old half-scale
			# export collapsed into thin isolated spikes in the wide grove view.
			var grass_scale := Transform3D(Basis().scaled(Vector3.ONE * 0.66), Vector3.ZERO)
			surface_tool.append_from(mesh_instance.mesh, surface_index, grass_scale * composed)
			surface_tool.set_material(material)
			surface_tool.commit(mesh_out)
	for child: Node in node.get_children():
		_append_forest_grass_meshes(mesh_out, child, composed)


func _append_forest_tree_meshes(mesh_out: ArrayMesh, node: Node, parent_transform: Transform3D, scale_factor: float, style: String, leaf_texture: Texture2D, edge_mask: Texture2D, bark_albedo: Texture2D, bark_normal: Texture2D) -> void:
	var composed_transform := parent_transform
	if node is Node3D:
		composed_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var source_material := mesh_instance.get_active_material(surface_index)
			var material: Material = source_material
			if mesh_instance.name.begins_with("Leaves_"):
				var edge_material := ShaderMaterial.new()
				edge_material.shader = FOREST_EDGE_SHADER
				edge_material.set_shader_parameter("albedo_tex", leaf_texture)
				edge_material.set_shader_parameter("edge_mask", edge_mask)
				edge_material.set_shader_parameter("alpha_cutoff", 0.5 if style == "oak" else 0.3)
				edge_material.set_shader_parameter("edge_color", Color(0.66, 0.42, 0.84))
				edge_material.set_shader_parameter("edge_strength", 0.48)
				edge_material.set_shader_parameter("night_vision", _night_vision)
				edge_material.set_shader_parameter("foliage_reveal_start", 0.90)
				edge_material.set_shader_parameter("foliage_reveal_end", 0.99)
				material = edge_material
				_foliage_materials.append(edge_material)
			elif mesh_instance.name.begins_with("Branches_"):
				# EZ-Tree's exported GLB bark albedo sidecars are fully transparent
				# after import, which leaves the trunks black even under direct light.
				var bark_material := StandardMaterial3D.new()
				if style == "pine":
					bark_material.albedo_texture = bark_albedo
					bark_material.albedo_color = Color(0.50, 0.48, 0.45)
					bark_material.normal_texture = bark_normal
					bark_material.normal_enabled = true
					bark_material.normal_scale = 0.32
				else:
					bark_material.albedo_color = Color(0.22, 0.16, 0.11)
				bark_material.roughness = 0.92
				bark_material.metallic = 0.0
				bark_material.metallic_specular = 0.12
				material = bark_material
			var surface_tool := SurfaceTool.new()
			surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			var root_scale := Transform3D(Basis().scaled(Vector3.ONE * scale_factor), Vector3.ZERO)
			surface_tool.append_from(mesh_instance.mesh, surface_index, root_scale * composed_transform)
			surface_tool.set_material(material)
			surface_tool.commit(mesh_out)
	for child: Node in node.get_children():
		_append_forest_tree_meshes(mesh_out, child, composed_transform, scale_factor, style, leaf_texture, edge_mask, bark_albedo, bark_normal)


func _set_owner_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_owner_recursive(child, scene_root)

func _tileable_noise(x: float, y: float, cells: int, salt: int) -> float:
	var period := float(cells)
	var px := x / 128.0 * period
	var py := y / 128.0 * period
	var ix := floori(px)
	var iy := floori(py)
	var tx := px - float(ix)
	var ty := py - float(iy)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _lattice_noise(posmod(ix, cells), posmod(iy, cells), salt)
	var b := _lattice_noise(posmod(ix + 1, cells), posmod(iy, cells), salt)
	var c := _lattice_noise(posmod(ix, cells), posmod(iy + 1, cells), salt)
	var d := _lattice_noise(posmod(ix + 1, cells), posmod(iy + 1, cells), salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

func _lattice_noise(x: int, y: int, salt: int) -> float:
	var value := sin(float(x * 127 + y * 311 + salt * 73) * 12.9898) * 43758.5453
	return value - floorf(value)

func _mesh_asset(label: String, mesh: Mesh, far_mesh: Mesh = null) -> Terrain3DMeshAsset:
	var root := Node3D.new()
	root.name = label.replace(" ", "")
	var near := MeshInstance3D.new()
	near.name = "LOD0"
	near.mesh = mesh
	root.add_child(near)
	near.owner = root
	if far_mesh != null:
		var distant := MeshInstance3D.new()
		distant.name = "LOD1"
		distant.mesh = far_mesh
		root.add_child(distant)
		distant.owner = root
	var scene := PackedScene.new()
	var error := scene.pack(root)
	assert(error == OK)
	root.free()
	var asset := Terrain3DMeshAsset.new()
	asset.name = label
	asset.scene_file = scene
	asset.lod0_range = 38.0 if far_mesh != null else 75.0
	if far_mesh != null:
		asset.last_lod = 1
		asset.lod1_range = 130.0
	else:
		asset.last_lod = 0
	return asset

func _append_primitive(out: ArrayMesh, primitive: Mesh, transform: Transform3D, material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(primitive, 0, transform)
	tool.set_material(material)
	tool.commit(out)

func _append_many(out: ArrayMesh, primitive: Mesh, transforms: Array[Transform3D], material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for transform in transforms:
		tool.append_from(primitive, 0, transform)
	tool.set_material(material)
	tool.commit(out)

func _material(color: Color, double_sided: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _foliage_material(color: Color, cutout: bool = false, grass_blades: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE_SHADER
	material.set_shader_parameter("foliage_color", color)
	material.set_shader_parameter("night_vision", _night_vision)
	material.set_shader_parameter("fleck_strength", 0.34 if grass_blades else 0.82)
	material.set_shader_parameter("river_night_vision", _stream_visibility if terrain_reveal_active else 0.0)
	material.set_shader_parameter("fleck_frequency", 6.0 if grass_blades else 3.0)
	material.set_shader_parameter("grove_size", float(surface.size_m))
	if cutout:
		if grass_blades:
			if _grass_foliage_mask == null:
				_grass_foliage_mask = _cutout_texture(true)
			material.set_shader_parameter("foliage_mask", _grass_foliage_mask)
		else:
			if _leaf_foliage_mask == null:
				_leaf_foliage_mask = _cutout_texture(false)
			material.set_shader_parameter("foliage_mask", _leaf_foliage_mask)
	else:
		if _opaque_foliage_mask == null:
			var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			_opaque_foliage_mask = ImageTexture.create_from_image(image)
		material.set_shader_parameter("foliage_mask", _opaque_foliage_mask)
	_foliage_materials.append(material)
	return material

func _cutout_texture(grass_blades: bool) -> ImageTexture:
	# Small authored mathematical masks exercise foliage coverage and cutout
	# cost without a third-party asset or animated wind shader.
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var u := (float(x) + 0.5) / 64.0
			var v := (float(y) + 0.5) / 64.0
			var opaque := false
			if grass_blades:
				for blade_center in [0.22, 0.50, 0.76]:
					var lean: float = (1.0 - v) * (float(blade_center) - 0.5) * 0.22
					var blade_width := 0.075 * (1.0 - v) + 0.006
					if v > 0.12 and absf(u - blade_center - lean) < blade_width and v < 0.92 - 0.09 * absf(blade_center - 0.5):
						opaque = true
			else:
				var centers := [Vector2(0.31, 0.48), Vector2(0.62, 0.40), Vector2(0.47, 0.64), Vector2(0.73, 0.66)]
				for center in centers:
					var delta := Vector2((u - center.x) / 0.28, (v - center.y) / 0.24)
					if delta.length_squared() < 1.0:
						opaque = true
				# Small empty pockets prevent a solid billboard crown.
				if sin(u * 47.0 + v * 25.0) * cos(v * 59.0 - u * 11.0) > 0.91:
					opaque = false
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if opaque else 0.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _tree_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var bark := _material(Color(0.23, 0.19, 0.15))
	var leaf := _foliage_material(Color(0.16, 0.28, 0.17))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.17
	trunk.bottom_radius = 0.40
	trunk.height = 5.8
	trunk.radial_segments = 7
	_append_primitive(mesh, trunk, Transform3D(Basis(), Vector3(0, 2.9, 0)), bark)
	var crown := SphereMesh.new()
	crown.radial_segments = 9
	crown.rings = 5
	var clumps := [
		Vector3(-1.45, 6.05, 0.25), Vector3(1.35, 6.15, -0.55),
		Vector3(-0.35, 6.75, 1.25), Vector3(0.25, 7.05, -1.1),
		Vector3(0.15, 7.7, 0.1),
	]
	var clump_transforms: Array[Transform3D] = []
	for index in clumps.size():
		var clump: Vector3 = clumps[index]
		var width := 1.7 if index < 2 else 1.45
		var basis := Basis().scaled(Vector3(width, 1.7, 1.45))
		clump_transforms.append(Transform3D(basis, clump))
	_append_many(mesh, crown, clump_transforms, leaf)
	var card := PlaneMesh.new()
	card.size = Vector2(3.0, 2.6)
	var card_transforms: Array[Transform3D] = []
	for clump in clumps:
		for side in 4:
			var angle := float(side) * TAU / 4.0
			var rotation := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -PI * 0.5)
			var offset := Vector3(sin(angle), 0.0, cos(angle)) * 0.98
			card_transforms.append(Transform3D(rotation, clump + offset))
	_append_many(mesh, card, card_transforms, _foliage_material(Color(0.18, 0.32, 0.18), true))
	return mesh

func _distant_tree_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.37
	trunk.height = 5.7
	trunk.radial_segments = 5
	_append_primitive(mesh, trunk, Transform3D(Basis(), Vector3(0, 2.85, 0)), _material(Color(0.23, 0.19, 0.15)))
	var crown := SphereMesh.new()
	crown.radial_segments = 7
	crown.rings = 4
	_append_primitive(mesh, crown, Transform3D(Basis().scaled(Vector3(2.85, 2.4, 2.3)), Vector3(0, 6.75, 0)), _foliage_material(Color(0.17, 0.29, 0.17)))
	return mesh

func _rock_mesh(style: String) -> Mesh:
	var stone: StandardMaterial3D
	if style in ["oak", "pine"]:
		stone = StandardMaterial3D.new()
		stone.albedo_texture = _mipmapped_texture("res://assets/forest/polyhaven/rock_01_diff_1k.jpg")
		stone.albedo_color = Color(0.62, 0.64, 0.60)
		stone.normal_texture = _mipmapped_texture("res://assets/forest/polyhaven/rock_01_nor_gl_1k.jpg")
		stone.normal_enabled = true
		stone.normal_scale = 0.42
		stone.uv1_triplanar = true
		stone.uv1_scale = Vector3(1.8, 1.8, 1.8)
		stone.roughness = 0.96
		stone.metallic = 0.0
	else:
		stone = _material(Color(0.29, 0.31, 0.28))
	# One shared, faceted mesh replaces the stacked primitives: displaced low
	# poly faces make an irregular boulder silhouette without extra draw calls.
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.55
	sphere.radial_segments = 16
	sphere.rings = 9
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var deformed := PackedVector3Array()
	deformed.resize(vertices.size())
	for index in vertices.size():
		var p := vertices[index]
		var n := p.normalized()
		var roughness := 1.0 + 0.13 * sin(n.x * 8.7 + n.y * 5.1) * cos(n.z * 7.9 - n.x * 3.4) + 0.055 * sin(n.y * 13.0 + n.z * 5.0)
		deformed[index] = Vector3(p.x * roughness * 1.05, p.y * roughness, p.z * roughness * 0.96) + Vector3(0.0, 0.76, 0.0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(stone)
	for tri in range(0, indices.size(), 3):
		var a: Vector3 = deformed[indices[tri]]
		var b: Vector3 = deformed[indices[tri + 1]]
		var c: Vector3 = deformed[indices[tri + 2]]
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot((a + b + c) / 3.0 - Vector3(0.0, 0.76, 0.0)) < 0.0:
			normal = -normal
		tool.set_normal(normal)
		tool.add_vertex(a)
		tool.set_normal(normal)
		tool.add_vertex(b)
		tool.set_normal(normal)
		tool.add_vertex(c)
	return tool.commit()

func _bush_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var clump := SphereMesh.new()
	clump.radial_segments = 6
	clump.rings = 4
	var leaf := _foliage_material(Color(0.19, 0.30, 0.15))
	var clumps: Array[Transform3D] = [
		Transform3D(Basis().scaled(Vector3(0.76, 0.60, 0.70)), Vector3(0, 0.58, 0)),
		Transform3D(Basis().scaled(Vector3(0.56, 0.53, 0.55)), Vector3(-0.47, 0.72, 0.17)),
		Transform3D(Basis().scaled(Vector3(0.61, 0.58, 0.56)), Vector3(0.38, 0.82, -0.30)),
	]
	_append_many(mesh, clump, clumps, leaf)
	var card := PlaneMesh.new()
	card.size = Vector2(1.55, 1.18)
	var transforms: Array[Transform3D] = []
	for side in 4:
		var angle := float(side) * TAU / 4.0
		transforms.append(Transform3D(Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(sin(angle) * 0.42, 0.70, cos(angle) * 0.42)))
	_append_many(mesh, card, transforms, _foliage_material(Color(0.20, 0.34, 0.17), true))
	return mesh

func _grass_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var blade := PlaneMesh.new()
	blade.size = Vector2(0.36, 0.38)
	var transforms: Array[Transform3D] = []
	for side in 3:
		var angle := float(side) * TAU / 3.0
		transforms.append(Transform3D(Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.19, 0)))
	_append_many(mesh, blade, transforms, _foliage_material(Color(0.20, 0.27, 0.13), true, true))
	return mesh

func _add_prop_collision(prop: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Trunk" if prop.kind == "tree" else "Rock"
	var shape_node := CollisionShape3D.new()
	var h: float = prop.height
	if prop.kind == "tree":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = prop.radius
		cylinder.height = h
		shape_node.shape = cylinder
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = prop.radius
		shape_node.shape = sphere
	body.position = prop.position + Vector3.UP * (h * 0.5)
	body.add_child(shape_node)
	_prop_bodies.add_child(body)
