extends SceneTree
## Run: godot --headless --path . --script res://tests/test_stage_01.gd
## Exits nonzero on a failing assertion (no third-party test framework).

const Chunk = preload("res://src/voxel/chunk_data.gd")
const Mesher = preload("res://src/voxel/chunk_mesher.gd")


func _initialize() -> void:
	var failures := 0
	failures += check_storage()
	failures += check_empty_mesh()
	failures += check_single_block()
	failures += check_adjacent_blocks()
	failures += check_filled_section()
	if failures == 0:
		print("PASS: 5 chunk/mesh test cases")
	else:
		push_error("FAILED: %d assertions" % failures)
	quit(0 if failures == 0 else 1)


func check_storage() -> int:
	var chunk = Chunk.new()
	var failures := 0
	failures += verify(chunk.blocks.size() == 4096, "4096 bytes in section")
	failures += verify(chunk.get_block(0, 0, 0) == Chunk.Block.AIR, "zero initialized")
	failures += verify(chunk.set_block(15, 15, 15, Chunk.Block.ROCK), "last voxel writable")
	failures += verify(chunk.get_block(15, 15, 15) == Chunk.Block.ROCK, "read after write")
	failures += verify(not chunk.set_block(16, 0, 0, Chunk.Block.ROCK), "out-of-bounds writes rejected")
	failures += verify(chunk.get_block(-1, 0, 0) == Chunk.Block.AIR, "out-of-bounds reads air")
	failures += verify(Chunk.index_of(15, 15, 15) == 4095, "flattened index")
	return failures


func check_empty_mesh() -> int:
	var mesher = Mesher.new()
	var mesh = mesher.build_mesh(Chunk.new())
	return verify(mesher.last_visible_faces == 0 and mesh.get_surface_count() == 0, "empty section")


func check_single_block() -> int:
	var chunk = Chunk.new()
	chunk.set_block(7, 7, 7, Chunk.Block.GRASS)
	var mesher = Mesher.new()
	var mesh = mesher.build_mesh(chunk)
	var fail := verify(mesher.last_visible_faces == 6, "one block = six faces")
	fail += verify(mesh.surface_get_array_index_len(0) == 36, "one block = 12 triangles")
	fail += verify(mesh.surface_get_array_len(0) == 24, "one block = 24 vertices")
	return fail


func check_adjacent_blocks() -> int:
	var chunk = Chunk.new()
	chunk.set_block(7, 7, 7, Chunk.Block.ROCK)
	chunk.set_block(8, 7, 7, Chunk.Block.ROCK)
	var mesher = Mesher.new()
	var mesh = mesher.build_mesh(chunk)
	var fail := verify(mesher.last_visible_faces == 10, "shared interior faces culled")
	fail += verify(mesh.surface_get_array_index_len(0) == 60, "two blocks = 20 triangles")
	return fail


func check_filled_section() -> int:
	var chunk = Chunk.new()
	chunk.fill(Chunk.Block.ROCK)
	var mesher = Mesher.new()
	var mesh = mesher.build_mesh(chunk)
	var fail := verify(mesher.last_solid_blocks == 4096, "solid count")
	fail += verify(mesher.last_visible_faces == 1536, "full section = 6*16*16 faces")
	fail += verify(mesh.surface_get_array_index_len(0) == 9216, "full section = 3072 triangles")
	return fail


func verify(ok: bool, label: String) -> int:
	if ok:
		print("  OK: ", label)
		return 0
	printerr("  FAIL: ", label)
	return 1
