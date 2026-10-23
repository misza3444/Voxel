extends Node3D
## Stage 01 is a read-only chunk viewer, NOT a playable character controller.

@onready var chunk_mesh: MeshInstance3D = $ChunkMesh
@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var stats: Label = $HUD/Panel/Margin/Column/Stats
@onready var environment_node: WorldEnvironment = $WorldEnvironment

var face_count: int = 0
var solid_count: int = 0
var frame_accumulator: float = 0.0


func _ready() -> void:
	var data := VFChunkData.new()
	data.populate_demo()
	var mesher := VFChunkMesher.new()
	chunk_mesh.mesh = mesher.build_mesh(data)
	face_count = mesher.last_visible_faces
	solid_count = mesher.last_solid_blocks

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	chunk_mesh.material_override = material

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8cbfd4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d7e9ea")
	env.ambient_light_energy = 0.65
	environment_node.environment = env
	reset_camera()
	update_stats()


func _process(delta: float) -> void:
	frame_accumulator += delta
	if frame_accumulator >= 0.3:
		frame_accumulator = 0.0
		update_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			pivot.rotation.y -= motion.relative.x * 0.007
			pivot.rotation.x = clampf(pivot.rotation.x - motion.relative.y * 0.007, -1.3, -0.12)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.position.z = maxf(12.0, camera.position.z - 1.5)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.position.z = minf(36.0, camera.position.z + 1.5)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			reset_camera()


func reset_camera() -> void:
	pivot.position = Vector3(8.0, 4.5, 8.0)
	pivot.rotation = Vector3(deg_to_rad(-26.0), deg_to_rad(-34.0), 0.0)
	camera.position = Vector3(0.0, 0.0, 25.0)


func update_stats() -> void:
	stats.text = "Etap 01 · jeden chunk 16³\nBryły: %d  |  Widoczne ściany: %d\nTrójkąty: %d  |  FPS: %d\n\nPPM + ruch: obrót kamery\nKółko: zoom  |  R: reset" % [
		solid_count, face_count, face_count * 2, Engine.get_frames_per_second()
	]
