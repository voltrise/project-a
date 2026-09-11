class_name CustomAStar
extends Node

# A helper inner class to represent each tile point during calculation
class PathNode:
	var position: Vector2i
	var parent: PathNode = null
	var g: float = 0.0 # Distance from start
	var h: float = 0.0 # Estimated distance to end
	var f: float = 0.0 # Total score (g + h)
	
	func _init(_pos: Vector2i, _parent: PathNode = null):
		self.position = _pos
		self.parent = _parent

static func find_path_debug(
	ground_map,
	obstacle_map,
	start: Vector2i,
	end: Vector2i
) -> Dictionary:

	var result := {
		"path": [],
		"steps": []
	}

	# =========================================
	# VALIDASI START
	# =========================================

	if not is_walkable(ground_map, obstacle_map, start):
		return result

	# =========================================
	# TARGET TERHALANG
	# =========================================

	if not is_walkable(ground_map, obstacle_map, end):
		var found_adj := false

		for offset in [
			Vector2i.DOWN,
			Vector2i.UP,
			Vector2i.RIGHT,
			Vector2i.LEFT
		]:
			var adj: Vector2i = end + offset

			if is_walkable(
				ground_map,
				obstacle_map,
				adj
			):
				end = adj
				found_adj = true
				break

		if not found_adj:
			return result

	# =========================================
	# START = TARGET
	# =========================================

	if start == end:
		result["path"] = [start]
		return result

	# =========================================
	# DATA A*
	# =========================================

	var open_list: Array[PathNode] = []
	var open_dict: Dictionary = {}
	var closed_set: Dictionary = {}
	var closed_nodes: Array[PathNode] = []

	var start_node := PathNode.new(start)

	start_node.g = 0.0
	start_node.h = _get_heuristic(start, end)
	start_node.f = start_node.g + start_node.h

	open_list.append(start_node)
	open_dict[start] = start_node

	# =========================================
	# INITIAL STATE
	# =========================================

	result["steps"].append(
		_make_snapshot(
			open_list,
			closed_nodes,
			null
		)
	)

	# =========================================
	# A* LOOP
	# =========================================

	while open_list.size() > 0:

		var current_node: PathNode = _pop_lowest_f(open_list)

		open_dict.erase(current_node.position)

		closed_set[current_node.position] = true

		closed_nodes.append(current_node)

		# =====================================
		# CHECK TARGET
		# =====================================

		if current_node.position == end:

			var path: Array[Vector2i] = []

			var current: PathNode = current_node

			while current != null:
				path.append(current.position)
				current = current.parent

			path.reverse()

			result["path"] = path

			result["steps"].append(
				_make_snapshot(
					open_list,
					closed_nodes,
					current_node
				)
			)

			return result

		# =====================================
		# CHECK NEIGHBORS
		# =====================================

		var neighbors := [
			Vector2i.UP,
			Vector2i.DOWN,
			Vector2i.LEFT,
			Vector2i.RIGHT
		]

		for offset in neighbors:

			var neighbor_pos: Vector2i = current_node.position + offset

			if closed_set.has(neighbor_pos):
				continue

			if not is_walkable(
				ground_map,
				obstacle_map,
				neighbor_pos
			):
				continue

			var tentative_g := (
				current_node.g + 1.0
			)

			if open_dict.has(neighbor_pos):

				var existing_node: PathNode = (
					open_dict[neighbor_pos]
				)

				if tentative_g < existing_node.g:

					existing_node.parent = current_node
					existing_node.g = tentative_g
					existing_node.f = (
						tentative_g +
						existing_node.h
					)

				continue

			var neighbor_node := PathNode.new(
				neighbor_pos,
				current_node
			)

			neighbor_node.g = tentative_g
			neighbor_node.h = _get_heuristic(
				neighbor_pos,
				end
			)

			neighbor_node.f = (
				neighbor_node.g +
				neighbor_node.h
			)

			open_list.append(neighbor_node)
			open_dict[neighbor_pos] = neighbor_node

		# =====================================
		# SAVE ONE A* STEP
		# =====================================

		result["steps"].append(
			_make_snapshot(
				open_list,
				closed_nodes,
				current_node
			)
		)

	return result

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
		open_data.append(
			_make_node_data(node)
		)

	for node in closed_nodes:
		closed_data.append(
			_make_node_data(node)
		)

	var current_data: Dictionary = {}

	if current_node != null:
		current_data = _make_node_data(current_node)

	return {
		"open": open_data,
		"closed": closed_data,
		"current": current_data
	}

static var debug_open_nodes: Array[PathNode] = []
static var debug_closed_nodes: Array[PathNode] = []
static var debug_start: Vector2i = Vector2i.ZERO
static var debug_end: Vector2i = Vector2i.ZERO

# Calculates Manhattan distance between two tile coordinates
static func _get_heuristic(a: Vector2i, b: Vector2i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y)

# Find the node with the lowest F score in an array
static func _pop_lowest_f(node_list: Array[PathNode]) -> PathNode:
	var lowest_index = 0
	for i in range(1, node_list.size()):
		if node_list[i].f < node_list[lowest_index].f:
			lowest_index = i
	return node_list.pop_at(lowest_index)

# Helper function to check if a tile is walkable
# - ground_map: TileMapLayer, Array of TileMapLayers, or null (if null, all non-obstacle tiles are walkable)
# - obstacle_map: TileMapLayer, Array of TileMapLayers, or null
static func is_walkable(ground_map, obstacle_map, cell: Vector2i) -> bool:
	# 1. Obstacle check: if there is a tile in obstacle_map, it is blocked
	if obstacle_map != null:
		if obstacle_map is TileMapLayer:
			if obstacle_map.get_cell_source_id(cell) != -1:
				return false
		elif obstacle_map is Array:
			for obs in obstacle_map:
				if obs != null and obs.get_cell_source_id(cell) != -1:
					return false

	# 2. Walkable ground check: only enforce if ground_map is specified
	if ground_map != null:
		if ground_map is TileMapLayer:
			if ground_map.get_cell_source_id(cell) == -1:
				return false
		elif ground_map is Array and ground_map.size() > 0:
			var on_ground = false
			for gm in ground_map:
				if gm != null and gm.get_cell_source_id(cell) != -1:
					on_ground = true
					break
			if not on_ground:
				return false

	return true

# The main custom pathfinding function
static func find_path(ground_map, obstacle_map, start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	debug_open_nodes.clear()
	debug_closed_nodes.clear()

	debug_start = start
	debug_end = end
	
	# If start is blocked, cannot pathfind
	if not is_walkable(ground_map, obstacle_map, start):
		return []

	# If target is directly on an obstacle, try adjacent walkable tile so the player walks up to it
	if not is_walkable(ground_map, obstacle_map, end):
		var found_adj = false
		for offset in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			var adj = end + offset
			if is_walkable(ground_map, obstacle_map, adj):
				end = adj
				found_adj = true
				break
		if not found_adj:
			return []

	# If already at destination
	if start == end:
		return [start]

	var open_list: Array[PathNode] = []
	var open_dict: Dictionary = {}
	var closed_set: Dictionary = {}
	var closed_nodes: Array[PathNode] = []
	
	# Create starting node
	var start_node = PathNode.new(start)
	open_list.append(start_node)
	open_dict[start] = start_node
	
	# Loop until no more paths to explore
	while open_list.size() > 0:
		var current_node: PathNode = _pop_lowest_f(open_list)

		open_dict.erase(current_node.position)
		closed_set[current_node.position] = true
		closed_nodes.append(current_node)
		
		# 2. Check if goal is reached
		if current_node.position == end:
			debug_closed_nodes = closed_nodes.duplicate()
			debug_open_nodes = open_list.duplicate()

			var path: Array[Vector2i] = []
			var current: PathNode = current_node

			while current != null:
				path.append(current.position)
				current = current.parent

			path.reverse()

			return path
			
		# 3. Check 4 directions (Up, Down, Left, Right)
		var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		for offset in neighbors:
			var neighbor_pos = current_node.position + offset
			
			# Skip if already evaluated
			if closed_set.has(neighbor_pos):
				continue
				
			# Check tile maps validity (walkable ground, no obstacle)
			if not is_walkable(ground_map, obstacle_map, neighbor_pos):
				continue
				
			# Calculate costs
			var tentative_g = current_node.g + 1.0 # 1.0 weight per tile step
			
			# Check if neighbor is already in open list
			if open_dict.has(neighbor_pos):
				var existing_node: PathNode = open_dict[neighbor_pos]
				if tentative_g < existing_node.g:
					existing_node.parent = current_node
					existing_node.g = tentative_g
					existing_node.f = tentative_g + existing_node.h
				continue
				
			# Create neighbor node and add to queue
			var neighbor_node = PathNode.new(neighbor_pos, current_node)
			neighbor_node.g = tentative_g
			neighbor_node.h = _get_heuristic(neighbor_pos, end)
			neighbor_node.f = neighbor_node.g + neighbor_node.h
			
			open_list.append(neighbor_node)
			open_dict[neighbor_pos] = neighbor_node
			
	debug_closed_nodes = closed_nodes.duplicate()
	debug_open_nodes = open_list.duplicate()

	return []
