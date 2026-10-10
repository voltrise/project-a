class_name WildernessTemplates
extends Node2D

## Scene Manager untuk Template Chunk, Enemy, dan Item.
## Menjadi penghubung antara desain visual di editor dengan generator CSP + Local Search.
##
## Konfigurasi dapat diubah melalui Inspector di Godot Editor:
## - chunk_size_p & chunk_size_q: ukuran 1 chunk dalam tile (default: 7x7)
## - grid_chunks_n & grid_chunks_m: ukuran total labirin dalam chunk (default: 5x5)
## - chunk_templates: daftar template pintu dan koordinat origin di layer

@export_group("Grid & Chunk Dimensions")
@export var chunk_size_p: int = 7 ## Lebar chunk dalam satuan tile (p)
@export var chunk_size_q: int = 7 ## Tinggi chunk dalam satuan tile (q)
@export var grid_chunks_n: int = 8 ## Jumlah kolom chunk di map (n)
@export var grid_chunks_m: int = 6 ## Jumlah baris chunk di map (m)

@export_group("Hallway Settings")
@export var hallway_length: int = 0 ## Panjang lorong antar-chunk dalam satuan tile
@export var hallway_h_origin: Vector2i = Vector2i(8, 16) ## Koordinat origin lorong horizontal di ChunkMap
@export var hallway_v_origin: Vector2i = Vector2i(16, 16) ## Koordinat origin lorong vertikal di ChunkMap

@export_group("Chunk Template Definitions")
@export var chunk_templates: Array[Dictionary] = [
	# Baris 0 (Y = 0, Stride X = 8 dengan gap 1 tile)
	{ "id": "4WAY", "name": "4-Way Open", "doors": [true, true, true, true], "origin": Vector2i(0, 0) },
	{ "id": "EW", "name": "Straight East-West", "doors": [false, false, true, true], "origin": Vector2i(8, 0) },
	{ "id": "NS", "name": "Straight North-South", "doors": [true, true, false, false], "origin": Vector2i(16, 0) },
	{ "id": "CORNER_ES", "name": "Corner East-South", "doors": [false, true, true, false], "origin": Vector2i(24, 0) },
	{ "id": "CORNER_SW", "name": "Corner South-West", "doors": [false, true, false, true], "origin": Vector2i(32, 0) },
	{ "id": "CORNER_WN", "name": "Corner West-North", "doors": [true, false, false, true], "origin": Vector2i(40, 0) },
	{ "id": "CORNER_NE", "name": "Corner North-East", "doors": [true, false, true, false], "origin": Vector2i(48, 0) },
	
	# Baris 1 (Y = 8, Stride X = 8 dengan gap 1 tile)
	{ "id": "T_NORTH", "name": "T-Junction North", "doors": [true, false, true, true], "origin": Vector2i(0, 8) },
	{ "id": "T_SOUTH", "name": "T-Junction South", "doors": [false, true, true, true], "origin": Vector2i(8, 8) },
	{ "id": "T_EAST", "name": "T-Junction East", "doors": [true, true, true, false], "origin": Vector2i(16, 8) },
	{ "id": "T_WEST", "name": "T-Junction West", "doors": [true, true, false, true], "origin": Vector2i(24, 8) },
	{ "id": "DEAD_N", "name": "Dead-End North", "doors": [true, false, false, false], "origin": Vector2i(32, 8) },
	{ "id": "DEAD_S", "name": "Dead-End South", "doors": [false, true, false, false], "origin": Vector2i(40, 8) },
	{ "id": "DEAD_E", "name": "Dead-End East", "doors": [false, false, true, false], "origin": Vector2i(48, 8) },
	{ "id": "DEAD_W", "name": "Dead-End West", "doors": [false, false, false, true], "origin": Vector2i(56, 8) },
	
	# Baris 2 (Y = 16)
	{ "id": "SOLID", "name": "Solid Wall Block", "doors": [false, false, false, false], "origin": Vector2i(0, 16) }
]

func _get_water_layer() -> TileMapLayer:
	return get_node_or_null("ChunkMap/Water") as TileMapLayer

func _get_ground_layer() -> TileMapLayer:
	return get_node_or_null("ChunkMap/Ground") as TileMapLayer

func _get_path_layer() -> TileMapLayer:
	return get_node_or_null("ChunkMap/Path") as TileMapLayer

func _get_decoration_layer() -> TileMapLayer:
	return get_node_or_null("ChunkMap/Decoration") as TileMapLayer

func _get_enemies_container() -> Node2D:
	return get_node_or_null("Enemies") as Node2D

func _get_items_container() -> Node2D:
	return get_node_or_null("Items") as Node2D

func _get_portal_template() -> Node2D:
	return get_node_or_null("Portal") as Node2D

func _ready() -> void:
	visible = false

func get_chunk_templates() -> Array[Dictionary]:
	return chunk_templates

func get_template_by_id(tpl_id: String) -> Dictionary:
	for tpl in chunk_templates:
		if tpl.id == tpl_id:
			return tpl
	return chunk_templates[0]

func get_chunk_tiles(template_id: String) -> Dictionary:
	var tpl = get_template_by_id(template_id)
	var origin: Vector2i = tpl.get("origin", Vector2i.ZERO)
	var doors: Array = tpl.get("doors", [true, true, true, true])
	
	var tiles_data := {
		"water": [],
		"ground": [],
		"path": [],
		"decoration": []
	}
	
	var water_l = _get_water_layer()
	var ground_l = _get_ground_layer()
	var path_l = _get_path_layer()
	var deco_l = _get_decoration_layer()
	
	for ly in range(chunk_size_q):
		for lx in range(chunk_size_p):
			var sample_coord = origin + Vector2i(lx, ly)
			
			if water_l:
				var w_src = water_l.get_cell_source_id(sample_coord)
				if w_src != -1:
					var w_entry = {
						"offset": Vector2i(lx, ly),
						"source_id": w_src,
						"atlas_coords": water_l.get_cell_atlas_coords(sample_coord),
						"alt": water_l.get_cell_alternative_tile(sample_coord)
					}
					tiles_data["water"].append(w_entry)
			
			if ground_l:
				var g_src = ground_l.get_cell_source_id(sample_coord)
				if g_src != -1:
					tiles_data["ground"].append({
						"offset": Vector2i(lx, ly),
						"source_id": g_src,
						"atlas_coords": ground_l.get_cell_atlas_coords(sample_coord),
						"alt": ground_l.get_cell_alternative_tile(sample_coord)
					})
			
			if path_l:
				var src = path_l.get_cell_source_id(sample_coord)
				if src != -1:
					tiles_data["path"].append({
						"offset": Vector2i(lx, ly),
						"source_id": src,
						"atlas_coords": path_l.get_cell_atlas_coords(sample_coord),
						"alt": path_l.get_cell_alternative_tile(sample_coord)
					})
					
			if deco_l:
				var d_src = deco_l.get_cell_source_id(sample_coord)
				if d_src != -1:
					tiles_data["decoration"].append({
						"offset": Vector2i(lx, ly),
						"source_id": d_src,
						"atlas_coords": deco_l.get_cell_atlas_coords(sample_coord),
						"alt": deco_l.get_cell_alternative_tile(sample_coord)
					})

	return tiles_data

## Mengambil pola slice 1-kolom untuk lorong horizontal
func get_hallway_h_slice() -> Dictionary:
	var slice := { "water": [], "ground": [], "path": [], "decoration": [] }
	var water_l = _get_water_layer()
	var ground_l = _get_ground_layer()
	var path_l = _get_path_layer()
	var deco_l = _get_decoration_layer()
	
	for ly in range(chunk_size_q):
		var coord = hallway_h_origin + Vector2i(0, ly)
		if water_l and water_l.get_cell_source_id(coord) != -1:
			var w_entry = {
				"y": ly,
				"source_id": water_l.get_cell_source_id(coord),
				"atlas_coords": water_l.get_cell_atlas_coords(coord),
				"alt": water_l.get_cell_alternative_tile(coord)
			}
			slice["water"].append(w_entry)
		if ground_l and ground_l.get_cell_source_id(coord) != -1:
			slice["ground"].append({
				"y": ly,
				"source_id": ground_l.get_cell_source_id(coord),
				"atlas_coords": ground_l.get_cell_atlas_coords(coord),
				"alt": ground_l.get_cell_alternative_tile(coord)
			})
		if path_l and path_l.get_cell_source_id(coord) != -1:
			slice["path"].append({
				"y": ly,
				"source_id": path_l.get_cell_source_id(coord),
				"atlas_coords": path_l.get_cell_atlas_coords(coord),
				"alt": path_l.get_cell_alternative_tile(coord)
			})
		if deco_l and deco_l.get_cell_source_id(coord) != -1:
			slice["decoration"].append({
				"y": ly,
				"source_id": deco_l.get_cell_source_id(coord),
				"atlas_coords": deco_l.get_cell_atlas_coords(coord),
				"alt": deco_l.get_cell_alternative_tile(coord)
			})
			
	return slice

## Mengambil pola slice 1-baris untuk lorong vertikal
func get_hallway_v_slice() -> Dictionary:
	var slice := { "water": [], "ground": [], "path": [], "decoration": [] }
	var water_l = _get_water_layer()
	var ground_l = _get_ground_layer()
	var path_l = _get_path_layer()
	var deco_l = _get_decoration_layer()
	
	for lx in range(chunk_size_p):
		var coord = hallway_v_origin + Vector2i(lx, 0)
		if water_l and water_l.get_cell_source_id(coord) != -1:
			var w_entry = {
				"x": lx,
				"source_id": water_l.get_cell_source_id(coord),
				"atlas_coords": water_l.get_cell_atlas_coords(coord),
				"alt": water_l.get_cell_alternative_tile(coord)
			}
			slice["water"].append(w_entry)
		if ground_l and ground_l.get_cell_source_id(coord) != -1:
			slice["ground"].append({
				"x": lx,
				"source_id": ground_l.get_cell_source_id(coord),
				"atlas_coords": ground_l.get_cell_atlas_coords(coord),
				"alt": ground_l.get_cell_alternative_tile(coord)
			})
		if path_l and path_l.get_cell_source_id(coord) != -1:
			slice["path"].append({
				"x": lx,
				"source_id": path_l.get_cell_source_id(coord),
				"atlas_coords": path_l.get_cell_atlas_coords(coord),
				"alt": path_l.get_cell_alternative_tile(coord)
			})
		if deco_l and deco_l.get_cell_source_id(coord) != -1:
			slice["decoration"].append({
				"x": lx,
				"source_id": deco_l.get_cell_source_id(coord),
				"atlas_coords": deco_l.get_cell_atlas_coords(coord),
				"alt": deco_l.get_cell_alternative_tile(coord)
			})
			
	return slice

func get_enemy_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var e_container = _get_enemies_container()
	if e_container:
		for child in e_container.get_children():
			var threat = child.get("threat_level") if "threat_level" in child else 25.0
			var e_name = child.get("enemy_name") if "enemy_name" in child else child.name
			var tier = child.get("tier") if "tier" in child else "Common"
			var hp = child.get("max_hp") if "max_hp" in child else 100
			var atk = child.get("atk_val") if "atk_val" in child else 18
			pool.append({
				"node_name": child.name,
				"name": e_name,
				"threat": threat,
				"tier": tier,
				"hp": hp,
				"atk": atk,
				"template_node": child
			})
	if pool.is_empty():
		pool.append({
			"node_name": "Skeleton",
			"name": "Skeleton Guard",
			"threat": 20.0,
			"tier": "Common",
			"hp": 90,
			"atk": 16,
			"template_node": null
		})
	return pool

func get_item_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var i_container = _get_items_container()
	if i_container:
		for child in i_container.get_children():
			var benefit = child.get("benefit_value") if "benefit_value" in child else 20.0
			var i_name = child.get("item_name") if "item_name" in child else child.name
			var i_type = child.get("item_type") if "item_type" in child else "Item"
			pool.append({
				"node_name": child.name,
				"name": i_name,
				"type": i_type,
				"benefit": benefit,
				"template_node": child
			})
	if pool.is_empty():
		pool.append({
			"node_name": "Meat",
			"name": "Roasted Meat",
			"type": "Food",
			"benefit": 20.0,
			"template_node": null
		})
	return pool

func instantiate_enemy(template_child_name: String) -> Node2D:
	var e_container = _get_enemies_container()
	if e_container and e_container.has_node(template_child_name):
		var orig = e_container.get_node(template_child_name)
		var dup = orig.duplicate()
		dup.visible = true
		return dup
	return null

func instantiate_item(template_child_name: String) -> Node2D:
	var i_container = _get_items_container()
	if i_container and i_container.has_node(template_child_name):
		var orig = i_container.get_node(template_child_name)
		var dup = orig.duplicate()
		dup.visible = true
		return dup
	return null

func instantiate_portal() -> Node2D:
	var p_tpl = _get_portal_template()
	if p_tpl:
		var dup = p_tpl.duplicate()
		dup.visible = true
		return dup
	return null
