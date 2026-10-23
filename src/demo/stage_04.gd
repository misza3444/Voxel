extends "res://src/demo/stage_03.gd"

var generator: VFWorldGenerator
var seed_input: LineEdit
var generate_button: Button
var random_button: Button
var cave_button: Button
var progress: Label
var _generation_queue: Array[Vector3i] = []
var _generating := false
var _generation_coord := Vector3i.ZERO
var _generation_total := 64
var _generated := 0

func stage_number() -> int:
	return 4

func _ready() -> void:
	super._ready()
	player.bounds = AABB(Vector3(-32, 0, -32), Vector3(64, 64, 64))
	overview.position = Vector3(64, 70, 82)
	overview.look_at(Vector3(0, 18, 0))

func populate_world() -> void:
	start_generation(20261022)

func start_generation(seed_value: int) -> void:
	world.hide()
	generator = VFWorldGenerator.new(seed_value)
	_generation_queue.clear()
	_generating = false
	_generated = 0
	_ready_to_play = false
	_smoke_ticks = 0
	_started_usec = Time.get_ticks_usec()
	for y in range(4):
		for z in range(-2, 2):
			for x in range(-2, 2): _generation_queue.append(Vector3i(x, y, z))

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < 2000:
		if not _generating:
			if _generation_queue.is_empty(): break
			_generation_coord = _generation_queue.pop_front()
			generator.begin_chunk(_generation_coord)
			_generating = true
		if generator.process_slice(4):
			var chunk := generator.finish()
			if chunk.blocks.count(VFChunkData.Block.AIR) != VFChunkData.VOLUME:
				world.add_chunk(_generation_coord, chunk)
			_generating = false
			_generated += 1
	super._process(delta)
	if _ready_to_play: world.show()
	generate_button.disabled = not _ready_to_play
	random_button.disabled = not _ready_to_play
	cave_button.disabled = not _ready_to_play
	seed_input.editable = _ready_to_play
	if not _ready_to_play:
		play_button.text = "PRZYGOTOWUJĘ ŚWIAT…"
		progress.text = "Teren: %d / %d   ·   Sekcje do zbudowania: %d" % [_generated, _generation_total, world.pending_count()]
	else:
		progress.text = "Seed: %d   ·   Świat 64 × 64 × 64" % generator.world_seed

func world_is_ready() -> bool:
	return _generation_queue.is_empty() and not _generating and world.pending_count() == 0

func ready_description() -> String:
	return "Łąki, lasy, wydmy i skaliste wzgórza.\nOdkrywaj jaskinie i buduj we własnym świecie."

func location_text() -> String:
	if world.pending_count() > 0: return "Aktualizuję teren…"
	var biome := generator.column(floori(player.position.x), floori(player.position.z)).y
	return "%s   ·   Seed %d" % [VFWorldGenerator.BIOME_NAMES[biome], generator.world_seed]

func menu_extras(column: VBoxContainer) -> void:
	column.add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	column.add_child(row)
	label(row, "Seed  ", 16)
	seed_input = LineEdit.new()
	seed_input.text = "20261022"
	seed_input.placeholder_text = "Liczba lub nazwa świata"
	seed_input.max_length = 64
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(seed_input)
	random_button = button(row, "Losuj", func(): seed_input.text = str(randi() & 0x7fffffff))
	generate_button = button(column, "Generuj nowy świat z seeda", regenerate)
	label(column, "Nowy świat usuwa zmiany w tej sesji.", 13, Color("d6c5a6"))
	progress = label(column, "Przygotowuję generator…", 13, Color("b8ddae"))
	cave_button = button(column, "Odkryj wejście do jaskini", visit_cave)

func regenerate() -> void:
	if not _ready_to_play: return
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_started = false
	_saw_capture = false
	hud.hide()
	menu.show()
	overview.current = true
	play_button.disabled = true
	return_button.hide()
	menu_title.text = "VOXELFORGE"
	menu_copy.text = "Tworzę świat z Twojego seeda…\nZa chwilę możesz ruszać na wyprawę."
	world.clear_world()
	var new_seed := VFWorldGenerator.seed_from_text(seed_input.text)
	start_generation(new_seed)
	print("VOXELFORGE_REGENERATE: seed %d" % new_seed)

func respawn_player() -> void:
	if generator == null: return
	var candidates: Array[Vector2i] = [Vector2i(8, 8), Vector2i(-8, 8), Vector2i(16, -16), Vector2i(-16, -16)]
	for column in candidates:
		if absi(column.x - generator.entrance.x) < 5: continue
		for y in range(63, -1, -1):
			var block_id := world.get_block_global(Vector3i(column.x, y, column.y))
			if block_id == VFChunkData.Block.AIR: continue
			if block_id == VFChunkData.Block.WOOD or block_id == VFChunkData.Block.LEAVES: break
			player.respawn(Vector3(column.x + 0.5, y + 1.08, column.y + 0.5))
			show_message("Powrót na powierzchnię.")
			return
	super.respawn_player()

func spawn_at_entrance() -> void:
	var x := generator.entrance.x
	var z := generator.entrance.y - 2
	for y in range(63, -1, -1):
		if world.get_block_global(Vector3i(x, y, z)) != VFChunkData.Block.AIR:
			player.respawn(Vector3(x + 0.5, y + 1.08, z + 0.5))
			player.rotation.y = PI
			return
	respawn_player()

func visit_cave() -> void:
	if not _ready_to_play: return
	spawn_at_entrance()
	play()
	show_message("Wejście przed Tobą. Zejdź w głąb jaskini.")
