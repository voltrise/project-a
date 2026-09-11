extends Camera2D

# Zoom configuration
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5   # Maximum zoomed out
@export var max_zoom: float = 2.0   # Maximum zoomed in

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
