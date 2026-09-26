class_name BattleState
extends RefCounted

## Pure-data representation of a 1v1 turn-based battle.
## Designed for minimax traversal: lightweight, no Node dependency, cheap to clone.
##
## Setiap action deterministic, tidak ada RNG.
## Ref: AI Modul 3 — Adversarial Search

# ── Enums ─────────────────────────────────────────────────────────────

enum Action { ATTACK, SPECIAL_ATTACK, USE_ITEM, DEFEND }
enum Side { PLAYER, ENEMY }

# ── Tier → base battle stats ─────────────────────────────────────────
## Stats scale dengan rarity tier dari gacha system.

const TIER_STATS: Dictionary = {
	"Common":    {"hp": 80,  "atk": 12, "def": 5,  "spd": 8},
	"Uncommon":  {"hp": 100, "atk": 15, "def": 7,  "spd": 10},
	"Rare":      {"hp": 120, "atk": 18, "def": 9,  "spd": 12},
	"Epic":      {"hp": 150, "atk": 22, "def": 12, "spd": 15},
	"Legendary": {"hp": 180, "atk": 26, "def": 15, "spd": 18},
	"Mythic":    {"hp": 220, "atk": 32, "def": 18, "spd": 22},
	"Secret":    {"hp": 250, "atk": 36, "def": 20, "spd": 25},
}

# ── State fields ─────────────────────────────────────────────────────
## Fighter data disimpan sebagai Dictionary supaya clone murah (duplicate).
## Struktur fighter dict:
##   name, tier, hp, max_hp, atk, def, base_def, spd,
##   items, max_items, special_charges, max_special, is_defending

var player: Dictionary = {}
var enemy: Dictionary = {}
var current_turn: int = Side.PLAYER


# ══════════════════════════════════════════════════════════════════════
#  FACTORY — buat fighter dari tier atau custom stats
# ══════════════════════════════════════════════════════════════════════

static func create_fighter(char_name: String, tier: String,
		items: int = 2, specials: int = 3) -> Dictionary:
	var base: Dictionary = TIER_STATS.get(tier, TIER_STATS["Common"])
	return {
		"name": char_name, "tier": tier,
		"hp": base["hp"], "max_hp": base["hp"],
		"atk": base["atk"], "def": base["def"], "spd": base["spd"],
		"base_def": base["def"],
		"items": items, "max_items": items,
		"special_charges": specials, "max_special": specials,
		"is_defending": false,
	}


static func create_fighter_custom(char_name: String, hp: int, atk: int,
		def_val: int, spd: int, items: int = 2, specials: int = 3) -> Dictionary:
	return {
		"name": char_name, "tier": "Custom",
		"hp": hp, "max_hp": hp,
		"atk": atk, "def": def_val, "spd": spd,
		"base_def": def_val,
		"items": items, "max_items": items,
		"special_charges": specials, "max_special": specials,
		"is_defending": false,
	}


# ══════════════════════════════════════════════════════════════════════
#  STATE OPERATIONS — clone, query, apply
# ══════════════════════════════════════════════════════════════════════

## Deep-copy state. Minimax memanggil ini ribuan kali per pencarian.
func clone() -> BattleState:
	var s := BattleState.new()
	s.player = player.duplicate(true)
	s.enemy = enemy.duplicate(true)
	s.current_turn = current_turn
	return s


func get_fighter(side: int) -> Dictionary:
	return player if side == Side.PLAYER else enemy


func get_current_fighter() -> Dictionary:
	return player if current_turn == Side.PLAYER else enemy


func get_opponent_of_current() -> Dictionary:
	return enemy if current_turn == Side.PLAYER else player


## Mengembalikan action yang valid untuk fighter yang sedang giliran.
## Action terbatas jika item/special habis.
func get_valid_actions() -> Array:
	var fighter := get_current_fighter()
	var actions: Array = [Action.ATTACK]
	if fighter.get("special_charges", 0) > 0:
		actions.append(Action.SPECIAL_ATTACK)
	if fighter.get("items", 0) > 0:
		actions.append(Action.USE_ITEM)
	actions.append(Action.DEFEND)
	return actions


## Terapkan action untuk fighter yang sedang giliran, lalu switch turn.
## Semua damage deterministic — tidak ada RNG.
## Return: log dictionary yang mendeskripsikan apa yang terjadi.
func apply_action(action: int) -> Dictionary:
	var attacker: Dictionary
	var defender: Dictionary
	if current_turn == Side.PLAYER:
		attacker = player
		defender = enemy
	else:
		attacker = enemy
		defender = player

	var log := {
		"side": current_turn,
		"action": action,
		"attacker_name": attacker["name"],
		"defender_name": defender["name"],
		"damage": 0,
		"heal": 0,
	}

	# Defend dari turn sebelumnya expire saat turn-mu mulai
	attacker["is_defending"] = false

	match action:
		Action.ATTACK:
			var eff_def: int = defender["def"] * (2 if defender["is_defending"] else 1)
			var damage: int = max(1, attacker["atk"] - eff_def)
			defender["hp"] = max(0, defender["hp"] - damage)
			if defender["is_defending"]:
				defender["is_defending"] = false  # consumed by hit
			log["damage"] = damage

		Action.SPECIAL_ATTACK:
			attacker["special_charges"] -= 1
			var eff_def: int = defender["def"] * (2 if defender["is_defending"] else 1)
			var damage: int = max(1, int(attacker["atk"] * 1.5) - eff_def)
			defender["hp"] = max(0, defender["hp"] - damage)
			if defender["is_defending"]:
				defender["is_defending"] = false  # consumed by hit
			log["damage"] = damage

		Action.USE_ITEM:
			attacker["items"] -= 1
			var heal_amount: int = int(attacker["max_hp"] * 0.3)
			var old_hp: int = attacker["hp"]
			attacker["hp"] = min(attacker["max_hp"], attacker["hp"] + heal_amount)
			log["heal"] = attacker["hp"] - old_hp

		Action.DEFEND:
			attacker["is_defending"] = true

	# Ganti giliran
	current_turn = Side.ENEMY if current_turn == Side.PLAYER else Side.PLAYER
	return log


# ══════════════════════════════════════════════════════════════════════
#  TERMINAL & UTILITY
# ══════════════════════════════════════════════════════════════════════

## Terminal state: salah satu fighter HP <= 0
func is_terminal() -> bool:
	return player["hp"] <= 0 or enemy["hp"] <= 0


## Return Side.PLAYER, Side.ENEMY, atau -1 jika belum ada pemenang.
func get_winner() -> int:
	if enemy["hp"] <= 0:
		return Side.PLAYER
	if player["hp"] <= 0:
		return Side.ENEMY
	return -1


## Set giliran pertama berdasarkan SPD. Speed lebih tinggi = first move.
func determine_first_turn() -> void:
	if player.get("spd", 0) >= enemy.get("spd", 0):
		current_turn = Side.PLAYER
	else:
		current_turn = Side.ENEMY


# ══════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════

static func action_name(action: int) -> String:
	match action:
		Action.ATTACK:         return "Attack"
		Action.SPECIAL_ATTACK: return "Special Attack"
		Action.USE_ITEM:       return "Use Item"
		Action.DEFEND:         return "Defend"
	return "Unknown"


static func side_name(side: int) -> String:
	match side:
		Side.PLAYER: return "Player"
		Side.ENEMY:  return "Enemy"
	return "Unknown"
