class_name RngRoller
extends Control

## Roblox-style vertical scrolling RNG roller with center needles, dynamic scaling, and dim overlay

signal roll_started
signal roll_finished(character_data, tier_data)

const ReelItemScript = preload("res://reel_item.gd")

@export var item_spacing: float = 230.0
@export var items_per_roll: int = 24
@export var roll_duration: float = 3.2
@export var result_display_duration: float = 1.6
@export var enable_sound: bool = true
@export var enable_screen_shake: bool = true

# Node references
@onready var dim_overlay: ColorRect = get_node_or_null("../DimOverlay")
@onready var shaker: Control = get_node_or_null("Shaker")
@onready var reel_viewport: Control = get_node_or_null("Shaker/ReelViewport") if has_node("Shaker/ReelViewport") else get_node_or_null("ReelViewport")
@onready var track: Control = reel_viewport.get_node("Track") if reel_viewport and reel_viewport.has_node("Track") else null
@onready var needle_left: TextureRect = get_node_or_null("Shaker/Needles/NeedleLeft") if has_node("Shaker/Needles/NeedleLeft") else get_node_or_null("Needles/NeedleLeft")
@onready var needle_right: TextureRect = get_node_or_null("Shaker/Needles/NeedleRight") if has_node("Shaker/Needles/NeedleRight") else get_node_or_null("Needles/NeedleRight")
@onready var winner_particles: CPUParticles2D = get_node_or_null("Shaker/WinnerParticles") if has_node("Shaker/WinnerParticles") else get_node_or_null("WinnerParticles")
@onready var tick_sound: AudioStreamPlayer = $TickSound
@onready var win_sound: AudioStreamPlayer = $WinSound
@onready var legendary_sound: AudioStreamPlayer = $LegendarySound

# Preload reel item scene
var reel_item_scene: PackedScene = preload("res://reel_item.tscn")

# Data
var tiers: Dictionary = {}
var characters: Array = []
var _cumulative_weights: Array = []
var _total_weight: float = 0.0

# State
var total_rolls: int = 0
var is_rolling: bool = false
var _scroll_pos_y: float = 0.0
var _target_scroll_pos_y: float = 0.0
var _roll_tween: Tween
var _fade_tween: Tween
var _roll_session_id: int = 0
var _last_tick_index: int = -1
var _active_items: Array[Control] = []
var _winner_character: Dictionary = {}
var _winner_tier: Dictionary = {}

var _base_needle_left_x: float = 0.0
var _base_needle_right_x: float = 0.0

func _ready() -> void:
	# Hidden by default - only shows when rolling dice!
	visible = false
	modulate.a = 0.0

	_update_pivots()
	resized.connect(_update_pivots)
	if get_viewport():
		get_viewport().size_changed.connect(_update_pivots)

	load_data()
	_setup_audio()
	_setup_needles()
	_setup_overlay()

func _update_pivots() -> void:
	pivot_offset = size * 0.5
	if winner_particles:
		winner_particles.position = size * 0.5

func _setup_overlay() -> void:
	if dim_overlay:
		dim_overlay.visible = false
		dim_overlay.modulate.a = 0.0
		dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not dim_overlay.gui_input.is_connected(_on_overlay_gui_input):
			dim_overlay.gui_input.connect(_on_overlay_gui_input)

func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_rolling:
			_skip_to_end()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_rolling:
			_skip_to_end()

func _setup_audio() -> void:
	if tick_sound and tick_sound.stream == null:
		tick_sound.stream = ReelItemScript.load_audio_safe("res://audio/sfx/reel_tick.wav")
	if win_sound and win_sound.stream == null:
		win_sound.stream = ReelItemScript.load_audio_safe("res://audio/sfx/roll_win.wav")
	if legendary_sound and legendary_sound.stream == null:
		legendary_sound.stream = ReelItemScript.load_audio_safe("res://audio/sfx/roll_legendary.wav")

func _setup_needles() -> void:
	var needle_tex = ReelItemScript.load_texture_safe("res://ui/needle.png")
	if needle_tex:
		if needle_left:
			needle_left.texture = needle_tex
		if needle_right:
			needle_right.texture = needle_tex

	if needle_left:
		_base_needle_left_x = needle_left.position.x
	if needle_right:
		_base_needle_right_x = needle_right.position.x

func load_data() -> void:
	# 1. Load tiers.json
	if FileAccess.file_exists("res://tiers.json"):
		var f = FileAccess.open("res://tiers.json", FileAccess.READ)
		var json_str = f.get_as_text()
		var parsed = JSON.parse_string(json_str)
		if parsed is Dictionary:
			tiers = parsed
	
	if tiers.is_empty():
		tiers = {
			"Common": {"name": "Common", "color": "#CBD5E1", "glow_color": "#F1F5F9", "aura_scale": 1.0, "sound": "common"},
			"Rare": {"name": "Rare", "color": "#38BDF8", "glow_color": "#7DD3FC", "aura_scale": 1.3, "sound": "rare"},
			"Legendary": {"name": "Legendary", "color": "#FBBF24", "glow_color": "#FEF08A", "aura_scale": 1.75, "sound": "legendary"}
		}

	# 2. Load characters.json
	if FileAccess.file_exists("res://characters.json"):
		var f = FileAccess.open("res://characters.json", FileAccess.READ)
		var json_str = f.get_as_text()
		var parsed = JSON.parse_string(json_str)
		if parsed is Array:
			characters = parsed

	if characters.is_empty():
		characters = [
			{"id": "rimuru", "name": "Rimuru", "image": "res://characters/rimuru.png", "tier": "Common", "chance": 2},
			{"id": "nijika", "name": "Nijika", "image": "res://characters/nijika.png", "tier": "Rare", "chance": 8},
			{"id": "bocchi", "name": "Bocchi", "image": "res://characters/bocchi.png", "tier": "Legendary", "chance": 32}
		]

	# Calculate probability weights (1.0 / chance)
	_cumulative_weights.clear()
	_total_weight = 0.0
	for c in characters:
		var chance_val = float(c.get("chance", 1))
		var w = 1.0 / max(1.0, chance_val)
		_total_weight += w
		_cumulative_weights.append(_total_weight)

func pick_random_character(equal_chance: bool = false) -> Dictionary:
	if characters.is_empty() or _cumulative_weights.is_empty():
		load_data()
	if characters.is_empty():
		return {}
	if equal_chance:
		return characters.pick_random()
	var roll = randf() * _total_weight
	for i in range(_cumulative_weights.size()):
		if roll <= _cumulative_weights[i]:
			return characters[i]
	return characters[0]

func get_tier(tier_name: String) -> Dictionary:
	if tiers.has(tier_name):
		return tiers[tier_name]
	return {"name": tier_name, "color": "#FFFFFF", "glow_color": "#FFFFFF", "aura_scale": 1.0, "sound": "common"}

func start_demo_roll() -> void:
	start_roll(true)

func start_roll(equal_chance: bool = false) -> void:
	if is_rolling:
		# Quick skip if already rolling
		_skip_to_end()
		return

	# Increment session to cancel any pending auto-close timers
	_roll_session_id += 1

	# Make visible and immediately cancel any fade-out
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	visible = true
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if dim_overlay:
		dim_overlay.visible = true
		dim_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		_fade_tween.tween_property(dim_overlay, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	is_rolling = true
	total_rolls += 1
	roll_started.emit()

	# Pick winning character (equal chance for demo roll)
	_winner_character = pick_random_character(equal_chance)
	_winner_tier = get_tier(_winner_character.get("tier", "Common"))

	# Clear and rebuild the track
	if track:
		for child in track.get_children():
			child.queue_free()
	_active_items.clear()

	var viewport_w: float = reel_viewport.size.x if (reel_viewport and reel_viewport.size.x > 0) else 300.0
	var viewport_h: float = reel_viewport.size.y if (reel_viewport and reel_viewport.size.y > 0) else 440.0
	var center_y: float = viewport_h * 0.5
	var item_w: float = 260.0
	var item_h: float = 240.0
	var item_x: float = (viewport_w - item_w) * 0.5

	# Generate sequence of items ending at winner
	if track:
		for i in range(items_per_roll):
			var item: Control = reel_item_scene.instantiate()
			track.add_child(item)
			
			var c = _winner_character if (i == items_per_roll - 1) else pick_random_character(equal_chance)
			var t = get_tier(c.get("tier", "Common"))
			item.call("set_character", c, t)
			
			# Center item exactly at (item_x, i * item_spacing + center_y - half_height)
			item.position = Vector2(item_x, i * item_spacing + center_y - (item_h * 0.5))
			_active_items.append(item)

	# Target scroll position aligns the last item (winner) directly at center_y
	_scroll_pos_y = 0.0
	_target_scroll_pos_y = (items_per_roll - 1) * item_spacing
	_last_tick_index = -1

	# Deceleration tween
	if _roll_tween and _roll_tween.is_valid():
		_roll_tween.kill()

	_roll_tween = create_tween()
	_roll_tween.tween_method(_set_scroll_pos, 0.0, _target_scroll_pos_y, roll_duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_roll_tween.finished.connect(_on_roll_completed)

func _set_scroll_pos(val: float) -> void:
	_scroll_pos_y = val
	if track:
		track.position.y = -_scroll_pos_y
	
	# Detect when an item crosses center line for tick sound
	var current_index = int(round(_scroll_pos_y / item_spacing))
	if current_index != _last_tick_index and current_index >= 0 and current_index < _active_items.size():
		_last_tick_index = current_index
		_play_tick_sound(current_index)
		_needle_micro_kick()

func _process(delta: float) -> void:
	if visible and modulate.a > 0.01:
		_update_reel_visuals(delta)

func _update_reel_visuals(delta: float) -> void:
	if reel_viewport == null or track == null:
		return
	var center_y = reel_viewport.size.y * 0.5
	var half_h = 120.0
	for item in _active_items:
		if not is_instance_valid(item):
			continue
		# Item center Y relative to the reel viewport
		var item_center_y = item.position.y + half_h + track.position.y
		var dist_from_center = abs(item_center_y - center_y)
		
		# Focus ratio: 1.0 when perfectly centered, down to 0.0 when 200px away
		var focus_ratio = clampf(1.0 - (dist_from_center / 200.0), 0.0, 1.0)
		item.call("update_focus", focus_ratio, delta)

func _play_tick_sound(idx: float) -> void:
	if not enable_sound or tick_sound == null:
		return
	var progress = clampf(idx / float(items_per_roll), 0.0, 1.0)
	tick_sound.pitch_scale = lerpf(0.95, 1.25, progress)
	tick_sound.play()

func _needle_micro_kick() -> void:
	if needle_left and needle_right:
		needle_left.position.x = _base_needle_left_x + 3.0
		needle_right.position.x = _base_needle_right_x - 3.0
		var tween = create_tween().set_parallel(true)
		tween.tween_property(needle_left, "position:x", _base_needle_left_x, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(needle_right, "position:x", _base_needle_right_x, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _skip_to_end() -> void:
	if _roll_tween and _roll_tween.is_valid():
		_roll_tween.kill()
	_set_scroll_pos(_target_scroll_pos_y)
	_on_roll_completed()

func _on_roll_completed() -> void:
	is_rolling = false
	if track:
		track.position.y = -_target_scroll_pos_y
	_update_reel_visuals(0.0)

	# Winner item is the last one
	var winner_item: Control = _active_items[_active_items.size() - 1] if not _active_items.is_empty() else null
	if winner_item:
		winner_item.call("play_winner_pop")

	# Needles celebration pinch
	_needle_celebrate_pinch()

	# Particle burst in tier's color
	if winner_particles:
		var glow_col = Color(_winner_tier.get("glow_color", "#FFFFFF"))
		winner_particles.color = glow_col
		winner_particles.restart()

	# Audio celebration
	if enable_sound:
		var sound_type = _winner_tier.get("sound", "common")
		if sound_type == "legendary" and legendary_sound:
			legendary_sound.play()
		elif win_sound:
			win_sound.play()

	# Screen rumble / shake
	if enable_screen_shake:
		_screen_shake()

	roll_finished.emit(_winner_character, _winner_tier)

	# Register character to CharacterManager modular library
	var cm = get_node_or_null("/root/CharacterManager")
	if cm and cm.has_method("add_character"):
		cm.add_character(_winner_character)

	# Auto-hide after roll completion, reset if rolled again
	_schedule_hide()

func _schedule_hide() -> void:
	var current_session = _roll_session_id
	var tree = get_tree()
	if tree:
		var timer = tree.create_timer(result_display_duration)
		timer.timeout.connect(func():
			# Only close if no new roll has started in the meantime
			if current_session == _roll_session_id and not is_rolling:
				_fade_out()
		)

func _fade_out() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	var current_session = _roll_session_id
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if dim_overlay:
		_fade_tween.tween_property(dim_overlay, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.chain().tween_callback(func():
		if current_session == _roll_session_id and not is_rolling:
			visible = false
			if dim_overlay:
				dim_overlay.visible = false
				dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

func _needle_celebrate_pinch() -> void:
	if needle_left and needle_right:
		var tween = create_tween().set_parallel(true)
		tween.tween_property(needle_left, "position:x", _base_needle_left_x + 12.0, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(needle_right, "position:x", _base_needle_right_x - 12.0, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
		tween.chain().set_parallel(true)
		tween.tween_property(needle_left, "position:x", _base_needle_left_x, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(needle_right, "position:x", _base_needle_right_x, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _screen_shake() -> void:
	if shaker != null:
		var tween = create_tween()
		tween.tween_property(shaker, "position", Vector2(randf_range(-5, 5), randf_range(-5, 5)), 0.04)
		tween.tween_property(shaker, "position", Vector2(randf_range(-3, 3), randf_range(-3, 3)), 0.04)
		tween.tween_property(shaker, "position", Vector2(randf_range(-2, 2), randf_range(-2, 2)), 0.04)
		tween.tween_property(shaker, "position", Vector2.ZERO, 0.06)
