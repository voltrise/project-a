extends CharacterBody2D

const MAX_SPEED = 300.0
const ACCELERATION = 3000.0
const FRICTION = 1200.0

# Reference your sprite node (change 'Sprite2D' to match your node name)
@onready var sprite_2d: Sprite2D = $Pawn1
var footstep_player: AudioStreamPlayer2D = null

var footstep_sounds: Array[AudioStream] = [
	preload("res://audio/grass_step_1.wav"),
	preload("res://audio/grass_step_2.wav"),
	preload("res://audio/grass_step_3.wav"),
	preload("res://audio/grass_step_4.wav")
]
var last_footstep_index: int = -1
var step_distance_threshold: float = 95.0
var distance_accumulated: float = 0.0
var step_cooldown: float = 0.0

func _ready() -> void:
	if has_node("FootstepAudio"):
		footstep_player = $FootstepAudio
	else:
		footstep_player = AudioStreamPlayer2D.new()
		footstep_player.name = "FootstepAudio"
		add_child(footstep_player)
	footstep_player.volume_db = -14.0
	footstep_player.max_polyphony = 2

func _physics_process(delta: float) -> void:
	if step_cooldown > 0.0:
		step_cooldown -= delta

	var direction := Input.get_vector("left", "right", "up", "down")
	var prev_pos = global_position
	
	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * MAX_SPEED, ACCELERATION * delta)
		
		# Flip sprite based on horizontal input
		if direction.x < 0:
			sprite_2d.flip_h = true   # Facing left
		elif direction.x > 0:
			sprite_2d.flip_h = false  # Facing right
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

	move_and_slide()
	
	var moved_dist = prev_pos.distance_to(global_position)
	if velocity.length() > 10.0 and moved_dist > 0.1:
		distance_accumulated += moved_dist
		if distance_accumulated >= step_distance_threshold and step_cooldown <= 0.0:
			play_footstep()
			distance_accumulated = 0.0
			step_cooldown = 0.28
	else:
		distance_accumulated = step_distance_threshold * 0.6

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
