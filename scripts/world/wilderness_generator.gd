class_name WildernessGenerator
extends RefCounted

## Hybrid Generator: CSP (Backtracking + MRV + LCV + AC-3) + Local Search
##
## 1. Fase CSP:
##    - Membangun layout grid chunk yang 100% konsisten (koneksi pintu antar chunk cocok).
##    - Memastikan pintu Start (0, 0) dan Exit Portal terhubung tanpa jalan buntu.
##    - Menggunakan CSPSolver (Backtracking, MRV/MRV+Degree, LCV, Forward Checking/AC-3).
##
## 2. Fase Local Search:
##    - Mengambil layout legal dari CSP.
##    - Mengisi musuh dan item dari WildernessTemplates.
##    - Menyetel penempatan musuh/item agar tingkat kesulitan (Difficulty)
##      mendekati target user (Easy, Medium, Hard).
##    - Menggunakan Simulated Annealing atau Hill Climbing dengan Random Restarts.

const CSPSolverClass = preload("res://scripts/world/csp_solver.gd")

class GeneratedMapState:
	var grid_w: int = 5
	var grid_h: int = 5
	var start_chunk: Vector2i = Vector2i(0, 0)
	var portal_chunk: Vector2i = Vector2i(4, 4)
	
	# Mapping: Vector2i -> template_id (String)
	var chunk_templates: Dictionary = {}
	
	# Mapping: Vector2i -> Entity Data
	# Entity Data: { "type": "enemy"|"item"|"empty", "node_name": String, "name": String, "threat": float, "benefit": float, "tier": String, "hp": int, "atk": int }
	var chunk_entities: Dictionary = {}
	
	# Evaluasi & Analisis
	var chunk_path: Array = [] # Urutan rute Start -> Portal
	var difficulty_score: float = 0.0
	var energy: float = 99999.0
	var is_solvable: bool = false
	
	func duplicate_state() -> GeneratedMapState:
		var s = GeneratedMapState.new()
		s.grid_w = self.grid_w
		s.grid_h = self.grid_h
		s.start_chunk = self.start_chunk
		s.portal_chunk = self.portal_chunk
		s.chunk_templates = self.chunk_templates.duplicate()
		s.chunk_entities = {}
		for k in self.chunk_entities.keys():
			s.chunk_entities[k] = self.chunk_entities[k].duplicate()
		s.chunk_path = self.chunk_path.duplicate()
		s.difficulty_score = self.difficulty_score
		s.energy = self.energy
		s.is_solvable = self.is_solvable
		return s

var templates_mgr = null
var csp_solver: CSPSolverClass = null

func _init(p_templates_mgr = null) -> void:
	templates_mgr = p_templates_mgr
	csp_solver = CSPSolverClass.new()

# =========================================================================
# 1. FASE CSP: GENERASI STRUKTUR CHUNK (DOOR MATCHING & REACHABILITY)
# =========================================================================
func run_csp_chunk_generation(
	var_heuristic: int = 2,    # 0: Fixed, 1: MRV, 2: MRV+Degree
	val_heuristic: int = 1,    # 0: Default, 1: LCV
	inference_mode: int = 2,   # 0: None, 1: Forward Checking, 2: AC-3
	random_portal: bool = true,
	record_steps: bool = false
) -> Dictionary:
	var gw = templates_mgr.grid_chunks_n if templates_mgr else 5
	var gh = templates_mgr.grid_chunks_m if templates_mgr else 5
	
	# Spawn player di sisi luar map (coastline/border)
	var coastline_candidates: Array = []
	for cx in range(gw):
		for cy in range(gh):
			if cx == 0 or cx == gw - 1 or cy == 0 or cy == gh - 1:
				coastline_candidates.append(Vector2i(cx, cy))
	var start_pos = coastline_candidates[randi() % coastline_candidates.size()]
	
	var portal_pos = Vector2i(gw - 1, gh - 1)
	if random_portal:
		var portal_candidates: Array = []
		var min_dist = max(3, int((gw + gh) * 0.45))
		for cx in range(gw):
			for cy in range(gh):
				var p = Vector2i(cx, cy)
				var dist = abs(p.x - start_pos.x) + abs(p.y - start_pos.y)
				if p != start_pos and dist >= min_dist:
					portal_candidates.append(p)
		if portal_candidates.is_empty():
			for cx in range(gw):
				for cy in range(gh):
					var p = Vector2i(cx, cy)
					if p != start_pos: portal_candidates.append(p)
		portal_pos = portal_candidates[randi() % portal_candidates.size()]

	# Variabel CSP: Setiap koordinat chunk (x, y)
	var variables: Array = []
	for cx in range(gw):
		for cy in range(gh):
			variables.append(Vector2i(cx, cy))
			
	# Buat Graf Tetangga (Grid Adjacency)
	var neighbors: Dictionary = {}
	for pos in variables:
		var nbs: Array = []
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nb = pos + dir
			if nb.x >= 0 and nb.x < gw and nb.y >= 0 and nb.y < gh:
				nbs.append(nb)
		neighbors[pos] = nbs
		
	# Ambil semua template dari template manager
	var raw_templates = templates_mgr.get_chunk_templates() if templates_mgr else []
	var template_dict: Dictionary = {}
	for tpl in raw_templates:
		template_dict[tpl.id] = tpl
		
	# Bangun spine path rute awal Start -> Portal sebagai panduan Unary Constraint
	var spine_path: Array = _generate_spine_path(start_pos, portal_pos, gw, gh)
	
	# Inisialisasi Domain per Variabel dengan Unary Constraints (Border Walls)
	var initial_domains: Dictionary = {}
	for pos in variables:
		var allowed: Array = []
		for tpl in raw_templates:
			var doors: Array = tpl.doors # [N, S, E, W]
			# Border Unary Constraints: Pintu tidak boleh mengarah keluar batas map
			if pos.y == 0 and doors[0]: continue
			if pos.y == gh - 1 and doors[1]: continue
			if pos.x == gw - 1 and doors[2]: continue
			if pos.x == 0 and doors[3]: continue
			
			# Start & Portal tidak boleh Solid (harus ada minimal 1 pintu)
			if (pos == start_pos or pos == portal_pos) and tpl.id == "SOLID":
				continue
				
			allowed.append(tpl.id)
			
		# Acak sedikit urutan domain untuk menghasilkan variasi labirin tiap run
		allowed.shuffle()
		initial_domains[pos] = allowed

	# Terapkan Unary Constraint untuk spine path agar jalur dijamin terhubung tanpa loop buntu
	for i in range(spine_path.size()):
		var p_curr: Vector2i = spine_path[i]
		var req_doors: Dictionary = {}
		if i > 0:
			var p_prev: Vector2i = spine_path[i - 1]
			var diff = p_prev - p_curr
			if diff == Vector2i(0, -1): req_doors[0] = true
			elif diff == Vector2i(0, 1): req_doors[1] = true
			elif diff == Vector2i(1, 0): req_doors[2] = true
			elif diff == Vector2i(-1, 0): req_doors[3] = true
		if i < spine_path.size() - 1:
			var p_next: Vector2i = spine_path[i + 1]
			var diff = p_next - p_curr
			if diff == Vector2i(0, -1): req_doors[0] = true
			elif diff == Vector2i(0, 1): req_doors[1] = true
			elif diff == Vector2i(1, 0): req_doors[2] = true
			elif diff == Vector2i(-1, 0): req_doors[3] = true
			
		var constrained: Array = []
		for tpl_id in initial_domains[p_curr]:
			var tpl = template_dict[tpl_id]
			var match_all = true
			for d_idx in req_doors.keys():
				if not tpl.doors[d_idx]:
					match_all = false
					break
			if match_all:
				constrained.append(tpl_id)
		if not constrained.is_empty():
			initial_domains[p_curr] = constrained
		
	# Binary Constraint Function: Pintu antar 2 chunk yang bertetangga harus cocok!
	# (Jika A membuka ke Timur, tetangga B di Timur WAJIB membuka ke Barat)
	var constraint_func = func(pos_a: Vector2i, tpl_a_id: String, pos_b: Vector2i, tpl_b_id: String) -> bool:
		var tpl_a = template_dict[tpl_a_id]
		var tpl_b = template_dict[tpl_b_id]
		var diff = pos_b - pos_a
		if diff == Vector2i(1, 0): # B di Timur A
			return tpl_a.doors[2] == tpl_b.doors[3]
		elif diff == Vector2i(-1, 0): # B di Barat A
			return tpl_a.doors[3] == tpl_b.doors[2]
		elif diff == Vector2i(0, 1): # B di Selatan A
			return tpl_a.doors[1] == tpl_b.doors[0]
		elif diff == Vector2i(0, -1): # B di Utara A
			return tpl_a.doors[0] == tpl_b.doors[1]
		return true

	# Global Validator: Jalur dari Start ke Portal harus terhubung
	var global_validator = func(assignments: Dictionary) -> bool:
		var path = _find_bfs_path(assignments, template_dict, start_pos, portal_pos, gw, gh)
		return not path.is_empty()

	# Konfigurasi solver
	csp_solver.var_heuristic = var_heuristic
	csp_solver.val_heuristic = val_heuristic
	csp_solver.inference_mode = inference_mode
	csp_solver.record_steps = record_steps
	
	csp_solver.setup(variables, initial_domains, neighbors, constraint_func, global_validator)
	var csp_result = csp_solver.solve()
	
	var map_state = GeneratedMapState.new()
	map_state.grid_w = gw
	map_state.grid_h = gh
	map_state.start_chunk = start_pos
	map_state.portal_chunk = portal_pos
	
	if csp_result.success:
		map_state.chunk_templates = csp_result.assignments.duplicate()
		# Reachability Rule: Setiap chunk non-solid WAJIB dapat dilewati oleh player!
		# Jika ada chunk yang terputus dari Start, ubah menjadi SOLID (closed off)
		var reachable = get_reachable_chunks(map_state.chunk_templates, template_dict, start_pos, gw, gh)
		for pos in variables:
			if not reachable.has(pos):
				map_state.chunk_templates[pos] = "SOLID"
				
		map_state.chunk_path = _find_bfs_path(map_state.chunk_templates, template_dict, start_pos, portal_pos, gw, gh)
		map_state.is_solvable = not map_state.chunk_path.is_empty()
	else:
		# Fallback darurat jika ada constraint over-constrained
		_build_fallback_connected_layout(map_state, template_dict)
		map_state.chunk_path = _find_bfs_path(map_state.chunk_templates, template_dict, start_pos, portal_pos, gw, gh)
		map_state.is_solvable = not map_state.chunk_path.is_empty()
		
	return {
		"csp_result": csp_result,
		"map_state": map_state,
		"steps": csp_result.get("steps", [])
	}

# =========================================================================
# 2. FASE LOCAL SEARCH: POPULASI & BALANCING MUSUH SERTA ITEM
# =========================================================================
func run_local_search_optimization(
	base_map: GeneratedMapState,
	target_difficulty: float = 80.0,
	algorithm: String = "simulated_annealing",
	max_steps: int = 150,
	record_steps: bool = false
) -> Dictionary:
	var enemy_pool = templates_mgr.get_enemy_pool() if templates_mgr else []
	var item_pool = templates_mgr.get_item_pool() if templates_mgr else []
	
	# Inisialisasi entitas awal di semua chunk legal (bukan start, bukan portal)
	var current_state = base_map.duplicate_state()
	_initialize_random_entities(current_state, enemy_pool, item_pool)
	_evaluate_state(current_state, target_difficulty)
	
	var best_state = current_state.duplicate_state()
	var history: Array = []
	var search_steps: Array = []
	
	if record_steps:
		search_steps.append({
			"phase": "local_search",
			"type": "init",
			"step_num": 0,
			"state": current_state.duplicate_state(),
			"energy": current_state.energy,
			"diff": current_state.difficulty_score,
			"target_diff": target_difficulty,
			"temp": 100.0,
			"var": current_state.start_chunk,
			"op_name": "Inisialisasi",
			"mut_detail": "Menempatkan sebaran awal musuh dan item acak di ruang kosong.",
			"delta_e": 0.0,
			"prev_energy": current_state.energy,
			"prev_diff": current_state.difficulty_score,
			"accepted": true,
			"acceptance_mode": "init",
			"desc": "Inisialisasi Entitas Awal: Difficulty = %.1f (Target = %.1f, Energy = %.1f)" % [current_state.difficulty_score, target_difficulty, current_state.energy]
		})
	
	if algorithm == "simulated_annealing":
		var temp = 100.0
		var cooling = 0.97
		for step in range(max_steps):
			var prev_energy = current_state.energy
			var prev_diff = current_state.difficulty_score
			var neighbor = current_state.duplicate_state()
			var mut_info = _mutate_state(neighbor, enemy_pool, item_pool)
			_evaluate_state(neighbor, target_difficulty)
			
			var delta_e = neighbor.energy - current_state.energy
			var is_improvement = delta_e < 0.0
			var accept_prob = exp(-delta_e / max(0.01, temp))
			var accepted_by_temp = (not is_improvement) and (randf() < accept_prob)
			var accepted = is_improvement or accepted_by_temp
			if accepted:
				current_state = neighbor
				if current_state.energy < best_state.energy:
					best_state = current_state.duplicate_state()
					
			if record_steps and (step < 35 or step % 2 == 0 or step == max_steps - 1) and search_steps.size() < 150:
				var target_pos = mut_info.get("target_pos", Vector2i.ZERO)
				var act = "Improved (ΔE = %.1f)" % delta_e if is_improvement else ("Accepted by Temp (P=%.1f%%)" % (accept_prob * 100.0) if accepted else "Rejected (ΔE = +%.1f)" % delta_e)
				search_steps.append({
					"phase": "local_search",
					"type": "mutate",
					"step_num": step + 1,
					"state": current_state.duplicate_state(),
					"energy": current_state.energy,
					"diff": current_state.difficulty_score,
					"target_diff": target_difficulty,
					"temp": temp,
					"var": target_pos,
					"other_var": mut_info.get("other_pos", null),
					"op_name": mut_info.get("op_name", "Mutasi"),
					"mut_detail": mut_info.get("detail", ""),
					"delta_e": delta_e,
					"prev_energy": prev_energy,
					"prev_diff": prev_diff,
					"accepted": accepted,
					"acceptance_mode": "improvement" if is_improvement else ("probabilistic" if accepted else "rejected"),
					"accept_prob": accept_prob,
					"desc": "Step %d: %s [%d, %d] - %s" % [step + 1, mut_info.get("op_name", "Mutasi"), target_pos.x, target_pos.y, act]
				})
			temp *= cooling
			if step % 5 == 0 or step == max_steps - 1:
				history.append({
					"step": step,
					"temp": temp,
					"current_energy": current_state.energy,
					"best_energy": best_state.energy,
					"current_diff": current_state.difficulty_score
				})
	else:
		# Hill Climbing dengan Random Restarts
		var restarts = 4
		var steps_per_restart = int(max_steps / restarts)
		for r in range(restarts):
			if r > 0:
				current_state = base_map.duplicate_state()
				_initialize_random_entities(current_state, enemy_pool, item_pool)
				_evaluate_state(current_state, target_difficulty)
				
			for step in range(steps_per_restart):
				var neighbor = current_state.duplicate_state()
				_mutate_state(neighbor, enemy_pool, item_pool)
				_evaluate_state(neighbor, target_difficulty)
				
				if neighbor.energy <= current_state.energy:
					current_state = neighbor
					if current_state.energy < best_state.energy:
						best_state = current_state.duplicate_state()
						
				if step % 4 == 0:
					history.append({
						"step": r * steps_per_restart + step,
						"restart": r + 1,
						"current_energy": current_state.energy,
						"best_energy": best_state.energy,
						"current_diff": current_state.difficulty_score
					})
					
	return {
		"best_state": best_state,
		"history": history,
		"algorithm": algorithm,
		"target_difficulty": target_difficulty,
		"steps": search_steps
	}

# =========================================================================
# HELPER LOCAL SEARCH: EVALUASI & MUTASI
# =========================================================================
func _evaluate_state(state: GeneratedMapState, target_difficulty: float) -> void:
	var path_threat: float = 0.0
	var side_threat: float = 0.0
	var item_benefits: float = 0.0
	
	var path_set: Dictionary = {}
	for p in state.chunk_path:
		path_set[p] = true
		
	for pos in state.chunk_entities.keys():
		var ent = state.chunk_entities[pos]
		if ent.type == "enemy":
			if path_set.has(pos):
				path_threat += ent.threat
			else:
				side_threat += ent.threat * 0.35
		elif ent.type == "item":
			if path_set.has(pos):
				item_benefits += ent.benefit
			else:
				item_benefits += ent.benefit * 0.5
				
	# Formula Difficulty:
	# Panjang Rute * 8 + Ancaman Musuh - Bantuan Item
	var path_len_score = float(state.chunk_path.size()) * 8.0
	state.difficulty_score = max(5.0, path_len_score + path_threat + side_threat - item_benefits)
	state.energy = abs(state.difficulty_score - target_difficulty)

func _initialize_random_entities(state: GeneratedMapState, enemy_pool: Array, item_pool: Array) -> void:
	state.chunk_entities.clear()
	for cx in range(state.grid_w):
		for cy in range(state.grid_h):
			var pos = Vector2i(cx, cy)
			# Start dan Portal TIDAK BISA memiliki enemy maupun item
			if pos == state.start_chunk or pos == state.portal_chunk:
				continue
				
			var tpl_id = state.chunk_templates.get(pos, "SOLID")
			if tpl_id == "SOLID":
				continue
				
			var roll = randf()
			if roll < 0.50 and not enemy_pool.is_empty():
				# Spawn Enemy
				var e = enemy_pool[randi() % enemy_pool.size()]
				state.chunk_entities[pos] = {
					"type": "enemy",
					"node_name": e.node_name,
					"name": e.name,
					"threat": e.threat,
					"tier": e.tier,
					"hp": e.hp,
					"atk": e.atk,
					"benefit": 0.0
				}
			elif roll < 0.75 and not item_pool.is_empty():
				# Spawn Item
				var it = item_pool[randi() % item_pool.size()]
				state.chunk_entities[pos] = {
					"type": "item",
					"node_name": it.node_name,
					"name": it.name,
					"benefit": it.benefit,
					"item_type": it.type,
					"threat": 0.0,
					"tier": "Common",
					"hp": 0,
					"atk": 0
				}
			else:
				state.chunk_entities[pos] = { "type": "empty", "threat": 0.0, "benefit": 0.0 }

func _mutate_state(state: GeneratedMapState, enemy_pool: Array, item_pool: Array) -> Dictionary:
	# Pilih satu chunk non-start, non-portal secara acak untuk dimutasi
	var valid_candidates: Array = []
	for cx in range(state.grid_w):
		for cy in range(state.grid_h):
			var pos = Vector2i(cx, cy)
			if pos != state.start_chunk and pos != state.portal_chunk:
				var tpl_id = state.chunk_templates.get(pos, "SOLID")
				if tpl_id != "SOLID":
					valid_candidates.append(pos)
					
	if valid_candidates.is_empty():
		return {}
		
	var target_pos = valid_candidates[randi() % valid_candidates.size()]
	var op = randi() % 4
	var op_name = ""
	var detail = ""
	var other_pos = null
	
	match op:
		0: # Ubah ke enemy lain (upgrade / downgrade)
			if not enemy_pool.is_empty():
				var e = enemy_pool[randi() % enemy_pool.size()]
				state.chunk_entities[target_pos] = {
					"type": "enemy",
					"node_name": e.node_name,
					"name": e.name,
					"threat": e.threat,
					"tier": e.tier,
					"hp": e.hp,
					"atk": e.atk,
					"benefit": 0.0
				}
				op_name = "Spawn/Mutate Enemy"
				detail = "Menempatkan musuh %s (Tier %s, Threat %.1f, HP %d, ATK %d)" % [e.name, e.tier, e.threat, e.hp, e.atk]
			else:
				op_name = "None"
		1: # Pasang item
			if not item_pool.is_empty():
				var it = item_pool[randi() % item_pool.size()]
				state.chunk_entities[target_pos] = {
					"type": "item",
					"node_name": it.node_name,
					"name": it.name,
					"benefit": it.benefit,
					"item_type": it.type,
					"threat": 0.0,
					"tier": "Common",
					"hp": 0,
					"atk": 0
				}
				op_name = "Spawn Item"
				detail = "Menaruh item bantuan %s (+%.1f Benefit)" % [it.name, it.benefit]
			else:
				op_name = "None"
		2: # Kosongkan chunk
			state.chunk_entities[target_pos] = { "type": "empty", "threat": 0.0, "benefit": 0.0 }
			op_name = "Clear Chunk"
			detail = "Mengosongkan entitas pada chunk [%d, %d]" % [target_pos.x, target_pos.y]
		3: # Tukar isi dengan chunk lain
			other_pos = valid_candidates[randi() % valid_candidates.size()]
			if other_pos != target_pos:
				var tmp = state.chunk_entities.get(target_pos, { "type": "empty" })
				state.chunk_entities[target_pos] = state.chunk_entities.get(other_pos, { "type": "empty" })
				state.chunk_entities[other_pos] = tmp
				op_name = "Swap Entities"
				detail = "Menukar entitas chunk [%d, %d] dengan [%d, %d]" % [target_pos.x, target_pos.y, other_pos.x, other_pos.y]
			else:
				op_name = "Swap Self"
				detail = "Tidak ada pertukaran (chunk target sama)"
				
	return {
		"target_pos": target_pos,
		"other_pos": other_pos,
		"op": op,
		"op_name": op_name,
		"detail": detail
	}
# PATHFINDING BFS ANTAR CHUNK (Memvalidasi Reachability Start -> Portal)
# =========================================================================
func _find_bfs_path(assignments: Dictionary, tpl_dict: Dictionary, start: Vector2i, goal: Vector2i, gw: int, gh: int) -> Array:
	if not assignments.has(start) or not assignments.has(goal):
		return []
		
	var queue: Array = [start]
	var visited: Dictionary = { start: true }
	var parent: Dictionary = {}
	
	var dirs = [
		{ "vec": Vector2i.UP, "out_idx": 0, "in_idx": 1 },
		{ "vec": Vector2i.DOWN, "out_idx": 1, "in_idx": 0 },
		{ "vec": Vector2i.RIGHT, "out_idx": 2, "in_idx": 3 },
		{ "vec": Vector2i.LEFT, "out_idx": 3, "in_idx": 2 }
	]
	
	var found = false
	while not queue.is_empty():
		var curr = queue.pop_front()
		if curr == goal:
			found = true
			break
			
		var curr_tpl = tpl_dict.get(assignments.get(curr, "SOLID"))
		if curr_tpl == null:
			continue
			
		for d in dirs:
			if curr_tpl.doors[d.out_idx]: # Pintu terbuka ke arah d
				var nxt = curr + d.vec
				if nxt.x >= 0 and nxt.x < gw and nxt.y >= 0 and nxt.y < gh:
					if not visited.has(nxt):
						var nxt_tpl = tpl_dict.get(assignments.get(nxt, "SOLID"))
						if nxt_tpl != null and nxt_tpl.doors[d.in_idx]:
							visited[nxt] = true
							parent[nxt] = curr
							queue.push_back(nxt)
							
	if not found:
		return []
		
	var path: Array = []
	var step = goal
	while step != start:
		path.push_front(step)
		step = parent[step]
	path.push_front(start)
	return path

func _build_fallback_connected_layout(state: GeneratedMapState, tpl_dict: Dictionary) -> void:
	for cx in range(state.grid_w):
		for cy in range(state.grid_h):
			var pos = Vector2i(cx, cy)
			# Fallback ke 4-way dengan penyesuaian border
			state.chunk_templates[pos] = "4WAY"

# =========================================================================
# REACHABILITY CALCULATOR & FULL PIPELINE WITH TIMELINE
# =========================================================================
func get_reachable_chunks(assignments: Dictionary, tpl_dict: Dictionary, start: Vector2i, gw: int, gh: int) -> Dictionary:
	if not assignments.has(start):
		return {}
	var queue: Array = [start]
	var visited: Dictionary = { start: true }
	var dirs = [
		{ "vec": Vector2i.UP, "out_idx": 0, "in_idx": 1 },
		{ "vec": Vector2i.DOWN, "out_idx": 1, "in_idx": 0 },
		{ "vec": Vector2i.RIGHT, "out_idx": 2, "in_idx": 3 },
		{ "vec": Vector2i.LEFT, "out_idx": 3, "in_idx": 2 }
	]
	while not queue.is_empty():
		var curr = queue.pop_front()
		var curr_tpl = tpl_dict.get(assignments.get(curr, "SOLID"))
		if curr_tpl == null:
			continue
		for d in dirs:
			if curr_tpl.doors[d.out_idx]:
				var nxt = curr + d.vec
				if nxt.x >= 0 and nxt.x < gw and nxt.y >= 0 and nxt.y < gh:
					if not visited.has(nxt):
						var nxt_tpl = tpl_dict.get(assignments.get(nxt, "SOLID"))
						if nxt_tpl != null and nxt_tpl.doors[d.in_idx]:
							visited[nxt] = true
							queue.push_back(nxt)
	return visited

func generate_full_map_with_timeline(
	var_h: int = 2,
	val_h: int = 1,
	inf_m: int = 2,
	target_diff: float = 80.0,
	ls_algo: String = "simulated_annealing",
	max_ls_steps: int = 80
) -> Dictionary:
	var csp_res = run_csp_chunk_generation(var_h, val_h, inf_m, true, true)
	var ls_res = run_local_search_optimization(csp_res.map_state, target_diff, ls_algo, max_ls_steps, true)
	
	var timeline: Array = []
	for s in csp_res.get("steps", []):
		timeline.append(s)
	for s in ls_res.get("steps", []):
		timeline.append(s)
		
	return {
		"csp_res": csp_res,
		"ls_res": ls_res,
		"final_state": ls_res.best_state,
		"timeline": timeline
	}

func _generate_spine_path(start: Vector2i, goal: Vector2i, gw: int, gh: int) -> Array:
	var curr = start
	var path: Array = [curr]
	var visited: Dictionary = { curr: true }
	var max_attempts = 40
	var attempts = 0
	
	while curr != goal and attempts < max_attempts:
		attempts += 1
		var nbs: Array = []
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nb = curr + dir
			if nb.x >= 0 and nb.x < gw and nb.y >= 0 and nb.y < gh and not visited.has(nb):
				nbs.append(nb)
		if nbs.is_empty():
			return _generate_spine_path(start, goal, gw, gh)
			
		nbs.shuffle()
		nbs.sort_custom(func(a, b):
			var da = abs(a.x - goal.x) + abs(a.y - goal.y)
			var db = abs(b.x - goal.x) + abs(b.y - goal.y)
			return da < db
		)
		curr = nbs[0]
		path.append(curr)
		visited[curr] = true
		
	return path
