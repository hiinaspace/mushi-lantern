class_name TerrainEnvironment
extends Node3D

const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage_luminescence.gdshader")

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

func build(world_surface: EnvironmentSurface) -> void:
	surface = world_surface
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
	terrain.assets.set_texture(0, _texture_asset("Meadow earth", Color(0.18, 0.24, 0.14)))
	terrain.assets.set_texture(1, _texture_asset("Rim stone", Color(0.24, 0.25, 0.22)))
	_mesh_assets = {
		"tree": _mesh_asset("Meadow tree", _tree_mesh(), _distant_tree_mesh()),
		"rock": _mesh_asset("Boulders", _rock_mesh()),
		"bush": _mesh_asset("Understory", _bush_mesh()),
		"grass": _mesh_asset("Meadow tufts", _grass_mesh()),
	}
	terrain.assets.set_mesh_asset(0, _mesh_assets.tree)
	terrain.assets.set_mesh_asset(1, _mesh_assets.rock)
	terrain.assets.set_mesh_asset(2, _mesh_assets.bush)
	terrain.assets.set_mesh_asset(3, _mesh_assets.grass)
	var origin := Vector3(-surface.size_m * 0.5, 0.0, -surface.size_m * 0.5)
	terrain.data.import_images([surface.get_terrain_height_image(), null, null], origin, 0.0, 1.0)
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
				if low_vegetation and decorative_index % 3 != 0:
					continue
			var mesh_id := 0
			match kind:
				"rock": mesh_id = 1
				"bush": mesh_id = 2
				"grass": mesh_id = 3
			var sc: float = prop.scale
			var basis := Basis(Vector3.UP, prop.yaw).scaled(Vector3.ONE * sc)
			groups[mesh_id].append(Transform3D(basis, prop.position))
		for mesh_id in 4:
			terrain.instancer.clear_by_mesh(mesh_id)
			terrain.instancer.add_transforms(mesh_id, groups[mesh_id])
		_instanced_vegetation_mode = vegetation_mode
	(_mesh_assets.grass as Terrain3DMeshAsset).cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_mesh_assets.bush as Terrain3DMeshAsset).cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	(_mesh_assets.tree as Terrain3DMeshAsset).cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	(_mesh_assets.tree as Terrain3DMeshAsset).lod0_range = 22.0 if low_vegetation else 38.0
	(_mesh_assets.grass as Terrain3DMeshAsset).lod0_range = 18.0 if low_vegetation else 32.0
	(_mesh_assets.bush as Terrain3DMeshAsset).lod0_range = 32.0 if low_vegetation else 60.0

func _texture_asset(label: String, color: Color) -> Terrain3DTextureAsset:
	var albedo := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	var normal := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 4:
			var shade := 0.94 if (x + y) % 2 == 0 else 1.03
			albedo.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, 0.5))
			normal.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.92))
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var asset := Terrain3DTextureAsset.new()
	asset.name = label
	asset.albedo_texture = ImageTexture.create_from_image(albedo)
	asset.normal_texture = ImageTexture.create_from_image(normal)
	asset.uv_scale = 0.12
	return asset

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
	material.set_shader_parameter("fleck_frequency", 6.0 if grass_blades else 3.0)
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
	trunk.top_radius = 0.20
	trunk.bottom_radius = 0.38
	trunk.height = 4.2
	trunk.radial_segments = 7
	_append_primitive(mesh, trunk, Transform3D(Basis(), Vector3(0, 2.1, 0)), bark)
	var crown := SphereMesh.new()
	crown.radial_segments = 9
	crown.rings = 5
	var clumps := [Vector3(-1.1, 4.6, 0.1), Vector3(1.0, 4.8, -0.5), Vector3(0.2, 5.3, 0.8)]
	var clump_transforms: Array[Transform3D] = []
	for clump in clumps:
		var basis := Basis().scaled(Vector3(1.55, 1.6, 1.25))
		clump_transforms.append(Transform3D(basis, clump))
	_append_many(mesh, crown, clump_transforms, leaf)
	var card := PlaneMesh.new()
	card.size = Vector2(2.8, 2.5)
	var card_transforms: Array[Transform3D] = []
	for clump in clumps:
		for side in 4:
			var angle := float(side) * TAU / 4.0
			var rotation := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -PI * 0.5)
			var offset := Vector3(sin(angle), 0.0, cos(angle)) * 0.9
			card_transforms.append(Transform3D(rotation, clump + offset))
	_append_many(mesh, card, card_transforms, _foliage_material(Color(0.18, 0.32, 0.18), true))
	return mesh

func _distant_tree_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.19
	trunk.bottom_radius = 0.35
	trunk.height = 4.1
	trunk.radial_segments = 5
	_append_primitive(mesh, trunk, Transform3D(Basis(), Vector3(0, 2.05, 0)), _material(Color(0.23, 0.19, 0.15)))
	var crown := SphereMesh.new()
	crown.radial_segments = 7
	crown.rings = 4
	_append_primitive(mesh, crown, Transform3D(Basis().scaled(Vector3(2.2, 1.9, 1.85)), Vector3(0, 4.9, 0)), _foliage_material(Color(0.17, 0.29, 0.17)))
	return mesh

func _rock_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	_append_primitive(mesh, rock, Transform3D(Basis().scaled(Vector3(1.05, 0.72, 0.88)), Vector3(0, 0.62, 0)), _material(Color(0.31, 0.32, 0.28)))
	return mesh

func _bush_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var clump := SphereMesh.new()
	clump.radial_segments = 7
	clump.rings = 4
	_append_primitive(mesh, clump, Transform3D(Basis().scaled(Vector3(0.9, 0.56, 0.75)), Vector3(0, 0.56, 0)), _foliage_material(Color(0.19, 0.30, 0.15)))
	var card := PlaneMesh.new()
	card.size = Vector2(1.4, 1.05)
	var transforms: Array[Transform3D] = []
	for side in 4:
		var angle := float(side) * TAU / 4.0
		transforms.append(Transform3D(Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(sin(angle) * 0.35, 0.62, cos(angle) * 0.35)))
	_append_many(mesh, card, transforms, _foliage_material(Color(0.20, 0.34, 0.17), true))
	return mesh

func _grass_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var blade := PlaneMesh.new()
	blade.size = Vector2(0.68, 0.55)
	var transforms: Array[Transform3D] = []
	for side in 3:
		var angle := float(side) * TAU / 3.0
		transforms.append(Transform3D(Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.27, 0)))
	_append_many(mesh, blade, transforms, _foliage_material(Color(0.29, 0.39, 0.18), true, true))
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
