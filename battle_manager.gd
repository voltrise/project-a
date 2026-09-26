class_name BattleManagerClass
extends Node

## Autoload singleton yang mengatur battle lifecycle.
## Tanggung jawab:
##   1. Menyimpan data player & enemy sebelum scene change
##   2. Scene transition ke battlestage.tscn dan kembali
##   3. Menyimpan hasil battle
##
## Dipanggil dari lobby/map, data diambil oleh BattleStage saat _ready().

# ── Signals ───────────────────────────────────────────────────────────

signal battle_started(player_data: Dictionary, enemy_data: Dictionary)
signal battle_ended(result: Dictionary)

# ── Battle setup data (persist across scene change) ───────────────────

var _player_fighter: Dictionary = {}
var _enemy_fighter: Dictionary = {}
var _battle_active: bool = false
var _return_scene: String = ""
var _battle_result: Dictionary = {}

## AI search depth — bisa di-tweak per difficulty
var ai_search_depth: int = 4

# ── Contoh enemy presets ──────────────────────────────────────────────
## Karena enemy belum ada di game, ini sebagai placeholder.
## Nanti bisa diganti dengan enemies.json atau enemy spawner.

const ENEMY_PRESETS: Dictionary = {
	"slime": {
		"name": "Slime",
		"tier": "Common",
		"image": "",
	},
	"goblin": {
		"name": "Goblin",
		"tier": "Uncommon",
		"image": "",
	},
	"skeleton_knight": {
		"name": "Skeleton Knight",
		"tier": "Rare",
		"image": "",
	},
	"dark_mage": {
		"name": "Dark Mage",
		"tier": "Epic",
		"image": "",
	},
	"dragon": {
		"name": "Dragon",
		"tier": "Legendary",
		"image": "",
	},
	"demon_lord": {
		"name": "Demon Lord",
		"tier": "Mythic",
		"image": "",
	},
}


# ══════════════════════════════════════════════════════════════════════
#  BATTLE LIFECYCLE
# ══════════════════════════════════════════════════════════════════════

## Mulai battle. Dipanggil dari lobby/overworld.
## player_char_data: data karakter dari CharacterManager (punya "name", "tier", dll)
## enemy_data: dictionary dengan minimal "name" + "tier" ATAU custom stats
## return_scene_path: scene path untuk kembali setelah battle selesai
func start_battle(caller: Node, player_char_data: Dictionary, enemy_data: Dictionary,
		return_scene_path: String = "") -> void:

	# Buat fighter dari tier karakter yang sudah di-roll
	var player_tier: String = player_char_data.get("tier", "Common")
	_player_fighter = BattleState.create_fighter(
		player_char_data.get("name", "Player"), player_tier
	)
	# Simpan visual data juga (buat UI battle nanti)
	_player_fighter["image"] = player_char_data.get("image", "")
	_player_fighter["id"] = player_char_data.get("id", "")

	# Buat enemy fighter
	if enemy_data.has("hp") and enemy_data.has("atk"):
		# Custom stats langsung
		_enemy_fighter = BattleState.create_fighter_custom(
			enemy_data.get("name", "Enemy"),
			enemy_data.get("hp", 100),
			enemy_data.get("atk", 15),
			enemy_data.get("def", 7),
			enemy_data.get("spd", 10),
			enemy_data.get("items", 2),
			enemy_data.get("special_charges", 3),
		)
	else:
		# Dari tier
		_enemy_fighter = BattleState.create_fighter(
			enemy_data.get("name", "Enemy"),
			enemy_data.get("tier", "Common")
		)
	_enemy_fighter["image"] = enemy_data.get("image", "")
	_enemy_fighter["id"] = enemy_data.get("id", "enemy")

	_battle_active = true
	_return_scene = return_scene_path
	_battle_result = {}

	battle_started.emit(_player_fighter, _enemy_fighter)
	print("[BattleManager] Battle started: %s (%s) vs %s (%s)" % [
		_player_fighter["name"], _player_fighter["tier"],
		_enemy_fighter["name"], _enemy_fighter["tier"],
	])

	caller.get_tree().change_scene_to_file("res://battlestage.tscn")


## Akhiri battle. Dipanggil oleh BattleStage saat ada pemenang.
## result: { "winner": "player"/"enemy", "turns": int, "nodes_total": int }
func end_battle(result: Dictionary) -> void:
	_battle_active = false
	_battle_result = result.duplicate(true)

	battle_ended.emit(_battle_result)
	print("[BattleManager] Battle ended: %s wins in %d turns" % [
		result.get("winner", "unknown"),
		result.get("turns", 0),
	])

	if _return_scene != "":
		get_tree().change_scene_to_file(_return_scene)


# ══════════════════════════════════════════════════════════════════════
#  DATA ACCESS — dipanggil BattleStage saat _ready()
# ══════════════════════════════════════════════════════════════════════

## Return deep copy dari battle setup data.
## BattleStage pakai ini untuk create BattleState.
func get_battle_data() -> Dictionary:
	return {
		"player": _player_fighter.duplicate(true),
		"enemy": _enemy_fighter.duplicate(true),
	}


func is_battle_active() -> bool:
	return _battle_active


func get_last_result() -> Dictionary:
	return _battle_result.duplicate(true)


func get_ai_depth() -> int:
	return ai_search_depth


func set_ai_depth(depth: int) -> void:
	ai_search_depth = clampi(depth, 1, 10)
	print("[BattleManager] AI depth set to %d" % ai_search_depth)


# ══════════════════════════════════════════════════════════════════════
#  HELPER — quick battle start dari preset
# ══════════════════════════════════════════════════════════════════════

## Start battle pakai enemy preset. Shortcut buat testing.
## Contoh: BattleManager.start_battle_preset(char_data, "goblin")
#func start_battle_preset(player_char_data: Dictionary, enemy_preset_id: String,
		#return_scene_path: String = "") -> void:
	#var preset: Dictionary = ENEMY_PRESETS.get(enemy_preset_id, ENEMY_PRESETS["slime"])
	#start_battle(player_char_data, preset, return_scene_path)


## Generate enemy yang level-nya match sama player tier.
## Berguna untuk random encounters.
func generate_matching_enemy(player_tier: String) -> Dictionary:
	var tier_order: Array = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
	var tier_idx: int = tier_order.find(player_tier)
	if tier_idx == -1:
		tier_idx = 0

	# Enemy bisa 1 tier di bawah sampai sama
	var enemy_tier_idx: int = max(0, tier_idx - 1)
	# Deterministic: pakai tier yang sama (biar fair buat minimax)
	var enemy_tier: String = tier_order[enemy_tier_idx]

	var enemy_names: Array = ["Slime", "Goblin", "Skeleton", "Dark Mage", "Dragon", "Demon Lord", "Shadow"]
	var enemy_name: String = enemy_names[min(enemy_tier_idx, enemy_names.size() - 1)]

	return {
		"name": enemy_name,
		"tier": enemy_tier,
		"image": "",
	}
