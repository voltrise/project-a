class_name SpinningPortal
extends Sprite2D

var anim_timer: float = 0.0

func _ready() -> void:
	hframes = 8

func _process(delta: float) -> void:
	anim_timer += delta * 10.0
	if anim_timer >= 1.0:
		anim_timer = 0.0
		frame = (frame + 1) % max(1, hframes)
