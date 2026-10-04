extends Node

## Map Lobby / Overworld Controller
## Menjaga inisialisasi world dan memastikan portal prompt aktif di koordinat portal tile.

const PORTAL_POSITION := Vector2(2917.0, 1251.0)

var BM = BattleManagerClass.new()
var CMC = CharacterManagerClass.new()

func _ready() -> void:
	_ensure_portal_prompt()
	_ensure_wilderness_entry()

func _ensure_portal_prompt() -> void:
	if has_node("PortalPrompt"):
		return

	var portal_scene = load("res://portal_prompt.tscn")
	if portal_scene:
		var portal_node = portal_scene.instantiate()
		portal_node.position = PORTAL_POSITION
		add_child(portal_node)
		print("[MapLobby] PortalPrompt attached at ", PORTAL_POSITION)
	else:
		var portal_script = load("res://scripts/world/portal_prompt.gd")
		if portal_script:
			var portal_node = Area2D.new()
			portal_node.name = "PortalPrompt"
			portal_node.set_script(portal_script)
			portal_node.position = PORTAL_POSITION
			add_child(portal_node)
			print("[MapLobby] PortalPrompt fallback created at ", PORTAL_POSITION)

func _ensure_wilderness_entry() -> void:
	if has_node("WildernessUI"):
		return
	var canvas := CanvasLayer.new()
	canvas.name = "WildernessUI"
	canvas.layer = 91
	
	var btn := Button.new()
	btn.text = "🌲 Wilderness (Local Search)"
	btn.custom_minimum_size = Vector2(200, 36)
	btn.position = Vector2(20, 75)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.22, 0.92)
	sb.border_color = Color(0.3, 0.8, 0.5, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	
	btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://Wilderness.tscn")
	)
	canvas.add_child(btn)
	add_child(canvas)

func _process(delta: float) -> void:
	pass
