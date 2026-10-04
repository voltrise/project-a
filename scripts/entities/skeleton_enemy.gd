class_name SkeletonEnemy
extends CharacterBody2D

## Skeleton Enemy Node dengan animasi lengkap dan Hover Detail Card.

@export var enemy_name: String = "Skeleton Guard"
@export var threat_val: float = 20.0
@export var enemy_tier: String = "Common"
@export var max_hp: int = 85
@export var atk_val: int = 16

var sprite: Sprite2D = null
var anim_player: AnimationPlayer = null
var detail_card: PanelContainer = null
var is_hovered: bool = false
var tier_color: Color = Color("#CBD5E1")

func _ready() -> void:
	z_index = 3
	_setup_nodes()

func setup_stats(name_str: String, pwr: float, tier_str: String = "Common", hp: int = 85, atk: int = 16) -> void:
	enemy_name = name_str
	threat_val = pwr
	enemy_tier = tier_str
	max_hp = hp
	atk_val = atk
	
	match enemy_tier:
		"Common": tier_color = Color("#CBD5E1")
		"Uncommon": tier_color = Color("#4ADE80")
		"Rare": tier_color = Color("#38BDF8")
		"Epic": tier_color = Color("#C084FC")
		"Legendary": tier_color = Color("#FBBF24")
		_: tier_color = Color("#CBD5E1")
		
	if detail_card:
		detail_card.queue_free()
		detail_card = null
	detail_card = _build_floating_card()
	add_child(detail_card)
	detail_card.visible = false

func _setup_nodes() -> void:
	sprite = get_node_or_null("Sprite2D")
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = load("res://assets/Tiny Swords (Free Pack)/Enemies/Skull/Skull_Idle.png")
		sprite.hframes = 8
		sprite.position = Vector2(-2, -7)
		add_child(sprite)
		
	anim_player = get_node_or_null("AnimationPlayer")
	if anim_player and anim_player.has_animation("idle"):
		anim_player.play("idle")
		
	if detail_card == null:
		detail_card = _build_floating_card()
		add_child(detail_card)
		detail_card.visible = false
		
	queue_redraw()

func _build_floating_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 52)
	panel.z_index = 10
	
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
	
	# Baris 1: Nama & PWR
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
	threat_lbl.text = "PWR:%d" % int(threat_val)
	threat_lbl.add_theme_font_size_override("font_size", 11)
	threat_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	header.add_child(threat_lbl)
	
	# Baris 2: Stats
	var stats_lbl := Label.new()
	stats_lbl.text = "HP: %d | ATK: %d | Skeleton" % [max_hp, atk_val]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(stats_lbl)
	
	panel.position = Vector2(-panel.custom_minimum_size.x * 0.5, -85.0)
	return panel

func _process(delta: float) -> void:
	# Continuous mouse hover check
	var m_pos = to_local(get_global_mouse_position())
	var in_bounds = abs(m_pos.x) < 30.0 and m_pos.y > -50.0 and m_pos.y < 20.0
	if in_bounds != is_hovered:
		is_hovered = in_bounds
		if detail_card:
			detail_card.visible = is_hovered

func _draw() -> void:
	var shadow_col = Color(0.0, 0.0, 0.0, 0.3)
	var center = Vector2(0, 14)
	var rx = 16.0
	var ry = 5.0
	var pts: PackedVector2Array = []
	for i in range(16):
		var a = float(i) / 16.0 * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, shadow_col)
