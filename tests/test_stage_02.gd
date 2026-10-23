extends SceneTree

var failures := 0
var assertions := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)


func drain(world: VFWorldManager) -> void:
	var iterations := 0
	while world.pending_count() > 0 and iterations < 20000:
		var completed := world.process_mesh_queue()
		check(completed <= world.max_chunks_per_frame, "completion cap")
		iterations += 1
	check(world.pending_count() == 0, "queue converges")


func filled() -> VFChunkData:
	var chunk := VFChunkData.new()
	chunk.fill(VFChunkData.Block.ROCK)
	return chunk


func run() -> void:
	check_coordinates()
	check_seams()
	check_mutations()
	check_incremental_mesh()
	check_winding()
	print("Stage 02: %d assertions, %d failures" % [assertions, failures])
	if failures == 0: print("VOXELFORGE_STAGE02_OK")
	quit(0 if failures == 0 else 1)


func check_coordinates() -> void:
	for n: int in [-33, -32, -17, -16, -1, 0, 15, 16, 31, 32]:
		var p := Vector3i(n, n, n)
		var expected := floori(float(n) / 16.0)
		var coord := VFWorldManager.chunk_coord(p)
		var local := VFWorldManager.local_coord(p)
		check(coord == Vector3i(expected, expected, expected), "negative floor %d" % n)
		check(local.x >= 0 and local.x < 16, "local range %d" % n)
		check(coord * 16 + local == p, "coordinate round trip")
	var world := VFWorldManager.new()
	check(world.set_block_global(Vector3i(-17, -1, 16), VFChunkData.Block.WOOD), "global write")
	check(world.get_block_global(Vector3i(-17, -1, 16)) == VFChunkData.Block.WOOD, "negative global read")
	check(not world.set_block_global(Vector3i.ZERO, 256), "invalid ID rejected")
	world.set_block_global(Vector3i(200, 200, 200), VFChunkData.Block.AIR)
	check(world.chunk_count() == 1, "air write does not allocate")
	world.free()


func check_seams() -> void:
	for direction: Vector3i in VFChunkMesher.DIRECTIONS:
		var world := VFWorldManager.new()
		world.max_chunks_per_frame = 1
		var base := Vector3i(-1, -1, -1)
		world.add_chunk(base, filled())
		world.add_chunk(base + direction, filled())
		check(world.pending_count() == 2, "queue deduplicates adjacent insertions")
		drain(world)
		check(world.visible_faces() == 2560, "two full chunks cull 512 shared faces: %s" % direction)
		check(world.solid_blocks() == 8192, "solid counts")
		world.remove_chunk(base + direction)
		drain(world)
		check(world.visible_faces() == 1536, "removal exposes neighbor face")
		world.add_chunk(base + direction, filled())
		drain(world)
		check(world.visible_faces() == 2560, "restoration hides seam again")
		world.free()


func check_mutations() -> void:
	var world := VFWorldManager.new()
	world.add_chunk(Vector3i.ZERO, filled())
	world.add_chunk(Vector3i.RIGHT, filled())
	world.add_chunk(Vector3i.UP, filled())
	world.add_chunk(Vector3i.BACK, filled())
	drain(world)
	world.set_block_global(Vector3i(5, 5, 5), VFChunkData.Block.AIR)
	check(world.pending_count() == 1, "interior edit rebuilds only owner")
	drain(world)
	world.set_block_global(Vector3i(15, 15, 15), VFChunkData.Block.AIR)
	check(world.pending_count() == 4, "corner edit rebuilds owner and 3 axial neighbors")
	world.mark_dirty_with_neighbors(Vector3i.ZERO)
	check(world.pending_count() == 4, "dirty duplicates are coalesced")
	drain(world)
	var before := world.rebuilt_total
	world.set_block_global(Vector3i(15, 15, 15), VFChunkData.Block.AIR)
	check(world.pending_count() == 0 and world.rebuilt_total == before, "unchanged write is no-op")
	world.free()
	# Mutation after a partially built section must discard stale boundary faces.
	world = VFWorldManager.new()
	world.mesh_budget_usec = 100
	world.add_chunk(Vector3i.ZERO, filled())
	world.process_mesh_queue()
	check(world.pending_count() == 1 and world.mesh_count() == 0, "meshing spans frames")
	world.add_chunk(Vector3i.RIGHT, filled())
	drain(world)
	check(world.visible_faces() == 2560, "neighbor load invalidates in-flight mesh")
	world.add_chunk(Vector3i.ZERO, VFChunkData.new())
	drain(world)
	check(world.visible_faces() == 1536, "replacement with air clears old mesh")
	world.mark_dirty(Vector3i.RIGHT)
	world.process_mesh_queue()
	world.remove_chunk(Vector3i.RIGHT)
	drain(world)
	check(world.chunk_count() == 1 and world.visible_faces() == 0, "remove active chunk leaves no stale render")
	world.free()


func check_incremental_mesh() -> void:
	var chunk := VFChunkData.new()
	chunk.populate_demo()
	var incremental := VFChunkMesher.new()
	incremental.begin(chunk)
	var steps := 0
	while not incremental.process_slice(37): steps += 1
	check(steps > 1, "incremental steps")
	var a := incremental.finish()
	var sync := VFChunkMesher.new()
	var b := sync.build_mesh(chunk)
	check(incremental.last_visible_faces == sync.last_visible_faces, "incremental face count")
	check(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "same vertices across slice sizes")
	check(a.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == b.surface_get_arrays(0)[Mesh.ARRAY_INDEX], "same indices across slice sizes")


func check_winding() -> void:
	var chunk := VFChunkData.new()
	chunk.set_block(0, 0, 0, VFChunkData.Block.ROCK)
	var arrays := VFChunkMesher.new().build_mesh(chunk).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		check((vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(normals[a]) < 0, "clockwise triangle %d" % i)
