class_name CustomUCS
extends Node2D

# Koordinat atlas tile pada layer 'Path'
const TILE_PAVED_PATH := Vector2i(27, 17) # Tile Kuning (Paved Path) - Cost 1
const TILE_GRASS := Vector2i(27, 12)      # Tile Hijau (Grass) - Cost 2

# Helper class untuk merepresentasikan node pada algoritma Uniform Cost Search (UCS)
class PathNode:
	var position: Vector2i
	var parent: PathNode = null
	var g: float = 0.0 # Biaya kumulatif jalur dari start ke node ini
	var h: float = 0.0 # Heuristik (selalu 0.0 dalam UCS)
	var f: float = 0.0 # Total evaluasi skor (dalam UCS: f = g)

	func _init(_pos: Vector2i, _parent: PathNode = null):
		self.position = _pos
		self.parent = _parent

# Menghitung movement cost untuk melangkah ke suatu cell HANYA berdasarkan layer 'Path':
# - Tile kosong (source_id == -1) -> INF (non-walkable)
# - Tile Kuning (atlas 27, 17) -> Paved Path: cost = 1.0
# - Tile Hijau (atlas 27, 12)  -> Grass: cost = 2.0
# - Default jika ada tile lain di layer Path -> cost = 2.0
static func get_step_cost(path_map: TileMapLayer, cell: Vector2i) -> float:
	if path_map == null or path_map.get_cell_source_id(cell) == -1:
		return INF
	var atlas: Vector2i = path_map.get_cell_atlas_coords(cell)
	if atlas == TILE_PAVED_PATH:
		return 1.0
	elif atlas == TILE_GRASS:
		return 2.0
	return 2.0

# Mengambil dan menghapus node dengan biaya kumulatif g(n) terendah dari antrean prioritas / frontier
static func _pop_lowest_cost(node_list: Array[PathNode]) -> PathNode:
	var lowest_index := 0
	for i in range(1, node_list.size()):
		if node_list[i].g < node_list[lowest_index].g:
			lowest_index = i
	return node_list.pop_at(lowest_index)

# Kompatibilitas interface
static func _pop_lowest_f(node_list: Array[PathNode]) -> PathNode:
	return _pop_lowest_cost(node_list)

static func _make_node_data(node: PathNode) -> Dictionary:
	return {
		"position": node.position,
		"g": node.g,
		"h": node.h,
		"f": node.f
	}

static func _make_snapshot(
	open_list: Array[PathNode],
	closed_nodes: Array[PathNode],
	current_node: PathNode
) -> Dictionary:
	var open_data: Array = []
	var closed_data: Array = []

	for node in open_list:
		open_data.append(_make_node_data(node))

	for node in closed_nodes:
		closed_data.append(_make_node_data(node))

	var current_data: Dictionary = {}
	if current_node != null:
		current_data = _make_node_data(current_node)

	return {
		"open": open_data,
		"closed": closed_data,
		"current": current_data
	}

# Mengecek apakah tile dapat dilalui:
# HANYA bersumber dari layer 'Path':
# - Jika tile kosong di layer Path (source_id == -1) -> NON-WALKABLE
# - Jika tile berada di blocked_cells (player lain, portal) -> NON-WALKABLE
# - Jika tile ada di layer Path (hijau/kuning) -> WALKABLE
static func is_walkable(path_map: TileMapLayer, cell: Vector2i, blocked_cells: Array = []) -> bool:
	if cell in blocked_cells:
		return false
	if path_map == null:
		return false
	if path_map.get_cell_source_id(cell) == -1:
		return false
	return true

# Algoritma Uniform Cost Search (UCS) dengan perekaman visualisasi langkah debug & bobot path
# Node-node dan validasi pathfinding HANYA diambil dari layer 'Path'
static func find_path_debug(
	path_map: TileMapLayer,
	start: Vector2i,
	end: Vector2i,
	blocked_cells: Array = []
) -> Dictionary:
	var result := {
		"path": [] as Array[Vector2i],
		"steps": []
	}

	if path_map == null:
		return result

	# Jika start terhalang / bukan tile walkable di Path, cari tile walkable terdekat di sekitarnya
	if not is_walkable(path_map, start, blocked_cells):
		var found_start_adj := false
		for offset in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			var adj: Vector2i = start + offset
			if is_walkable(path_map, adj, blocked_cells):
				start = adj
				found_start_adj = true
				break
		if not found_start_adj:
			return result

	# Jika target terhalang / di luar tile Path, cari tile walkable terdekat di sekitarnya
	if not is_walkable(path_map, end, blocked_cells):
		var found_adj := false
		for offset in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			var adj: Vector2i = end + offset
			if is_walkable(path_map, adj, blocked_cells):
				end = adj
				found_adj = true
				break
		if not found_adj:
			return result

	# Jika start sama dengan target
	if start == end:
		var typed_single_path: Array[Vector2i] = [start]
		result["path"] = typed_single_path
		return result

	var open_list: Array[PathNode] = []
	var open_dict: Dictionary = {}
	var closed_set: Dictionary = {}
	var closed_nodes: Array[PathNode] = []

	var start_node := PathNode.new(start)
	start_node.g = 0.0
	start_node.h = 0.0 # True UCS tidak menggunakan heuristik
	start_node.f = 0.0

	open_list.append(start_node)
	open_dict[start] = start_node

	result["steps"].append(_make_snapshot(open_list, closed_nodes, null))

	while open_list.size() > 0:
		# Ambil node dengan cumulative path cost g(n) terendah
		var current_node: PathNode = _pop_lowest_cost(open_list)
		open_dict.erase(current_node.position)
		closed_set[current_node.position] = true
		closed_nodes.append(current_node)

		# Goal test: UCS menguji target saat node di-expand dari antrean prioritas
		if current_node.position == end:
			var path: Array[Vector2i] = []
			var current: PathNode = current_node
			while current != null:
				path.append(current.position)
				current = current.parent
			path.reverse()
			result["path"] = path
			result["steps"].append(_make_snapshot(open_list, closed_nodes, current_node))
			return result

		# Cek 4 arah tetangga (Atas, Bawah, Kiri, Kanan)
		var neighbors := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		for offset in neighbors:
			var neighbor_pos: Vector2i = current_node.position + offset

			if closed_set.has(neighbor_pos):
				continue

			# Validasi hanya dari layer Path
			if not is_walkable(path_map, neighbor_pos, blocked_cells):
				continue

			# Hitung movement cost (kuning = 1.0, hijau = 2.0)
			var step_cost: float = get_step_cost(path_map, neighbor_pos)
			var tentative_g: float = current_node.g + step_cost

			if open_dict.has(neighbor_pos):
				var existing_node: PathNode = open_dict[neighbor_pos]
				# Decrease-key: perbarui biaya jika ditemukan jalur yang lebih murah
				if tentative_g < existing_node.g:
					existing_node.parent = current_node
					existing_node.g = tentative_g
					existing_node.f = tentative_g
				continue

			var neighbor_node := PathNode.new(neighbor_pos, current_node)
			neighbor_node.g = tentative_g
			neighbor_node.h = 0.0 # Tidak ada heuristik dalam UCS
			neighbor_node.f = tentative_g

			open_list.append(neighbor_node)
			open_dict[neighbor_pos] = neighbor_node

		result["steps"].append(_make_snapshot(open_list, closed_nodes, current_node))

	return result

# Wrapper ringkas jika hanya membutuhkan array path tanpa perekaman visualisasi
static func find_path(
	path_map: TileMapLayer,
	start: Vector2i,
	end: Vector2i,
	blocked_cells: Array = []
) -> Array[Vector2i]:
	var result: Dictionary = find_path_debug(path_map, start, end, blocked_cells)
	var path: Array[Vector2i] = []
	if result.has("path"):
		path.assign(result["path"])
	return path
