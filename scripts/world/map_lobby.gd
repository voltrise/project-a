extends Node

## Map Lobby / Overworld Controller
## Menjaga inisialisasi world dan memastikan portal prompt aktif di koordinat portal tile.

const PORTAL_POSITION := Vector2(2917.0, 1251.0)

var BM = BattleManagerClass.new()
var CMC = CharacterManagerClass.new()

func _ready() -> void:
	_ensure_portal_prompt()

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

func _process(delta: float) -> void:
	pass
