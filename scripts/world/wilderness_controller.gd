class_name WildernessController
extends Node2D

## Controller untuk 5x5 Chunk Maze (Soul Knight Style)
## Mengatur rendering 5x5 chunk sesuai sample user (Rock4 di border, Path di doorway/interior),
## penempatan musuh Skeleton & Portal random, serta pergerakan player chunk-by-chunk.

const WildernessGen = preload("res://scripts/world/wilderness_generator.gd")
const SkeletonEnemyClass = preload("res://scripts/entities/skeleton_enemy.gd")

@onready var ground_layer: TileMapLayer = $Background/Ground if has_node("Background/Ground") else null
@onready var path_layer: TileMapLayer = $Path if has_node("Path") else null
@onready var decoration_layer: TileMapLayer = $Decoration if has_node("Decoration") else null
@onready var player_node: CharacterBody2D = $Player if has_node("Player") else null
@onready var skeleton_template: CharacterBody2D = $Skeleton if has_node("Skeleton") else null
@onready var camera: Camera2D = $Camera2D if has_node("Camera2D") else null

# Runtime spawned containers
var enemies_container: Node2D = null
var portal_node: Node2D = null
var path_line: Line2D = null

# Dynamic UI references
var ui_layer: CanvasLayer = null
var algorithm_option: OptionButton = null
var difficulty_option: OptionButton = null
var btn_generate: Button = null
var btn_animate: Button = null
var btn_toggle_path: Button = null
var btn_back: Button = null

var btn_move_north: Button = null
var btn_move_south: Button = null
var btn_move_west: Button = null
var btn_move_east: Button = null
var lbl_current_room: Label = null

var lbl_status: Label = null
var lbl_energy: Label = null
var lbl_threat: Label = null
var lbl_path_len: Label = null
var enemy_list_vbox: VBoxContainer = null

var generator: WildernessGen = null
var current_maze: WildernessGen.MazeState = null
var is_animating_search: bool = false
var show_path_line: bool = true

# Player chunk coordinate
var current_chunk: Vector2i = Vector2i(0, 0)
var is_moving_chunk: bool = false

func _ready() -> void:
	generator = WildernessGen.new()
	_ensure_runtime_nodes()
	_build_ui()
	
	# Sembunyikan template skeleton yang ada di negative Y
	if skeleton_template:
		skeleton_template.visible = false
		
	# Jalankan generasi maze pertama kali
	generate_wilderness()

func _ensure_runtime_nodes() -> void:
	if enemies_container == null:
		enemies_container = Node2D.new()
		enemies_container.name = "EnemiesContainer"
		enemies_container.z_index = 3
		add_child(enemies_container)
		
	if portal_node == null:
		portal_node = Node2D.new()
		portal_node.name = "Portal"
		portal_node.z_index = 2
		
		var spr := Sprite2D.new()
		spr.name = "PortalSprite"
		spr.texture = load("res://assets/Greyscale Portal-Spinning scaled.png")
		spr.hframes = 8
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(0.9, 0.9)
		spr.set_script(load("res://scripts/world/spinning_portal.gd"))
		portal_node.add_child(spr)
		add_child(portal_node)
		
	if path_line == null:
		path_line = Line2D.new()
		path_line.name = "PathLine"
		path_line.z_index = 2
		path_line.width = 6.0
		path_line.default_color = Color(0, 0.96, 0.57, 0.8)
		path_line.joint_mode = Line2D.LINE_JOINT_ROUND
		path_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		path_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(path_line)

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "WildernessUI"
	ui_layer.layer = 50
	add_child(ui_layer)
	
	var font_bold = load("res://fonts/PixelifySans-Bold.ttf")
	
	# 1. Top Bar Panel
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 20.0
	top_panel.offset_top = 16.0
	top_panel.offset_right = -20.0
	top_panel.offset_bottom = 74.0
	
	var sb_top := StyleBoxFlat.new()
	sb_top.bg_color = Color(0.08, 0.1, 0.16, 0.94)
	sb_top.border_color = Color(0.25, 0.35, 0.5, 0.8)
	sb_top.set_border_width_all(2)
	sb_top.set_corner_radius_all(10)
	sb_top.set_content_margin_all(8)
	top_panel.add_theme_stylebox_override("panel", sb_top)
	ui_layer.add_child(top_panel)
	
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	top_panel.add_child(top_hbox)
	
	var title := Label.new()
	title.text = "⚔️ 5x5 MAZE (LOCAL SEARCH)"
	if font_bold: title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	top_hbox.add_child(title)
	
	top_hbox.add_child(VSeparator.new())
	
	# Algorithm dropdown
	algorithm_option = OptionButton.new()
	algorithm_option.add_item("Simulated Annealing", 0)
	algorithm_option.add_item("Hill Climbing (Restart)", 1)
	top_hbox.add_child(algorithm_option)
	
	# Difficulty dropdown
	difficulty_option = OptionButton.new()
	difficulty_option.add_item("Easy (Threat: 40)", 0)
	difficulty_option.add_item("Medium (Threat: 80)", 1)
	difficulty_option.add_item("Hard (Threat: 140)", 2)
	difficulty_option.selected = 1
	top_hbox.add_child(difficulty_option)
	
	btn_generate = Button.new()
	btn_generate.text = "🎲 Generate Maze"
	btn_generate.add_theme_color_override("font_color", Color(0.35, 0.9, 0.55))
	btn_generate.pressed.connect(generate_wilderness)
	top_hbox.add_child(btn_generate)
	
	btn_animate = Button.new()
	btn_animate.text = "🎬 Watch Search"
	btn_animate.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	btn_animate.pressed.connect(start_animated_search)
	top_hbox.add_child(btn_animate)
	
	btn_toggle_path = Button.new()
	btn_toggle_path.text = "📍 Route: ON"
	btn_toggle_path.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	btn_toggle_path.pressed.connect(_toggle_path_line)
	top_hbox.add_child(btn_toggle_path)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)
	
	btn_back = Button.new()
	btn_back.text = "🏠 Overworld"
	btn_back.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	btn_back.pressed.connect(_return_to_overworld)
	top_hbox.add_child(btn_back)
	
	# 2. Bottom-Left D-Pad Navigation Panel
	var nav_panel := PanelContainer.new()
	nav_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	nav_panel.offset_left = 20.0
	nav_panel.offset_top = -180.0
	nav_panel.offset_right = 260.0
	nav_panel.offset_bottom = -20.0
	
	var sb_nav := StyleBoxFlat.new()
	sb_nav.bg_color = Color(0.06, 0.08, 0.14, 0.92)
	sb_nav.border_color = Color(0.3, 0.45, 0.65, 0.8)
	sb_nav.set_border_width_all(2)
	sb_nav.set_corner_radius_all(10)
	sb_nav.set_content_margin_all(8)
	nav_panel.add_theme_stylebox_override("panel", sb_nav)
	ui_layer.add_child(nav_panel)
	
	var nav_vbox := VBoxContainer.new()
	nav_vbox.add_theme_constant_override("separation", 5)
	nav_panel.add_child(nav_vbox)
	
	lbl_current_room = Label.new()
	lbl_current_room.text = "Room [0, 0]: Start"
	if font_bold: lbl_current_room.add_theme_font_override("font", font_bold)
	lbl_current_room.add_theme_font_size_override("font_size", 12)
	lbl_current_room.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	lbl_current_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_vbox.add_child(lbl_current_room)
	
	var dpad_grid := GridContainer.new()
	dpad_grid.columns = 3
	dpad_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dpad_grid.add_theme_constant_override("h_separation", 6)
	dpad_grid.add_theme_constant_override("v_separation", 6)
	nav_vbox.add_child(dpad_grid)
	
	var dummy1 = Control.new()
	dummy1.custom_minimum_size = Vector2(36, 30)
	dpad_grid.add_child(dummy1)
	
	btn_move_north = _create_dpad_btn("⬆️", Vector2i.UP)
	dpad_grid.add_child(btn_move_north)
	
	var dummy2 = Control.new()
	dummy2.custom_minimum_size = Vector2(36, 30)
	dpad_grid.add_child(dummy2)
	
	btn_move_west = _create_dpad_btn("⬅️", Vector2i.LEFT)
	dpad_grid.add_child(btn_move_west)
	
	var compass_lbl = Label.new()
	compass_lbl.text = "🧭"
	compass_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	compass_lbl.custom_minimum_size = Vector2(36, 30)
	dpad_grid.add_child(compass_lbl)
	
	btn_move_east = _create_dpad_btn("➡️", Vector2i.RIGHT)
	dpad_grid.add_child(btn_move_east)
	
	var dummy3 = Control.new()
	dummy3.custom_minimum_size = Vector2(36, 30)
	dpad_grid.add_child(dummy3)
	
	btn_move_south = _create_dpad_btn("⬇️", Vector2i.DOWN)
	dpad_grid.add_child(btn_move_south)
	
	var dummy4 = Control.new()
	dummy4.custom_minimum_size = Vector2(36, 30)
	dpad_grid.add_child(dummy4)
	
	var hint_nav := Label.new()
	hint_nav.text = "Gunakan WASD / Arrow Keys untuk gerak room"
	hint_nav.add_theme_font_size_override("font_size", 9)
	hint_nav.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	hint_nav.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_vbox.add_child(hint_nav)
	
	# 3. Right Analytics Panel
	var anal_panel := PanelContainer.new()
	anal_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anal_panel.offset_left = -310.0
	anal_panel.offset_top = 88.0
	anal_panel.offset_right = -20.0
	anal_panel.offset_bottom = 430.0
	anal_panel.add_theme_stylebox_override("panel", sb_nav)
	ui_layer.add_child(anal_panel)
	
	var anal_vbox := VBoxContainer.new()
	anal_vbox.add_theme_constant_override("separation", 5)
	anal_panel.add_child(anal_vbox)
	
	var anal_title := Label.new()
	anal_title.text = "📊 LOCAL SEARCH ANALYTICS"
	if font_bold: anal_title.add_theme_font_override("font", font_bold)
	anal_title.add_theme_font_size_override("font_size", 14)
	anal_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	anal_vbox.add_child(anal_title)
	anal_vbox.add_child(HSeparator.new())
	
	lbl_status = Label.new()
	lbl_status.text = "Simulated Annealing | [OK] Solvable"
	lbl_status.add_theme_font_size_override("font_size", 12)
	lbl_status.add_theme_color_override("font_color", Color("#4ADE80"))
	anal_vbox.add_child(lbl_status)
	
	lbl_energy = Label.new()
	lbl_energy.text = "Energy / Cost: 12.0 (Optimal)"
	lbl_energy.add_theme_font_size_override("font_size", 11)
	lbl_energy.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	anal_vbox.add_child(lbl_energy)
	
	lbl_threat = Label.new()
	lbl_threat.text = "Threat: 80.0 / 80.0 (Target)"
	lbl_threat.add_theme_font_size_override("font_size", 11)
	lbl_threat.add_theme_color_override("font_color", Color("#4ADE80"))
	anal_vbox.add_child(lbl_threat)
	
	lbl_path_len = Label.new()
	lbl_path_len.text = "Path: 7 Rooms (Portal @ [4, 4])"
	lbl_path_len.add_theme_font_size_override("font_size", 11)
	lbl_path_len.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	anal_vbox.add_child(lbl_path_len)
	anal_vbox.add_child(HSeparator.new())
	
	var enemy_header := Label.new()
	enemy_header.text = "👾 ENEMIES ON CHUNK PATH:"
	if font_bold: enemy_header.add_theme_font_override("font", font_bold)
	enemy_header.add_theme_font_size_override("font_size", 12)
	enemy_header.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	anal_vbox.add_child(enemy_header)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	anal_vbox.add_child(scroll)
	
	enemy_list_vbox = VBoxContainer.new()
	enemy_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(enemy_list_vbox)

func _create_dpad_btn(arrow: String, dir: Vector2i) -> Button:
	var b := Button.new()
	b.text = arrow
	b.custom_minimum_size = Vector2(38, 30)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.24, 0.38, 0.95)
	sb.border_color = Color(0.45, 0.65, 0.95, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	b.pressed.connect(func(): move_player_chunk(dir))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if is_moving_chunk:
		return
	if event.is_action_pressed("up"):
		move_player_chunk(Vector2i.UP)
	elif event.is_action_pressed("down"):
		move_player_chunk(Vector2i.DOWN)
	elif event.is_action_pressed("left"):
		move_player_chunk(Vector2i.LEFT)
	elif event.is_action_pressed("right"):
		move_player_chunk(Vector2i.RIGHT)

func get_target_difficulty() -> float:
	var idx = difficulty_option.selected if difficulty_option else 1
	match idx:
		0: return 40.0   # Easy
		1: return 80.0   # Medium
		2: return 140.0  # Hard
		_: return 80.0

# =========================================================================
# GENERATE WILDERNESS (LOCAL SEARCH)
# =========================================================================
func generate_wilderness() -> void:
	if is_animating_search:
		return
		
	var target_diff = get_target_difficulty()
	var algo_idx = algorithm_option.selected if algorithm_option else 0
	
	var result: Dictionary = {}
	if algo_idx == 0:
		result = generator.run_simulated_annealing(target_diff, 280, 100.0, 0.982)
	else:
		result = generator.run_hill_climbing_restart(target_diff, 5, 55, 12)
		
	current_maze = result["best_state"]
	current_chunk = current_maze.start_chunk
	_render_maze(current_maze, target_diff, result["algorithm"])

# =========================================================================
# ANIMATED LIVE SEARCH VISUALIZATION
# =========================================================================
func start_animated_search() -> void:
	if is_animating_search:
		return
		
	is_animating_search = true
	if btn_generate: btn_generate.disabled = true
	if btn_animate: btn_animate.disabled = true
	
	var target_diff = get_target_difficulty()
	var algo_idx = algorithm_option.selected if algorithm_option else 0
	
	var result: Dictionary = {}
	if algo_idx == 0:
		result = generator.run_simulated_annealing(target_diff, 180, 90.0, 0.975)
	else:
		result = generator.run_hill_climbing_restart(target_diff, 4, 45, 10)
		
	var history: Array = result.get("history", [])
	
	for item in history:
		if not is_inside_tree():
			break
		if lbl_energy:
			lbl_energy.text = "Energy: %.1f | Best: %.1f" % [item.current_energy, item.best_energy]
		if lbl_status:
			var extra = "T: %.1f" % item.temp if item.has("temp") else "Restart #%d" % item.get("restart", 1)
			lbl_status.text = "Optimizing [%s]... Step %d (%s)" % [result["algorithm"], item.step, extra]
		await get_tree().create_timer(0.02).timeout
		
	current_maze = result["best_state"]
	current_chunk = current_maze.start_chunk
	_render_maze(current_maze, target_diff, result["algorithm"])
	
	is_animating_search = false
	if btn_generate: btn_generate.disabled = false
	if btn_animate: btn_animate.disabled = false

# =========================================================================
# CHUNK-TO-PIXEL CONVERSION
# =========================================================================
func get_chunk_tile_origin(c_pos: Vector2i) -> Vector2i:
	return Vector2i(c_pos.x * 5, c_pos.y * 5)

func get_chunk_center_pixel(c_pos: Vector2i) -> Vector2:
	var orig = get_chunk_tile_origin(c_pos)
	# Center tile adalah (orig.x + 2, orig.y + 2)
	return Vector2(orig.x + 2.5, orig.y + 2.5) * 64.0

# =========================================================================
# RENDER 5x5 CHUNK MAZE
# Mengikuti pola sample: 4 Sudut Batu, Pintu Terbuka/Tertutup, 9 Tile Interior
# Area 0..24 x 0..24 saja (TIDAK menyentuh sample di negative Y)
# =========================================================================
func _render_maze(maze: WildernessGen.MazeState, target_diff: float, algo_name: String) -> void:
	if maze == null:
		return
		
	# 1. Bersihkan tile Path & Decoration pada area 0..24 x 0..24
	if path_layer:
		for x in range(25):
			for y in range(25):
				path_layer.set_cell(Vector2i(x, y), -1)
	if decoration_layer:
		for x in range(25):
			for y in range(25):
				decoration_layer.set_cell(Vector2i(x, y), -1)
				
	if enemies_container:
		for c in enemies_container.get_children():
			c.queue_free()
			
	# 2. Render setiap 5x5 Chunk sesuai state pintu
	for cy in range(WildernessGen.GRID_H):
		for cx in range(WildernessGen.GRID_W):
			var c_pos = Vector2i(cx, cy)
			var chunk: WildernessGen.ChunkData = maze.chunks.get(c_pos)
			if chunk == null:
				continue
			var orig = get_chunk_tile_origin(c_pos)
			_render_single_chunk(chunk, orig)
			
	# 3. Spawn Player di Chunk (0, 0)
	var start_pixel = get_chunk_center_pixel(maze.start_chunk)
	if player_node:
		player_node.global_position = start_pixel
		if player_node.has_method("set_active"):
			player_node.set_active(true)
			
	# 4. Spawn Portal di Chunk Random
	var portal_pixel = get_chunk_center_pixel(maze.portal_chunk)
	if portal_node:
		portal_node.global_position = portal_pixel
		portal_node.visible = true
		
	# 5. Spawn Enemies (Satu atau Tidak Ada Enemy per Chunk)
	# Aturan: Chunk Start (0,0) dan Chunk Portal TIDAK BISA memiliki enemy
	for c_pos in maze.chunks.keys():
		var chunk: WildernessGen.ChunkData = maze.chunks[c_pos]
		if chunk.has_enemy and c_pos != maze.start_chunk and c_pos != maze.portal_chunk:
			_spawn_skeleton_enemy(chunk)
			
	# 6. Gambar Jalur Rute A* Room Path
	_draw_chunk_path(maze.chunk_path)
	
	# 7. Update UI
	_update_ui_dashboard(maze, target_diff, algo_name)
	_update_room_hud()
	
	# Fokuskan kamera pada Start room
	if camera:
		camera.global_position = start_pixel

func _render_single_chunk(chunk: WildernessGen.ChunkData, orig: Vector2i) -> void:
	var cx = chunk.grid_pos.x
	var cy = chunk.grid_pos.y
	
	for ly in range(WildernessGen.CHUNK_SIZE):
		for lx in range(WildernessGen.CHUNK_SIZE):
			var tile = orig + Vector2i(lx, ly)
			
			# 1. Empat sudut selalu batu (Rock4, source 9)
			var is_corner = (lx == 0 or lx == 4) and (ly == 0 or ly == 4)
			
			# 2. Periksa apakah dinding terbuka atau tertutup
			var is_wall = false
			if is_corner:
				is_wall = true
			elif ly == 0 and (lx >= 1 and lx <= 3):
				# North wall (tutup jika cy == 0 atau door_north false)
				is_wall = (cy == 0) or (not chunk.door_north)
			elif ly == 4 and (lx >= 1 and lx <= 3):
				# South wall (tutup jika cy == 4 atau door_south false)
				is_wall = (cy == WildernessGen.GRID_H - 1) or (not chunk.door_south)
			elif lx == 0 and (ly >= 1 and ly <= 3):
				# West wall (tutup jika cx == 0 atau door_west false)
				is_wall = (cx == 0) or (not chunk.door_west)
			elif lx == 4 and (ly >= 1 and ly <= 3):
				# East wall (tutup jika cx == 4 atau door_east false)
				is_wall = (cx == WildernessGen.GRID_W - 1) or (not chunk.door_east)
			else:
				# 9 tile interior (lx in 1..3, ly in 1..3) selalu terbuka
				is_wall = false
				
			if is_wall:
				# Letakkan batu di layer Decoration (source 9, atlas (0, 0))
				if decoration_layer:
					decoration_layer.set_cell(tile, 9, Vector2i(0, 0))
				if path_layer:
					path_layer.set_cell(tile, -1)
			else:
				# Walkable path di layer Path (source 2, atlas (27, 12))
				if path_layer:
					path_layer.set_cell(tile, 2, Vector2i(27, 12))
				if decoration_layer:
					decoration_layer.set_cell(tile, -1)

func _spawn_skeleton_enemy(chunk: WildernessGen.ChunkData) -> void:
	var enemy := SkeletonEnemyClass.new()
	var center_pixel = get_chunk_center_pixel(chunk.grid_pos)
	enemy.position = center_pixel
	enemy.setup_stats(chunk.enemy_name, chunk.enemy_threat, chunk.enemy_tier, chunk.enemy_hp, chunk.enemy_atk)
	enemies_container.add_child(enemy)

# =========================================================================
# CHUNK-BY-CHUNK PLAYER MOVEMENT
# =========================================================================
func move_player_chunk(dir: Vector2i) -> void:
	if is_moving_chunk or current_maze == null:
		return
		
	var curr_chunk_data: WildernessGen.ChunkData = current_maze.chunks.get(current_chunk)
	if curr_chunk_data == null:
		return
		
	var can_move = false
	if dir == Vector2i.UP and curr_chunk_data.door_north and current_chunk.y > 0:
		can_move = true
	elif dir == Vector2i.DOWN and curr_chunk_data.door_south and current_chunk.y < WildernessGen.GRID_H - 1:
		can_move = true
	elif dir == Vector2i.LEFT and curr_chunk_data.door_west and current_chunk.x > 0:
		can_move = true
	elif dir == Vector2i.RIGHT and curr_chunk_data.door_east and current_chunk.x < WildernessGen.GRID_W - 1:
		can_move = true
		
	if not can_move:
		_show_feedback("Door is closed or wall blocked!")
		return
		
	var target_chunk = current_chunk + dir
	is_moving_chunk = true
	current_chunk = target_chunk
	var target_pixel = get_chunk_center_pixel(current_chunk)
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	if player_node:
		tween.tween_property(player_node, "global_position", target_pixel, 0.35)
	if camera:
		tween.tween_property(camera, "global_position", target_pixel, 0.38)
		
	tween.chain().tween_callback(func():
		is_moving_chunk = false
		_update_room_hud()
		if current_chunk == current_maze.portal_chunk:
			_show_feedback("🎉 PORTAL REACHED! DUNGEON CLEARED!")
	)

func _update_room_hud() -> void:
	if lbl_current_room == null or current_maze == null:
		return
	var c_data: WildernessGen.ChunkData = current_maze.chunks.get(current_chunk)
	if c_data == null:
		return
		
	var enemy_desc = "No Enemy"
	if c_data.has_enemy:
		enemy_desc = "⚠️ 1x %s (PWR %d)" % [c_data.enemy_name, int(c_data.enemy_threat)]
		
	var tag = ""
	if current_chunk == current_maze.start_chunk:
		tag = " [Start Room]"
	elif current_chunk == current_maze.portal_chunk:
		tag = " [PORTAL EXIT!]"
		
	lbl_current_room.text = "Room [%d, %d]: %s%s" % [current_chunk.x, current_chunk.y, enemy_desc, tag]
	
	if btn_move_north: btn_move_north.disabled = not (c_data.door_north and current_chunk.y > 0)
	if btn_move_south: btn_move_south.disabled = not (c_data.door_south and current_chunk.y < WildernessGen.GRID_H - 1)
	if btn_move_west: btn_move_west.disabled = not (c_data.door_west and current_chunk.x > 0)
	if btn_move_east: btn_move_east.disabled = not (c_data.door_east and current_chunk.x < WildernessGen.GRID_W - 1)

func _show_feedback(msg: String) -> void:
	if lbl_current_room:
		var prev = lbl_current_room.text
		lbl_current_room.text = msg
		lbl_current_room.modulate = Color("#FBBF24")
		await get_tree().create_timer(1.2).timeout
		lbl_current_room.modulate = Color.WHITE
		lbl_current_room.text = prev

# =========================================================================
# PATH LINE & ANALYTICS UI
# =========================================================================
func _draw_chunk_path(route: Array) -> void:
	if path_line == null:
		return
	path_line.clear_points()
	if not show_path_line or route.is_empty():
		return
	for c_pos in route:
		var pt = get_chunk_center_pixel(c_pos)
		path_line.add_point(pt)

func _toggle_path_line() -> void:
	show_path_line = not show_path_line
	if btn_toggle_path:
		btn_toggle_path.text = "Route: " + ("ON" if show_path_line else "OFF")
	if current_maze:
		_draw_chunk_path(current_maze.chunk_path)

func _update_ui_dashboard(maze: WildernessGen.MazeState, target_diff: float, algo_name: String) -> void:
	if lbl_status:
		var solv_str = "[OK] Solvable" if maze.is_solvable else "[FAIL] Blocked"
		lbl_status.text = "%s | %s" % [algo_name, solv_str]
		lbl_status.modulate = Color("#4ADE80") if maze.is_solvable else Color("#F43F5E")
		
	if lbl_energy:
		lbl_energy.text = "Energy / Cost: %.1f (Optimal)" % maze.energy
		
	if lbl_threat:
		lbl_threat.text = "Threat: %.1f / %.1f (Target)" % [maze.path_threat, target_diff]
		var gap = abs(maze.path_threat - target_diff)
		if gap <= 10.0:
			lbl_threat.modulate = Color("#4ADE80")
		elif gap <= 25.0:
			lbl_threat.modulate = Color("#FBBF24")
		else:
			lbl_threat.modulate = Color("#F43F5E")
			
	if lbl_path_len:
		lbl_path_len.text = "Path: %d Rooms (Portal @ [%d, %d])" % [maze.chunk_path.size(), maze.portal_chunk.x, maze.portal_chunk.y]
		
	if enemy_list_vbox:
		for c in enemy_list_vbox.get_children():
			c.queue_free()
			
		for c_pos in maze.chunk_path:
			var chunk: WildernessGen.ChunkData = maze.chunks[c_pos]
			if not chunk.has_enemy:
				continue
				
			var row := HBoxContainer.new()
			var rl := Label.new()
			rl.text = "Room [%d, %d]:" % [c_pos.x, c_pos.y]
			rl.add_theme_font_size_override("font_size", 10)
			rl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
			rl.custom_minimum_size = Vector2(85, 0)
			row.add_child(rl)
			
			var nl := Label.new()
			nl.text = chunk.enemy_name
			nl.add_theme_font_size_override("font_size", 10)
			nl.add_theme_color_override("font_color", Color.WHITE)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nl)
			
			var pl := Label.new()
			pl.text = "PWR:%d" % int(chunk.enemy_threat)
			pl.add_theme_font_size_override("font_size", 10)
			pl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
			row.add_child(pl)
			
			enemy_list_vbox.add_child(row)

func _return_to_overworld() -> void:
	get_tree().change_scene_to_file("res://Overworld.tscn")
