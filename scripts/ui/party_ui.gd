extends CanvasLayer

signal character_switched(player_index: int)

@export var player_1: CharacterBody2D
@export var player_2: CharacterBody2D
@export var camera: Camera2D

var active_index: int = 1

var font_regular: Font = null
var font_bold: Font = null

var card_1: Button
var card_2: Button

var style_active_1: StyleBoxFlat
var style_inactive_1: StyleBoxFlat
var style_active_2: StyleBoxFlat
var style_inactive_2: StyleBoxFlat

func _ready() -> void:
	layer = 80
	_load_fonts()
	_find_references()
	_create_ui()
	_apply_active_state()

func _load_fonts() -> void:
	if ResourceLoader.exists("res://fonts/PixelifySans-Regular.ttf"):
		font_regular = load("res://fonts/PixelifySans-Regular.ttf")
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		font_bold = load("res://fonts/PixelifySans-Bold.ttf")

	if font_regular == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Pixelify Sans", "PixelifySans"])
		font_regular = sys
	if font_bold == null:
		var sys_b := SystemFont.new()
		sys_b.font_names = PackedStringArray(["Pixelify Sans", "PixelifySans"])
		sys_b.font_weight = 700
		font_bold = sys_b

func _find_references() -> void:
	if player_1 == null and get_parent() != null:
		player_1 = get_parent().get_node_or_null("Player") as CharacterBody2D
	if player_2 == null and get_parent() != null:
		player_2 = get_parent().get_node_or_null("Player2") as CharacterBody2D
	if camera == null and get_parent() != null:
		camera = get_parent().get_node_or_null("Camera2D") as Camera2D

func _create_ui() -> void:
	var control := Control.new()
	control.name = "PartyControl"
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)

	var v_box := VBoxContainer.new()
	v_box.name = "PartyList"
	v_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v_box.add_theme_constant_override("separation", 10)
	
	# Posisikan di sisi kanan layar secara vertikal terpusat (ala Genshin Impact)
	v_box.anchor_left = 1.0
	v_box.anchor_right = 1.0
	v_box.anchor_top = 0.5
	v_box.anchor_bottom = 0.5
	v_box.offset_left = -196.0
	v_box.offset_right = -16.0
	v_box.offset_top = -60.0
	v_box.offset_bottom = 60.0
	control.add_child(v_box)

	# Buat StyleBox untuk Card 1 (Pawn - aksen biru/emas)
	style_active_1 = _create_card_style(
		Color(0.10, 0.16, 0.28, 0.90),
		Color(0.35, 0.75, 1.0, 1.0),
		2,
		Color(0.2, 0.6, 1.0, 0.4)
	)
	style_inactive_1 = _create_card_style(
		Color(0.08, 0.11, 0.18, 0.65),
		Color(0.25, 0.35, 0.5, 0.4),
		1,
		Color(0, 0, 0, 0)
	)

	# Buat StyleBox untuk Card 2 (Archer - aksen hijau/toska)
	style_active_2 = _create_card_style(
		Color(0.08, 0.22, 0.24, 0.90),
		Color(0.25, 0.95, 0.85, 1.0),
		2,
		Color(0.2, 0.9, 0.7, 0.4)
	)
	style_inactive_2 = _create_card_style(
		Color(0.08, 0.11, 0.18, 0.65),
		Color(0.25, 0.45, 0.45, 0.4),
		1,
		Color(0, 0, 0, 0)
	)

	# Card 1: Pawn
	var avatar_pawn_tex := load("res://ui/avatar_pawn.png") if ResourceLoader.exists("res://ui/avatar_pawn.png") else null
	card_1 = _build_character_card("Pawn", "Warrior", "1", avatar_pawn_tex, 1)
	v_box.add_child(card_1)

	# Card 2: Archer
	var avatar_archer_tex := load("res://ui/avatar_archer.png") if ResourceLoader.exists("res://ui/avatar_archer.png") else null
	card_2 = _build_character_card("Archer", "Ranger", "2", avatar_archer_tex, 2)
	v_box.add_child(card_2)

func _create_card_style(bg_col: Color, border_col: Color, border_w: int, shadow_col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if shadow_col.a > 0.0:
		sb.shadow_color = shadow_col
		sb.shadow_size = 6
	return sb

func _build_character_card(char_name: String, role: String, key_num: String, avatar_tex: Texture2D, index: int) -> Button:
	var btn := Button.new()
	btn.name = "Card_" + char_name
	btn.custom_minimum_size = Vector2(176, 50)
	btn.focus_mode = Control.FOCUS_NONE

	# Content layout
	var hbox := HBoxContainer.new()
	hbox.name = "HBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 6
	hbox.offset_right = -8
	hbox.offset_top = 4
	hbox.offset_bottom = -4
	hbox.add_theme_constant_override("separation", 8)
	btn.add_child(hbox)

	# Avatar Container with clip_contents to ensure no pixels spill out
	var avatar_container := Control.new()
	avatar_container.name = "AvatarContainer"
	avatar_container.custom_minimum_size = Vector2(40, 40)
	avatar_container.clip_contents = true
	avatar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(avatar_container)

	# Avatar TextureRect
	var avatar_rect := TextureRect.new()
	avatar_rect.name = "Avatar"
	avatar_rect.texture = avatar_tex
	avatar_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_container.add_child(avatar_rect)

	# Name + Role VBox
	var text_vbox := VBoxContainer.new()
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.add_theme_constant_override("separation", -2)
	hbox.add_child(text_vbox)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = char_name
	if font_bold != null:
		name_label.add_theme_font_override("font", font_bold)
	name_label.add_theme_font_size_override("font_size", 14)
	text_vbox.add_child(name_label)

	var role_label := Label.new()
	role_label.name = "RoleLabel"
	role_label.text = role
	if font_regular != null:
		role_label.add_theme_font_override("font", font_regular)
	role_label.add_theme_font_size_override("font_size", 10)
	role_label.modulate = Color(0.65, 0.75, 0.85)
	text_vbox.add_child(role_label)

	# Keycap Badge [ 1 ] / [ 2 ]
	var key_panel := PanelContainer.new()
	key_panel.name = "Keycap"
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key_sb := StyleBoxFlat.new()
	key_sb.bg_color = Color(0.12, 0.16, 0.22, 0.9)
	key_sb.border_color = Color(0.4, 0.55, 0.7, 0.8)
	key_sb.set_border_width_all(1)
	key_sb.set_corner_radius_all(5)
	key_sb.content_margin_left = 6
	key_sb.content_margin_right = 6
	key_sb.content_margin_top = 2
	key_sb.content_margin_bottom = 2
	key_panel.add_theme_stylebox_override("panel", key_sb)

	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.text = key_num
	if font_bold != null:
		key_label.add_theme_font_override("font", font_bold)
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_panel.add_child(key_label)
	hbox.add_child(key_panel)

	btn.pressed.connect(func(): switch_to_character(index))
	return btn

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 or event.keycode == KEY_KP_1:
			switch_to_character(1)
		elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
			switch_to_character(2)

func switch_to_character(index: int) -> void:
	if index == active_index:
		return
		
	active_index = index
	
	if active_index == 1:
		if player_1 != null and is_instance_valid(player_1):
			player_1.set_active(true)
		if player_2 != null and is_instance_valid(player_2):
			player_2.set_active(false)
		if camera != null and is_instance_valid(camera) and camera.has_method("set_target"):
			camera.set_target(player_1, true)
	elif active_index == 2:
		if player_1 != null and is_instance_valid(player_1):
			player_1.set_active(false)
		if player_2 != null and is_instance_valid(player_2):
			player_2.set_active(true)
		if camera != null and is_instance_valid(camera) and camera.has_method("set_target"):
			camera.set_target(player_2, true)
			
	_apply_active_state()
	character_switched.emit(active_index)

func _apply_active_state() -> void:
	if card_1 == null or card_2 == null:
		return
		
	if active_index == 1:
		_set_card_style(card_1, style_active_1, 1.0, true)
		_set_card_style(card_2, style_inactive_2, 0.70, false)
		_animate_pop(card_1)
	else:
		_set_card_style(card_1, style_inactive_1, 0.70, false)
		_set_card_style(card_2, style_active_2, 1.0, true)
		_animate_pop(card_2)

func _set_card_style(btn: Button, style: StyleBoxFlat, alpha: float, is_active: bool) -> void:
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.modulate.a = alpha

func _animate_pop(btn: Button) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	btn.scale = Vector2(1.04, 1.04)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.2)
