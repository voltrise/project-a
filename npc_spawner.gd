class_name NPCSpawner
extends Node2D

## Spawns characters as NPCs on walkable tiles in TileMapLayer "World" / "Ground"
## avoiding any tiles in TileMapLayer "Obstacle" / "Obstacles".

@export var world_layer_name: String = "World" # Fallback to "Ground"
@export var obstacle_layer_name: String = "Obstacle" # Fallback to "Obstacles"
@export var deco_layer_name: String = "Deco_Objects"

var world_layer: TileMapLayer = null
var obstacle_layer: TileMapLayer = null
var deco_layer: TileMapLayer = null

var npc_scene: PackedScene = preload("res://npc_character.tscn")
var occupied_cells: Dictionary = {}

func _ready() -> void:
	_resolve_layers()
	_connect_character_manager()

func _resolve_layers() -> void:
	# Search for walkable world layer (checks "World", then "Ground", etc.)
	world_layer = _find_tilemap_layer([world_layer_name, "Ground", "ground", "world"])
	if world_layer == null:
		push_warning("[NPCSpawner] Walkable layer ('World' or 'Ground') not found!")

	# Search for obstacle layer (checks "Obstacle", then "Obstacles", etc.)
	obstacle_layer = _find_tilemap_layer([obstacle_layer_name, "Obstacles", "obstacles", "obstacle"])
	if obstacle_layer == null:
		push_warning("[NPCSpawner] Obstacle layer ('Obstacle' or 'Obstacles') not found!")

	# Optional deco layer
	deco_layer = _find_tilemap_layer([deco_layer_name, "Deco_Objects", "DecoObjects"])

func _find_tilemap_layer(candidate_names: Array) -> TileMapLayer:
	# 1. Check siblings under parent first
	var p = get_parent()
	if p:
		for n in candidate_names:
			var node = p.get_node_or_null(n)
			if node is TileMapLayer:
				return node

	# 2. Search recursively in scene tree for a TileMapLayer matching any candidate name
	if get_tree() and get_tree().root:
		var stack: Array[Node] = [get_tree().root]
		while stack.size() > 0:
			var curr = stack.pop_back()
			if curr is TileMapLayer:
				for n in candidate_names:
					if curr.name.nocasecmp_to(n) == 0:
						return curr
			for child in curr.get_children():
				stack.append(child)

	return null

func _connect_character_manager() -> void:
	# Connect to CharacterManager autoload signal
	var cm = get_node_or_null("/root/CharacterManager")
	if cm and cm.has_signal("character_added"):
		if not cm.character_added.is_connected(_on_character_added):
			cm.character_added.connect(_on_character_added)

func _on_character_added(char_data: Dictionary) -> void:
	spawn_npc(char_data)

## Finds a random valid walkable cell and spawns the character as an NPC
func spawn_npc(char_data: Dictionary, tier_data: Dictionary = {}) -> NpcCharacter:
	if world_layer == null:
		_resolve_layers()
	if world_layer == null:
		push_error("[NPCSpawner] Cannot spawn NPC: world_layer is missing!")
		return null

	var valid_cell: Vector2i = _pick_random_valid_cell()
	if valid_cell == Vector2i(999999, 999999):
		push_warning("[NPCSpawner] No valid walkable tiles available to spawn NPC!")
		return null

	occupied_cells[valid_cell] = true

	# Convert tile cell coordinate to world position (center of 64x64 tile)
	var local_pos = world_layer.map_to_local(valid_cell)
	var world_pos = world_layer.to_global(local_pos)

	var npc = npc_scene.instantiate() as NpcCharacter
	add_child(npc)
	npc.global_position = world_pos
	npc.setup(char_data, tier_data)

	var c_name = char_data.get("name", "Unknown")
	print("[NPCSpawner] Spawned NPC '%s' at tile %s (world: %s)" % [c_name, valid_cell, world_pos])
	return npc

func _pick_random_valid_cell() -> Vector2i:
	var all_used = world_layer.get_used_cells()
	if all_used.is_empty():
		return Vector2i(999999, 999999)

	# Collect player positions to avoid spawning directly on top of players
	var player_tiles: Dictionary = {}
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			var pt = world_layer.local_to_map(world_layer.to_local(p.global_position))
			player_tiles[pt] = true

	var candidates_unoccupied: Array[Vector2i] = []
	var candidates_fallback: Array[Vector2i] = []

	for cell in all_used:
		# 1. Must exist on world/ground layer
		if world_layer.get_cell_source_id(cell) == -1:
			continue

		# 2. Must NOT exist on obstacle layer
		if obstacle_layer != null and obstacle_layer.get_cell_source_id(cell) != -1:
			continue

		# 3. Must NOT exist on decoration objects layer (trees, rocks, etc.)
		if deco_layer != null and deco_layer.get_cell_source_id(cell) != -1:
			continue

		# 4. Filter players
		if player_tiles.has(cell):
			continue

		# 5. Check if already occupied by an NPC
		if not occupied_cells.has(cell):
			candidates_unoccupied.append(cell)
		else:
			candidates_fallback.append(cell)

	if candidates_unoccupied.size() > 0:
		return candidates_unoccupied.pick_random()
	elif candidates_fallback.size() > 0:
		return candidates_fallback.pick_random()

	return Vector2i(999999, 999999)
