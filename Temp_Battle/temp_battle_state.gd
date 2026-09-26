class_name TempBattleState
extends RefCounted

## State representasi untuk Turn-Based Adversarial Battle (1v1 Duel).
## Memenuhi spesifikasi Tugas Besar Tahap 2: Adversarial Search.
##
## State: Player & NPC HP, Stamina (0-100), Status Defending, Status Guard Broken.
## Action: Branching factor <= 4 (Attack, Heavy Attack, Defend, Rest).
## Mekanik:
## - Attack & Heavy Attack mengonsumsi Stamina (menghasilkan damage HP atau Stamina lawan jika Defend).
## - Defend menahan serangan masuk tanpa memulihkan stamina.
## - Rest memulihkan Stamina (+50 STM) dan menyembuhkan Guard Break.

enum Action { ATTACK = 0, HEAVY_ATTACK = 1, DEFEND = 2, REST = 3 }
enum Side { PLAYER = 0, ENEMY = 1 }

# ── Fighter Data Dictionaries ──────────────────────────────────────────
var player: Dictionary = {}
var enemy: Dictionary = {}
var current_turn: int = Side.PLAYER
var turn_count: int = 0

# ── Game Constants ─────────────────────────────────────────────────────
const DEFAULT_MAX_HP: int = 100
const DEFAULT_MAX_STAMINA: int = 100

const ATTACK_COST: int = 30
const ATTACK_DAMAGE: int = 20
const ATTACK_STAMINA_DMG: int = 30

const HEAVY_COST: int = 60
const HEAVY_DAMAGE: int = 45
const HEAVY_STAMINA_DMG: int = 60

const REST_RECOVER: int = 50


# ══════════════════════════════════════════════════════════════════════
#  INITIALIZATION / FACTORY
# ══════════════════════════════════════════════════════════════════════

func _init(p_hp: int = DEFAULT_MAX_HP, e_hp: int = DEFAULT_MAX_HP) -> void:
	reset(p_hp, e_hp)


func reset(p_hp: int = DEFAULT_MAX_HP, e_hp: int = DEFAULT_MAX_HP) -> void:
	player = {
		"name": "Player",
		"hp": p_hp,
		"max_hp": p_hp,
		"stamina": DEFAULT_MAX_STAMINA,
		"max_stamina": DEFAULT_MAX_STAMINA,
		"is_defending": false,
		"is_guard_broken": false,
	}

	enemy = {
		"name": "NPC",
		"hp": e_hp,
		"max_hp": e_hp,
		"stamina": DEFAULT_MAX_STAMINA,
		"max_stamina": DEFAULT_MAX_STAMINA,
		"is_defending": false,
		"is_guard_broken": false,
	}

	current_turn = Side.PLAYER
	turn_count = 1


## Deep-copy state untuk pencarian adversarial (Minimax/Alpha-Beta).
func clone() -> RefCounted:
	var copy = (get_script() as GDScript).new()
	copy.player = player.duplicate(true)
	copy.enemy = enemy.duplicate(true)
	copy.current_turn = current_turn
	copy.turn_count = turn_count
	return copy


# ══════════════════════════════════════════════════════════════════════
#  STATE ACCESSORS
# ══════════════════════════════════════════════════════════════════════

func get_fighter(side: int) -> Dictionary:
	return player if side == Side.PLAYER else enemy


func get_current_fighter() -> Dictionary:
	return player if current_turn == Side.PLAYER else enemy


func get_opponent_fighter() -> Dictionary:
	return enemy if current_turn == Side.PLAYER else player


# ══════════════════════════════════════════════════════════════════════
#  ACTIONS (Branching Factor <= 4)
# ══════════════════════════════════════════════════════════════════════

## Mengembalikan daftar action legal pada state saat ini.
## Branching factor dijamin <= 4:
## 1. Jika Guard Broken: hanya REST (branching = 1)
## 2. ATTACK (jika stamina >= 30)
## 3. HEAVY_ATTACK (jika stamina >= 60)
## 4. DEFEND (selalu valid, tidak memulihkan stamina tapi menahan pukulan)
## 5. REST (selalu valid, memulihkan stamina +50)
func get_valid_actions() -> Array[int]:
	var current := get_current_fighter()

	if current.get("is_guard_broken", false):
		return [Action.REST]

	var actions: Array[int] = []

	if current.get("stamina", 0) >= ATTACK_COST:
		actions.append(Action.ATTACK)

	if current.get("stamina", 0) >= HEAVY_COST:
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

	# Ketika giliran baru dimulai, status defending milik penyerang kedaluwarsa
	attacker["is_defending"] = false

	var log := {
		"side": current_turn,
		"action": action,
		"action_name": get_action_name(action),
		"attacker_name": attacker["name"],
		"defender_name": defender["name"],
		"damage": 0,
		"stamina_damage": 0,
		"stamina_gain": 0,
		"blocked": false,
		"guard_break": false,
		"is_critical": false,
		"recovered_from_break": false,
	}

	match action:
		Action.ATTACK:
			attacker["stamina"] = max(0, attacker["stamina"] - ATTACK_COST)
			var is_crit: bool = false
			var atk_dmg: int = ATTACK_DAMAGE

			if stochastic and randf() < 0.20:
				is_crit = true
				atk_dmg = int(float(atk_dmg) * 1.5)

			log["is_critical"] = is_crit

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
				defender["hp"] = max(0, defender["hp"] - atk_dmg)
				log["damage"] = atk_dmg

		Action.HEAVY_ATTACK:
			attacker["stamina"] = max(0, attacker["stamina"] - HEAVY_COST)
			var is_crit: bool = false
			var atk_dmg: int = HEAVY_DAMAGE

			if stochastic and randf() < 0.15:
				is_crit = true
				atk_dmg = int(float(atk_dmg) * 1.4)

			log["is_critical"] = is_crit

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
				defender["hp"] = max(0, defender["hp"] - atk_dmg)
				log["damage"] = atk_dmg

		Action.DEFEND:
			attacker["is_defending"] = true
			# Defend TIDAK memulihkan stamina (stamina_gain = 0)
			log["stamina_gain"] = 0

		Action.REST:
			attacker["is_guard_broken"] = false
			var old_stm: int = attacker["stamina"]
			attacker["stamina"] = min(attacker["max_stamina"], attacker["stamina"] + REST_RECOVER)
			log["stamina_gain"] = attacker["stamina"] - old_stm
			log["recovered_from_break"] = true

	# Ganti giliran
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
#  HELPERS / STRING CONVERTERS
# ══════════════════════════════════════════════════════════════════════

static func get_action_name(action: int) -> String:
	match action:
		Action.ATTACK:       return "Attack"
		Action.HEAVY_ATTACK: return "Heavy Attack"
		Action.DEFEND:       return "Defend"
		Action.REST:         return "Rest"
	return "Unknown"


static func get_side_name(side: int) -> String:
	match side:
		Side.PLAYER: return "Player"
		Side.ENEMY:  return "NPC"
	return "Unknown"
