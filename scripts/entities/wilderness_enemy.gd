class_name WildernessEnemy
extends CharacterBody2D

## Template-based Enemy Node untuk Wilderness Map.
## Dapat diedit di editor di dalam WildernessTemplate.tscn.
## Mendukung AnimationPlayer ('idle', 'walk', 'attack') atau sprite cycling,
## serta kartu tooltip info saat di-hover mouse.

@export var enemy_name: String = "Enemy"
@export var threat_level: float = 20.0
@export var tier: String = "Common"
@export var max_hp: int = 80
@export var atk_val: int = 15

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")

var detail_card: PanelContainer = null
var is_hovered: bool = false
var anim_timer: float = 0.0
var current_frame: int = 0
var tier_color: Color = Color("#CBD5E1")

func _ready() -> void:
	z_index = 3
	_update_tier_color()
	_setup_card()
	play_animation("idle")

func _update_tier_color() -> void:
	match tier:
		"Common": tier_color = Color("#CBD5E1")
		"Uncommon": tier_color = Color("#4ADE80")
		"Rare": tier_color = Color("#38BDF8")
		"Epic": tier_color = Color("#C084FC")
		"Legendary": tier_color = Color("#FBBF24")
		_: tier_color = Color("#CBD5E1")

func play_animation(anim_name: String) -> void:
	if anim_player:
		var target_name = anim_name
		if anim_name == "walk" and not anim_player.has_animation("walk") and anim_player.has_animation("run"):
			target_name = "run"
			
		if anim_player.has_animation(target_name):
			anim_player.play(target_name)
			return

func _setup_card() -> void:
	if detail_card != null:
		detail_card.queue_free()
	detail_card = _build_floating_card()
	add_child(detail_card)
	detail_card.visible = false
	queue_redraw()

func _build_floating_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(165, 54)
	panel.z_index = 20
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.94)
	sb.border_color = tier_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 5
	panel.add_theme_stylebox_override("panel", sb)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	var name_lbl := Label.new()
	name_lbl.text = enemy_name
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", tier_color)
	header.add_child(name_lbl)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var threat_lbl := Label.new()
	threat_lbl.text = "PWR: %d" % int(threat_level)
	threat_lbl.add_theme_font_size_override("font_size", 11)
	threat_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	header.add_child(threat_lbl)
	
	var stats_lbl := Label.new()
	stats_lbl.text = "Tier: %s | HP: %d | ATK: %d" % [tier, max_hp, atk_val]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(stats_lbl)
	
	panel.position = Vector2(-panel.custom_minimum_size.x * 0.5, -82.0)
	return panel

func _process(delta: float) -> void:
	if anim_player == null or not anim_player.is_playing():
		if sprite and sprite.hframes > 1:
			anim_timer += delta * 7.0
			if anim_timer >= 1.0:
				anim_timer = 0.0
				current_frame = (current_frame + 1) % sprite.hframes
				sprite.frame = current_frame
				
	var m_pos = to_local(get_global_mouse_position())
	var in_bounds = abs(m_pos.x) < 32.0 and m_pos.y > -55.0 and m_pos.y < 25.0
	if in_bounds != is_hovered:
		is_hovered = in_bounds
		if detail_card:
			detail_card.visible = is_hovered

func _draw() -> void:
	var shadow_col = Color(0.0, 0.0, 0.0, 0.35)
	var center = Vector2(0, 14)
	var rx = 16.0
	var ry = 5.0
	var pts: PackedVector2Array = []
	for i in range(16):
		var a = float(i) / 16.0 * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, shadow_col)
