extends CharacterBody2D

@onready var obstacle_map_layer: TileMapLayer = $"../Obstacles"
@onready var path_debug: Node2D = $"../PathDebug"

var current_path: Array[Vector2] = []
var debug_path: Array[Vector2] = []

@onready var sprite: Sprite2D = $PlayerSprite

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
	if current_path.is_empty():
		return
		
	# Target world position
	var target_pos = current_path[0]
	
	# Move toward target position
	global_position = global_position.move_toward(target_pos, delta * 500)
	
	if target_pos.x < global_position.x:
		sprite.flip_h = true
	elif target_pos.x > global_position.x:
		sprite.flip_h = false
	
	# Check if reached target (within 1 pixel), then remove point from array to target next tile
	if global_position.distance_to(target_pos) < 1.0:
		global_position = target_pos
		current_path.pop_front()
