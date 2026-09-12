extends Node2D

@onready var obstacle_map_layer: TileMapLayer = $"../Obstacles"

@export var step_delay: float = 0.5

@export var open_color: Color = Color(0.25, 0.55, 1.0, 0.55)
@export var closed_color: Color = Color(0.9, 0.25, 0.25, 0.55)
@export var current_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var path_color: Color = Color(0.0, 0.96, 0.574, 1.0)
@export var text_color: Color = Color.WHITE

@export var font_size: int = 10

var debug_steps: Array = []
var final_path: Array[Vector2i] = []

var current_step: int = -1
var is_animating: bool = false

# Dipakai untuk membatalkan animasi lama jika player melakukan tap baru
var animation_id: int = 0

# =========================================
# DEBUGGER UI & FONT
# =========================================

var debug_open_button: Button
var close_button: Button
var path_debug_button: Button
var is_path_debug_enabled: bool = true

var font_regular: Font = null
var font_bold: Font = null

var debug_panel: PanelContainer
var step_label: Label
var expanded_label: Label
var open_label: Label
var closed_label: Label
var status_label: Label
var play_button: Button
var step_button: Button
var reset_button: Button
var speed_slider: HSlider

var is_paused: bool = true
var animation_finished: bool = false


func _ready() -> void:
	z_index = 100
	_load_fonts()
	_create_debugger_ui()

func _load_fonts() -> void:
	if ResourceLoader.exists("res://fonts/PixelifySans-Regular.ttf"):
		font_regular = load("res://fonts/PixelifySans-Regular.ttf")
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		font_bold = load("res://fonts/PixelifySans-Bold.ttf")

	if font_regular == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Pixelify Sans", "PixelifySans"])
		font_regular = sys
	if font_bold == null:
		var sys_b := SystemFont.new()
		sys_b.font_names = PackedStringArray(["Pixelify Sans", "PixelifySans"])
		sys_b.font_weight = 700
		font_bold = sys_b

func _create_debugger_ui() -> void:
	# CanvasLayer agar UI tetap di layar
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "DebuggerCanvas"
	add_child(canvas_layer)

	# Theme dengan font Pixelify Sans
	var theme := Theme.new()
	if font_regular != null:
		theme.default_font = font_regular
	theme.default_font_size = 11

	# Button DEBUG di ujung kiri atas saat panel ditutup
	debug_open_button = Button.new()
	debug_open_button.name = "DebugOpenButton"
	debug_open_button.text = "DEBUG"
	debug_open_button.position = Vector2(12, 12)
	debug_open_button.custom_minimum_size = Vector2(76, 30)
	debug_open_button.visible = false
	debug_open_button.theme = theme
	if font_bold != null:
		debug_open_button.add_theme_font_override("font", font_bold)
	debug_open_button.pressed.connect(_on_open_button_pressed)
	canvas_layer.add_child(debug_open_button)

	# Panel utama
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebuggerPanel"
	debug_panel.position = Vector2(12, 12)
	debug_panel.custom_minimum_size = Vector2(210, 0)
	debug_panel.theme = theme

	canvas_layer.add_child(debug_panel)

	# Container
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)

	debug_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)

	margin.add_child(vbox)

	# =========================================
	# HEADER (TITLE + [X] BUTTON)
	# =========================================

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "A* DEBUGGER"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font_bold != null:
		title.add_theme_font_override("font", font_bold)
	header.add_child(title)

	close_button = Button.new()
	close_button.text = "[X]"
	close_button.custom_minimum_size = Vector2(28, 22)
	if font_bold != null:
		close_button.add_theme_font_override("font", font_bold)
	close_button.pressed.connect(_on_close_button_pressed)
	header.add_child(close_button)

	# =========================================
	# STATUS
	# =========================================

	status_label = Label.new()
	status_label.text = "READY"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	# =========================================
	# INFO
	# =========================================

	step_label = Label.new()
	step_label.text = "Step: 0 / 0"
	vbox.add_child(step_label)

	expanded_label = Label.new()
	expanded_label.text = "Expanded: 0"
	vbox.add_child(expanded_label)

	open_label = Label.new()
	open_label.text = "Open: 0"
	vbox.add_child(open_label)

	closed_label = Label.new()
	closed_label.text = "Closed: 0"
	vbox.add_child(closed_label)

	# =========================================
	# BUTTONS
	# =========================================

	var button_container := HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 4)

	vbox.add_child(button_container)

	play_button = Button.new()
	play_button.text = "PLAY"
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_container.add_child(play_button)

	step_button = Button.new()
	step_button.text = "STEP"
	step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_container.add_child(step_button)

	reset_button = Button.new()
	reset_button.text = "RESET"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_container.add_child(reset_button)

	play_button.pressed.connect(_on_play_pressed)
	step_button.pressed.connect(_on_step_pressed)
	reset_button.pressed.connect(_on_reset_pressed)

	# =========================================
	# PATH DEBUG TOGGLE
	# =========================================

	path_debug_button = Button.new()
	path_debug_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font_bold != null:
		path_debug_button.add_theme_font_override("font", font_bold)
	path_debug_button.pressed.connect(_on_toggle_path_debug_pressed)
	vbox.add_child(path_debug_button)
	_update_path_debug_button()

	# =========================================
	# SPEED
	# =========================================

	var speed_label := Label.new()
	speed_label.text = "Speed"
	vbox.add_child(speed_label)

	speed_slider = HSlider.new()
	speed_slider.min_value = 0.02
	speed_slider.max_value = 0.5
	speed_slider.step = 0.01
	speed_slider.value = step_delay
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	vbox.add_child(speed_slider)

	# =========================================
	# LEGEND
	# =========================================

	var legend := Label.new()

	legend.text = "OPEN    = candidate\n"
	legend.text += "CLOSED  = evaluated\n"
	legend.text += "CURRENT = selected\n"
	legend.text += "PATH    = final path"

	vbox.add_child(legend)

func _on_close_button_pressed() -> void:
	debug_panel.visible = false
	debug_open_button.visible = true

func _on_open_button_pressed() -> void:
	debug_panel.visible = true
	debug_open_button.visible = false

func _on_toggle_path_debug_pressed() -> void:
	is_path_debug_enabled = not is_path_debug_enabled
	_update_path_debug_button()
	if not is_path_debug_enabled:
		animation_id += 1
		is_animating = false
		is_paused = true
		current_step = -1
		debug_steps.clear()
		final_path.clear()
		queue_redraw()
		if status_label != null:
			status_label.text = "DEBUG OFF"
	else:
		if status_label != null:
			status_label.text = "READY"

func _update_path_debug_button() -> void:
	if path_debug_button == null:
		return
	if is_path_debug_enabled:
		path_debug_button.text = "PATH DEBUG: ON"
		path_debug_button.modulate = Color(0.65, 1.0, 0.65)
	else:
		path_debug_button.text = "PATH DEBUG: OFF"
		path_debug_button.modulate = Color(1.0, 0.65, 0.65)

func _update_debugger_ui() -> void:
	if step_label == null:
		return

	if debug_steps.is_empty():
		step_label.text = "Step: 0 / 0"
		expanded_label.text = "Expanded: 0"
		open_label.text = "Open: 0"
		closed_label.text = "Closed: 0"
		return

	var safe_step: int = clamp(
		current_step,
		0,
		debug_steps.size() - 1
	)

	var snapshot: Dictionary = debug_steps[safe_step]

	var open_nodes: Array = snapshot["open"]
	var closed_nodes: Array = snapshot["closed"]

	step_label.text = "Step: %d / %d" % [
		safe_step + 1,
		debug_steps.size()
	]

	expanded_label.text = "Expanded: %d" % closed_nodes.size()
	open_label.text = "Open: %d" % open_nodes.size()
	closed_label.text = "Closed: %d" % closed_nodes.size()

func _on_play_pressed() -> void:
	if debug_steps.is_empty():
		return

	if is_animating:
		is_paused = not is_paused

		if is_paused:
			play_button.text = "PLAY"
			status_label.text = "PAUSED"
		else:
			play_button.text = "PAUSE"
			status_label.text = "PLAYING"

	else:
		is_paused = false
		is_animating = true
		play_button.text = "PAUSE"
		status_label.text = "PLAYING"

	_update_debugger_ui()

func _on_step_pressed() -> void:
	is_paused = true
	status_label.text = "STEPPING"

	_step_once()

func _on_reset_pressed() -> void:
	reset_animation()

func _step_once() -> void:
	if debug_steps.is_empty():
		return

	if current_step >= debug_steps.size() - 1:
		return

	current_step += 1

	queue_redraw()
	_update_debugger_ui()

func play_animation(
	steps: Array,
	path: Array[Vector2i]
) -> bool:
	if not is_path_debug_enabled:
		debug_steps.clear()
		final_path.clear()
		queue_redraw()
		return true

	animation_id += 1

	var my_animation_id: int = animation_id

	debug_steps = steps
	final_path = path

	current_step = -1
	is_animating = true
	is_paused = false
	animation_finished = false

	if play_button != null:
		play_button.text = "PAUSE"

	if status_label != null:
		status_label.text = "PLAYING"

	_update_debugger_ui()
	queue_redraw()

	while current_step < debug_steps.size() - 1:
		if not is_path_debug_enabled:
			return true

		if my_animation_id != animation_id:
			return false

		if is_paused:
			await get_tree().process_frame
			continue

		current_step += 1

		_update_debugger_ui()
		queue_redraw()

		await get_tree().create_timer(
			0.5 - speed_slider.value
		).timeout

	if not is_path_debug_enabled:
		return true

	if my_animation_id != animation_id:
		return false

	is_animating = false
	animation_finished = true
	is_paused = true

	if play_button != null:
		play_button.text = "PLAY"

	if status_label != null:
		status_label.text = "FINISHED"

	_update_debugger_ui()
	queue_redraw()

	return true


func step_forward() -> void:
	if debug_steps.is_empty():
		return

	if current_step < debug_steps.size() - 1:
		current_step += 1
		is_animating = false
		queue_redraw()


func reset_animation() -> void:
	animation_id += 1

	debug_steps.clear()
	final_path.clear()

	current_step = -1
	is_animating = false
	is_paused = true
	animation_finished = false

	play_button.text = "PLAY"
	status_label.text = "READY"

	_update_debugger_ui()
	queue_redraw()


func _get_tile_center(cell: Vector2i) -> Vector2:
	var local_pos: Vector2 = obstacle_map_layer.map_to_local(cell)
	var global_pos: Vector2 = obstacle_map_layer.to_global(local_pos)

	return to_local(global_pos)


func _get_tile_size() -> Vector2:
	var tile_size: Vector2i = obstacle_map_layer.tile_set.tile_size
	return Vector2(tile_size.x, tile_size.y)


func _draw() -> void:
	if not is_path_debug_enabled:
		return

	if obstacle_map_layer == null:
		return

	if current_step < 0:
		return

	if current_step >= debug_steps.size():
		return

	var snapshot: Dictionary = debug_steps[current_step]

	var tile_size := _get_tile_size()

	# =========================================
	# CLOSED
	# =========================================

	var closed_nodes: Array = snapshot["closed"]

	for node_data in closed_nodes:
		var cell: Vector2i = node_data["position"]
		var center := _get_tile_center(cell)

		var rect := Rect2(
			center - tile_size / 2.0,
			tile_size
		)

		draw_rect(
			rect,
			closed_color,
			true
		)

		_draw_values(
			center,
			node_data["g"],
			node_data["h"],
			node_data["f"]
		)

	# =========================================
	# OPEN
	# =========================================

	var open_nodes: Array = snapshot["open"]

	for node_data in open_nodes:
		var cell: Vector2i = node_data["position"]
		var center := _get_tile_center(cell)

		var rect := Rect2(
			center - tile_size / 2.0,
			tile_size
		)

		draw_rect(
			rect,
			open_color,
			true
		)

		_draw_values(
			center,
			node_data["g"],
			node_data["h"],
			node_data["f"]
		)

	# =========================================
	# CURRENT NODE
	# =========================================

	var current_node: Dictionary = snapshot["current"]

	if not current_node.is_empty():
		var current_cell: Vector2i = current_node["position"]
		var current_center := _get_tile_center(current_cell)

		var current_rect := Rect2(
			current_center - tile_size / 2.0,
			tile_size
		)

		draw_rect(
			current_rect,
			current_color,
			true
		)

		draw_rect(
			current_rect,
			text_color,
			false,
			2.0
		)

		_draw_values(
			current_center,
			current_node["g"],
			current_node["h"],
			current_node["f"]
		)

	# =========================================
	# FINAL PATH
	# HANYA MUNCUL SETELAH ANIMASI SELESAI
	# =========================================

	if not is_animating and current_step == debug_steps.size() - 1:
		for i in range(final_path.size()):
			var cell: Vector2i = final_path[i]
			var center := _get_tile_center(cell)

			var rect := Rect2(
				center - tile_size / 2.0,
				tile_size
			)

			draw_rect(
				rect,
				path_color,
				false,
				2.0
			)

			var draw_font: Font = font_bold if font_bold != null else (font_regular if font_regular != null else ThemeDB.fallback_font)
			draw_string(
				draw_font,
				center + Vector2(-2, 2),
				str(i),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				path_color
			)

func _draw_values(
	center: Vector2,
	g: float,
	h: float,
	f: float
) -> void:

	var font: Font = font_regular if font_regular != null else ThemeDB.fallback_font
	var tile_size := _get_tile_size()

	# Mulai dari sisi kiri tile
	var left_x: float = center.x - tile_size.x / 2.0 + 1.0

	# Sedikit naik supaya tiga baris muat
	var top_y: float = center.y - tile_size.y / 2.0 + 8.0

	draw_string(
		font,
		Vector2(left_x, top_y),
		"G:" + str(int(g)),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		text_color
	)

	draw_string(
		font,
		Vector2(left_x, top_y + 12.0),
		"H:" + str(int(h)),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		text_color
	)

	draw_string(
		font,
		Vector2(left_x, top_y + 24.0),
		"F:" + str(int(f)),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		text_color
	)
