class_name CustomUCS
extends Node

# A helper inner class to represent each tile point during calculation
class PathNode:
	var position: Vector2i
	var parent: PathNode = null
	var g: float = 0.0 # Cumulative path cost from start
	var h: float = 0.0 # Heuristic cost (always 0.0 in Uniform Cost Search)
	var f: float = 0.0 # Total evaluation score (in UCS: f = g)
	
	func _init(_pos: Vector2i, _parent: PathNode = null):
		self.position = _pos
		self.parent = _parent

static var debug_open_nodes: Array[PathNode] = []
static var debug_closed_nodes: Array[PathNode] = []
static var debug_start: Vector2i = Vector2i.ZERO
static var debug_end: Vector2i = Vector2i.ZERO

# Find and remove the node with the lowest cumulative path cost (g) from the open list
static func _pop_lowest_cost(node_list: Array[PathNode]) -> PathNode:
	var lowest_index := 0
	for i in range(1, node_list.size()):
		if node_list[i].g < node_list[lowest_index].g:
			lowest_index = i
	return node_list.pop_at(lowest_index)

# Kept for interface compatibility with CustomAStar
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

# Helper function to check if a tile is walkable
# - ground_map: TileMapLayer, Array of TileMapLayers, or null (if null, all non-obstacle tiles are walkable)
# - obstacle_map: TileMapLayer, Array of TileMapLayers, or null
# - blocked_cells: Array of Vector2i to treat as obstacles (e.g. other player units)
static func is_walkable(ground_map, obstacle_map, cell: Vector2i, blocked_cells: Array = []) -> bool:
	# 0. Blocked cells check (e.g. other players)
	if cell in blocked_cells:
		return false

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

# ==============================================================================
# UNIFORM COST SEARCH WITH DEBUG SNAPSHOTS (find_path_debug)
# ==============================================================================
static func find_path_debug(
	ground_map,
	obstacle_map,
	start: Vector2i,
	end: Vector2i,
	blocked_cells: Array = []
) -> Dictionary:

	var result := {
		"path": [] as Array[Vector2i],
		"steps": []
	}

	# =========================================
	# VALIDASI START
	# =========================================

	if not is_walkable(ground_map, obstacle_map, start, blocked_cells):
		var found_start_adj := false
		for offset in [
			Vector2i.DOWN,
			Vector2i.UP,
			Vector2i.RIGHT,
			Vector2i.LEFT
		]:
			var adj: Vector2i = start + offset
			if is_walkable(
				ground_map,
				obstacle_map,
				adj,
				blocked_cells
			):
				start = adj
				found_start_adj = true
				break
		if not found_start_adj:
			return result

	# =========================================
	# TARGET TERHALANG
	# =========================================

	if not is_walkable(ground_map, obstacle_map, end, blocked_cells):
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
				adj,
				blocked_cells
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
		var typed_single_path: Array[Vector2i] = [start]
		result["path"] = typed_single_path
		return result

	# =========================================
	# DATA UCS
	# =========================================

	var open_list: Array[PathNode] = []
	var open_dict: Dictionary = {}
	var closed_set: Dictionary = {}
	var closed_nodes: Array[PathNode] = []

	var start_node := PathNode.new(start)
	start_node.g = 0.0
	start_node.h = 0.0 # True UCS: No heuristic
	start_node.f = 0.0 # f = g

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
	# UCS LOOP
	# =========================================

	while open_list.size() > 0:

		# Select node with the lowest cumulative path cost g(n) from priority queue / frontier
		var current_node: PathNode = _pop_lowest_cost(open_list)

		open_dict.erase(current_node.position)
		closed_set[current_node.position] = true
		closed_nodes.append(current_node)

		# =====================================
		# GOAL TEST (True UCS tests goal upon node expansion)
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
		# EXPAND NEIGHBORS
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
				neighbor_pos,
				blocked_cells
			):
				continue

			# Standard grid uniform step cost c(u, v) = 1.0
			var step_cost: float = 1.0
			var tentative_g: float = current_node.g + step_cost

			if open_dict.has(neighbor_pos):

				var existing_node: PathNode = open_dict[neighbor_pos]

				# Decrease-key: if shorter path found to a frontier node, update its cost & parent
				if tentative_g < existing_node.g:
					existing_node.parent = current_node
					existing_node.g = tentative_g
					existing_node.f = tentative_g # In UCS: f = g

				continue

			# Node not yet in frontier: create and insert
			var neighbor_node := PathNode.new(
				neighbor_pos,
				current_node
			)

			neighbor_node.g = tentative_g
			neighbor_node.h = 0.0 # True UCS has no heuristic
			neighbor_node.f = tentative_g

			open_list.append(neighbor_node)
			open_dict[neighbor_pos] = neighbor_node

		# =====================================
		# SAVE ONE UCS STEP
		# =====================================

		result["steps"].append(
			_make_snapshot(
				open_list,
				closed_nodes,
				current_node
			)
		)

	return result

# ==============================================================================
# MAIN UNIFORM COST SEARCH PATHFINDING (find_path)
# ==============================================================================
static func find_path(
	ground_map,
	obstacle_map,
	start: Vector2i,
	end: Vector2i,
	blocked_cells: Array = []
) -> Array[Vector2i]:

	debug_open_nodes.clear()
	debug_closed_nodes.clear()

	debug_start = start
	debug_end = end
	
	# If start is blocked, try adjacent walkable tile
	if not is_walkable(ground_map, obstacle_map, start, blocked_cells):
		var found_start_adj = false
		for offset in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			var adj = start + offset
			if is_walkable(ground_map, obstacle_map, adj, blocked_cells):
				start = adj
				found_start_adj = true
				break
		if not found_start_adj:
			return []

	# If target is directly on an obstacle, try adjacent walkable tile so the player walks up to it
	if not is_walkable(ground_map, obstacle_map, end, blocked_cells):
		var found_adj = false
		for offset in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			var adj = end + offset
			if is_walkable(ground_map, obstacle_map, adj, blocked_cells):
				end = adj
				found_adj = true
				break
		if not found_adj:
			return []

	# If already at destination
	if start == end:
		var typed_single: Array[Vector2i] = [start]
		return typed_single

	var open_list: Array[PathNode] = []
	var open_dict: Dictionary = {}
	var closed_set: Dictionary = {}
	var closed_nodes: Array[PathNode] = []
	
	# Create starting node
	var start_node = PathNode.new(start)
	start_node.g = 0.0
	start_node.h = 0.0
	start_node.f = 0.0

	open_list.append(start_node)
	open_dict[start] = start_node
	
	# Loop until no more paths to explore
	while open_list.size() > 0:
		# Pop node with the lowest cumulative path cost g(n)
		var current_node: PathNode = _pop_lowest_cost(open_list)

		open_dict.erase(current_node.position)
		closed_set[current_node.position] = true
		closed_nodes.append(current_node)
		
		# Check if goal is reached (True UCS tests goal upon node expansion)
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
			
		# Check 4 orthogonal directions (Up, Down, Left, Right)
		var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		for offset in neighbors:
			var neighbor_pos = current_node.position + offset
			
			# Skip if already evaluated
			if closed_set.has(neighbor_pos):
				continue
				
			# Check tile maps validity (walkable ground, no obstacle)
			if not is_walkable(ground_map, obstacle_map, neighbor_pos, blocked_cells):
				continue
				
			# Step cost c(current, neighbor) is 1.0
			var step_cost: float = 1.0
			var tentative_g: float = current_node.g + step_cost
			
			# Check if neighbor is already in open list
			if open_dict.has(neighbor_pos):
				var existing_node: PathNode = open_dict[neighbor_pos]
				if tentative_g < existing_node.g:
					existing_node.parent = current_node
					existing_node.g = tentative_g
					existing_node.f = tentative_g
				continue
				
			# Create neighbor node and add to queue
			var neighbor_node = PathNode.new(neighbor_pos, current_node)
			neighbor_node.g = tentative_g
			neighbor_node.h = 0.0 # No heuristic in True UCS
			neighbor_node.f = tentative_g
			
			open_list.append(neighbor_node)
			open_dict[neighbor_pos] = neighbor_node
			
	debug_closed_nodes = closed_nodes.duplicate()
	debug_open_nodes = open_list.duplicate()

	return []
