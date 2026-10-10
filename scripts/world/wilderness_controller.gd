class_name WildernessController
extends Node2D

## Controller Utama untuk Wilderness Map (CSP + Local Search)
## Mengatur alur Loading Screen, Debug Mode, Step-by-Step Graph Visualizer,
## rendering tilemap, spawning musuh & item yang bervariasi, serta navigasi player.

const WildernessGenClass = preload("res://scripts/world/wilderness_generator.gd")

@export var template_scene: PackedScene = preload("res://WildernessTemplate.tscn")
@export var hallway_length: int = 1 ## Panjang lorong (0 = menempel, 1 = default 1 tile)

# Template instance & Generator
var template_instance = null
var generator = null

# Layer TileMap (dinamis dicari agar kompatibel di berbagai struktur scene)
var water_foam_layer: TileMapLayer = null
var ground_layer: TileMapLayer = null
var path_layer: TileMapLayer = null
var decoration_layer: TileMapLayer = null
var player_node: CharacterBody2D = null
var camera: Camera2D = null

# Runtime containers
var enemies_container: Node2D = null
var items_container: Node2D = null
var portal_node: Node2D = null
var path_line: Line2D = null

# UI Canvas Layers & Panels
var ui_layer: CanvasLayer = null
var start_screen_panel: PanelContainer = null
var config_dialog_panel: PanelContainer = null
var visualizer_panel: PanelContainer = null
var ingame_hud_panel: PanelContainer = null

# Start & Config Widgets
var opt_difficulty: OptionButton = null
var opt_var_heuristic: OptionButton = null
var opt_val_heuristic: OptionButton = null
var opt_inference: OptionButton = null
var opt_local_search: OptionButton = null

# Ingame HUD Widgets
var lbl_current_room: Label = null
var lbl_hud_stats: Label = null
var btn_restart: Button = null
var btn_overworld: Button = null
var dpad_container: Control = null
var btn_move_north: Button = null
var btn_move_south: Button = null
var btn_move_west: Button = null
var btn_move_east: Button = null

# Visualizer State & Widgets
var visualizer_canvas: Control = null
var lbl_vis_title: Label = null
var lbl_vis_phase: Label = null
var lbl_vis_desc: Label = null
var lbl_vis_metrics: Label = null
var lbl_chunk_detail: RichTextLabel = null
var slider_vis_step: HSlider = null
var btn_vis_play: Button = null
var btn_vis_speed: Button = null

var timeline_steps: Array = []
var current_step_idx: int = 0
var is_vis_playing: bool = false
var vis_speed_multiplier: float = 1.0
var vis_timer: Timer = null
var selected_graph_chunk: Vector2i = Vector2i(-1, -1)

# Game State
var current_map_state = null
var current_chunk: Vector2i = Vector2i(0, 0)
var is_moving_chunk: bool = false
var last_generated_data: Dictionary = {}

func _ready() -> void:
	# 1. Instansiasi template scene untuk membaca data desain
	if template_scene:
		template_instance = template_scene.instantiate()
		add_child(template_instance)
		template_instance.visible = false
	
	generator = WildernessGenClass.new(template_instance)
	
	# 2. Cari layer TileMap dan nodes penting secara fleksibel
	_resolve_scene_nodes()
	_ensure_runtime_nodes()
	
	# Sembunyikan player dan dummy nodes sebelum game dimulai
	if player_node:
		player_node.visible = false
		if player_node.has_method("set_active"):
			player_node.set_active(false)
			
	var dummy_skel = get_node_or_null("Skeleton")
	if dummy_skel:
		dummy_skel.visible = false
		
	# 3. Bangun seluruh sistem UI (Loading Screen, Config, Visualizer, In-game HUD)
	_build_ui()
	
	# 4. Timer untuk animasi visualizer graph
	vis_timer = Timer.new()
	vis_timer.one_shot = false
	vis_timer.wait_time = 0.4
	vis_timer.timeout.connect(_on_vis_timer_tick)
	add_child(vis_timer)
	
	# Buka tampilan awal: Loading / Start Screen (TIDAK langsung freeze generate)
	_show_screen_state("START")

func _resolve_scene_nodes() -> void:
	water_foam_layer = _find_tile_layer(["Visuals/Water", "Visuals/WaterFoam", "Background/WaterFoam", "Background/Water", "WaterFoam", "Water"])
	ground_layer = _find_tile_layer(["Visuals/Ground", "Background/Ground", "Ground"])
	path_layer = _find_tile_layer(["Path", "Visuals/Path", "Background/Path"])
	decoration_layer = _find_tile_layer(["Visuals/Decoration", "Background/Decoration", "Decoration"])
	player_node = get_node_or_null("Player") as CharacterBody2D
	camera = get_node_or_null("Camera2D") as Camera2D

func _find_tile_layer(paths: Array) -> TileMapLayer:
	for p in paths:
		var n = get_node_or_null(p)
		if n is TileMapLayer:
			return n
	return null

func _ensure_runtime_nodes() -> void:
	if enemies_container == null:
		enemies_container = Node2D.new()
		enemies_container.name = "EnemiesContainer"
		enemies_container.z_index = 3
		add_child(enemies_container)
		
	if items_container == null:
		items_container = Node2D.new()
		items_container.name = "ItemsContainer"
		items_container.z_index = 2
		add_child(items_container)
		
	if portal_node == null:
		if template_instance:
			portal_node = template_instance.instantiate_portal()
		if portal_node == null:
			portal_node = Node2D.new()
			portal_node.name = "Portal"
		portal_node.z_index = 2
		add_child(portal_node)
		portal_node.visible = false
		
	if path_line == null:
		path_line = Line2D.new()
		path_line.name = "PathLine"
		path_line.width = 4.0
		path_line.default_color = Color(0.2, 0.85, 0.4, 0.7)
		path_line.z_index = 4
		add_child(path_line)

# =========================================================================
# SISTEM UI (START SCREEN, CONFIG DIALOG, GRAPH VISUALIZER, INGAME HUD)
# =========================================================================
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	
	_build_start_screen()
	_build_config_dialog()
	_build_graph_visualizer()
	_build_ingame_hud()

func _show_screen_state(state: String) -> void:
	if start_screen_panel: start_screen_panel.visible = (state == "START")
	if config_dialog_panel: config_dialog_panel.visible = (state == "CONFIG")
	if visualizer_panel: visualizer_panel.visible = (state == "VISUALIZER")
	if ingame_hud_panel: ingame_hud_panel.visible = (state == "PLAYING")
	if dpad_container: dpad_container.visible = (state == "PLAYING")

# --- 1. START SCREEN (Loading / Launch Menu) ---
func _build_start_screen() -> void:
	start_screen_panel = PanelContainer.new()
	start_screen_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.88)
	start_screen_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(start_screen_panel)
	
	var center := CenterContainer.new()
	start_screen_panel.add_child(center)
	
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 360)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	
	var title := Label.new()
	title.text = "⚔️ WILDERNESS EXPEDITION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#FBBF24"))
	box.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = "Hybrid CSP (MRV / LCV / AC-3) + Local Search Optimization"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	box.add_child(subtitle)
	
	box.add_child(HSeparator.new())
	
	var btn_start_fast := Button.new()
	btn_start_fast.text = "🚀 Start Exploration (Direct Play)"
	btn_start_fast.custom_minimum_size = Vector2(0, 50)
	btn_start_fast.add_theme_font_size_override("font_size", 15)
	btn_start_fast.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	btn_start_fast.pressed.connect(_on_start_exploration_fast)
	box.add_child(btn_start_fast)
	
	var btn_open_debug := Button.new()
	btn_open_debug.text = "🛠️ Debug Mode & Configuration"
	btn_open_debug.custom_minimum_size = Vector2(0, 46)
	btn_open_debug.add_theme_font_size_override("font_size", 14)
	btn_open_debug.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	btn_open_debug.pressed.connect(func(): _show_screen_state("CONFIG"))
	box.add_child(btn_open_debug)
	
	var btn_back_overworld := Button.new()
	btn_back_overworld.text = "🏠 Return to Overworld"
	btn_back_overworld.custom_minimum_size = Vector2(0, 40)
	btn_back_overworld.add_theme_font_size_override("font_size", 13)
	btn_back_overworld.pressed.connect(_return_to_overworld)
	box.add_child(btn_back_overworld)

# --- 2. CONFIGURATION PROMPT DIALOG ---
func _build_config_dialog() -> void:
	config_dialog_panel = PanelContainer.new()
	config_dialog_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.14, 0.92)
	config_dialog_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(config_dialog_panel)
	
	var center := CenterContainer.new()
	config_dialog_panel.add_child(center)
	
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 420)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	
	var title := Label.new()
	title.text = "⚙️ Map Generation Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#60A5FA"))
	box.add_child(title)
	
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	
	# 1. Difficulty
	var l_diff := Label.new()
	l_diff.text = "Target Difficulty:"
	grid.add_child(l_diff)
	opt_difficulty = OptionButton.new()
	opt_difficulty.add_item("Easy (Target: 40)", 0)
	opt_difficulty.add_item("Medium (Target: 80)", 1)
	opt_difficulty.add_item("Hard (Target: 140)", 2)
	opt_difficulty.selected = 1
	grid.add_child(opt_difficulty)
	
	# 2. CSP Variable Heuristic
	var l_var := Label.new()
	l_var.text = "CSP Variable Choice:"
	grid.add_child(l_var)
	opt_var_heuristic = OptionButton.new()
	opt_var_heuristic.add_item("Fixed Order", 0)
	opt_var_heuristic.add_item("MRV (Fail-First)", 1)
	opt_var_heuristic.add_item("MRV + Degree (Recommended)", 2)
	opt_var_heuristic.selected = 2
	grid.add_child(opt_var_heuristic)
	
	# 3. CSP Value Heuristic
	var l_val := Label.new()
	l_val.text = "CSP Value Ordering:"
	grid.add_child(l_val)
	opt_val_heuristic = OptionButton.new()
	opt_val_heuristic.add_item("Default / Shuffled", 0)
	opt_val_heuristic.add_item("LCV (Least Constraining)", 1)
	opt_val_heuristic.selected = 1
	grid.add_child(opt_val_heuristic)
	
	# 4. CSP Inference
	var l_inf := Label.new()
	l_inf.text = "Inference Constraint:"
	grid.add_child(l_inf)
	opt_inference = OptionButton.new()
	opt_inference.add_item("None (Standard Backtracking)", 0)
	opt_inference.add_item("Forward Checking", 1)
	opt_inference.add_item("AC-3 Arc Consistency", 2)
	opt_inference.selected = 2
	grid.add_child(opt_inference)
	
	# 5. Local Search Algo
	var l_ls := Label.new()
	l_ls.text = "Local Search Method:"
	grid.add_child(l_ls)
	opt_local_search = OptionButton.new()
	opt_local_search.add_item("Simulated Annealing", 0)
	opt_local_search.add_item("Hill Climbing (Random Restarts)", 1)
	opt_local_search.selected = 0
	grid.add_child(opt_local_search)
	
	box.add_child(HSeparator.new())
	
	var btn_run_vis := Button.new()
	btn_run_vis.text = "🎬 Generate & Open Step-by-Step Graph"
	btn_run_vis.custom_minimum_size = Vector2(0, 46)
	btn_run_vis.add_theme_font_size_override("font_size", 14)
	btn_run_vis.add_theme_color_override("font_color", Color("#FBBF24"))
	btn_run_vis.pressed.connect(_on_run_step_by_step_visualizer)
	box.add_child(btn_run_vis)
	
	var btn_run_play := Button.new()
	btn_run_play.text = "⚡ Instant Generate & Play"
	btn_run_play.custom_minimum_size = Vector2(0, 42)
	btn_run_play.add_theme_font_size_override("font_size", 13)
	btn_run_play.add_theme_color_override("font_color", Color("#4ADE80"))
	btn_run_play.pressed.connect(_on_start_exploration_fast)
	box.add_child(btn_run_play)
	
	var btn_cfg_back := Button.new()
	btn_cfg_back.text = "⬅️ Back to Menu"
	btn_cfg_back.custom_minimum_size = Vector2(0, 36)
	btn_cfg_back.pressed.connect(func(): _show_screen_state("START"))
	box.add_child(btn_cfg_back)

# --- 3. STEP-BY-STEP GRAPH VISUALIZER PANEL ---
func _build_graph_visualizer() -> void:
	visualizer_panel = PanelContainer.new()
	visualizer_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.15, 0.98)
	visualizer_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(visualizer_panel)
	
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 8)
	visualizer_panel.add_child(root_vbox)
	
	# Top bar
	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 44)
	root_vbox.add_child(top_bar)
	
	lbl_vis_title = Label.new()
	lbl_vis_title.text = "🧭 STEP-BY-STEP GRAPH SIMULATION"
	lbl_vis_title.add_theme_font_size_override("font_size", 16)
	lbl_vis_title.add_theme_color_override("font_color", Color("#FBBF24"))
	top_bar.add_child(lbl_vis_title)
	
	lbl_vis_phase = Label.new()
	lbl_vis_phase.text = " | Phase: CSP Backtracking (Step 0/0)"
	lbl_vis_phase.add_theme_font_size_override("font_size", 13)
	lbl_vis_phase.add_theme_color_override("font_color", Color("#60A5FA"))
	top_bar.add_child(lbl_vis_phase)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	
	var btn_vis_cancel := Button.new()
	btn_vis_cancel.text = "❌ Close / Menu"
	btn_vis_cancel.pressed.connect(func():
		vis_timer.stop()
		_show_screen_state("START")
	)
	top_bar.add_child(btn_vis_cancel)
	
	# Middle Section: Graph View (Kiri) + Inspector (Kanan)
	var middle_hbox := HBoxContainer.new()
	middle_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(middle_hbox)
	
	# Canvas Graf
	var graph_card := PanelContainer.new()
	graph_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_card.size_flags_stretch_ratio = 1.4
	var sb_g := StyleBoxFlat.new()
	sb_g.bg_color = Color(0.04, 0.06, 0.09, 0.95)
	sb_g.border_color = Color(0.25, 0.35, 0.5, 0.6)
	sb_g.set_border_width_all(1)
	sb_g.set_corner_radius_all(6)
	graph_card.add_theme_stylebox_override("panel", sb_g)
	middle_hbox.add_child(graph_card)
	
	visualizer_canvas = Control.new()
	visualizer_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	visualizer_canvas.draw.connect(_on_draw_graph_canvas)
	visualizer_canvas.gui_input.connect(_on_graph_canvas_gui_input)
	graph_card.add_child(visualizer_canvas)
	
	# Inspector Side Panel (Kanan)
	var inspect_card := PanelContainer.new()
	inspect_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_card.size_flags_stretch_ratio = 1.0
	var sb_i := StyleBoxFlat.new()
	sb_i.bg_color = Color(0.05, 0.07, 0.11, 0.95)
	sb_i.border_color = Color(0.25, 0.35, 0.5, 0.6)
	sb_i.set_border_width_all(1)
	sb_i.set_corner_radius_all(6)
	inspect_card.add_theme_stylebox_override("panel", sb_i)
	middle_hbox.add_child(inspect_card)
	
	var inspect_vbox := VBoxContainer.new()
	inspect_vbox.add_theme_constant_override("separation", 10)
	inspect_card.add_child(inspect_vbox)
	
	var l_card_title := Label.new()
	l_card_title.text = "📊 Chunk & Step Inspector"
	l_card_title.add_theme_font_size_override("font_size", 14)
	l_card_title.add_theme_color_override("font_color", Color("#93C5FD"))
	inspect_vbox.add_child(l_card_title)
	
	lbl_vis_desc = Label.new()
	lbl_vis_desc.text = "Klik node pada graf untuk melihat detail chunk."
	lbl_vis_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl_vis_desc.add_theme_font_size_override("font_size", 12)
	lbl_vis_desc.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	inspect_vbox.add_child(lbl_vis_desc)
	
	lbl_vis_metrics = Label.new()
	lbl_vis_metrics.text = "Assignments: 0 | Backtracks: 0"
	lbl_vis_metrics.add_theme_font_size_override("font_size", 11)
	lbl_vis_metrics.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	inspect_vbox.add_child(lbl_vis_metrics)
	
	inspect_vbox.add_child(HSeparator.new())
	
	lbl_chunk_detail = RichTextLabel.new()
	lbl_chunk_detail.bbcode_enabled = true
	lbl_chunk_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_chunk_detail.text = "[color=#94A3B8]Pilih salah satu lingkaran node pada graf untuk memeriksa koordinat, pintu, dan entitasnya.[/color]"
	inspect_vbox.add_child(lbl_chunk_detail)
	
	# Bottom Controls: Navigation timeline & enter map
	var bottom_card := PanelContainer.new()
	bottom_card.custom_minimum_size = Vector2(0, 72)
	var sb_b := StyleBoxFlat.new()
	sb_b.bg_color = Color(0.05, 0.08, 0.12, 0.95)
	sb_b.set_border_width_all(1)
	sb_b.border_color = Color(0.2, 0.3, 0.4, 0.6)
	bottom_card.add_theme_stylebox_override("panel", sb_b)
	root_vbox.add_child(bottom_card)
	
	var bot_vbox := VBoxContainer.new()
	bot_vbox.add_theme_constant_override("separation", 6)
	bottom_card.add_child(bot_vbox)
	
	slider_vis_step = HSlider.new()
	slider_vis_step.min_value = 0
	slider_vis_step.max_value = 1
	slider_vis_step.value_changed.connect(_on_slider_vis_step_changed)
	bot_vbox.add_child(slider_vis_step)
	
	var bot_hbox := HBoxContainer.new()
	bot_hbox.add_theme_constant_override("separation", 8)
	bot_vbox.add_child(bot_hbox)
	
	var btn_first := Button.new()
	btn_first.text = "|<< First"
	btn_first.pressed.connect(func(): _go_to_step(0))
	bot_hbox.add_child(btn_first)
	
	var btn_prev := Button.new()
	btn_prev.text = "< Prev"
	btn_prev.pressed.connect(func(): _go_to_step(current_step_idx - 1))
	bot_hbox.add_child(btn_prev)
	
	btn_vis_play = Button.new()
	btn_vis_play.text = "▶ Play"
	btn_vis_play.pressed.connect(_toggle_vis_play)
	bot_hbox.add_child(btn_vis_play)
	
	var btn_next := Button.new()
	btn_next.text = "Next >"
	btn_next.pressed.connect(func(): _go_to_step(current_step_idx + 1))
	bot_hbox.add_child(btn_next)
	
	var btn_last := Button.new()
	btn_last.text = ">>| Last"
	btn_last.pressed.connect(func(): _go_to_step(timeline_steps.size() - 1))
	bot_hbox.add_child(btn_last)
	
	btn_vis_speed = Button.new()
	btn_vis_speed.text = "Speed: 1x"
	btn_vis_speed.pressed.connect(_toggle_vis_speed)
	bot_hbox.add_child(btn_vis_speed)
	
	var bot_spacer := Control.new()
	bot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_hbox.add_child(bot_spacer)
	
	var btn_enter_game := Button.new()
	btn_enter_game.text = "🚀 Enter Map (Play Now)"
	btn_enter_game.custom_minimum_size = Vector2(210, 36)
	btn_enter_game.add_theme_font_size_override("font_size", 14)
	btn_enter_game.add_theme_color_override("font_color", Color("#4ADE80"))
	btn_enter_game.pressed.connect(_on_enter_game_from_vis)
	bot_hbox.add_child(btn_enter_game)

# --- 4. IN-GAME HUD (Playable Section) ---
func _build_ingame_hud() -> void:
	ingame_hud_panel = PanelContainer.new()
	ingame_hud_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ingame_hud_panel.custom_minimum_size = Vector2(0, 52)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.88)
	sb.border_color = Color(0.2, 0.3, 0.45, 0.5)
	sb.border_width_bottom = 2
	ingame_hud_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(ingame_hud_panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	ingame_hud_panel.add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)
	
	lbl_current_room = Label.new()
	lbl_current_room.text = "Room [0, 0] 🟢 Start"
	lbl_current_room.custom_minimum_size = Vector2(220, 0)
	lbl_current_room.add_theme_font_size_override("font_size", 14)
	lbl_current_room.add_theme_color_override("font_color", Color("#FBBF24"))
	hbox.add_child(lbl_current_room)
	
	hbox.add_child(VSeparator.new())
	
	lbl_hud_stats = Label.new()
	lbl_hud_stats.text = "Threat: 80 / 80 | Solvable: Yes | Path: 6 Rooms"
	lbl_hud_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_hud_stats.add_theme_font_size_override("font_size", 12)
	lbl_hud_stats.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	hbox.add_child(lbl_hud_stats)
	
	# Tombol Restart: Mengembalikan fresh ke awal scene (tanpa in-place regenerate rawan crash)
	btn_restart = Button.new()
	btn_restart.text = "🔄 Restart Run"
	btn_restart.custom_minimum_size = Vector2(120, 34)
	btn_restart.add_theme_color_override("font_color", Color("#F87171"))
	btn_restart.pressed.connect(func():
		get_tree().reload_current_scene()
	)
	hbox.add_child(btn_restart)
	
	btn_overworld = Button.new()
	btn_overworld.text = "🏠 Overworld"
	btn_overworld.custom_minimum_size = Vector2(100, 34)
	btn_overworld.pressed.connect(_return_to_overworld)
	hbox.add_child(btn_overworld)
	
	# D-pad kontrol arah
	_build_dpad_ui()

func _build_dpad_ui() -> void:
	dpad_container = Control.new()
	dpad_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dpad_container.position = Vector2(-170, -170)
	ui_layer.add_child(dpad_container)
	
	var dpad_box := Control.new()
	dpad_box.custom_minimum_size = Vector2(150, 150)
	dpad_container.add_child(dpad_box)
	
	btn_move_north = _create_dpad_btn("▲", Vector2i.UP)
	btn_move_north.position = Vector2(50, 0)
	dpad_box.add_child(btn_move_north)
	
	btn_move_west = _create_dpad_btn("◀", Vector2i.LEFT)
	btn_move_west.position = Vector2(0, 50)
	dpad_box.add_child(btn_move_west)
	
	btn_move_east = _create_dpad_btn("▶", Vector2i.RIGHT)
	btn_move_east.position = Vector2(100, 50)
	dpad_box.add_child(btn_move_east)
	
	btn_move_south = _create_dpad_btn("▼", Vector2i.DOWN)
	btn_move_south.position = Vector2(50, 100)
	dpad_box.add_child(btn_move_south)

func _create_dpad_btn(arrow: String, dir: Vector2i) -> Button:
	var b := Button.new()
	b.text = arrow
	b.custom_minimum_size = Vector2(46, 46)
	b.pressed.connect(func(): move_player_chunk(dir))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if ingame_hud_panel == null or not ingame_hud_panel.visible:
		return
	if is_moving_chunk:
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("up"):
		move_player_chunk(Vector2i.UP)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("down"):
		move_player_chunk(Vector2i.DOWN)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("left"):
		move_player_chunk(Vector2i.LEFT)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("right"):
		move_player_chunk(Vector2i.RIGHT)

# =========================================================================
# EKSEKUSI GENERASI MAP & LOGIKA STEP-BY-STEP
# =========================================================================
func get_target_difficulty() -> float:
	var idx = opt_difficulty.selected if opt_difficulty else 1
	match idx:
		0: return 40.0
		1: return 80.0
		2: return 140.0
		_: return 80.0

func _on_start_exploration_fast() -> void:
	var var_h = opt_var_heuristic.selected if opt_var_heuristic else 2
	var val_h = opt_val_heuristic.selected if opt_val_heuristic else 1
	var inf_m = opt_inference.selected if opt_inference else 2
	var target_diff = get_target_difficulty()
	var ls_algo = "simulated_annealing" if (opt_local_search and opt_local_search.selected == 0) else "hill_climbing"
	
	var res = generator.generate_full_map_with_timeline(var_h, val_h, inf_m, target_diff, ls_algo, 80)
	last_generated_data = res
	current_map_state = res.final_state
	current_chunk = current_map_state.start_chunk
	
	_render_map(current_map_state, res.csp_res.csp_result, res.ls_res)
	_show_screen_state("PLAYING")

func _on_run_step_by_step_visualizer() -> void:
	var var_h = opt_var_heuristic.selected if opt_var_heuristic else 2
	var val_h = opt_val_heuristic.selected if opt_val_heuristic else 1
	var inf_m = opt_inference.selected if opt_inference else 2
	var target_diff = get_target_difficulty()
	var ls_algo = "simulated_annealing" if (opt_local_search and opt_local_search.selected == 0) else "hill_climbing"
	
	var res = generator.generate_full_map_with_timeline(var_h, val_h, inf_m, target_diff, ls_algo, 80)
	last_generated_data = res
	timeline_steps = res.timeline
	current_map_state = res.final_state
	
	slider_vis_step.max_value = max(0, timeline_steps.size() - 1)
	_show_screen_state("VISUALIZER")
	_go_to_step(0)

func _on_enter_game_from_vis() -> void:
	vis_timer.stop()
	if last_generated_data.has("final_state"):
		current_map_state = last_generated_data.final_state
		current_chunk = current_map_state.start_chunk
		_render_map(current_map_state, last_generated_data.csp_res.csp_result, last_generated_data.ls_res)
	_show_screen_state("PLAYING")

# --- Visualizer Timeline Playback ---
func _go_to_step(idx: int) -> void:
	if timeline_steps.is_empty():
		return
	current_step_idx = clampi(idx, 0, timeline_steps.size() - 1)
	slider_vis_step.value = current_step_idx
	_update_visualizer_view()

func _on_slider_vis_step_changed(val: float) -> void:
	var idx = int(val)
	if idx != current_step_idx:
		_go_to_step(idx)

func _toggle_vis_play() -> void:
	is_vis_playing = not is_vis_playing
	if is_vis_playing:
		btn_vis_play.text = "⏸ Pause"
		vis_timer.wait_time = 0.4 / vis_speed_multiplier
		vis_timer.start()
	else:
		btn_vis_play.text = "▶ Play"
		vis_timer.stop()

func _toggle_vis_speed() -> void:
	if vis_speed_multiplier == 1.0:
		vis_speed_multiplier = 2.0
		btn_vis_speed.text = "Speed: 2x"
	elif vis_speed_multiplier == 2.0:
		vis_speed_multiplier = 0.5
		btn_vis_speed.text = "Speed: 0.5x"
	else:
		vis_speed_multiplier = 1.0
		btn_vis_speed.text = "Speed: 1x"
		
	if is_vis_playing:
		vis_timer.wait_time = 0.4 / vis_speed_multiplier

func _on_vis_timer_tick() -> void:
	if current_step_idx >= timeline_steps.size() - 1:
		_toggle_vis_play() # Stop at the end
		return
	_go_to_step(current_step_idx + 1)

func _update_visualizer_view() -> void:
	if timeline_steps.is_empty():
		return
		
	var step_data: Dictionary = timeline_steps[current_step_idx]
	var phase = step_data.get("phase", "csp")
	var phase_str = "CSP Backtracking" if phase == "csp" else "Local Search Optimization"
	
	lbl_vis_phase.text = " | Phase: %s (Step %d/%d)" % [phase_str, current_step_idx + 1, timeline_steps.size()]
	lbl_vis_desc.text = step_data.get("desc", "")
	
	if phase == "csp":
		lbl_vis_metrics.text = "CSP Type: %s | Active Var: %s" % [step_data.get("type", ""), str(step_data.get("var", "-"))]
	else:
		lbl_vis_metrics.text = "Temp: %.1f | Energy: %.1f | Diff: %.1f" % [step_data.get("temp", 0.0), step_data.get("energy", 0.0), step_data.get("diff", 0.0)]
		
	if visualizer_canvas:
		visualizer_canvas.queue_redraw()
		
	_update_chunk_inspector()

# =========================================================================
# RENDERING TOPOLOGICAL GRAPH CHUNK (CANVAS)
# =========================================================================
func _on_draw_graph_canvas() -> void:
	if visualizer_canvas == null or timeline_steps.is_empty():
		return
		
	var rect = visualizer_canvas.get_rect()
	var gw = current_map_state.grid_w if current_map_state else 5
	var gh = current_map_state.grid_h if current_map_state else 5
	
	var step_data = timeline_steps[current_step_idx]
	var phase = step_data.get("phase", "csp")
	var assignments = {}
	var entities = {}
	var start_c = current_map_state.start_chunk if current_map_state else Vector2i(0, 0)
	var portal_c = current_map_state.portal_chunk if current_map_state else Vector2i(gw-1, gh-1)
	
	if phase == "csp":
		assignments = step_data.get("assignments", {})
	else:
		var st = step_data.get("state", null)
		if st:
			assignments = st.chunk_templates
			entities = st.chunk_entities
			start_c = st.start_chunk
			portal_c = st.portal_chunk
			
	var active_var = step_data.get("var", null)
	
	# Margin dan Cell metrics
	var pad = 40.0
	var cell_w = (rect.size.x - pad * 2.0) / float(gw)
	var cell_h = (rect.size.y - pad * 2.0) / float(gh)
	var radius = min(cell_w, cell_h) * 0.32
	
	var raw_templates = template_instance.get_chunk_templates() if template_instance else []
	var tpl_dict: Dictionary = {}
	for t in raw_templates:
		tpl_dict[t.id] = t
		
	# 1. Gambar Edges / Koneksi Lorong Antar Chunk
	for cx in range(gw):
		for cy in range(gh):
			var pos = Vector2i(cx, cy)
			var tpl_id = assignments.get(pos, "")
			if tpl_id == "" or tpl_id == "SOLID":
				continue
			var tpl = tpl_dict.get(tpl_id)
			if tpl == null:
				continue
				
			var c_px = Vector2(pad + (float(cx) + 0.5) * cell_w, pad + (float(cy) + 0.5) * cell_h)
			
			# Hubungan ke Timur
			if cx < gw - 1 and tpl.doors[2]:
				var east_pos = pos + Vector2i(1, 0)
				var east_tpl = tpl_dict.get(assignments.get(east_pos, ""))
				if east_tpl != null and east_tpl.doors[3]:
					var east_px = Vector2(pad + (float(cx + 1) + 0.5) * cell_w, pad + (float(cy) + 0.5) * cell_h)
					visualizer_canvas.draw_line(c_px, east_px, Color(0.22, 0.74, 0.97, 0.8), 5.0)
					
			# Hubungan ke Selatan
			if cy < gh - 1 and tpl.doors[1]:
				var south_pos = pos + Vector2i(0, 1)
				var south_tpl = tpl_dict.get(assignments.get(south_pos, ""))
				if south_tpl != null and south_tpl.doors[0]:
					var south_px = Vector2(pad + (float(cx) + 0.5) * cell_w, pad + (float(cy + 1) + 0.5) * cell_h)
					visualizer_canvas.draw_line(c_px, south_px, Color(0.22, 0.74, 0.97, 0.8), 5.0)

	# 2. Gambar Nodes (Lingkaran Chunk)
	for cx in range(gw):
		for cy in range(gh):
			var pos = Vector2i(cx, cy)
			var center_pt = Vector2(pad + (float(cx) + 0.5) * cell_w, pad + (float(cy) + 0.5) * cell_h)
			var tpl_id = assignments.get(pos, "")
			
			var bg_color = Color(0.18, 0.22, 0.28, 0.5) # Default unassigned
			var border_color = Color(0.35, 0.42, 0.52, 0.7)
			var label_str = "%d,%d" % [cx, cy]
			
			if tpl_id != "":
				if tpl_id == "SOLID":
					bg_color = Color(0.12, 0.14, 0.18, 0.9) # Solid wall
					border_color = Color(0.25, 0.28, 0.35, 0.8)
				else:
					bg_color = Color(0.15, 0.35, 0.65, 0.9) # Assigned room
					border_color = Color(0.38, 0.68, 0.98, 1.0)
					
			if pos == start_c:
				bg_color = Color(0.13, 0.65, 0.34, 0.95)
				border_color = Color(0.3, 0.95, 0.5, 1.0)
				label_str = "S"
			elif pos == portal_c:
				bg_color = Color(0.55, 0.20, 0.75, 0.95)
				border_color = Color(0.85, 0.4, 0.98, 1.0)
				label_str = "EXIT"
				
			# Highlight node yang aktif dimutasi/di-assign pada step ini
			if active_var != null and pos == active_var:
				border_color = Color("#F59E0B")
				visualizer_canvas.draw_arc(center_pt, radius + 6.0, 0, TAU, 32, Color("#F59E0B"), 3.5)
				
			# Highlight node yang dipilih oleh user
			if pos == selected_graph_chunk:
				visualizer_canvas.draw_arc(center_pt, radius + 4.0, 0, TAU, 32, Color.WHITE, 2.5)
				
			visualizer_canvas.draw_circle(center_pt, radius, bg_color)
			visualizer_canvas.draw_arc(center_pt, radius, 0, TAU, 32, border_color, 2.0)
			
			# Entity symbol jika fase Local Search
			if entities.has(pos):
				var ent = entities[pos]
				if ent.type == "enemy":
					visualizer_canvas.draw_circle(center_pt + Vector2(0, -radius * 0.45), 4.0, Color("#EF4444"))
				elif ent.type == "item":
					visualizer_canvas.draw_circle(center_pt + Vector2(0, -radius * 0.45), 4.0, Color("#EAB308"))
					
			visualizer_canvas.draw_string(
				ThemeDB.fallback_font,
				center_pt + Vector2(-radius * 0.5, 4),
				label_str,
				HORIZONTAL_ALIGNMENT_CENTER,
				radius,
				11,
				Color.WHITE
			)

func _on_graph_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var rect = visualizer_canvas.get_rect()
		var gw = current_map_state.grid_w if current_map_state else 5
		var gh = current_map_state.grid_h if current_map_state else 5
		var pad = 40.0
		var cell_w = (rect.size.x - pad * 2.0) / float(gw)
		var cell_h = (rect.size.y - pad * 2.0) / float(gh)
		
		var click_pos = event.position - Vector2(pad, pad)
		var cx = int(click_pos.x / cell_w)
		var cy = int(click_pos.y / cell_h)
		
		if cx >= 0 and cx < gw and cy >= 0 and cy < gh:
			selected_graph_chunk = Vector2i(cx, cy)
			visualizer_canvas.queue_redraw()
			_update_chunk_inspector()

func _update_chunk_inspector() -> void:
	if lbl_chunk_detail == null or timeline_steps.is_empty():
		return
		
	if selected_graph_chunk == Vector2i(-1, -1):
		# Default pilih start_chunk
		selected_graph_chunk = current_map_state.start_chunk if current_map_state else Vector2i(0, 0)
		
	var pos = selected_graph_chunk
	var step_data = timeline_steps[current_step_idx]
	var phase = step_data.get("phase", "csp")
	var assignments = {}
	var entities = {}
	var domains = step_data.get("domains", {})
	
	if phase == "csp":
		assignments = step_data.get("assignments", {})
	else:
		var st = step_data.get("state", null)
		if st:
			assignments = st.chunk_templates
			entities = st.chunk_entities
			
	var tpl_id = assignments.get(pos, "UNASSIGNED")
	var raw_templates = template_instance.get_chunk_templates() if template_instance else []
	var tpl_name = "-"
	var doors_str = "N: ?, S: ?, E: ?, W: ?"
	for t in raw_templates:
		if t.id == tpl_id:
			tpl_name = t.get("name", tpl_id)
			doors_str = "N: %s, S: %s, E: %s, W: %s" % [
				"✓" if t.doors[0] else "✗",
				"✓" if t.doors[1] else "✗",
				"✓" if t.doors[2] else "✗",
				"✓" if t.doors[3] else "✗"
			]
			break
			
	var tag = ""
	if pos == (current_map_state.start_chunk if current_map_state else Vector2i.ZERO):
		tag = " [color=#22C55E](PLAYER SPAWN COASTLINE)[/color]"
	elif pos == (current_map_state.portal_chunk if current_map_state else Vector2i.ZERO):
		tag = " [color=#A855F7](EXIT PORTAL)[/color]"
		
	var ent_desc = "Empty / None"
	if entities.has(pos):
		var ent = entities[pos]
		if ent.type == "enemy":
			ent_desc = "[color=#EF4444]👾 %s (Tier: %s, Threat: %.1f, HP: %d, ATK: %d)[/color]" % [ent.name, ent.tier, ent.threat, ent.hp, ent.atk]
		elif ent.type == "item":
			ent_desc = "[color=#EAB308]💎 %s (+%.1f Benefit)[/color]" % [ent.name, ent.benefit]
			
	var domain_left = domains.get(pos, [])
	var domain_str = str(domain_left) if not domain_left.is_empty() else "[color=#64748B]Assigned / Pruned[/color]"
	
	var bb = "[b]Selected Chunk:[/b] [color=#FBBF24][%d, %d][/color]%s
" % [pos.x, pos.y, tag]
	bb += "[b]Template:[/b] %s (%s)
" % [tpl_id, tpl_name]
	bb += "[b]Doors:[/b] %s
" % doors_str
	bb += "[b]Entity:[/b] %s
" % ent_desc
	bb += "[b]CSP Domain Candidates (%d):[/b] %s" % [domain_left.size(), domain_str]
	
	lbl_chunk_detail.text = bb

# =========================================================================
# CHUNK-TO-PIXEL CONVERSION & MAP RENDERING
# =========================================================================
func get_chunk_tile_origin(c_pos: Vector2i) -> Vector2i:
	var p = template_instance.chunk_size_p if template_instance else 7
	var q = template_instance.chunk_size_q if template_instance else 7
	var stride_x = p + hallway_length
	var stride_y = q + hallway_length
	return Vector2i(c_pos.x * stride_x, c_pos.y * stride_y)

func get_chunk_center_pixel(c_pos: Vector2i) -> Vector2:
	var p = template_instance.chunk_size_p if template_instance else 7
	var q = template_instance.chunk_size_q if template_instance else 7
	var orig = get_chunk_tile_origin(c_pos)
	return Vector2(float(orig.x) + float(p) * 0.5, float(orig.y) + float(q) * 0.5) * 64.0

func _render_map(state, csp_stats: Dictionary, ls_stats: Dictionary) -> void:
	if state == null:
		return
		
	# 1. Bersihkan seluruh tile layer sebelum menggambar map baru
	if water_foam_layer:
		water_foam_layer.clear()
	if ground_layer:
		ground_layer.clear()
	if path_layer:
		path_layer.clear()
	if decoration_layer:
		decoration_layer.clear()
		
	# Bersihkan spawn container
	if enemies_container:
		for c in enemies_container.get_children():
			c.queue_free()
	if items_container:
		for c in items_container.get_children():
			c.queue_free()
			
	var gw = state.grid_w
	var gh = state.grid_h
	
	# 2. Gambar setiap chunk menggunakan tile yang dibaca dari WildernessTemplate
	for cy in range(gh):
		for cx in range(gw):
			var c_pos = Vector2i(cx, cy)
			var tpl_id = state.chunk_templates.get(c_pos, "SOLID")
			var orig = get_chunk_tile_origin(c_pos)
			var tile_data = template_instance.get_chunk_tiles(tpl_id) if template_instance else {}
			
			# Layer WaterFoam
			var w_tiles = tile_data.get("water_foam", tile_data.get("water", []))
			if water_foam_layer and not w_tiles.is_empty():
				for entry in w_tiles:
					water_foam_layer.set_cell(orig + entry.offset, entry.source_id, entry.atlas_coords, entry.alt)

			# Layer Ground
			if ground_layer and tile_data.has("ground") and not tile_data["ground"].is_empty():
				for entry in tile_data["ground"]:
					ground_layer.set_cell(orig + entry.offset, entry.source_id, entry.atlas_coords, entry.alt)
					
			# Layer Path
			if path_layer and tile_data.has("path"):
				for entry in tile_data["path"]:
					path_layer.set_cell(orig + entry.offset, entry.source_id, entry.atlas_coords, entry.alt)
					
			# Layer Decoration
			if decoration_layer and tile_data.has("decoration"):
				for entry in tile_data["decoration"]:
					decoration_layer.set_cell(orig + entry.offset, entry.source_id, entry.atlas_coords, entry.alt)

	# 2b. Gambar Hallway jika hallway_length > 0
	if hallway_length > 0:
		_render_hallways(state)

	# 3. Spawn Player di Start Room (Coastline)
	var start_pixel = get_chunk_center_pixel(state.start_chunk)
	if player_node:
		player_node.visible = true
		player_node.global_position = start_pixel
		if player_node.has_method("set_active"):
			player_node.set_active(true)
			
	if camera:
		camera.global_position = start_pixel
		
	# 4. Spawn Portal di Portal Chunk
	if portal_node:
		portal_node.visible = true
		portal_node.global_position = get_chunk_center_pixel(state.portal_chunk)
		
	# 5. Spawn Enemies & Items dari data hasil Local Search
	for c_pos in state.chunk_entities.keys():
		var ent = state.chunk_entities[c_pos]
		var px_center = get_chunk_center_pixel(c_pos)
		
		if ent.type == "enemy":
			var e_node = template_instance.instantiate_enemy(ent.node_name) if template_instance else null
			if e_node:
				e_node.global_position = px_center
				enemies_container.add_child(e_node)
		elif ent.type == "item":
			var i_node = template_instance.instantiate_item(ent.node_name) if template_instance else null
			if i_node:
				i_node.global_position = px_center
				items_container.add_child(i_node)
				
	_draw_chunk_path(state.chunk_path)
	_update_room_hud()
	
	if lbl_hud_stats:
		lbl_hud_stats.text = "Threat: %.1f / %.1f | Path: %d Rooms | Solvable: %s" % [
			state.difficulty_score,
			get_target_difficulty(),
			state.chunk_path.size(),
			"Yes" if state.is_solvable else "No"
		]

func _draw_chunk_path(route: Array) -> void:
	if path_line == null:
		return
	path_line.clear_points()
	for c_pos in route:
		path_line.add_point(get_chunk_center_pixel(c_pos))

# =========================================================================
# NAVIGASI PLAYER ANTAR CHUNK
# =========================================================================
func move_player_chunk(dir: Vector2i) -> void:
	if is_moving_chunk or current_map_state == null:
		return
		
	var target = current_chunk + dir
	if target.x < 0 or target.x >= current_map_state.grid_w or target.y < 0 or target.y >= current_map_state.grid_h:
		return
		
	var c_tpl_id = current_map_state.chunk_templates.get(current_chunk, "SOLID")
	var t_tpl_id = current_map_state.chunk_templates.get(target, "SOLID")
	var tpl_mgr = template_instance
	var c_doors = tpl_mgr.get_template_by_id(c_tpl_id).doors if tpl_mgr else [false, false, false, false]
	var t_doors = tpl_mgr.get_template_by_id(t_tpl_id).doors if tpl_mgr else [false, false, false, false]
	
	var can_exit = false
	var can_enter = false
	if dir == Vector2i.UP:
		can_exit = c_doors[0]; can_enter = t_doors[1]
	elif dir == Vector2i.DOWN:
		can_exit = c_doors[1]; can_enter = t_doors[0]
	elif dir == Vector2i.RIGHT:
		can_exit = c_doors[2]; can_enter = t_doors[3]
	elif dir == Vector2i.LEFT:
		can_exit = c_doors[3]; can_enter = t_doors[2]
		
	if not (can_exit and can_enter):
		return
		
	current_chunk = target
	_animate_player_to_chunk(current_chunk)

func _animate_player_to_chunk(c_pos: Vector2i) -> void:
	is_moving_chunk = true
	var target_px = get_chunk_center_pixel(c_pos)
	if player_node:
		var tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(player_node, "global_position", target_px, 0.22)
		tw.tween_callback(func():
			is_moving_chunk = false
			_update_room_hud()
		)
	else:
		is_moving_chunk = false
		_update_room_hud()

func _update_room_hud() -> void:
	if lbl_current_room == null or current_map_state == null:
		return
	var text = "Room [%d, %d]" % [current_chunk.x, current_chunk.y]
	if current_chunk == current_map_state.start_chunk:
		text += " 🟢 Start"
	elif current_chunk == current_map_state.portal_chunk:
		text += " 🌀 Exit Portal"
	else:
		var ent = current_map_state.chunk_entities.get(current_chunk, { "type": "empty" })
		if ent.type == "enemy":
			text += " 👾 " + ent.name
		elif ent.type == "item":
			text += " 💎 " + ent.name
		else:
			text += " (Clear)"
	lbl_current_room.text = text

func _return_to_overworld() -> void:
	get_tree().change_scene_to_file("res://Overworld.tscn")

# =========================================================================
# LORONG / HALLWAY RENDERING (MENYAMBUNG DOOR ANGKUT AIR, PATH, DECORATION)
# =========================================================================
func _render_hallways(state) -> void:
	var gw = state.grid_w
	var gh = state.grid_h
	var p = template_instance.chunk_size_p if template_instance else 7
	var q = template_instance.chunk_size_q if template_instance else 7
	var h_slice = template_instance.get_hallway_h_slice() if template_instance else {}
	var v_slice = template_instance.get_hallway_v_slice() if template_instance else {}
	
	for cy in range(gh):
		for cx in range(gw):
			var c_pos = Vector2i(cx, cy)
			var tpl_id = state.chunk_templates.get(c_pos, "SOLID")
			var tpl = template_instance.get_template_by_id(tpl_id) if template_instance else {}
			var doors = tpl.get("doors", [true, true, true, true])
			var orig = get_chunk_tile_origin(c_pos)
			
			# 1. Hallway Horizontal (Pintu Timur)
			if cx < gw - 1:
				var east_pos = c_pos + Vector2i(1, 0)
				var east_tpl_id = state.chunk_templates.get(east_pos, "SOLID")
				var east_tpl = template_instance.get_template_by_id(east_tpl_id) if template_instance else {}
				var east_doors = east_tpl.get("doors", [true, true, true, true])
				var is_open = doors[2] and east_doors[3]
				var h_offset = orig + Vector2i(p, 0)
				
				if is_open and not h_slice.is_empty():
					for step in range(hallway_length):
						var col_offset = h_offset + Vector2i(step, 0)
						var h_w = h_slice.get("water_foam", h_slice.get("water", []))
						if water_foam_layer and not h_w.is_empty():
							for entry in h_w:
								water_foam_layer.set_cell(col_offset + Vector2i(0, entry.y), entry.source_id, entry.atlas_coords, entry.alt)
						if ground_layer and h_slice.has("ground"):
							for entry in h_slice["ground"]:
								ground_layer.set_cell(col_offset + Vector2i(0, entry.y), entry.source_id, entry.atlas_coords, entry.alt)
						if path_layer and h_slice.has("path"):
							for entry in h_slice["path"]:
								path_layer.set_cell(col_offset + Vector2i(0, entry.y), entry.source_id, entry.atlas_coords, entry.alt)
						if decoration_layer and h_slice.has("decoration"):
							for entry in h_slice["decoration"]:
								decoration_layer.set_cell(col_offset + Vector2i(0, entry.y), entry.source_id, entry.atlas_coords, entry.alt)
							
			# 2. Hallway Vertikal (Pintu Selatan)
			if cy < gh - 1:
				var south_pos = c_pos + Vector2i(0, 1)
				var south_tpl_id = state.chunk_templates.get(south_pos, "SOLID")
				var south_tpl = template_instance.get_template_by_id(south_tpl_id) if template_instance else {}
				var south_doors = south_tpl.get("doors", [true, true, true, true])
				var is_open = doors[1] and south_doors[0]
				var v_offset = orig + Vector2i(0, q)
				
				if is_open and not v_slice.is_empty():
					for step in range(hallway_length):
						var row_offset = v_offset + Vector2i(0, step)
						var v_w = v_slice.get("water_foam", v_slice.get("water", []))
						if water_foam_layer and not v_w.is_empty():
							for entry in v_w:
								water_foam_layer.set_cell(row_offset + Vector2i(entry.x, 0), entry.source_id, entry.atlas_coords, entry.alt)
						if ground_layer and v_slice.has("ground"):
							for entry in v_slice["ground"]:
								ground_layer.set_cell(row_offset + Vector2i(entry.x, 0), entry.source_id, entry.atlas_coords, entry.alt)
						if path_layer and v_slice.has("path"):
							for entry in v_slice["path"]:
								path_layer.set_cell(row_offset + Vector2i(entry.x, 0), entry.source_id, entry.atlas_coords, entry.alt)
						if decoration_layer and v_slice.has("decoration"):
							for entry in v_slice["decoration"]:
								decoration_layer.set_cell(row_offset + Vector2i(entry.x, 0), entry.source_id, entry.atlas_coords, entry.alt)
