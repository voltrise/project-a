class_name MinimaxTreeViewer
extends Control

## Visualizer Interaktif Pohon Keputusan Minimax & Alpha-Beta Search.
## Fitur:
## - Full Pan & Dragging (Klik kiri/tengah/kanan drag)
## - Smooth Focal Zooming (Mouse Wheel Up/Down, Zoom In/Out buttons)
## - Dua Mode Tampilan:
##     1. SIMPLIFIED: Icon-icon move kecil & kompak; hover untuk melihat detail lengkap.
##     2. DETAILED: Menampilkan icon move battle UI + semua detail teks (Skor, HP, Alpha/Beta).
## - Mode Algoritma Otomatis berdasarkan Leader (Pawn -> Minimax, Archer -> Alpha-Beta).
## - Interactive Tree Graph (MAX/MIN nodes, Best Move Path, Pruned Cutoffs)
## - Dynamic Depth Selector (1 s/d 4)
## - Live Node Inspector & Floating Hover Tooltip

const StateScript = preload("res://scripts/battle/battle_state.gd")
const AIScript = preload("res://scripts/battle/battle_ai.gd")

# Move Icons from Battle UI
const ICON_ATTACK = preload("res://ui/BattleStage/Action Button/Attack Btn.png")
const ICON_SPECIAL = preload("res://ui/BattleStage/Action Button/Special Btn.png")
const ICON_DEFENSE = preload("res://ui/BattleStage/Action Button/Defense Btn.png")
const ICON_ITEM = preload("res://ui/BattleStage/Action Button/Item Btn.png")
const ICON_AVATAR_PAWN = preload("res://ui/avatar_pawn.png")
const ICON_AVATAR_ARCHER = preload("res://ui/avatar_archer.png")

enum ViewMode { SIMPLIFIED = 0, DETAILED = 1 }

# State & AI references
var source_state: StateScript
var ai_engine: AIScript
var view_algo: int = AIScript.Algorithm.ALPHABETA
var view_depth: int = 3
var view_eval: int = AIScript.EvalType.BALANCED
var view_ordering: int = AIScript.MoveOrdering.OPTIMAL
var current_leader: String = "Pawn"
var current_view_mode: int = ViewMode.DETAILED

# Tree data & layout
var tree_root: Dictionary = {}
var hovered_node: Dictionary = {}
var _node_counter: int = 0

# Pan & Zoom parameters
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var pan_start: Vector2 = Vector2.ZERO
var _cam_tween: Tween

# UI Controls
var bg_overlay: ColorRect
var modal_card: PanelContainer
var viewport_area: Control
var tree_draw_canvas: Control
var inspector_panel: PanelContainer
var inspector_label: RichTextLabel
var lbl_stats_summary: Label
var btn_depth_buttons: Dictionary = {}
var lbl_algo_display: Label
var lbl_turn_state: Label
var btn_mode_simplified: Button
var btn_mode_detailed: Button
var lbl_zoom_val: Label

# Fonts
var font_bold: Font
var font_medium: Font


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 300
	visible = false

	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		font_bold = load("res://fonts/PixelifySans-Bold.ttf")
	if ResourceLoader.exists("res://fonts/PixelifySans-Medium.ttf"):
		font_medium = load("res://fonts/PixelifySans-Medium.ttf")


func _ready() -> void:
	_build_ui()


# ══════════════════════════════════════════════════════════════════════
#  NODE METRICS (DYNAMIC PER VIEW MODE)
# ══════════════════════════════════════════════════════════════════════

func get_node_w() -> float:
	return 64.0 if current_view_mode == ViewMode.SIMPLIFIED else 204.0


func get_node_h() -> float:
	return 64.0 if current_view_mode == ViewMode.SIMPLIFIED else 96.0


func get_h_gap() -> float:
	return 22.0 if current_view_mode == ViewMode.SIMPLIFIED else 28.0


func get_v_gap() -> float:
	return 58.0 if current_view_mode == ViewMode.SIMPLIFIED else 80.0


# ══════════════════════════════════════════════════════════════════════
#  UI CONSTRUCTION
# ══════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	# 1. Translucent Backdrop Overlay
	bg_overlay = ColorRect.new()
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_overlay.color = Color(0.02, 0.03, 0.05, 0.38)
	add_child(bg_overlay)

	# 2. Main Window Modal Card (Responsive Full Rect with Margins, Translucent Glass Styling)
	modal_card = PanelContainer.new()
	modal_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_card.offset_left = 20.0
	modal_card.offset_top = 16.0
	modal_card.offset_right = -20.0
	modal_card.offset_bottom = -16.0
	modal_card.custom_minimum_size = Vector2(720, 480)

	var modal_sb := StyleBoxFlat.new()
	modal_sb.bg_color = Color(0.05, 0.07, 0.12, 0.42)
	modal_sb.border_color = Color(0.2, 0.8, 0.95, 0.75)
	modal_sb.set_border_width_all(2)
	modal_sb.set_corner_radius_all(12)
	modal_sb.set_content_margin_all(10)
	modal_sb.shadow_size = 24
	modal_sb.shadow_color = Color(0.0, 0.35, 0.5, 0.3)
	modal_card.add_theme_stylebox_override("panel", modal_sb)
	add_child(modal_card)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	modal_card.add_child(main_vbox)

	# 3A. Header Bar (Row 1: Title, Algorithm, Turn Info, and Close button)
	var header_bar := HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", 8)
	main_vbox.add_child(header_bar)

	var title_lbl := Label.new()
	title_lbl.text = "🌳 ADVERSARIAL TREE"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.3, 0.95, 0.85))
	if font_bold: title_lbl.add_theme_font_override("font", font_bold)
	header_bar.add_child(title_lbl)

	# Algorithm Display Badge (Read-only, tied to active leader)
	var algo_panel := PanelContainer.new()
	var ap_sb := StyleBoxFlat.new()
	ap_sb.bg_color = Color(0.1, 0.14, 0.22, 0.9)
	ap_sb.border_color = Color(0.3, 0.6, 0.85, 0.8)
	ap_sb.set_border_width_all(1)
	ap_sb.set_corner_radius_all(6)
	ap_sb.content_margin_left = 8
	ap_sb.content_margin_right = 8
	ap_sb.content_margin_top = 2
	ap_sb.content_margin_bottom = 2
	algo_panel.add_theme_stylebox_override("panel", ap_sb)
	header_bar.add_child(algo_panel)

	lbl_algo_display = Label.new()
	lbl_algo_display.text = "⚡ Alpha-Beta (Archer)"
	lbl_algo_display.add_theme_font_size_override("font_size", 11)
	lbl_algo_display.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	if font_bold: lbl_algo_display.add_theme_font_override("font", font_bold)
	algo_panel.add_child(lbl_algo_display)

	# Snapshot Info Badge (shows which turn & who is moving at root)
	var snap_panel := PanelContainer.new()
	var sp_sb := StyleBoxFlat.new()
	sp_sb.bg_color = Color(0.08, 0.12, 0.18, 0.9)
	sp_sb.border_color = Color(0.3, 0.5, 0.7, 0.7)
	sp_sb.set_border_width_all(1)
	sp_sb.set_corner_radius_all(6)
	sp_sb.content_margin_left = 8
	sp_sb.content_margin_right = 8
	sp_sb.content_margin_top = 2
	sp_sb.content_margin_bottom = 2
	snap_panel.add_theme_stylebox_override("panel", sp_sb)
	header_bar.add_child(snap_panel)

	lbl_turn_state = Label.new()
	lbl_turn_state.text = "📍 Turn 1 (Player)"
	lbl_turn_state.add_theme_font_size_override("font_size", 11)
	lbl_turn_state.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	if font_medium: lbl_turn_state.add_theme_font_override("font", font_medium)
	snap_panel.add_child(lbl_turn_state)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(spacer)

	# Close Button
	var close_btn := Button.new()
	close_btn.text = "✖ Tutup [ESC]"
	close_btn.custom_minimum_size = Vector2(96, 26)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.45, 0.15, 0.18, 0.9)
	csb.border_color = Color(0.9, 0.35, 0.35, 0.9)
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(6)
	close_btn.add_theme_stylebox_override("normal", csb)
	close_btn.pressed.connect(close_visualizer)
	header_bar.add_child(close_btn)

	# 3B. Controls Toolbar (Row 2: View Mode, Depth, Zoom, Opacity)
	var toolbar_panel := PanelContainer.new()
	var tb_sb := StyleBoxFlat.new()
	tb_sb.bg_color = Color(0.07, 0.10, 0.16, 0.65)
	tb_sb.border_color = Color(0.25, 0.35, 0.5, 0.6)
	tb_sb.set_border_width_all(1)
	tb_sb.set_corner_radius_all(6)
	tb_sb.content_margin_left = 8
	tb_sb.content_margin_right = 8
	tb_sb.content_margin_top = 3
	tb_sb.content_margin_bottom = 3
	toolbar_panel.add_theme_stylebox_override("panel", tb_sb)
	main_vbox.add_child(toolbar_panel)

	var toolbar_box := HBoxContainer.new()
	toolbar_box.add_theme_constant_override("separation", 6)
	toolbar_panel.add_child(toolbar_box)

	# View Mode Switcher: Simplified vs Detailed
	var mode_box := HBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 4)
	toolbar_box.add_child(mode_box)

	var lbl_mode := Label.new()
	lbl_mode.text = "Tampilan:"
	lbl_mode.add_theme_font_size_override("font_size", 11)
	lbl_mode.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	mode_box.add_child(lbl_mode)

	btn_mode_simplified = _create_toggle_btn("🔲 Simplified", current_view_mode == ViewMode.SIMPLIFIED)
	btn_mode_simplified.tooltip_text = "Mode Ikon Ringkas: Node kecil berbentuk ikon aksi; arahkan kursor untuk melihat detail lengkap."
	btn_mode_simplified.pressed.connect(func(): _set_view_mode(ViewMode.SIMPLIFIED))
	mode_box.add_child(btn_mode_simplified)

	btn_mode_detailed = _create_toggle_btn("📋 Detailed", current_view_mode == ViewMode.DETAILED)
	btn_mode_detailed.tooltip_text = "Mode Lengkap: Menampilkan ikon aksi dan seluruh metrik teks pada setiap node."
	btn_mode_detailed.pressed.connect(func(): _set_view_mode(ViewMode.DETAILED))
	mode_box.add_child(btn_mode_detailed)

	toolbar_box.add_child(_create_vsep())

	# Depth Selectors
	var depth_box := HBoxContainer.new()
	depth_box.add_theme_constant_override("separation", 3)
	toolbar_box.add_child(depth_box)

	var lbl_d_title := Label.new()
	lbl_d_title.text = "Kedalaman:"
	lbl_d_title.add_theme_font_size_override("font_size", 11)
	lbl_d_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	depth_box.add_child(lbl_d_title)

	for d in [1, 2, 3, 4]:
		var d_btn := _create_toggle_btn("D%d" % d, d == view_depth)
		d_btn.custom_minimum_size = Vector2(30, 24)
		d_btn.pressed.connect(func(target_d = d):
			view_depth = target_d
			_update_depth_buttons()
			_rebuild_tree()
		)
		depth_box.add_child(d_btn)
		btn_depth_buttons[d] = d_btn

	toolbar_box.add_child(_create_vsep())

	# Zoom controls
	var zoom_box := HBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 3)
	toolbar_box.add_child(zoom_box)

	var lbl_z_title := Label.new()
	lbl_z_title.text = "Zoom:"
	lbl_z_title.add_theme_font_size_override("font_size", 11)
	lbl_z_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	zoom_box.add_child(lbl_z_title)

	var zoom_out_btn := Button.new()
	zoom_out_btn.text = " ➖ "
	zoom_out_btn.custom_minimum_size = Vector2(28, 24)
	zoom_out_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	zoom_out_btn.pressed.connect(func():
		if viewport_area:
			_zoom_at(viewport_area.size * 0.5, 1.0 / 1.25)
	)
	zoom_box.add_child(zoom_out_btn)

	lbl_zoom_val = Label.new()
	lbl_zoom_val.text = "100%"
	lbl_zoom_val.custom_minimum_size.x = 36
	lbl_zoom_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_zoom_val.add_theme_font_size_override("font_size", 11)
	zoom_box.add_child(lbl_zoom_val)

	var zoom_in_btn := Button.new()
	zoom_in_btn.text = " ➕ "
	zoom_in_btn.custom_minimum_size = Vector2(28, 24)
	zoom_in_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	zoom_in_btn.pressed.connect(func():
		if viewport_area:
			_zoom_at(viewport_area.size * 0.5, 1.25)
	)
	zoom_box.add_child(zoom_in_btn)

	var reset_view_btn := Button.new()
	reset_view_btn.text = "⟲ Reset"
	reset_view_btn.custom_minimum_size = Vector2(52, 24)
	reset_view_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset_view_btn.pressed.connect(reset_view)
	zoom_box.add_child(reset_view_btn)

	var btn_go_best := Button.new()
	btn_go_best.text = "★ Go to BEST"
	btn_go_best.custom_minimum_size = Vector2(96, 24)
	btn_go_best.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_go_best.add_theme_font_size_override("font_size", 11)
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0.24, 0.20, 0.06, 0.85)
	gsb.border_color = Color(0.95, 0.8, 0.25, 0.9)
	gsb.set_border_width_all(1)
	gsb.set_corner_radius_all(6)
	gsb.set_content_margin_all(3)
	btn_go_best.add_theme_stylebox_override("normal", gsb)
	btn_go_best.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	btn_go_best.tooltip_text = "Fokuskan kamera langsung ke node pilihan terbaik (Best Move) hasil algoritma."
	btn_go_best.pressed.connect(go_to_best)
	zoom_box.add_child(btn_go_best)

	# 4. Viewport Area (Container with clip_contents)
	viewport_area = Control.new()
	viewport_area.name = "TreeViewport"
	viewport_area.clip_contents = true
	viewport_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_area.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_area.mouse_default_cursor_shape = Control.CURSOR_MOVE
	viewport_area.gui_input.connect(_on_canvas_gui_input)
	viewport_area.mouse_exited.connect(func():
		hovered_node = {}
		if inspector_panel:
			inspector_panel.visible = false
		_queue_tree_redraw()
	)

	var vp_sb := StyleBoxFlat.new()
	vp_sb.bg_color = Color(0.03, 0.04, 0.08, 0.35)
	vp_sb.border_color = Color(0.2, 0.3, 0.45, 0.5)
	vp_sb.set_border_width_all(1)
	vp_sb.set_corner_radius_all(8)
	var vp_panel := PanelContainer.new()
	vp_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_panel.add_theme_stylebox_override("panel", vp_sb)
	vp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_area.add_child(vp_panel)

	# Inner Canvas that gets drawn
	tree_draw_canvas = Control.new()
	tree_draw_canvas.name = "TreeDrawCanvas"
	tree_draw_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_draw_canvas.draw.connect(_on_draw_tree)
	viewport_area.add_child(tree_draw_canvas)

	main_vbox.add_child(viewport_area)

	# 5. Floating / Bottom Details & Legend Bar
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 14)
	main_vbox.add_child(bottom_bar)

	# Legend
	var legend_box := HBoxContainer.new()
	legend_box.add_theme_constant_override("separation", 10)
	bottom_bar.add_child(legend_box)

	legend_box.add_child(_create_legend_badge("🟦 MAX (AI/NPC)", Color(0.2, 0.7, 0.95)))
	legend_box.add_child(_create_legend_badge("🟧 MIN (Player)", Color(0.95, 0.55, 0.2)))
	legend_box.add_child(_create_legend_badge("★ Best Move", Color(1.0, 0.85, 0.25)))
	legend_box.add_child(_create_legend_badge("✂️ Cutoff", Color(0.9, 0.35, 0.35)))

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(sp2)

	lbl_stats_summary = Label.new()
	lbl_stats_summary.text = "Nodes: 0 | Pruned: 0 | Waktu: 0 ms"
	lbl_stats_summary.add_theme_font_size_override("font_size", 12)
	lbl_stats_summary.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	bottom_bar.add_child(lbl_stats_summary)

	# 6. Floating Node Inspector
	_build_inspector()


func _build_inspector() -> void:
	inspector_panel = PanelContainer.new()
	inspector_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	inspector_panel.offset_left = 16.0
	inspector_panel.offset_bottom = -16.0
	inspector_panel.offset_top = -166.0
	inspector_panel.offset_right = 516.0
	inspector_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inspector_panel.grow_horizontal = Control.GROW_DIRECTION_END
	inspector_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	inspector_panel.visible = false

	var insp_sb := StyleBoxFlat.new()
	insp_sb.bg_color = Color(0.04, 0.06, 0.10, 0.88)
	insp_sb.border_color = Color(0.3, 0.65, 0.85, 0.8)
	insp_sb.set_border_width_all(1)
	insp_sb.set_corner_radius_all(8)
	insp_sb.set_content_margin_all(10)
	inspector_panel.add_theme_stylebox_override("panel", insp_sb)

	var ivbox := VBoxContainer.new()
	ivbox.add_theme_constant_override("separation", 4)
	inspector_panel.add_child(ivbox)

	var ititle := Label.new()
	ititle.text = "🔍 INSPECTOR NODE (Arahkan Mouse ke Node)"
	ititle.add_theme_font_size_override("font_size", 11)
	ititle.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	if font_bold: ititle.add_theme_font_override("font", font_bold)
	ivbox.add_child(ititle)

	inspector_label = RichTextLabel.new()
	inspector_label.bbcode_enabled = true
	inspector_label.fit_content = true
	inspector_label.text = "[color=#8899aa]Arahkan kursor atau klik salah satu node di pohon untuk melihat evaluasi skor, nilai Alpha/Beta, dan status cutoff.[/color]"
	inspector_label.add_theme_font_size_override("normal_font_size", 11)
	ivbox.add_child(inspector_label)

	viewport_area.add_child(inspector_panel)


func _create_toggle_btn(txt: String, is_active: bool) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 11)
	_style_toggle_btn(btn, is_active)
	return btn


func _create_vsep() -> Control:
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(10, 18)
	var line := ColorRect.new()
	line.color = Color(0.25, 0.35, 0.48, 0.5)
	line.custom_minimum_size = Vector2(1, 14)
	line.set_anchors_preset(Control.PRESET_CENTER)
	line.offset_left = -0.5
	line.offset_right = 0.5
	line.offset_top = -7.0
	line.offset_bottom = 7.0
	sep.add_child(line)
	return sep


func _style_toggle_btn(btn: Button, is_active: bool) -> void:
	var sb := StyleBoxFlat.new()
	if is_active:
		sb.bg_color = Color(0.15, 0.5, 0.7, 1.0)
		sb.border_color = Color(0.4, 0.9, 1.0, 1.0)
	else:
		sb.bg_color = Color(0.12, 0.16, 0.22, 0.85)
		sb.border_color = Color(0.25, 0.32, 0.42, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", sb)


func _create_legend_badge(txt: String, col: Color) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.color = col
	hbox.add_child(dot)

	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	hbox.add_child(lbl)

	return hbox


func _set_view_mode(mode: int) -> void:
	if current_view_mode == mode:
		return
	current_view_mode = mode
	_update_view_mode_buttons()
	if not tree_root.is_empty():
		_calculate_tree_layout(tree_root)
		reset_view()


func _update_view_mode_buttons() -> void:
	if btn_mode_simplified:
		_style_toggle_btn(btn_mode_simplified, current_view_mode == ViewMode.SIMPLIFIED)
	if btn_mode_detailed:
		_style_toggle_btn(btn_mode_detailed, current_view_mode == ViewMode.DETAILED)


# ══════════════════════════════════════════════════════════════════════
#  PUBLIC OPEN / CLOSE & STATE HOOK
# ══════════════════════════════════════════════════════════════════════

func open_with_state(
	p_state: StateScript,
	p_ai: AIScript,
	p_algo: int = AIScript.Algorithm.ALPHABETA,
	p_depth: int = 3,
	p_eval: int = AIScript.EvalType.BALANCED,
	p_ordering: int = AIScript.MoveOrdering.OPTIMAL,
	p_leader: String = "Pawn"
) -> void:
	source_state = p_state
	ai_engine = p_ai
	current_leader = p_leader

	# Algoritma konsisten dengan leader: Pawn -> Minimax, Archer -> Alpha-Beta
	if current_leader.to_lower().contains("archer"):
		view_algo = AIScript.Algorithm.ALPHABETA
	else:
		view_algo = AIScript.Algorithm.MINIMAX

	view_depth = clampi(p_depth, 1, 4)
	view_eval = p_eval
	view_ordering = p_ordering

	_update_algo_display()
	_update_view_mode_buttons()
	_update_depth_buttons()
	_rebuild_tree()
	reset_view()

	visible = true
	modulate.a = 0.0
	hovered_node = {}
	if inspector_panel:
		inspector_panel.visible = false
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _update_algo_display() -> void:
	if not lbl_algo_display:
		return
	if view_algo == AIScript.Algorithm.ALPHABETA:
		lbl_algo_display.text = "⚡ Alpha-Beta Pruning (Leader: Archer)"
		lbl_algo_display.add_theme_color_override("font_color", Color(0.35, 0.95, 0.85))
	else:
		lbl_algo_display.text = "🔍 Minimax (Leader: Pawn)"
		lbl_algo_display.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))


func close_visualizer() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): visible = false)


func toggle_visualizer(p_state: StateScript, p_ai: AIScript, p_algo: int, p_depth: int, p_leader: String = "Pawn") -> void:
	if visible:
		close_visualizer()
	else:
		open_with_state(p_state, p_ai, p_algo, p_depth, AIScript.EvalType.BALANCED, AIScript.MoveOrdering.OPTIMAL, p_leader)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_visualizer()
			get_viewport().set_input_as_handled()


# ══════════════════════════════════════════════════════════════════════
#  TREE GENERATION & MINIMAX SEARCH SIMULATION
# ══════════════════════════════════════════════════════════════════════

func _rebuild_tree() -> void:
	if not source_state or not ai_engine:
		return

	_node_counter = 0
	var start_usec := Time.get_ticks_usec()
	var root_clone = source_state.clone()
	var is_root_max: bool = (root_clone.current_turn == StateScript.Side.ENEMY)

	if lbl_turn_state and source_state:
		var turn_side_str := "Giliran Player" if source_state.current_turn == StateScript.Side.PLAYER else "Giliran NPC"
		lbl_turn_state.text = "📍 Turn %d: %s" % [source_state.turn_count + 1, turn_side_str]
		var col := Color(0.35, 0.95, 0.85) if source_state.current_turn == StateScript.Side.PLAYER else Color(1.0, 0.65, 0.3)
		lbl_turn_state.add_theme_color_override("font_color", col)

	tree_root = {
		"id": 0,
		"name": "START",
		"action": -1,
		"depth": 0,
		"is_max": is_root_max,
		"score": 0.0,
		"alpha": -INF,
		"beta": INF,
		"is_pruned": false,
		"is_best": false,
		"is_terminal": root_clone.is_terminal(),
		"winner": root_clone.get_winner(),
		"player_hp": root_clone.player["hp"],
		"player_stm": root_clone.player["stamina"],
		"enemy_hp": root_clone.enemy["hp"],
		"enemy_stm": root_clone.enemy["stamina"],
		"children": []
	}

	var stats := {"expanded": 0, "pruned": 0}
	_expand_tree_node(
		tree_root,
		root_clone,
		view_depth,
		-INF,
		INF,
		is_root_max,
		StateScript.Side.ENEMY,
		stats
	)

	_mark_best_path(tree_root)
	_calculate_tree_layout(tree_root)

	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	if lbl_stats_summary:
		lbl_stats_summary.text = "Nodes: %d | Pruned Cutoffs: %d | Waktu: %.2f ms" % [
			stats["expanded"], stats["pruned"], elapsed_ms
		]

	if tree_draw_canvas:
		tree_draw_canvas.queue_redraw()


func _expand_tree_node(
	node: Dictionary,
	current_state: StateScript,
	remaining_depth: int,
	alpha: float,
	beta: float,
	is_max: bool,
	piece: int,
	stats: Dictionary
) -> float:
	stats["expanded"] += 1
	node["is_max"] = is_max
	node["alpha"] = alpha
	node["beta"] = beta

	# Base cases: terminal state or depth reached
	if current_state.is_terminal():
		var winner := current_state.get_winner()
		var term_score: float = 0.0
		if winner == piece:
			term_score = AIScript.WIN_SCORE + float(remaining_depth)
		elif winner != -1:
			term_score = -(AIScript.WIN_SCORE + float(remaining_depth))
		node["score"] = term_score
		node["is_terminal"] = true
		node["winner"] = winner
		return term_score

	if remaining_depth <= 0:
		var eval_score: float = ai_engine.evaluate(current_state, piece, view_eval)
		node["score"] = eval_score
		return eval_score

	var valid_actions = current_state.get_valid_actions()
	if valid_actions.is_empty():
		var eval_score: float = ai_engine.evaluate(current_state, piece, view_eval)
		node["score"] = eval_score
		return eval_score

	var ordered_actions = ai_engine.order_actions(current_state, valid_actions, is_max, piece, view_ordering)

	var best_score: float = -INF if is_max else INF
	var cur_alpha: float = alpha
	var cur_beta: float = beta
	var was_cutoff: bool = false

	for act in ordered_actions:
		_node_counter += 1
		var child_state = current_state.clone()
		child_state.apply_action(act, false)

		var child_node := {
			"id": _node_counter,
			"name": StateScript.get_action_name(act),
			"action": act,
			"depth": node["depth"] + 1,
			"is_max": not is_max,
			"score": 0.0,
			"alpha": cur_alpha,
			"beta": cur_beta,
			"is_pruned": was_cutoff,
			"is_best": false,
			"is_terminal": child_state.is_terminal(),
			"winner": child_state.get_winner(),
			"player_hp": child_state.player["hp"],
			"player_stm": child_state.player["stamina"],
			"enemy_hp": child_state.enemy["hp"],
			"enemy_stm": child_state.enemy["stamina"],
			"children": []
		}
		node["children"].append(child_node)

		if was_cutoff:
			stats["pruned"] += 1
			continue

		var child_score := _expand_tree_node(
			child_node,
			child_state,
			remaining_depth - 1,
			cur_alpha,
			cur_beta,
			not is_max,
			piece,
			stats
		)

		if is_max:
			if child_score > best_score:
				best_score = child_score
			if view_algo == AIScript.Algorithm.ALPHABETA:
				cur_alpha = maxf(cur_alpha, best_score)
				if cur_alpha >= cur_beta:
					was_cutoff = true
		else:
			if child_score < best_score:
				best_score = child_score
			if view_algo == AIScript.Algorithm.ALPHABETA:
				cur_beta = minf(cur_beta, best_score)
				if cur_alpha >= cur_beta:
					was_cutoff = true

	node["score"] = best_score
	node["alpha"] = cur_alpha
	node["beta"] = cur_beta
	return best_score


func _mark_best_path(node: Dictionary) -> void:
	node["is_best"] = true
	var children: Array = node.get("children", [])
	if children.is_empty():
		return

	var target_score: float = node["score"]
	var best_child: Dictionary = {}

	for child in children:
		if not child.get("is_pruned", false) and is_equal_approx(child.get("score", 0.0), target_score):
			best_child = child
			break

	if not best_child.is_empty():
		_mark_best_path(best_child)


# ══════════════════════════════════════════════════════════════════════
#  TREE LAYOUT ALGORITHM (Non-overlapping Subtree Widths)
# ══════════════════════════════════════════════════════════════════════

func _calculate_tree_layout(node: Dictionary) -> void:
	_calc_subtree_width(node)
	_assign_tree_positions(node, 0.0, 30.0)


func _calc_subtree_width(node: Dictionary) -> float:
	var nw := get_node_w()
	var hgap := get_h_gap()
	var children: Array = node.get("children", [])
	if children.is_empty():
		node["width"] = nw + hgap
		return node["width"]

	var total_w: float = 0.0
	for child in children:
		total_w += _calc_subtree_width(child)
	node["width"] = maxf(total_w, nw + hgap)
	return node["width"]


func _assign_tree_positions(node: Dictionary, cur_x: float, cur_y: float) -> void:
	node["pos_y"] = cur_y
	var nw := get_node_w()
	var nh := get_node_h()
	var vgap := get_v_gap()

	var children: Array = node.get("children", [])
	if children.is_empty():
		node["pos_x"] = cur_x + (node["width"] - nw) * 0.5
		return

	var child_x := cur_x
	for child in children:
		_assign_tree_positions(child, child_x, cur_y + nh + vgap)
		child_x += child["width"]

	var first_child: Dictionary = children[0]
	var last_child: Dictionary = children[children.size() - 1]
	node["pos_x"] = (first_child["pos_x"] + last_child["pos_x"]) * 0.5


# ══════════════════════════════════════════════════════════════════════
#  INTERACTIVE PAN, DRAG & ZOOM HANDLING
# ══════════════════════════════════════════════════════════════════════

func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()

		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				is_dragging = true
				drag_start = event.position
				pan_start = pan_offset
				if viewport_area:
					viewport_area.mouse_default_cursor_shape = Control.CURSOR_DRAG
			else:
				is_dragging = false
				if viewport_area:
					viewport_area.mouse_default_cursor_shape = Control.CURSOR_MOVE

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)

	elif event is InputEventMouseMotion:
		if is_dragging:
			pan_offset = pan_start + (event.position - drag_start)
			_queue_tree_redraw()
		else:
			var hit = _get_node_at_screen_pos(event.position)
			if hit != hovered_node:
				hovered_node = hit
				if not hovered_node.is_empty():
					if inspector_panel:
						inspector_panel.visible = true
						_update_inspector(hovered_node)
				else:
					if inspector_panel:
						inspector_panel.visible = false
				_queue_tree_redraw()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old_zoom := zoom
	zoom = clampf(zoom * factor, 0.20, 3.5)
	var world_pos := (screen_pos - pan_offset) / old_zoom
	pan_offset = screen_pos - world_pos * zoom

	if lbl_zoom_val:
		lbl_zoom_val.text = "%d%%" % int(zoom * 100.0)
	_queue_tree_redraw()


func reset_view() -> void:
	zoom = 1.0
	hovered_node = {}
	if inspector_panel:
		inspector_panel.visible = false
	if lbl_zoom_val:
		lbl_zoom_val.text = "100%"

	if viewport_area and not tree_root.is_empty():
		var vp_w := viewport_area.size.x if viewport_area.size.x > 0 else 1200.0
		var nw := get_node_w()
		var root_x: float = tree_root.get("pos_x", 0.0) + nw * 0.5
		pan_offset = Vector2(vp_w * 0.5 - root_x, 30.0)
	else:
		pan_offset = Vector2(400.0, 30.0)

	_queue_tree_redraw()


func go_to_best() -> void:
	if tree_root.is_empty():
		return
	var best_target: Dictionary = {}
	for child in tree_root.get("children", []):
		if child.get("is_best", false):
			best_target = child
			break
	if best_target.is_empty():
		best_target = _find_best_node_recursive(tree_root)
	if best_target.is_empty():
		best_target = tree_root

	var nw := get_node_w()
	var nh := get_node_h()
	var target_world_pos := Vector2(best_target.get("pos_x", 0.0) + nw * 0.5, best_target.get("pos_y", 0.0) + nh * 0.5)

	var vp_size := viewport_area.size if viewport_area and viewport_area.size.x > 0 else Vector2(1200, 600)
	var target_pan := vp_size * 0.5 - target_world_pos * zoom

	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()

	var start_pan := pan_offset
	_cam_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cam_tween.tween_method(func(val: Vector2):
		pan_offset = val
		_queue_tree_redraw()
	, start_pan, target_pan, 0.55)


func _find_best_node_recursive(node: Dictionary) -> Dictionary:
	for child in node.get("children", []):
		if child.get("is_best", false):
			return child
		var res := _find_best_node_recursive(child)
		if not res.is_empty():
			return res
	return {}


func _queue_tree_redraw() -> void:
	if tree_draw_canvas:
		tree_draw_canvas.queue_redraw()


func _get_node_at_screen_pos(screen_pos: Vector2) -> Dictionary:
	var world_pos := (screen_pos - pan_offset) / zoom
	return _find_node_at_world_pos(tree_root, world_pos)


func _find_node_at_world_pos(node: Dictionary, world_pos: Vector2) -> Dictionary:
	if node.is_empty():
		return {}
	var rect := Rect2(node.get("pos_x", 0.0), node.get("pos_y", 0.0), get_node_w(), get_node_h())
	if rect.has_point(world_pos):
		return node
	for child in node.get("children", []):
		var hit = _find_node_at_world_pos(child, world_pos)
		if not hit.is_empty():
			return hit
	return {}


# ══════════════════════════════════════════════════════════════════════
#  ACTION ICON RESOLVER
# ══════════════════════════════════════════════════════════════════════

func _get_action_icon(action: int) -> Texture2D:
	match action:
		StateScript.Action.ATTACK:
			return ICON_ATTACK
		StateScript.Action.HEAVY_ATTACK:
			return ICON_SPECIAL
		StateScript.Action.DEFEND:
			return ICON_DEFENSE
		StateScript.Action.REST:
			return ICON_ITEM
	if current_leader.to_lower().contains("archer"):
		return ICON_AVATAR_ARCHER
	return ICON_AVATAR_PAWN


# ══════════════════════════════════════════════════════════════════════
#  CUSTOM CANVAS DRAWING (_draw)
# ══════════════════════════════════════════════════════════════════════

func _on_draw_tree() -> void:
	if not tree_draw_canvas or tree_root.is_empty():
		return

	# 1. Draw connection branches
	_draw_branches_recursive(tree_root)

	# 2. Draw nodes (Simplified or Detailed)
	_draw_nodes_recursive(tree_root)

	# 3. Floating Hover Tooltip Card (Khusus Simplified mode saat kursor berada di atas node)
	if current_view_mode == ViewMode.SIMPLIFIED and not hovered_node.is_empty():
		_draw_simplified_hover_tooltip(hovered_node)


func _draw_branches_recursive(node: Dictionary) -> void:
	var children: Array = node.get("children", [])
	if children.is_empty():
		return

	var nw := get_node_w()
	var nh := get_node_h()

	var parent_pt := pan_offset + Vector2(node["pos_x"] + nw * 0.5, node["pos_y"] + nh) * zoom

	for child in children:
		var child_pt := pan_offset + Vector2(child["pos_x"] + nw * 0.5, child["pos_y"]) * zoom
		var is_best_branch: bool = node.get("is_best", false) and child.get("is_best", false)
		var is_pruned: bool = child.get("is_pruned", false)

		var col: Color = Color(0.35, 0.45, 0.6, 0.6)
		var line_w: float = 2.0 * zoom

		if is_best_branch:
			col = Color(1.0, 0.85, 0.25, 0.95)
			line_w = 3.5 * zoom
		elif is_pruned:
			col = Color(0.85, 0.3, 0.3, 0.45)
			line_w = 1.5 * zoom

		var mid_y: float = (parent_pt.y + child_pt.y) * 0.5
		var p1 := parent_pt
		var p2 := Vector2(parent_pt.x, mid_y)
		var p3 := Vector2(child_pt.x, mid_y)
		var p4 := child_pt

		tree_draw_canvas.draw_line(p1, p2, col, line_w, true)
		tree_draw_canvas.draw_line(p2, p3, col, line_w, true)
		tree_draw_canvas.draw_line(p3, p4, col, line_w, true)

		# Pruned badge on branch
		if is_pruned and zoom >= 0.5:
			var cut_pos := (p2 + p3) * 0.5
			tree_draw_canvas.draw_string(
				font_bold if font_bold else ThemeDB.fallback_font,
				cut_pos + Vector2(-24, -4),
				"✂️ CUT",
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				clampi(int(9 * zoom), 7, 12),
				Color(1.0, 0.4, 0.4, 0.9)
			)

		_draw_branches_recursive(child)


func _draw_nodes_recursive(node: Dictionary) -> void:
	if current_view_mode == ViewMode.SIMPLIFIED:
		_draw_node_simplified(node)
	else:
		_draw_node_detailed(node)

	for child in node.get("children", []):
		_draw_nodes_recursive(child)


# ── Detailed Mode Node Drawing ─────────────────────────────────────────

func _draw_node_detailed(node: Dictionary) -> void:
	var nw := get_node_w()
	var nh := get_node_h()
	var screen_pos := pan_offset + Vector2(node["pos_x"], node["pos_y"]) * zoom
	var node_sz := Vector2(nw, nh) * zoom
	var rect := Rect2(screen_pos, node_sz)

	var is_hovered := (node == hovered_node)
	var is_best: bool = node.get("is_best", false)
	var is_pruned: bool = node.get("is_pruned", false)
	var is_max: bool = node.get("is_max", true)
	var is_root: bool = (node.get("depth", 0) == 0)

	# 1. Background color
	var bg_col := Color(0.08, 0.14, 0.22, 0.95) if is_max else Color(0.24, 0.12, 0.08, 0.95)
	if is_root:
		bg_col = Color(0.18, 0.12, 0.28, 0.95)
	if is_pruned:
		bg_col = Color(0.14, 0.14, 0.16, 0.75)

	# 2. Border color
	var border_col := Color(0.3, 0.5, 0.75, 0.8)
	var border_w: float = 1.5 * zoom
	if is_best:
		border_col = Color(1.0, 0.85, 0.25, 1.0)
		border_w = 3.0 * zoom
	elif is_hovered:
		border_col = Color(1.0, 1.0, 1.0, 1.0)
		border_w = 2.8 * zoom
	elif is_pruned:
		border_col = Color(0.85, 0.3, 0.3, 0.6)

	tree_draw_canvas.draw_rect(rect, bg_col, true)
	tree_draw_canvas.draw_rect(rect, border_col, false, border_w)

	# Header Pill Banner inside node
	var header_h: float = 24.0 * zoom
	var header_rect := Rect2(screen_pos, Vector2(node_sz.x, header_h))
	var pill_col := Color(0.15, 0.45, 0.7, 0.9) if is_max else Color(0.7, 0.35, 0.1, 0.9)
	if is_root: pill_col = Color(0.35, 0.2, 0.55, 0.9)
	if is_pruned: pill_col = Color(0.25, 0.25, 0.28, 0.8)
	tree_draw_canvas.draw_rect(header_rect, pill_col, true)

	var f := font_bold if font_bold else ThemeDB.fallback_font
	var fm := font_medium if font_medium else f

	# Header Text: [MAX / MIN] + Action
	if zoom >= 0.35:
		var type_tag := "MAX" if is_max else "MIN"
		if is_root: type_tag = "ROOT"
		var act_name: String = node.get("name", "").to_upper()
		var header_txt: String = "[%s] %s" % [type_tag, act_name]
		var f_sz_h: int = clampi(int(13 * zoom), 9, 18)
		tree_draw_canvas.draw_string(
			f,
			screen_pos + Vector2(7 * zoom, 17 * zoom),
			header_txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(node_sz.x - 14 * zoom),
			f_sz_h,
			Color.WHITE
		)

	# Draw Move Icon on the left body
	var icon := _get_action_icon(node.get("action", -1))
	var icon_sz := 54.0 * zoom
	var icon_pos := screen_pos + Vector2(7 * zoom, 29 * zoom)
	var icon_rect := Rect2(icon_pos, Vector2(icon_sz, icon_sz))

	if icon:
		var icon_modulate := Color(1.0, 1.0, 1.0, 0.95)
		if is_pruned:
			icon_modulate = Color(0.8, 0.4, 0.4, 0.45)
		tree_draw_canvas.draw_texture_rect(icon, icon_rect, false, icon_modulate)

	# Texts on the right side of the icon
	if zoom >= 0.38:
		var text_x := screen_pos.x + 68.0 * zoom
		var f_sz_b: int = clampi(int(12 * zoom), 8, 16)

		# Line 1: Score / Pruned tag
		var score_txt: String = ""
		var score_col := Color(0.9, 0.95, 1.0)
		if is_pruned:
			score_txt = "✂️ CUTOFF (α≥β)"
			score_col = Color(1.0, 0.45, 0.45)
		else:
			var sc: float = node.get("score", 0.0)
			if sc >= AIScript.WIN_SCORE * 0.5:
				score_txt = "👑 MENANG"
				score_col = Color(0.3, 1.0, 0.5)
			elif sc <= -AIScript.WIN_SCORE * 0.5:
				score_txt = "💀 KALAH"
				score_col = Color(1.0, 0.35, 0.35)
			else:
				score_txt = "Skor: %+5.1f" % sc
				score_col = Color(0.35, 0.95, 0.6) if sc > 0 else (Color(1.0, 0.4, 0.4) if sc < 0 else Color(0.9, 0.9, 0.9))

		tree_draw_canvas.draw_string(
			f,
			Vector2(text_x, screen_pos.y + 46 * zoom),
			score_txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(node_sz.x - 72 * zoom),
			clampi(int(13 * zoom), 9, 17),
			score_col
		)

		# Line 2: Snapshot HP
		var snap_txt: String = "AI:%d | PL:%d" % [node.get("enemy_hp", 0), node.get("player_hp", 0)]
		tree_draw_canvas.draw_string(
			fm,
			Vector2(text_x, screen_pos.y + 66 * zoom),
			snap_txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(node_sz.x - 72 * zoom),
			f_sz_b,
			Color(0.7, 0.8, 0.9)
		)

		# Line 3: Alpha / Beta interval
		var a_val = node.get("alpha", -INF)
		var b_val = node.get("beta", INF)
		var a_str: String = "-∞" if a_val == -INF else "%+.0f" % a_val
		var b_str: String = "+∞" if b_val == INF else "%+.0f" % b_val
		var ab_txt: String = "α:%s β:%s" % [a_str, b_str]
		tree_draw_canvas.draw_string(
			fm,
			Vector2(text_x, screen_pos.y + 86 * zoom),
			ab_txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(node_sz.x - 72 * zoom),
			f_sz_b,
			Color(0.85, 0.75, 0.45)
		)


# ── Simplified Mode Node Drawing (Compact Move Icons) ──────────────────

func _draw_node_simplified(node: Dictionary) -> void:
	var nw := get_node_w()
	var nh := get_node_h()
	var screen_pos := pan_offset + Vector2(node["pos_x"], node["pos_y"]) * zoom
	var node_sz := Vector2(nw, nh) * zoom
	var rect := Rect2(screen_pos, node_sz)

	var is_hovered := (node == hovered_node)
	var is_best: bool = node.get("is_best", false)
	var is_pruned: bool = node.get("is_pruned", false)
	var is_max: bool = node.get("is_max", true)
	var is_root: bool = (node.get("depth", 0) == 0)

	# 1. Background
	var bg_col := Color(0.08, 0.14, 0.22, 0.95) if is_max else Color(0.24, 0.12, 0.08, 0.95)
	if is_root: bg_col = Color(0.2, 0.12, 0.32, 0.95)
	if is_pruned: bg_col = Color(0.12, 0.12, 0.14, 0.8)

	# 2. Border
	var border_col := Color(0.25, 0.45, 0.65, 0.8)
	var border_w: float = 1.5 * zoom
	if is_best:
		border_col = Color(1.0, 0.85, 0.25, 1.0)
		border_w = 3.0 * zoom
	elif is_hovered:
		border_col = Color(1.0, 1.0, 1.0, 1.0)
		border_w = 2.8 * zoom
	elif is_pruned:
		border_col = Color(0.85, 0.3, 0.3, 0.6)

	tree_draw_canvas.draw_rect(rect, bg_col, true)
	tree_draw_canvas.draw_rect(rect, border_col, false, border_w)

	# Top Indicator Strip
	var strip_h := 6.0 * zoom
	var strip_col := Color(0.2, 0.7, 1.0) if is_max else Color(1.0, 0.55, 0.2)
	if is_root: strip_col = Color(0.65, 0.35, 0.95)
	if is_pruned: strip_col = Color(0.35, 0.35, 0.38)
	tree_draw_canvas.draw_rect(Rect2(screen_pos, Vector2(node_sz.x, strip_h)), strip_col, true)

	# Center Action Icon
	var icon := _get_action_icon(node.get("action", -1))
	var icon_sz := 44.0 * zoom
	var icon_pos := screen_pos + Vector2(10 * zoom, 10 * zoom)
	var icon_rect := Rect2(icon_pos, Vector2(icon_sz, icon_sz))

	if icon:
		var icon_mod := Color(1.0, 1.0, 1.0, 0.95)
		if is_pruned:
			icon_mod = Color(0.8, 0.35, 0.35, 0.4)
		tree_draw_canvas.draw_texture_rect(icon, icon_rect, false, icon_mod)

	# Pruned scissor badge in corner
	if is_pruned:
		tree_draw_canvas.draw_rect(icon_rect, Color(0.2, 0.05, 0.05, 0.45), true)
		if zoom >= 0.50:
			var f := font_bold if font_bold else ThemeDB.fallback_font
			tree_draw_canvas.draw_string(
				f,
				screen_pos + Vector2(4 * zoom, node_sz.y - 4 * zoom),
				"✂",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				clampi(int(12 * zoom), 9, 16),
				Color(1.0, 0.35, 0.35)
			)

	# Tiny score indicator at bottom if zoom allows
	if zoom >= 0.55 and not is_pruned and not is_root:
		var f := font_bold if font_bold else ThemeDB.fallback_font
		var sc: float = node.get("score", 0.0)
		var sc_str := "%+.0f" % sc
		var sc_col := Color(0.35, 0.95, 0.6) if sc > 0 else (Color(1.0, 0.4, 0.4) if sc < 0 else Color(0.8, 0.8, 0.8))
		tree_draw_canvas.draw_string(
			f,
			screen_pos + Vector2(2 * zoom, node_sz.y - 3 * zoom),
			sc_str,
			HORIZONTAL_ALIGNMENT_CENTER,
			int(node_sz.x - 4 * zoom),
			clampi(int(11 * zoom), 8, 15),
			sc_col
		)


# ── Floating Hover Tooltip (Simplified Mode) ───────────────────────────

func _draw_simplified_hover_tooltip(node: Dictionary) -> void:
	var nw := get_node_w()
	var screen_pos := pan_offset + Vector2(node["pos_x"], node["pos_y"]) * zoom
	var node_sz := Vector2(nw, get_node_h()) * zoom

	# Tooltip dimensions
	var tt_w: float = 260.0
	var tt_h: float = 125.0
	var tt_pos := screen_pos + Vector2(node_sz.x + 12.0, -10.0)

	# Clamp inside viewport
	if viewport_area:
		if tt_pos.x + tt_w > viewport_area.size.x - 10.0:
			tt_pos.x = screen_pos.x - tt_w - 12.0
		if tt_pos.y + tt_h > viewport_area.size.y - 10.0:
			tt_pos.y = viewport_area.size.y - tt_h - 10.0
		if tt_pos.y < 10.0:
			tt_pos.y = 10.0

	var tt_rect := Rect2(tt_pos, Vector2(tt_w, tt_h))

	# Card Background & Border
	tree_draw_canvas.draw_rect(tt_rect, Color(0.04, 0.06, 0.10, 0.96), true)
	var tb_col := Color(0.25, 0.75, 0.95, 0.95)
	if node.get("is_best", false):
		tb_col = Color(1.0, 0.85, 0.25, 1.0)
	elif node.get("is_pruned", false):
		tb_col = Color(0.9, 0.35, 0.35, 0.9)
	tree_draw_canvas.draw_rect(tt_rect, tb_col, false, 2.0)

	# Move icon inside tooltip
	var icon := _get_action_icon(node.get("action", -1))
	if icon:
		var ic_rect := Rect2(tt_pos + Vector2(8, 8), Vector2(40, 40))
		tree_draw_canvas.draw_texture_rect(icon, ic_rect, false, Color.WHITE)

	var f := font_bold if font_bold else ThemeDB.fallback_font
	var fm := font_medium if font_medium else f

	var is_max: bool = node.get("is_max", true)
	var is_root: bool = (node.get("depth", 0) == 0)
	var type_str := "ROOT" if is_root else ("MAX (AI)" if is_max else "MIN (Player)")
	var act_name: String = node.get("name", "ACTION").to_upper()

	# Title Line
	tree_draw_canvas.draw_string(
		f,
		tt_pos + Vector2(54, 22),
		"%s: %s" % [type_str, act_name],
		HORIZONTAL_ALIGNMENT_LEFT,
		int(tt_w - 60),
		13,
		Color(0.3, 0.95, 1.0) if is_max else Color(1.0, 0.65, 0.3)
	)

	# Best Move Badge
	if node.get("is_best", false):
		tree_draw_canvas.draw_string(
			f,
			tt_pos + Vector2(54, 38),
			"★ BEST MOVE",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(1.0, 0.85, 0.25)
		)

	# Divider line
	tree_draw_canvas.draw_line(
		tt_pos + Vector2(8, 52),
		tt_pos + Vector2(tt_w - 8, 52),
		Color(0.2, 0.3, 0.45, 0.8),
		1.0
	)

	# Metrics Details
	var sc: float = node.get("score", 0.0)
	var sc_str := "Skor: %+6.1f" % sc
	if node.get("is_pruned", false):
		sc_str = "✂️ CUTOFF (α ≥ β)"
	tree_draw_canvas.draw_string(
		fm,
		tt_pos + Vector2(10, 70),
		sc_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1.0, 0.45, 0.45) if node.get("is_pruned", false) else Color(0.35, 1.0, 0.6)
	)

	# HP Snapshot
	tree_draw_canvas.draw_string(
		fm,
		tt_pos + Vector2(10, 88),
		"AI: %d HP • PL: %d HP" % [node.get("enemy_hp", 0), node.get("player_hp", 0)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color(0.8, 0.85, 0.95)
	)

	# Alpha Beta Range
	var a_val = node.get("alpha", -INF)
	var b_val = node.get("beta", INF)
	var a_str: String = "-∞" if a_val == -INF else "%+.0f" % a_val
	var b_str: String = "+∞" if b_val == INF else "%+.0f" % b_val
	tree_draw_canvas.draw_string(
		fm,
		tt_pos + Vector2(10, 106),
		"Alpha: %s  |  Beta: %s" % [a_str, b_str],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color(0.9, 0.8, 0.45)
	)


# ══════════════════════════════════════════════════════════════════════
#  INSPECTOR EXPLANATION (Human-readable educational guide)
# ══════════════════════════════════════════════════════════════════════

func _update_inspector(node: Dictionary, is_pinned: bool = false) -> void:
	if not inspector_label:
		return
	if node.is_empty():
		inspector_label.text = "[color=#8899aa]Arahkan kursor atau klik salah satu node di pohon untuk melihat evaluasi skor, nilai Alpha/Beta, dan status cutoff.[/color]"
		return

	var depth: int = node.get("depth", 0)
	var is_max: bool = node.get("is_max", true)
	var is_pruned: bool = node.get("is_pruned", false)
	var is_best: bool = node.get("is_best", false)
	var act_name: String = node.get("name", "ROOT")
	var sc: float = node.get("score", 0.0)
	var a_val = node.get("alpha", -INF)
	var b_val = node.get("beta", INF)
	var a_str: String = "-∞" if a_val == -INF else "%+.1f" % a_val
	var b_str: String = "+∞" if b_val == INF else "%+.1f" % b_val

	var bb := ""
	var tag_col := "#33bbee" if is_max else "#ff8833"
	var type_name := "MAX (AI/Enemy)" if is_max else "MIN (Player)"
	bb += "[b][color=%s]Depth %d • %s — Aksi: %s[/color][/b]" % [tag_col, depth, type_name, act_name]
	if is_best:
		bb += " [color=#f4d03f]★ BEST MOVE[/color]"
	bb += "\n"

	bb += "[color=#dddddd]State:[/color] AI HP [color=#ff7766]%d[/color], STM [color=#55ccff]%d[/color]  |  Player HP [color=#ff7766]%d[/color], STM [color=#55ccff]%d[/color]\n" % [
		node.get("enemy_hp", 0), node.get("enemy_stm", 0),
		node.get("player_hp", 0), node.get("player_stm", 0)
	]

	bb += "[color=#dddddd]Skor Minimax:[/color] [b]%+.2f[/b]   |   [color=#f4d03f]α (Best MAX):[/color] %s   |   [color=#f4d03f]β (Best MIN):[/color] %s\n" % [
		sc, a_str, b_str
	]

	if is_pruned:
		bb += "[color=#ff5555][b]✂️ STATUS: DIPRUNE / CUTOFF![/b] Cabang ini tidak dievaluasi lebih lanjut karena α ≥ β (%s ≥ %s). Lawan dipastikan tidak akan memilih cabang ini, menghemat iterasi pencarian.[/color]" % [a_str, b_str]
	elif is_max:
		bb += "[color=#88ccff]• Logika MAX: AI mencari nilai evaluasi [b]tertinggi[/b] dari semua kemungkinan cabang anaknya.[/color]"
	else:
		bb += "[color=#ffaa77]• Logika MIN: AI memprediksi player akan memilih balasan dengan nilai [b]terendah[/b] bagi AI.[/color]"

	inspector_label.text = bb


func _update_depth_buttons() -> void:
	for d in btn_depth_buttons.keys():
		var btn: Button = btn_depth_buttons[d]
		_style_toggle_btn(btn, d == view_depth)
