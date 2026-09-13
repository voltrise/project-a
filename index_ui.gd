class_name IndexUI
extends CanvasLayer

## Index UI (Character Compendium)
## Displays all characters obtainable from the RNG roll system.
## Opens via the HUD button on the left of the screen.

signal opened
signal closed

@export var characters_file: String = "res://characters.json"
@export var tiers_file: String = "res://tiers.json"

const CARDS_PER_PAGE: int = 8

# Slot coordinates relative to the 990x730 book texture (cards comfortably inside parchment bounds)
const SLOT_POSITIONS: Array[Vector2] = [
	Vector2(104, 118), Vector2(284, 118),
	Vector2(104, 340), Vector2(284, 340),
	Vector2(578, 118), Vector2(758, 118),
	Vector2(578, 340), Vector2(758, 340)
]

const CARD_SIZE: Vector2 = Vector2(128, 190)

# Data
var characters: Array = []
var tiers: Dictionary = {}
var current_page: int = 0
var total_pages: int = 1
var is_open: bool = false

# Fonts & Textures
var font_bold: Font = null
var font_regular: Font = null
var tex_button: Texture2D = null
var tex_book: Texture2D = null
var tex_card_bg: Texture2D = null
var tex_close: Texture2D = null
var tex_arrow_left: Texture2D = null
var tex_arrow_right: Texture2D = null

# Audio
var sfx_hover: AudioStream = null
var sfx_click: AudioStream = null
var sfx_flip: AudioStream = null

static func load_texture_safe(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

static func load_audio_safe(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res
	return null

func _load_resources() -> void:
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		font_bold = load("res://fonts/PixelifySans-Bold.ttf")
	if ResourceLoader.exists("res://fonts/PixelifySans-Regular.ttf"):
		font_regular = load("res://fonts/PixelifySans-Regular.ttf")

	tex_button = load_texture_safe("res://ui/index_button.png")
	tex_book = load_texture_safe("res://ui/book_bg.png")
	tex_card_bg = load_texture_safe("res://ui/card_bg.png")
	tex_close = load_texture_safe("res://ui/close_btn.png")
	tex_arrow_left = load_texture_safe("res://ui/arrow_left.png")
	tex_arrow_right = load_texture_safe("res://ui/arrow_right.png")

	sfx_hover = load_audio_safe("res://audio/sfx/hover_pop.wav")
	sfx_click = load_audio_safe("res://audio/sfx/dice_click.wav")
	sfx_flip = load_audio_safe("res://audio/sfx/reel_tick.wav")

# Node references
var hud_button: TextureButton
var modal: Control
var dim_overlay: ColorRect
var book_container: Control
var title_label: Label
var slots_container: Control
var page_label: Label
var prev_btn: TextureButton
var next_btn: TextureButton
var close_btn: TextureButton

var audio_player: AudioStreamPlayer
var _tween: Tween

func _ready() -> void:
	layer = 92
	_load_resources()
	_load_data()
	_create_ui()
	_update_cards()

	# Listen to CharacterManager if new characters are rolled
	if typeof(CharacterManager) != TYPE_NIL and CharacterManager != null:
		if CharacterManager.has_signal("character_added"):
			CharacterManager.character_added.connect(_on_character_obtained)

	# Auto-close if RNG roll starts so it doesn't obstruct the gacha animation
	var roller := get_tree().root.find_child("RngRoller", true, false)
	if roller and roller.has_signal("roll_started"):
		roller.roll_started.connect(close)

func _load_data() -> void:
	# 1. Load characters
	if FileAccess.file_exists(characters_file):
		var f := FileAccess.open(characters_file, FileAccess.READ)
		var json := JSON.new()
		if json.parse(f.get_as_text()) == OK and json.data is Array:
			characters = json.data
		f.close()

	# 2. Load tiers
	if FileAccess.file_exists(tiers_file):
		var f := FileAccess.open(tiers_file, FileAccess.READ)
		var json := JSON.new()
		if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
			tiers = json.data
		f.close()

	total_pages = int(max(1, ceil(float(characters.size()) / float(CARDS_PER_PAGE))))

## Converts numeric chance into fraction notation with K/M abbreviations
## e.g. 2 -> "1/2", 850 -> "1/850", 1200 -> "1/1.2K", 10000 -> "1/10K", 1000000 -> "1/1M"
func format_chance(chance: int) -> String:
	if chance >= 1_000_000:
		var val: float = float(chance) / 1_000_000.0
		var s: String = String.num(val, 1) if fmod(val, 1.0) > 0.05 else str(int(val))
		return "1/" + s + "M"
	elif chance >= 1_000:
		var val: float = float(chance) / 1_000.0
		var s: String = String.num(val, 1) if fmod(val, 1.0) > 0.05 else str(int(val))
		return "1/" + s + "K"
	else:
		return "1/" + str(chance)

func _create_ui() -> void:
	# Audio player
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "IndexAudio"
	audio_player.volume_db = -4.0
	add_child(audio_player)

	# -------------------------------------------------------------
	# 1. HUD Button on the Left
	# -------------------------------------------------------------
	hud_button = TextureButton.new()
	hud_button.name = "IndexButton"
	hud_button.texture_normal = tex_button
	hud_button.ignore_texture_size = true
	hud_button.stretch_mode = TextureButton.STRETCH_SCALE
	hud_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hud_button.custom_minimum_size = Vector2(160, 50)
	
	# Position at middle-left of the screen
	hud_button.anchor_left = 0.0
	hud_button.anchor_right = 0.0
	hud_button.anchor_top = 0.5
	hud_button.anchor_bottom = 0.5
	hud_button.offset_left = 22.0
	hud_button.offset_top = -25.0
	hud_button.offset_right = 182.0
	hud_button.offset_bottom = 25.0
	hud_button.pivot_offset = Vector2(80, 25)
	
	# Connect button events
	hud_button.mouse_entered.connect(_on_hud_btn_hover)
	hud_button.mouse_exited.connect(_on_hud_btn_unhover)
	hud_button.button_down.connect(_on_hud_btn_down)
	hud_button.button_up.connect(_on_hud_btn_up)
	hud_button.pressed.connect(toggle)
	add_child(hud_button)

	# -------------------------------------------------------------
	# 2. Modal Window (Dim overlay + Book)
	# -------------------------------------------------------------
	modal = Control.new()
	modal.name = "IndexModal"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	modal.modulate.a = 0.0
	add_child(modal)

	# Dim background overlay
	dim_overlay = ColorRect.new()
	dim_overlay.name = "DimOverlay"
	dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_overlay.color = Color(0, 0, 0, 0.65)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	dim_overlay.gui_input.connect(_on_dim_overlay_input)
	modal.add_child(dim_overlay)

	# Centered book container
	book_container = Control.new()
	book_container.name = "BookContainer"
	book_container.custom_minimum_size = Vector2(990, 730)
	book_container.set_anchors_preset(Control.PRESET_CENTER)
	book_container.offset_left = -495.0
	book_container.offset_top = -365.0
	book_container.offset_right = 495.0
	book_container.offset_bottom = 365.0
	book_container.pivot_offset = Vector2(495, 365)
	# Scale 0.86 so it fits neatly in 720p height
	book_container.scale = Vector2(0.86, 0.86)
	modal.add_child(book_container)

	# Book background image
	var book_bg := TextureRect.new()
	book_bg.name = "BookBackground"
	book_bg.texture = tex_book
	book_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	book_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	book_bg.mouse_filter = Control.MOUSE_FILTER_PASS
	book_container.add_child(book_bg)

	# Centered Book Title "✦ INDEX ✦"
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.position = Vector2(345, 52)
	title_label.size = Vector2(300, 36)
	title_label.add_theme_font_override("font", font_bold)
	title_label.add_theme_font_size_override("font_size", 40)
	title_label.add_theme_color_override("font_color", Color(0.24, 0.15, 0.08, 1.0))
	title_label.add_theme_constant_override("outline_size", 4)
	title_label.add_theme_color_override("font_outline_color", Color(0.96, 0.88, 0.74, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.text = "✦ INDEX ✦"
	book_container.add_child(title_label)

	# Close button (top right of book)
	close_btn = TextureButton.new()
	close_btn.name = "CloseButton"
	close_btn.texture_normal = tex_close
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_SCALE
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.offset_left = 936.0
	close_btn.offset_top = 28.0
	close_btn.offset_right = 972.0
	close_btn.offset_bottom = 64.0
	close_btn.pivot_offset = Vector2(18, 18)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.mouse_entered.connect(func(): _animate_btn_hover(close_btn, true))
	close_btn.mouse_exited.connect(func(): _animate_btn_hover(close_btn, false))
	close_btn.pressed.connect(close)
	book_container.add_child(close_btn)

	# -------------------------------------------------------------
	# 3. Side Navigation Arrows (Center Left & Center Right of book)
	# -------------------------------------------------------------
	# Left arrow (vertically centered on left edge of book)
	prev_btn = TextureButton.new()
	prev_btn.name = "PrevButton"
	prev_btn.texture_normal = tex_arrow_left
	prev_btn.ignore_texture_size = true
	prev_btn.stretch_mode = TextureButton.STRETCH_SCALE
	prev_btn.custom_minimum_size = Vector2(40, 40)
	prev_btn.position = Vector2(14, 345)
	prev_btn.size = Vector2(40, 40)
	prev_btn.pivot_offset = Vector2(20, 20)
	prev_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	prev_btn.mouse_entered.connect(func(): _animate_btn_hover(prev_btn, true))
	prev_btn.mouse_exited.connect(func(): _animate_btn_hover(prev_btn, false))
	prev_btn.pressed.connect(_on_prev_page)
	book_container.add_child(prev_btn)

	# Right arrow (vertically centered on right edge of book)
	next_btn = TextureButton.new()
	next_btn.name = "NextButton"
	next_btn.texture_normal = tex_arrow_right
	next_btn.ignore_texture_size = true
	next_btn.stretch_mode = TextureButton.STRETCH_SCALE
	next_btn.custom_minimum_size = Vector2(40, 40)
	next_btn.position = Vector2(936, 345)
	next_btn.size = Vector2(40, 40)
	next_btn.pivot_offset = Vector2(20, 20)
	next_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	next_btn.mouse_entered.connect(func(): _animate_btn_hover(next_btn, true))
	next_btn.mouse_exited.connect(func(): _animate_btn_hover(next_btn, false))
	next_btn.pressed.connect(_on_next_page)
	book_container.add_child(next_btn)

	# Page label at bottom center near the ribbon
	page_label = Label.new()
	page_label.name = "PageLabel"
	page_label.position = Vector2(420, 642)
	page_label.size = Vector2(150, 28)
	page_label.add_theme_font_override("font", font_bold)
	page_label.add_theme_font_size_override("font_size", 16)
	page_label.add_theme_color_override("font_color", Color(0.24, 0.15, 0.08, 0.95))
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_label.text = "Page 1 / 3"
	book_container.add_child(page_label)

	# Container for the 8 character card slots
	slots_container = Control.new()
	slots_container.name = "SlotsContainer"
	slots_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book_container.add_child(slots_container)

	for i in range(CARDS_PER_PAGE):
		var card := _build_card_slot(i)
		card.position = SLOT_POSITIONS[i]
		slots_container.add_child(card)

## Builds a single reusable card slot Control
func _build_card_slot(slot_index: int) -> Control:
	var slot := Control.new()
	slot.name = "CardSlot_%d" % slot_index
	slot.custom_minimum_size = CARD_SIZE
	slot.size = CARD_SIZE

	# 1. Card parchment frame background
	var bg := TextureRect.new()
	bg.name = "CardBG"
	bg.texture = tex_card_bg
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bg)

	# 2. Character Appearance (Sprite image)
	var char_sprite := TextureRect.new()
	char_sprite.name = "CharSprite"
	char_sprite.position = Vector2(8, 18)
	char_sprite.size = Vector2(112, 114)
	char_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	char_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(char_sprite)

	# 3. Top-Right: Rarity Badge
	var rarity_label := Label.new()
	rarity_label.name = "RarityLabel"
	rarity_label.position = Vector2(8, 7)
	rarity_label.size = Vector2(112, 14)
	rarity_label.add_theme_font_override("font", font_bold)
	rarity_label.add_theme_font_size_override("font_size", 12)
	rarity_label.add_theme_constant_override("outline_size", 4)
	rarity_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slot.add_child(rarity_label)

	# 4. Top-Right: Chance Label
	var chance_label := Label.new()
	chance_label.name = "ChanceLabel"
	chance_label.position = Vector2(8, 21)
	chance_label.size = Vector2(112, 14)
	chance_label.add_theme_font_override("font", font_bold)
	chance_label.add_theme_font_size_override("font_size", 12)
	chance_label.add_theme_constant_override("outline_size", 4)
	chance_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	chance_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	chance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slot.add_child(chance_label)

	# 5. Top-Left: Status / Owned Count Badge
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.position = Vector2(8, 7)
	status_label.size = Vector2(50, 14)
	status_label.add_theme_font_override("font", font_bold)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_constant_override("outline_size", 4)
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	slot.add_child(status_label)

	# 6. Bottom Nameplate: Character Name
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.position = Vector2(6, 142)
	name_label.size = Vector2(116, 38)
	name_label.add_theme_font_override("font", font_bold)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.24, 0.15, 0.08, 1.0))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(name_label)

	return slot

## Refreshes the 8 cards based on current_page
func _update_cards() -> void:
	page_label.text = "Page %d / %d" % [current_page + 1, total_pages]
	prev_btn.visible = (current_page > 0)
	next_btn.visible = (current_page < total_pages - 1)

	var start_idx: int = current_page * CARDS_PER_PAGE
	for i in range(CARDS_PER_PAGE):
		var char_idx: int = start_idx + i
		var slot := slots_container.get_node_or_null("CardSlot_%d" % i) as Control
		if slot == null:
			continue

		if char_idx < characters.size():
			slot.visible = true
			var char_data: Dictionary = characters[char_idx]
			_populate_card(slot, char_data)
		else:
			slot.visible = false

func _populate_card(slot: Control, char_data: Dictionary) -> void:
	var char_sprite := slot.get_node("CharSprite") as TextureRect
	var rarity_label := slot.get_node("RarityLabel") as Label
	var chance_label := slot.get_node("ChanceLabel") as Label
	var status_label := slot.get_node("StatusLabel") as Label
	var name_label := slot.get_node("NameLabel") as Label

	# Name
	name_label.text = char_data.get("name", "Unknown")

	# Appearance / Texture
	var img_path: String = char_data.get("image", "")
	char_sprite.texture = load_texture_safe(img_path)

	# Rarity
	var tier_name: String = char_data.get("tier", "Common")
	rarity_label.text = tier_name.to_upper()
	var tier_info: Dictionary = tiers.get(tier_name, {})
	var tier_color_hex: String = tier_info.get("color", "#CBD5E1")
	rarity_label.add_theme_color_override("font_color", Color.from_string(tier_color_hex, Color.WHITE))

	# Chance with denominator conversion (>1000 => K / M)
	var chance_int: int = int(char_data.get("chance", 1))
	chance_label.text = format_chance(chance_int)

	# Check ownership in CharacterManager
	var is_owned: bool = false
	var count: int = 0
	var char_id: String = char_data.get("id", "")
	if typeof(CharacterManager) != TYPE_NIL and CharacterManager != null:
		is_owned = CharacterManager.has_character(char_id)
		count = CharacterManager.get_character_count(char_id)

	if is_owned:
		status_label.text = "x%d" % count
		status_label.visible = true
		char_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		status_label.text = ""
		status_label.visible = false
		# Still show appearance cleanly as requested
		char_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_prev_page() -> void:
	if current_page > 0:
		current_page -= 1
		_play_sound(sfx_flip, 1.1)
		_animate_page_turn(-1)

func _on_next_page() -> void:
	if current_page < total_pages - 1:
		current_page += 1
		_play_sound(sfx_flip, 0.95)
		_animate_page_turn(1)

func _animate_page_turn(dir: int) -> void:
	var t := create_tween()
	t.tween_property(slots_container, "modulate:a", 0.0, 0.08)
	t.tween_callback(_update_cards)
	t.tween_property(slots_container, "modulate:a", 1.0, 0.12)

func _on_character_obtained(_char_data: Dictionary) -> void:
	if is_open:
		_update_cards()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if is_open:
		return
	is_open = true
	_update_cards()
	modal.visible = true

	_play_sound(sfx_click)

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	
	# Dim overlay fade in
	_tween.tween_property(modal, "modulate:a", 1.0, 0.2).from(0.0)
	
	# Book scale popup with slight bounce
	book_container.scale = Vector2(0.72, 0.72)
	_tween.tween_property(book_container, "scale", Vector2(0.86, 0.86), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	opened.emit()

func close() -> void:
	if not is_open:
		return
	is_open = false

	_play_sound(sfx_click, 0.9)

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(modal, "modulate:a", 0.0, 0.15)
	_tween.tween_property(book_container, "scale", Vector2(0.75, 0.75), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func():
		modal.visible = false
	)

	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_ESCAPE and is_open:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			toggle()
			get_viewport().set_input_as_handled()

func _on_dim_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# Button micro-animations
func _on_hud_btn_hover() -> void:
	_play_sound(sfx_hover)
	var t := create_tween()
	t.tween_property(hud_button, "scale", Vector2(1.08, 1.08), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_hud_btn_unhover() -> void:
	var t := create_tween()
	t.tween_property(hud_button, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_hud_btn_down() -> void:
	var t := create_tween()
	t.tween_property(hud_button, "scale", Vector2(0.94, 0.94), 0.06)

func _on_hud_btn_up() -> void:
	var t := create_tween()
	t.tween_property(hud_button, "scale", Vector2(1.08, 1.08), 0.08)

func _animate_btn_hover(btn: TextureButton, hovered: bool) -> void:
	if hovered:
		_play_sound(sfx_hover, 1.2)
	var target_scale := Vector2(1.12, 1.12) if hovered else Vector2(1.0, 1.0)
	var t := create_tween()
	t.tween_property(btn, "scale", target_scale, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _play_sound(stream: AudioStream, pitch: float = 1.0) -> void:
	if audio_player == null or stream == null:
		return
	audio_player.stream = stream
	audio_player.pitch_scale = pitch * randf_range(0.96, 1.04)
	audio_player.play()
