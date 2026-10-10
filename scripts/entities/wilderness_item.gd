class_name WildernessItem
extends Node2D

## Template-based Item Node untuk Wilderness Map.
## Dapat diedit di editor di dalam WildernessTemplate.tscn.
## Memiliki animasi mengambang (bobbing) halus dan kartu hover info.

@export var item_name: String = "Item"
@export var item_type: String = "Resource"
@export var benefit_value: float = 20.0

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

var detail_card: PanelContainer = null
var is_hovered: bool = false
var float_timer: float = 0.0
var base_sprite_y: float = 0.0

func _ready() -> void:
	z_index = 2
	if sprite:
		base_sprite_y = sprite.position.y
	_setup_card()

func _setup_card() -> void:
	if detail_card != null:
		detail_card.queue_free()
	detail_card = _build_floating_card()
	add_child(detail_card)
	detail_card.visible = false
	queue_redraw()

func _build_floating_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 46)
	panel.z_index = 20
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.94)
	sb.border_color = Color(0.3, 0.85, 0.65, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	panel.add_theme_stylebox_override("panel", sb)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	var name_lbl := Label.new()
	name_lbl.text = item_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.7))
	header.add_child(name_lbl)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var val_lbl := Label.new()
	val_lbl.text = "+%.0f" % benefit_value
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	header.add_child(val_lbl)
	
	var type_lbl := Label.new()
	type_lbl.text = "Type: %s" % item_type
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vbox.add_child(type_lbl)
	
	panel.position = Vector2(-panel.custom_minimum_size.x * 0.5, -60.0)
	return panel

func _process(delta: float) -> void:
	float_timer += delta * 3.0
	if sprite:
		sprite.position.y = base_sprite_y + sin(float_timer) * 4.0
		
	var m_pos = to_local(get_global_mouse_position())
	var in_bounds = abs(m_pos.x) < 24.0 and abs(m_pos.y) < 24.0
	if in_bounds != is_hovered:
		is_hovered = in_bounds
		if detail_card:
			detail_card.visible = is_hovered

func _draw() -> void:
	var shadow_col = Color(0.0, 0.0, 0.0, 0.3)
	var center = Vector2(0, 10)
	var rx = 12.0
	var ry = 4.0
	var pts: PackedVector2Array = []
	for i in range(16):
		var a = float(i) / 16.0 * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, shadow_col)
