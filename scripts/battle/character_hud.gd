class_name CharacterHUD
extends Node2D

@export var character_name: String = "ALLIES":
	set(val):
		character_name = val
		if is_node_ready() and name_label:
			name_label.text = val

@export var is_enemy: bool = false:
	set(val):
		is_enemy = val
		if is_node_ready():
			_update_pointer_color()
			_update_value_visibility()

@export var show_value_text: bool = true:
	set(val):
		show_value_text = val
		if is_node_ready():
			_update_value_visibility()

@export var max_hp: int = 100
@export var current_hp: int = 100
@export var max_stamina: int = 100
@export var current_stamina: int = 100

@onready var name_label: Label = $Nametag/NameLabel
@onready var pointer: Polygon2D = $Nametag/Pointer
@onready var hp_bar: ProgressBar = $Bars/HPRow/BarContainer/HBox/HPBar
@onready var hp_val_label: Label = $Bars/HPRow/HPValue
@onready var stamina_bar: ProgressBar = $Bars/StaminaRow/BarContainer/HBox/StaminaBar
@onready var stamina_val_label: Label = $Bars/StaminaRow/StaminaValue

var _hp_tween: Tween
var _stamina_tween: Tween

func _ready() -> void:
	if name_label:
		name_label.text = character_name
	_update_pointer_color()
	_update_value_visibility()
	_update_bars(false)

func _update_pointer_color() -> void:
	if pointer:
		if is_enemy:
			pointer.color = Color(0.95, 0.35, 0.35, 1.0)
		else:
			pointer.color = Color(0.28, 0.78, 0.98, 1.0)

func _update_value_visibility() -> void:
	if stamina_val_label:
		stamina_val_label.visible = show_value_text
	if hp_val_label:
		hp_val_label.visible = show_value_text

func set_character_name(new_name: String) -> void:
	character_name = new_name
	if name_label:
		name_label.text = new_name

func set_hp(val: int, maximum: int = -1, animated: bool = true) -> void:
	if maximum > 0:
		max_hp = maximum
	current_hp = clampi(val, 0, max_hp)
	_update_hp_bar(animated)

func set_stamina(val: int, maximum: int = -1, animated: bool = true) -> void:
	if maximum > 0:
		max_stamina = maximum
	current_stamina = clampi(val, 0, max_stamina)
	_update_stamina_bar(animated)

func _update_bars(animated: bool = true) -> void:
	_update_hp_bar(animated)
	_update_stamina_bar(animated)

func _update_hp_bar(animated: bool) -> void:
	if not hp_bar:
		return
	hp_bar.max_value = max_hp
	if hp_val_label:
		hp_val_label.text = "%d/%d" % [current_hp, max_hp]
	if animated:
		if _hp_tween and _hp_tween.is_valid():
			_hp_tween.kill()
		_hp_tween = create_tween()
		_hp_tween.tween_property(hp_bar, "value", float(current_hp), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		hp_bar.value = float(current_hp)

func _update_stamina_bar(animated: bool) -> void:
	if not stamina_bar:
		return
	stamina_bar.max_value = max_stamina
	if stamina_val_label:
		stamina_val_label.text = "%d/%d" % [current_stamina, max_stamina]
	if animated:
		if _stamina_tween and _stamina_tween.is_valid():
			_stamina_tween.kill()
		_stamina_tween = create_tween()
		_stamina_tween.tween_property(stamina_bar, "value", float(current_stamina), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		stamina_bar.value = float(current_stamina)
