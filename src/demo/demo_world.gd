extends RefCounted
class_name VFDemoWorld
## Fixed, authored 64 x 32 x 64 test landscape. Seed/noise/biomes are stage 4.


static func height_at(x: int, z: int) -> int:
	var height := 3
	if absi(x + 5) + absi(z + 5) < 35:
		height = 6
	if absi(x + 9) + absi(z + 9) < 22:
		height = 10
	if absi(x + 10) + absi(z + 11) < 14:
		height = 14
	if absi(x + 11) + absi(z + 11) < 7:
		height = 18
	if x > 12 and z < -6:
		height = 8
	if absi(x - 21) + absi(z + 17) < 8:
		height = 12
	if absi(z - 12) <= 2 and x < 25:
		height = 2
	return height


static func populate(world: VFWorldManager) -> void:
	var sections: Dictionary = {}
	for cy in range(2):
		for cz in range(-2, 2):
			for cx in range(-2, 2):
				sections[Vector3i(cx, cy, cz)] = VFChunkData.new()
	for x in range(-32, 32):
		for z in range(-32, 32):
			var top := height_at(x, z)
			for y in range(top + 1):
				var kind := VFChunkData.Block.ROCK
				if y >= top - 1:
					kind = VFChunkData.Block.SOIL
				if y == top:
					kind = VFChunkData.Block.SAND if top <= 3 else VFChunkData.Block.GRASS
				_put(sections, Vector3i(x, y, z), kind)
	for tree: Vector2i in [Vector2i(-21, -13), Vector2i(-2, -18), Vector2i(7, -7), Vector2i(23, -17), Vector2i(-18, 22), Vector2i(10, 23), Vector2i(-24, 3), Vector2i(16, 3)]:
		var base := height_at(tree.x, tree.y) + 1
		for y in range(base, base + 5):
			_put(sections, Vector3i(tree.x, y, tree.y), VFChunkData.Block.WOOD)
		for y in range(base + 3, base + 7):
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if absi(dx) + absi(dz) + absi(y - base - 4) <= 4:
						_put(sections, Vector3i(tree.x + dx, y, tree.y + dz), VFChunkData.Block.LEAVES)
	for coord: Vector3i in sections:
		world.add_chunk(coord, sections[coord])


static func _put(sections: Dictionary, position: Vector3i, kind: int) -> void:
	var coord := VFWorldManager.chunk_coord(position)
	if sections.has(coord):
		var local := VFWorldManager.local_coord(position)
		var chunk: VFChunkData = sections[coord]
		chunk.set_block(local.x, local.y, local.z, kind)
