extends SceneTree
var failures := 0
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(VFWorldGenerator.seed_from_text(" 42 ") == 42, "numeric seed trims whitespace")
	check(VFWorldGenerator.seed_from_text("Michał") == VFWorldGenerator.seed_from_text("Michał"), "UTF-8 seed is stable")
	check(VFWorldGenerator.seed_from_text("Michał") != VFWorldGenerator.seed_from_text("Michal"), "UTF-8 seed retains accents")
	var generator := VFWorldGenerator.new(20261022)
	var chunks: Dictionary = {}
	var counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var biomes := PackedInt32Array([0, 0, 0, 0])
	var min_height := 64
	var max_height := 0
	for z in range(-32, 32):
		for x in range(-32, 32):
			var col := generator.column(x, z)
			biomes[col.y] += 1
			min_height = mini(min_height, col.x)
			max_height = maxi(max_height, col.x)
	for y in range(4):
		for z in range(-2, 2):
			for x in range(-2, 2):
				var coord := Vector3i(x, y, z)
				var chunk := generator.generate_chunk(coord)
				chunks[coord] = chunk.blocks.duplicate()
				for block_id in chunk.blocks: counts[block_id] += 1
	print("WORLD_METRICS: biomes=%s heights=%d..%d blocks=%s entrance=%s floor=%d" % [biomes, min_height, max_height, counts, generator.entrance, generator.entrance_floor])
	check(biomes.count(0) == 0, "default seed has all four biomes")
	check(max_height - min_height > 10, "terrain has visible relief")
	check(counts[5] > 0 and counts[6] > 0, "trees have trunks and crowns")
	# Reverse generation order and varying work slices must produce identical bytes.
	var independent := VFWorldGenerator.new(20261022)
	var reversed: Array = chunks.keys()
	reversed.reverse()
	var deterministic := true
	for coord: Vector3i in reversed:
		independent.begin_chunk(coord)
		while not independent.process_slice(7): pass
		if independent.finish().blocks != chunks[coord]: deterministic = false
	check(deterministic, "all 64 sections invariant to order and slice size")
	var different := VFWorldGenerator.new(42)
	check(different.generate_chunk(Vector3i(0, 1, 0)).blocks != chunks[Vector3i(0, 1, 0)], "different seed changes terrain")
	var cave_clear := true
	var floor_solid := true
	for dz in range(-3, 23):
		var z := generator.entrance.y + dz
		var floor_y := generator.tunnel_floor(z)
		for dx in range(-1, 2):
			var x := generator.entrance.x + dx
			if generator.base_block(x, floor_y, z) == 0: floor_solid = false
			for dy in range(1, 4):
				if generator.base_block(x, floor_y + dy, z) != 0: cave_clear = false
	check(cave_clear and floor_solid, "continuous cave entrance has solid floor and three-block clearance")
	var bottom_solid := true
	var underground_air := 0
	for z in range(-32, 32):
		for x in range(-32, 32):
			if generator.base_block(x, 0, z) != 3 or generator.base_block(x, 1, z) != 3: bottom_solid = false
			for y in range(3, generator.column(x, z).x - 3):
				if generator.base_block(x, y, z) == 0: underground_air += 1
	check(bottom_solid, "generator retains solid bottom")
	check(underground_air > 100, "three-dimensional underground caves exist")
	check(generator.base_block(-33, 10, 0) == 0 and generator.base_block(0, 64, 0) == 0, "finite world bounds")
	# Destructive regeneration must remove existing physical shapes and queued jobs.
	var world := VFWorldManager.new()
	world.collision_enabled = true
	root.add_child(world)
	var block := VFChunkData.new()
	block.set_block(0, 0, 0, 3)
	world.add_chunk(Vector3i.ZERO, block)
	while world.pending_count() > 0: await physics_frame
	check(world.collision_section_count() == 1, "fixture has a live collider")
	world.mark_dirty(Vector3i.ZERO)
	world.clear_world()
	check(world.chunk_count() == 0 and world.mesh_count() == 0 and world.pending_count() == 0 and world.get_child_count() == 0 and world.collision_section_count() == 0, "regeneration removes data, colliders and pending mesh work")
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.5, 3, 0.5), Vector3(0.5, -1, 0.5), 1)
	check(world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "old collider is absent from physics space")
	world.add_chunk(Vector3i(1, 0, 0), block)
	while world.pending_count() > 0: await physics_frame
	check(world.get_block_global(Vector3i(16, 0, 0)) == 3 and world.collision_section_count() == 1, "new world can rebuild after clear")
	world.queue_free()
	await process_frame
	print("Stage 4: %d checks, %d failures" % [checks, failures])
	if failures == 0: print("VOXELFORGE_STAGE04_OK")
	quit(0 if failures == 0 else 1)
