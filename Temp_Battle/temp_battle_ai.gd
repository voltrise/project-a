class_name TempBattleAI
extends RefCounted

const TempBattleState = preload("res://Temp_Battle/temp_battle_state.gd")

## Adversarial Search Engine untuk Turn-Based Duel (Tugas Besar Tahap 2).
##
## Fitur:
## 1. Minimax standar
## 2. Alpha-Beta Pruning
## 3. Heuristic Move Ordering (Optimal vs Default vs Reverse)
## 4. Evaluasi Multi-Personality (Balanced, Aggressive, Defensive, HP Ratio)
## 5. Expectimax (Stochastic Chance Nodes)
## 6. Root Candidate Action & Score Breakdown
## 7. Automated Experiment Runner (Depth, Eval, Move Ordering)

enum Algorithm { ALPHABETA = 0, MINIMAX = 1, EXPECTIMAX = 2 }
enum EvalType { BALANCED = 0, AGGRESSIVE = 1, DEFENSIVE = 2, HP_RATIO = 3 }
enum MoveOrdering { OPTIMAL = 0, DEFAULT = 1, REVERSE = 2 }

const WIN_SCORE: float = 100000.0

var total_nodes: int = 0
var prune_count: int = 0


# ══════════════════════════════════════════════════════════════════════
#  MAIN DECISION INTERFACE (ROOT SEARCH)
# ══════════════════════════════════════════════════════════════════════

func decide_action(
	state: TempBattleState,
	depth: int = 4,
	algo: int = Algorithm.ALPHABETA,
	eval_type: int = EvalType.BALANCED,
	ordering: int = MoveOrdering.OPTIMAL,
	piece: int = TempBattleState.Side.ENEMY
) -> Dictionary:
	total_nodes = 0
	prune_count = 0
	var start_time_usec := Time.get_ticks_usec()

	var valid_actions := state.get_valid_actions()
	if valid_actions.is_empty():
		return {"action": -1, "score": 0.0, "total_nodes": 0, "prune_count": 0, "time_ms": 0.0, "candidates": []}

	var ordered_actions := order_actions(state, valid_actions, true, piece, ordering)

	var candidates: Array[Dictionary] = []
	var best_action: int = ordered_actions[0]
	var best_score: float = -INF
	var alpha: float = -INF
	var beta: float = INF

	for act in ordered_actions:
		var node_before := total_nodes
		var child := state.clone()
		child.apply_action(act, false)

		var score: float = 0.0

		match algo:
			Algorithm.MINIMAX:
				var res := _minimax(child, depth - 1, false, piece, eval_type)
				score = res[0]
			Algorithm.ALPHABETA:
				var res := _alphabeta(child, depth - 1, alpha, beta, false, piece, eval_type, ordering)
				score = res[0]
				if score > best_score:
					best_score = score
					best_action = act
				alpha = maxf(alpha, best_score)
			Algorithm.EXPECTIMAX:
				var res := _expectimax_chance(state, act, depth - 1, false, piece, eval_type)
				score = res

		if algo != Algorithm.ALPHABETA:
			if score > best_score:
				best_score = score
				best_action = act

		var branch_nodes := total_nodes - node_before
		candidates.append({
			"action": act,
			"name": TempBattleState.get_action_name(act),
			"score": score,
			"nodes": branch_nodes,
			"is_best": false
		})

	for c in candidates:
		if c["action"] == best_action:
			c["is_best"] = true

	var elapsed_ms: float = float(Time.get_ticks_usec() - start_time_usec) / 1000.0

	return {
		"action": best_action,
		"action_name": TempBattleState.get_action_name(best_action),
		"score": best_score,
		"total_nodes": total_nodes,
		"prune_count": prune_count,
		"time_ms": elapsed_ms,
		"candidates": candidates
	}


# ══════════════════════════════════════════════════════════════════════
#  1. MINIMAX
# ══════════════════════════════════════════════════════════════════════

func _minimax(
	state: TempBattleState,
	depth: int,
	maximizing: bool,
	piece: int,
	eval_type: int
) -> Array:
	total_nodes += 1

	if state.is_terminal():
		var winner := state.get_winner()
		if winner == piece:
			return [WIN_SCORE + float(depth), -1]
		elif winner != -1:
			return [-(WIN_SCORE + float(depth)), -1]
		return [0.0, -1]

	if depth <= 0:
		return [evaluate(state, piece, eval_type), -1]

	var valid_actions := state.get_valid_actions()
	if valid_actions.is_empty():
		return [evaluate(state, piece, eval_type), -1]

	if maximizing:
		var max_eval: float = -INF
		var best_act: int = valid_actions[0]
		for act in valid_actions:
			var child := state.clone()
			child.apply_action(act, false)
			var res := _minimax(child, depth - 1, false, piece, eval_type)
			if res[0] > max_eval:
				max_eval = res[0]
				best_act = act
		return [max_eval, best_act]
	else:
		var min_eval: float = INF
		var best_act: int = valid_actions[0]
		for act in valid_actions:
			var child := state.clone()
			child.apply_action(act, false)
			var res := _minimax(child, depth - 1, true, piece, eval_type)
			if res[0] < min_eval:
				min_eval = res[0]
				best_act = act
		return [min_eval, best_act]


# ══════════════════════════════════════════════════════════════════════
#  2. ALPHA-BETA PRUNING
# ══════════════════════════════════════════════════════════════════════

func _alphabeta(
	state: TempBattleState,
	depth: int,
	alpha: float,
	beta: float,
	maximizing: bool,
	piece: int,
	eval_type: int,
	ordering: int
) -> Array:
	total_nodes += 1

	if state.is_terminal():
		var winner := state.get_winner()
		if winner == piece:
			return [WIN_SCORE + float(depth), -1]
		elif winner != -1:
			return [-(WIN_SCORE + float(depth)), -1]
		return [0.0, -1]

	if depth <= 0:
		return [evaluate(state, piece, eval_type), -1]

	var valid_actions := state.get_valid_actions()
	if valid_actions.is_empty():
		return [evaluate(state, piece, eval_type), -1]

	var actions := order_actions(state, valid_actions, maximizing, piece, ordering)

	if maximizing:
		var max_eval: float = -INF
		var best_act: int = actions[0]
		for act in actions:
			var child := state.clone()
			child.apply_action(act, false)
			var res := _alphabeta(child, depth - 1, alpha, beta, false, piece, eval_type, ordering)
			if res[0] > max_eval:
				max_eval = res[0]
				best_act = act
			alpha = maxf(alpha, max_eval)
			if alpha >= beta:
				prune_count += 1
				break
		return [max_eval, best_act]
	else:
		var min_eval: float = INF
		var best_act: int = actions[0]
		for act in actions:
			var child := state.clone()
			child.apply_action(act, false)
			var res := _alphabeta(child, depth - 1, alpha, beta, true, piece, eval_type, ordering)
			if res[0] < min_eval:
				min_eval = res[0]
				best_act = act
			beta = minf(beta, min_eval)
			if alpha >= beta:
				prune_count += 1
				break
		return [min_eval, best_act]


# ══════════════════════════════════════════════════════════════════════
#  3. EXPECTIMAX
# ══════════════════════════════════════════════════════════════════════

func _expectimax(
	state: TempBattleState,
	depth: int,
	is_agent_turn: bool,
	piece: int,
	eval_type: int
) -> Array:
	total_nodes += 1

	if state.is_terminal():
		var winner := state.get_winner()
		if winner == piece:
			return [WIN_SCORE + float(depth), -1]
		elif winner != -1:
			return [-(WIN_SCORE + float(depth)), -1]
		return [0.0, -1]

	if depth <= 0:
		return [evaluate(state, piece, eval_type), -1]

	var valid_actions := state.get_valid_actions()
	if valid_actions.is_empty():
		return [evaluate(state, piece, eval_type), -1]

	if is_agent_turn:
		var max_eval: float = -INF
		var best_act: int = valid_actions[0]
		for act in valid_actions:
			var expected_val := _expectimax_chance(state, act, depth - 1, false, piece, eval_type)
			if expected_val > max_eval:
				max_eval = expected_val
				best_act = act
		return [max_eval, best_act]
	else:
		var min_eval: float = INF
		var best_act: int = valid_actions[0]
		for act in valid_actions:
			var expected_val := _expectimax_chance(state, act, depth - 1, true, piece, eval_type)
			if expected_val < min_eval:
				min_eval = expected_val
				best_act = act
		return [min_eval, best_act]


func _expectimax_chance(
	state: TempBattleState,
	action: int,
	depth: int,
	next_is_agent: bool,
	piece: int,
	eval_type: int
) -> float:
	match action:
		TempBattleState.Action.ATTACK, TempBattleState.Action.HEAVY_ATTACK:
			var child_normal := state.clone()
			child_normal.apply_action(action, false)
			var res_normal := _expectimax(child_normal, depth, next_is_agent, piece, eval_type)

			var child_crit := state.clone()
			child_crit.apply_action(action, true)
			var res_crit := _expectimax(child_crit, depth, next_is_agent, piece, eval_type)

			var p_crit: float = 0.20 if action == TempBattleState.Action.ATTACK else 0.15
			return (1.0 - p_crit) * float(res_normal[0]) + p_crit * float(res_crit[0])

		_:
			# DEFEND dan REST sepenuhnya deterministik
			var child := state.clone()
			child.apply_action(action, false)
			var res := _expectimax(child, depth, next_is_agent, piece, eval_type)
			return float(res[0])


# ══════════════════════════════════════════════════════════════════════
#  4. MOVE ORDERING (HEURISTIC)
# ══════════════════════════════════════════════════════════════════════

func order_actions(
	state: TempBattleState,
	actions: Array[int],
	maximizing: bool,
	piece: int,
	order_mode: int
) -> Array[int]:
	if order_mode == MoveOrdering.DEFAULT:
		return actions

	var scored: Array[Dictionary] = []
	var actor := state.get_current_fighter()
	var target := state.get_opponent_fighter()

	for act in actions:
		var quick_h: float = 0.0
		match act:
			TempBattleState.Action.HEAVY_ATTACK:
				quick_h = 35.0
				if target.get("is_guard_broken", false):
					quick_h += 60.0  # Punish broken enemy!
				elif target.get("is_defending", false) and target["stamina"] <= TempBattleState.HEAVY_STAMINA_DMG:
					quick_h += 70.0  # Break posture!
				elif target["hp"] <= TempBattleState.HEAVY_DAMAGE:
					quick_h += 85.0  # Lethal hit

			TempBattleState.Action.ATTACK:
				quick_h = 25.0
				if target.get("is_guard_broken", false):
					quick_h += 40.0
				elif target.get("is_defending", false) and target["stamina"] <= TempBattleState.ATTACK_STAMINA_DMG:
					quick_h += 60.0  # Break posture!
				elif target["hp"] <= TempBattleState.ATTACK_DAMAGE:
					quick_h += 75.0  # Lethal hit

			TempBattleState.Action.REST:
				if actor["stamina"] < TempBattleState.ATTACK_COST:
					quick_h = 65.0  # Sangat butuh stamina untuk menyerang
				elif actor["stamina"] < TempBattleState.HEAVY_COST:
					quick_h = 30.0
				elif actor["stamina"] >= 80:
					quick_h = -15.0  # Kurang efisien jika stamina sudah tinggi
				else:
					quick_h = 10.0

			TempBattleState.Action.DEFEND:
				if actor["hp"] < 35 and target["stamina"] >= TempBattleState.ATTACK_COST:
					quick_h = 35.0  # Bertahan dari potensi lethal lawan
				elif actor.get("is_guard_broken", false):
					quick_h = -50.0
				else:
					quick_h = 15.0

		scored.append({"action": act, "h": quick_h})

	scored.sort_custom(func(a, b): return a["h"] > b["h"])

	var result: Array[int] = []
	for item in scored:
		result.append(item["action"])

	if order_mode == MoveOrdering.REVERSE:
		result.reverse()

	return result


# ══════════════════════════════════════════════════════════════════════
#  5. EVALUATION FUNCTIONS
# ══════════════════════════════════════════════════════════════════════

func evaluate(state: TempBattleState, piece: int, eval_type: int) -> float:
	var opp_piece: int = TempBattleState.Side.PLAYER if piece == TempBattleState.Side.ENEMY else TempBattleState.Side.ENEMY
	var my := state.get_fighter(piece)
	var opp := state.get_fighter(opp_piece)

	match eval_type:
		EvalType.BALANCED:
			var score: float = 0.0
			score += (float(my["hp"]) - float(opp["hp"])) * 1.0
			score += (float(my["stamina"]) - float(opp["stamina"])) * 0.40
			if opp.get("is_guard_broken", false):
				score += 45.0
			if my.get("is_guard_broken", false):
				score -= 45.0
			if my.get("is_defending", false):
				score += 5.0
			if opp.get("is_defending", false):
				score -= 5.0
			return score

		EvalType.AGGRESSIVE:
			var score: float = 0.0
			score -= float(opp["hp"]) * 2.5
			score += float(my["hp"]) * 0.8
			score += float(my["stamina"]) * 0.30
			if opp.get("is_guard_broken", false):
				score += 65.0
			if my.get("is_guard_broken", false):
				score -= 35.0
			return score

		EvalType.DEFENSIVE:
			var score: float = 0.0
			score += float(my["hp"]) * 2.2
			score -= float(opp["hp"]) * 0.7
			score += float(my["stamina"]) * 0.70
			if my.get("is_defending", false):
				score += 10.0
			if my.get("is_guard_broken", false):
				score -= 65.0
			return score

		EvalType.HP_RATIO:
			var my_ratio: float = float(my["hp"]) / float(my["max_hp"])
			var opp_ratio: float = float(opp["hp"]) / float(opp["max_hp"])
			return (my_ratio - opp_ratio) * 100.0

	return 0.0


# ══════════════════════════════════════════════════════════════════════
#  6. AUTOMATED EXPERIMENT / BENCHMARK RUNNER
# ══════════════════════════════════════════════════════════════════════

func run_ai_experiments(state: TempBattleState) -> Dictionary:
	var results := {
		"depth_comparison": [],
		"eval_comparison": [],
		"order_comparison": []
	}

	print("
══════════════════════════════════════════════════════════════")
	print("       EXPERIMENT 1: MINIMAX vs ALPHA-BETA (DEPTH 1..5)       ")
	print("══════════════════════════════════════════════════════════════")
	print("| Depth | Minimax Nodes (ms) | AB Nodes (ms) | Pruned | AB+Order Nodes | Match? |")
	print("|-------|--------------------|---------------|--------|----------------|--------|")

	for d in range(1, 6):
		total_nodes = 0
		var mm_res := decide_action(state, d, Algorithm.MINIMAX, EvalType.BALANCED, MoveOrdering.DEFAULT)
		var mm_nodes := total_nodes
		var mm_time: float = mm_res["time_ms"]

		total_nodes = 0
		prune_count = 0
		var ab_res := decide_action(state, d, Algorithm.ALPHABETA, EvalType.BALANCED, MoveOrdering.DEFAULT)
		var ab_nodes := total_nodes
		var ab_prunes := prune_count
		var ab_time: float = ab_res["time_ms"]

		total_nodes = 0
		prune_count = 0
		var abo_res := decide_action(state, d, Algorithm.ALPHABETA, EvalType.BALANCED, MoveOrdering.OPTIMAL)
		var abo_nodes := total_nodes
		var abo_time: float = abo_res["time_ms"]

		var score_match: bool = absf(mm_res["score"] - ab_res["score"]) < 0.01

		results["depth_comparison"].append({
			"depth": d,
			"mm_nodes": mm_nodes,
			"mm_time_ms": mm_time,
			"ab_nodes": ab_nodes,
			"ab_time_ms": ab_time,
			"ab_prunes": ab_prunes,
			"abo_nodes": abo_nodes,
			"abo_time_ms": abo_time,
			"match": score_match
		})

		print("| %-5d | %-18s | %-13s | %-6d | %-14s | %-6s |" % [
			d,
			"%d (%.2f ms)" % [mm_nodes, mm_time],
			"%d (%.2f ms)" % [ab_nodes, ab_time],
			ab_prunes,
			"%d (%.2f ms)" % [abo_nodes, abo_time],
			str(score_match)
		])

	# Experiment 2: Evaluation Functions Comparison (Depth 4)
	print("
══════════════════════════════════════════════════════════════")
	print("       EXPERIMENT 2: EVALUATION FUNCTIONS (DEPTH 4)           ")
	print("══════════════════════════════════════════════════════════════")
	var eval_names := ["Balanced", "Aggressive", "Defensive", "HP Ratio"]
	for et in [EvalType.BALANCED, EvalType.AGGRESSIVE, EvalType.DEFENSIVE, EvalType.HP_RATIO]:
		var r := decide_action(state, 4, Algorithm.ALPHABETA, et, MoveOrdering.OPTIMAL)
		results["eval_comparison"].append({
			"eval_name": eval_names[et],
			"action_name": r["action_name"],
			"score": r["score"],
			"nodes": r["total_nodes"]
		})
		print("• %-12s -> Action: %-12s | Score: %8.2f | Nodes: %d" % [
			eval_names[et], r["action_name"], r["score"], r["total_nodes"]
		])

	# Experiment 3: Move Ordering Comparison (AB Depth 4)
	print("
══════════════════════════════════════════════════════════════")
	print("       EXPERIMENT 3: MOVE ORDERING EFFICIENCY (DEPTH 4)       ")
	print("══════════════════════════════════════════════════════════════")
	var order_names := ["Optimal (Heuristic)", "Default (No Sort)", "Reverse (Worst)"]
	for mo in [MoveOrdering.OPTIMAL, MoveOrdering.DEFAULT, MoveOrdering.REVERSE]:
		var r := decide_action(state, 4, Algorithm.ALPHABETA, EvalType.BALANCED, mo)
		results["order_comparison"].append({
			"order_name": order_names[mo],
			"action_name": r["action_name"],
			"nodes": r["total_nodes"],
			"prunes": r["prune_count"]
		})
		print("• %-22s -> Nodes: %-6d | Prunes: %-4d | Action: %s" % [
			order_names[mo], r["total_nodes"], r["prune_count"], r["action_name"]
		])

	return results
