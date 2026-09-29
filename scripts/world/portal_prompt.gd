class_name PortalPrompt
extends Area2D

## Proximity prompt & Pre-battle Party Preview Modal untuk portal tile di overworld.
## Centered via CenterContainer, avatar besar dengan player grounded sejajar NPC,
## tombol Start Battle hijau terpusat di tengah (tanpa tombol Cancel),
## tombol X lebih besar di pojok kanan atas, tanpa icon pedang di tepi header.

@export var prompt_radius: float = 130.0
@export var enemy_preset_key: String = "slime"
@export var prompt_label_text: String = "Start Battle"

var is_player_near: bool = false
var _prompt_ui: Control = null
var _key_icon_node: Control = null
var _is_transitioning: bool = false
var _sfx_stream: AudioStream = null

# Modal CanvasLayer & Controls
var _modal_canvas: CanvasLayer = null
var _modal_overlay: ColorRect = null
var _modal_card: Control = null
var _is_modal_open: bool = false

# Font Pixelify Sans
var font_bold: Font = null
var font_regular: Font = null

func _ready() -> void:
	name = "PortalPrompt"
	z_index = 6
	collision_layer = 0
	collision_mask = 1 # Player layer

	# Load Pixelify Sans fonts
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		font_bold = load("res://fonts/PixelifySans-Bold.ttf")
	elif ResourceLoader.exists("res://fonts/PixelifySans-SemiBold.ttf"):
		font_bold = load("res://fonts/PixelifySans-SemiBold.ttf")

	if ResourceLoader.exists("res://fonts/PixelifySans-Regular.ttf"):
		font_regular = load("res://fonts/PixelifySans-Regular.ttf")

	# Buat CollisionShape2D jika belum ada
	if not has_node("CollisionShape2D"):
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = prompt_radius
		col.shape = circle
		add_child(col)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# SFX
	if ResourceLoader.exists("res://audio/sfx/dice_click.wav"):
		_sfx_stream = load("res://audio/sfx/dice_click.wav")

	_build_floating_prompt()
	_set_prompt_visible(false, false)

# ══════════════════════════════════════════════════════════════════════
#  PIXEL ART ICON HELPERS (res://ui/Icons/Sprites/)
# ══════════════════════════════════════════════════════════════════════

func _get_attr_icon(region: Rect2) -> AtlasTexture:
	var path = "res://ui/Icons/Sprites/Attrs16x16TickOutline.png"
	if not ResourceLoader.exists(path):
		path = "res://ui/Icons/Sprites/Attrs16x16.png"
	if ResourceLoader.exists(path):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(path)
		atlas.region = region
		return atlas
	return null

func _get_icon_hp() -> AtlasTexture:
	return _get_attr_icon(Rect2(0, 0, 16, 16)) # Heart

func _get_icon_atk() -> AtlasTexture:
	return _get_attr_icon(Rect2(0, 16, 16, 16)) # Sword

func _get_icon_def() -> AtlasTexture:
	return _get_attr_icon(Rect2(16, 16, 16, 16)) # Shield

func _get_icon_spd() -> AtlasTexture:
	return _get_attr_icon(Rect2(0, 32, 16, 16)) # Boot / Speed

func _create_pixel_icon(tex: Texture2D, size: Vector2 = Vector2(16, 16)) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.custom_minimum_size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr

# ══════════════════════════════════════════════════════════════════════
#  ANIMATED IDLE SPRITE GENERATOR (GROUNDED SEJAJAR DENGAN NPC)
# ══════════════════════════════════════════════════════════════════════

func _create_player_idle_animated_sprite(is_archer: bool) -> Control:
	var tex_path = "res://Tiny Swords (Free Pack)/Units/Blue Units/Archer/Archer_Idle.png" if is_archer else "res://Tiny Swords (Free Pack)/Units/Blue Units/Pawn/Pawn_Idle.png"
	var total_frames = 6 if is_archer else 8
	var fps = 8.0

	if not ResourceLoader.exists(tex_path):
		return null

	var base_tex = load(tex_path)
	if not base_tex is Texture2D:
		return null

	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", fps)

	var frame_w: float = float(base_tex.get_width()) / float(total_frames)
	var frame_h: float = float(base_tex.get_height())

	for i in range(total_frames):
		var atlas := AtlasTexture.new()
		atlas.atlas = base_tex
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		frames.add_frame("idle", atlas)

	# Wrapper Control agar centered dan responsive dalam UI
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(110, 110)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var anim := AnimatedSprite2D.new()
	anim.name = "PlayerIdleAnim"
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.sprite_frames = frames
	anim.animation = "idle"
	anim.autoplay = "idle"
	anim.centered = true
	# Posisi dan skala sprite player yang diperbesar (1.42x) dan diturunkan ~13px agar grounded sejajar NPC
	anim.position = Vector2(55, 97)
	anim.scale = Vector2(1.42, 1.42)
	anim.play("idle")
	wrapper.add_child(anim)

	return wrapper

# ══════════════════════════════════════════════════════════════════════
#  FLOATING PROMPT DI ATAS PORTAL TILE
# ══════════════════════════════════════════════════════════════════════

func _build_floating_prompt() -> void:
	var anchor := Node2D.new()
	anchor.name = "UIAnchor"
	anchor.position = Vector2(0, -75)
	add_child(anchor)

	_prompt_ui = Control.new()
	_prompt_ui.name = "PromptUI"
	_prompt_ui.custom_minimum_size = Vector2(184, 46)
	_prompt_ui.position = Vector2(-92, -23)
	anchor.add_child(_prompt_ui)

	# Background Panel Capsule
	var panel := PanelContainer.new()
	panel.name = "PromptPanel"
	panel.custom_minimum_size = Vector2(184, 46)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.06, 0.08, 0.15, 0.92)
	sb_normal.border_color = Color(0.28, 0.78, 1.0, 0.88)
	sb_normal.set_border_width_all(2)
	sb_normal.set_corner_radius_all(10)
	sb_normal.content_margin_left = 10
	sb_normal.content_margin_right = 14
	sb_normal.content_margin_top = 6
	sb_normal.content_margin_bottom = 6
	sb_normal.shadow_size = 4
	sb_normal.shadow_color = Color(0, 0, 0, 0.45)
	panel.add_theme_stylebox_override("panel", sb_normal)

	# Layout horizontal: [E Tooltip Icon] + [Text Label]
	var hbox := HBoxContainer.new()
	hbox.name = "ContentHBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# --- 1. E TOOLTIP ICON (White Theme) ---
	var key_texture: Texture2D = null
	if ResourceLoader.exists("res://ui/e_key_icon.png"):
		key_texture = load("res://ui/e_key_icon.png")

	if key_texture:
		var icon_rect := TextureRect.new()
		icon_rect.name = "EKeyIcon"
		icon_rect.texture = key_texture
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon_rect)
		_key_icon_node = icon_rect
	else:
		var key_box := PanelContainer.new()
		key_box.name = "EKeyBox"
		key_box.custom_minimum_size = Vector2(26, 26)

		var sb_key := StyleBoxFlat.new()
		sb_key.bg_color = Color(0.96, 0.97, 0.99, 1.0)
		sb_key.border_color = Color(0.2, 0.25, 0.35, 1.0)
		sb_key.border_width_left = 2
		sb_key.border_width_top = 2
		sb_key.border_width_right = 2
		sb_key.border_width_bottom = 4
		sb_key.border_color_bottom = Color(0.75, 0.8, 0.88, 1.0)
		sb_key.set_corner_radius_all(5)
		key_box.add_theme_stylebox_override("panel", sb_key)

		var key_lbl := Label.new()
		key_lbl.text = "E"
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if font_bold:
			key_lbl.add_theme_font_override("font", font_bold)
		key_lbl.add_theme_font_size_override("font_size", 16)
		key_lbl.add_theme_color_override("font_color", Color(0.08, 0.1, 0.16, 1.0))
		key_box.add_child(key_lbl)
		hbox.add_child(key_box)
		_key_icon_node = key_box

	# --- 2. ACTION TEXT (Pixelify Sans) ---
	var action_lbl := Label.new()
	action_lbl.name = "ActionLabel"
	action_lbl.text = prompt_label_text
	action_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font_bold:
		action_lbl.add_theme_font_override("font", font_bold)
	action_lbl.add_theme_font_size_override("font_size", 17)
	action_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	action_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	action_lbl.add_theme_constant_override("shadow_offset_y", 1)
	hbox.add_child(action_lbl)

	_prompt_ui.add_child(panel)

	# Transparent button overlay for mouse interaction
	var btn := Button.new()
	btn.name = "OverlayButton"
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var sb_empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", sb_empty)
	btn.add_theme_stylebox_override("hover", sb_empty)
	btn.add_theme_stylebox_override("pressed", sb_empty)
	btn.add_theme_stylebox_override("focus", sb_empty)

	btn.mouse_entered.connect(func():
		var sb_hover: StyleBoxFlat = sb_normal.duplicate()
		sb_hover.bg_color = Color(0.12, 0.18, 0.32, 0.96)
		sb_hover.border_color = Color(0.96, 0.82, 0.35, 1.0)
		panel.add_theme_stylebox_override("panel", sb_hover)
		action_lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.65, 1.0))
	)
	btn.mouse_exited.connect(func():
		panel.add_theme_stylebox_override("panel", sb_normal)
		action_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	)
	btn.button_down.connect(func():
		if _key_icon_node:
			_key_icon_node.position.y += 2
	)
	btn.button_up.connect(func():
		if _key_icon_node:
			_key_icon_node.position.y -= 2
	)
	btn.pressed.connect(_on_prompt_interacted)

	_prompt_ui.add_child(btn)

func _process(_delta: float) -> void:
	if _is_modal_open:
		return

	var nearest_dist := 999999.0
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		players = get_tree().get_nodes_in_group("player")

	if players.is_empty() and get_parent() != null:
		for child in get_parent().get_children():
			if child is CharacterBody2D:
				var d = global_position.distance_to(child.global_position)
				if d < nearest_dist:
					nearest_dist = d
	else:
		for p in players:
			if p is Node2D:
				var d = global_position.distance_to(p.global_position)
				if d < nearest_dist:
					nearest_dist = d

	var near := (nearest_dist <= prompt_radius)
	if near != is_player_near:
		is_player_near = near
		_set_prompt_visible(is_player_near, true)

	if _prompt_ui and _prompt_ui.visible:
		var anchor = get_node_or_null("UIAnchor")
		if anchor:
			anchor.position.y = -75.0 + sin(Time.get_ticks_msec() * 0.005) * 4.0

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D or body.is_in_group("players") or body.is_in_group("player"):
		is_player_near = true
		_set_prompt_visible(true, true)

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D or body.is_in_group("players") or body.is_in_group("player"):
		pass

func _set_prompt_visible(show_it: bool, animate: bool) -> void:
	if not _prompt_ui:
		return
	if show_it and not _is_modal_open:
		_prompt_ui.visible = true
		if animate:
			var t := create_tween()
			t.tween_property(_prompt_ui, "modulate:a", 1.0, 0.2).from(0.0)
			t.parallel().tween_property(_prompt_ui, "scale", Vector2.ONE, 0.2).from(Vector2(0.85, 0.85))
		else:
			_prompt_ui.modulate.a = 1.0
			_prompt_ui.scale = Vector2.ONE
	else:
		if animate and _prompt_ui.visible:
			var t := create_tween()
			t.tween_property(_prompt_ui, "modulate:a", 0.0, 0.15)
			t.chain().tween_callback(func(): _prompt_ui.visible = false)
		else:
			_prompt_ui.visible = false
			_prompt_ui.modulate.a = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if _is_modal_open:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close_modal()
		return

	if not is_player_near or _is_transitioning:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			get_viewport().set_input_as_handled()
			_on_prompt_interacted()

func _play_sfx() -> void:
	if _sfx_stream:
		var p := AudioStreamPlayer.new()
		p.stream = _sfx_stream
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

# ══════════════════════════════════════════════════════════════════════
#  PARTY & NPC QUERY HELPERS
# ══════════════════════════════════════════════════════════════════════

## Cari NPC yang sedang mengikuti player (is_following == true)
func _get_following_npc() -> Node:
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if is_instance_valid(npc) and npc.get("is_following") == true:
			return npc
	return null

## Ambil data player aktif (Pawn atau Archer)
func _get_active_player_info() -> Dictionary:
	var players = get_tree().get_nodes_in_group("players")
	var active_node: Node2D = null

	for p in players:
		if is_instance_valid(p) and p.get("is_active_character") == true:
			active_node = p
			break

	if active_node == null and players.size() > 0:
		active_node = players[0]

	var char_name: String = "Pawn"
	if active_node:
		var n = active_node.get("character_name")
		if n != null and str(n) != "":
			char_name = str(n)
		else:
			char_name = active_node.name

	var is_archer = char_name.to_lower().contains("archer")
	var role = "Ranger" if is_archer else "Warrior"
	var avatar_path = "res://ui/avatar_archer.png" if is_archer else "res://ui/avatar_pawn.png"
	var avatar_tex: Texture2D = null
	if ResourceLoader.exists(avatar_path):
		avatar_tex = load(avatar_path)

	return {
		"node": active_node,
		"name": char_name,
		"role": role,
		"is_archer": is_archer,
		"avatar": avatar_tex,
		"hp": 100,
		"max_hp": 100,
		"stamina": 100,
		"max_stamina": 100,
		"atk": 20,
		"def": 10,
		"spd": 10,
	}

# ══════════════════════════════════════════════════════════════════════
#  PRE-BATTLE MODAL DIALOG (GUARANTEED CENTERED VIA CenterContainer)
# ══════════════════════════════════════════════════════════════════════

func _on_prompt_interacted() -> void:
	if _is_modal_open or _is_transitioning:
		return
	_play_sfx()
	_open_modal()

func _open_modal() -> void:
	_is_modal_open = true
	_set_prompt_visible(false, false)

	if _modal_canvas == null:
		_modal_canvas = CanvasLayer.new()
		_modal_canvas.name = "PreBattleModalLayer"
		_modal_canvas.layer = 92
		add_child(_modal_canvas)

	for c in _modal_canvas.get_children():
		c.queue_free()

	# Root Fullscreen Control
	var root_ctrl := Control.new()
	root_ctrl.name = "ModalRoot"
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_canvas.add_child(root_ctrl)

	# 1. Black Fade Background Overlay (Full Screen)
	_modal_overlay = ColorRect.new()
	_modal_overlay.name = "ModalDimOverlay"
	_modal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.color = Color(0, 0, 0, 0.75)
	_modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_modal()
	)
	root_ctrl.add_child(_modal_overlay)

	# 2. CenterContainer (Memastikan 100% tepat di tengah layar secara matematis)
	var center_container := CenterContainer.new()
	center_container.name = "CenterContainer"
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(center_container)

	# 3. Bangun card sesuai ada/tidaknya follower NPC
	var following_npc = _get_following_npc()
	var active_player = _get_active_player_info()

	if following_npc == null:
		_build_warning_modal(center_container)
	else:
		_build_party_battle_modal(center_container, active_player, following_npc)

	# Animate Modal In (Zoom & Fade dari tengah)
	_modal_overlay.modulate.a = 0.0
	_modal_card.modulate.a = 0.0
	_modal_card.scale = Vector2(0.9, 0.9)
	_modal_card.pivot_offset = _modal_card.custom_minimum_size / 2.0

	var t := create_tween().set_parallel(true)
	t.tween_property(_modal_overlay, "modulate:a", 1.0, 0.18)
	t.tween_property(_modal_card, "modulate:a", 1.0, 0.22)
	t.tween_property(_modal_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close_modal() -> void:
	if not _is_modal_open:
		return
	_is_modal_open = false
	_play_sfx()

	if _modal_card and _modal_overlay:
		var t := create_tween().set_parallel(true)
		t.tween_property(_modal_overlay, "modulate:a", 0.0, 0.15)
		t.tween_property(_modal_card, "modulate:a", 0.0, 0.15)
		t.tween_property(_modal_card, "scale", Vector2(0.9, 0.9), 0.15)
		t.chain().tween_callback(func():
			if _modal_canvas:
				for c in _modal_canvas.get_children():
					c.queue_free()
			if is_player_near:
				_set_prompt_visible(true, true)
		)
	else:
		if is_player_near:
			_set_prompt_visible(true, true)

# ── Modal Mode A: No NPC Following (Warning) ──────────────────────────

func _build_warning_modal(parent_container: Node) -> void:
	_modal_card = PanelContainer.new()
	_modal_card.name = "WarningCard"
	_modal_card.custom_minimum_size = Vector2(520, 290)
	_modal_card.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.18, 0.98)
	sb.border_color = Color(0.96, 0.72, 0.20, 1.0) # Amber warning glow
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(24)
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.7)
	_modal_card.add_theme_stylebox_override("panel", sb)
	parent_container.add_child(_modal_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_modal_card.add_child(vbox)

	# Title Banner with Pixel Art Icon
	var title_hbox := HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(title_hbox)

	var warn_icon := _create_pixel_icon(_get_icon_def(), Vector2(26, 26))
	warn_icon.modulate = Color(1.0, 0.75, 0.2, 1.0)
	title_hbox.add_child(warn_icon)

	var title := Label.new()
	title.text = "COMPANION REQUIRED"
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.98, 0.75, 0.25, 1.0))
	title_hbox.add_child(title)

	# Divider line
	var div := HSeparator.new()
	div.add_theme_stylebox_override("separator", _create_line_style(Color(0.96, 0.72, 0.20, 0.4)))
	vbox.add_child(div)

	# Message body
	var desc := Label.new()
	desc.text = "You cannot enter the battle portal alone!\n\nPlease recruit a companion from your rolled NPCs:\n1. Roll an NPC using the Dice System.\n2. Right-Click any NPC in the overworld to make them follow you.\n3. Return here together to start the battle!"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_regular:
		desc.add_theme_font_override("font", font_regular)
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98, 0.95))
	vbox.add_child(desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Button Dismiss
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)

	var ok_btn := Button.new()
	ok_btn.text = "UNDERSTOOD"
	ok_btn.custom_minimum_size = Vector2(170, 42)
	ok_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font_bold:
		ok_btn.add_theme_font_override("font", font_bold)
	ok_btn.add_theme_font_size_override("font_size", 15)

	var sb_btn := StyleBoxFlat.new()
	sb_btn.bg_color = Color(0.18, 0.24, 0.38, 0.95)
	sb_btn.border_color = Color(0.96, 0.72, 0.20, 0.9)
	sb_btn.set_border_width_all(2)
	sb_btn.set_corner_radius_all(8)
	ok_btn.add_theme_stylebox_override("normal", sb_btn)

	var sb_btn_h := sb_btn.duplicate()
	sb_btn_h.bg_color = Color(0.25, 0.32, 0.50, 1.0)
	sb_btn_h.border_color = Color(1.0, 0.85, 0.40, 1.0)
	ok_btn.add_theme_stylebox_override("hover", sb_btn_h)

	ok_btn.pressed.connect(_close_modal)
	btn_box.add_child(ok_btn)

# ── Modal Mode B: Party Battle Preview (Player + Followed NPC) ─────────

func _build_party_battle_modal(parent_container: Node, player_info: Dictionary, npc_node: Node) -> void:
	_modal_card = PanelContainer.new()
	_modal_card.name = "PartyPreviewCard"
	_modal_card.custom_minimum_size = Vector2(740, 420)
	_modal_card.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.16, 0.98)
	sb.border_color = Color(0.35, 0.78, 1.0, 0.9) # Glowing cyan border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(20)
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.75)
	_modal_card.add_theme_stylebox_override("panel", sb)
	parent_container.add_child(_modal_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_modal_card.add_child(vbox)

	# --- Header Title & Bigger Close Button at Top-Right Edge ---
	var header_bar := Control.new()
	header_bar.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(header_bar)

	# Title terpusat tanpa icon pedang di tepi
	var title := Label.new()
	title.text = "READY FOR BATTLE"
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	header_bar.add_child(title)

	# Tombol X lebih besar di pojok kanan atas
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_top = 0.5
	close_btn.anchor_bottom = 0.5
	close_btn.offset_left = -36.0
	close_btn.offset_right = 0.0
	close_btn.offset_top = -18.0
	close_btn.offset_bottom = 18.0
	close_btn.flat = true
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if ResourceLoader.exists("res://ui/close_btn.png"):
		close_btn.icon = load("res://ui/close_btn.png")
		close_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		close_btn.expand_icon = true
	else:
		close_btn.text = "X"
		if font_bold:
			close_btn.add_theme_font_override("font", font_bold)
		close_btn.add_theme_font_size_override("font_size", 20)
		close_btn.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	close_btn.pressed.connect(_close_modal)
	header_bar.add_child(close_btn)

	var sub := Label.new()
	sub.text = "Deploying active leader and companion into the portal"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_regular:
		sub.add_theme_font_override("font", font_regular)
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.68, 0.78, 0.90, 0.90))
	vbox.add_child(sub)

	# Divider line
	var div := HSeparator.new()
	div.add_theme_stylebox_override("separator", _create_line_style(Color(0.35, 0.78, 1.0, 0.35)))
	vbox.add_child(div)

	# --- Side-by-Side Character Cards ---
	var side_by_side := HBoxContainer.new()
	side_by_side.name = "SideBySideCards"
	side_by_side.alignment = BoxContainer.ALIGNMENT_CENTER
	side_by_side.add_theme_constant_override("separation", 16)
	side_by_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(side_by_side)

	# 1. Left Card: Active Player (Pawn / Archer) dengan IDLE ANIMATION GROUNDED!
	var is_archer: bool = player_info.get("is_archer", false)
	var player_idle_anim := _create_player_idle_animated_sprite(is_archer)

	var player_card = _build_character_profile_card(
		"LEADER",
		player_info.name,
		player_info.role,
		Color(0.28, 0.78, 1.0, 1.0),
		player_info.avatar,
		player_info.hp,
		player_info.atk,
		player_info.def,
		player_info.spd,
		player_idle_anim
	)
	side_by_side.add_child(player_card)

	# Synergy Link Icon / Divider in Center
	var center_badge := VBoxContainer.new()
	center_badge.alignment = BoxContainer.ALIGNMENT_CENTER
	center_badge.custom_minimum_size = Vector2(28, 0)
	center_badge.add_theme_constant_override("separation", 6)

	var icon_s := _create_pixel_icon(_get_icon_atk(), Vector2(20, 20))
	center_badge.add_child(icon_s)

	var plus_lbl := Label.new()
	plus_lbl.text = "+"
	plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		plus_lbl.add_theme_font_override("font", font_bold)
	plus_lbl.add_theme_font_size_override("font_size", 18)
	plus_lbl.add_theme_color_override("font_color", Color(0.96, 0.82, 0.35, 0.9))
	center_badge.add_child(plus_lbl)

	var icon_d := _create_pixel_icon(_get_icon_def(), Vector2(20, 20))
	center_badge.add_child(icon_d)

	side_by_side.add_child(center_badge)

	# 2. Right Card: Followed NPC Companion
	var npc_data: Dictionary = npc_node.get("character_data") if npc_node.get("character_data") != null else {}
	var npc_name: String = npc_data.get("name", "Companion")
	var npc_tier: String = npc_data.get("tier", "Common")
	var npc_tier_color := _get_tier_color(npc_tier)

	var npc_stats = BattleState.TIER_STATS.get(npc_tier, BattleState.TIER_STATS["Common"])
	var npc_avatar: Texture2D = null
	var sprite_node = npc_node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite_node and sprite_node.texture:
		npc_avatar = sprite_node.texture
	elif ResourceLoader.exists(npc_data.get("image", "")):
		npc_avatar = load(npc_data.get("image"))

	var companion_card = _build_character_profile_card(
		"COMPANION",
		npc_name,
		npc_tier.to_upper(),
		npc_tier_color,
		npc_avatar,
		npc_stats["hp"],
		npc_stats["atk"],
		npc_stats["def"],
		npc_stats["spd"],
		null # Menggunakan texture sprite NPC
	)
	side_by_side.add_child(companion_card)

	# --- Bottom Action Bar: START BATTLE CENTERED & GREEN (Cancel removed) ---
	var action_bar := HBoxContainer.new()
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(action_bar)

	var start_btn := Button.new()
	start_btn.text = "START BATTLE"
	start_btn.custom_minimum_size = Vector2(240, 48)
	start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font_bold:
		start_btn.add_theme_font_override("font", font_bold)
	start_btn.add_theme_font_size_override("font_size", 17)

	# Warna Hijau RPG Vibrant
	var sb_s := StyleBoxFlat.new()
	sb_s.bg_color = Color(0.12, 0.52, 0.28, 0.98) # Vibrant Emerald Green
	sb_s.border_color = Color(0.35, 0.92, 0.52, 1.0) # Bright Mint Glow Border
	sb_s.set_border_width_all(2)
	sb_s.set_corner_radius_all(10)
	sb_s.shadow_size = 8
	sb_s.shadow_color = Color(0.1, 0.45, 0.2, 0.4)
	start_btn.add_theme_stylebox_override("normal", sb_s)

	var sb_s_h := sb_s.duplicate()
	sb_s_h.bg_color = Color(0.18, 0.65, 0.35, 1.0) # Brighter Green on hover
	sb_s_h.border_color = Color(0.65, 1.0, 0.75, 1.0)
	sb_s_h.shadow_size = 12
	sb_s_h.shadow_color = Color(0.2, 0.7, 0.3, 0.6)
	start_btn.add_theme_stylebox_override("hover", sb_s_h)

	var sb_s_p := sb_s.duplicate()
	sb_s_p.bg_color = Color(0.08, 0.38, 0.18, 1.0)
	sb_s_p.border_color = Color(0.8, 1.0, 0.85, 1.0)
	start_btn.add_theme_stylebox_override("pressed", sb_s_p)

	start_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	start_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

	start_btn.pressed.connect(func():
		_execute_start_battle(player_info, npc_data)
	)
	action_bar.add_child(start_btn)

## Profile Card Helper (Avatar Besar di Kiri + Stats di Samping Kanan)
func _build_character_profile_card(role_badge: String, char_name: String, sub_tag: String,
		accent_col: Color, avatar_tex: Texture2D, hp: int, atk: int, def_val: int, spd: int,
		custom_avatar_node: Node = null) -> Control:

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 225)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.20, 0.94)
	sb.border_color = accent_col.lerp(Color.WHITE, 0.15)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Top: Role / Status Badge (dengan margin lebih lega agar huruf pertama tidak terpotong)
	var badge_box := HBoxContainer.new()
	badge_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(badge_box)

	var badge_panel := PanelContainer.new()
	var sb_b := StyleBoxFlat.new()
	sb_b.bg_color = accent_col.lerp(Color.BLACK, 0.65)
	sb_b.border_color = accent_col
	sb_b.set_border_width_all(1)
	sb_b.set_corner_radius_all(6)
	sb_b.content_margin_left = 12
	sb_b.content_margin_right = 12
	sb_b.content_margin_top = 3
	sb_b.content_margin_bottom = 3
	badge_panel.add_theme_stylebox_override("panel", sb_b)

	var badge_lbl := Label.new()
	badge_lbl.text = role_badge
	if font_bold:
		badge_lbl.add_theme_font_override("font", font_bold)
	badge_lbl.add_theme_font_size_override("font_size", 12)
	badge_lbl.add_theme_color_override("font_color", accent_col)
	badge_panel.add_child(badge_lbl)
	badge_box.add_child(badge_panel)

	# Horizontal Layout: [Avatar Besar di Kiri] + [Nama & Stats di Kanan]
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 14)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_hbox)

	# 1. Big Avatar Frame (110x110) dengan clipping rapi
	var avatar_frame := PanelContainer.new()
	avatar_frame.custom_minimum_size = Vector2(110, 110)
	avatar_frame.clip_contents = true # Memastikan animasi sprite terpotong rapi sesuai rounded box
	var sb_af := StyleBoxFlat.new()
	sb_af.bg_color = Color(0.05, 0.07, 0.12, 1.0)
	sb_af.border_color = accent_col.lerp(Color.BLACK, 0.25)
	sb_af.set_border_width_all(2)
	sb_af.set_corner_radius_all(12)
	avatar_frame.add_theme_stylebox_override("panel", sb_af)

	if custom_avatar_node != null:
		# Gunakan custom AnimatedSprite2D untuk idle animation (Player)
		avatar_frame.add_child(custom_avatar_node)
	elif avatar_tex:
		# Gunakan TextureRect statis (untuk NPC)
		var rect := TextureRect.new()
		rect.texture = avatar_tex
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(100, 100)
		avatar_frame.add_child(rect)

	content_hbox.add_child(avatar_frame)

	# 2. Right Side: Nama, Sub-tag & Stats Baris
	var details_vbox := VBoxContainer.new()
	details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_vbox.add_theme_constant_override("separation", 4)
	content_hbox.add_child(details_vbox)

	var name_lbl := Label.new()
	name_lbl.text = char_name
	if font_bold:
		name_lbl.add_theme_font_override("font", font_bold)
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	details_vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = sub_tag
	if font_regular:
		sub_lbl.add_theme_font_override("font", font_regular)
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", accent_col)
	details_vbox.add_child(sub_lbl)

	var div_mini := HSeparator.new()
	div_mini.add_theme_stylebox_override("separator", _create_line_style(accent_col.lerp(Color.BLACK, 0.5)))
	details_vbox.add_child(div_mini)

	# Stats Rows berdampingan dengan icon pixel art
	var hp_row := _create_pixel_stat_row(_get_icon_hp(), "HP", "%d / %d" % [hp, hp], Color(0.4, 0.9, 0.5))
	var atk_row := _create_pixel_stat_row(_get_icon_atk(), "ATK", "%d" % atk, Color(0.95, 0.75, 0.35))
	var def_row := _create_pixel_stat_row(_get_icon_def(), "DEF", "%d" % def_val, Color(0.4, 0.75, 1.0))
	var spd_row := _create_pixel_stat_row(_get_icon_spd(), "SPD", "%d" % spd, Color(0.4, 0.8, 1.0))

	details_vbox.add_child(hp_row)
	details_vbox.add_child(atk_row)
	details_vbox.add_child(def_row)
	details_vbox.add_child(spd_row)

	return card

func _create_pixel_stat_row(icon_tex: Texture2D, lbl_text: String, val_text: String, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	if icon_tex:
		var tr := _create_pixel_icon(icon_tex, Vector2(20, 20))
		h.add_child(tr)

	var l := Label.new()
	l.text = lbl_text
	if font_regular:
		l.add_theme_font_override("font", font_regular)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88, 0.9))
	h.add_child(l)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var v := Label.new()
	v.text = val_text
	if font_bold:
		v.add_theme_font_override("font", font_bold)
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_color_override("font_color", col)
	h.add_child(v)
	return h

func _create_line_style(color: Color) -> StyleBoxFlat:
	var l := StyleBoxFlat.new()
	l.bg_color = color
	l.set_border_width_all(0)
	l.content_margin_top = 1
	l.content_margin_bottom = 1
	return l

func _get_tier_color(tier: String) -> Color:
	match tier:
		"Common": return Color(0.80, 0.84, 0.88, 1.0)
		"Uncommon": return Color(0.29, 0.87, 0.50, 1.0)
		"Rare": return Color(0.22, 0.74, 0.97, 1.0)
		"Epic": return Color(0.66, 0.33, 0.97, 1.0)
		"Legendary": return Color(0.98, 0.75, 0.14, 1.0)
		"Mythic": return Color(0.96, 0.25, 0.37, 1.0)
		"Secret": return Color(0.93, 0.28, 0.60, 1.0)
		_: return Color(0.7, 0.8, 0.9, 1.0)

# ══════════════════════════════════════════════════════════════════════
#  EXECUTE BATTLE TRANSITION
# ══════════════════════════════════════════════════════════════════════

func _execute_start_battle(player_info: Dictionary, npc_data: Dictionary) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_play_sfx()

	print("[PortalPrompt] Starting battle with Leader (%s) and Companion (%s)" % [
		player_info.name, npc_data.get("name", "Companion")
	])

	var player_fighter_data: Dictionary = {
		"name": npc_data.get("name", "Companion"),
		"tier": npc_data.get("tier", "Common"),
		"image": npc_data.get("image", ""),
		"id": npc_data.get("id", "team"),
		"leader": player_info.name,
		"companion": npc_data.get("name", "Companion"),
		"role": player_info.role,
		"avatar": "res://ui/avatar_archer.png" if player_info.name.to_lower().contains("archer") else "res://ui/avatar_pawn.png"
	}

	var enemy_data: Dictionary = {}
	if BattleManagerClass.ENEMY_PRESETS.has(enemy_preset_key):
		enemy_data = BattleManagerClass.ENEMY_PRESETS[enemy_preset_key]
	else:
		enemy_data = BattleManagerClass.ENEMY_PRESETS["slime"]

	var return_scene: String = "res://Overworld.tscn"
	if get_tree() and get_tree().current_scene and get_tree().current_scene.scene_file_path != "":
		return_scene = get_tree().current_scene.scene_file_path

	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		bm.start_battle(self, player_fighter_data, enemy_data, return_scene)
	else:
		var bm_fallback = BattleManagerClass.new()
		bm_fallback.start_battle(self, player_fighter_data, enemy_data, return_scene)
