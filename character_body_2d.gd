extends CharacterBody2D

const MAX_SPEED = 300.0
const ACCELERATION = 3000.0
const FRICTION = 1200.0

# Reference your sprite node
@onready var sprite_2d: Sprite2D = $PlayerSprite if has_node("PlayerSprite") else ($Pawn1 if has_node("Pawn1") else $Sprite2D)
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
var footstep_player: AudioStreamPlayer2D = null

@export var current_tool: String = "" # Options: "", "axe", "hammer", "knife", "pickaxe", "gold", "meat", "wood"
var is_interacting: bool = false

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
	
	var is_moving := velocity.length() > 10.0
	_update_animation(is_moving)
	
	var moved_dist = prev_pos.distance_to(global_position)
	if is_moving and moved_dist > 0.1:
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
		_update_animation(velocity.length() > 10.0)
