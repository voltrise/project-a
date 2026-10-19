class_name WildernessBattleState
extends RefCounted

## State representasi khusus untuk Wilderness Battle (Player 500 HP + Item Buffs).
## Mendukung Minimax & Alpha-Beta Adversarial Search Engine.

enum Action { ATTACK = 0, HEAVY_ATTACK = 1, DEFEND = 2, REST = 3 }
enum Side { PLAYER = 0, ENEMY = 1 }

var player: Dictionary = {}
var enemy: Dictionary = {}
var current_turn: int = Side.PLAYER
var turn_count: int = 1
var buffs: Dictionary = {
	"pothp": 0,
	"potstamina": 0,
	"sword": 0,
	"axe": 0,
}

# Mekanik Parry & Retaliation
var parry_active: bool = false
var last_enemy_attack_damage: int = 0
var last_enemy_attack_type: int = -1

# ══════════════════════════════════════════════════════════════════════
#  BASE CONSTANTS
# ══════════════════════════════════════════════════════════════════════
const BASE_ATTACK_COST: int = 20
const BASE_HEAVY_COST: int = 40
const BASE_PLAYER_ATTACK_DMG: int = 20
const BASE_PLAYER_HEAVY_DMG: int = 35

const ATTACK_STAMINA_DMG: int = 20
const HEAVY_STAMINA_DMG: int = 45

const REST_RECOVER_STM: int = 50
const DEFEND_RECOVER_STM: int = 0


func _init(p_hp: int = 500, e_preset: Dictionary = {}, active_buffs: Dictionary = {}, p_max_hp: int = 500) -> void:
	if not e_preset.is_empty():
		setup_battle(p_hp, e_preset, active_buffs, p_max_hp)


func setup_battle(p_hp: int, e_preset: Dictionary, active_buffs: Dictionary, p_max_hp: int = 500) -> void:
	buffs = active_buffs.duplicate(true)
	var max_h = maxi(p_max_hp, p_hp)
	player = {
		"name": "Pawn",
		"hp": clampi(p_hp, 1, max_h),
		"max_hp": max_h,
		"stamina": 100,
		"max_stamina": 100,
		"is_defending": false,
		"is_guard_broken": false,
	}

	var e_max_hp = e_preset.get("max_hp", 100)
	var e_atk = e_preset.get("attack_damage", 18)
	var e_heavy = e_preset.get("heavy_damage", 30)

	enemy = {
		"name": e_preset.get("name", "Enemy"),
		"node_name": e_preset.get("node_name", "Enemy"),
		"tier": e_preset.get("tier", "Common"),
		"hp": e_max_hp,
		"max_hp": e_max_hp,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": e_atk,
		"heavy_damage": e_heavy,
		"is_defending": false,
		"is_guard_broken": false,
	}

	current_turn = Side.PLAYER
	turn_count = 1
	parry_active = false
	last_enemy_attack_damage = 0
	last_enemy_attack_type = -1


## Deep-copy state untuk adversarial search tree
func clone() -> RefCounted:
	var copy = (get_script() as GDScript).new()
	copy.player = player.duplicate(true)
	copy.enemy = enemy.duplicate(true)
	copy.current_turn = current_turn
	copy.turn_count = turn_count
	copy.buffs = buffs.duplicate(true)
	copy.parry_active = parry_active
	copy.last_enemy_attack_damage = last_enemy_attack_damage
	copy.last_enemy_attack_type = last_enemy_attack_type
	return copy


# ══════════════════════════════════════════════════════════════════════
#  ACTION COSTS & DAMAGE CALCULATIONS (WITH BUFFS)
# ══════════════════════════════════════════════════════════════════════

func get_attack_cost(side: int) -> int:
	if side == Side.PLAYER:
		if buffs.get("potstamina", 0) > 0:
			# Stamina Potion: setiap aksi menggunakan 25% lebih sedikit stamina
			return int(round(float(BASE_ATTACK_COST) * 0.75)) # 15
		return BASE_ATTACK_COST
	return BASE_ATTACK_COST


func get_heavy_cost(side: int) -> int:
	if side == Side.PLAYER:
		if parry_active:
			return 0 # Parry reward: Heavy Attack berbiaya 0 stamina
		if buffs.get("potstamina", 0) > 0:
			# Stamina Potion: 25% stamina cost reduction
			return int(round(float(BASE_HEAVY_COST) * 0.75)) # 30
		return BASE_HEAVY_COST
	return BASE_HEAVY_COST


func get_attack_damage(side: int) -> int:
	if side == Side.PLAYER:
		var dmg = BASE_PLAYER_ATTACK_DMG
		if buffs.get("sword", 0) > 0:
			# Sword: damage basic attack bertambah sebanyak 10%
			dmg = int(round(float(dmg) * 1.10)) # 22
		return dmg
	return enemy.get("attack_damage", 18)


func get_heavy_damage(side: int) -> int:
	if side == Side.PLAYER:
		var dmg = BASE_PLAYER_HEAVY_DMG
		if buffs.get("axe", 0) > 0:
			# Axe: damage heavy attack bertambah sebanyak 10%
			dmg = int(round(float(dmg) * 1.10)) # 39
		return dmg
	return enemy.get("heavy_damage", 32)


# ══════════════════════════════════════════════════════════════════════
#  ACTIONS (Branching Factor <= 4)
# ══════════════════════════════════════════════════════════════════════

func get_valid_actions() -> Array[int]:
	var current := player if current_turn == Side.PLAYER else enemy

	if current.get("is_guard_broken", false):
		return [Action.REST]

	var actions: Array[int] = []
	var atk_c = get_attack_cost(current_turn)
	var hvy_c = get_heavy_cost(current_turn)

	if current.get("stamina", 0) >= atk_c:
		actions.append(Action.ATTACK)

	if current.get("stamina", 0) >= hvy_c:
		actions.append(Action.HEAVY_ATTACK)

	actions.append(Action.DEFEND)
	actions.append(Action.REST)

	return actions


# ══════════════════════════════════════════════════════════════════════
#  STATE TRANSITION MODEL
# ══════════════════════════════════════════════════════════════════════

func apply_action(action: int, stochastic: bool = false) -> Dictionary:
	var attacker: Dictionary
	var defender: Dictionary

	if current_turn == Side.PLAYER:
		attacker = player
		defender = enemy
	else:
		attacker = enemy
		defender = player

	# Status defending penyerang kedaluwarsa di awal giliran barunya
	attacker["is_defending"] = false

	var was_parry = parry_active
	var prev_enemy_dmg = last_enemy_attack_damage
	var prev_enemy_type = last_enemy_attack_type

	if current_turn == Side.PLAYER:
		parry_active = false
		last_enemy_attack_damage = 0
		last_enemy_attack_type = -1

	var log := {
		"side": current_turn,
		"action": action,
		"action_name": get_action_name(action),
		"attacker_name": attacker["name"],
		"defender_name": defender["name"],
		"damage": 0,
		"hp_gain": 0,
		"stamina_damage": 0,
		"stamina_gain": 0,
		"blocked": false,
		"guard_break": false,
		"is_critical": false,
		"recovered_from_break": false,
		"parry": false,
		"parry_triggered": false,
		"parry_type": "",
		"parry_heal": 0,
		"retaliation_heal": 0,
	}

	match action:
		Action.ATTACK:
			var cost = get_attack_cost(current_turn)
			attacker["stamina"] = max(0, attacker["stamina"] - cost)
			var base_dmg = get_attack_damage(current_turn)
			var is_crit: bool = false

			if stochastic and randf() < 0.20:
				is_crit = true
				base_dmg = int(float(base_dmg) * 1.5)

			log["is_critical"] = is_crit

			# PARRY REWARD (Light Attack): Pulihkan +100 HP
			if current_turn == Side.PLAYER and was_parry:
				var old_p_hp: int = attacker["hp"]
				attacker["hp"] = mini(attacker["max_hp"], attacker["hp"] + 100)
				log["parry_triggered"] = true
				log["parry_type"] = "light"
				log["parry_heal"] = attacker["hp"] - old_p_hp
				log["hp_gain"] += log["parry_heal"]

			# RETALIATION (Rally): Light Attack membalas damage musuh ronde lalu
			elif current_turn == Side.PLAYER and prev_enemy_dmg > 0:
				var heal_pct = 0.75 if prev_enemy_type == Action.ATTACK else 0.50
				var heal_amt = maxi(1, int(round(float(prev_enemy_dmg) * heal_pct)))
				var old_r_hp: int = attacker["hp"]
				attacker["hp"] = mini(attacker["max_hp"], attacker["hp"] + heal_amt)
				log["retaliation_heal"] = attacker["hp"] - old_r_hp
				log["hp_gain"] += log["retaliation_heal"]

			if defender["is_defending"]:
				log["blocked"] = true
				log["stamina_damage"] = ATTACK_STAMINA_DMG
				defender["stamina"] -= ATTACK_STAMINA_DMG
				if defender["stamina"] <= 0:
					defender["stamina"] = 0
					defender["is_guard_broken"] = true
					defender["is_defending"] = false
					log["guard_break"] = true
			else:
				defender["hp"] = max(0, defender["hp"] - base_dmg)
				log["damage"] = base_dmg

			if current_turn == Side.ENEMY:
				if log["damage"] > 0:
					last_enemy_attack_damage = log["damage"]
					last_enemy_attack_type = Action.ATTACK
				else:
					last_enemy_attack_damage = 0
					last_enemy_attack_type = -1

		Action.HEAVY_ATTACK:
			var cost = 0 if (current_turn == Side.PLAYER and was_parry) else get_heavy_cost(current_turn)
			attacker["stamina"] = max(0, attacker["stamina"] - cost)
			var base_dmg = get_heavy_damage(current_turn)
			var is_crit: bool = false

			if stochastic and randf() < 0.15:
				is_crit = true
				base_dmg = int(float(base_dmg) * 1.4)

			log["is_critical"] = is_crit

			# PARRY REWARD (Heavy Attack): Berhasil menggunakan Heavy Attack 0 Stamina!
			if current_turn == Side.PLAYER and was_parry:
				log["parry_triggered"] = true
				log["parry_type"] = "heavy"

			if defender["is_defending"]:
				log["blocked"] = true
				log["stamina_damage"] = HEAVY_STAMINA_DMG
				defender["stamina"] -= HEAVY_STAMINA_DMG
				if defender["stamina"] <= 0:
					defender["stamina"] = 0
					defender["is_guard_broken"] = true
					defender["is_defending"] = false
					log["guard_break"] = true
				else:
					# PARRY TRIGGER: Musuh Heavy Attack mengenai Player yang sedang Defend!
					if current_turn == Side.ENEMY:
						parry_active = true
						log["parry"] = true
			else:
				defender["hp"] = max(0, defender["hp"] - base_dmg)
				log["damage"] = base_dmg

			if current_turn == Side.ENEMY:
				if log["damage"] > 0:
					last_enemy_attack_damage = log["damage"]
					last_enemy_attack_type = Action.HEAVY_ATTACK
				else:
					last_enemy_attack_damage = 0
					last_enemy_attack_type = -1

		Action.DEFEND:
			attacker["is_defending"] = true
			log["stamina_gain"] = 0
			if current_turn == Side.ENEMY:
				last_enemy_attack_damage = 0
				last_enemy_attack_type = -1

		Action.REST:
			attacker["is_guard_broken"] = false
			if current_turn == Side.ENEMY:
				last_enemy_attack_damage = 0
				last_enemy_attack_type = -1
			var old_stm: int = attacker["stamina"]
			attacker["stamina"] = mini(attacker["max_stamina"], attacker["stamina"] + REST_RECOVER_STM)
			log["stamina_gain"] = attacker["stamina"] - old_stm

			# HP Potion Buff: dalam battle, heal 25hp setiap player melakukan rest
			var hp_recover = 0
			if current_turn == Side.PLAYER and buffs.get("pothp", 0) > 0:
				hp_recover = 25
				var old_hp: int = attacker["hp"]
				attacker["hp"] = mini(attacker["max_hp"], attacker["hp"] + hp_recover)
				log["hp_gain"] = attacker["hp"] - old_hp

			log["recovered_from_break"] = true

	current_turn = Side.ENEMY if current_turn == Side.PLAYER else Side.PLAYER
	turn_count += 1

	return log


# ══════════════════════════════════════════════════════════════════════
#  TERMINAL TEST & WINNER
# ══════════════════════════════════════════════════════════════════════

func is_terminal() -> bool:
	return player["hp"] <= 0 or enemy["hp"] <= 0


func get_winner() -> int:
	if enemy["hp"] <= 0:
		return Side.PLAYER
	if player["hp"] <= 0:
		return Side.ENEMY
	return -1


# ══════════════════════════════════════════════════════════════════════
#  HEURISTIC EVALUATION FOR MINIMAX
# ══════════════════════════════════════════════════════════════════════

func evaluate(eval_type: int = 0) -> float:
	if is_terminal():
		var winner = get_winner()
		if winner == Side.ENEMY:
			return 100000.0 - float(turn_count)
		elif winner == Side.PLAYER:
			return -100000.0 + float(turn_count)
		return 0.0

	var raw_dmg_dealt: float = float(player["max_hp"] - player["hp"])
	var damage_score: float = raw_dmg_dealt * 2.8

	var my_hp_ratio: float = float(enemy["hp"]) / float(enemy["max_hp"])
	var survival_score: float = my_hp_ratio * 70.0

	var stm_score: float = (float(enemy["stamina"]) - 20.0) * 0.35
	var opp_stm_penalty: float = 35.0 if player["stamina"] <= 20 else (18.0 if player["stamina"] <= 40 else 0.0)

	var gb_score: float = 0.0
	if player.get("is_guard_broken", false):
		gb_score += 75.0
	if enemy.get("is_guard_broken", false):
		gb_score -= 60.0

	var guard_eval: float = 0.0
	if enemy.get("is_defending", false):
		if my_hp_ratio < 0.35 and player["stamina"] >= 40:
			guard_eval += 25.0
		else:
			guard_eval -= 35.0
			if player["stamina"] < 20:
				guard_eval -= 30.0

	var base_eval: float = damage_score + survival_score + stm_score + opp_stm_penalty + gb_score + guard_eval

	match eval_type:
		3: # BERZERKER
			var berzerk_guard_penalty: float = -60.0 if enemy.get("is_defending", false) else 0.0
			return damage_score * 1.5 + (survival_score * 0.4) + stm_score + gb_score * 1.3 + berzerk_guard_penalty
		4: # TACTICIAN
			var exploit_bonus: float = 50.0 if (player["stamina"] <= 35 or player.get("is_guard_broken", false)) else 0.0
			return damage_score * 1.1 + survival_score * 0.9 + stm_score * 1.2 + exploit_bonus + gb_score * 1.4
		5: # JUGGERNAUT
			return damage_score * 1.3 + survival_score * 1.1 + stm_score + gb_score
		2: # DEFENSIVE
			return damage_score * 0.8 + survival_score * 1.3 + guard_eval + stm_score
		1: # AGGRESSIVE
			var agg_guard_penalty: float = -45.0 if enemy.get("is_defending", false) else 0.0
			return damage_score * 1.3 + survival_score * 0.7 + stm_score + gb_score * 1.2 + agg_guard_penalty
		_: # BALANCED
			return base_eval


static func get_action_name(action: int) -> String:
	match action:
		Action.ATTACK:       return "Attack"
		Action.HEAVY_ATTACK: return "Heavy Attack"
		Action.DEFEND:       return "Defend"
		Action.REST:         return "Rest"
	return "Unknown"

