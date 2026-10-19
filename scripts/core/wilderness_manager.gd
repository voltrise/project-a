class_name WildernessManagerClass
extends Node

## Autoload Singleton yang mengatur Session Eksplorasi Wilderness & Integrasi Battle.
## Menyimpan state HP player (500), efek item aktif (durasi 2 battle),
## posisi chunk eksplorasi, serta riwayat pertarungan & rekap item.

signal exploration_started()
signal exploration_ended(recap_data: Dictionary)
signal battle_prepared(enemy_data: Dictionary)

# ══════════════════════════════════════════════════════════════════════
#  ENEMY PRESETS UNTUK WILDERNESS BATTLE
# ══════════════════════════════════════════════════════════════════════
## Menyesuaikan value dari ENEMY_PRESETS di battle_manager dan sprite set
## yang sudah ada di wildernesstemplate.tscn.
## Range HP: Easiest (Skeleton: 75 HP) s/d Boss (Troll: 250 HP).
const ENEMY_PRESETS: Dictionary = {
	"skeleton": {
		"id": "skeleton",
		"name": "Skeleton",
		"node_name": "Skeleton",
		"tier": "Easy",
		"max_hp": 75,
		"hp": 75,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 15,
		"heavy_damage": 25,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Skull/Skull_Idle.png",
	},
	"gnome": {
		"id": "gnome",
		"name": "Gnome",
		"node_name": "Gnome",
		"tier": "Easy",
		"max_hp": 90,
		"hp": 90,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 18,
		"heavy_damage": 28,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Gnome/Gnome_Idle.png",
	},
	"thief": {
		"id": "thief",
		"name": "Thief",
		"node_name": "Thief",
		"tier": "Easy",
		"max_hp": 110,
		"hp": 110,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 20,
		"heavy_damage": 32,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Thief/Thief_Idle.png",
	},
	"torch_goblin": {
		"id": "torch_goblin",
		"name": "Torch Goblin",
		"node_name": "TorchGoblin",
		"tier": "Medium",
		"max_hp": 135,
		"hp": 135,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 22,
		"heavy_damage": 36,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Goblin Raiders/Torch Goblin/Torch Goblin_Idle.png",
	},
	"spear_goblin": {
		"id": "spear_goblin",
		"name": "Spear Goblin",
		"node_name": "SpearGoblin",
		"tier": "Medium",
		"max_hp": 160,
		"hp": 160,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 25,
		"heavy_damage": 40,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Goblin Raiders/Spear Goblin/Spear Goblin_Idle.png",
	},
	"panda": {
		"id": "panda",
		"name": "Panda",
		"node_name": "Panda",
		"tier": "Hard",
		"max_hp": 190,
		"hp": 190,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 28,
		"heavy_damage": 45,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Panda/Panda_Idle.png",
	},
	"minotaur": {
		"id": "minotaur",
		"name": "Minotaur",
		"node_name": "Minotaur",
		"tier": "Hard",
		"max_hp": 220,
		"hp": 220,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 32,
		"heavy_damage": 50,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Minotaur/Minotaur_Attack.png",
	},
	"troll": {
		"id": "troll",
		"name": "Troll",
		"node_name": "Troll",
		"tier": "Boss",
		"max_hp": 250,
		"hp": 250,
		"stamina": 100,
		"max_stamina": 100,
		"attack_damage": 36,
		"heavy_damage": 55,
		"image": "res://assets/Tiny Swords (Free Pack)/Enemies/Troll/Troll_Idle.png",
	},
}

# ══════════════════════════════════════════════════════════════════════
#  EXPLORATION STATE
# ══════════════════════════════════════════════════════════════════════
var is_exploring: bool = false
var player_hp: int = 500
var player_max_hp: int = 500
var player_stamina: int = 100
var player_max_stamina: int = 100

## Buff item aktif dan sisa durasi pertarungan (maks 2 battle)
var active_buffs: Dictionary = {
	"pothp": 0,       # +25 HP tiap Rest di battle
	"potstamina": 0,  # 25% stamina cost reduction di battle
	"sword": 0,       # +10% basic attack damage di battle
	"axe": 0,         # +10% heavy attack damage di battle
}

# Persistensi peta & navigasi antar chunk
var current_chunk: Vector2i = Vector2i(0, 0)
var saved_map_state = null
var saved_csp_result = null
var saved_ls_result = null
var defeated_chunks: Array[Vector2i] = []
var collected_chunks: Array[Vector2i] = []

# Rekap / Statistik Eksplorasi
var enemies_defeated_count: int = 0
var items_collected_count: int = 0
var initial_threat_score: float = 0.0

# Current battle encounter
var current_enemy_key: String = ""
var current_enemy_preset: Dictionary = {}


func _ready() -> void:
	pass


# ══════════════════════════════════════════════════════════════════════
#  LIFECYCLE MANAGEMENT
# ══════════════════════════════════════════════════════════════════════

## Memulai sesi eksplorasi baru dengan Full HP 500
func start_exploration(map_state, csp_res = null, ls_res = null) -> void:
	is_exploring = true
	player_hp = 500
	player_max_hp = 500
	player_stamina = 100
	player_max_stamina = 100

	active_buffs = {
		"pothp": 0,
		"potstamina": 0,
		"sword": 0,
		"axe": 0,
	}

	saved_map_state = map_state
	saved_csp_result = csp_res
	saved_ls_result = ls_res
	current_chunk = map_state.start_chunk if map_state else Vector2i.ZERO
	defeated_chunks.clear()
	collected_chunks.clear()

	enemies_defeated_count = 0
	items_collected_count = 0
	initial_threat_score = map_state.difficulty_score if map_state else 0.0

	exploration_started.emit()
	print("[WildernessManager] Exploration started. HP: %d/%d" % [player_hp, player_max_hp])


func has_active_session() -> bool:
	return is_exploring and saved_map_state != null


func clear_session() -> void:
	is_exploring = false
	saved_map_state = null
	saved_csp_result = null
	saved_ls_result = null
	defeated_chunks.clear()
	collected_chunks.clear()
	current_enemy_key = ""
	current_enemy_preset.clear()


# ══════════════════════════════════════════════════════════════════════
#  ITEM PICKUP & BUFF LOGIC
# ══════════════════════════════════════════════════════════════════════

## Mengaplikasikan efek saat player melewati chunk berisi item.
## Mengembalikan dictionary informasi efek untuk visual floating text / HUD feedback.
func apply_item_pickup(raw_item_name: String) -> Dictionary:
	var norm = raw_item_name.to_lower().replace("_", "").replace(" ", "")
	var res := {
		"name": raw_item_name,
		"type": "item",
		"text": "",
		"color": Color.WHITE
	}

	if norm.contains("meat"):
		# Instant heal 150 HP ketika diambil (maks 500)
		var old_hp = player_hp
		player_hp = mini(player_max_hp, player_hp + 150)
		var healed = player_hp - old_hp
		res["type"] = "heal"
		res["text"] = "+%d HP (Meat)" % healed
		res["color"] = Color(0.3, 1.0, 0.4)
	elif norm.contains("pothp") or norm.contains("potionhp"):
		# Dalam battle: heal 5hp setiap player melakukan rest (selama 2 battle)
		active_buffs["pothp"] = 2
		res["type"] = "buff"
		res["text"] = "HP Potion Aktif! (+25 HP Rest, 2 Battle)"
		res["color"] = Color(0.95, 0.4, 0.5)
	elif norm.contains("potstamina") or norm.contains("potionstamina"):
		# Dalam battle: setiap aksi menggunakan 10% lebih sedikit stamina (selama 2 battle)
		active_buffs["potstamina"] = 2
		res["type"] = "buff"
		res["text"] = "Stamina Potion Aktif! (-25% Biaya Stamina, 2 Battle)"
		res["color"] = Color(0.3, 0.85, 1.0)
	elif norm.contains("sword"):
		# Dalam battle: damage basic attack bertambah sebanyak 10% (selama 2 battle)
		active_buffs["sword"] = 2
		res["type"] = "buff"
		res["text"] = "Sword Buff Aktif! (+10% Basic ATK, 2 Battle)"
		res["color"] = Color(1.0, 0.85, 0.25)
	elif norm.contains("axe"):
		# Dalam battle: damage heavy attack bertambah sebanyak 10% (selama 2 battle)
		active_buffs["axe"] = 2
		res["type"] = "buff"
		res["text"] = "Axe Buff Aktif! (+10% Heavy ATK, 2 Battle)"
		res["color"] = Color(1.0, 0.5, 0.2)
	else:
		# Fallback item generic
		res["text"] = "Item Diambil: %s" % raw_item_name

	items_collected_count += 1
	return res


## Mengurangi durasi buff battle sebanyak 1 ronde setelah battle selesai menang.
func consume_battle_buffs() -> void:
	for k in active_buffs.keys():
		if active_buffs[k] > 0:
			active_buffs[k] -= 1
	print("[WildernessManager] Buffs decremented. Current buffs: ", active_buffs)


# ══════════════════════════════════════════════════════════════════════
#  BATTLE PREPARATION & TRANSITION
# ══════════════════════════════════════════════════════════════════════

func get_enemy_preset(key: String) -> Dictionary:
	var clean_key = key.to_lower().replace("_", "").replace(" ", "")
	for preset_id in ENEMY_PRESETS:
		var norm_id = preset_id.to_lower().replace("_", "").replace(" ", "")
		var norm_name = ENEMY_PRESETS[preset_id].get("node_name", "").to_lower().replace("_", "").replace(" ", "")
		if clean_key == norm_id or clean_key == norm_name:
			return ENEMY_PRESETS[preset_id].duplicate(true)

	# Partial contains matching
	for preset_id in ENEMY_PRESETS:
		var norm_id = preset_id.to_lower().replace("_", "").replace(" ", "")
		if clean_key.contains(norm_id) or norm_id.contains(clean_key):
			return ENEMY_PRESETS[preset_id].duplicate(true)

	return ENEMY_PRESETS["skeleton"].duplicate(true)


## Mempersiapkan battle dan transisi ke scene WildernessBattleStage.tscn
func start_wilderness_battle(enemy_node_name: String, chunk_pos: Vector2i) -> void:
	current_chunk = chunk_pos
	current_enemy_key = enemy_node_name
	current_enemy_preset = get_enemy_preset(enemy_node_name)

	# Stamina player selalu kembali ke full (100) setiap mulai battle
	player_stamina = 100

	battle_prepared.emit(current_enemy_preset)
	print("[WildernessManager] Starting battle vs %s (%s, HP %d) at Chunk %s" % [
		current_enemy_preset["name"],
		current_enemy_preset["tier"],
		current_enemy_preset["max_hp"],
		str(chunk_pos)
	])

	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://WildernessBattleStage.tscn")
	else:
		push_error("[WildernessManager] Could not resolve SceneTree to transition to WildernessBattleStage!")


## Dipanggil oleh WildernessBattleStage saat pertarungan selesai
func on_battle_completed(player_won: bool, remaining_player_hp: int) -> void:
	if player_won:
		player_hp = clampi(remaining_player_hp, 1, player_max_hp)
		enemies_defeated_count += 1
		if not current_chunk in defeated_chunks:
			defeated_chunks.append(current_chunk)
		consume_battle_buffs()
		print("[WildernessManager] Battle WON! Saved Player HP: %d/%d" % [player_hp, player_max_hp])
	else:
		player_hp = 0
		print("[WildernessManager] Battle LOST! Player Defeated.")


## Menghasilkan data rekapitulasi eksplorasi untuk ditampilkan saat sampai ke portal
func get_recap_data() -> Dictionary:
	return {
		"is_success": true,
		"final_hp": player_hp,
		"max_hp": player_max_hp,
		"enemies_defeated": enemies_defeated_count,
		"items_collected": items_collected_count,
		"active_buffs": active_buffs.duplicate(true),
		"threat_score": initial_threat_score,
	}
