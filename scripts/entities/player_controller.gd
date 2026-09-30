extends CharacterBody2D

@onready var path_map_layer: TileMapLayer = $"../Path" if has_node("../Path") else null
@onready var path_debug: Node2D = $"../PathDebug" if has_node("../PathDebug") else null

var current_path: Array[Vector2] = []
var debug_path: Array[Vector2] = []

@onready var sprite: Sprite2D = $PlayerSprite
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var footstep_player: AudioStreamPlayer2D = $FootstepAudio if has_node("FootstepAudio") else null

@export var is_active_character: bool = true
@export var character_name: String = "Pawn"
@export var current_tool: String = "" # Options: "", "axe", "hammer", "knife", "pickaxe", "gold", "meat", "wood"
var is_interacting: bool = false
var stuck_counter: int = 0

var footstep_sounds: Array[AudioStream] = [
	preload("res://audio/sfx/grass_step_1.wav"),
	preload("res://audio/sfx/grass_step_2.wav"),
	preload("res://audio/sfx/grass_step_3.wav"),
	preload("res://audio/sfx/grass_step_4.wav")
]
var last_footstep_index: int = -1
var step_distance_threshold: float = 140.0
var distance_accumulated: float = 0.0
var step_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("players")

	if footstep_player == null:
		if has_node("FootstepAudio"):
			footstep_player = $FootstepAudio
		else:
			footstep_player = AudioStreamPlayer2D.new()
			footstep_player.name = "FootstepAudio"
			add_child(footstep_player)
	footstep_player.volume_db = -14.0
	footstep_player.max_polyphony = 2

	# Ensure BGMPlayer loops seamlessly
	if get_tree() and get_tree().root:
		var bgm = get_tree().root.find_child("BGMPlayer", true, false) as AudioStreamPlayer
		if bgm:
			if bgm.stream is AudioStreamWAV:
				var wav_stream = bgm.stream as AudioStreamWAV
				wav_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				if wav_stream.loop_end <= 0:
					wav_stream.loop_end = wav_stream.data.size() / 4
			if not bgm.finished.is_connected(bgm.play):
				bgm.finished.connect(bgm.play)
			if not bgm.playing:
				bgm.play()

	_update_animation(false)

func set_active(active: bool) -> void:
	is_active_character = active
	if not active:
		current_path.clear()
		_update_animation(false)

func get_other_player_tiles() -> Array:
	var tiles: Array = []
	if not path_map_layer:
		return tiles
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is CharacterBody2D and is_instance_valid(p):
			var tile: Vector2i = path_map_layer.local_to_map(
				path_map_layer.to_local(p.global_position)
			)
			if not tile in tiles:
				tiles.append(tile)
			if p.get("current_path") != null and not p.current_path.is_empty():
				var dest_tile: Vector2i = path_map_layer.local_to_map(
					path_map_layer.to_local(p.current_path[p.current_path.size() - 1])
				)
				if not dest_tile in tiles:
					tiles.append(dest_tile)
	return tiles

func _unhandled_input(event: InputEvent) -> void:
	if not is_active_character:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_pos = get_global_mouse_position()
		move_to(mouse_pos)
		
func move_to(pos: Vector2) -> void:
	if not path_map_layer:
		return

	var start_tile: Vector2i = path_map_layer.local_to_map(
		path_map_layer.to_local(global_position)
	)

	var target_tile: Vector2i = path_map_layer.local_to_map(
		path_map_layer.to_local(pos)
	)

	# 1. Jangan proses jika klik di tile yang sama dengan posisi karakter saat ini (fix bug crash)
	if start_tile == target_tile:
		return

	# 2. Ambil semua tile yang diblokir player lain untuk collision & path avoidance
	var blocked_tiles: Array = get_other_player_tiles()

	# Jika target klik tepat di tile yang terblokir atau non-walkable di Path, cari tile adjacent yang walkable terdekat
	if not CustomAStar.is_walkable(path_map_layer, target_tile, blocked_tiles):
		var found_adj := false
		for offset in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			var candidate: Vector2i = target_tile + offset
			if candidate != start_tile and CustomAStar.is_walkable(path_map_layer, candidate, blocked_tiles):
				target_tile = candidate
				found_adj = true
				break
		if not found_adj:
			return

	# =========================================
	# HITUNG A* + RECORD SEMUA LANGKAH (HANYA DARI LAYER PATH)
	# =========================================

	var debug_result: Dictionary = (
		CustomAStar.find_path_debug(
			path_map_layer,
			start_tile,
			target_tile,
			blocked_tiles
		)
	)
	
	if not debug_result.has("path") or debug_result["path"].is_empty():
		return

	var astar_path: Array[Vector2i] = []
	astar_path.assign(debug_result["path"])

	var debug_steps: Array = (
		debug_result["steps"]
	)

	if astar_path.size() <= 1:
		return

	# =========================================
	# PUTAR ANIMASI DEBUG (JIKA DIAKTIFKAN)
	# =========================================

	if path_debug != null:
		var animation_completed: bool = await path_debug.play_animation(
			debug_steps,
			astar_path
		)

		if not animation_completed:
			return

	# =========================================
	# SET MOVEMENT PATH
	# =========================================

	current_path.clear()
	stuck_counter = 0

	for i in range(1, astar_path.size()):
		var tile: Vector2i = astar_path[i]
		var pixel_pos: Vector2 = (
			path_map_layer.to_global(
				path_map_layer.map_to_local(tile)
			)
		)
		current_path.append(pixel_pos)

func _physics_process(delta: float) -> void:
	if step_cooldown > 0.0:
		step_cooldown -= delta

	var is_moving := not current_path.is_empty()
	_update_animation(is_moving)

	if not is_moving:
		distance_accumulated = step_distance_threshold * 0.6
		stuck_counter = 0
		return
		
	# Target world position
	var target_pos = current_path[0]
	var prev_pos = global_position
	
	var to_target: Vector2 = target_pos - global_position
	var step_amount: float = delta * 500.0
	
	if to_target.length() <= step_amount:
		global_position = target_pos
		current_path.pop_front()
		stuck_counter = 0
	else:
		velocity = to_target.normalized() * 500.0
		move_and_slide()
		
		# Collision dengan player lain: hentikan pergerakan agar tidak menembus atau bertumpuk
		for i in range(get_slide_collision_count()):
			var col = get_slide_collision(i)
			var collider = col.get_collider()
			if collider is CharacterBody2D and collider != self:
				current_path.clear()
				_update_animation(false)
				stuck_counter = 0
				return

		# Check jika sudah dekat target (dalam 4 pixel), snap dan lanjutkan ke waypoint berikutnya
		if global_position.distance_to(target_pos) <= 4.0:
			global_position = target_pos
			current_path.pop_front()
			stuck_counter = 0
		elif prev_pos.distance_to(global_position) < 0.1:
			stuck_counter += 1
			if stuck_counter > 10:
				# Safeguard: jika pergerakan terhambat selama 10 physics frame, lanjutkan waypoint
				current_path.pop_front()
				stuck_counter = 0
		else:
			stuck_counter = 0
	
	# Trigger grass footsteps based on distance moved and cooldown
	var moved_dist = prev_pos.distance_to(global_position)
	distance_accumulated += moved_dist
	if distance_accumulated >= step_distance_threshold and step_cooldown <= 0.0:
		play_footstep()
		distance_accumulated = 0.0
		step_cooldown = 0.24
	
	if target_pos.x < global_position.x - 1.0:
		sprite.flip_h = true
	elif target_pos.x > global_position.x + 1.0:
		sprite.flip_h = false

func play_footstep() -> void:
	if footstep_sounds.is_empty() or footstep_player == null:
		return
	var idx = randi() % footstep_sounds.size()
	if idx == last_footstep_index and footstep_sounds.size() > 1:
		idx = (idx + 1) % footstep_sounds.size()
	last_footstep_index = idx
	
	footstep_player.stream = footstep_sounds[idx]
	footstep_player.pitch_scale = randf_range(0.95, 1.05)
	footstep_player.volume_db = -14.0 + randf_range(-1.0, 1.0)
	footstep_player.play()

func _update_animation(moving: bool) -> void:
	if animation_player == null:
		return
	if is_interacting and not moving:
		return
	is_interacting = false
	
	var prefix = "run" if moving else "idle"
	var anim_name = prefix if current_tool.is_empty() else prefix + "_" + current_tool
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)
	elif animation_player.has_animation(prefix):
		if animation_player.current_animation != prefix:
			animation_player.play(prefix)

func play_interact(tool_name: String = "") -> void:
	if animation_player == null:
		return
	var tool_to_use = tool_name if not tool_name.is_empty() else current_tool
	if tool_to_use.is_empty():
		tool_to_use = "axe"
	var anim_name = "interact_" + tool_to_use
	if animation_player.has_animation(anim_name):
		is_interacting = true
		animation_player.play(anim_name)
		await animation_player.animation_finished
		is_interacting = false
		_update_animation(not current_path.is_empty())
	elif animation_player.has_animation("shoot"):
		is_interacting = true
		animation_player.play("shoot")
		await animation_player.animation_finished
		is_interacting = false
		_update_animation(not current_path.is_empty())
