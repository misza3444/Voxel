extends RefCounted
class_name VFChunkMesher
## Emits only faces next to air. Exactly 4 vertices and 6 indices per face.
## A single ArrayMesh surface is shared by all opaque block types.

const DIRECTIONS = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# Outward CCW corner order; indices reverse it for Godot clockwise front faces.
const CORNERS = [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]

var last_visible_faces: int = 0
var last_solid_blocks: int = 0


var _chunk: VFChunkData
var _origin := Vector3i.ZERO
var _world_block := Callable()
var _cursor: int = 0
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func begin(chunk: VFChunkData, origin := Vector3i.ZERO, world_block := Callable()) -> void:
	# The callback accepts a GLOBAL Vector3i; only boundary samples need it.
	_chunk = chunk
	_origin = origin
	_world_block = world_block
	_cursor = 0
	last_visible_faces = 0
	last_solid_blocks = 0
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_uvs = PackedVector2Array()
	_indices = PackedInt32Array()


func process_slice(max_voxels: int = 32) -> bool:
	assert(_chunk != null)
	var end := mini(_cursor + maxi(max_voxels, 1), VFChunkData.VOLUME)
	while _cursor < end:
		var x := _cursor % 16
		var z := (_cursor >> 4) % 16
		var y := _cursor >> 8
		_cursor += 1
		var block := _chunk.get_block(x, y, z)
		if block == VFChunkData.Block.AIR:
			continue
		last_solid_blocks += 1
		for face in range(6):
			var neighbor: Vector3i = Vector3i(x, y, z) + DIRECTIONS[face]
			var neighbor_block := _chunk.get_block(neighbor.x, neighbor.y, neighbor.z)
			if not VFChunkData.contains(neighbor.x, neighbor.y, neighbor.z) and _world_block.is_valid():
				neighbor_block = int(_world_block.call(_origin + neighbor))
			if neighbor_block == VFChunkData.Block.AIR:
				append_face(_vertices, _normals, _colors, _uvs, _indices, Vector3(x, y, z), block, face)
				last_visible_faces += 1
	return _cursor == VFChunkData.VOLUME


func finish() -> ArrayMesh:
	assert(_cursor == VFChunkData.VOLUME)
	var mesh := ArrayMesh.new()
	if _vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func build_mesh(chunk: VFChunkData, origin := Vector3i.ZERO, world_block := Callable()) -> ArrayMesh:
	# Synchronous compatibility path for stage 1 and focused tests.
	begin(chunk, origin, world_block)
	process_slice(VFChunkData.VOLUME)
	return finish()


static func append_face(
	vertices: PackedVector3Array, normals: PackedVector3Array,
	colors: PackedColorArray, uvs: PackedVector2Array,
	indices: PackedInt32Array, origin: Vector3, block: int, face: int
) -> void:
	var start := vertices.size()
	var direction: Vector3i = DIRECTIONS[face]
	var normal := Vector3(direction.x, direction.y, direction.z)
	var color := block_color(block, face)
	var face_uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(4):
		vertices.append(origin + CORNERS[face][i])
		normals.append(normal)
		colors.append(color)
		uvs.append(face_uvs[i])
	indices.append_array(PackedInt32Array([
		start, start + 2, start + 1, start, start + 3, start + 2
	]))


static func block_color(block: int, face: int) -> Color:
	var base := Color("8e9da5")
	match block:
		VFChunkData.Block.GRASS:
			base = Color("6fc487") if face == 2 else Color("a77a53")
		VFChunkData.Block.SOIL:
			base = Color("95654d")
		VFChunkData.Block.ROCK:
			base = Color("879ca7")
		VFChunkData.Block.SAND:
			base = Color("ebce87")
		VFChunkData.Block.WOOD:
			base = Color("946b48")
		VFChunkData.Block.LEAVES:
			base = Color("3f9c70")
	var shade := 1.0
	match face:
		0: shade = 0.83
		1: shade = 0.70
		2: shade = 1.00
		3: shade = 0.52
		4: shade = 0.91
		5: shade = 0.76
	return Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
