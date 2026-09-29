class_name BattleStageController
extends Node2D

## Battle Stage Controller (New Battle Stage)
## Mengimplementasikan visual & layout sesuai Penerapan UI.png mockup:
## - Background Cave Theme (Background1.png)
## - Allies di kiri facing right (Player Archer/Pawn + Follower Companion)
## - Enemy di kanan facing left (FallenOrder - SeveredFang dengan animasi Idle, Attack, Hurt, Death)
## - Name Badges (Ally Name, Enemy Name)
## - HP & Stamina Bars interaktif
## - Turn Order Tracker di pojok kiri atas
## - 4 Hexagonal Action Buttons (Special, Attack, Item, Defense) di pojok kanan bawah
## - Debug Overlay di pojok kanan atas terintegrasi dengan TempBattleAI & TempBattleState

const StateScript = preload("res://Temp_Battle/temp_battle_state.gd")
const AIScript = preload("res://Temp_Battle/temp_battle_ai.gd")

# ══════════════════════════════════════════════════════════════════════
#  STATE & AI
# ══════════════════════════════════════════════════════════════════════

var state: StateScript
var ai: AIScript

var current_algo: int = AIScript.Algorithm.ALPHABETA
var current_depth: int = 2
var current_eval: int = AIScript.EvalType.BALANCED
var current_ordering: int = AIScript.MoveOrdering.OPTIMAL

var is_processing_turn: bool = false

# ══════════════════════════════════════════════════════════════════════
#  FONTS & AUDIO
# ══════════════════════════════════════════════════════════════════════

var font_bold: Font = null
var font_regular: Font = null
var sfx_hover: AudioStream = null
var sfx_click: AudioStream = null

# ══════════════════════════════════════════════════════════════════════
#  NODE REFERENCES
# ══════════════════════════════════════════════════════════════════════

var ally_sprite: Node2D
var enemy_sprite: AnimatedSprite2D

# Bars
var ally_hp_bar: TextureProgressBar
var ally_hp_lbl: Label
var ally_stm_bar: TextureProgressBar
var ally_stm_lbl: Label

var enemy_hp_bar: TextureProgressBar
var enemy_hp_lbl: Label
var enemy_stm_bar: TextureProgressBar
var enemy_stm_lbl: Label

# Action Buttons
var btn_special: TextureButton
var btn_attack: TextureButton
var btn_item: TextureButton
var btn_defense: TextureButton

# Debug Overlay Elements
var debug_panel: Control
var debug_toggle_btn: BaseButton
var opt_algorithm: OptionButton
var slider_depth: HSlider
var lbl_depth_val: Label
var opt_eval_type: OptionButton
var opt_move_ordering: OptionButton
var lbl_nodes: Label
var lbl_pruned: Label
var lbl_time: Label
var candidates_container: VBoxContainer

# Turn Tracker
var turn_tracker_container: Control
var active_turn_card: Control
var upcoming_cards_box: VBoxContainer

# Banner / Notification
var banner_label: Label


func _ready() -> void:
	_load_resources()
	state = StateScript.new(100, 100)
	ai = AIScript.new()

	_build_scene_layout()
	_update_ui_state()

	_show_banner("BATTLE START!", Color(0.3, 0.9, 1.0))


func _load_resources() -> void:
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		font_bold = load("res://fonts/PixelifySans-Bold.ttf")
	if ResourceLoader.exists("res://fonts/PixelifySans-Regular.ttf"):
		font_regular = load("res://fonts/PixelifySans-Regular.ttf")

	if ResourceLoader.exists("res://audio/sfx/hover_pop.wav"):
		sfx_hover = load("res://audio/sfx/hover_pop.wav")
	if ResourceLoader.exists("res://audio/sfx/dice_click.wav"):
		sfx_click = load("res://audio/sfx/dice_click.wav")


func _play_sfx(stream: AudioStream) -> void:
	if stream:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Master"
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)


# ══════════════════════════════════════════════════════════════════════
#  SCENE BUILDER (MATCHING PENERAPAN UI.PNG)
# ══════════════════════════════════════════════════════════════════════

func _build_scene_layout() -> void:
	# 1. Background
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.centered = false
	if ResourceLoader.exists("res://assets/Background1.png"):
		bg.texture = load("res://assets/Background1.png")
	add_child(bg)

	# 2. Characters Layer
	_build_characters()

	# 3. CanvasLayer for 1280x720 Pixel-Perfect UI
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	var ui_root := Control.new()
	ui_root.name = "UIRoot"
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)

	# Top Center: Battle Stage Title
	var title_lbl := Label.new()
	title_lbl.text = "Battle Stage"
	title_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_lbl.offset_top = 22.0
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		title_lbl.add_theme_font_override("font", font_bold)
	title_lbl.add_theme_font_size_override("font_size", 34)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.14, 1.0))
	title_lbl.add_theme_constant_override("outline_size", 8)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	title_lbl.add_theme_constant_override("shadow_offset_y", 3)
	ui_root.add_child(title_lbl)

	# Return to Lobby Button (Top-Middle Left)
	var lobby_btn := Button.new()
	lobby_btn.text = "< Return to Lobby"
	lobby_btn.position = Vector2(160, 26)
	lobby_btn.custom_minimum_size = Vector2(140, 32)
	lobby_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font_bold:
		lobby_btn.add_theme_font_override("font", font_bold)
	lobby_btn.add_theme_font_size_override("font_size", 14)
	var sb_btn := StyleBoxFlat.new()
	sb_btn.bg_color = Color(0.1, 0.15, 0.25, 0.85)
	sb_btn.border_color = Color(0.3, 0.7, 0.9, 0.8)
	sb_btn.set_border_width_all(1)
	sb_btn.set_corner_radius_all(6)
	lobby_btn.add_theme_stylebox_override("normal", sb_btn)
	lobby_btn.pressed.connect(func():
		_play_sfx(sfx_click)
		var return_scene := "res://Overworld.tscn"
		if has_node("/root/BattleManager"):
			var bm = get_node("/root/BattleManager")
			if bm.get("_return_scene") and str(bm.get("_return_scene")) != "":
				return_scene = str(bm.get("_return_scene"))
		get_tree().change_scene_to_file(return_scene)
	)
	ui_root.add_child(lobby_btn)

	# Top Left: Turn Order Tracker
	_build_turn_tracker(ui_root)

	# Top Right: Debug Overlay
	_build_debug_overlay(ui_root)

	# Status Badges and Bars (Allies & Enemy)
	_build_status_bars(ui_root)

	# Bottom Right: Persona-style Hexagonal Action Buttons
	_build_action_buttons(ui_root)

	# Banner / Floating Text Root
	banner_label = Label.new()
	banner_label.name = "BannerNotification"
	banner_label.set_anchors_preset(Control.PRESET_CENTER)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.offset_top = -140.0
	banner_label.offset_bottom = -90.0
	banner_label.offset_left = -300.0
	banner_label.offset_right = 300.0
	if font_bold:
		banner_label.add_theme_font_override("font", font_bold)
	banner_label.add_theme_font_size_override("font_size", 28)
	banner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_label.add_theme_constant_override("outline_size", 6)
	banner_label.modulate.a = 0.0
	ui_root.add_child(banner_label)


# ══════════════════════════════════════════════════════════════════════
#  CHARACTERS (ALLIES ON LEFT, ENEMY ON RIGHT)
# ══════════════════════════════════════════════════════════════════════

func _build_characters() -> void:
	# 1. Left Side: Allies (Companion NPC as the main fighter) facing right
	var allies_node := Node2D.new()
	allies_node.name = "AlliesGroup"
	add_child(allies_node)

	ally_sprite = Node2D.new()
	ally_sprite.name = "CompanionNode"
	ally_sprite.position = Vector2(400, 520)
	_setup_companion(ally_sprite)
	allies_node.add_child(ally_sprite)

	# 2. Right Side: Enemy (FallenOrder - SeveredFang) facing left
	var enemy_node := Node2D.new()
	enemy_node.name = "EnemyGroup"
	add_child(enemy_node)

	enemy_sprite = AnimatedSprite2D.new()
	enemy_sprite.name = "EnemySprite"
	enemy_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	enemy_sprite.sprite_frames = _create_severed_fang_frames()
	enemy_sprite.animation = "Idle"
	enemy_sprite.autoplay = "Idle"
	enemy_sprite.flip_h = true
	enemy_sprite.position = Vector2(880, 520)
	enemy_sprite.scale = Vector2(2.6, 2.6)
	enemy_sprite.play("Idle")
	enemy_node.add_child(enemy_sprite)

func _create_player_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	var path := "res://Tiny Swords (Free Pack)/Units/Blue Units/Archer/Archer_Idle.png"
	var frame_count := 6

	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var p_fighter = bm.get("_player_fighter")
		if p_fighter and str(p_fighter.get("leader", "")).to_lower().contains("pawn"):
			path = "res://Tiny Swords (Free Pack)/Units/Blue Units/Pawn/Pawn_Idle.png"
			frame_count = 8

	_add_frames_from_sheet(frames, "Idle", path, frame_count, 8.0, true)
	return frames


func _create_severed_fang_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	_add_frames_from_sheet(frames, "Idle", "res://characters/enemy/FallenOrder-SeveredFang/SpriteSheet/SeveredFangIdle001-Sheet.png", 6, 8.0, true)
	_add_frames_from_sheet(frames, "Attack", "res://characters/enemy/FallenOrder-SeveredFang/SpriteSheet/SeveredFangBasicAtk001-Sheet.png", 24, 16.0, false)
	_add_frames_from_sheet(frames, "Hurt", "res://characters/enemy/FallenOrder-SeveredFang/SpriteSheet/SeveredFangHurt001-Sheet.png", 4, 10.0, false)
	_add_frames_from_sheet(frames, "Death", "res://characters/enemy/FallenOrder-SeveredFang/SpriteSheet/SeveredFangDeath001-Sheet.png", 7, 8.0, false)
	return frames


func _add_frames_from_sheet(frames: SpriteFrames, anim_name: String, path: String, count: int, fps: float, loop: bool) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex = load(path)
	if not tex is Texture2D:
		return
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	var fw := float(tex.get_width()) / float(count)
	var fh := float(tex.get_height())
	for i in range(count):
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(anim_name, a)


func _setup_companion(parent: Node2D) -> void:
	var companion_tex: Texture2D = null

	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var p_fighter = bm.get("_player_fighter")
		if p_fighter and p_fighter.has("image") and ResourceLoader.exists(p_fighter["image"]):
			companion_tex = load(p_fighter["image"])

	if companion_tex == null:
		if ResourceLoader.exists("res://characters/Frieren.png"):
			companion_tex = load("res://characters/Frieren.png")
		elif ResourceLoader.exists("res://characters/Ryo.png"):
			companion_tex = load("res://characters/Ryo.png")
		elif ResourceLoader.exists("res://characters/Tenxi/Tenxi_Idle.png"):
			companion_tex = load("res://characters/Tenxi/Tenxi_Idle.png")

	var spr := Sprite2D.new()
	spr.name = "CompanionSprite"
	spr.texture = companion_tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(2.1, 2.1)

	# Gentle breathing animation
	var tw := create_tween().set_loops()
	tw.tween_property(spr, "scale", Vector2(2.1, 2.16), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spr, "scale", Vector2(2.1, 2.1), 0.7).set_trans(Tween.TRANS_SINE)

	parent.add_child(spr)


# ══════════════════════════════════════════════════════════════════════
#  STATUS BARS & NAME BADGES (MATCHING MOCKUP)
# ══════════════════════════════════════════════════════════════════════

func _build_status_bars(ui_root: Control) -> void:
	# -- Allies Name Badge & Bars --
	var ally_badge := Label.new()
	ally_badge.name = "AllyBadge"
	ally_badge.text = "Companion"
	if font_bold:
		ally_badge.add_theme_font_override("font", font_bold)
	ally_badge.add_theme_font_size_override("font_size", 24)
	ally_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	ally_badge.add_theme_constant_override("outline_size", 6)
	ally_badge.position = Vector2(340, 380)
	ui_root.add_child(ally_badge)

	# Allies Bars Container
	var allies_bars_vbox := VBoxContainer.new()
	allies_bars_vbox.position = Vector2(320, 620)
	allies_bars_vbox.add_theme_constant_override("separation", 6)
	ui_root.add_child(allies_bars_vbox)

	# Allies Stamina Bar Row
	var a_stm_row := _create_bar_row("Stamina", Color(0.96, 0.65, 0.15), "res://ui/BattleStage/Bar/Stamina Bar Without Text.png")
	allies_bars_vbox.add_child(a_stm_row["container"])
	ally_stm_bar = a_stm_row["bar"]
	ally_stm_lbl = a_stm_row["label"]

	# Allies HP Bar Row
	var a_hp_row := _create_bar_row("HP", Color(0.96, 0.35, 0.40), "res://ui/BattleStage/Bar/Health Bar Without Text.png")
	allies_bars_vbox.add_child(a_hp_row["container"])
	ally_hp_bar = a_hp_row["bar"]
	ally_hp_lbl = a_hp_row["label"]

	# -- Enemy Name Badge & Bars --
	var enemy_badge := Label.new()
	enemy_badge.name = "EnemyBadge"
	enemy_badge.text = "Severed Fang"
	if font_bold:
		enemy_badge.add_theme_font_override("font", font_bold)
	enemy_badge.add_theme_font_size_override("font_size", 24)
	enemy_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	enemy_badge.add_theme_constant_override("outline_size", 6)
	enemy_badge.position = Vector2(800, 380)
	ui_root.add_child(enemy_badge)

	# Enemy Bars Container
	var enemy_bars_vbox := VBoxContainer.new()
	enemy_bars_vbox.position = Vector2(800, 620)
	enemy_bars_vbox.add_theme_constant_override("separation", 6)
	ui_root.add_child(enemy_bars_vbox)

	# Enemy Stamina Bar Row
	var e_stm_row := _create_bar_row("Stamina", Color(0.96, 0.65, 0.15), "res://ui/BattleStage/Bar/Stamina Bar Without Text.png")
	enemy_bars_vbox.add_child(e_stm_row["container"])
	enemy_stm_bar = e_stm_row["bar"]
	enemy_stm_lbl = e_stm_row["label"]

	# Enemy HP Bar Row
	var e_hp_row := _create_bar_row("HP", Color(0.96, 0.35, 0.40), "res://ui/BattleStage/Bar/Health Bar Without Text.png")
	enemy_bars_vbox.add_child(e_hp_row["container"])
	enemy_hp_bar = e_hp_row["bar"]
	enemy_hp_lbl = e_hp_row["label"]

func _create_bar_row(title: String, fill_color: Color, bar_tex_path: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.custom_minimum_size = Vector2(58, 0)
	if font_bold:
		title_lbl.add_theme_font_override("font", font_bold)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 4)
	row.add_child(title_lbl)

	# Progress Bar
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(170, 16)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 6
	bar.stretch_margin_right = 6
	bar.stretch_margin_top = 2
	bar.stretch_margin_bottom = 2

	if ResourceLoader.exists(bar_tex_path):
		var tex = load(bar_tex_path)
		bar.texture_progress = tex
		# Under texture
		var under_tex = tex.duplicate()
		bar.texture_under = under_tex
		bar.tint_under = Color(0.2, 0.22, 0.28, 0.8)
	else:
		# Fallback if texture not found
		pass

	row.add_child(bar)

	# Number Label
	var val_lbl := Label.new()
	val_lbl.text = "100/100"
	val_lbl.custom_minimum_size = Vector2(65, 0)
	if font_regular:
		val_lbl.add_theme_font_override("font", font_regular)
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	val_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	val_lbl.add_theme_constant_override("outline_size", 4)
	row.add_child(val_lbl)

	return {
		"container": row,
		"bar": bar,
		"label": val_lbl
	}


# ══════════════════════════════════════════════════════════════════════
#  ACTION BUTTONS CLUSTER (BOTTOM RIGHT - PERSONA STYLE)
# ══════════════════════════════════════════════════════════════════════

func _build_action_buttons(ui_root: Control) -> void:
	var cluster := Control.new()
	cluster.name = "ActionButtonsCluster"
	# Radial center (around the ally character)
	cluster.position = Vector2(240, 480)
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(cluster)
	
	var radius = 110.0
	var sz = Vector2(90, 90)
	
	# Attack (Mid Left)
	btn_attack = _create_action_button(
		"res://ui/BattleStage/Action Button/Attack Btn.png",
		"",
		Vector2(-70, -20) - sz/2.0,
		sz,
		func(): _on_player_action_chosen(StateScript.Action.ATTACK)
	)
	cluster.add_child(btn_attack)

	# Special / Heavy Attack (Top Right)
	btn_special = _create_action_button(
		"res://ui/BattleStage/Action Button/Special Btn.png",
		"res://ui/BattleStage/Action Button/Penerapan UI.png",
		Vector2(50, -100) - sz/2.0,
		sz,
		func(): _on_player_action_chosen(StateScript.Action.HEAVY_ATTACK)
	)
	cluster.add_child(btn_special)

	# Defense (Bottom Left)
	btn_defense = _create_action_button(
		"res://ui/BattleStage/Action Button/Defense Btn.png",
		"",
		Vector2(-50, 70) - sz/2.0,
		sz,
		func(): _on_player_action_chosen(StateScript.Action.DEFEND)
	)
	cluster.add_child(btn_defense)

	# Item / Rest (Bottom Right)
	btn_item = _create_action_button(
		"res://ui/BattleStage/Action Button/Item Btn.png",
		"",
		Vector2(70, 50) - sz/2.0,
		sz,
		func(): _on_player_action_chosen(StateScript.Action.REST)
	)
	cluster.add_child(btn_item)

func _create_action_button(path_a: String, path_b: String, pos: Vector2, sz: Vector2, on_click: Callable) -> TextureButton:
	var btn := TextureButton.new()
	var tex: Texture2D = null
	if ResourceLoader.exists(path_a):
		tex = load(path_a)
	elif path_b != "" and ResourceLoader.exists(path_b):
		tex = load(path_b)

	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = sz
	btn.size = sz
	btn.texture_normal = tex
	btn.position = pos
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pivot_offset = sz / 2.0

	# Micro-animation on hover & click
	btn.mouse_entered.connect(func():
		if not btn.disabled:
			_play_sfx(sfx_hover)
			var tw := create_tween()
			tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE)
	)
	btn.button_down.connect(func():
		if not btn.disabled:
			_play_sfx(sfx_click)
			btn.scale = Vector2(0.95, 0.95)
	)
	btn.button_up.connect(func():
		btn.scale = Vector2(1.08, 1.08)
	)

	btn.pressed.connect(on_click)
	return btn


# ══════════════════════════════════════════════════════════════════════
#  TURN ORDER TRACKER (TOP LEFT)
# ══════════════════════════════════════════════════════════════════════

func _build_turn_tracker(ui_root: Control) -> void:
	turn_tracker_container = Control.new()
	turn_tracker_container.name = "TurnOrderTracker"
	turn_tracker_container.position = Vector2(24, 28)
	turn_tracker_container.custom_minimum_size = Vector2(120, 420)
	turn_tracker_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(turn_tracker_container)

	# 1. Active Turn Card (Bigger top card)
	active_turn_card = _create_turn_card(true, true)
	active_turn_card.position = Vector2(0, 0)
	turn_tracker_container.add_child(active_turn_card)

	# 2. Upcoming Cards Vertical Stack
	upcoming_cards_box = VBoxContainer.new()
	upcoming_cards_box.position = Vector2(0, 72)
	upcoming_cards_box.add_theme_constant_override("separation", 14)
	turn_tracker_container.add_child(upcoming_cards_box)

	_refresh_turn_tracker_cards()


func _refresh_turn_tracker_cards() -> void:
	for c in upcoming_cards_box.get_children():
		c.queue_free()

	# Upcoming 5 turns alternating / future queue
	var is_player_active = (state.current_turn == StateScript.Side.PLAYER)

	# Update active card indicator
	_update_active_card_visual(is_player_active)

	# Add upcoming preview cards
	var current_side = 1 - state.current_turn
	for i in range(5):
		var card = _create_turn_card(false, current_side == StateScript.Side.PLAYER)
		upcoming_cards_box.add_child(card)
		current_side = 1 - current_side


func _create_turn_card(is_active: bool, is_ally: bool) -> Control:
	var container := Control.new()
	var frame_path := ""
	var badge_path := ""
	var card_sz := Vector2(77, 39)

	if is_active:
		card_sz = Vector2(114, 64)
		frame_path = "res://ui/BattleStage/TurnCard/Frame Ally Active.png" if is_ally else "res://ui/BattleStage/TurnCard/Frame Enemy Active.png"
		badge_path = "res://ui/BattleStage/TurnCard/Badge Active Ally.png" if is_ally else "res://ui/BattleStage/TurnCard/Badge Active Enemy.png"
	else:
		card_sz = Vector2(77, 44)
		frame_path = "res://ui/BattleStage/TurnCard/Frame Ally.png" if is_ally else "res://ui/BattleStage/TurnCard/Frame Enemy.png"
		badge_path = "res://ui/BattleStage/TurnCard/Badge Ally.png" if is_ally else "res://ui/BattleStage/TurnCard/Badge Enemy.png"

	container.custom_minimum_size = card_sz
	container.size = card_sz

	# Card Frame
	var frame_rect := TextureRect.new()
	frame_rect.name = "Frame"
	if ResourceLoader.exists(frame_path):
		frame_rect.texture = load(frame_path)
	frame_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame_rect.custom_minimum_size = card_sz
	frame_rect.size = card_sz
	frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.add_child(frame_rect)

	# Badge Indicator on Left Notch
	var badge_rect := TextureRect.new()
	badge_rect.name = "Badge"
	if ResourceLoader.exists(badge_path):
		badge_rect.texture = load(badge_path)
	badge_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if is_active:
		badge_rect.position = Vector2(-2, 19)
		badge_rect.custom_minimum_size = Vector2(26, 26)
	else:
		badge_rect.position = Vector2(0, 10)
		badge_rect.custom_minimum_size = Vector2(13, 20)
	badge_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.add_child(badge_rect)

	# Character Portrait inside
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	if is_ally and ally_sprite and ally_sprite.has_node("CompanionSprite"):
		portrait.texture = ally_sprite.get_node("CompanionSprite").texture
	elif ResourceLoader.exists("res://ui/BattleStage/TurnCard/Potrait.png"):
		portrait.texture = load("res://ui/BattleStage/TurnCard/Potrait.png")
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if is_active:
		portrait.position = Vector2(30, 2)
		portrait.custom_minimum_size = Vector2(80, 58)
	else:
		portrait.position = Vector2(20, 2)
		portrait.custom_minimum_size = Vector2(52, 35)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	container.add_child(portrait)

	return container


func _update_active_card_visual(is_ally: bool) -> void:
	if active_turn_card == null:
		return
	var frame_rect = active_turn_card.get_node_or_null("Frame") as TextureRect
	var badge_rect = active_turn_card.get_node_or_null("Badge") as TextureRect

	var frame_path = "res://ui/BattleStage/TurnCard/Frame Ally Active.png" if is_ally else "res://ui/BattleStage/TurnCard/Frame Enemy Active.png"
	var badge_path = "res://ui/BattleStage/TurnCard/Badge Active Ally.png" if is_ally else "res://ui/BattleStage/TurnCard/Badge Active Enemy.png"

	if frame_rect and ResourceLoader.exists(frame_path):
		frame_rect.texture = load(frame_path)
	if badge_rect and ResourceLoader.exists(badge_path):
		badge_rect.texture = load(badge_path)


# ══════════════════════════════════════════════════════════════════════
#  DEBUG OVERLAY (TOP RIGHT - MATCHING MOCKUP)
# ══════════════════════════════════════════════════════════════════════

var btn_toggle_debug: Button

func _build_debug_overlay(parent: Control) -> void:
	btn_toggle_debug = Button.new()
	btn_toggle_debug.text = "Toggle Debug"
	btn_toggle_debug.position = Vector2(1100, 10)
	btn_toggle_debug.custom_minimum_size = Vector2(120, 30)
	btn_toggle_debug.pressed.connect(func(): debug_panel.visible = not debug_panel.visible)
	parent.add_child(btn_toggle_debug)

	debug_panel = PanelContainer.new()
	debug_panel.visible = false
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
	d_title.text = "DEBUG OVERLAY"
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
	opt_algorithm.item_selected.connect(func(_idx): current_algo = opt_algorithm.get_item_id(_idx))
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
		lbl_depth_val.text = "%d" % int(v)
		current_depth = int(v)
	)
	depth_hbox.add_child(slider_depth)

	lbl_depth_val = Label.new()
	lbl_depth_val.text = "4"
	lbl_depth_val.custom_minimum_size.x = 20
	lbl_depth_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	depth_hbox.add_child(lbl_depth_val)
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
	opt_eval_type.item_selected.connect(func(_idx): current_eval = opt_eval_type.get_item_id(_idx))
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
	opt_move_ordering.item_selected.connect(func(_idx): current_ordering = opt_move_ordering.get_item_id(_idx))
	cfg_grid.add_child(opt_move_ordering)

	vbox.add_child(HSeparator.new())

	# Metrics
	var metrics_box := VBoxContainer.new()
	metrics_box.add_theme_constant_override("separation", 2)
	vbox.add_child(metrics_box)

	lbl_nodes = Label.new()
	lbl_nodes.text = "Nodes: 0"
	lbl_nodes.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_nodes)

	lbl_pruned = Label.new()
	lbl_pruned.text = "Pruned: 0"
	lbl_pruned.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_pruned)

	lbl_time = Label.new()
	lbl_time.text = "Waktu: 0.00 ms"
	lbl_time.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_time)

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

# GAMEPLAY LOOP
func _on_player_action_chosen(action: int) -> void:
	if is_processing_turn or state.is_terminal():
		return
	if state.current_turn != StateScript.Side.PLAYER:
		return

	# Cek apakah stamina mencukupi
	var valid_actions = state.get_valid_actions()
	if not valid_actions.has(action):
		_show_banner("Not enough Stamina!", Color(1.0, 0.4, 0.4))
		_play_sfx(sfx_click)
		return

	is_processing_turn = true
	_set_buttons_disabled(true)

	# 1. Visual player dash & sound
	_play_action_visual(true, action)

	# 2. Apply action ke state
	var log_data = state.apply_action(action, current_algo == AIScript.Algorithm.EXPECTIMAX)
	_show_action_floating_text(true, log_data)
	_update_ui_state()

	# 3. Cek apakah lawan kalah
	if state.is_terminal():
		_handle_game_over()
		return

	# 4. Tunggu sejenak sebelum AI Enemy mengeksekusi giliran
	await get_tree().create_timer(0.6).timeout
	_execute_enemy_ai_turn()


func _execute_enemy_ai_turn() -> void:
	if state.is_terminal():
		return

	# AI Search
	var decision := ai.decide_action(
		state,
		current_depth,
		current_algo,
		current_eval,
		current_ordering,
		StateScript.Side.ENEMY
	)

	# Update debug metrics
	lbl_nodes.text = "Nodes : %d" % decision.get("total_nodes", 0)
	lbl_pruned.text = "Pruned : %d" % decision.get("prune_count", 0)
	lbl_time.text = "Waktu : %.2f ms" % decision.get("time_ms", 0.0)

	# Update considered actions list
	_update_considered_actions_display(decision)

	var enemy_action = decision.get("action", StateScript.Action.ATTACK)
	if enemy_action == -1:
		enemy_action = StateScript.Action.REST

	# Visual enemy attack animation
	_play_action_visual(false, enemy_action)

	var log_data = state.apply_action(enemy_action, current_algo == AIScript.Algorithm.EXPECTIMAX)
	_show_action_floating_text(false, log_data)
	_update_ui_state()

	if state.is_terminal():
		_handle_game_over()
		return

	# Kembali ke giliran Player
	is_processing_turn = false
	_set_buttons_disabled(false)
	_refresh_turn_tracker_cards()


func _update_considered_actions_display(decision: Dictionary) -> void:
	for c in candidates_container.get_children():
		c.queue_free()

	var candidates: Array = decision.get("candidates", [])
	var chosen_action: int = decision.get("action", -1)

	var names := {
		StateScript.Action.ATTACK: "Attack",
		StateScript.Action.HEAVY_ATTACK: "Heavy Attack",
		StateScript.Action.DEFEND: "Defend",
		StateScript.Action.REST: "Rest"
	}

	if candidates.is_empty():
		var l := Label.new()
		l.text = "%s : Skor %.0f" % [names.get(chosen_action, "Action"), decision.get("score", 0.0)]
		if font_bold:
			l.add_theme_font_override("font", font_bold)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.12, 0.75, 0.25, 1.0))
		candidates_container.add_child(l)
		return

	for c in candidates:
		var act = c.get("action", 0)
		var sc = c.get("score", 0.0)
		var is_chosen = (act == chosen_action)

		var l := Label.new()
		l.text = "%s : Skor %.0f" % [names.get(act, "Action"), sc]
		if is_chosen and font_bold:
			l.add_theme_font_override("font", font_bold)
			l.add_theme_color_override("font_color", Color(0.12, 0.72, 0.22, 1.0)) # Hijau terang sesuai mockup
		else:
			if font_regular:
				l.add_theme_font_override("font", font_regular)
			l.add_theme_color_override("font_color", Color(0.20, 0.24, 0.32, 1.0))
		l.add_theme_font_size_override("font_size", 12)
		candidates_container.add_child(l)


func _update_ui_state() -> void:
	# Update bar values
	_tween_bar(ally_hp_bar, ally_hp_lbl, state.player["hp"], StateScript.DEFAULT_MAX_HP)
	_tween_bar(ally_stm_bar, ally_stm_lbl, state.player["stamina"], StateScript.DEFAULT_MAX_STAMINA)

	_tween_bar(enemy_hp_bar, enemy_hp_lbl, state.enemy["hp"], StateScript.DEFAULT_MAX_HP)
	_tween_bar(enemy_stm_bar, enemy_stm_lbl, state.enemy["stamina"], StateScript.DEFAULT_MAX_STAMINA)

	# Update button disabled status berdasarkan stamina player
	var valid_actions = state.get_valid_actions()
	if btn_attack:
		btn_attack.modulate = Color.WHITE if valid_actions.has(StateScript.Action.ATTACK) else Color(0.5, 0.5, 0.5, 0.8)
	if btn_special:
		btn_special.modulate = Color.WHITE if valid_actions.has(StateScript.Action.HEAVY_ATTACK) else Color(0.5, 0.5, 0.5, 0.8)
	if btn_defense:
		btn_defense.modulate = Color.WHITE if valid_actions.has(StateScript.Action.DEFEND) else Color(0.5, 0.5, 0.5, 0.8)
	if btn_item:
		btn_item.modulate = Color.WHITE if valid_actions.has(StateScript.Action.REST) else Color(0.5, 0.5, 0.5, 0.8)


func _tween_bar(bar: TextureProgressBar, lbl: Label, current_val: int, max_val: int) -> void:
	if bar:
		var tw := create_tween()
		tw.tween_property(bar, "value", float(current_val), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if lbl:
		lbl.text = "%d/%d" % [current_val, max_val]


func _set_buttons_disabled(disabled: bool) -> void:
	if btn_attack: btn_attack.disabled = disabled
	if btn_special: btn_special.disabled = disabled
	if btn_defense: btn_defense.disabled = disabled
	if btn_item: btn_item.disabled = disabled


# ══════════════════════════════════════════════════════════════════════
#  VISUAL EFFECTS & ANIMATIONS
# ══════════════════════════════════════════════════════════════════════

func _play_action_visual(is_player: bool, action: int) -> void:
	var actor := ally_sprite if is_player else enemy_sprite
	var target := enemy_sprite if is_player else ally_sprite

	if actor == null:
		return

	var orig_pos = actor.position
	var target_pos = target.position if target != null else (orig_pos + Vector2(100, 0) * (1 if is_player else -1))
	var dir = (target_pos - orig_pos).normalized()

	match action:
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			if not is_player and enemy_sprite:
				enemy_sprite.play("Attack")
			else:
				if ally_sprite and ally_sprite.has_node("AnimationPlayer"):
					var anim = ally_sprite.get_node("AnimationPlayer")
					if anim.has_animation("Attack"): anim.play("Attack")
			var tw := create_tween()
			var dash_dist = 90.0 if action == StateScript.Action.ATTACK else 140.0
			tw.tween_property(actor, "position", orig_pos + dir * dash_dist, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func():
				_play_sfx(sfx_click)
				if is_player and enemy_sprite:
					enemy_sprite.play("Hurt")
					var t2 = create_tween()
					t2.tween_interval(0.4)
					t2.tween_callback(func(): enemy_sprite.play("Idle"))
			)
			tw.tween_property(actor, "position", orig_pos, 0.2).set_trans(Tween.TRANS_SINE)
			if not is_player and enemy_sprite:
				tw.tween_callback(func(): enemy_sprite.play("Idle"))

		StateScript.Action.DEFEND:
			var tw := create_tween()
			tw.tween_property(actor, "modulate", Color(0.4, 0.8, 1.2, 1.0), 0.15)
			tw.tween_property(actor, "modulate", Color.WHITE, 0.25)

		StateScript.Action.REST:
			var tw := create_tween()
			tw.tween_property(actor, "modulate", Color(0.5, 1.3, 0.7, 1.0), 0.2)
			tw.tween_property(actor, "modulate", Color.WHITE, 0.3)


func _show_action_floating_text(is_player: bool, log_data: Dictionary) -> void:
	var target_pos = (enemy_sprite.position if is_player else ally_sprite.position) + Vector2(0, -90)
	var actor_pos = (ally_sprite.position if is_player else enemy_sprite.position) + Vector2(0, -90)

	var action = log_data.get("action", 0)

	match action:
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			var dmg = log_data.get("damage", 0)
			var stm_dmg = log_data.get("stamina_damage", 0)
			if dmg > 0:
				_spawn_floating_text(target_pos, "-%d HP" % dmg, Color(1.0, 0.25, 0.25))
			elif stm_dmg > 0:
				_spawn_floating_text(target_pos, "-%d STM (Blocked)" % stm_dmg, Color(1.0, 0.7, 0.2))

			if log_data.get("guard_break", false):
				_spawn_floating_text(target_pos + Vector2(0, -30), "GUARD BREAK!", Color(1.0, 0.9, 0.1))

		StateScript.Action.DEFEND:
			_spawn_floating_text(actor_pos, "DEFENDING", Color(0.3, 0.8, 1.0))

		StateScript.Action.REST:
			var stm_gain = log_data.get("stamina_gain", 50)
			_spawn_floating_text(actor_pos, "+%d STM" % stm_gain, Color(0.3, 1.0, 0.4))


func _spawn_floating_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos - Vector2(60, 0)
	l.custom_minimum_size = Vector2(120, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		l.add_theme_font_override("font", font_bold)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)

	var tw := create_tween()
	tw.tween_property(l, "position:y", pos.y - 45.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tw.tween_callback(l.queue_free)


func _show_banner(msg: String, color: Color) -> void:
	if banner_label == null:
		return
	banner_label.text = msg
	banner_label.add_theme_color_override("font_color", color)
	banner_label.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(banner_label, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.2)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.35)


func _handle_game_over() -> void:
	is_processing_turn = true
	_set_buttons_disabled(true)

	var winner = state.get_winner()
	var is_player_win = (winner == StateScript.Side.PLAYER)

	if is_player_win:
		_show_banner("VICTORY!", Color(0.2, 1.0, 0.4))
		if enemy_sprite:
			enemy_sprite.play("Death")
	else:
		_show_banner("DEFEAT...", Color(1.0, 0.2, 0.2))

	await get_tree().create_timer(2.0).timeout

	# Show Game Over Panel
	_show_game_over_modal(is_player_win)


func _show_game_over_modal(is_player_win: bool) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UILayer/UIRoot.add_child(overlay)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 220)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -180
	card.offset_right = 180
	card.offset_top = -110
	card.offset_bottom = 110

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.20, 0.98)
	sb.border_color = Color(0.35, 0.85, 1.0) if is_player_win else Color(1.0, 0.35, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	card.add_theme_stylebox_override("panel", sb)
	overlay.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)

	var res_lbl := Label.new()
	res_lbl.text = "VICTORY" if is_player_win else "DEFEAT"
	res_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		res_lbl.add_theme_font_override("font", font_bold)
	res_lbl.add_theme_font_size_override("font_size", 28)
	res_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4) if is_player_win else Color(1.0, 0.3, 0.3))
	vbox.add_child(res_lbl)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_box)

	var retry_btn := Button.new()
	retry_btn.text = "Rematch"
	retry_btn.custom_minimum_size = Vector2(120, 38)
	if font_bold: retry_btn.add_theme_font_override("font", font_bold)
	retry_btn.pressed.connect(func():
		_play_sfx(sfx_click)
		get_tree().reload_current_scene()
	)
	btn_box.add_child(retry_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Overworld"
	exit_btn.custom_minimum_size = Vector2(120, 38)
	if font_bold: exit_btn.add_theme_font_override("font", font_bold)
	exit_btn.pressed.connect(func():
		_play_sfx(sfx_click)
		get_tree().change_scene_to_file("res://Overworld.tscn")
	)
	btn_box.add_child(exit_btn)
