class_name CSPSolver
extends RefCounted

## Constraint Satisfaction Problem (CSP) Solver
## Mengimplementasikan materi kuliah CSP (Slide 1-46):
## - Backtracking Search (Slide 17, 21, 43)
## - MRV (Minimum Remaining Values - Slide 22, 23)
## - MRV + Degree Heuristic Tie-Breaker (Slide 25, 26)
## - LCV (Least Constraining Value - Slide 28, 30)
## - Forward Checking (Slide 31)
## - AC-3 Arc Consistency via REVISE(X, Y) (Slide 34-43)

enum VarHeuristic {
	FIXED = 0,       # Urutan tetap (tanpa MRV)
	MRV = 1,         # Minimum Remaining Values (fail-first)
	MRV_DEGREE = 2   # MRV dengan tie-breaker Degree Heuristic (slide 26)
}

enum ValHeuristic {
	DEFAULT = 0,     # Urutan daftar domain default
	LCV = 1          # Least Constraining Value (succeed-first, slide 28)
}

enum InferenceMode {
	NONE = 0,
	FORWARD_CHECKING = 1,
	AC3 = 2          # Full Arc Consistency AC-3 (slide 37, 43)
}

# Metrik hasil pencarian (untuk pelaporan statistik)
var assignments_tried: int = 0
var backtracks_count: int = 0
var ac3_prunes_count: int = 0
var max_backtracks: int = 1500
var time_taken_ms: float = 0.0

# Step-by-step visualizer recording
var record_steps: bool = false
var step_history: Array = []
const MAX_RECORDED_STEPS: int = 250

# Konfigurasi aktif
var var_heuristic: int = VarHeuristic.MRV_DEGREE
var val_heuristic: int = ValHeuristic.LCV
var inference_mode: int = InferenceMode.AC3

# Definisi masalah:
# variables: Array of Variant (misal Vector2i untuk posisi chunk)
# domains: Dictionary { var: Array of Variant }
# neighbors: Dictionary { var: Array of Variant }
# binary_constraint_fn: Callable(var_x, val_x, var_y, val_y) -> bool
# global_validator_fn: Callable(assignments) -> bool (optional)
var variables: Array = []
var initial_domains: Dictionary = {}
var neighbor_graph: Dictionary = {}
var constraint_fn: Callable
var global_validator: Callable

func setup(
	p_variables: Array,
	p_domains: Dictionary,
	p_neighbors: Dictionary,
	p_constraint_fn: Callable,
	p_global_validator: Callable = Callable()
) -> void:
	variables = p_variables.duplicate()
	initial_domains = {}
	for k in p_domains.keys():
		initial_domains[k] = p_domains[k].duplicate()
	neighbor_graph = {}
	for k in p_neighbors.keys():
		neighbor_graph[k] = p_neighbors[k].duplicate()
	constraint_fn = p_constraint_fn
	global_validator = p_global_validator
	
	assignments_tried = 0
	backtracks_count = 0
	ac3_prunes_count = 0

## Menjalankan pencarian CSP
func solve() -> Dictionary:
	var start_time = Time.get_ticks_msec()
	assignments_tried = 0
	backtracks_count = 0
	ac3_prunes_count = 0
	step_history.clear()
	
	# Salin domain awal
	var current_domains: Dictionary = {}
	for v in variables:
		current_domains[v] = initial_domains[v].duplicate()
	
	if record_steps:
		step_history.append({
			"phase": "csp",
			"type": "init",
			"var": null,
			"val": "",
			"assignments": {},
			"domains": _clone_domains(current_domains),
			"desc": "Initial setup: Applied unary border constraints across %d chunks." % variables.size()
		})
		
	# Pre-processing AC-3 jika diaktifkan (Slide 37)
	if inference_mode == InferenceMode.AC3:
		var ac3_ok = run_ac3(current_domains)
		if record_steps:
			step_history.append({
				"phase": "csp",
				"type": "ac3_preprocess",
				"var": null,
				"val": "",
				"assignments": {},
				"domains": _clone_domains(current_domains),
				"desc": "AC-3 Pre-processing: Eliminated %d arc-inconsistent template values." % ac3_prunes_count
			})
		if not ac3_ok:
			time_taken_ms = Time.get_ticks_msec() - start_time
			return {
				"success": false,
				"assignments": {},
				"assignments_tried": assignments_tried,
				"backtracks_count": backtracks_count,
				"ac3_prunes": ac3_prunes_count,
				"time_ms": time_taken_ms,
				"steps": step_history
			}
			
	var initial_assignments: Dictionary = {}
	var result = _backtrack(initial_assignments, current_domains)
	
	time_taken_ms = Time.get_ticks_msec() - start_time
	
	if record_steps and result != null:
		step_history.append({
			"phase": "csp",
			"type": "success",
			"var": null,
			"val": "",
			"assignments": result.duplicate(),
			"domains": _clone_domains(current_domains),
			"desc": "CSP Complete: Consistent door alignment found for all chunks!"
		})
	
	return {
		"success": result != null,
		"assignments": result if result != null else {},
		"assignments_tried": assignments_tried,
		"backtracks_count": backtracks_count,
		"ac3_prunes": ac3_prunes_count,
		"time_ms": time_taken_ms,
		"steps": step_history
	}

# =========================================================================
# BACKTRACKING CORE (Slide 21 & 43)
# =========================================================================
func _backtrack(assignments: Dictionary, domains: Dictionary):
	# 1. Base case: Jika semua variabel sudah ter-assign
	if assignments.size() == variables.size():
		if global_validator.is_valid():
			if not global_validator.call(assignments):
				return null # Melanggar batasan global
		return assignments.duplicate()
		
	# 2. SELECT-VARIABLE (Slide 21, 26)
	var x = _select_unassigned_variable(assignments, domains)
	if x == null:
		return null
		
	# 3. ORDER-VALUES (Slide 21, 28)
	var values = _order_domain_values(x, assignments, domains)
	
	# 4. Loop setiap nilai yang mungkin
	for v in values:
		# Periksa konsistensi lokal dengan variabel tetangga yang sudah ter-assign
		if _is_consistent(x, v, assignments):
			assignments[x] = v
			assignments_tried += 1
			
			if record_steps and step_history.size() < MAX_RECORDED_STEPS:
				step_history.append({
					"phase": "csp",
					"type": "assign",
					"var": x,
					"val": v,
					"assignments": assignments.duplicate(),
					"domains": _clone_domains(domains),
					"desc": "Assign %s to [%d, %d] (Candidate selected, domain size: %d)" % [v, x.x, x.y, domains[x].size()]
				})
			
			# Jalankan inferensi (Slide 43)
			var domains_copy: Dictionary = _clone_domains(domains)
			domains_copy[x] = [v] # Nilai x terikat
			
			var inference_ok = true
			if inference_mode == InferenceMode.FORWARD_CHECKING:
				inference_ok = _forward_checking(x, v, domains_copy, assignments)
			elif inference_mode == InferenceMode.AC3:
				inference_ok = _ac3_inference(x, domains_copy, assignments)
				
			if inference_ok:
				var res = _backtrack(assignments, domains_copy)
				if res != null:
					return res
					
			# Gagal / Dead-end: Backtrack & restore (Slide 21)
			backtracks_count += 1
			if backtracks_count >= max_backtracks:
				return null
			assignments.erase(x)
			
			if record_steps and step_history.size() < MAX_RECORDED_STEPS:
				step_history.append({
					"phase": "csp",
					"type": "backtrack",
					"var": x,
					"val": v,
					"assignments": assignments.duplicate(),
					"domains": _clone_domains(domains),
					"desc": "Backtrack from [%d, %d]: %s caused empty domain downstream" % [x.x, x.y, v]
				})
			
	return null

# =========================================================================
# HEURISTIK PEMILIHAN VARIABEL (MRV + DEGREE - Slide 22-26)
# =========================================================================
func _select_unassigned_variable(assignments: Dictionary, domains: Dictionary):
	var unassigned: Array = []
	for v in variables:
		if not assignments.has(v):
			unassigned.append(v)
			
	if unassigned.is_empty():
		return null
		
	if var_heuristic == VarHeuristic.FIXED:
		return unassigned[0]
		
	# Heuristik MRV: Pilih variabel dengan sisa domain terkecil (Slide 22)
	var min_domain_size: int = 999999
	var mrv_candidates: Array = []
	
	for v in unassigned:
		var d_size: int = domains[v].size()
		if d_size < min_domain_size:
			min_domain_size = d_size
			mrv_candidates = [v]
		elif d_size == min_domain_size:
			mrv_candidates.append(v)
			
	if mrv_candidates.size() == 1 or var_heuristic == VarHeuristic.MRV:
		return mrv_candidates[0]
		
	# Tie-breaker: Degree Heuristic (Slide 25, 26)
	# Pilih variabel yang terlibat dengan unassigned variables paling banyak
	var best_var = mrv_candidates[0]
	var max_degree: int = -1
	
	for v in mrv_candidates:
		var degree: int = 0
		var nbs: Array = neighbor_graph.get(v, [])
		for nb in nbs:
			if not assignments.has(nb):
				degree += 1
		if degree > max_degree:
			max_degree = degree
			best_var = v
			
	return best_var

# =========================================================================
# HEURISTIK PEMILIHAN NILAI (LCV - Slide 28, 30)
# =========================================================================
func _order_domain_values(x, assignments: Dictionary, domains: Dictionary) -> Array:
	var vals: Array = domains[x].duplicate()
	if val_heuristic == ValHeuristic.DEFAULT or vals.size() <= 1:
		return vals
		
	# LCV (Least Constraining Value):
	# Urutkan nilai berdasarkan seberapa sedikit opsi legal tetangga yang dieliminasi
	var scored: Array = []
	var unassigned_neighbors: Array = []
	for nb in neighbor_graph.get(x, []):
		if not assignments.has(nb):
			unassigned_neighbors.append(nb)
			
	for v in vals:
		var eliminated_count: int = 0
		for nb in unassigned_neighbors:
			for nb_val in domains[nb]:
				if not constraint_fn.call(x, v, nb, nb_val):
					eliminated_count += 1
		scored.append({ "val": v, "conflicts": eliminated_count })
		
	# Urutkan ascending: Yang mengeliminasi paling sedikit didahulukan (succeed-first)
	scored.sort_custom(func(a, b): return a.conflicts < b.conflicts)
	
	var sorted_vals: Array = []
	for item in scored:
		sorted_vals.append(item.val)
	return sorted_vals

# =========================================================================
# KONSISTENSI LOKAL
# =========================================================================
func _is_consistent(x, v, assignments: Dictionary) -> bool:
	for nb in neighbor_graph.get(x, []):
		if assignments.has(nb):
			var nb_val = assignments[nb]
			if not constraint_fn.call(x, v, nb, nb_val):
				return false
	return true

# =========================================================================
# INFERENSI: FORWARD CHECKING (Slide 31)
# =========================================================================
func _forward_checking(x, v, domains: Dictionary, assignments: Dictionary) -> bool:
	for nb in neighbor_graph.get(x, []):
		if not assignments.has(nb):
			var valid_options: Array = []
			for nb_val in domains[nb]:
				if constraint_fn.call(x, v, nb, nb_val):
					valid_options.append(nb_val)
				else:
					ac3_prunes_count += 1
			if valid_options.is_empty():
				return false # Domain tetangga kosong -> gagal
			domains[nb] = valid_options
	return true

# =========================================================================
# INFERENSI: AC-3 ALGORITHM DENGAN REVISE (Slide 34-39, 43)
# =========================================================================
func run_ac3(domains: Dictionary) -> bool:
	var queue: Array = []
	for u in variables:
		for v in neighbor_graph.get(u, []):
			queue.append([u, v])
	return _process_ac3_queue(queue, domains)

func _ac3_inference(assigned_x, domains: Dictionary, assignments: Dictionary) -> bool:
	var queue: Array = []
	for nb in neighbor_graph.get(assigned_x, []):
		if not assignments.has(nb):
			queue.append([nb, assigned_x])
	return _process_ac3_queue(queue, domains)

func _process_ac3_queue(queue: Array, domains: Dictionary) -> bool:
	while not queue.is_empty():
		var arc: Array = queue.pop_front()
		var xi = arc[0]
		var xj = arc[1]
		
		if _revise(xi, xj, domains):
			if domains[xi].is_empty():
				return false # Wipeout! (Slide 37)
			# Masukkan kembali arc tetangga Z -> Xi (kecuali Xj)
			for zk in neighbor_graph.get(xi, []):
				if zk != xj:
					var exists = false
					for q in queue:
						if q[0] == zk and q[1] == xi:
							exists = true
							break
					if not exists:
						queue.push_back([zk, xi])
	return true

## Fungsi REVISE(X, Y) persis seperti Slide 36:
## Menghilangkan value pada X yang tidak memiliki support di Y
func _revise(xi, xj, domains: Dictionary) -> bool:
	var revised: bool = false
	var remaining: Array = []
	
	for x_val in domains[xi]:
		var has_support: bool = false
		for y_val in domains[xj]:
			if constraint_fn.call(xi, x_val, xj, y_val):
				has_support = true
				break
		if has_support:
			remaining.append(x_val)
		else:
			revised = true
			ac3_prunes_count += 1
			
	if revised:
		domains[xi] = remaining
	return revised

func _clone_domains(src: Dictionary) -> Dictionary:
	var dest: Dictionary = {}
	for k in src.keys():
		dest[k] = src[k].duplicate()
	return dest
