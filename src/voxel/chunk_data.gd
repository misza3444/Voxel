extends RefCounted
class_name VFChunkData
## One 16x16x16 voxel section; X is the fastest-changing coordinate.
## Own data layout, not an on-disk Minecraft format.

const SIZE: int = 16
const VOLUME: int = SIZE * SIZE * SIZE

enum Block { AIR, GRASS, SOIL, ROCK, SAND, WOOD, LEAVES }

var blocks: PackedByteArray = PackedByteArray()


func _init() -> void:
	blocks.resize(VOLUME)  # Initialized to AIR (0).


static func contains(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < SIZE and z >= 0 and z < SIZE


static func index_of(x: int, y: int, z: int) -> int:
	return x + SIZE * (z + SIZE * y)


func get_block(x: int, y: int, z: int) -> int:
	# Local out-of-bounds = air; the stage 2 mesher resolves world neighbors.
	if not contains(x, y, z):
		return Block.AIR
	return blocks[index_of(x, y, z)]


func set_block(x: int, y: int, z: int, block_id: int) -> bool:
	if not contains(x, y, z) or block_id < 0 or block_id > 255:
		return false
	blocks[index_of(x, y, z)] = block_id
	return true


func fill(block_id: int) -> void:
	assert(block_id >= 0 and block_id <= 255)
	blocks.fill(block_id)


func populate_demo() -> void:
	## Hand-authored composition, not procedural world generation.
	fill(Block.AIR)
	for x in range(SIZE):
		for z in range(SIZE):
			var top := 2
			if x >= 2 and x <= 13 and z >= 2 and z <= 13:
				top = 3
			if x >= 4 and x <= 11 and z >= 4 and z <= 11:
				top = 4
			if x >= 7 and x <= 10 and z >= 6 and z <= 9:
				top = 5
			for y in range(top + 1):
				var kind := Block.ROCK if y < top - 1 else Block.SOIL
				if y == top:
					kind = Block.SAND if top == 2 else Block.GRASS
				set_block(x, y, z, kind)

	# Small handmade tree on the terrace.
	for y in range(5, 9):
		set_block(5, y, 6, Block.WOOD)
	for y in range(8, 11):
		for x in range(3, 8):
			for z in range(4, 9):
				var distance := absi(x - 5) + absi(z - 6) + absi(y - 9)
				if distance <= 3:
					set_block(x, y, z, Block.LEAVES)
	set_block(5, 10, 6, Block.LEAVES)

	# A few stones as identifiable points of interest.
	set_block(12, 4, 5, Block.ROCK)
	set_block(12, 5, 5, Block.ROCK)
	set_block(11, 4, 5, Block.ROCK)
	set_block(3, 4, 11, Block.ROCK)
