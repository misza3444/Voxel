extends Node3D

var overview: Camera3D
var world: VFWorldManager
var player: VFPlayerController
var menu: Control
var hud: Control
var play_button: Button
var return_button: Button
var menu_title: Label
var menu_copy: Label
var info: Label
var message: Label
var slots: Array[Button] = []
var _ready_to_play := false
var _started := false
var _saw_capture := false
var _clock := 0.0
var _message_until := 0
var _smoke := false
var _smoke_ticks := 0
var _started_usec := 0

func _ready() -> void:
	_started_usec = Time.get_ticks_usec()
	_smoke = "--smoke-test" in OS.get_cmdline_user_args()
	world = VFWorldManager.new()
	world.collision_enabled = true
	add_child(world)
	populate_world()
	player = VFPlayerController.new()
	player.world = world
	add_child(player)
	player.pause_requested.connect(pause_game)
	player.respawn_requested.connect(respawn_player)
	player.selection_changed.connect(update_hotbar)
	player.feedback.connect(show_message)
	player.block_edited.connect(func(kind, cell): print("VOXELFORGE_EDIT: %s %s" % [kind, cell]))
	overview = Camera3D.new()
	overview.position = Vector3(58, 53, 72)
	add_child(overview)
	overview.look_at(Vector3(0, 5, 0))
	overview.current = true
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("4f8cbd")
	sky_material.sky_horizon_color = Color("c0dfde")
	sky_material.ground_bottom_color = Color("6c827b")
	sky_material.ground_horizon_color = Color("c0dfde")
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d7e7e8")
	env.ambient_light_energy = 0.4
	env_node.environment = env
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -28, 0)
	sun.light_color = Color("ffefd7")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	add_child(sun)
	build_hud()
	update_hotbar(0)

func _process(delta: float) -> void:
	_clock += delta
	if not _ready_to_play and world_is_ready():
		_ready_to_play = true
		respawn_player()
		play_button.disabled = false
		play_button.text = "ZAGRAJ"
		menu_copy.text = ready_description()
		print("VOXELFORGE_WORLD_READY: stage %d, %d collision sections" % [stage_number(), world.collision_section_count()])
		if _smoke:
			player.camera.current = true
			player.set_active(true)
	if not _ready_to_play: play_button.text = "Przygotowuję świat… %d" % world.pending_count()
	if _started and player.active:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: _saw_capture = true
		elif _saw_capture: pause_game()
	if _clock >= 0.15:
		_clock = 0
		info.text = "X %.1f   Y %.1f   Z %.1f\n%s" % [player.position.x, player.position.y, player.position.z, location_text()]
		if Time.get_ticks_msec() > _message_until: message.text = ""

func _physics_process(_delta: float) -> void:
	if not _smoke: return
	if Time.get_ticks_usec() - _started_usec > 45000000:
		push_error("World smoke timeout")
		get_tree().quit(1)
	if _ready_to_play:
		_smoke_ticks += 1
		if _smoke_ticks == 100:
			player.camera.rotation.x = -PI * 0.5
			player.update_target()
			if player.is_on_floor() and not player.target.is_empty() and world.collision_section_count() > 0:
				print("VOXELFORGE_SMOKE_OK: grounded player, voxel ray, terrain colliders")
				get_tree().quit(0)
			else:
				push_error("World smoke failed: player/terrain/ray")
				get_tree().quit(1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN
		if DisplayServer.window_get_mode() == mode: mode = DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(mode)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _started and is_instance_valid(player): pause_game()

func play() -> void:
	if not _ready_to_play: return
	_started = true
	_saw_capture = false
	menu.hide()
	hud.show()
	player.camera.current = true
	player.set_active(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func pause_game() -> void:
	if not _started: return
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_saw_capture = false
	menu_title.text = "Chwila przerwy"
	menu_copy.text = "Świat poczeka. Wróć, kiedy będziesz gotowy.\nZmiany terenu pozostają tylko do zamknięcia gry."
	play_button.text = "WRÓĆ DO GRY"
	return_button.show()
	menu.show()

func respawn_player() -> void:
	var candidates: Array[Vector2i] = [Vector2i(5, 4), Vector2i(8, 4), Vector2i(0, 0)]
	for z in range(-24, 25, 8):
		for x in range(-24, 25, 8): candidates.append(Vector2i(x, z))
	for column in candidates:
		for y in range(45, -1, -1):
			if world.get_block_global(Vector3i(column.x, y, column.y)) != VFChunkData.Block.AIR:
				player.respawn(Vector3(column.x + 0.5, y + 1.08, column.y + 0.5))
				show_message("Powrót na bezpieczny grunt.")
				return
	world.set_block_global(Vector3i(5, 3, 4), VFChunkData.Block.ROCK)
	player.respawn(Vector3(5.5, 4.08, 4.5))

func show_message(text: String) -> void:
	if is_instance_valid(message):
		message.text = text
		_message_until = Time.get_ticks_msec() + 2500

func update_hotbar(index: int) -> void:
	for i in range(slots.size()): slots[i].set_pressed_no_signal(i == index)

func label(parent: Node, text: String, size: int, color := Color("eff6f1")) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	parent.add_child(item)
	return item

func box(color: Color) -> StyleBoxFlat:
	var item := StyleBoxFlat.new()
	item.bg_color = color
	item.set_corner_radius_all(8)
	item.content_margin_left = 18
	item.content_margin_right = 18
	item.content_margin_top = 14
	item.content_margin_bottom = 14
	return item

func button(parent: Node, text: String, callback: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_NONE
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_stylebox("panel", "PanelContainer", box(Color(0.035, 0.09, 0.10, 0.93)))
	theme.set_stylebox("normal", "Button", box(Color("214943")))
	theme.set_stylebox("hover", "Button", box(Color("32675a")))
	var selected_style := box(Color("477f59"))
	selected_style.set_border_width_all(2)
	selected_style.border_color = Color("d7e9aa")
	theme.set_stylebox("pressed", "Button", selected_style)
	theme.set_color("font_color", "Label", Color("eff6f1"))
	root.theme = theme
	hud = Control.new()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.hide()
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	label(col, "VOXELFORGE  /  SANDBOX %02d" % stage_number(), 17, Color("b8ddae"))
	info = label(col, "", 13)
	var cross := label(hud, "+", 27)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.offset_left = -12
	cross.offset_top = -19
	cross.offset_right = 12
	cross.offset_bottom = 19
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.add_theme_color_override("font_shadow_color", Color("183a35"))
	cross.add_theme_constant_override("shadow_offset_x", 1)
	cross.add_theme_constant_override("shadow_offset_y", 1)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom := VBoxContainer.new()
	hud.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -375
	bottom.offset_right = 375
	bottom.offset_top = -175
	bottom.offset_bottom = -18
	bottom.add_theme_constant_override("separation", 10)
	message = label(bottom, "", 16, Color("fff0ad"))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 7)
	bottom.add_child(row)
	for i in range(6):
		var item := button(row, "%d\n%s" % [i + 1, VFPlayerController.NAMES[i]], player.select_material.bind(i))
		item.toggle_mode = true
		item.custom_minimum_size.x = 110
		slots.append(item)
	var help := label(bottom, "WASD: ruch   ·   Spacja: skok   ·   Shift: bieg   ·   Esc: pauza\nLPM: kop   ·   PPM: postaw   ·   1–6 / kółko: materiał", 13)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu = Control.new()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	menu.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.06, 0.07, 0.72)
	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 540
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	card.add_child(column)
	label(column, "WŁASNY ŚWIAT  /  ETAP %02d" % stage_number(), 14, Color("b8ddae"))
	menu_title = label(column, "VOXELFORGE", 40)
	menu_copy = label(column, "Przygotowuję teren i miejsce startu…", 17)
	label(column, "Eksploruj. Kop. Buduj.", 22)
	play_button = button(column, "PRZYGOTOWUJĘ ŚWIAT…", play)
	play_button.disabled = true
	return_button = button(column, "Wróć na bezpieczny grunt", func(): respawn_player(); play())
	return_button.hide()
	menu_extras(column)
	label(column, "1–6 / kółko myszy: materiał   ·   R: powrót na start\nF11: pełny ekran   ·   Esc: zwolnij kursor\n\nTen etap nie zapisuje zmian po zamknięciu gry.", 14, Color("a4bfba"))

func populate_world() -> void:
	VFDemoWorld.populate(world)

func world_is_ready() -> bool:
	return world.pending_count() == 0

func ready_description() -> String:
	return "Twój pierwszy świat do odkrywania i budowania.\nWybierz materiał i zmieniaj teren po swojemu."

func location_text() -> String:
	return "Aktualizuję teren…" if world.pending_count() > 0 else ""

func stage_number() -> int:
	return 3

func menu_extras(_column: VBoxContainer) -> void:
	pass
