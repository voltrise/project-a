class_name WildernessEnemy
extends CharacterBody2D

## Representasi visual musuh sederhana per-tile dalam Chunk.

const WildernessGen = preload("res://scripts/world/wilderness_generator.gd")

@export var enemy_type: String = "torch_goblin"
@export var threat_val: float = 28.0
@export var enemy_name: String = "Torch Goblin"
@export var max_hp: int = 120
@export var atk_val: int = 25

var sprite: Sprite2D = null
var detail_card: PanelContainer = null
var is_hovered: bool = false
var anim_timer: float = 0.0
var idle_frame: int = 0
var total_frames: int = 8
var tier_color: Color = Color("#FBBF24")

func _ready() -> void:
	z_index = 2
	_setup_visuals()

func setup_data(data: Dictionary) -> void:
	enemy_type = data.get("type", "torch_goblin")
	threat_val = data.get("threat", 28.0)
	
	if WildernessGen.ENEMY_TYPES.has(enemy_type):
		var info = WildernessGen.ENEMY_TYPES[enemy_type]
		enemy_name = info.name
		threat_val = info.threat
		max_hp = info.hp
		atk_val = info.atk
		tier_color = info.color
		total_frames = info.hframes
		
	_setup_visuals()

func _setup_visuals() -> void:
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		
	if WildernessGen.ENEMY_TYPES.has(enemy_type):
		var info = WildernessGen.ENEMY_TYPES[enemy_type]
		var tex = load(info.texture) as Texture2D
		if tex:
			sprite.texture = tex
			sprite.hframes = info.hframes
			sprite.vframes = 1
			sprite.frame = 0
			total_frames = info.hframes
			var frame_h = float(tex.get_height())
			sprite.position = Vector2(0, -frame_h * 0.5 + 16.0)
			
	if detail_card == null:
		detail_card = _build_floating_card()
		add_child(detail_card)
		detail_card.visible = false
		
	queue_redraw()

func _build_floating_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(150, 50)
	panel.z_index = 10
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.94)
	sb.border_color = tier_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
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
	threat_lbl.text = "PWR:%d" % int(threat_val)
	threat_lbl.add_theme_font_size_override("font_size", 11)
	threat_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	header.add_child(threat_lbl)
	
	var stats_lbl := Label.new()
	stats_lbl.text = "HP: %d | ATK: %d" % [max_hp, atk_val]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(stats_lbl)
	
	panel.position = Vector2(-panel.custom_minimum_size.x * 0.5, -80.0)
	return panel

func _process(delta: float) -> void:
	anim_timer += delta * 7.0
	if anim_timer >= 1.0:
		anim_timer = 0.0
		idle_frame = (idle_frame + 1) % max(1, total_frames)
		if sprite:
			sprite.frame = idle_frame
			
	var m_pos = to_local(get_global_mouse_position())
	var in_bounds = abs(m_pos.x) < 28.0 and m_pos.y > -50.0 and m_pos.y < 16.0
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
