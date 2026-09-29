class_name DiceButton
extends TextureButton

signal right_pressed

var _is_right_pressed: bool = false

@export_group("Hover Animation")
@export var hover_scale: Vector2 = Vector2(1.08, 1.08)
@export var hover_lift_y: float = -3.0
@export var hover_tint: Color = Color(1.15, 1.15, 1.25, 1.0)
@export var enable_idle_float: bool = true
@export var float_speed: float = 4.0
@export var float_amplitude: float = 2.0
@export var float_tilt_angle: float = 1.2

@export_group("Press Down")
@export var press_squash: Vector2 = Vector2(1.14, 0.86)
@export var press_drop_y: float = 3.0
@export var press_tilt: float = 3.5
@export var press_tint: Color = Color(0.86, 0.86, 0.92, 1.0)
@export var press_duration: float = 0.07

@export_group("Release & Bounce")
@export var bounce_stretch: Vector2 = Vector2(0.86, 1.22)
@export var bounce_squash: Vector2 = Vector2(1.12, 0.90)
@export var bounce_jump_y: float = -6.0
@export var enable_tumble_wobble: bool = true
@export var tumble_angle: float = 8.0

@export_group("Juice Effects")
@export var enable_particles: bool = true
@export var enable_sound: bool = true
@export var pitch_randomness: float = 0.08

# Node references
@onready var label: Label = get_node_or_null("Label")
@onready var particles: CPUParticles2D = get_node_or_null("Particles")
@onready var hover_sound: AudioStreamPlayer = get_node_or_null("HoverSound")
@onready var click_sound: AudioStreamPlayer = get_node_or_null("ClickSound")

# Anchor-safe vertical offsets (relative to anchor_top = 1.0)
var _base_offset_top: float = -96.0
var _base_offset_bottom: float = -16.0
var _anim_offset_y: float = 0.0
var _is_hovered: bool = false
var _is_pressed: bool = false
var _was_clicked: bool = false
var _float_time: float = 0.0

var _anim_tween: Tween
var _wobble_tween: Tween
var _label_tween: Tween

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Connect signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)

	# Cache initial layout offsets and update pivots
	call_deferred("_cache_base_offsets")
	resized.connect(_update_pivots)
	if get_viewport():
		get_viewport().size_changed.connect(_update_pivots)

func _cache_base_offsets() -> void:
	_base_offset_top = offset_top - _anim_offset_y
	_base_offset_bottom = offset_bottom - _anim_offset_y
	_update_pivots()

func _update_pivots() -> void:
	pivot_offset = size * 0.5
	if label:
		label.pivot_offset = label.size * 0.5
	if particles:
		particles.position = size * 0.5

func _apply_y_offset(extra_y: float) -> void:
	offset_top = _base_offset_top + extra_y
	offset_bottom = _base_offset_bottom + extra_y

func _set_animated_offset_y(val: float) -> void:
	_anim_offset_y = val
	_apply_y_offset(_anim_offset_y)

func _process(delta: float) -> void:
	var bob: float = 0.0
	# Subtle floating / breathing animation while hovered and not pressed
	if enable_idle_float and _is_hovered and not _is_pressed and (_wobble_tween == null or not _wobble_tween.is_running()):
		_float_time += delta
		bob = sin(_float_time * float_speed) * float_amplitude
		var tilt = cos(_float_time * float_speed * 0.6) * float_tilt_angle
		rotation_degrees = tilt
	elif not _is_hovered and not _is_pressed and (_anim_tween == null or not _anim_tween.is_running()):
		rotation_degrees = 0.0

	_apply_y_offset(_anim_offset_y + bob)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_is_right_pressed = true
			_on_button_down()
		elif _is_right_pressed:
			_is_right_pressed = false
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				_on_pressed()
				right_pressed.emit()
			_on_button_up()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_on_button_down()
			_on_pressed()
			pressed.emit()
			_on_button_up()

func _on_mouse_entered() -> void:
	_is_hovered = true
	_float_time = 0.0

	if enable_sound and hover_sound and not _is_pressed:
		hover_sound.pitch_scale = randf_range(1.0 - pitch_randomness, 1.0 + pitch_randomness)
		hover_sound.play()

	if _is_pressed:
		return

	_kill_tweens()
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(self, "scale", hover_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "self_modulate", hover_tint, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_method(_set_animated_offset_y, _anim_offset_y, hover_lift_y, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_mouse_exited() -> void:
	_is_hovered = false

	if _is_pressed:
		return

	_kill_tweens()
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "rotation_degrees", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "self_modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_method(_set_animated_offset_y, _anim_offset_y, 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_button_down() -> void:
	_is_pressed = true
	_was_clicked = false

	_kill_tweens()
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(self, "scale", press_squash, press_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "rotation_degrees", press_tilt, press_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "self_modulate", press_tint, press_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_method(_set_animated_offset_y, _anim_offset_y, press_drop_y, press_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if label:
		if _label_tween:
			_label_tween.kill()
		_label_tween = create_tween()
		_label_tween.tween_property(label, "scale", Vector2(0.92, 0.92), press_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_pressed() -> void:
	_was_clicked = true

	if enable_sound and click_sound:
		click_sound.pitch_scale = randf_range(1.0 - pitch_randomness, 1.0 + pitch_randomness)
		click_sound.play()

	if enable_particles and particles:
		particles.restart()

	_punch_label()

	if enable_tumble_wobble:
		_play_tumble_wobble()

func _on_button_up() -> void:
	_is_pressed = false

	_kill_tweens()
	_anim_tween = create_tween()

	var target_final_scale = hover_scale if _is_hovered else Vector2.ONE
	var target_final_offset = hover_lift_y if _is_hovered else 0.0
	var target_final_tint = hover_tint if _is_hovered else Color.WHITE

	if _was_clicked:
		_anim_tween.set_parallel(true)
		_anim_tween.tween_property(self, "scale", bounce_stretch, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_method(_set_animated_offset_y, _anim_offset_y, bounce_jump_y, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_property(self, "self_modulate", Color(1.2, 1.2, 1.3, 1.0), 0.10)

		_anim_tween.chain().set_parallel(true)
		_anim_tween.tween_property(self, "scale", bounce_squash, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_anim_tween.tween_method(_set_animated_offset_y, bounce_jump_y, target_final_offset + 2.0, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

		_anim_tween.chain().set_parallel(true)
		_anim_tween.tween_property(self, "scale", target_final_scale, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_property(self, "self_modulate", target_final_tint, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_method(_set_animated_offset_y, target_final_offset + 2.0, target_final_offset, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_anim_tween.set_parallel(true)
		_anim_tween.tween_property(self, "scale", target_final_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_property(self, "rotation_degrees", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_property(self, "self_modulate", target_final_tint, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_anim_tween.tween_method(_set_animated_offset_y, _anim_offset_y, target_final_offset, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_tumble_wobble() -> void:
	if _wobble_tween:
		_wobble_tween.kill()

	_wobble_tween = create_tween()
	_wobble_tween.tween_property(self, "rotation_degrees", -tumble_angle, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_wobble_tween.tween_property(self, "rotation_degrees", tumble_angle * 0.75, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_wobble_tween.tween_property(self, "rotation_degrees", -tumble_angle * 0.4, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_wobble_tween.tween_property(self, "rotation_degrees", tumble_angle * 0.15, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_wobble_tween.tween_property(self, "rotation_degrees", 0.0, 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _punch_label() -> void:
	if not label:
		return
	if _label_tween:
		_label_tween.kill()

	_label_tween = create_tween()
	_label_tween.set_parallel(true)
	_label_tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_label_tween.tween_property(label, "modulate", Color(1.3, 1.25, 0.9, 1.0), 0.08)

	_label_tween.chain().set_parallel(true)
	_label_tween.tween_property(label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_label_tween.tween_property(label, "modulate", Color.WHITE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _kill_tweens() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
