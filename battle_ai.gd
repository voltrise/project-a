class_name BattleAI
extends RefCounted

## Minimax + Alpha-Beta Pruning AI untuk 1v1 turn-based battle.
##
## Mengikuti konvensi AI Modul 3 — Adversarial Search:
## - piece: sudut pandang skor, tidak berubah sepanjang rekursi
## - maximizing: berganti setiap lapis (True saat giliran piece)
## - NODES: counter yang dinaikkan setiap kali fungsi dipanggil
## - WIN + depth: kemenangan cepat lebih bernilai
## - evaluate(): tidak boleh return magnitude >= WIN
##
## Ref: Russell & Norvig, AIMA 4th ed, Section 5.1–5.4

# ── Constants ─────────────────────────────────────────────────────────
## WIN magnitude harus jauh di atas evaluate range (~161).
## evaluate() TIDAK BOLEH return nilai mendekati WIN.
const WIN: float = 1000000.0

# ── Node counter ──────────────────────────────────────────────────────
## Reset ke 0 sebelum setiap pencarian. Dinaikkan setiap kali
## minimax/alphabeta dipanggil, termasuk pada base case.
var nodes: int = 0


# ══════════════════════════════════════════════════════════════════════
#  MINIMAX — standard, tanpa pruning
# ══════════════════════════════════════════════════════════════════════

## Return [score, best_action].
## best_action = -1 pada terminal/leaf node (tidak ada action yang dipilih).
##
## Invariant (Modul 3, C.3):
##   piece     — sudut pandang skor, TIDAK BERUBAH sepanjang rekursi.
##   maximizing — True tepat ketika giliran jatuh pada piece.
func minimax(state: BattleState, depth: int, maximizing: bool, piece: int) -> Array:
	nodes += 1

	# ── Base case: terminal state ──
	if state.is_terminal():
		var winner := state.get_winner()
		if winner == piece:
			return [WIN + depth, -1]     # menang, prefer cepat
		elif winner != -1:
			return [-(WIN + depth), -1]  # kalah
		return [0.0, -1]                 # seri (seharusnya tidak terjadi)

	# ── Base case: depth cutoff ──
	if depth == 0:
		return [evaluate(state, piece), -1]

	var valid_actions := state.get_valid_actions()

	if maximizing:
		var best_score: float = -INF
		var best_action: int = valid_actions[0]
		for action in valid_actions:
			var child := state.clone()
			child.apply_action(action)
			var result := minimax(child, depth - 1, false, piece)
			if result[0] > best_score:
				best_score = result[0]
				best_action = action
		return [best_score, best_action]
	else:
		var best_score: float = INF
		var best_action: int = valid_actions[0]
		for action in valid_actions:
			var child := state.clone()
			child.apply_action(action)
			var result := minimax(child, depth - 1, true, piece)
			if result[0] < best_score:
				best_score = result[0]
				best_action = action
		return [best_score, best_action]


# ══════════════════════════════════════════════════════════════════════
#  ALPHA-BETA — minimax dengan pruning
# ══════════════════════════════════════════════════════════════════════

## Same contract as minimax, plus alpha-beta cutoff.
##
## Alpha: nilai terbaik yang sudah dijamin MAX (tidak pernah turun).
## Beta:  nilai terbaik yang sudah dijamin MIN (tidak pernah naik).
## Prune saat alpha >= beta.
##
## Alpha-beta BUKAN aproksimasi — mengembalikan nilai IDENTIK dengan minimax.
## Cabang yang di-prune terbukti tidak mengubah keputusan di root.
## Ref: Modul 3, Section A.6 & C.5
func alphabeta(state: BattleState, depth: int, alpha: float, beta: float,
		maximizing: bool, piece: int) -> Array:
	nodes += 1

	# ── Base case: terminal state ──
	if state.is_terminal():
		var winner := state.get_winner()
		if winner == piece:
			return [WIN + depth, -1]
		elif winner != -1:
			return [-(WIN + depth), -1]
		return [0.0, -1]

	# ── Base case: depth cutoff ──
	if depth == 0:
		return [evaluate(state, piece), -1]

	var valid_actions := state.get_valid_actions()

	if maximizing:
		var v: float = -INF
		var best_action: int = valid_actions[0]
		for action in valid_actions:
			var child := state.clone()
			child.apply_action(action)
			var result := alphabeta(child, depth - 1, alpha, beta, false, piece)
			if result[0] > v:
				v = result[0]
				best_action = action
			alpha = maxf(alpha, v)
			if alpha >= beta:
				break  # beta cutoff — MIN sudah punya opsi lebih baik di atas
		return [v, best_action]
	else:
		var v: float = INF
		var best_action: int = valid_actions[0]
		for action in valid_actions:
			var child := state.clone()
			child.apply_action(action)
			var result := alphabeta(child, depth - 1, alpha, beta, true, piece)
			if result[0] < v:
				v = result[0]
				best_action = action
			beta = minf(beta, v)
			if alpha >= beta:
				break  # alpha cutoff — MAX sudah punya opsi lebih baik di atas
		return [v, best_action]


# ══════════════════════════════════════════════════════════════════════
#  EVALUATION FUNCTION
# ══════════════════════════════════════════════════════════════════════

## Heuristic score dari sudut pandang piece. Positif = bagus untuk piece.
##
## Bentuk weighted linear (Modul 3, A.8):
##   EVAL(s) = w1*f1(s) + w2*f2(s) + ... + wn*fn(s)
##
## Features:
##   f1: HP ratio advantage          (range: -100 to +100)
##   f2: Item resource advantage     (range: -24 to +24)
##   f3: Special charge advantage    (range: -24 to +24)
##   f4: Defending status            (range: -15 to +15)
##
## Total possible range: ~-163 to +163, jauh di bawah WIN (1,000,000).
## Memenuhi syarat: "evaluate() must never reach WIN magnitude."
func evaluate(state: BattleState, piece: int) -> float:
	var opp_piece: int = BattleState.Side.PLAYER if piece == BattleState.Side.ENEMY else BattleState.Side.ENEMY
	var my: Dictionary = state.get_fighter(piece)
	var opp: Dictionary = state.get_fighter(opp_piece)

	var score: float = 0.0

	# f1: HP advantage — faktor paling penting
	score += (float(my["hp"]) / float(my["max_hp"])) * 100.0
	score -= (float(opp["hp"]) / float(opp["max_hp"])) * 100.0

	# f2: Item advantage — punya heal = punya safety net
	score += float(my.get("items", 0)) * 12.0
	score -= float(opp.get("items", 0)) * 12.0

	# f3: Special charge advantage — burst damage potential
	score += float(my.get("special_charges", 0)) * 8.0
	score -= float(opp.get("special_charges", 0)) * 8.0

	# f4: Defense status — sedang defend = temporarily safer
	if my.get("is_defending", false):
		score += 15.0
	if opp.get("is_defending", false):
		score -= 15.0

	return score


# ══════════════════════════════════════════════════════════════════════
#  CONVENIENCE API
# ══════════════════════════════════════════════════════════════════════

## Pilih action terbaik untuk enemy menggunakan alpha-beta.
## Panggil ini saat giliran enemy.
## Return: { "action": int, "score": float, "nodes": int }
func decide_enemy_action(state: BattleState, depth: int) -> Dictionary:
	nodes = 0
	var result := alphabeta(state, depth, -INF, INF, true, BattleState.Side.ENEMY)
	return {
		"action": result[1],
		"score": result[0],
		"nodes_searched": nodes,
	}


## Verifikasi: minimax dan alphabeta harus return skor identik.
## Ref: Modul 3, D.3 — "Skor kedua versi harus sama persis di setiap depth."
func verify_consistency(state: BattleState, depth: int, piece: int) -> bool:
	nodes = 0
	var mm := minimax(state, depth, true, piece)
	var mm_nodes := nodes

	nodes = 0
	var ab := alphabeta(state, depth, -INF, INF, true, piece)
	var ab_nodes := nodes

	var match_score: bool = absf(mm[0] - ab[0]) < 0.001
	print("[BattleAI] Depth %d: minimax score=%.2f (%d nodes), alphabeta score=%.2f (%d nodes), match=%s" % [
		depth, mm[0], mm_nodes, ab[0], ab_nodes, str(match_score)
	])
	return match_score
