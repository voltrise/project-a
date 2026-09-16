class_name Portal
extends Area2D

## Interactive Battle Stage Portal
## Activates & animates when player is nearby.
## Shows an interactive "[E] Enter Portal" prompt and opens a Stage Selection modal.

signal stage_selected(stage_id: int, stage_name: String)
signal portal_opened
signal portal_closed

@export var animation_fps: float = 12.0
@export var proximity_radius: float = 150.0
@export var enable_solid_collision: bool = true

var is_player_near: bool = false
var is_stage_select_open: bool = false

# Resources
var font_bold: Font = null
var font_regular: Font = null
var sfx_hover: AudioStream = null
var sfx_click: AudioStream = null
var sfx_select: AudioStream = null

# Node references
var animated_sprite: AnimatedSprite2D
var solid_body: StaticBody2D
var floating_prompt: Control
var stage_select_canvas: CanvasLayer
var audio_player: AudioStreamPlayer

# Stage data list (Easy to extend or configure)
var stages_data: Array[Dictionary] = [
	{
		"id": 1,
		"name": "Goblin Glade",
		"tier": "EASY",
		"level": "LV. 1-5",
		"color": Color(0.29, 0.85, 0.39, 1.0), # #4ADE80
		"desc": "A sunlit clearing occupied by goblin scouts. Perfect for warming up your party.",
		"monsters": "Goblin Scout, Wild Slime",
		"reward": "150 EXP • 200 Gold • Herb"
	},
	{
		"id": 2,
		"name": "Ruined Outpost",
		"tier": "NORMAL",
		"level": "LV. 6-10",
		"color": Color(0.98, 0.75, 0.14, 1.0), # #FBBF24
		"desc": "Ancient stone barricades defended by armored goblin warriors and archers.",
		"monsters": "Goblin Archer, Heavy Brute",
		"reward": "450 EXP • 500 Gold • Iron Gear"
	},
	{
		"id": 3,
		"name": "Dragon Sanctum",
		"tier": "NIGHTMARE",
		"level": "LV. 11+",
		"color": Color(0.97, 0.44, 0.44, 1.0), # #F87171
		"desc": "Volcanic ruins teeming with dragon whelps and an ancient awakened titan.",
		"monsters": "Fire Drake, Fallen Champion",
		"reward": "1,200 EXP • Relic Chest • Gem"
	}
]

func _ready() -> void:
	z_index = 2
	add_to_group("portals")
	add_to_group("obstacles")

	_load_resources()
	_setup_nodes()
	_create_floating_prompt()
	_create_stage_select_ui()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Start dormant
	if animated_sprite:
		if animated_sprite.sprite_frames:
			animated_sprite.sprite_frames.set_animation_speed("default", animation_fps)
		animated_sprite.speed_scale = 1.0
		animated_sprite.stop()
		animated_sprite.frame = 0

	_set_portal_active(false)

func _load_resources() -> void:
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		font_bold = load("res://fonts/PixelifySans-Bold.ttf")
	if ResourceLoader.exists("res://fonts/PixelifySans-Regular.ttf"):
		font_regular = load("res://fonts/PixelifySans-Regular.ttf")

	if ResourceLoader.exists("res://audio/sfx/hover_pop.wav"):
		sfx_hover = load("res://audio/sfx/hover_pop.wav")
	if ResourceLoader.exists("res://audio/sfx/dice_click.wav"):
		sfx_click = load("res://audio/sfx/dice_click.wav")
	if ResourceLoader.exists("res://audio/sfx/reel_tick.wav"):
		sfx_select = load("res://audio/sfx/reel_tick.wav")

func _setup_nodes() -> void:
	animated_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	solid_body = get_node_or_null("SolidBody") as StaticBody2D
	if solid_body and not enable_solid_collision:
		solid_body.queue_free()

	audio_player = AudioStreamPlayer.new()
	audio_player.name = "PortalAudio"
	audio_player.volume_db = -6.0
	add_child(audio_player)

func _play_sfx(stream: AudioStream, pitch: float = 1.0) -> void:
	if audio_player and stream:
		audio_player.stream = stream
		audio_player.pitch_scale = pitch * randf_range(0.97, 1.03)
		audio_player.play()

# -----------------------------------------------------------------------------
# 1. Floating World Prompt ("[E] Enter Portal")
# -----------------------------------------------------------------------------
func _create_floating_prompt() -> void:
	floating_prompt = Control.new()
	floating_prompt.name = "FloatingPrompt"
	floating_prompt.position = Vector2(0, -100)
	floating_prompt.modulate.a = 0.0
	floating_prompt.visible = false
	add_child(floating_prompt)

	var btn := Button.new()
	btn.name = "PromptButton"
	btn.text = "✦ ENTER PORTAL [E] ✦"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(170, 36)
	btn.position = Vector2(-85, -18)

	if font_bold:
		btn.add_theme_font_override("font", font_bold)
	btn.add_theme_font_size_override("font_size", 14)

	# Style normal
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.10, 0.13, 0.18, 0.92)
	sb_normal.border_color = Color(0.25, 0.85, 0.95, 0.9)
	sb_normal.set_border_width_all(2)
	sb_normal.set_corner_radius_all(18)
	sb_normal.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", sb_normal)

	# Style hover
	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.14, 0.22, 0.32, 0.96)
	sb_hover.border_color = Color(0.95, 0.85, 0.40, 1.0) # Golden glow
	sb_hover.set_border_width_all(2)
	sb_hover.set_corner_radius_all(18)
	sb_hover.set_content_margin_all(6)
	btn.add_theme_stylebox_override("hover", sb_hover)

	var sb_pressed := StyleBoxFlat.new()
	sb_pressed.bg_color = Color(0.08, 0.16, 0.25, 1.0)
	sb_pressed.border_color = Color(0.95, 0.85, 0.40, 1.0)
	sb_pressed.set_border_width_all(2)
	sb_pressed.set_corner_radius_all(18)
	btn.add_theme_stylebox_override("pressed", sb_pressed)

	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.50, 1.0))

	btn.pressed.connect(open_stage_select)
	btn.mouse_entered.connect(func(): _play_sfx(sfx_hover, 1.15))

	floating_prompt.add_child(btn)

# -----------------------------------------------------------------------------
# 2. Stage Select Modal UI (CanvasLayer)
# -----------------------------------------------------------------------------
var modal_overlay: ColorRect
var modal_panel: Control
var toast_label: Label

func _create_stage_select_ui() -> void:
	stage_select_canvas = CanvasLayer.new()
	stage_select_canvas.name = "StageSelectCanvas"
	stage_select_canvas.layer = 95
	stage_select_canvas.visible = false
	add_child(stage_select_canvas)

	# Dim background
	modal_overlay = ColorRect.new()
	modal_overlay.name = "DimOverlay"
	modal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_overlay.color = Color(0, 0, 0, 0.65)
	modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_overlay.gui_input.connect(_on_overlay_input)
	stage_select_canvas.add_child(modal_overlay)

	# Centered Dialog Window (780 x 500)
	modal_panel = Control.new()
	modal_panel.name = "ModalPanel"
	modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	modal_panel.offset_left = -390.0
	modal_panel.offset_top = -250.0
	modal_panel.offset_right = 390.0
	modal_panel.offset_bottom = 250.0
	modal_panel.pivot_offset = Vector2(390, 250)
	stage_select_canvas.add_child(modal_panel)

	# Panel Background Box
	var panel_bg := Panel.new()
	panel_bg.name = "PanelBG"
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb_panel := StyleBoxFlat.new()
	sb_panel.bg_color = Color(0.11, 0.14, 0.19, 0.97)
	sb_panel.border_color = Color(0.35, 0.65, 0.75, 1.0)
	sb_panel.set_border_width_all(3)
	sb_panel.set_corner_radius_all(16)
	sb_panel.shadow_color = Color(0, 0, 0, 0.5)
	sb_panel.shadow_size = 18
	panel_bg.add_theme_stylebox_override("panel", sb_panel)
	modal_panel.add_child(panel_bg)

	# Header Title
	var title := Label.new()
	title.text = "✦ SELECT BATTLE STAGE ✦"
	title.position = Vector2(40, 24)
	title.size = Vector2(700, 36)
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.65, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose a realm to deploy your party and engage in tactical battle"
	subtitle.position = Vector2(40, 62)
	subtitle.size = Vector2(700, 24)
	if font_regular:
		subtitle.add_theme_font_override("font", font_regular)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 0.9))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_panel.add_child(subtitle)

	# Close [X] Button
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(728, 18)
	close_btn.size = Vector2(36, 36)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font_bold:
		close_btn.add_theme_font_override("font", font_bold)
	close_btn.add_theme_font_size_override("font_size", 18)

	var sb_close := StyleBoxFlat.new()
	sb_close.bg_color = Color(0.2, 0.24, 0.32, 0.8)
	sb_close.border_color = Color(0.6, 0.7, 0.8, 0.5)
	sb_close.set_border_width_all(1)
	sb_close.set_corner_radius_all(18)
	close_btn.add_theme_stylebox_override("normal", sb_close)

	var sb_close_h := StyleBoxFlat.new()
	sb_close_h.bg_color = Color(0.85, 0.25, 0.25, 0.95)
	sb_close_h.border_color = Color(1.0, 0.8, 0.8, 1.0)
	sb_close_h.set_border_width_all(1)
	sb_close_h.set_corner_radius_all(18)
	close_btn.add_theme_stylebox_override("hover", sb_close_h)

	close_btn.pressed.connect(close_stage_select)
	close_btn.mouse_entered.connect(func(): _play_sfx(sfx_hover, 1.2))
	modal_panel.add_child(close_btn)

	# Stage Cards Container
	var cards_container := HBoxContainer.new()
	cards_container.name = "CardsContainer"
	cards_container.position = Vector2(30, 100)
	cards_container.size = Vector2(720, 310)
	cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_container.add_theme_constant_override("separation", 16)
	modal_panel.add_child(cards_container)

	for stage in stages_data:
		var card := _build_stage_card(stage)
		cards_container.add_child(card)

	# Bottom Status / Feedback Toast
	toast_label = Label.new()
	toast_label.name = "ToastLabel"
	toast_label.position = Vector2(40, 430)
	toast_label.size = Vector2(700, 30)
	if font_bold:
		toast_label.add_theme_font_override("font", font_bold)
	toast_label.add_theme_font_size_override("font_size", 14)
	toast_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 1.0))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.text = ""
	modal_panel.add_child(toast_label)

func _build_stage_card(stage: Dictionary) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(226, 305)

	var sb_card := StyleBoxFlat.new()
	sb_card.bg_color = Color(0.15, 0.18, 0.25, 0.95)
	sb_card.border_color = stage.get("color", Color.WHITE).lerp(Color(0.2, 0.2, 0.2), 0.3)
	sb_card.set_border_width_all(2)
	sb_card.set_corner_radius_all(12)
	sb_card.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb_card)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 12
	vbox.offset_right = -12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Header: Tier Badge + Level
	var badge_box := HBoxContainer.new()
	var tier_badge := Label.new()
	tier_badge.text = "[ %s ]" % stage.get("tier", "NORMAL")
	if font_bold:
		tier_badge.add_theme_font_override("font", font_bold)
	tier_badge.add_theme_font_size_override("font_size", 12)
	tier_badge.add_theme_color_override("font_color", stage.get("color", Color.WHITE))
	badge_box.add_child(tier_badge)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_box.add_child(spacer)

	var lvl_lbl := Label.new()
	lvl_lbl.text = stage.get("level", "")
	if font_bold:
		lvl_lbl.add_theme_font_override("font", font_bold)
	lvl_lbl.add_theme_font_size_override("font_size", 12)
	lvl_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, 0.9))
	badge_box.add_child(lvl_lbl)
	vbox.add_child(badge_box)

	# Stage Name
	var name_lbl := Label.new()
	name_lbl.text = stage.get("name", "Stage")
	if font_bold:
		name_lbl.add_theme_font_override("font", font_bold)
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(name_lbl)

	# Divider line
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(0.3, 0.35, 0.45, 0.5)
	vbox.add_child(sep)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = stage.get("desc", "")
	if font_regular:
		desc_lbl.add_theme_font_override("font", font_regular)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9, 0.85))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(0, 60)
	vbox.add_child(desc_lbl)

	# Monsters Preview
	var monster_box := VBoxContainer.new()
	var monster_title := Label.new()
	monster_title.text = "Enemies:"
	if font_bold:
		monster_title.add_theme_font_override("font", font_bold)
	monster_title.add_theme_font_size_override("font_size", 11)
	monster_title.add_theme_color_override("font_color", Color(0.95, 0.7, 0.3, 1.0))
	monster_box.add_child(monster_title)

	var monster_desc := Label.new()
	monster_desc.text = stage.get("monsters", "-")
	if font_regular:
		monster_desc.add_theme_font_override("font", font_regular)
	monster_desc.add_theme_font_size_override("font_size", 11)
	monster_desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.8))
	monster_box.add_child(monster_desc)
	vbox.add_child(monster_box)

	# Rewards Preview
	var reward_box := VBoxContainer.new()
	var reward_title := Label.new()
	reward_title.text = "Rewards:"
	if font_bold:
		reward_title.add_theme_font_override("font", font_bold)
	reward_title.add_theme_font_size_override("font_size", 11)
	reward_title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0, 1.0))
	reward_box.add_child(reward_title)

	var reward_desc := Label.new()
	reward_desc.text = stage.get("reward", "-")
	if font_regular:
		reward_desc.add_theme_font_override("font", font_regular)
	reward_desc.add_theme_font_size_override("font_size", 11)
	reward_desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.8))
	reward_box.add_child(reward_desc)
	vbox.add_child(reward_box)

	var card_spacer := Control.new()
	card_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(card_spacer)

	# Enter Stage Button
	var enter_btn := Button.new()
	enter_btn.text = "ENTER BATTLE ▶"
	enter_btn.custom_minimum_size = Vector2(0, 36)
	enter_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font_bold:
		enter_btn.add_theme_font_override("font", font_bold)
	enter_btn.add_theme_font_size_override("font_size", 13)

	var sb_btn := StyleBoxFlat.new()
	sb_btn.bg_color = stage.get("color", Color.WHITE).lerp(Color.BLACK, 0.7)
	sb_btn.border_color = stage.get("color", Color.WHITE)
	sb_btn.set_border_width_all(2)
	sb_btn.set_corner_radius_all(8)
	enter_btn.add_theme_stylebox_override("normal", sb_btn)

	var sb_btn_h := StyleBoxFlat.new()
	sb_btn_h.bg_color = stage.get("color", Color.WHITE).lerp(Color.BLACK, 0.4)
	sb_btn_h.border_color = Color.WHITE
	sb_btn_h.set_border_width_all(2)
	sb_btn_h.set_corner_radius_all(8)
	enter_btn.add_theme_stylebox_override("hover", sb_btn_h)

	enter_btn.mouse_entered.connect(func(): _play_sfx(sfx_hover, 1.1))
	enter_btn.pressed.connect(func(): _on_stage_chosen(stage))
	vbox.add_child(enter_btn)

	return card

func _on_stage_chosen(stage: Dictionary) -> void:
	_play_sfx(sfx_click)
	var stage_id: int = stage.get("id", 1)
	var stage_name: String = stage.get("name", "Stage")

	toast_label.text = "⚔ Entering [ %s ]... (Battle Scene Ready!)" % stage_name
	print("[Portal] Selected Stage %d: '%s'. Hook your battle stage scene here!" % [stage_id, stage_name])

	stage_selected.emit(stage_id, stage_name)

	# Animate brief confirmation before action
	var t := create_tween()
	t.tween_property(toast_label, "modulate:a", 1.0, 0.1).from(0.0)

	# If user has a battle scene in the future, trigger it:
	# e.g.: get_tree().change_scene_to_file("res://battle_stage.tscn")

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_stage_select()

# -----------------------------------------------------------------------------
# 3. Proximity & State Control
# -----------------------------------------------------------------------------
var _players_in_area: int = 0

func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		_players_in_area += 1
		_update_proximity_state()

func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		_players_in_area = max(0, _players_in_area - 1)
		_update_proximity_state()

func _is_player(node: Node) -> bool:
	if node == null:
		return false
	if node is CharacterBody2D:
		return true
	if node.name.begins_with("Player"):
		return true
	return false

func _process(_delta: float) -> void:
	# Fallback distance check to ensure seamless detection with tap-to-move / multiple players
	var nearest_dist := 999999.0
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty() and get_parent() != null:
		for child in get_parent().get_children():
			if _is_player(child) and child is Node2D:
				var d = global_position.distance_to(child.global_position)
				if d < nearest_dist:
					nearest_dist = d
	else:
		for p in players:
			if p is Node2D:
				var d = global_position.distance_to(p.global_position)
				if d < nearest_dist:
					nearest_dist = d

	var near_by_distance := (nearest_dist <= proximity_radius)
	var near := (_players_in_area > 0 or near_by_distance)

	if near != is_player_near:
		is_player_near = near
		_set_portal_active(is_player_near)

	# Gentle bobbing for floating prompt when visible
	if floating_prompt and floating_prompt.visible:
		floating_prompt.position.y = -100.0 + sin(Time.get_ticks_msec() * 0.005) * 4.0

func _update_proximity_state() -> void:
	var near := (_players_in_area > 0)
	if near != is_player_near:
		is_player_near = near
		_set_portal_active(is_player_near)

func _set_portal_active(active: bool) -> void:
	if active:
		# Awaken portal!
		if animated_sprite:
			if animated_sprite.sprite_frames:
				animated_sprite.sprite_frames.set_animation_speed("default", animation_fps)
			animated_sprite.speed_scale = 1.0
			animated_sprite.play("default")

		# Show floating prompt
		if floating_prompt:
			floating_prompt.visible = true
			var t := create_tween()
			t.tween_property(floating_prompt, "modulate:a", 1.0, 0.2).from(0.0)
			t.parallel().tween_property(floating_prompt, "scale", Vector2.ONE, 0.25).from(Vector2(0.8, 0.8)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		# Wind down portal
		if animated_sprite:
			animated_sprite.stop()
			animated_sprite.frame = 0

		# Hide prompt
		if floating_prompt:
			var t := create_tween()
			t.tween_property(floating_prompt, "modulate:a", 0.0, 0.15)
			t.parallel().tween_property(floating_prompt, "scale", Vector2(0.8, 0.8), 0.15)
			t.chain().tween_callback(func(): floating_prompt.visible = false)

		if is_stage_select_open:
			close_stage_select()

# -----------------------------------------------------------------------------
# 4. Modal Open / Close & Input
# -----------------------------------------------------------------------------
func open_stage_select() -> void:
	if is_stage_select_open:
		return
	is_stage_select_open = true
	_play_sfx(sfx_click)

	stage_select_canvas.visible = true
	toast_label.text = ""

	var t := create_tween().set_parallel(true)
	modal_overlay.modulate.a = 0.0
	modal_panel.scale = Vector2(0.85, 0.85)
	modal_panel.modulate.a = 0.0

	t.tween_property(modal_overlay, "modulate:a", 1.0, 0.2)
	t.tween_property(modal_panel, "modulate:a", 1.0, 0.2)
	t.tween_property(modal_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	portal_opened.emit()

func close_stage_select() -> void:
	if not is_stage_select_open:
		return
	is_stage_select_open = false
	_play_sfx(sfx_click, 0.9)

	var t := create_tween().set_parallel(true)
	t.tween_property(modal_overlay, "modulate:a", 0.0, 0.15)
	t.tween_property(modal_panel, "modulate:a", 0.0, 0.15)
	t.tween_property(modal_panel, "scale", Vector2(0.85, 0.85), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func():
		stage_select_canvas.visible = false
	)

	portal_closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E and is_player_near:
			if not is_stage_select_open:
				open_stage_select()
			else:
				close_stage_select()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_stage_select_open:
			close_stage_select()
			get_viewport().set_input_as_handled()
