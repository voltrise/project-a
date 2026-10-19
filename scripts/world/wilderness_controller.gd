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

# Player Status HUD Widgets
var lbl_player_hp: Label = null
var hp_bar: ProgressBar = null
var lbl_buff_title: Label = null
var buffs_box: HBoxContainer = null
var recap_modal_panel: PanelContainer = null

# Ingame HUD Widgets
var lbl_current_room: Label = null
var lbl_hud_stats: Label = null
var btn_restart: Button = null
var btn_overworld: Button = null
var is_event_busy: bool = false

# Debug Menu & Overlay Widgets
var debug_menu_panel: PanelContainer = null
var debug_grid_overlay: Node2D = null
var chk_debug_optimal_path: CheckBox = null
var chk_debug_grid: CheckBox = null
var chk_debug_skip_battle: CheckBox = null
var chk_debug_ai_stats: CheckBox = null
var btn_debug_toggle: Button = null
var debug_ai_stats_card: PanelContainer = null
var lbl_debug_ai_stats_content: RichTextLabel = null
var teleport_modal_panel: PanelContainer = null
var teleport_canvas: Control = null
var last_csp_stats: Dictionary = {}
var last_ls_stats: Dictionary = {}

# Visualizer State & Widgets
var visualizer_canvas: Control = null
var lbl_vis_title: Label = null
var lbl_vis_phase: Label = null
var lbl_vis_desc: Label = null
var lbl_vis_metrics: Label = null
var lbl_step_detail: RichTextLabel = null
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
var last_generated_data: Dictionary = {}

func _get_wm() -> Node:
	return get_node_or_null("/root/WildernessManager")

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
	
	# Buka tampilan awal: Jika ada sesi aktif dari battle, resume langsung!
	var wm = _get_wm()
	if wm and wm.has_active_session():
		_resume_exploration_session()
	else:
		_show_screen_state("START")

func _resume_exploration_session() -> void:
	var wm = _get_wm()
	if wm == null:
		_show_screen_state("START")
		return
	current_map_state = wm.saved_map_state
	current_chunk = wm.current_chunk
	_render_map(current_map_state, wm.saved_csp_result, wm.saved_ls_result)
	var chunk_px = get_chunk_center_pixel(current_chunk)
	if player_node:
		player_node.global_position = chunk_px
		player_node.visible = true
		if player_node.has_method("set_active"):
			player_node.set_active(true)
	if camera:
		camera.global_position = chunk_px
	_show_screen_state("PLAYING")
	_update_room_hud()
	_update_player_status_hud()

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
	
	if debug_grid_overlay == null:
		debug_grid_overlay = Node2D.new()
		debug_grid_overlay.name = "DebugGridOverlay"
		debug_grid_overlay.z_index = 6
		debug_grid_overlay.visible = false
		debug_grid_overlay.draw.connect(_on_draw_debug_grid_overlay)
		add_child(debug_grid_overlay)

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
	_build_debug_menu()
	_build_teleport_modal()

func _show_screen_state(state: String) -> void:
	if start_screen_panel: start_screen_panel.visible = (state == "START")
	if config_dialog_panel: config_dialog_panel.visible = (state == "CONFIG")
	if visualizer_panel: visualizer_panel.visible = (state == "VISUALIZER")
	if ingame_hud_panel: ingame_hud_panel.visible = (state == "PLAYING")

	if state == "PLAYING":
		is_event_busy = false
		if player_node:
			player_node.visible = true
			if player_node.has_method("set_active"):
				player_node.set_active(true)
	else:
		if player_node:
			if player_node.has_method("set_active"):
				player_node.set_active(false)

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
	opt_difficulty.add_item("Easy (Target: 80)", 0)
	opt_difficulty.add_item("Medium (Target: 160)", 1)
	opt_difficulty.add_item("Hard (Target: 250)", 2)
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
	inspect_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspect_vbox.add_theme_constant_override("separation", 10)
	inspect_card.add_child(inspect_vbox)
	
	# 1. TOP SECTION: STEP INFORMATION (50% Vertical)
	var step_card := PanelContainer.new()
	step_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	step_card.size_flags_stretch_ratio = 1.0
	var sb_step := StyleBoxFlat.new()
	sb_step.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	sb_step.border_color = Color(0.25, 0.40, 0.65, 0.75)
	sb_step.set_border_width_all(1)
	sb_step.set_corner_radius_all(6)
	sb_step.set_content_margin_all(8)
	step_card.add_theme_stylebox_override("panel", sb_step)
	inspect_vbox.add_child(step_card)
	
	var step_vbox := VBoxContainer.new()
	step_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	step_vbox.add_theme_constant_override("separation", 4)
	step_card.add_child(step_vbox)
	
	var l_step_title := Label.new()
	l_step_title.text = "📋 Step Information"
	l_step_title.add_theme_font_size_override("font_size", 13)
	l_step_title.add_theme_color_override("font_color", Color("#60A5FA"))
	step_vbox.add_child(l_step_title)
	
	lbl_vis_desc = Label.new()
	lbl_vis_desc.visible = false
	step_vbox.add_child(lbl_vis_desc)
	lbl_vis_metrics = Label.new()
	lbl_vis_metrics.visible = false
	step_vbox.add_child(lbl_vis_metrics)
	
	lbl_step_detail = RichTextLabel.new()
	lbl_step_detail.bbcode_enabled = true
	lbl_step_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_step_detail.scroll_active = true
	lbl_step_detail.add_theme_font_size_override("normal_font_size", 11)
	lbl_step_detail.add_theme_font_size_override("bold_font_size", 11)
	lbl_step_detail.text = "[color=#94A3B8]Tekan Play atau gerakkan timeline untuk meninjau langkah simulasi.[/color]"
	step_vbox.add_child(lbl_step_detail)
	
	# 2. BOTTOM SECTION: SELECTED CHUNK / NODE INSPECTOR (50% Vertical)
	var node_card := PanelContainer.new()
	node_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_card.size_flags_stretch_ratio = 1.0
	var sb_node := StyleBoxFlat.new()
	sb_node.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	sb_node.border_color = Color(0.45, 0.35, 0.65, 0.75)
	sb_node.set_border_width_all(1)
	sb_node.set_corner_radius_all(6)
	sb_node.set_content_margin_all(8)
	node_card.add_theme_stylebox_override("panel", sb_node)
	inspect_vbox.add_child(node_card)
	
	var node_vbox := VBoxContainer.new()
	node_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_vbox.add_theme_constant_override("separation", 4)
	node_card.add_child(node_vbox)
	
	var l_node_title := Label.new()
	l_node_title.text = "🔍 Selected Chunk Inspector"
	l_node_title.add_theme_font_size_override("font_size", 13)
	l_node_title.add_theme_color_override("font_color", Color("#FBBF24"))
	node_vbox.add_child(l_node_title)
	
	lbl_chunk_detail = RichTextLabel.new()
	lbl_chunk_detail.bbcode_enabled = true
	lbl_chunk_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_chunk_detail.scroll_active = true
	lbl_chunk_detail.add_theme_font_size_override("normal_font_size", 11)
	lbl_chunk_detail.add_theme_font_size_override("bold_font_size", 11)
	lbl_chunk_detail.text = "[color=#94A3B8]Pilih salah satu lingkaran node pada graf untuk memeriksa koordinat, pintu, dan entitasnya.[/color]"
	node_vbox.add_child(lbl_chunk_detail)
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
# Tampilan UI secara default ketika main: Healthbar, Active Item, Return Overworld, dan Tombol Toggle Debug Menu
func _build_ingame_hud() -> void:
	ingame_hud_panel = PanelContainer.new()
	ingame_hud_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ingame_hud_panel.custom_minimum_size = Vector2(0, 52)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.94)
	sb.border_color = Color(0.2, 0.3, 0.45, 0.6)
	sb.border_width_bottom = 2
	ingame_hud_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(ingame_hud_panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	ingame_hud_panel.add_child(margin)
	
	var h_row := HBoxContainer.new()
	h_row.add_theme_constant_override("separation", 10)
	h_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(h_row)
	
	# 1. Player Health Bar Container (Vertically Aligned)
	var hp_box := HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 6)
	hp_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h_row.add_child(hp_box)
	
	var hp_title := Label.new()
	hp_title.text = "💖 HP:"
	hp_title.add_theme_font_size_override("font_size", 12)
	hp_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.6))
	hp_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_box.add_child(hp_title)
	
	var init_max_hp: int = 500
	if has_node("/root/WildernessManager"):
		var wm_init = get_node("/root/WildernessManager")
		init_max_hp = wm_init.get("player_max_hp")
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(135, 20)
	hp_bar.min_value = 0
	hp_bar.max_value = init_max_hp
	hp_bar.value = init_max_hp
	hp_bar.show_percentage = false
	var hp_sb := StyleBoxFlat.new()
	hp_sb.bg_color = Color(0.18, 0.8, 0.44, 1.0)
	hp_sb.set_corner_radius_all(4)
	hp_bar.add_theme_stylebox_override("fill", hp_sb)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.15, 0.18, 0.25, 0.9)
	bg_sb.set_corner_radius_all(4)
	hp_bar.add_theme_stylebox_override("background", bg_sb)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_box.add_child(hp_bar)
	
	lbl_player_hp = Label.new()
	lbl_player_hp.text = "%d / %d" % [init_max_hp, init_max_hp]
	lbl_player_hp.custom_minimum_size = Vector2(65, 0)
	lbl_player_hp.add_theme_font_size_override("font_size", 12)
	lbl_player_hp.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	lbl_player_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_box.add_child(lbl_player_hp)
	
	var vsep := VSeparator.new()
	vsep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h_row.add_child(vsep)
	
	# 2. Efek Item Aktif Container (Vertically Aligned)
	var buff_container := HBoxContainer.new()
	buff_container.add_theme_constant_override("separation", 6)
	buff_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h_row.add_child(buff_container)
	
	lbl_buff_title = Label.new()
	lbl_buff_title.text = "Buffs:"
	lbl_buff_title.add_theme_font_size_override("font_size", 12)
	lbl_buff_title.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98))
	lbl_buff_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buff_container.add_child(lbl_buff_title)
	
	buffs_box = HBoxContainer.new()
	buffs_box.add_theme_constant_override("separation", 4)
	buffs_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buff_container.add_child(buffs_box)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_row.add_child(spacer)
	
	# 3. Right Box (Pinned at the right margin, immune to overflow)
	var right_box := HBoxContainer.new()
	right_box.add_theme_constant_override("separation", 8)
	right_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	h_row.add_child(right_box)
	
	btn_debug_toggle = Button.new()
	btn_debug_toggle.text = "🛠️ Debug (F3)"
	btn_debug_toggle.custom_minimum_size = Vector2(105, 32)
	var dt_sb := StyleBoxFlat.new()
	dt_sb.bg_color = Color(0.12, 0.22, 0.35, 0.95)
	dt_sb.border_color = Color(0.3, 0.6, 0.9, 0.9)
	dt_sb.set_border_width_all(1)
	dt_sb.set_corner_radius_all(6)
	btn_debug_toggle.add_theme_stylebox_override("normal", dt_sb)
	btn_debug_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_debug_toggle.pressed.connect(_toggle_debug_menu)
	right_box.add_child(btn_debug_toggle)
	
	btn_overworld = Button.new()
	btn_overworld.text = "🏠 Overworld"
	btn_overworld.custom_minimum_size = Vector2(95, 32)
	btn_overworld.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_overworld.pressed.connect(_return_to_overworld)
	right_box.add_child(btn_overworld)
func _update_player_status_hud() -> void:
	if not has_node("/root/WildernessManager"):
		return
	var wm = get_node("/root/WildernessManager")
	var hp: int = wm.get("player_hp")
	var max_hp: int = wm.get("player_max_hp")
	
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if lbl_player_hp:
		lbl_player_hp.text = "%d / %d" % [hp, max_hp]
	
	if buffs_box:
		for c in buffs_box.get_children():
			buffs_box.remove_child(c)
			c.queue_free()
		
		var b_dict = wm.get("active_buffs")
		var active_list: Array = []
		
		if b_dict.get("pothp", 0) > 0:
			active_list.append({
				"id": "pothp",
				"icon": "🧪",
				"name": "HP Pot",
				"short": "+25 HP",
				"full": "+25 HP Rest Recovery",
				"dur": b_dict["pothp"],
				"color": Color(0.95, 0.4, 0.5)
			})
		if b_dict.get("potstamina", 0) > 0:
			active_list.append({
				"id": "potstamina",
				"icon": "⚡",
				"name": "Stamina",
				"short": "-25% STM",
				"full": "-25% Stamina Cost Reduction",
				"dur": b_dict["potstamina"],
				"color": Color(0.3, 0.85, 1.0)
			})
		if b_dict.get("sword", 0) > 0:
			active_list.append({
				"id": "sword",
				"icon": "⚔️",
				"name": "Sword",
				"short": "+10% ATK",
				"full": "+10% Basic Attack Damage",
				"dur": b_dict["sword"],
				"color": Color(1.0, 0.85, 0.25)
			})
		if b_dict.get("axe", 0) > 0:
			active_list.append({
				"id": "axe",
				"icon": "🪓",
				"name": "Axe",
				"short": "+10% HVY",
				"full": "+10% Heavy Attack Damage",
				"dur": b_dict["axe"],
				"color": Color(1.0, 0.5, 0.2)
			})
		
		var total_buffs = active_list.size()
		if lbl_buff_title:
			lbl_buff_title.text = "Buffs (%d):" % total_buffs if total_buffs > 0 else "Buffs:"
			
		if total_buffs == 0:
			var empty_lbl := Label.new()
			empty_lbl.text = "-"
			empty_lbl.add_theme_font_size_override("font_size", 11)
			empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
			buffs_box.add_child(empty_lbl)
		else:
			for b in active_list:
				_create_hud_buff_pill(b, total_buffs)
func _create_hud_buff_pill(b: Dictionary, total_buffs: int) -> void:
	var p := PanelContainer.new()
	var col: Color = b.color
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.1, 0.16, 0.92)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(2)
	
	var label_text := ""
	var font_sz := 11
	
	if total_buffs <= 1:
		# Format lengkap ketika hanya 1 buff
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		label_text = "%s %s (%s) [%db]" % [b.icon, b.name, b.short, b.dur]
		font_sz = 11
	elif total_buffs == 2:
		# Format compact ketika ada 2 buff
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		label_text = "%s %s [%db]" % [b.icon, b.short, b.dur]
		font_sz = 10
	else:
		# Format badge collapse super-ringkas ketika ada >= 3 buff bersamaan
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		label_text = "%s %s [%d]" % [b.icon, b.short, b.dur]
		font_sz = 10
		
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.tooltip_text = "%s %s
Efek: %s
Durasi Sisa: %d Battle" % [b.icon, b.name, b.full, b.dur]
	
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", font_sz)
	l.add_theme_color_override("font_color", col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(l)
	
	if buffs_box:
		buffs_box.add_child(p)
# =========================================================================
# TOGGLEABLE DEBUG MENU & OVERLAYS (F3 / BUTTON)
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_toggle_debug_menu()

func _toggle_debug_menu() -> void:
	if debug_menu_panel:
		debug_menu_panel.visible = not debug_menu_panel.visible
		if debug_menu_panel.visible:
			_update_room_hud()
			_update_debug_ai_stats()

func _build_debug_menu() -> void:
	debug_menu_panel = PanelContainer.new()
	debug_menu_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_menu_panel.offset_top = 60.0
	debug_menu_panel.offset_right = -16.0
	debug_menu_panel.offset_left = -400.0
	debug_menu_panel.custom_minimum_size = Vector2(384, 0)
	debug_menu_panel.z_index = 40
	debug_menu_panel.visible = false
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.13, 0.96)
	sb.border_color = Color(0.28, 0.52, 0.85, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	debug_menu_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(debug_menu_panel)
	
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 480)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	debug_menu_panel.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	
	# Header Bar
	var head_box := HBoxContainer.new()
	vbox.add_child(head_box)
	
	var title_lbl := Label.new()
	title_lbl.text = "🛠️ WILDERNESS DEBUG MENU"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color("#FBBF24"))
	head_box.add_child(title_lbl)
	
	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_box.add_child(h_spacer)
	
	var btn_close_dbg := Button.new()
	btn_close_dbg.text = " ✕ "
	btn_close_dbg.custom_minimum_size = Vector2(28, 24)
	btn_close_dbg.pressed.connect(func(): debug_menu_panel.visible = false)
	head_box.add_child(btn_close_dbg)
	
	# Lokasi Ruangan Sekarang
	lbl_current_room = Label.new()
	lbl_current_room.text = "📍 Room [0, 0] 🟢 Start"
	lbl_current_room.add_theme_font_size_override("font_size", 12)
	lbl_current_room.add_theme_color_override("font_color", Color("#60A5FA"))
	vbox.add_child(lbl_current_room)
	
	vbox.add_child(HSeparator.new())
	
	# SECTION 1: MAP & PATH OVERLAYS
	var sec1_lbl := Label.new()
	sec1_lbl.text = "👁️ MAP & PATH OVERLAYS"
	sec1_lbl.add_theme_font_size_override("font_size", 12)
	sec1_lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	vbox.add_child(sec1_lbl)
	
	# 1.1 Checkbox Optimal Path
	chk_debug_optimal_path = CheckBox.new()
	chk_debug_optimal_path.text = "Show Optimal Path"
	chk_debug_optimal_path.button_pressed = false
	chk_debug_optimal_path.toggled.connect(func(on: bool):
		if path_line:
			path_line.visible = on
	)
	vbox.add_child(chk_debug_optimal_path)
	
	# 1.2, 1.3, 1.4 Checkbox Chunk Grid & Coordinates
	chk_debug_grid = CheckBox.new()
	chk_debug_grid.text = "Show Chunk Grid & Coordinates"
	chk_debug_grid.button_pressed = false
	chk_debug_grid.toggled.connect(func(on: bool):
		if debug_grid_overlay:
			debug_grid_overlay.visible = on
			if on:
				debug_grid_overlay.queue_redraw()
	)
	vbox.add_child(chk_debug_grid)
	
	# 2.2, 2.3 Checkbox AI Search Stats Panel
	chk_debug_ai_stats = CheckBox.new()
	chk_debug_ai_stats.text = "Show AI Search Stats Panel"
	chk_debug_ai_stats.button_pressed = false
	chk_debug_ai_stats.toggled.connect(func(on: bool):
		if debug_ai_stats_card:
			debug_ai_stats_card.visible = on
			if on:
				_update_debug_ai_stats()
	)
	vbox.add_child(chk_debug_ai_stats)
	
	# AI Stats Card (Consistent font size, no emojis, clean layout)
	debug_ai_stats_card = PanelContainer.new()
	var ai_sb := StyleBoxFlat.new()
	ai_sb.bg_color = Color(0.04, 0.06, 0.09, 0.95)
	ai_sb.border_color = Color(0.2, 0.35, 0.5, 0.7)
	ai_sb.set_border_width_all(1)
	ai_sb.set_corner_radius_all(6)
	ai_sb.set_content_margin_all(10)
	debug_ai_stats_card.add_theme_stylebox_override("panel", ai_sb)
	debug_ai_stats_card.visible = false
	vbox.add_child(debug_ai_stats_card)
	
	lbl_debug_ai_stats_content = RichTextLabel.new()
	lbl_debug_ai_stats_content.bbcode_enabled = true
	lbl_debug_ai_stats_content.fit_content = true
	lbl_debug_ai_stats_content.custom_minimum_size = Vector2(0, 240)
	lbl_debug_ai_stats_content.add_theme_font_size_override("normal_font_size", 11)
	lbl_debug_ai_stats_content.add_theme_font_size_override("bold_font_size", 11)
	lbl_debug_ai_stats_content.add_theme_font_size_override("italics_font_size", 11)
	lbl_debug_ai_stats_content.add_theme_font_size_override("bold_italics_font_size", 11)
	lbl_debug_ai_stats_content.add_theme_font_size_override("mono_font_size", 11)
	debug_ai_stats_card.add_child(lbl_debug_ai_stats_content)
	
	vbox.add_child(HSeparator.new())
	
	# SECTION 2: TESTING & SANDBOX TOOLS
	var sec2_lbl := Label.new()
	sec2_lbl.text = "SANDBOX / TESTING TOOLS"
	sec2_lbl.add_theme_font_size_override("font_size", 12)
	sec2_lbl.add_theme_color_override("font_color", Color(0.9, 0.5, 1.0))
	vbox.add_child(sec2_lbl)
	
	# Checkbox Skip Battle
	chk_debug_skip_battle = CheckBox.new()
	chk_debug_skip_battle.text = "Skip Battle"
	chk_debug_skip_battle.button_pressed = false
	vbox.add_child(chk_debug_skip_battle)
	
	# Subpoin 1: Chunk Teleport Button
	var btn_dbg_teleport := Button.new()
	btn_dbg_teleport.text = "Teleport to Chunk..."
	btn_dbg_teleport.custom_minimum_size = Vector2(0, 32)
	btn_dbg_teleport.pressed.connect(func():
		_show_teleport_modal(true)
	)
	vbox.add_child(btn_dbg_teleport)
	
	# Subpoin 3: Instant Heal Button
	var btn_dbg_heal := Button.new()
	btn_dbg_heal.text = "💖 Instant Heal (100% HP)"
	btn_dbg_heal.custom_minimum_size = Vector2(0, 32)
	var heal_sb := StyleBoxFlat.new()
	heal_sb.bg_color = Color(0.12, 0.32, 0.22, 0.9)
	heal_sb.border_color = Color(0.2, 0.8, 0.4, 0.9)
	heal_sb.set_border_width_all(1)
	heal_sb.set_corner_radius_all(6)
	btn_dbg_heal.add_theme_stylebox_override("normal", heal_sb)
	btn_dbg_heal.pressed.connect(_instant_heal_player)
	vbox.add_child(btn_dbg_heal)
	
	# Restart Run Button (dipindahkan ke debug menu)
	btn_restart = Button.new()
	btn_restart.text = "🔄 Restart Run"
	btn_restart.custom_minimum_size = Vector2(0, 32)
	var rst_sb := StyleBoxFlat.new()
	rst_sb.bg_color = Color(0.32, 0.12, 0.15, 0.9)
	rst_sb.border_color = Color(0.85, 0.3, 0.35, 0.9)
	rst_sb.set_border_width_all(1)
	rst_sb.set_corner_radius_all(6)
	btn_restart.add_theme_stylebox_override("normal", rst_sb)
	btn_restart.pressed.connect(func():
		var wm = _get_wm()
		if wm:
			wm.clear_session()
		get_tree().reload_current_scene()
	)
	vbox.add_child(btn_restart)

func _instant_heal_player() -> void:
	var wm = _get_wm()
	var max_hp = 500
	if wm:
		max_hp = wm.get("player_max_hp")
		wm.player_hp = max_hp
	if hp_bar:
		hp_bar.value = max_hp
	if lbl_player_hp:
		lbl_player_hp.text = "%d / %d" % [max_hp, max_hp]
	if player_node:
		_spawn_floating_text(player_node.global_position, "💚 FULL HEAL! (%d HP)" % max_hp, Color(0.3, 1.0, 0.4))

func _update_debug_ai_stats() -> void:
	if lbl_debug_ai_stats_content == null or current_map_state == null:
		return
	var path_len = current_map_state.chunk_path.size()
	var path_score = float(path_len) * 8.0
	var path_threat: float = 0.0
	var side_threat: float = 0.0
	var item_benefits: float = 0.0
	var path_set: Dictionary = {}
	for cp in current_map_state.chunk_path:
		path_set[cp] = true
		
	var enemy_count = 0
	var item_count = 0
	for pos in current_map_state.chunk_entities.keys():
		var ent = current_map_state.chunk_entities[pos]
		if ent.type == "enemy":
			enemy_count += 1
			if path_set.has(pos):
				path_threat += ent.threat
			else:
				side_threat += ent.threat * 0.35
		elif ent.type == "item":
			item_count += 1
			if path_set.has(pos):
				item_benefits += ent.benefit
			else:
				item_benefits += ent.benefit * 0.5
				
	var target_diff = get_target_difficulty()
	var curr_diff = current_map_state.difficulty_score
	var energy = abs(curr_diff - target_diff)
	
	var csp_time = last_csp_stats.get("time_ms", 0.0)
	var backtracks = last_csp_stats.get("backtracks_count", 0)
	var prunes = last_csp_stats.get("ac3_prunes", 0)
	var ls_algo = last_ls_stats.get("algorithm", "simulated_annealing")
	var is_solv = "YES" if current_map_state.is_solvable else "NO"
	
	var solv_col = "#30d158" if current_map_state.is_solvable else "#ff453a"
	var energy_col = "#30d158" if energy <= 2.0 else ("#ffd60a" if energy <= 5.0 else "#ff453a")
	
	var text := ""
	text += "[b][color=#64d2ff]FORMULA KESULITAN (OBJECTIVE FUNCTION)[/color][/b]
"
	text += "• Panjang Rute BFS (%d rooms x 8): [b][color=#30d158]+%.1f[/color][/b]
" % [path_len, path_score]
	text += "• Threat Jalur Utama: [b][color=#ff453a]+%.1f[/color][/b]
" % path_threat
	text += "• Threat Jalur Samping (x0.35): [b][color=#ff9f0a]+%.1f[/color][/b]
" % side_threat
	text += "• Bantuan Item: [b][color=#32d74b]-%.1f[/color][/b]
" % item_benefits
	text += "[color=#48484a]----------------------------------------[/color]
"
	text += "Difficulty Score: [b][color=#ffd60a]%.1f[/color][/b] (Target: [b][color=#8e8e93]%.1f[/color][/b])
" % [curr_diff, target_diff]
	text += "Residual Energy: [b][color=%s]%.1f[/color][/b]

" % [energy_col, energy]
	
	text += "[b][color=#bf5af2]STATISTIK ALGORITMA (CSP & LOCAL SEARCH)[/color][/b]
"
	text += "• Waktu Eksekusi CSP: [b][color=#64d2ff]%.2f ms[/color][/b]
" % csp_time
	text += "• Jumlah Backtrack: [b][color=#ff9f0a]%d[/color][/b]
" % backtracks
	text += "• Pangkasan Busur AC-3: [b][color=#64d2ff]%d prunes[/color][/b]
" % prunes
	text += "• Algoritma Local Search: [b][color=#bf5af2]%s[/color][/b]
" % ls_algo.replace("_", " ").capitalize()
	text += "• Solvable (Start ke Exit): [b][color=%s]%s[/color][/b]
" % [solv_col, is_solv]
	text += "• Total Musuh: [b][color=#ff453a]%d[/color][/b] | Total Item: [b][color=#30d158]%d[/color][/b]
" % [enemy_count, item_count]
	
	lbl_debug_ai_stats_content.text = text

# --- Overview Node Modal for Chunk Teleport ---
func _build_teleport_modal() -> void:
	teleport_modal_panel = PanelContainer.new()
	teleport_modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	teleport_modal_panel.custom_minimum_size = Vector2(620, 520)
	teleport_modal_panel.offset_left = -310.0
	teleport_modal_panel.offset_top = -260.0
	teleport_modal_panel.offset_right = 310.0
	teleport_modal_panel.offset_bottom = 260.0
	teleport_modal_panel.z_index = 80
	teleport_modal_panel.visible = false
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.13, 0.98)
	sb.border_color = Color(0.3, 0.7, 1.0, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	teleport_modal_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(teleport_modal_panel)
	
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	teleport_modal_panel.add_child(root_vbox)
	
	# Top bar
	var top_bar := HBoxContainer.new()
	root_vbox.add_child(top_bar)
	
	var t_title := Label.new()
	t_title.text = "🗺️ CHUNK TELEPORT SELECTOR"
	t_title.add_theme_font_size_override("font_size", 15)
	t_title.add_theme_color_override("font_color", Color("#FBBF24"))
	top_bar.add_child(t_title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	
	var btn_close := Button.new()
	btn_close.text = " ✕ Tutup "
	btn_close.pressed.connect(func(): teleport_modal_panel.visible = false)
	top_bar.add_child(btn_close)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "Klik salah satu node chunk pada grid di bawah untuk langsung berteleportasi ke ruangan tersebut."
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	root_vbox.add_child(sub_lbl)
	
	# Center Canvas Card
	var canvas_card := PanelContainer.new()
	canvas_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb_c := StyleBoxFlat.new()
	sb_c.bg_color = Color(0.03, 0.05, 0.08, 0.95)
	sb_c.border_color = Color(0.2, 0.3, 0.45, 0.7)
	sb_c.set_border_width_all(1)
	sb_c.set_corner_radius_all(6)
	canvas_card.add_theme_stylebox_override("panel", sb_c)
	root_vbox.add_child(canvas_card)
	
	teleport_canvas = Control.new()
	teleport_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	teleport_canvas.draw.connect(_on_draw_teleport_canvas)
	teleport_canvas.gui_input.connect(_on_teleport_canvas_gui_input)
	canvas_card.add_child(teleport_canvas)
	
	# Legend Footer
	var leg_lbl := Label.new()
	leg_lbl.text = "Keterangan: 🟢 Start | 🟣 Portal | 🟡 Lokasi Player | 🔴 Musuh | 🔶 Item | 🟦 Clear"
	leg_lbl.add_theme_font_size_override("font_size", 10)
	leg_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	root_vbox.add_child(leg_lbl)

func _show_teleport_modal(show_val: bool) -> void:
	if teleport_modal_panel:
		teleport_modal_panel.visible = show_val
		if show_val and teleport_canvas:
			teleport_canvas.queue_redraw()

func _on_draw_teleport_canvas() -> void:
	if teleport_canvas == null or current_map_state == null:
		return
	var rect = teleport_canvas.get_rect()
	var gw = current_map_state.grid_w
	var gh = current_map_state.grid_h
	var pad = 36.0
	var cell_w = (rect.size.x - pad * 2.0) / float(gw)
	var cell_h = (rect.size.y - pad * 2.0) / float(gh)
	var radius = min(cell_w, cell_h) * 0.34
	
	var raw_templates = template_instance.get_chunk_templates() if template_instance else []
	var tpl_dict: Dictionary = {}
	for t in raw_templates: tpl_dict[t.id] = t
	
	var assignments = current_map_state.chunk_templates
	var entities = current_map_state.chunk_entities
	
	# 1. Gambar koneksi pintu antar-chunk
	for cx in range(gw):
		for cy in range(gh):
			var pos = Vector2i(cx, cy)
			var tpl_id = assignments.get(pos, "")
			if tpl_id == "" or tpl_id == "SOLID": continue
			var tpl = tpl_dict.get(tpl_id)
			if tpl == null: continue
			var c_px = Vector2(pad + (float(cx) + 0.5) * cell_w, pad + (float(cy) + 0.5) * cell_h)
			
			if cx < gw - 1 and tpl.doors[2]:
				var east_pos = pos + Vector2i(1, 0)
				var east_tpl = tpl_dict.get(assignments.get(east_pos, ""))
				if east_tpl != null and east_tpl.doors[3]:
					var east_px = Vector2(pad + (float(cx + 1) + 0.5) * cell_w, pad + (float(cy) + 0.5) * cell_h)
					teleport_canvas.draw_line(c_px, east_px, Color(0.2, 0.7, 0.95, 0.75), 4.0)
					
			if cy < gh - 1 and tpl.doors[1]:
				var south_pos = pos + Vector2i(0, 1)
				var south_tpl = tpl_dict.get(assignments.get(south_pos, ""))
				if south_tpl != null and south_tpl.doors[0]:
					var south_px = Vector2(pad + (float(cx) + 0.5) * cell_w, pad + (float(cy + 1) + 0.5) * cell_h)
					teleport_canvas.draw_line(c_px, south_px, Color(0.2, 0.7, 0.95, 0.75), 4.0)
					
	# 2. Gambar Nodes
	for cx in range(gw):
		for cy in range(gh):
			var pos = Vector2i(cx, cy)
			var center_pt = Vector2(pad + (float(cx) + 0.5) * cell_w, pad + (float(cy) + 0.5) * cell_h)
			var tpl_id = assignments.get(pos, "")
			var bg_color = Color(0.18, 0.22, 0.28, 0.7)
			var border_color = Color(0.35, 0.45, 0.6, 0.8)
			
			var is_player = (pos == current_chunk)
			var is_start = (pos == current_map_state.start_chunk)
			var is_portal = (pos == current_map_state.portal_chunk)
			var ent = entities.get(pos, { "type": "empty" })
			
			if tpl_id == "SOLID":
				bg_color = Color(0.1, 0.12, 0.16, 0.85)
				border_color = Color(0.25, 0.28, 0.35, 0.6)
			elif is_start:
				bg_color = Color("#10B981")
				border_color = Color("#34D399")
			elif is_portal:
				bg_color = Color("#8B5CF6")
				border_color = Color("#A78BFA")
			elif ent.type == "enemy":
				bg_color = Color("#EF4444")
				border_color = Color("#F87171")
			elif ent.type == "item":
				bg_color = Color("#F59E0B")
				border_color = Color("#FBBF24")
			else:
				bg_color = Color("#3B82F6")
				border_color = Color("#60A5FA")
				
			teleport_canvas.draw_circle(center_pt, radius, bg_color)
			teleport_canvas.draw_arc(center_pt, radius, 0, TAU, 24, border_color, 2.0)
			
			if is_player:
				teleport_canvas.draw_arc(center_pt, radius + 4.0, 0, TAU, 24, Color("#FBBF24"), 3.0)
				
			var lbl = "%d,%d" % [cx, cy]
			if is_player: lbl += "\nPAWN"
			elif is_start: lbl += "\nSTART"
			elif is_portal: lbl += "\nEXIT"
			elif ent.type == "enemy": lbl += "\n💀"
			elif ent.type == "item": lbl += "\n💎"
			
			teleport_canvas.draw_string(ThemeDB.fallback_font, center_pt + Vector2(-radius * 0.75, -radius * 0.1), lbl, HORIZONTAL_ALIGNMENT_CENTER, int(radius * 1.5), 10, Color.WHITE)

func _on_teleport_canvas_gui_input(event: InputEvent) -> void:
	if current_map_state == null or teleport_canvas == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var rect = teleport_canvas.get_rect()
		var gw = current_map_state.grid_w
		var gh = current_map_state.grid_h
		var pad = 36.0
		var cell_w = (rect.size.x - pad * 2.0) / float(gw)
		var cell_h = (rect.size.y - pad * 2.0) / float(gh)
		var radius = min(cell_w, cell_h) * 0.34
		var m_pos = event.position
		
		for cx in range(gw):
			for cy in range(gh):
				var center_pt = Vector2(pad + (float(cx) + 0.5) * cell_w, pad + (float(cy) + 0.5) * cell_h)
				if m_pos.distance_to(center_pt) <= radius * 1.3:
					_teleport_player_to_chunk(Vector2i(cx, cy))
					return

func _teleport_player_to_chunk(c_pos: Vector2i) -> void:
	if current_map_state == null:
		return
	var target_px = get_chunk_center_pixel(c_pos)
	if player_node:
		player_node.global_position = target_px
		player_node.velocity = Vector2.ZERO
		if "current_path" in player_node:
			player_node.current_path.clear()
	if camera:
		camera.global_position = target_px
	current_chunk = c_pos
	var wm = _get_wm()
	if wm:
		wm.current_chunk = c_pos
	_update_room_hud()
	_spawn_floating_text(target_px, "⚡ TELEPORTED TO (%d, %d)" % [c_pos.x, c_pos.y], Color(0.4, 0.85, 1.0))
	if is_instance_valid(teleport_modal_panel):
		teleport_modal_panel.visible = false
	if is_instance_valid(teleport_canvas):
		teleport_canvas.queue_redraw()

# --- World Overlay: Grid, Coordinates, Door Markers & Classification Tint ---
func _on_draw_debug_grid_overlay() -> void:
	if current_map_state == null or debug_grid_overlay == null or chk_debug_grid == null or not chk_debug_grid.button_pressed:
		return
	var gw = current_map_state.grid_w
	var gh = current_map_state.grid_h
	var p = template_instance.chunk_size_p if template_instance else 7
	var q = template_instance.chunk_size_q if template_instance else 7
	var chunk_px_size = Vector2(float(p) * 64.0, float(q) * 64.0)
	var raw_templates = template_instance.get_chunk_templates() if template_instance else []
	var tpl_dict: Dictionary = {}
	for t in raw_templates: tpl_dict[t.id] = t
	
	var path_set: Dictionary = {}
	for cp in current_map_state.chunk_path:
		path_set[cp] = true
		
	for cy in range(gh):
		for cx in range(gw):
			var c_pos = Vector2i(cx, cy)
			var orig_px = Vector2(get_chunk_tile_origin(c_pos)) * 64.0
			var rect = Rect2(orig_px, chunk_px_size)
			var tpl_id = current_map_state.chunk_templates.get(c_pos, "SOLID")
			var tpl = tpl_dict.get(tpl_id)
			
			# 1.4 Room Classification Tint:
			if path_set.has(c_pos):
				# Main Path (Cyan/Green tint)
				debug_grid_overlay.draw_rect(rect, Color(0.1, 0.75, 0.95, 0.16), true)
			elif tpl_id == "SOLID":
				# Solid / Unreachable (Dark Red)
				debug_grid_overlay.draw_rect(rect, Color(0.85, 0.15, 0.15, 0.28), true)
			else:
				# Side Path (Yellow tint)
				debug_grid_overlay.draw_rect(rect, Color(0.95, 0.8, 0.15, 0.14), true)
				
			# 1.2 Chunk Grid Lines / Border
			var border_col = Color(0.3, 0.8, 1.0, 0.7) if path_set.has(c_pos) else (Color(0.8, 0.3, 0.3, 0.6) if tpl_id == "SOLID" else Color(0.8, 0.8, 0.8, 0.4))
			debug_grid_overlay.draw_rect(rect, border_col, false, 2.0)
			
			# 1.3 Door Connection Markers (Green bars on edges)
			if tpl != null:
				var center = orig_px + chunk_px_size * 0.5
				# North (top)
				if tpl.doors[0]:
					debug_grid_overlay.draw_line(Vector2(center.x - 28, orig_px.y + 4), Vector2(center.x + 28, orig_px.y + 4), Color(0.2, 1.0, 0.45, 0.95), 6.0)
				# South (bottom)
				if tpl.doors[1]:
					debug_grid_overlay.draw_line(Vector2(center.x - 28, orig_px.y + chunk_px_size.y - 4), Vector2(center.x + 28, orig_px.y + chunk_px_size.y - 4), Color(0.2, 1.0, 0.45, 0.95), 6.0)
				# East (right)
				if tpl.doors[2]:
					debug_grid_overlay.draw_line(Vector2(orig_px.x + chunk_px_size.x - 4, center.y - 28), Vector2(orig_px.x + chunk_px_size.x - 4, center.y + 28), Color(0.2, 1.0, 0.45, 0.95), 6.0)
				# West (left)
				if tpl.doors[3]:
					debug_grid_overlay.draw_line(Vector2(orig_px.x + 4, center.y - 28), Vector2(orig_px.x + 4, center.y + 28), Color(0.2, 1.0, 0.45, 0.95), 6.0)
					
			# 1.2 Coordinate & Template label
			var label_str = "Chunk (%d, %d)\n%s" % [cx, cy, tpl_id]
			if c_pos == current_map_state.start_chunk:
				label_str += " 🟢 [START]"
			elif c_pos == current_map_state.portal_chunk:
				label_str += " 🟣 [PORTAL]"
			debug_grid_overlay.draw_string(ThemeDB.fallback_font, orig_px + Vector2(10, 22), label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95))

# =========================================================================
# EKSEKUSI GENERASI MAP & LOGIKA STEP-BY-STEP
# =========================================================================
func get_target_difficulty() -> float:
	var idx = opt_difficulty.selected if opt_difficulty else 1
	match idx:
		0: return 80.0
		1: return 160.0
		2: return 250.0
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
	
	var wm = _get_wm()
	if wm:
		wm.start_exploration(current_map_state, res.csp_res.csp_result, res.ls_res)
	
	_render_map(current_map_state, res.csp_res.csp_result, res.ls_res)
	_show_screen_state("PLAYING")
	_update_player_status_hud()

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
		var wm = _get_wm()
		if wm:
			wm.start_exploration(current_map_state, last_generated_data.csp_res.csp_result, last_generated_data.ls_res)
		_render_map(current_map_state, last_generated_data.csp_res.csp_result, last_generated_data.ls_res)
	_show_screen_state("PLAYING")
	_update_player_status_hud()

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
	if lbl_vis_desc:
		lbl_vis_desc.text = step_data.get("desc", "")
	
	# Otomatis sinkronkan selected_graph_chunk dengan active node pada step ini
	var step_var = step_data.get("var", null)
	if step_var != null and step_var is Vector2i:
		selected_graph_chunk = step_var
	elif phase == "csp" and step_data.has("var") and step_data["var"] != null:
		selected_graph_chunk = step_data["var"]
	elif phase == "local_search":
		var act_pos = step_data.get("var", null)
		if act_pos != null and act_pos is Vector2i:
			selected_graph_chunk = act_pos
	
	# Update Step Information Panel (Rich Text)
	if phase == "csp":
		var step_type = step_data.get("type", "step")
		var step_val = step_data.get("val", "-")
		var step_desc = step_data.get("desc", "")
		if lbl_vis_metrics:
			lbl_vis_metrics.text = "CSP Type: %s | Active Var: %s" % [step_type, str(step_var if step_var != null else "-")]
		
		var s_bb := ""
		s_bb += "[b]Fase:[/b] [color=#60A5FA]CSP Backtracking Search[/color]
"
		s_bb += "[b]Langkah:[/b] %d / %d
" % [current_step_idx + 1, timeline_steps.size()]
		s_bb += "[b]Tipe Aksi:[/b] %s
" % step_type.to_upper()
		if step_var != null:
			s_bb += "[b]Variabel Terpilih (Chunk):[/b] [color=#FBBF24][%d, %d][/color]
" % [step_var.x, step_var.y]
			s_bb += "[b]Nilai Template Ditugaskan:[/b] %s
" % step_val
		s_bb += "----------------------------------------
"
		s_bb += "[b]Deskripsi Operasi:[/b]
%s
" % step_desc
		s_bb += "[color=#94A3B8][b]Prinsip CSP:[/b] Algoritma memeriksa kecocokan template pintu 4 arah (North, South, East, West) dan kendala batas tepi unary. Jika terjadi domain kosong pada tetangga, dilakukan Backtrack.[/color]"
		if lbl_step_detail:
			lbl_step_detail.text = s_bb
	else:
		var step_num = step_data.get("step_num", current_step_idx + 1)
		var temp = step_data.get("temp", 0.0)
		var energy = step_data.get("energy", 0.0)
		var diff = step_data.get("diff", 0.0)
		var target_diff = step_data.get("target_diff", get_target_difficulty())
		var delta_e = step_data.get("delta_e", 0.0)
		var prev_energy = step_data.get("prev_energy", energy)
		var prev_diff = step_data.get("prev_diff", diff)
		var acc_mode = step_data.get("acceptance_mode", "improvement")
		var op_name = step_data.get("op_name", "Mutasi")
		var mut_detail = step_data.get("mut_detail", "")
		var target_chunk = step_data.get("var", null)
		
		if lbl_vis_metrics:
			lbl_vis_metrics.text = "Temp: %.1f | Energy: %.1f | Diff: %.1f" % [temp, energy, diff]
			
		var status_text = ""
		if acc_mode == "init":
			status_text = "[color=#38BDF8]INISIALISASI AWAL[/color]"
		elif acc_mode == "improvement":
			status_text = "[color=#4ADE80]DITERIMA (Perbaikan: ΔE = %.1f)[/color]" % delta_e
		elif acc_mode == "probabilistic":
			var p_val = step_data.get("accept_prob", 0.0) * 100.0
			status_text = "[color=#FBBF24]DITERIMA KARENA SUHU (P = %.1f%%)[/color]" % p_val
		elif acc_mode == "plateau":
			status_text = "[color=#A78BFA]DITERIMA (Energi Setara: ΔE = 0)[/color]"
		else:
			status_text = "[color=#F87171]DITOLAK (Memperburuk: ΔE = +%.1f)[/color]" % delta_e
			
		var s_bb := ""
		s_bb += "[b]Fase:[/b] [color=#C084FC]Local Search (Simulated Annealing)[/color]
"
		s_bb += "[b]Langkah:[/b] %d / %d (Iterasi %d)
" % [current_step_idx + 1, timeline_steps.size(), step_num]
		s_bb += "[b]Keputusan:[/b] %s
" % status_text
		if target_chunk != null:
			s_bb += "[b]Target Mutasi:[/b] Chunk [color=#FBBF24][%d, %d][/color] - [b]%s[/b]
" % [target_chunk.x, target_chunk.y, op_name]
			if not mut_detail.is_empty():
				s_bb += "• [color=#E2E8F0]%s[/color]
" % mut_detail
		s_bb += "----------------------------------------
"
		s_bb += "[b]METRIK SISTEM SAAT INI:[/b]
"
		s_bb += "• [b]Diff (Difficulty):[/b] [color=#FDE047]%.1f[/color] (Target: %.1f)
" % [diff, target_diff]
		s_bb += "• [b]Energy (Error):[/b] [color=%s]%.1f[/color] (Sebelumnya: %.1f | ΔE: %+.1f)
" % [
			"#4ADE80" if energy <= 2.0 else ("#FDE047" if energy <= 6.0 else "#F87171"),
			energy, prev_energy, delta_e
		]
		s_bb += "• [b]Temp (Suhu):[/b] [color=#38BDF8]%.2f[/color]
" % temp
		s_bb += "----------------------------------------
"
		s_bb += "[b]PENJELASAN PARAMETER & PROSES:[/b]
"
		s_bb += "• [b]Diff (Difficulty Score):[/b] Skor tantangan map = (Panjang BFS x 8) + Ancaman Musuh - Bantuan Item.
"
		s_bb += "• [b]Energy (Residual Cost):[/b] Selisih mutlak ke target (|Diff - Target|). Tujuan optimasi adalah menekan Energy menuju 0.
"
		s_bb += "• [b]Temp (Temperature):[/b] Probabilitas menerima solusi lebih buruk (P = e^(-ΔE/Temp)). Di awal suhu tinggi memungkinkan eksplorasi luas agar tidak terjebak di local optima; semakin ke akhir suhu mendingin untuk konvergensi presisi.
"
		s_bb += "• [b]Aksi Pada Langkah Ini:[/b]
"
		if acc_mode == "init":
			s_bb += "  Menempatkan sebaran awal musuh dan item acak di ruang kosong untuk membentuk konfigurasi awal sebelum optimasi."
		elif acc_mode == "improvement":
			s_bb += "  Mutasi berhasil mendekatkan Difficulty ke target sehingga Energy turun. Perubahan ini langsung disetujui."
		elif acc_mode == "probabilistic":
			s_bb += "  Meskipun mutasi menaikkan Energy, suhu (Temp = %.1f) masih cukup panas sehingga mutasi tetap diterima secara stokastik guna menghindari jebakan lokal (local minima)." % temp
		elif acc_mode == "plateau":
			s_bb += "  Mutasi memiliki energi yang setara dengan state sebelumnya dan diterima untuk menelusuri dataran solusi."
		else:
			s_bb += "  Mutasi memperburuk Energy dan gagal memenuhi ambang probabilitas suhu, sehingga perubahan dibatalkan dan susunan entitas dikembalikan ke state sebelumnya."
			
		if lbl_step_detail:
			lbl_step_detail.text = s_bb
		
	if visualizer_canvas:
		visualizer_canvas.queue_redraw()
		
	_update_chunk_inspector()
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
	if phase == "csp":
		bb += "[b]CSP Domain Candidates (%d):[/b] %s
" % [domain_left.size(), domain_str]
	else:
		var is_mutated = (step_data.get("var", null) == pos)
		if is_mutated:
			bb += "[color=#4ADE80]⚡ Chunk ini aktif dimutasi pada langkah ini![/color]
"
		else:
			bb += "[color=#94A3B8]Status entitas stabil (tidak dimutasi pada langkah ini).[/color]
"
	
	lbl_chunk_detail.text = bb
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

	# 3. Spawn Player (Start Room atau Posisi Sesi Tersimpan)
	var wm_sess = _get_wm()
	var player_pixel = get_chunk_center_pixel(current_chunk) if (wm_sess and wm_sess.has_active_session()) else get_chunk_center_pixel(state.start_chunk)
	if player_node:
		player_node.visible = true
		player_node.global_position = player_pixel
		if player_node.has_method("set_active"):
			player_node.set_active(true)
			
	if camera:
		camera.global_position = player_pixel
		
	# 4. Spawn Portal di Portal Chunk
	if portal_node:
		portal_node.visible = true
		portal_node.global_position = get_chunk_center_pixel(state.portal_chunk)
		
	# 5. Spawn Enemies & Items dari data hasil Local Search
	for c_pos in state.chunk_entities.keys():
		var ent = state.chunk_entities[c_pos]
		var px_center = get_chunk_center_pixel(c_pos)
		
		if ent.type == "enemy":
			var wm_chk = _get_wm()
			if wm_chk and (c_pos in wm_chk.defeated_chunks):
				continue
			var e_node = template_instance.instantiate_enemy(ent.node_name) if template_instance else null
			if e_node:
				e_node.global_position = px_center
				e_node.set_meta("chunk_pos", c_pos)
				e_node.set_meta("entity_data", ent)
				enemies_container.add_child(e_node)
		elif ent.type == "item":
			var wm_chk_i = _get_wm()
			if wm_chk_i and (c_pos in wm_chk_i.collected_chunks):
				continue
			var i_node = template_instance.instantiate_item(ent.node_name) if template_instance else null
			if i_node:
				i_node.global_position = px_center
				i_node.set_meta("chunk_pos", c_pos)
				i_node.set_meta("entity_data", ent)
				items_container.add_child(i_node)
				
	_draw_chunk_path(state.chunk_path)
	_update_room_hud()
	
	last_csp_stats = csp_stats
	last_ls_stats = ls_stats
	
	if lbl_hud_stats:
		lbl_hud_stats.text = "Threat: %.1f / %.1f | Path: %d Rooms | Solvable: %s" % [
			state.difficulty_score,
			get_target_difficulty(),
			state.chunk_path.size(),
			"Yes" if state.is_solvable else "No"
		]
		
	_update_debug_ai_stats()
	if debug_grid_overlay and chk_debug_grid and chk_debug_grid.button_pressed:
		debug_grid_overlay.queue_redraw()
	if teleport_canvas and teleport_modal_panel and teleport_modal_panel.visible:
		teleport_canvas.queue_redraw()

func _draw_chunk_path(route: Array) -> void:
	if path_line == null:
		return
	path_line.clear_points()
	if chk_debug_optimal_path and not chk_debug_optimal_path.button_pressed:
		path_line.visible = false
		return
	path_line.visible = true
	for c_pos in route:
		path_line.add_point(get_chunk_center_pixel(c_pos))

# =========================================================================
# MONITOR POSISI PLAYER UNTUK CLICK-TO-MOVE (DETEKSI CHUNK REAL-TIME)
# =========================================================================

func _physics_process(_delta: float) -> void:
	if ingame_hud_panel == null or not ingame_hud_panel.visible:
		return
	if player_node == null or not is_instance_valid(player_node):
		return
	if current_map_state == null or is_event_busy:
		return

	_monitor_player_exploration_position()

func get_chunk_from_pixel(pixel_pos: Vector2) -> Vector2i:
	var p = template_instance.chunk_size_p if template_instance else 7
	var q = template_instance.chunk_size_q if template_instance else 7
	var stride_x_px = float(p + hallway_length) * 64.0
	var stride_y_px = float(q + hallway_length) * 64.0
	if stride_x_px <= 0.0 or stride_y_px <= 0.0:
		return Vector2i.ZERO
	var cx = int(floor(pixel_pos.x / stride_x_px))
	var cy = int(floor(pixel_pos.y / stride_y_px))
	return Vector2i(cx, cy)

func _monitor_player_exploration_position() -> void:
	var p_pos: Vector2 = player_node.global_position
	var p_chunk: Vector2i = get_chunk_from_pixel(p_pos)

	# 1. Update room HUD saat player melintasi batas chunk
	if p_chunk != current_chunk:
		if p_chunk.x >= 0 and p_chunk.x < current_map_state.grid_w and p_chunk.y >= 0 and p_chunk.y < current_map_state.grid_h:
			current_chunk = p_chunk
			_update_room_hud()
			if teleport_canvas and teleport_modal_panel and teleport_modal_panel.visible:
				teleport_canvas.queue_redraw()

	# 2. Cek apakah sampai ke portal chunk (Eksplorasi Selesai!)
	var portal_px = get_chunk_center_pixel(current_map_state.portal_chunk)
	if p_chunk == current_map_state.portal_chunk or p_pos.distance_to(portal_px) < 110.0:
		is_event_busy = true
		if player_node.has_method("set_active"):
			player_node.set_active(false)
		if "current_path" in player_node:
			player_node.current_path.clear()
		player_node.velocity = Vector2.ZERO
		_show_exploration_recap_modal()
		return

	# 3. Cek Item di seluruh chunk yang belum diambil
	for c_pos in current_map_state.chunk_entities.keys():
		var ent = current_map_state.chunk_entities[c_pos]
		if ent.type == "item":
			var wm_chk_i = _get_wm()
			if wm_chk_i and (c_pos in wm_chk_i.collected_chunks):
				continue
			var item_px = get_chunk_center_pixel(c_pos)
			if p_chunk == c_pos or p_pos.distance_to(item_px) < 135.0:
				_collect_item_at_chunk(c_pos, ent)
				break

	# 4. Cek Enemy di seluruh chunk yang belum dikalahkan
	for c_pos in current_map_state.chunk_entities.keys():
		var ent = current_map_state.chunk_entities[c_pos]
		if ent.type == "enemy":
			var wm_chk = _get_wm()
			if wm_chk and (c_pos in wm_chk.defeated_chunks):
				continue
			var enemy_px = get_chunk_center_pixel(c_pos)
			if p_chunk == c_pos or p_pos.distance_to(enemy_px) < 145.0:
				if chk_debug_skip_battle and chk_debug_skip_battle.button_pressed:
					_trigger_enemy_encounter(c_pos, ent)
					return
				is_event_busy = true
				if player_node.has_method("set_active"):
					player_node.set_active(false)
				if "current_path" in player_node:
					player_node.current_path.clear()
				player_node.velocity = Vector2.ZERO
				_trigger_enemy_encounter(c_pos, ent)
				return

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

# =========================================================================
# CHUNK INTERACTION & BATTLE TRIGGER (WILDERNESS INTEGRATION)
# =========================================================================


func _collect_item_at_chunk(c_pos: Vector2i, ent: Dictionary) -> void:
	var wm = _get_wm()
	if wm:
		if c_pos in wm.collected_chunks:
			return
		wm.collected_chunks.append(c_pos)

	var item_node: Node2D = null
	if items_container:
		for child in items_container.get_children():
			if child.has_meta("chunk_pos") and child.get_meta("chunk_pos") == c_pos:
				item_node = child
				break
		if item_node == null:
			var target_px = get_chunk_center_pixel(c_pos)
			for child in items_container.get_children():
				if child is Node2D and child.global_position.distance_to(target_px) < 60.0:
					item_node = child
					break

	var pickup_res := {}
	if has_node("/root/WildernessManager"):
		pickup_res = wm.apply_item_pickup(ent.node_name)
		_update_player_status_hud()

	if item_node and is_instance_valid(item_node) and player_node:
		var tw = create_tween().set_parallel(true)
		tw.tween_property(item_node, "global_position", player_node.global_position, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(item_node, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(item_node, "modulate:a", 0.0, 0.4)
		tw.chain().tween_callback(func():
			if is_instance_valid(item_node):
				item_node.queue_free()
		)
	elif item_node and is_instance_valid(item_node):
		item_node.queue_free()

	if not pickup_res.is_empty() and player_node:
		_spawn_floating_text(player_node.global_position, pickup_res.get("text", "+Item"), pickup_res.get("color", Color.WHITE))

func _trigger_enemy_encounter(c_pos: Vector2i, ent: Dictionary) -> void:
	if chk_debug_skip_battle and chk_debug_skip_battle.button_pressed:
		var wm = _get_wm()
		if wm:
			if not (c_pos in wm.defeated_chunks):
				wm.defeated_chunks.append(c_pos)
				wm.enemies_defeated_count += 1
		
		var enemy_node: Node2D = null
		if enemies_container:
			for child in enemies_container.get_children():
				if child.has_meta("chunk_pos") and child.get_meta("chunk_pos") == c_pos:
					enemy_node = child
					break
		if enemy_node and is_instance_valid(enemy_node):
			var tw = create_tween()
			tw.tween_property(enemy_node, "modulate:a", 0.0, 0.25)
			tw.tween_callback(enemy_node.queue_free)
		
		if current_map_state and current_map_state.chunk_entities.has(c_pos):
			current_map_state.chunk_entities[c_pos]["type"] = "defeated"
		is_event_busy = false
		if player_node:
			if player_node.has_method("set_active"):
				player_node.set_active(true)
			_spawn_floating_text(player_node.global_position, "BATTLE SKIPPED: %s" % ent.get("name", "Enemy"), Color(1.0, 0.75, 0.3))
		_update_room_hud()
		return

	is_event_busy = true
	if player_node and player_node.has_method("set_active"):
		player_node.set_active(false)
	if player_node and "current_path" in player_node:
		player_node.current_path.clear()
	if player_node:
		player_node.velocity = Vector2.ZERO

	var enemy_node: Node2D = null
	if enemies_container:
		for child in enemies_container.get_children():
			if child.has_meta("chunk_pos") and child.get_meta("chunk_pos") == c_pos:
				enemy_node = child
				break
		if enemy_node == null:
			var target_px = get_chunk_center_pixel(c_pos)
			for child in enemies_container.get_children():
				if child is Node2D and child.global_position.distance_to(target_px) < 60.0:
					enemy_node = child
					break

	if enemy_node and is_instance_valid(enemy_node) and player_node:
		if enemy_node.has_method("play_animation"):
			enemy_node.play_animation("run")

		var sp = enemy_node.get_node_or_null("Sprite2D") as Sprite2D
		if sp:
			sp.flip_h = (player_node.global_position.x < enemy_node.global_position.x)

		var tw = create_tween()
		tw.tween_property(enemy_node, "global_position", player_node.global_position, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			_launch_battle_scene(c_pos, ent.node_name)
		)
	else:
		_launch_battle_scene(c_pos, ent.node_name)

func _launch_battle_scene(c_pos: Vector2i, enemy_node_name: String) -> void:
	var wm = _get_wm()
	if wm:
		wm.current_chunk = c_pos
		wm.saved_map_state = current_map_state
		wm.start_wilderness_battle(enemy_node_name, c_pos)
	else:
		get_tree().change_scene_to_file("res://WildernessBattleStage.tscn")

func _show_exploration_recap_modal() -> void:
	if is_instance_valid(recap_modal_panel):
		recap_modal_panel.queue_free()
		recap_modal_panel = null

	recap_modal_panel = PanelContainer.new()
	recap_modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	recap_modal_panel.custom_minimum_size = Vector2(500, 360)
	recap_modal_panel.offset_left = -250.0
	recap_modal_panel.offset_top = -180.0
	recap_modal_panel.offset_right = 250.0
	recap_modal_panel.offset_bottom = 180.0
	recap_modal_panel.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.16, 0.98)
	style.border_color = Color(0.3, 0.95, 0.65, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	recap_modal_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	recap_modal_panel.add_child(vbox)

	var title := Label.new()
	title.text = "🎉 EKSPLORASI SELESAI!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.3, 0.95, 0.65))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pawn berhasil mencapai Portal Wilderness dan menyelesaikan seluruh eksplorasi!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.88, 0.96))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	var wm = get_node_or_null("/root/WildernessManager")
	var hp_val = wm.get("player_hp") if wm else 500
	var max_hp_val = wm.get("player_max_hp") if wm else 500
	var def_val = wm.get("enemies_defeated_count") if wm else 0
	var itm_val = wm.get("items_collected_count") if wm else 0
	var thr_val = current_map_state.difficulty_score if current_map_state else 0.0

	_add_recap_stat_row(grid, "💖 Sisa HP Player:", "%d / %d" % [hp_val, max_hp_val], Color(0.35, 1.0, 0.55))
	_add_recap_stat_row(grid, "⚔️ Musuh Dikalahkan:", "%d Musuh" % def_val, Color(1.0, 0.45, 0.45))
	_add_recap_stat_row(grid, "💎 Item Diambil:", "%d Item" % itm_val, Color(0.4, 0.85, 1.0))
	_add_recap_stat_row(grid, "🔥 Total Threat Cleared:", "%.1f" % thr_val, Color(1.0, 0.85, 0.3))

	vbox.add_child(HSeparator.new())

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)

	var btn_overworld := Button.new()
	btn_overworld.text = "🏠 Kembali ke Overworld"
	btn_overworld.custom_minimum_size = Vector2(230, 44)
	var ob := StyleBoxFlat.new()
	ob.bg_color = Color(0.14, 0.45, 0.65, 1.0)
	ob.border_color = Color(0.35, 0.85, 1.0, 1.0)
	ob.set_border_width_all(1)
	ob.set_corner_radius_all(8)
	btn_overworld.add_theme_stylebox_override("normal", ob)
	btn_overworld.pressed.connect(func():
		if wm:
			wm.clear_session()
		get_tree().change_scene_to_file("res://Overworld.tscn")
	)
	btn_box.add_child(btn_overworld)

	ui_layer.add_child(recap_modal_panel)

func _add_recap_stat_row(grid: GridContainer, label_txt: String, val_txt: String, val_col: Color) -> void:
	var l := Label.new()
	l.text = label_txt
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	grid.add_child(l)

	var v := Label.new()
	v.text = val_txt
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", val_col)
	grid.add_child(v)

func _spawn_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 50
	label.position = world_pos + Vector2(-90, -50)
	label.custom_minimum_size = Vector2(180, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)

	var tw = create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 35.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.2)
	tw.chain().tween_callback(label.queue_free)
