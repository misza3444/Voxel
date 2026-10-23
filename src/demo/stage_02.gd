extends Node3D
## Stage 2 viewer. No character/physics/block interaction until stage 3.

var world: VFWorldManager
var pivot: Node3D
var camera: Camera3D
var grid: MeshInstance3D
var stats: Label
var status: Label
var cut_button: Button
var grid_button: Button
var saved_sections: Dictionary = {}
var _stats_clock := 0.0
var _smoke := false
var _smoke_phase := 0
var _initial_faces := 0
var _started_usec := 0
var _preview_path := ""
var _preview_started := false
var _was_busy := true


func _ready() -> void:
	_started_usec = Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument == "--smoke-test":
			_smoke = true
		elif argument.begins_with("--preview="):
			_preview_path = argument.trim_prefix("--preview=")
	world = VFWorldManager.new()
	add_child(world)
	pivot = Node3D.new()
	add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.far = 350.0
	pivot.add_child(camera)
	camera.current = true
	reset_camera()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_color = Color("fff0d7")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a8cbd6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6e2ed")
	env.ambient_light_energy = 0.4
	environment_node.environment = env
	add_child(environment_node)
	build_hud()
	build_grid()
	VFDemoWorld.populate(world)
	update_stats()


func _process(delta: float) -> void:
	if world.pending_count() == 0 and _was_busy:
		_was_busy = false
		update_stats()
		print("VOXELFORGE_WORLD_READY: %d sections, %d faces" % [world.chunk_count(), world.visible_faces()])
	_stats_clock += delta
	if _stats_clock >= 0.15:
		_stats_clock = 0.0
		update_stats()
	var movement := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): movement.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): movement.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): movement.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): movement.x += 1.0
	movement = movement.rotated(Vector3.UP, pivot.rotation.y)
	pivot.position += movement.normalized() * delta * 22.0
	pivot.position.x = clampf(pivot.position.x, -40.0, 40.0)
	pivot.position.z = clampf(pivot.position.z, -40.0, 40.0)
	if _smoke:
		run_smoke_step()
	elif not _preview_path.is_empty() and not _preview_started and world.pending_count() == 0:
		_preview_started = true
		capture_preview()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		pivot.rotation.y -= event.relative.x * 0.006
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * 0.006, -1.35, -0.12)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom(-6.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom(6.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R: reset_camera()
			KEY_B: toggle_grid()
			KEY_C: toggle_cut()
			KEY_F11:
				var mode := DisplayServer.WINDOW_MODE_FULLSCREEN
				if DisplayServer.window_get_mode() == mode: mode = DisplayServer.WINDOW_MODE_WINDOWED
				DisplayServer.window_set_mode(mode)


func zoom(amount: float) -> void:
	camera.position.z = clampf(camera.position.z + amount, 25.0, 160.0)


func reset_camera() -> void:
	pivot.position = Vector3(0, 6, 0)
	pivot.rotation = Vector3(deg_to_rad(-34), deg_to_rad(-38), 0)
	camera.position = Vector3(0, 0, 124)


func toggle_cut() -> void:
	_was_busy = true
	if saved_sections.is_empty():
		for cy in range(2):
			var coord := Vector3i(0, cy, 0)
			saved_sections[coord] = world.get_chunk(coord)
			world.remove_chunk(coord)
	else:
		for coord: Vector3i in saved_sections:
			world.add_chunk(coord, saved_sections[coord])
		saved_sections.clear()
	cut_button.text = "C  Przywróć fragment" if not saved_sections.is_empty() else "C  Wyjmij fragment"
	update_stats()


func toggle_grid() -> void:
	grid.visible = not grid.visible
	grid_button.text = "B  Ukryj granice" if grid.visible else "B  Pokaż granice"


func update_stats() -> void:
	stats.text = "%d / 32 sekcje     ·     %s bloków\n%s ścian     ·     %d FPS" % [world.chunk_count(), str(world.solid_blocks()), str(world.visible_faces()), Engine.get_frames_per_second()]
	status.text = "ŚWIAT GOTOWY" if world.pending_count() == 0 else "BUDOWANIE ŚWIATA  ·  pozostało %d" % world.pending_count()


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("eaf4f2"))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.10, 0.12, 0.94)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("265451") if state == "normal" else Color("387b70")
		style.set_corner_radius_all(6)
		style.content_margin_left = 15
		style.content_margin_right = 15
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		theme.set_stylebox(state, "Button", style)
	root.theme = theme
	var top := PanelContainer.new()
	top.position = Vector2(24, 24)
	root.add_child(top)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	top.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "WORLD LAB  /  ETAP 02"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color("8cd9b3"))
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "VOXELFORGE"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Jeden świat. Wiele chunków."
	column.add_child(subtitle)
	column.add_child(HSeparator.new())
	stats = Label.new()
	column.add_child(stats)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("8cd9b3"))
	column.add_child(status)
	var bottom := PanelContainer.new()
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -125
	bottom.offset_bottom = -24
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	bottom.add_child(controls)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	controls.add_child(row)
	grid_button = add_button(row, "B  Pokaż granice", toggle_grid)
	cut_button = add_button(row, "C  Wyjmij fragment", toggle_cut)
	add_button(row, "R  Widok początkowy", reset_camera)
	add_button(row, "+", func(): zoom(-8))
	add_button(row, "−", func(): zoom(8))
	var help := Label.new()
	help.text = "PPM + ruch: obrót   ·   Kółko: zoom   ·   WASD: przesuwanie   ·   F11: pełny ekran"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color("abc4c8"))
	controls.add_child(help)


func add_button(parent: Control, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func build_grid() -> void:
	var vertices := PackedVector3Array()
	for height: float in [0.05, 16.05, 32.05]:
		for n in range(-32, 33, 16):
			vertices.append_array(PackedVector3Array([Vector3(n, height, -32), Vector3(n, height, 32), Vector3(-32, height, n), Vector3(32, height, n)]))
	for x in range(-32, 33, 16):
		for z in range(-32, 33, 16):
			vertices.append_array(PackedVector3Array([Vector3(x, 0, z), Vector3(x, 32, z)]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	grid = MeshInstance3D.new()
	grid.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("20675f")
	grid.material_override = material
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.visible = false
	add_child(grid)


func run_smoke_step() -> void:
	if Time.get_ticks_usec() - _started_usec > 30000000:
		push_error("SMOKE timeout: world never became ready")
		get_tree().quit(1)
		return
	if world.pending_count() > 0:
		return
	if _smoke_phase == 0:
		if world.chunk_count() != 32 or world.mesh_count() != 32 or world.visible_faces() <= 0:
			push_error("SMOKE initial world incomplete")
			get_tree().quit(1)
			return
		_initial_faces = world.visible_faces()
		toggle_cut()
		_smoke_phase = 1
	elif _smoke_phase == 1:
		if world.chunk_count() != 30 or world.mesh_count() != 30:
			push_error("SMOKE removal incomplete")
			get_tree().quit(1)
			return
		toggle_cut()
		_smoke_phase = 2
	else:
		if world.chunk_count() != 32 or world.mesh_count() != 32 or world.visible_faces() != _initial_faces:
			push_error("SMOKE restore differs from original")
			get_tree().quit(1)
			return
		print("VOXELFORGE_SMOKE_OK: 32 sections, remove/restore, %d faces" % _initial_faces)
		get_tree().quit(0)


func capture_preview() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Preview requires a rendering display")
		get_tree().quit(1)
		return
	update_stats()
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(_preview_path)
	get_tree().quit(0 if error == OK else 1)
