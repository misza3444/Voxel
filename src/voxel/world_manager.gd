extends Node3D
class_name VFWorldManager
## Main-thread section store. Soft budget: 32 voxels and mesh upload are indivisible.

signal chunk_rebuilt(coord: Vector3i)

@export var collision_enabled: bool = false

@export_range(100, 16000, 100) var mesh_budget_usec: int = 3000
@export_range(1, 8, 1) var max_chunks_per_frame: int = 2

var last_mesh_usec: int = 0
var rebuilt_total: int = 0
var _chunks: Dictionary = {}
var _views: Dictionary = {}
var _counts: Dictionary = {}
var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _active: VFChunkMesher
var _active_coord := Vector3i.ZERO
var _material: StandardMaterial3D


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0


static func chunk_coord(block: Vector3i) -> Vector3i:
	# Arithmetic right shift = exact floor division by 16, including negative ints.
	return Vector3i(block.x >> 4, block.y >> 4, block.z >> 4)


static func local_coord(block: Vector3i) -> Vector3i:
	return block - chunk_coord(block) * VFChunkData.SIZE


func get_chunk(coord: Vector3i) -> VFChunkData:
	# Borrowed data: external bulk edits require mark_dirty_with_neighbors().
	return _chunks.get(coord) as VFChunkData


func get_block_global(block: Vector3i) -> int:
	var chunk := get_chunk(chunk_coord(block))
	if chunk == null:
		return VFChunkData.Block.AIR
	var local := local_coord(block)
	return chunk.get_block(local.x, local.y, local.z)


func add_chunk(coord: Vector3i, chunk: VFChunkData) -> void:
	assert(chunk != null)
	_chunks[coord] = chunk
	mark_dirty_with_neighbors(coord)


func remove_chunk(coord: Vector3i) -> bool:
	if not _chunks.has(coord):
		return false
	_chunks.erase(coord)
	_queue.erase(coord)
	_queued.erase(coord)
	if _active != null and _active_coord == coord:
		_active = null
	if _views.has(coord):
		var view: MeshInstance3D = _views[coord]
		remove_child(view)
		view.queue_free()
		_views.erase(coord)
	_counts.erase(coord)
	mark_dirty_with_neighbors(coord)
	return true


func set_block_global(block: Vector3i, block_id: int) -> bool:
	if block_id < 0 or block_id > 255:
		return false
	var coord := chunk_coord(block)
	var chunk := get_chunk(coord)
	if chunk == null:
		if block_id == VFChunkData.Block.AIR:
			return true
		chunk = VFChunkData.new()
		_chunks[coord] = chunk
	var local := local_coord(block)
	if chunk.get_block(local.x, local.y, local.z) == block_id:
		return true
	chunk.set_block(local.x, local.y, local.z, block_id)
	mark_dirty(coord)
	# Only face-adjacent sections can change. No diagonal rebuilds at corners.
	for direction: Vector3i in VFChunkMesher.DIRECTIONS:
		var neighbor := local + direction
		if not VFChunkData.contains(neighbor.x, neighbor.y, neighbor.z):
			mark_dirty(coord + direction)
	return true


func mark_dirty_with_neighbors(coord: Vector3i) -> void:
	mark_dirty(coord)
	for direction: Vector3i in VFChunkMesher.DIRECTIONS:
		mark_dirty(coord + direction)


func mark_dirty(coord: Vector3i) -> void:
	if not _chunks.has(coord):
		return
	if _active != null and _active_coord == coord:
		# A neighbor edit can invalidate partially collected faces, too.
		_active = null
	if not _queued.has(coord):
		_queue.append(coord)
		_queued[coord] = true


func pending_count() -> int:
	return _queue.size() + (1 if _active != null else 0)


func chunk_count() -> int:
	return _chunks.size()


func mesh_count() -> int:
	return _counts.size()


func visible_faces() -> int:
	var total := 0
	for count: Vector2i in _counts.values():
		total += count.x
	return total


func solid_blocks() -> int:
	var total := 0
	for count: Vector2i in _counts.values():
		total += count.y
	return total


func _process(_delta: float) -> void:
	if not collision_enabled: process_mesh_queue()


func _physics_process(_delta: float) -> void:
	if collision_enabled: process_mesh_queue()


func process_mesh_queue() -> int:
	var started := Time.get_ticks_usec()
	var completed := 0
	while pending_count() > 0 and completed < max_chunks_per_frame:
		if Time.get_ticks_usec() - started >= mesh_budget_usec:
			break
		if _active == null:
			_active_coord = _queue.pop_front()
			_queued.erase(_active_coord)
			_active = VFChunkMesher.new()
			_active.begin(get_chunk(_active_coord), _active_coord * VFChunkData.SIZE, get_block_global)
		if _active.process_slice(32):
			var coord := _active_coord
			var mesh := _active.finish()
			_counts[coord] = Vector2i(_active.last_visible_faces, _active.last_solid_blocks)
			if not _views.has(coord):
				var view := MeshInstance3D.new()
				view.position = Vector3(coord * VFChunkData.SIZE)
				view.material_override = _material
				add_child(view)
				_views[coord] = view
			var instance: MeshInstance3D = _views[coord]
			instance.mesh = mesh if mesh.get_surface_count() > 0 else null
			if collision_enabled: _update_collision(instance, mesh)
			_active = null
			completed += 1
			rebuilt_total += 1
			chunk_rebuilt.emit(coord)
	last_mesh_usec = Time.get_ticks_usec() - started
	return completed


func _update_collision(instance: MeshInstance3D, mesh: ArrayMesh) -> void:
	var body := instance.get_node_or_null("TerrainBody") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "TerrainBody"
		body.collision_layer = 1
		body.collision_mask = 0
		instance.add_child(body)
		var collider := CollisionShape3D.new()
		collider.name = "Shape"
		body.add_child(collider)
	var shape := body.get_node("Shape") as CollisionShape3D
	shape.shape = mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null


func collision_section_count() -> int:
	var count := 0
	for view: MeshInstance3D in _views.values():
		var shape := view.get_node_or_null("TerrainBody/Shape") as CollisionShape3D
		if shape != null and shape.shape != null: count += 1
	return count


func clear_world() -> void:
	# Detach views immediately: their old colliders must leave the physics world.
	_active = null
	_queue.clear()
	_queued.clear()
	_chunks.clear()
	_counts.clear()
	for view: MeshInstance3D in _views.values():
		remove_child(view)
		view.queue_free()
	_views.clear()
	rebuilt_total = 0
