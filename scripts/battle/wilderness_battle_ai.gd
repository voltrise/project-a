class_name WildernessBattleAI
extends RefCounted

const StateClass = preload("res://scripts/battle/wilderness_battle_state.gd")

## Adversarial Search Engine untuk Wilderness Turn-Based Duel.
## Mendukung Minimax, Alpha-Beta Pruning, Move Ordering, dan Multi-Personality Evaluation.

enum Algorithm { ALPHABETA = 0, MINIMAX = 1, EXPECTIMAX = 2 }
enum EvalType {
	BALANCED = 0,
	AGGRESSIVE = 1,
	DEFENSIVE = 2,
	BERZERKER = 3,
	TACTICIAN = 4,
	JUGGERNAUT = 5
}
enum MoveOrdering { OPTIMAL = 0, DEFAULT = 1, REVERSE = 2 }

static func get_personality_for_enemy(enemy_name: String) -> int:
	var norm = enemy_name.to_lower().replace(" ", "").replace("_", "")
	if norm.contains("troll") or norm.contains("minotaur") or norm.contains("torch"):
		return EvalType.BERZERKER
	elif norm.contains("thief") or norm.contains("spear"):
		return EvalType.TACTICIAN
	elif norm.contains("panda"):
		return EvalType.JUGGERNAUT
	else:
		return EvalType.AGGRESSIVE

const WIN_SCORE: float = 100000.0

var total_nodes: int = 0
var prune_count: int = 0


# ══════════════════════════════════════════════════════════════════════
#  MAIN DECISION INTERFACE (ROOT SEARCH)
# ══════════════════════════════════════════════════════════════════════

func decide_action(
	state: StateClass,
	depth: int = 4,
	algo: int = Algorithm.ALPHABETA,
	eval_type: int = EvalType.AGGRESSIVE,
	ordering: int = MoveOrdering.OPTIMAL,
	piece: int = StateClass.Side.ENEMY
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
	var best_effective_score: float = -INF
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
				alpha = maxf(alpha, score)
			Algorithm.EXPECTIMAX:
				var res := _expectimax_chance(state, act, depth - 1, false, piece, eval_type)
				score = res

		# Aggressive tempo tie-breaker:
		# Jika dua opsi bernilai hampir sama, dahulukan menyerang daripada pasif guarding/resting
		var tempo_bonus: float = 0.0
		if act == StateClass.Action.HEAVY_ATTACK:
			tempo_bonus = 2.5
		elif act == StateClass.Action.ATTACK:
			tempo_bonus = 1.5
		elif act == StateClass.Action.DEFEND:
			tempo_bonus = -3.0

		var effective_score: float = score + tempo_bonus
		if effective_score > best_effective_score:
			best_effective_score = effective_score
			best_score = score
			best_action = act

		var branch_nodes := total_nodes - node_before
		candidates.append({
			"action": act,
			"name": StateClass.get_action_name(act),
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
		"action_name": StateClass.get_action_name(best_action),
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
	state: StateClass,
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
	state: StateClass,
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
	state: StateClass,
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
	state: StateClass,
	action: int,
	depth: int,
	next_is_agent: bool,
	piece: int,
	eval_type: int
) -> float:
	match action:
		StateClass.Action.ATTACK, StateClass.Action.HEAVY_ATTACK:
			var child_normal := state.clone()
			child_normal.apply_action(action, false)
			var res_normal := _expectimax(child_normal, depth, next_is_agent, piece, eval_type)

			var child_crit := state.clone()
			child_crit.apply_action(action, true)
			var res_crit := _expectimax(child_crit, depth, next_is_agent, piece, eval_type)

			var p_crit: float = 0.20 if action == StateClass.Action.ATTACK else 0.15
			return (1.0 - p_crit) * float(res_normal[0]) + p_crit * float(res_crit[0])

		_:
			var child := state.clone()
			child.apply_action(action, false)
			var res := _expectimax(child, depth, next_is_agent, piece, eval_type)
			return float(res[0])


# ══════════════════════════════════════════════════════════════════════
#  4. MOVE ORDERING
# ══════════════════════════════════════════════════════════════════════

func order_actions(
	state: StateClass,
	actions: Array[int],
	maximizing: bool,
	piece: int,
	order_mode: int
) -> Array[int]:
	if order_mode == MoveOrdering.DEFAULT:
		return actions

	var scored: Array[Dictionary] = []
	var actor := state.player if state.current_turn == StateClass.Side.PLAYER else state.enemy
	var target := state.enemy if state.current_turn == StateClass.Side.PLAYER else state.player

	var atk_c = state.get_attack_cost(state.current_turn)
	var hvy_c = state.get_heavy_cost(state.current_turn)
	var atk_d = state.get_attack_damage(state.current_turn)
	var hvy_d = state.get_heavy_damage(state.current_turn)

	for act in actions:
		var quick_h: float = 0.0
		match act:
			StateClass.Action.HEAVY_ATTACK:
				quick_h = 60.0
				if target.get("is_guard_broken", false):
					quick_h += 80.0
				elif target.get("is_defending", false) and target["stamina"] <= StateClass.HEAVY_STAMINA_DMG:
					quick_h += 85.0
				elif target["hp"] <= hvy_d:
					quick_h += 120.0

			StateClass.Action.ATTACK:
				quick_h = 50.0
				if target.get("is_guard_broken", false):
					quick_h += 60.0
				elif target.get("is_defending", false) and target["stamina"] <= StateClass.ATTACK_STAMINA_DMG:
					quick_h += 65.0
				elif target["hp"] <= atk_d:
					quick_h += 100.0

			StateClass.Action.REST:
				if actor["stamina"] < atk_c:
					quick_h = 70.0 # Wajib isi stamina jika habis
				elif actor["stamina"] < hvy_c:
					quick_h = 25.0
				elif actor["stamina"] >= 80:
					quick_h = -30.0 # Dilarang rest jika stamina penuh
				else:
					quick_h = 5.0

			StateClass.Action.DEFEND:
				var actor_hp_ratio: float = float(actor["hp"]) / float(actor["max_hp"])
				if actor_hp_ratio < 0.30 and target["stamina"] >= atk_c:
					quick_h = 40.0 # Emergency block saat sekarat
				elif actor.get("is_guard_broken", false):
					quick_h = -60.0
				elif target["stamina"] < atk_c:
					quick_h = -40.0 # Musuh tak punya stamina, jangan buang giliran untuk guard
				else:
					quick_h = -15.0 # Deprioritaskan turtling secara umum

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

func evaluate(state: StateClass, piece: int, eval_type: int) -> float:
	var my = state.enemy if piece == StateClass.Side.ENEMY else state.player
	var opp = state.player if piece == StateClass.Side.ENEMY else state.enemy

	var my_hp: float = float(my["hp"])
	var my_max_hp: float = float(my["max_hp"])
	var opp_hp: float = float(opp["hp"])
	var opp_max_hp: float = float(opp["max_hp"])

	var my_stm: float = float(my["stamina"])
	var opp_stm: float = float(opp["stamina"])

	# 1. Terminal condition
	if my_hp <= 0.0:
		return -WIN_SCORE
	if opp_hp <= 0.0:
		return WIN_SCORE

	# 2. Progress Damage Dealt (Skala absolut, mengatasi distorsi 500 max HP player)
	var raw_dmg_dealt: float = opp_max_hp - opp_hp
	var damage_score: float = raw_dmg_dealt * 2.8

	# 3. HP Survival Ratio
	var my_hp_ratio: float = my_hp / my_max_hp
	var survival_score: float = my_hp_ratio * 70.0

	# 4. Stamina Pressure & Advantage
	var stm_score: float = (my_stm - 20.0) * 0.35
	var opp_stm_penalty: float = 0.0
	if opp_stm <= 20.0:
		opp_stm_penalty = 35.0 # Player kehabisan stamina, waktu sempurna untuk menyerang!
	elif opp_stm <= 40.0:
		opp_stm_penalty = 18.0

	# 5. Guard Break & Vulnerability
	var gb_score: float = 0.0
	if opp.get("is_guard_broken", false):
		gb_score += 75.0
	if my.get("is_guard_broken", false):
		gb_score -= 60.0

	# 6. Anti-Turtle Guarding Heuristic
	# Guard hanya bernilai positif jika HP musuh kritis & player punya stamina tinggi
	var guard_eval: float = 0.0
	if my.get("is_defending", false):
		if my_hp_ratio < 0.35 and opp_stm >= 40.0:
			guard_eval += 25.0 # Clutch life-saving block
		else:
			guard_eval -= 35.0 # Penalti turtling pasif
			if opp_stm < 20.0:
				guard_eval -= 30.0 # Guard saat player tak bisa menyerang balik adalah blunder

	# Insentif memecahkan guard musuh
	var punish_opp_guard: float = 0.0
	if opp.get("is_defending", false):
		if opp_stm <= 40.0:
			punish_opp_guard += 40.0
		else:
			punish_opp_guard -= 10.0

	var base_eval: float = damage_score + survival_score + stm_score + opp_stm_penalty + gb_score + guard_eval + punish_opp_guard

	# 7. Penerapan Personality / Archetype
	match eval_type:
		EvalType.BERZERKER:
			# Agresivitas brutal, mengabaikan survival, memprioritaskan damage besar
			var berzerk_guard_penalty: float = -60.0 if my.get("is_defending", false) else 0.0
			return damage_score * 1.5 + (survival_score * 0.4) + stm_score + gb_score * 1.3 + berzerk_guard_penalty + (40.0 if my_stm >= 40.0 else 0.0)

		EvalType.TACTICIAN:
			# Mengeksploitasi stamina player & guard break
			var exploit_bonus: float = 50.0 if (opp_stm <= 35.0 or opp.get("is_guard_broken", false)) else 0.0
			return damage_score * 1.1 + survival_score * 0.9 + stm_score * 1.2 + exploit_bonus + gb_score * 1.4 + (guard_eval * 0.6)

		EvalType.JUGGERNAUT:
			# Serangan bertubi-tubi dengan HP tebal
			return damage_score * 1.3 + survival_score * 1.1 + stm_score + gb_score + (guard_eval * 0.5)

		EvalType.DEFENSIVE:
			# Cautious (bertahan secara taktis saat HP rendah)
			return damage_score * 0.8 + survival_score * 1.3 + (guard_eval * 1.4 if my_hp_ratio < 0.45 else -10.0) + stm_score

		EvalType.AGGRESSIVE:
			# Konstan menekan player, minim guard
			var agg_guard_penalty: float = -45.0 if my.get("is_defending", false) else 0.0
			return damage_score * 1.3 + survival_score * 0.7 + stm_score + gb_score * 1.2 + agg_guard_penalty

		_: # BALANCED
			return base_eval
