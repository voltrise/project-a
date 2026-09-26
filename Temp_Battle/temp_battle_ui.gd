class_name TempBattleUI
extends CanvasLayer

signal player_action_selected(action: int)
signal reset_battle_requested()
signal run_experiments_requested()
signal ai_config_changed(algo: int, depth: int, eval_type: int, ordering: int)

const StateScript = preload("res://Temp_Battle/temp_battle_state.gd")
const AIScript = preload("res://Temp_Battle/temp_battle_ai.gd")

# ── UI Elements ────────────────────────────────────────────────────────
var player_hp_bar: ProgressBar
var player_hp_lbl: Label
var player_stm_bar: ProgressBar
var player_stm_lbl: Label
var player_status_badge: Label

var npc_hp_bar: ProgressBar
var npc_hp_lbl: Label
var npc_stm_bar: ProgressBar
var npc_stm_lbl: Label
var npc_status_badge: Label

var turn_banner_label: Label
var log_rich_text: RichTextLabel

# 4 Action Buttons
var btn_attack: Button
var btn_heavy: Button
var btn_defend: Button
var btn_rest: Button

# Debug Overlay Elements
var debug_panel: PanelContainer
var btn_toggle_debug: Button
var opt_algorithm: OptionButton
var slider_depth: HSlider
var label_depth: Label
var opt_eval_type: OptionButton
var opt_move_ordering: OptionButton

var lbl_nodes_searched: Label
var lbl_prune_count: Label
var lbl_search_time: Label
var candidates_container: VBoxContainer

# Experiment Modal
var experiment_modal: PanelContainer
var experiment_text: RichTextLabel


func _init() -> void:
	layer = 10


func _ready() -> void:
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 or event.keycode == KEY_D:
			toggle_debug_panel()


func toggle_debug_panel() -> void:
	if debug_panel:
		debug_panel.visible = not debug_panel.visible
		if btn_toggle_debug:
			btn_toggle_debug.text = "📊 Debug [%s]" % ("ON" if debug_panel.visible else "OFF")


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── 1. Top Header Bar ──────────────────────────────────────────────
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.custom_minimum_size.y = 36
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	top_style.set_content_margin_all(6)
	top_panel.add_theme_stylebox_override("panel", top_style)
	root.add_child(top_panel)

	var top_hbox := HBoxContainer.new()
	top_panel.add_child(top_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "⚔ Battle System (Adversarial Search)"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	top_hbox.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	btn_toggle_debug = Button.new()
	btn_toggle_debug.text = "📊 Debug [ON]"
	btn_toggle_debug.pressed.connect(toggle_debug_panel)
	top_hbox.add_child(btn_toggle_debug)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 Reset"
	reset_btn.pressed.connect(func(): reset_battle_requested.emit())
	top_hbox.add_child(reset_btn)

	# ── 2. Fighter Status Cards ────────────────────────────────────────
	var status_container := HBoxContainer.new()
	status_container.position = Vector2(20, 48)
	status_container.size = Vector2(820, 115)
	status_container.add_theme_constant_override("separation", 20)
	root.add_child(status_container)

	# Player Card
	var p_card := _create_fighter_card("Player", Color(0.25, 0.65, 0.95))
	status_container.add_child(p_card["panel"])
	player_hp_bar = p_card["hp_bar"]
	player_hp_lbl = p_card["hp_lbl"]
	player_stm_bar = p_card["stm_bar"]
	player_stm_lbl = p_card["stm_lbl"]
	player_status_badge = p_card["status_lbl"]

	# NPC Card
	var n_card := _create_fighter_card("NPC (AI)", Color(0.95, 0.35, 0.35))
	status_container.add_child(n_card["panel"])
	npc_hp_bar = n_card["hp_bar"]
	npc_hp_lbl = n_card["hp_lbl"]
	npc_stm_bar = n_card["stm_bar"]
	npc_stm_lbl = n_card["stm_lbl"]
	npc_status_badge = n_card["status_lbl"]

	# ── 3. Turn Indicator Banner ───────────────────────────────────────
	turn_banner_label = Label.new()
	turn_banner_label.position = Vector2(20, 172)
	turn_banner_label.size = Vector2(820, 28)
	turn_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_banner_label.text = "Giliran: Player"
	turn_banner_label.add_theme_font_size_override("font_size", 14)
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.12, 0.16, 0.22, 0.85)
	banner_style.set_corner_radius_all(6)
	turn_banner_label.add_theme_stylebox_override("normal", banner_style)
	root.add_child(turn_banner_label)

	# ── 4. Bottom Controls: Action Buttons & Log ──────────────────────
	var bottom_container := HBoxContainer.new()
	bottom_container.position = Vector2(20, 520)
	bottom_container.size = Vector2(820, 180)
	bottom_container.add_theme_constant_override("separation", 16)
	root.add_child(bottom_container)

	# Actions Panel
	var actions_panel := PanelContainer.new()
	actions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actions_style := StyleBoxFlat.new()
	actions_style.bg_color = Color(0.10, 0.12, 0.16, 0.90)
	actions_style.set_corner_radius_all(8)
	actions_style.set_content_margin_all(10)
	actions_panel.add_theme_stylebox_override("panel", actions_style)
	bottom_container.add_child(actions_panel)

	var actions_vbox := VBoxContainer.new()
	actions_vbox.add_theme_constant_override("separation", 6)
	actions_panel.add_child(actions_vbox)

	var actions_title := Label.new()
	actions_title.text = "Aksi Player (Branching <= 4):"
	actions_title.add_theme_font_size_override("font_size", 13)
	actions_title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	actions_vbox.add_child(actions_title)

	var btns_grid := GridContainer.new()
	btns_grid.columns = 2
	btns_grid.add_theme_constant_override("h_separation", 8)
	btns_grid.add_theme_constant_override("v_separation", 6)
	btns_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions_vbox.add_child(btns_grid)

	btn_attack = Button.new()
	btn_attack.text = "⚔ Attack (30 STM)"
	btn_attack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_attack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_attack.pressed.connect(func(): player_action_selected.emit(StateScript.Action.ATTACK))
	btns_grid.add_child(btn_attack)

	btn_heavy = Button.new()
	btn_heavy.text = "💥 Heavy Attack (60 STM)"
	btn_heavy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_heavy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_heavy.pressed.connect(func(): player_action_selected.emit(StateScript.Action.HEAVY_ATTACK))
	btns_grid.add_child(btn_heavy)

	btn_defend = Button.new()
	btn_defend.text = "🛡 Defend (Guard)"
	btn_defend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_defend.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_defend.pressed.connect(func(): player_action_selected.emit(StateScript.Action.DEFEND))
	btns_grid.add_child(btn_defend)

	btn_rest = Button.new()
	btn_rest.text = "💤 Rest (+50 STM)"
	btn_rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_rest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_rest.pressed.connect(func(): player_action_selected.emit(StateScript.Action.REST))
	btns_grid.add_child(btn_rest)

	# Combat Log Panel
	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size.x = 380
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.07, 0.09, 0.12, 0.90)
	log_style.set_corner_radius_all(8)
	log_style.set_content_margin_all(8)
	log_panel.add_theme_stylebox_override("panel", log_style)
	bottom_container.add_child(log_panel)

	var log_vbox := VBoxContainer.new()
	log_panel.add_child(log_vbox)

	var log_header := Label.new()
	log_header.text = "Log Pertarungan:"
	log_header.add_theme_font_size_override("font_size", 12)
	log_header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	log_vbox.add_child(log_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_vbox.add_child(scroll)

	log_rich_text = RichTextLabel.new()
	log_rich_text.bbcode_enabled = true
	log_rich_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_rich_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rich_text.scroll_following = true
	scroll.add_child(log_rich_text)

	# ── 5. DEBUG OVERLAY ──────────────────────────────────────────────
	_build_debug_overlay(root)

	# ── 6. Experiment Results Modal ────────────────────────────────────
	_build_experiment_modal(root)


func _create_fighter_card(title: String, accent_color: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.13, 0.18, 0.85)
	style.border_color = accent_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", accent_color)
	vbox.add_child(name_lbl)

	# HP Row
	var hp_box := HBoxContainer.new()
	vbox.add_child(hp_box)

	var hp_tag := Label.new()
	hp_tag.text = "HP:"
	hp_tag.custom_minimum_size.x = 35
	hp_tag.add_theme_font_size_override("font_size", 11)
	hp_box.add_child(hp_tag)

	var hp_bar := ProgressBar.new()
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.custom_minimum_size.y = 14
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	hp_box.add_child(hp_bar)

	var hp_lbl := Label.new()
	hp_lbl.text = "100/100"
	hp_lbl.custom_minimum_size.x = 65
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_lbl.add_theme_font_size_override("font_size", 11)
	hp_box.add_child(hp_lbl)

	# Stamina Row
	var stm_box := HBoxContainer.new()
	vbox.add_child(stm_box)

	var stm_tag := Label.new()
	stm_tag.text = "STM:"
	stm_tag.custom_minimum_size.x = 35
	stm_tag.add_theme_font_size_override("font_size", 11)
	stm_tag.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	stm_box.add_child(stm_tag)

	var stm_bar := ProgressBar.new()
	stm_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stm_bar.custom_minimum_size.y = 14
	stm_bar.max_value = 100
	stm_bar.value = 100
	stm_bar.show_percentage = false
	stm_box.add_child(stm_bar)

	var stm_lbl := Label.new()
	stm_lbl.text = "100/100"
	stm_lbl.custom_minimum_size.x = 65
	stm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stm_lbl.add_theme_font_size_override("font_size", 11)
	stm_box.add_child(stm_lbl)

	# Badges Row
	var badges_box := HBoxContainer.new()
	badges_box.add_theme_constant_override("separation", 10)
	vbox.add_child(badges_box)

	var status_lbl := Label.new()
	status_lbl.text = "Status: Normal"
	status_lbl.add_theme_font_size_override("font_size", 11)
	badges_box.add_child(status_lbl)

	return {
		"panel": panel,
		"hp_bar": hp_bar,
		"hp_lbl": hp_lbl,
		"stm_bar": stm_bar,
		"stm_lbl": stm_lbl,
		"status_lbl": status_lbl
	}


func _build_debug_overlay(parent: Control) -> void:
	debug_panel = PanelContainer.new()
	debug_panel.position = Vector2(860, 48)
	debug_panel.size = Vector2(400, 652)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	style.border_color = Color(0.35, 0.45, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	debug_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(debug_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	debug_panel.add_child(vbox)

	var d_title := Label.new()
	d_title.text = "📊 DEBUG OVERLAY"
	d_title.add_theme_font_size_override("font_size", 13)
	d_title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	vbox.add_child(d_title)

	vbox.add_child(HSeparator.new())

	var cfg_grid := GridContainer.new()
	cfg_grid.columns = 2
	cfg_grid.add_theme_constant_override("h_separation", 8)
	cfg_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(cfg_grid)

	# 1. Algorithm
	var lbl_algo := Label.new()
	lbl_algo.text = "Algoritma:"
	lbl_algo.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_algo)

	opt_algorithm = OptionButton.new()
	opt_algorithm.add_item("Alpha-Beta", AIScript.Algorithm.ALPHABETA)
	opt_algorithm.add_item("Minimax", AIScript.Algorithm.MINIMAX)
	opt_algorithm.add_item("Expectimax", AIScript.Algorithm.EXPECTIMAX)
	opt_algorithm.selected = 0
	opt_algorithm.item_selected.connect(func(_idx): _on_config_changed())
	cfg_grid.add_child(opt_algorithm)

	# 2. Depth
	var lbl_d := Label.new()
	lbl_d.text = "Kedalaman (Depth):"
	lbl_d.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_d)

	var depth_hbox := HBoxContainer.new()
	slider_depth = HSlider.new()
	slider_depth.min_value = 1
	slider_depth.max_value = 6
	slider_depth.value = 4
	slider_depth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_depth.value_changed.connect(func(v):
		label_depth.text = "%d" % int(v)
		_on_config_changed()
	)
	depth_hbox.add_child(slider_depth)

	label_depth = Label.new()
	label_depth.text = "4"
	label_depth.custom_minimum_size.x = 20
	label_depth.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	depth_hbox.add_child(label_depth)
	cfg_grid.add_child(depth_hbox)

	# 3. Evaluation Function
	var lbl_ev := Label.new()
	lbl_ev.text = "Fungsi Evaluasi:"
	lbl_ev.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_ev)

	opt_eval_type = OptionButton.new()
	opt_eval_type.add_item("Balanced", AIScript.EvalType.BALANCED)
	opt_eval_type.add_item("Aggressive", AIScript.EvalType.AGGRESSIVE)
	opt_eval_type.add_item("Defensive", AIScript.EvalType.DEFENSIVE)
	opt_eval_type.add_item("HP Ratio", AIScript.EvalType.HP_RATIO)
	opt_eval_type.selected = 0
	opt_eval_type.item_selected.connect(func(_idx): _on_config_changed())
	cfg_grid.add_child(opt_eval_type)

	# 4. Move Ordering
	var lbl_ord := Label.new()
	lbl_ord.text = "Move Ordering:"
	lbl_ord.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_ord)

	opt_move_ordering = OptionButton.new()
	opt_move_ordering.add_item("Optimal (Heuristic)", AIScript.MoveOrdering.OPTIMAL)
	opt_move_ordering.add_item("Default (No Sort)", AIScript.MoveOrdering.DEFAULT)
	opt_move_ordering.add_item("Reverse (Worst)", AIScript.MoveOrdering.REVERSE)
	opt_move_ordering.selected = 0
	opt_move_ordering.item_selected.connect(func(_idx): _on_config_changed())
	cfg_grid.add_child(opt_move_ordering)

	vbox.add_child(HSeparator.new())

	# Metrics
	var metrics_box := VBoxContainer.new()
	metrics_box.add_theme_constant_override("separation", 2)
	vbox.add_child(metrics_box)

	lbl_nodes_searched = Label.new()
	lbl_nodes_searched.text = "Nodes: 0"
	lbl_nodes_searched.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_nodes_searched)

	lbl_prune_count = Label.new()
	lbl_prune_count.text = "Pruned: 0"
	lbl_prune_count.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_prune_count)

	lbl_search_time = Label.new()
	lbl_search_time.text = "Waktu: 0.00 ms"
	lbl_search_time.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_search_time)

	vbox.add_child(HSeparator.new())

	# Root Candidates Breakdown
	var c_title := Label.new()
	c_title.text = "Aksi Dipertimbangkan NPC:"
	c_title.add_theme_font_size_override("font_size", 12)
	c_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	vbox.add_child(c_title)

	var cand_scroll := ScrollContainer.new()
	cand_scroll.custom_minimum_size.y = 120
	vbox.add_child(cand_scroll)

	candidates_container = VBoxContainer.new()
	candidates_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidates_container.add_theme_constant_override("separation", 2)
	cand_scroll.add_child(candidates_container)

	var empty_lbl := Label.new()
	empty_lbl.text = "Menunggu giliran NPC..."
	empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	empty_lbl.add_theme_font_size_override("font_size", 11)
	candidates_container.add_child(empty_lbl)

	vbox.add_child(HSeparator.new())

	# Benchmark Button
	var exp_btn := Button.new()
	exp_btn.text = "🔬 Jalankan Benchmark AI"
	exp_btn.custom_minimum_size.y = 30
	exp_btn.pressed.connect(func(): run_experiments_requested.emit())
	vbox.add_child(exp_btn)


func _build_experiment_modal(parent: Control) -> void:
	experiment_modal = PanelContainer.new()
	experiment_modal.position = Vector2(80, 50)
	experiment_modal.size = Vector2(1120, 620)
	experiment_modal.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.98)
	style.border_color = Color(0.95, 0.75, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	experiment_modal.add_theme_stylebox_override("panel", style)
	parent.add_child(experiment_modal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	experiment_modal.add_child(vbox)

	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	var title := Label.new()
	title.text = "HASIL EKSPERIMEN ADVERSARIAL SEARCH"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	header_hbox.add_child(title)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(sp)

	var close_btn := Button.new()
	close_btn.text = "✖ Tutup"
	close_btn.pressed.connect(func(): experiment_modal.visible = false)
	header_hbox.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	experiment_text = RichTextLabel.new()
	experiment_text.bbcode_enabled = true
	experiment_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	experiment_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(experiment_text)


func _on_config_changed() -> void:
	ai_config_changed.emit(
		opt_algorithm.get_selected_id(),
		int(slider_depth.value),
		opt_eval_type.get_selected_id(),
		opt_move_ordering.get_selected_id()
	)


# ══════════════════════════════════════════════════════════════════════
#  UPDATE UI DISPLAY
# ══════════════════════════════════════════════════════════════════════

func update_state_display(state: StateScript) -> void:
	var p = state.player
	var e = state.enemy

	# Player Stats
	player_hp_bar.max_value = p["max_hp"]
	player_hp_bar.value = p["hp"]
	player_hp_lbl.text = "%d/%d" % [p["hp"], p["max_hp"]]

	player_stm_bar.max_value = p["max_stamina"]
	player_stm_bar.value = p["stamina"]
	player_stm_lbl.text = "%d/%d" % [p["stamina"], p["max_stamina"]]

	if p.get("is_guard_broken", false):
		player_status_badge.text = "Status: GUARD BROKEN!"
		player_status_badge.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif p.get("is_defending", false):
		player_status_badge.text = "Status: Defending"
		player_status_badge.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	else:
		player_status_badge.text = "Status: Normal"
		player_status_badge.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# NPC Stats
	npc_hp_bar.max_value = e["max_hp"]
	npc_hp_bar.value = e["hp"]
	npc_hp_lbl.text = "%d/%d" % [e["hp"], e["max_hp"]]

	npc_stm_bar.max_value = e["max_stamina"]
	npc_stm_bar.value = e["stamina"]
	npc_stm_lbl.text = "%d/%d" % [e["stamina"], e["max_stamina"]]

	if e.get("is_guard_broken", false):
		npc_status_badge.text = "Status: GUARD BROKEN!"
		npc_status_badge.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif e.get("is_defending", false):
		npc_status_badge.text = "Status: Defending"
		npc_status_badge.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	else:
		npc_status_badge.text = "Status: Normal"
		npc_status_badge.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# Player Buttons State
	var is_player_turn = (state.current_turn == StateScript.Side.PLAYER) and not state.is_terminal()
	var is_broken: bool = p.get("is_guard_broken", false)

	if is_broken:
		btn_attack.disabled = true
		btn_heavy.disabled = true
		btn_defend.disabled = true
		btn_rest.disabled = not is_player_turn
	else:
		btn_attack.disabled = (not is_player_turn) or (p["stamina"] < StateScript.ATTACK_COST)
		btn_heavy.disabled = (not is_player_turn) or (p["stamina"] < StateScript.HEAVY_COST)
		btn_defend.disabled = not is_player_turn
		btn_rest.disabled = not is_player_turn

	# Turn banner
	if state.is_terminal():
		var winner = state.get_winner()
		if winner == StateScript.Side.PLAYER:
			turn_banner_label.text = "Duel Selesai: Player Menang"
			turn_banner_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		else:
			turn_banner_label.text = "Duel Selesai: NPC Menang"
			turn_banner_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif state.current_turn == StateScript.Side.PLAYER:
		turn_banner_label.text = "Giliran: Player"
		turn_banner_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	else:
		turn_banner_label.text = "Giliran: NPC"
		turn_banner_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))


func update_ai_debug(decision: Dictionary) -> void:
	lbl_nodes_searched.text = "Nodes: %d" % decision.get("total_nodes", 0)
	lbl_prune_count.text = "Pruned: %d" % decision.get("prune_count", 0)
	lbl_search_time.text = "Waktu: %.2f ms" % decision.get("time_ms", 0.0)

	for child in candidates_container.get_children():
		child.queue_free()

	var candidates: Array = decision.get("candidates", [])
	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "Tidak ada aksi."
		candidates_container.add_child(lbl)
		return

	for c in candidates:
		var row := HBoxContainer.new()
		var is_best: bool = c.get("is_best", false)

		var name_lbl := Label.new()
		name_lbl.text = "%-13s" % c.get("name", "")
		name_lbl.add_theme_font_size_override("font_size", 11)
		if is_best:
			name_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		row.add_child(name_lbl)

		var score_lbl := Label.new()
		score_lbl.text = "Skor: %6.1f" % c.get("score", 0.0)
		score_lbl.add_theme_font_size_override("font_size", 11)
		score_lbl.custom_minimum_size.x = 80
		row.add_child(score_lbl)

		var nodes_lbl := Label.new()
		nodes_lbl.text = "(%d n)" % c.get("nodes", 0)
		nodes_lbl.add_theme_font_size_override("font_size", 10)
		nodes_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		row.add_child(nodes_lbl)

		if is_best:
			var best_badge := Label.new()
			best_badge.text = " ★"
			best_badge.add_theme_font_size_override("font_size", 11)
			best_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			row.add_child(best_badge)

		candidates_container.add_child(row)


func append_battle_log(text: String, color: Color = Color.WHITE) -> void:
	var hex := color.to_html()
	log_rich_text.append_text("[color=#%s]%s[/color]
" % [hex, text])


func display_experiment_results(results: Dictionary) -> void:
	var bb := ""
	bb += "[b][color=#f4d03f]═══ EKSPERIMEN 1: MINIMAX vs ALPHA-BETA vs MOVE ORDERING ═══[/color][/b]
"
	bb += "[table=6]"
	bb += "[cell][b]Depth[/b][/cell][cell][b]Minimax[/b][/cell][cell][b]Alpha-Beta[/b][/cell][cell][b]Cutoffs[/b][/cell][cell][b]AB + Order[/b][/cell][cell][b]Match?[/b][/cell]"

	for row in results.get("depth_comparison", []):
		bb += "[cell]Depth %d[/cell]" % row["depth"]
		bb += "[cell]%d (%.2f ms)[/cell]" % [row["mm_nodes"], row["mm_time_ms"]]
		bb += "[cell]%d (%.2f ms)[/cell]" % [row["ab_nodes"], row["ab_time_ms"]]
		bb += "[cell]%d[/cell]" % row["ab_prunes"]
		bb += "[cell][color=#58d68d]%d (%.2f ms)[/color][/cell]" % [row["abo_nodes"], row["abo_time_ms"]]
		bb += "[cell][color=#5dade2]%s[/color][/cell]" % str(row["match"])
	bb += "[/table]

"

	bb += "[b][color=#f4d03f]═══ EKSPERIMEN 2: FUNGSI EVALUASI (DEPTH 4) ═══[/color][/b]
"
	bb += "[table=4]"
	bb += "[cell][b]Fungsi[/b][/cell][cell][b]Aksi Dipilih[/b][/cell][cell][b]Skor[/b][/cell][cell][b]Nodes[/b][/cell]"
	for row in results.get("eval_comparison", []):
		bb += "[cell]%s[/cell]" % row["eval_name"]
		bb += "[cell][color=#f39c12]%s[/color][/cell]" % row["action_name"]
		bb += "[cell]%7.2f[/cell]" % row["score"]
		bb += "[cell]%d[/cell]" % row["nodes"]
	bb += "[/table]

"

	bb += "[b][color=#f4d03f]═══ EKSPERIMEN 3: MOVE ORDERING (DEPTH 4) ═══[/color][/b]
"
	bb += "[table=4]"
	bb += "[cell][b]Mode Urutan[/b][/cell][cell][b]Aksi[/b][/cell][cell][b]Nodes[/b][/cell][cell][b]Cutoffs[/b][/cell]"
	for row in results.get("order_comparison", []):
		var col := "#58d68d" if "Optimal" in row["order_name"] else ("#ec7063" if "Reverse" in row["order_name"] else "#ffffff")
		bb += "[cell]%s[/cell]" % row["order_name"]
		bb += "[cell]%s[/cell]" % row["action_name"]
		bb += "[cell][color=%s]%d[/color][/cell]" % [col, row["nodes"]]
		bb += "[cell]%d[/cell]" % row["prunes"]
	bb += "[/table]
"

	experiment_text.text = bb
	experiment_modal.visible = true
