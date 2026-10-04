class_name WildernessGenerator
extends RefCounted

## 5x5 Chunk-Based Maze & Enemy Generator (Soul Knight Style)
## Menggunakan Local Search & Optimization (Slide 1-22).
##
## Fitur:
## - 5x5 Chunk (25 Chunk total), masing-masing berukuran 5x5 tile (Total 25x25 tile).
## - Bentuk setiap chunk sesuai sample:
##   - 4 sudut batu (Rock4)
##   - Pintu atas/bawah/kiri/kanan terbuka (Path) atau tertutup (Rock4)
##   - 9 tile interior selalu walkable path
## - Player mulai di Chunk (0, 0).
## - Portal keluar berada di Chunk random (selain 0, 0).
## - Setiap chunk memiliki maksimal 1 enemy (atau 0 enemy).
## - Chunk Start (0, 0) dan Chunk Portal TIDAK BISA memiliki enemy.
## - Local Search mengoptimasi koneksi pintu & sebaran musuh agar
##   labirin solvable dan tantangannya seimbang (Slide 22).

const GRID_W: int = 5
const GRID_H: int = 5
const CHUNK_SIZE: int = 5

class ChunkData:
	var grid_pos: Vector2i = Vector2i.ZERO
	var door_north: bool = false
	var door_south: bool = false
	var door_east: bool = false
	var door_west: bool = false
	var has_enemy: bool = false
	var enemy_threat: float = 0.0
	var enemy_name: String = "Skeleton Guard"
	var enemy_tier: String = "Common"
	var enemy_hp: int = 85
	var enemy_atk: int = 16
	var has_portal: bool = false
	
	func duplicate_chunk() -> ChunkData:
		var c = ChunkData.new()
		c.grid_pos = self.grid_pos
		c.door_north = self.door_north
		c.door_south = self.door_south
		c.door_east = self.door_east
		c.door_west = self.door_west
		c.has_enemy = self.has_enemy
		c.enemy_threat = self.enemy_threat
		c.enemy_name = self.enemy_name
		c.enemy_tier = self.enemy_tier
		c.enemy_hp = self.enemy_hp
		c.enemy_atk = self.enemy_atk
		c.has_portal = self.has_portal
		return c

class MazeState:
	var chunks: Dictionary = {} # Vector2i -> ChunkData
	var start_chunk: Vector2i = Vector2i(0, 0)
	var portal_chunk: Vector2i = Vector2i(4, 4)
	
	# Metrics Evaluasi
	var energy: float = 99999.0
	var is_solvable: bool = false
	var chunk_path: Array = [] # Urutan room dari start ke portal
	var path_threat: float = 0.0
	var reachable_rooms: int = 0
	
	func duplicate_state() -> MazeState:
		var s = MazeState.new()
		s.start_chunk = self.start_chunk
		s.portal_chunk = self.portal_chunk
		s.chunks = {}
		for k in self.chunks.keys():
			s.chunks[k] = self.chunks[k].duplicate_chunk()
		s.energy = self.energy
		s.is_solvable = self.is_solvable
		s.chunk_path = self.chunk_path.duplicate()
		s.path_threat = self.path_threat
		s.reachable_rooms = self.reachable_rooms
		return s

# Pilihan variasi Skeleton untuk enemy
const SKELETON_ROLES: Array = [
	{ "name": "Skeleton Scout", "tier": "Common", "threat": 15.0, "hp": 75, "atk": 14 },
	{ "name": "Skeleton Guard", "tier": "Common", "threat": 20.0, "hp": 90, "atk": 16 },
	{ "name": "Skeleton Warrior", "tier": "Uncommon", "threat": 28.0, "hp": 120, "atk": 22 },
	{ "name": "Skeleton Knight", "tier": "Rare", "threat": 40.0, "hp": 160, "atk": 30 },
	{ "name": "Skeleton Captain", "tier": "Epic", "threat": 55.0, "hp": 210, "atk": 38 }
]

# =========================================================================
# INITIAL STATE GENERATION (Seed Awal / Maze Spanning Tree)
# =========================================================================
func create_initial_state(random_portal: bool = true) -> MazeState:
	var state = MazeState.new()
	state.start_chunk = Vector2i(0, 0)
	
	# Pilih Portal keluar di chunk acak selain (0, 0)
	if random_portal:
		var candidates: Array = []
		for cx in range(GRID_W):
			for cy in range(GRID_H):
				var pos = Vector2i(cx, cy)
				if pos != state.start_chunk and (pos.x >= 2 or pos.y >= 2):
					candidates.append(pos)
		state.portal_chunk = candidates[randi() % candidates.size()]
	else:
		state.portal_chunk = Vector2i(GRID_W - 1, GRID_H - 1)
		
	# Inisialisasi 25 Chunks
	for cx in range(GRID_W):
		for cy in range(GRID_H):
			var pos = Vector2i(cx, cy)
			var chunk = ChunkData.new()
			chunk.grid_pos = pos
			if pos == state.portal_chunk:
				chunk.has_portal = true
			state.chunks[pos] = chunk
			
	# Buat labirin awal dengan Randomized Depth-First Search (DFS) Spanning Tree
	_generate_dfs_maze(state)
	
	# Tambahkan beberapa loop tambahan (10% extra doors) agar labirin punya banyak rute
	_add_random_loops(state, 6)
	
	# Tentukan musuh (maksimal 1 per chunk, portal & start tidak boleh ada musuh)
	for pos in state.chunks.keys():
		if pos == state.start_chunk or pos == state.portal_chunk:
			continue
		var chunk: ChunkData = state.chunks[pos]
		# 55% kemungkinan muncul enemy di chunk ini
		if randf() < 0.55:
			_assign_random_enemy(chunk)
			
	return state

func _generate_dfs_maze(state: MazeState) -> void:
	var visited: Dictionary = {}
	var stack: Array = [state.start_chunk]
	visited[state.start_chunk] = true
	
	while not stack.is_empty():
		var curr: Vector2i = stack[stack.size() - 1]
		var neighbors: Array = []
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n = curr + dir
			if n.x >= 0 and n.x < GRID_W and n.y >= 0 and n.y < GRID_H:
				if not visited.has(n):
					neighbors.append(n)
					
		if neighbors.is_empty():
			stack.pop_back()
		else:
			var chosen: Vector2i = neighbors[randi() % neighbors.size()]
			_open_door_between(state, curr, chosen)
			visited[chosen] = true
			stack.append(chosen)

func _open_door_between(state: MazeState, c1_pos: Vector2i, c2_pos: Vector2i) -> void:
	var c1: ChunkData = state.chunks.get(c1_pos)
	var c2: ChunkData = state.chunks.get(c2_pos)
	if c1 == null or c2 == null:
		return
	var diff = c2_pos - c1_pos
	if diff == Vector2i(1, 0): # c2 di East
		c1.door_east = true
		c2.door_west = true
	elif diff == Vector2i(-1, 0): # c2 di West
		c1.door_west = true
		c2.door_east = true
	elif diff == Vector2i(0, 1): # c2 di South
		c1.door_south = true
		c2.door_north = true
	elif diff == Vector2i(0, -1): # c2 di North
		c1.door_north = true
		c2.door_south = true

func _close_door_between(state: MazeState, c1_pos: Vector2i, c2_pos: Vector2i) -> void:
	var c1: ChunkData = state.chunks.get(c1_pos)
	var c2: ChunkData = state.chunks.get(c2_pos)
	if c1 == null or c2 == null:
		return
	var diff = c2_pos - c1_pos
	if diff == Vector2i(1, 0):
		c1.door_east = false
		c2.door_west = false
	elif diff == Vector2i(-1, 0):
		c1.door_west = false
		c2.door_east = false
	elif diff == Vector2i(0, 1):
		c1.door_south = false
		c2.door_north = false
	elif diff == Vector2i(0, -1):
		c1.door_north = false
		c2.door_south = false

func _add_random_loops(state: MazeState, count: int) -> void:
	for i in range(count):
		var cx = randi() % GRID_W
		var cy = randi() % GRID_H
		var pos = Vector2i(cx, cy)
		var dirs = [Vector2i.RIGHT, Vector2i.DOWN]
		var d = dirs[randi() % dirs.size()]
		var next = pos + d
		if next.x < GRID_W and next.y < GRID_H:
			_open_door_between(state, pos, next)

func _assign_random_enemy(chunk: ChunkData) -> void:
	chunk.has_enemy = true
	var role = SKELETON_ROLES[randi() % SKELETON_ROLES.size()]
	chunk.enemy_name = role.name
	chunk.enemy_tier = role.tier
	chunk.enemy_threat = role.threat
	chunk.enemy_hp = role.hp
	chunk.enemy_atk = role.atk

# =========================================================================
# BFS CHUNK-PATHFINDING (Pencarian Rute Room Start -> Portal)
# =========================================================================
func _find_chunk_path(state: MazeState) -> Array:
	var start = state.start_chunk
	var goal = state.portal_chunk
	
	var queue: Array = [start]
	var came_from: Dictionary = { start: null }
	
	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		if curr == goal:
			var path: Array = []
			var trace = curr
			while trace != null:
				path.append(trace)
				trace = came_from[trace]
			path.reverse()
			return path
			
		var chunk: ChunkData = state.chunks.get(curr, null)
		if chunk == null:
			continue
			
		# Tetangga dengan pintu terbuka kedua arah
		var neighbors: Array = []
		if chunk.door_north and curr.y > 0:
			var n = curr + Vector2i(0, -1)
			var nc = state.chunks.get(n)
			if nc and nc.door_south: neighbors.append(n)
		if chunk.door_south and curr.y < GRID_H - 1:
			var s = curr + Vector2i(0, 1)
			var sc = state.chunks.get(s)
			if sc and sc.door_north: neighbors.append(s)
		if chunk.door_west and curr.x > 0:
			var w = curr + Vector2i(-1, 0)
			var wc = state.chunks.get(w)
			if wc and wc.door_east: neighbors.append(w)
		if chunk.door_east and curr.x < GRID_W - 1:
			var e = curr + Vector2i(1, 0)
			var ec = state.chunks.get(e)
			if ec and ec.door_west: neighbors.append(e)
			
		for next_node in neighbors:
			if not came_from.has(next_node):
				came_from[next_node] = curr
				queue.append(next_node)
				
	return []

# =========================================================================
# OBJECTIVE / FITNESS FUNCTION (Minimasi Energi E - Slide 7, 15, 22)
# =========================================================================
func evaluate_state(state: MazeState, target_difficulty: float) -> float:
	var total_penalty: float = 0.0
	
	# 1. Reachability: Apakah Portal bisa dicapai dari Start (0, 0)?
	var path = _find_chunk_path(state)
	state.chunk_path = path
	
	if path.is_empty():
		state.is_solvable = false
		state.energy = 8000.0 # Penalti besar: labirin buntu
		return state.energy
		
	state.is_solvable = true
	var path_len = path.size()
	
	# 2. Pacing Labirin: Target panjang rute ideal 6 - 9 ruangan
	var desired_len: int = 7
	var len_gap = abs(path_len - desired_len)
	total_penalty += float(len_gap) * 80.0
	
	# 3. Difficulty Balancing (Slide 22: Jumlah & Threat musuh yang dihadapi)
	var accumulated_threat: float = 0.0
	for c_pos in path:
		var chunk: ChunkData = state.chunks[c_pos]
		if chunk.has_enemy:
			accumulated_threat += chunk.enemy_threat
			
	state.path_threat = accumulated_threat
	var diff_gap = abs(accumulated_threat - target_difficulty)
	total_penalty += diff_gap * 15.0
	
	# 4. Coverage / Connected Rooms
	# Hitung berapa room yang bisa dijangkau dari start
	var visited: Dictionary = {}
	var q: Array = [state.start_chunk]
	visited[state.start_chunk] = true
	while not q.is_empty():
		var curr = q.pop_front()
		var chunk: ChunkData = state.chunks[curr]
		var n_list: Array = []
		if chunk.door_north and curr.y > 0 and state.chunks[curr + Vector2i.UP].door_south:
			n_list.append(curr + Vector2i.UP)
		if chunk.door_south and curr.y < GRID_H - 1 and state.chunks[curr + Vector2i.DOWN].door_north:
			n_list.append(curr + Vector2i.DOWN)
		if chunk.door_west and curr.x > 0 and state.chunks[curr + Vector2i.LEFT].door_east:
			n_list.append(curr + Vector2i.LEFT)
		if chunk.door_east and curr.x < GRID_W - 1 and state.chunks[curr + Vector2i.RIGHT].door_west:
			n_list.append(curr + Vector2i.RIGHT)
		for next_r in n_list:
			if not visited.has(next_r):
				visited[next_r] = true
				q.append(next_r)
				
	state.reachable_rooms = visited.size()
	# Penalti jika banyak room terisolasi (kurang dari 20 room terhubung)
	if state.reachable_rooms < 20:
		total_penalty += float(20 - state.reachable_rooms) * 50.0
		
	state.energy = total_penalty
	return total_penalty

# =========================================================================
# NEIGHBOUR GENERATOR (Mutasi Kecil pada State - Slide 6, 7, 15)
# =========================================================================
func generate_neighbour(state: MazeState) -> MazeState:
	var next_state = state.duplicate_state()
	var op = randi() % 4
	
	match op:
		0:
			# Mutasi 1: Toggle Door Horizontal (buka/tutup lorong barat-timur)
			var cx = randi() % (GRID_W - 1)
			var cy = randi() % GRID_H
			var p1 = Vector2i(cx, cy)
			var p2 = Vector2i(cx + 1, cy)
			var c1 = next_state.chunks[p1]
			if c1.door_east:
				_close_door_between(next_state, p1, p2)
			else:
				_open_door_between(next_state, p1, p2)
		1:
			# Mutasi 2: Toggle Door Vertical (buka/tutup lorong utara-selatan)
			var cx = randi() % GRID_W
			var cy = randi() % (GRID_H - 1)
			var p1 = Vector2i(cx, cy)
			var p2 = Vector2i(cx, cy + 1)
			var c1 = next_state.chunks[p1]
			if c1.door_south:
				_close_door_between(next_state, p1, p2)
			else:
				_open_door_between(next_state, p1, p2)
		2:
			# Mutasi 3: Toggle Enemy (Munculkan / Hilangkan enemy di satu chunk)
			var cand: Array = []
			for pos in next_state.chunks.keys():
				if pos != next_state.start_chunk and pos != next_state.portal_chunk:
					cand.append(pos)
			if not cand.is_empty():
				var chosen_pos: Vector2i = cand[randi() % cand.size()]
				var c: ChunkData = next_state.chunks[chosen_pos]
				if c.has_enemy:
					c.has_enemy = false
					c.enemy_threat = 0.0
				else:
					_assign_random_enemy(c)
		3:
			# Mutasi 4: Ubah Rarity / Role Skeleton di chunk yang ada musuhnya
			var enemy_chunks: Array = []
			for pos in next_state.chunks.keys():
				var c = next_state.chunks[pos]
				if c.has_enemy:
					enemy_chunks.append(c)
			if not enemy_chunks.is_empty():
				var c: ChunkData = enemy_chunks[randi() % enemy_chunks.size()]
				_assign_random_enemy(c)
				
	return next_state

# =========================================================================
# ALGORITMA 1: SIMULATED ANNEALING (Slide 14-18)
# =========================================================================
func run_simulated_annealing(
	target_difficulty: float,
	max_steps: int = 300,
	initial_temp: float = 100.0,
	cooling_rate: float = 0.982
) -> Dictionary:
	var current: MazeState = create_initial_state()
	evaluate_state(current, target_difficulty)
	var best: MazeState = current.duplicate_state()
	
	var temp: float = initial_temp
	var history: Array = []
	
	for step in range(max_steps):
		var next_state = generate_neighbour(current)
		evaluate_state(next_state, target_difficulty)
		
		var delta_e = next_state.energy - current.energy
		var accepted = false
		
		if delta_e < 0.0:
			current = next_state
			accepted = true
		else:
			var prob = exp(-delta_e / max(temp, 0.001))
			if randf() < prob:
				current = next_state
				accepted = true
				
		if current.energy < best.energy:
			best = current.duplicate_state()
			
		temp *= cooling_rate
		
		if step % 5 == 0 or step == max_steps - 1:
			history.append({
				"step": step,
				"temp": temp,
				"current_energy": current.energy,
				"best_energy": best.energy,
				"path_threat": current.path_threat,
				"solvable": current.is_solvable,
				"accepted": accepted
			})
			
	return {
		"algorithm": "Simulated Annealing",
		"best_state": best,
		"history": history
	}

# =========================================================================
# ALGORITMA 2: HILL CLIMBING DENGAN RESTART & SIDEWAYS (Slide 7, 10-13)
# =========================================================================
func run_hill_climbing_restart(
	target_difficulty: float,
	max_restarts: int = 5,
	steps_per_restart: int = 60,
	max_sideways: int = 15
) -> Dictionary:
	var best_overall: MazeState = null
	var history: Array = []
	var total_evaluations: int = 0
	
	for r in range(max_restarts):
		var current = create_initial_state()
		evaluate_state(current, target_difficulty)
		var sideways_left = max_sideways
		
		for s in range(steps_per_restart):
			total_evaluations += 1
			
			var best_neighbour: MazeState = null
			for k in range(6):
				var cand = generate_neighbour(current)
				evaluate_state(cand, target_difficulty)
				if best_neighbour == null or cand.energy < best_neighbour.energy:
					best_neighbour = cand
					
			if best_neighbour == null:
				break
				
			var dE = best_neighbour.energy - current.energy
			if dE < -0.01:
				current = best_neighbour
				sideways_left = max_sideways
			elif abs(dE) <= 0.01 and sideways_left > 0:
				current = best_neighbour
				sideways_left -= 1
			else:
				break
				
			if best_overall == null or current.energy < best_overall.energy:
				best_overall = current.duplicate_state()
				
			if s % 5 == 0 or s == steps_per_restart - 1:
				history.append({
					"step": total_evaluations,
					"restart": r + 1,
					"current_energy": current.energy,
					"best_energy": best_overall.energy,
					"path_threat": current.path_threat,
					"solvable": current.is_solvable,
					"accepted": true
				})
				
		if best_overall == null or current.energy < best_overall.energy:
			best_overall = current.duplicate_state()
			
	return {
		"algorithm": "Hill Climbing (Random Restart)",
		"best_state": best_overall,
		"history": history
	}
