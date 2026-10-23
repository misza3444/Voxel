extends RefCounted
class_name VFWorldGenerator
## Generator v1: global coordinates, isolated noise channels, no global RNG.
const VERSION := 1
const MIN_XZ := -32
const MAX_XZ := 32
const HEIGHT := 64
const BIOME_NAMES := ["Łąka", "Las", "Wydmy", "Skaliste wzgórza"]
enum Biome { MEADOW, FOREST, DUNES, HIGHLANDS }
var world_seed := 20261022
var entrance := Vector2i.ZERO
var entrance_floor := 0
var _height: FastNoiseLite
var _detail: FastNoiseLite
var _moisture: FastNoiseLite
var _cave_a: FastNoiseLite
var _cave_b: FastNoiseLite
var _columns: Dictionary = {}
var _chunk: VFChunkData
var _coord := Vector3i.ZERO
var _column_index := 0

static func seed_from_text(value: String) -> int:
	var clean := value.strip_edges()
	if clean.is_valid_int(): return int(clean) & 0x7fffffff
	var hash_value := 2166136261
	for byte in clean.to_utf8_buffer(): hash_value = ((hash_value ^ byte) * 16777619) & 0xffffffff
	return hash_value & 0x7fffffff

func _init(seed_value: int = 20261022) -> void:
	configure(seed_value)

func configure(seed_value: int) -> void:
	world_seed = seed_value & 0x7fffffff
	_columns.clear()
	_height = noise(11, 0.023, 3)
	_detail = noise(37, 0.075, 2)
	_moisture = noise(71, 0.038, 2)
	_cave_a = noise(101, 0.065, 2)
	_cave_b = noise(151, 0.065, 2)
	entrance = Vector2i(int(cell_hash(7, 11) % 17) - 8, int(cell_hash(13, 3) % 7) - 16)
	entrance_floor = column(entrance.x, entrance.y).x - 1

func noise(offset: int, frequency: float, octaves: int) -> FastNoiseLite:
	var item := FastNoiseLite.new()
	item.seed = (world_seed + offset) & 0x7fffffff
	item.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	item.frequency = frequency
	item.fractal_type = FastNoiseLite.FRACTAL_FBM
	item.fractal_octaves = octaves
	item.fractal_gain = 0.5
	item.fractal_lacunarity = 2.0
	return item

func cell_hash(x: int, z: int) -> int:
	var h := (world_seed ^ (x * 374761393) ^ (z * 668265263)) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return (h ^ (h >> 16)) & 0x7fffffff

func column(x: int, z: int) -> Vector2i:
	var key := Vector2i(x, z)
	if _columns.has(key): return _columns[key]
	var broad := _height.get_noise_2d(x, z)
	var height_value := clampi(roundi(23.0 + broad * 19.0 + _detail.get_noise_2d(x, z) * 3.0), 9, 44)
	var moisture := _moisture.get_noise_2d(x, z)
	var biome := Biome.MEADOW
	if height_value >= 29: biome = Biome.HIGHLANDS
	elif moisture < -0.16: biome = Biome.DUNES
	elif moisture > 0.12: biome = Biome.FOREST
	var result := Vector2i(height_value, biome)
	_columns[key] = result
	return result

func tunnel_floor(z: int) -> int:
	return maxi(4, entrance_floor - floori(maxi(0, z - entrance.y) / 2.0))

func base_block(x: int, y: int, z: int) -> int:
	if x < MIN_XZ or x >= MAX_XZ or z < MIN_XZ or z >= MAX_XZ or y < 0 or y >= HEIGHT: return VFChunkData.Block.AIR
	if y <= 1: return VFChunkData.Block.ROCK
	var surface := column(x, z)
	var dz := z - entrance.y
	# A three-wide descending access passage, with a solid walkable floor.
	if absi(x - entrance.x) <= 1 and dz >= -3 and dz <= 22:
		var floor_y := tunnel_floor(z)
		if y == floor_y: return VFChunkData.Block.ROCK
		if y > floor_y and (y <= floor_y + 3 or dz < 1): return VFChunkData.Block.AIR
	var chamber_center := Vector3(entrance.x, tunnel_floor(entrance.y + 22) + 2, entrance.y + 22)
	var relative := (Vector3(x, y, z) - chamber_center) / Vector3(5.5, 2.5, 5.5)
	if relative.length_squared() < 1.0 and y >= 3: return VFChunkData.Block.AIR
	if y > surface.x: return VFChunkData.Block.AIR
	if y >= 3 and y < surface.x - 3:
		var a := _cave_a.get_noise_3d(x, y, z) / 0.13
		var b := _cave_b.get_noise_3d(x, y, z) / 0.16
		if a * a + b * b < 1.0: return VFChunkData.Block.AIR
	if surface.y == Biome.DUNES and y >= surface.x - 3: return VFChunkData.Block.SAND
	if surface.y == Biome.HIGHLANDS: return VFChunkData.Block.ROCK
	if y == surface.x: return VFChunkData.Block.GRASS
	if y >= surface.x - 3: return VFChunkData.Block.SOIL
	return VFChunkData.Block.ROCK

func begin_chunk(coord: Vector3i) -> void:
	_coord = coord
	_chunk = VFChunkData.new()
	_column_index = 0

func process_slice(max_columns: int = 4) -> bool:
	assert(_chunk != null)
	var origin := _coord * VFChunkData.SIZE
	var end := mini(256, _column_index + maxi(1, max_columns))
	while _column_index < end:
		var x := _column_index % 16
		var z := _column_index / 16
		for y in range(16): _chunk.set_block(x, y, z, base_block(origin.x + x, origin.y + y, origin.z + z))
		_column_index += 1
	return _column_index == 256

func finish() -> VFChunkData:
	assert(_column_index == 256)
	decorate_trees()
	return _chunk

func generate_chunk(coord: Vector3i) -> VFChunkData:
	begin_chunk(coord)
	while not process_slice(256): pass
	return finish()

func decorate_trees() -> void:
	var origin := _coord * 16
	# Anchors outside the section are included so crowns cross all boundaries.
	for gz in range((origin.z - 2) >> 3, ((origin.z + 17) >> 3) + 1):
		for gx in range((origin.x - 2) >> 3, ((origin.x + 17) >> 3) + 1):
			var h := cell_hash(gx, gz)
			var x := gx * 8 + 1 + h % 6
			var z := gz * 8 + 1 + (h >> 4) % 6
			if x < MIN_XZ + 2 or x >= MAX_XZ - 2 or z < MIN_XZ + 2 or z >= MAX_XZ - 2: continue
			if absi(x - entrance.x) < 5 and z >= entrance.y - 6 and z <= entrance.y + 24: continue
			var surface := column(x, z)
			if surface.y != Biome.FOREST and surface.y != Biome.MEADOW: continue
			if (h >> 8) % 100 >= (75 if surface.y == Biome.FOREST else 15): continue
			var top := surface.x + 4 + (h >> 16) % 3
			for y in range(surface.x + 1, top + 1): decorate_block(Vector3i(x, y, z), VFChunkData.Block.WOOD)
			for dy in range(-2, 2):
				for dz in range(-2, 3):
					for dx in range(-2, 3):
						if absi(dx) + absi(dz) + maxi(0, dy) > 3: continue
						decorate_block(Vector3i(x + dx, top + dy, z + dz), VFChunkData.Block.LEAVES)

func decorate_block(global: Vector3i, block_id: int) -> void:
	var local := global - _coord * 16
	if not VFChunkData.contains(local.x, local.y, local.z): return
	var existing := _chunk.get_block(local.x, local.y, local.z)
	if existing == VFChunkData.Block.AIR or (block_id == VFChunkData.Block.WOOD and existing == VFChunkData.Block.LEAVES):
		_chunk.set_block(local.x, local.y, local.z, block_id)
