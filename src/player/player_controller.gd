extends CharacterBody3D
class_name VFPlayerController

signal block_edited(kind: String, cell: Vector3i)
signal feedback(message: String)
signal selection_changed(index: int)
signal pause_requested
signal respawn_requested

const HEIGHT := 1.8
const RADIUS := 0.3
const REACH := 6.0
const MATERIALS: Array[int] = [1, 2, 3, 4, 5, 6]
const NAMES: Array[String] = ["Trawa", "Ziemia", "Kamień", "Piasek", "Drewno", "Liście"]
var world: VFWorldManager
var camera: Camera3D
var active := false
var selected := 0
var target: Dictionary = {}
var bounds := AABB(Vector3(-32, 0, -32), Vector3(64, 48, 64))
var sensitivity := 0.0025
var _break_queued := false
var _place_queued := false
var _settle := 0
var _skip_capture_motion := true
var _outline: MeshInstance3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.2
	floor_max_angle = deg_to_rad(45)
	safe_margin = 0.001
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = HEIGHT * 0.5
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 75
	camera.near = 0.05
	camera.far = 220
	add_child(camera)
	var keys := {"vf_forward": KEY_W, "vf_back": KEY_S, "vf_left": KEY_A, "vf_right": KEY_D, "vf_jump": KEY_SPACE, "vf_sprint": KEY_SHIFT}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = keys[action]
			InputMap.action_add_event(action, key)
	_make_outline()

func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			pause_requested.emit()
			return
		if event.keycode == KEY_R:
			respawn_requested.emit()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_6: select_material(event.keycode - KEY_1)
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_skip_capture_motion = true
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT: _break_queued = true
			MOUSE_BUTTON_RIGHT: _place_queued = true
			MOUSE_BUTTON_WHEEL_UP: select_material(posmod(selected - 1, 6))
			MOUSE_BUTTON_WHEEL_DOWN: select_material((selected + 1) % 6)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _skip_capture_motion:
			_skip_capture_motion = false
			return
		rotation.y -= event.relative.x * sensitivity
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sensitivity, -1.54, 1.54)

func select_material(index: int) -> void:
	selected = clampi(index, 0, 5)
	selection_changed.emit(selected)

func _physics_process(delta: float) -> void:
	if not active or world == null: return
	# Freeze displacement while terrain changes; physics sees both mesh and collision commit.
	if world.pending_count() > 0:
		_settle = 2
		_clear_actions()
		return
	if _settle > 0:
		_settle -= 1
		_clear_actions()
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var axes := Input.get_vector("vf_left", "vf_right", "vf_forward", "vf_back") if captured else Vector2.ZERO
	step_motion(delta, axes, captured and Input.is_action_just_pressed("vf_jump"), captured and Input.is_action_pressed("vf_sprint"))
	update_target()
	if _break_queued: break_target()
	elif _place_queued: place_target()
	_clear_actions()
	if position.y < -16: respawn_requested.emit()

func step_motion(delta: float, axes: Vector2, jump: bool, sprint: bool) -> void:
	var wish := (basis * Vector3(axes.x, 0, axes.y)).normalized()
	var speed := 7.5 if sprint else 4.8
	var acceleration := 28.0 if is_on_floor() else 10.0
	velocity.x = move_toward(velocity.x, wish.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, acceleration * delta)
	if is_on_floor(): velocity.y = 7.2 if jump else -0.1
	else: velocity.y = maxf(velocity.y - 22 * delta, -45)
	move_and_slide()

func update_target() -> void:
	target = VFVoxelRaycast.cast(world, camera.global_position, -camera.global_basis.z, REACH)
	_outline.visible = not target.is_empty() and active
	if not target.is_empty(): _outline.global_position = Vector3(target.block) + Vector3.ONE * 0.5

func break_target() -> bool:
	update_target()
	if target.is_empty() or world.pending_count() > 0: return false
	var cell: Vector3i = target.block
	if not bounds.has_point(Vector3(cell) + Vector3.ONE * 0.5): return false
	world.set_block_global(cell, VFChunkData.Block.AIR)
	block_edited.emit("break", cell)
	return true

func place_target() -> bool:
	update_target()
	if target.is_empty() or world.pending_count() > 0 or target.normal == Vector3i.ZERO: return false
	var cell: Vector3i = target.place
	if not bounds.has_point(Vector3(cell) + Vector3.ONE * 0.5):
		feedback.emit("To granica tego świata demonstracyjnego.")
		return false
	if world.get_block_global(cell) != VFChunkData.Block.AIR: return false
	if overlaps_block(cell):
		feedback.emit("Tutaj stoi Twoja postać.")
		return false
	world.set_block_global(cell, MATERIALS[selected])
	block_edited.emit("place", cell)
	return true

func overlaps_block(cell: Vector3i) -> bool:
	# Conservative capsule AABB; a small clearance also rejects near-contact placements.
	var box := AABB(global_position + Vector3(-RADIUS, 0.002, -RADIUS), Vector3(RADIUS * 2, HEIGHT - 0.004, RADIUS * 2)).grow(0.002)
	return box.intersects(AABB(Vector3(cell), Vector3.ONE))

func set_active(value: bool) -> void:
	active = value
	_skip_capture_motion = true
	_clear_actions()
	_outline.visible = false
	if not value: velocity = Vector3.ZERO

func respawn(feet: Vector3) -> void:
	global_position = feet
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	camera.rotation = Vector3(-0.12, 0, 0)
	_settle = 2
	_clear_actions()

func _clear_actions() -> void:
	_break_queued = false
	_place_queued = false

func _make_outline() -> void:
	var points := PackedVector3Array()
	var half := 0.505
	for axis in range(3):
		for a: float in [-half, half]:
			for b: float in [-half, half]:
				var p := Vector3.ZERO
				p[axis] = -half
				p[(axis + 1) % 3] = a
				p[(axis + 2) % 3] = b
				var q := p
				q[axis] = half
				points.append_array(PackedVector3Array([p, q]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_outline = MeshInstance3D.new()
	_outline.top_level = true
	_outline.mesh = mesh
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("fff1a6")
	_outline.material_override = material
	_outline.visible = false
	add_child(_outline)
