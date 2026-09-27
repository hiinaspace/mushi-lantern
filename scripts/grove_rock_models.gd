class_name GroveRockModels
extends RefCounted

## Optional low-detail Poly Haven rock kit. TerrainEnvironment can register
## these as separate Terrain3DMeshAssets and assign variant % 3 to their IDs.
const ROCK_SCENES := [
	preload("res://assets/forest/polyhaven/rock_models/moss_rock01.gltf"),
	preload("res://assets/forest/polyhaven/rock_models/moss_rock03.gltf"),
	preload("res://assets/forest/polyhaven/rock_models/moss_rock05.gltf"),
]
const CLIFF_SCENE: PackedScene = preload("res://assets/forest/polyhaven/rock_models/cliff_face.gltf")
## Source meshes have their lowest vertex at y=0; these are their local heights.
const ROCK_HEIGHTS := [0.876, 1.043, 0.805]


static func rock_mesh(variant: int) -> Mesh:
	return _mesh_from_scene(ROCK_SCENES[posmod(variant, ROCK_SCENES.size())] as PackedScene)


static func rock_height(variant: int) -> float:
	return ROCK_HEIGHTS[posmod(variant, ROCK_HEIGHTS.size())]


static func cliff_mesh() -> Mesh:
	return _mesh_from_scene(CLIFF_SCENE)


static func _mesh_from_scene(scene: PackedScene) -> Mesh:
	if scene == null:
		push_error("Missing optional rock scene")
		return null
	var instance := scene.instantiate()
	var candidates := instance.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not candidates.is_empty():
		mesh = (candidates[0] as MeshInstance3D).mesh
	instance.free()
	return mesh
