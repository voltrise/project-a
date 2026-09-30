extends Camera2D

# Target tracking configuration
@export var target: Node2D = null
@export var follow_speed: float = 8.0

var is_transitioning: bool = false
var active_tween: Tween = null

# Zoom configuration
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5   # Maximum zoomed out
@export var max_zoom: float = 2.0   # Maximum zoomed in

func _ready() -> void:
	var vp = get_viewport()
	if vp:
		vp.audio_listener_enable_2d = true
	if not has_node("AudioListener2D"):
		var listener := AudioListener2D.new()
		listener.name = "AudioListener2D"
		add_child(listener)
		listener.make_current()

	if target == null and get_parent() != null:
		target = get_parent().get_node_or_null("Player")
	if target != null and is_instance_valid(target):
		global_position = target.global_position

func _physics_process(delta: float) -> void:
	if not is_transitioning and target != null and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, delta * follow_speed)

func set_target(new_target: Node2D, smooth: bool = true) -> void:
	if new_target == null or not is_instance_valid(new_target):
		return
	target = new_target
	
	if not smooth or global_position.distance_to(new_target.global_position) < 40.0:
		global_position = new_target.global_position
		is_transitioning = false
		return
		
	if active_tween != null and active_tween.is_valid():
		active_tween.kill()
		
	is_transitioning = true
	active_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(self, "global_position", new_target.global_position, 0.45)
	active_tween.finished.connect(func(): is_transitioning = false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()

func zoom_in() -> void:
	var target_zoom := zoom + Vector2(zoom_speed, zoom_speed)
	zoom = target_zoom.clamp(Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))

func zoom_out() -> void:
	var target_zoom := zoom - Vector2(zoom_speed, zoom_speed)
	zoom = target_zoom.clamp(Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
