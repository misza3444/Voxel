extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", title)
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func drain(world: VFWorldManager) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while world.pending_count() > 0 and Time.get_ticks_msec() < deadline: await physics_frame
	check(world.pending_count() == 0, "queue converges")
	await frames(3)
func drive(player: VFPlayerController, count: int, axes := Vector2.ZERO, jump := false) -> void:
	for i in range(count):
		await physics_frame
		player.step_motion(1.0 / 60.0, axes, jump and i == 0, false)
func run() -> void:
	test_rays()
	await test_physics()
	print("Stage 03: %d checks, %d failures" % [checks, failures])
	if failures == 0: print("VOXELFORGE_STAGE03_OK")
	quit(0 if failures == 0 else 1)
func test_rays() -> void:
	var world := VFWorldManager.new()
	world.set_block_global(Vector3i.ZERO, 3)
	for direction: Vector3i in VFChunkMesher.DIRECTIONS:
		var hit := VFVoxelRaycast.cast(world, Vector3.ONE * 0.5 + Vector3(direction) * 3, -Vector3(direction))
		check(not hit.is_empty(), "ray hits %s" % direction)
		if not hit.is_empty():
			check(hit.block == Vector3i.ZERO and hit.normal == direction and hit.place == direction, "face and placement")
			check(is_equal_approx(hit.distance, 2.5), "ray distance")
	check(VFVoxelRaycast.cast(world, Vector3(0.5, 0.5, 3.5), Vector3.FORWARD, 2.49).is_empty(), "reach enforced")
	check(VFVoxelRaycast.cast(world, Vector3.ZERO, Vector3.ZERO).is_empty(), "zero ray")
	check(VFVoxelRaycast.cast(world, Vector3(-2, 2, -2), Vector3.RIGHT).is_empty(), "parallel empty ray")
	var inside := VFVoxelRaycast.cast(world, Vector3.ONE * 0.5, Vector3.UP)
	check(inside.normal == Vector3i.ZERO and inside.distance == 0, "inside block")
	world.set_block_global(Vector3i(-17, 2, 16), 5)
	var negative := VFVoxelRaycast.cast(world, Vector3(-14.5, 2.5, 16.5), Vector3.LEFT)
	check(not negative.is_empty() and negative.block == Vector3i(-17, 2, 16), "negative boundary")
	world.set_block_global(Vector3i.ONE, 3)
	world.set_block_global(Vector3i.ZERO, 0)
	var diagonal := VFVoxelRaycast.cast(world, Vector3.ONE * 0.5, Vector3.ONE)
	check(not diagonal.is_empty() and diagonal.block == Vector3i.ONE, "corner tie")
	world.free()
func test_physics() -> void:
	var world := VFWorldManager.new()
	world.collision_enabled = true
	root.add_child(world)
	for x in range(-5, 21):
		for z in range(-4, 5): world.set_block_global(Vector3i(x, 0, z), 3)
	for y in range(1, 3):
		for z in range(-2, 3): world.set_block_global(Vector3i(3, y, z), 5)
	await drain(world)
	check(world.collision_section_count() > 0, "colliders exist")
	var player := VFPlayerController.new()
	player.world = world
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(-2.5, 4, 0.5)
	await drive(player, 100)
	check(player.is_on_floor() and absf(player.position.y - 1) < 0.02, "land on ground")
	await drive(player, 90, Vector2.RIGHT)
	check(player.is_on_floor() and player.position.x > 2.5 and player.position.x < 2.72, "seam and wall")
	player.position = Vector3(-1.5, 1.01, 0.5)
	player.velocity = Vector3.ZERO
	await drive(player, 4)
	await drive(player, 18, Vector2.ZERO, true)
	check(player.position.y > 1.8, "jump height")
	await drive(player, 70)
	check(player.is_on_floor() and absf(player.position.y - 1) < 0.02, "jump landing")
	player.position = Vector3(14.5, 1.01, 3.5)
	player.velocity = Vector3.ZERO
	await drive(player, 40, Vector2.RIGHT)
	check(player.position.x > 16 and player.is_on_floor(), "X=16 seam")
	player.position = Vector3(0.5, 1.01, 0.5)
	player.velocity = Vector3.ZERO
	await drive(player, 4)
	player.camera.rotation.x = -PI * 0.5
	check(not player.place_target(), "no placement into player")
	check(player.overlaps_block(Vector3i(0, 1, 0)), "overlap")
	check(not player.overlaps_block(Vector3i(1, 1, 0)), "adjacent space")
	check(player.break_target(), "break floor")
	check(world.get_block_global(Vector3i.ZERO) == 0, "source changed")
	await drain(world)
	await drive(player, 40)
	check(player.position.y < 0, "old collider removed")
	world.set_block_global(Vector3i.ZERO, 3)
	await drain(world)
	player.position = Vector3(0.5, 1.01, 0.5)
	player.velocity = Vector3.ZERO
	player.camera.look_at(Vector3(1.5, 0.5, 0.5))
	player.select_material(4)
	player.update_target()
	check(not player.target.is_empty() and player.target.place == Vector3i(1, 1, 0), "placement cell")
	check(player.place_target(), "place wood")
	check(world.get_block_global(Vector3i(1, 1, 0)) == 5, "material stored")
	await drain(world)
	await drive(player, 40, Vector2.RIGHT)
	check(player.position.x < 0.72, "new collider blocks movement")
	world.remove_chunk(Vector3i(1, 0, 0))
	await drain(world)
	player.position = Vector3(17.5, 1.1, 0.5)
	player.velocity = Vector3.ZERO
	await drive(player, 40)
	check(player.position.y < 0, "unload collider")
	player.queue_free()
	world.queue_free()
	await frames(2)
