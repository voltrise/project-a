extends CharacterBody2D

@onready var obstacle_map_layer: TileMapLayer = $"../Obstacles"
@onready var path_debug: Node2D = $"../PathDebug"

var current_path: Array[Vector2] = []
var debug_path: Array[Vector2] = []

@onready var sprite: Sprite2D = $PlayerSprite
@onready var footstep_player: AudioStreamPlayer2D = $FootstepAudio if has_node("FootstepAudio") else null

var footstep_sounds: Array[AudioStream] = [
	preload("res://audio/grass_step_1.wav"),
	preload("res://audio/grass_step_2.wav"),
	preload("res://audio/grass_step_3.wav"),
	preload("res://audio/grass_step_4.wav")
]
var last_footstep_index: int = -1
var step_distance_threshold: float = 140.0
var distance_accumulated: float = 0.0
var step_cooldown: float = 0.0

func _ready() -> void:
	if footstep_player == null:
		if has_node("FootstepAudio"):
			footstep_player = $FootstepAudio
		else:
			footstep_player = AudioStreamPlayer2D.new()
			footstep_player.name = "FootstepAudio"
			add_child(footstep_player)
	footstep_player.volume_db = -14.0
	footstep_player.max_polyphony = 2

#func _ready() -> void:
	#if obstacle_map_layer:
		# Convert global position to map coords
		#var map_pos = obstacle_map_layer.local_to_map(obstacle_map_layer.to_local(global_position))
		# Snap centered position correctly in global space
		#global_position = obstacle_map_layer.to_global(obstacle_map_layer.map_to_local(map_pos))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_pos = get_global_mouse_position()
		move_to(mouse_pos)
		
func move_to(pos: Vector2) -> void:
	if not obstacle_map_layer:
		return

	var start_tile: Vector2i = obstacle_map_layer.local_to_map(
		obstacle_map_layer.to_local(global_position)
	)

	var target_tile: Vector2i = obstacle_map_layer.local_to_map(
		obstacle_map_layer.to_local(pos)
	)

	# Jangan klik obstacle
	if obstacle_map_layer.get_cell_source_id(target_tile) != -1:
		return

	# =========================================
	# HITUNG A* + RECORD SEMUA LANGKAH
	# =========================================

	var debug_result: Dictionary = (
		CustomAStar.find_path_debug(
			null,
			obstacle_map_layer,
			start_tile,
			target_tile
		)
	)
	
	if debug_result["path"] == []:
		return

	var astar_path: Array[Vector2i] = (
		debug_result["path"]
	)

	var debug_steps: Array = (
		debug_result["steps"]
	)

	if astar_path.is_empty():
		return

	# =========================================
	# PUTAR ANIMASI DEBUG
	# =========================================

	var animation_completed: bool = await $"../PathDebug".play_animation(
	debug_steps,
	astar_path
	)

	if not animation_completed:
		return

	# =========================================
	# SET MOVEMENT PATH
	# =========================================

	current_path.clear()

	for i in range(1, astar_path.size()):

		var tile: Vector2i = astar_path[i]

		var pixel_pos: Vector2 = (
			obstacle_map_layer.to_global(
				obstacle_map_layer.map_to_local(tile)
			)
		)

		current_path.append(pixel_pos)

func _physics_process(delta: float) -> void:
	if step_cooldown > 0.0:
		step_cooldown -= delta

	if current_path.is_empty():
		distance_accumulated = step_distance_threshold * 0.6
		return
		
	# Target world position
	var target_pos = current_path[0]
	var prev_pos = global_position
	
	# Move toward target position
	global_position = global_position.move_toward(target_pos, delta * 500)
	
	# Trigger grass footsteps based on distance moved and cooldown
	var moved_dist = prev_pos.distance_to(global_position)
	distance_accumulated += moved_dist
	if distance_accumulated >= step_distance_threshold and step_cooldown <= 0.0:
		play_footstep()
		distance_accumulated = 0.0
		step_cooldown = 0.24
	
	if target_pos.x < global_position.x:
		sprite.flip_h = true
	elif target_pos.x > global_position.x:
		sprite.flip_h = false
	
	# Check if reached target (within 1 pixel), then remove point from array to target next tile
	if global_position.distance_to(target_pos) < 1.0:
		global_position = target_pos
		current_path.pop_front()

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
