extends CharacterBody2D

const MAX_SPEED = 300.0
const ACCELERATION = 3000.0
const FRICTION = 1200.0

# Reference your sprite node (change 'Sprite2D' to match your node name)
@onready var sprite_2d: Sprite2D = $Pawn1
	
func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("left", "right", "up", "down")
	
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
