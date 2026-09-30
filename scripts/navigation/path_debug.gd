extends Node2D

@onready var path_map_layer: TileMapLayer = $"../Path"

@export var step_delay: float = 0.5

# =========================================
# A* VISUALIZATION COLORS
# =========================================
@export var open_color: Color = Color(0.25, 0.55, 1.0, 0.55)
@export var closed_color: Color = Color(0.9, 0.25, 0.25, 0.55)
@export var current_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var path_color: Color = Color(0.0, 0.96, 0.574, 1.0)
@export var text_color: Color = Color.WHITE

# =========================================
# UCS VISUALIZATION COLORS
# =========================================
@export var ucs_open_color: Color = Color(0.15, 0.75, 0.85, 0.55)
@export var ucs_closed_color: Color = Color(0.75, 0.3, 0.85, 0.55)
@export var ucs_current_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var ucs_path_color: Color = Color(1.0, 0.82, 0.1, 1.0)

@export var font_size: int = 10

# =========================================
# A* STATE
# =========================================
var debug_steps: Array = []
var final_path: Array[Vector2i] = []
var current_step: int = -1
var is_animating: bool = false
var animation_id: int = 0
var is_path_debug_enabled: bool = false
var is_paused: bool = true
var animation_finished: bool = false

# =========================================
# UCS STATE
# =========================================
var ucs_debug_steps: Array = []
var ucs_final_path: Array[Vector2i] = []
var ucs_current_step: int = -1
var ucs_is_animating: bool = false
var ucs_animation_id: int = 0
var is_ucs_debug_enabled: bool = false
var ucs_is_paused: bool = true
var ucs_animation_finished: bool = false
var ucs_active_npc_name: String = ""

# =========================================
# UI ELEMENTS
# =========================================
var font_regular: Font = null
var font_bold: Font = null

# Menu Button List (Top-Left)
var debug_button_container: VBoxContainer
var astar_open_button: Button
var ucs_open_button: Button
var debug_open_button: Button # Backward compatibility alias

# A* Panel Elements
var debug_panel: PanelContainer
var close_button: Button
var status_label: Label
var step_label: Label
var expanded_label: Label
var open_label: Label
var closed_label: Label
var play_button: Button
var step_button: Button
var reset_button: Button
var path_debug_button: Button
var speed_slider: HSlider

# UCS Panel Elements
var ucs_panel: PanelContainer
var ucs_close_button: Button
var ucs_status_label: Label
var ucs_npc_label: Label
var ucs_step_label: Label
var ucs_expanded_label: Label
var ucs_open_label: Label
var ucs_closed_label: Label
var ucs_play_button: Button
var ucs_step_button: Button
var ucs_reset_button: Button
var ucs_debug_button: Button
var ucs_speed_slider: HSlider

var ucs_panel_user_closed: bool = false
var _follow_check_timer: float = 0.0


func _ready() -> void:
	z_index = 100
	_load_fonts()
	_create_debugger_ui()

func _process(delta: float) -> void:
	_follow_check_timer -= delta
	if _follow_check_timer <= 0.0:
		_follow_check_timer = 0.3
		_check_following_npc_status()

func has_following_npc() -> bool:
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if is_instance_valid(npc) and npc.get("is_following") == true:
			return true
	return false

func get_following_npc() -> Node2D:
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if is_instance_valid(npc) and npc.get("is_following") == true:
			return npc as Node2D
	return null

func _check_following_npc_status() -> void:
	var follower = get_following_npc()
	if follower == null:
		if ucs_debug_steps.size() > 0 or ucs_final_path.size() > 0 or ucs_is_animating:
			reset_ucs_animation()
		if ucs_npc_label != null and ucs_npc_label.text != "NPC: None":
			ucs_npc_label.text = "NPC: None"
	else:
		if ucs_npc_label != null:
			var char_name: String = ""
			if follower.get("character_data") is Dictionary:
				char_name = follower.character_data.get("name", "NPC")
			else:
				char_name = follower.name
			ucs_npc_label.text = "NPC: " + char_name

func on_npc_follow_changed(npc: Node2D, following: bool) -> void:
	if following:
		var char_name: String = ""
		if npc.get("character_data") is Dictionary:
			char_name = npc.character_data.get("name", "NPC")
		else:
			char_name = npc.name
		ucs_active_npc_name = char_name
		if ucs_npc_label != null:
			ucs_npc_label.text = "NPC: " + char_name
	else:
		_check_following_npc_status()

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
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "DebuggerCanvas"
	add_child(canvas_layer)

	var theme := Theme.new()
	if font_regular != null:
		theme.default_font = font_regular
	theme.default_font_size = 11

	# =========================================
	# TOP-LEFT BUTTON LIST (A* Debug & UCS Debug)
	# =========================================
	debug_button_container = VBoxContainer.new()
	debug_button_container.name = "DebugButtonList"
	debug_button_container.position = Vector2(12, 12)
	debug_button_container.add_theme_constant_override("separation", 6)
	canvas_layer.add_child(debug_button_container)

	astar_open_button = Button.new()
	astar_open_button.name = "AStarDebugButton"
	astar_open_button.text = "A* Debug"
	astar_open_button.custom_minimum_size = Vector2(96, 30)
	astar_open_button.theme = theme
	if font_bold != null:
		astar_open_button.add_theme_font_override("font", font_bold)
	astar_open_button.pressed.connect(_on_astar_open_pressed)
	debug_button_container.add_child(astar_open_button)

	debug_open_button = astar_open_button # Compatibility

	ucs_open_button = Button.new()
	ucs_open_button.name = "UCSDebugButton"
	ucs_open_button.text = "UCS Debug"
	ucs_open_button.custom_minimum_size = Vector2(96, 30)
	ucs_open_button.theme = theme
	if font_bold != null:
		ucs_open_button.add_theme_font_override("font", font_bold)
	ucs_open_button.pressed.connect(_on_ucs_open_pressed)
	debug_button_container.add_child(ucs_open_button)

	# =========================================
	# A* DEBUGGER PANEL
	# =========================================
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebuggerPanel"
	debug_panel.position = Vector2(118, 12)
	debug_panel.custom_minimum_size = Vector2(210, 0)
	debug_panel.theme = theme
	debug_panel.visible = false
	canvas_layer.add_child(debug_panel)

	var margin_a := MarginContainer.new()
	margin_a.add_theme_constant_override("margin_left", 10)
	margin_a.add_theme_constant_override("margin_right", 10)
	margin_a.add_theme_constant_override("margin_top", 8)
	margin_a.add_theme_constant_override("margin_bottom", 10)
	debug_panel.add_child(margin_a)

	var vbox_a := VBoxContainer.new()
	vbox_a.add_theme_constant_override("separation", 5)
	margin_a.add_child(vbox_a)

	var header_a := HBoxContainer.new()
	header_a.add_theme_constant_override("separation", 4)
	vbox_a.add_child(header_a)

	var title_a := Label.new()
	title_a.text = "A* DEBUGGER"
	title_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font_bold != null:
		title_a.add_theme_font_override("font", font_bold)
	header_a.add_child(title_a)

	close_button = Button.new()
	close_button.text = "[X]"
	close_button.custom_minimum_size = Vector2(28, 22)
	if font_bold != null:
		close_button.add_theme_font_override("font", font_bold)
	close_button.pressed.connect(_on_close_button_pressed)
	header_a.add_child(close_button)

	status_label = Label.new()
	status_label.text = "READY"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_a.add_child(status_label)

	step_label = Label.new()
	step_label.text = "Step: 0 / 0"
	vbox_a.add_child(step_label)

	expanded_label = Label.new()
	expanded_label.text = "Expanded: 0"
	vbox_a.add_child(expanded_label)

	open_label = Label.new()
	open_label.text = "Open: 0"
	vbox_a.add_child(open_label)

	closed_label = Label.new()
	closed_label.text = "Closed: 0"
	vbox_a.add_child(closed_label)

	var btn_box_a := HBoxContainer.new()
	btn_box_a.add_theme_constant_override("separation", 4)
	vbox_a.add_child(btn_box_a)

	play_button = Button.new()
	play_button.text = "PLAY"
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box_a.add_child(play_button)

	step_button = Button.new()
	step_button.text = "STEP"
	step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box_a.add_child(step_button)

	reset_button = Button.new()
	reset_button.text = "RESET"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box_a.add_child(reset_button)

	play_button.pressed.connect(_on_play_pressed)
	step_button.pressed.connect(_on_step_pressed)
	reset_button.pressed.connect(_on_reset_pressed)

	path_debug_button = Button.new()
	path_debug_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font_bold != null:
		path_debug_button.add_theme_font_override("font", font_bold)
	path_debug_button.pressed.connect(_on_toggle_path_debug_pressed)
	vbox_a.add_child(path_debug_button)
	_update_path_debug_button()

	var speed_label_a := Label.new()
	speed_label_a.text = "Speed"
	vbox_a.add_child(speed_label_a)

	speed_slider = HSlider.new()
	speed_slider.min_value = 0.02
	speed_slider.max_value = 0.5
	speed_slider.step = 0.01
	speed_slider.value = step_delay
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_a.add_child(speed_slider)

	var legend_a := Label.new()
	legend_a.text = "OPEN    = candidate\nCLOSED  = evaluated\nCURRENT = selected\nPATH    = final path"
	vbox_a.add_child(legend_a)

	# =========================================
	# UCS DEBUGGER PANEL
	# =========================================
	ucs_panel = PanelContainer.new()
	ucs_panel.name = "UCSDebuggerPanel"
	ucs_panel.position = Vector2(338, 12)
	ucs_panel.custom_minimum_size = Vector2(210, 0)
	ucs_panel.theme = theme
	ucs_panel.visible = false
	canvas_layer.add_child(ucs_panel)

	var margin_u := MarginContainer.new()
	margin_u.add_theme_constant_override("margin_left", 10)
	margin_u.add_theme_constant_override("margin_right", 10)
	margin_u.add_theme_constant_override("margin_top", 8)
	margin_u.add_theme_constant_override("margin_bottom", 10)
	ucs_panel.add_child(margin_u)

	var vbox_u := VBoxContainer.new()
	vbox_u.add_theme_constant_override("separation", 5)
	margin_u.add_child(vbox_u)

	var header_u := HBoxContainer.new()
	header_u.add_theme_constant_override("separation", 4)
	vbox_u.add_child(header_u)

	var title_u := Label.new()
	title_u.text = "UCS DEBUGGER"
	title_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font_bold != null:
		title_u.add_theme_font_override("font", font_bold)
	header_u.add_child(title_u)

	ucs_close_button = Button.new()
	ucs_close_button.text = "[X]"
	ucs_close_button.custom_minimum_size = Vector2(28, 22)
	if font_bold != null:
		ucs_close_button.add_theme_font_override("font", font_bold)
	ucs_close_button.pressed.connect(_on_ucs_close_pressed)
	header_u.add_child(ucs_close_button)

	ucs_status_label = Label.new()
	ucs_status_label.text = "READY"
	ucs_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_u.add_child(ucs_status_label)

	ucs_npc_label = Label.new()
	ucs_npc_label.text = "NPC: None"
	vbox_u.add_child(ucs_npc_label)

	ucs_step_label = Label.new()
	ucs_step_label.text = "Step: 0 / 0"
	vbox_u.add_child(ucs_step_label)

	ucs_expanded_label = Label.new()
	ucs_expanded_label.text = "Expanded: 0"
	vbox_u.add_child(ucs_expanded_label)

	ucs_open_label = Label.new()
	ucs_open_label.text = "Open: 0"
	vbox_u.add_child(ucs_open_label)

	ucs_closed_label = Label.new()
	ucs_closed_label.text = "Closed: 0"
	vbox_u.add_child(ucs_closed_label)

	var btn_box_u := HBoxContainer.new()
	btn_box_u.add_theme_constant_override("separation", 4)
	vbox_u.add_child(btn_box_u)

	ucs_play_button = Button.new()
	ucs_play_button.text = "PLAY"
	ucs_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box_u.add_child(ucs_play_button)

	ucs_step_button = Button.new()
	ucs_step_button.text = "STEP"
	ucs_step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box_u.add_child(ucs_step_button)

	ucs_reset_button = Button.new()
	ucs_reset_button.text = "RESET"
	ucs_reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box_u.add_child(ucs_reset_button)

	ucs_play_button.pressed.connect(_on_ucs_play_pressed)
	ucs_step_button.pressed.connect(_on_ucs_step_pressed)
	ucs_reset_button.pressed.connect(_on_ucs_reset_pressed)

	ucs_debug_button = Button.new()
	ucs_debug_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font_bold != null:
		ucs_debug_button.add_theme_font_override("font", font_bold)
	ucs_debug_button.pressed.connect(_on_toggle_ucs_debug_pressed)
	vbox_u.add_child(ucs_debug_button)
	_update_ucs_debug_button()

	var speed_label_u := Label.new()
	speed_label_u.text = "Speed"
	vbox_u.add_child(speed_label_u)

	ucs_speed_slider = HSlider.new()
	ucs_speed_slider.min_value = 0.02
	ucs_speed_slider.max_value = 0.5
	ucs_speed_slider.step = 0.01
	ucs_speed_slider.value = step_delay
	ucs_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_u.add_child(ucs_speed_slider)

	var legend_u := Label.new()
	legend_u.text = "OPEN    = candidate\nCLOSED  = evaluated\nCURRENT = selected\nPATH    = final path"
	vbox_u.add_child(legend_u)

	_update_menu_buttons()

# =========================================
# MENU BUTTON HANDLERS
# =========================================
func _on_astar_open_pressed() -> void:
	if debug_panel:
		debug_panel.visible = not debug_panel.visible
	_update_menu_buttons()

func _on_ucs_open_pressed() -> void:
	if ucs_panel:
		ucs_panel.visible = not ucs_panel.visible
	_update_menu_buttons()

func _on_close_button_pressed() -> void:
	if debug_panel:
		debug_panel.visible = false
	_update_menu_buttons()

func _on_ucs_close_pressed() -> void:
	if ucs_panel:
		ucs_panel.visible = false
	_update_menu_buttons()

func _on_open_button_pressed() -> void:
	_on_astar_open_pressed()

func _update_menu_buttons() -> void:
	if astar_open_button:
		if debug_panel and debug_panel.visible:
			astar_open_button.modulate = Color(0.65, 1.0, 0.65)
		else:
			astar_open_button.modulate = Color.WHITE
	if ucs_open_button:
		if ucs_panel and ucs_panel.visible:
			ucs_open_button.modulate = Color(0.5, 0.9, 1.0)
		else:
			ucs_open_button.modulate = Color.WHITE

# =========================================
# A* CONTROLS & LOGIC
# =========================================
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
		path_debug_button.text = "A* DEBUG: ON"
		path_debug_button.modulate = Color(0.65, 1.0, 0.65)
	else:
		path_debug_button.text = "A* DEBUG: OFF"
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

	var safe_step: int = clamp(current_step, 0, debug_steps.size() - 1)
	var snapshot: Dictionary = debug_steps[safe_step]
	var open_nodes: Array = snapshot.get("open", [])
	var closed_nodes: Array = snapshot.get("closed", [])

	step_label.text = "Step: %d / %d" % [safe_step + 1, debug_steps.size()]
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

func play_animation(steps: Array, path: Array[Vector2i]) -> bool:
	if not is_path_debug_enabled:
		debug_steps.clear()
		final_path.clear()
		queue_redraw()
		return true

	# Auto-open A* panel if closed
	if debug_panel != null and not debug_panel.visible:
		debug_panel.visible = true
		_update_menu_buttons()

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

		var delay: float = 0.5 - speed_slider.value if speed_slider != null else 0.2
		await get_tree().create_timer(max(0.01, delay)).timeout

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

	if play_button != null:
		play_button.text = "PLAY"
	if status_label != null:
		status_label.text = "READY"

	_update_debugger_ui()
	queue_redraw()

# =========================================
# UCS CONTROLS & LOGIC (NPC)
# =========================================
func _on_toggle_ucs_debug_pressed() -> void:
	is_ucs_debug_enabled = not is_ucs_debug_enabled
	_update_ucs_debug_button()
	if not is_ucs_debug_enabled:
		reset_ucs_animation()
		if ucs_status_label != null:
			ucs_status_label.text = "DEBUG OFF"
	else:
		if ucs_status_label != null:
			ucs_status_label.text = "READY"

func _update_ucs_debug_button() -> void:
	if ucs_debug_button == null:
		return
	if is_ucs_debug_enabled:
		ucs_debug_button.text = "UCS DEBUG: ON"
		ucs_debug_button.modulate = Color(0.65, 1.0, 0.65)
	else:
		ucs_debug_button.text = "UCS DEBUG: OFF"
		ucs_debug_button.modulate = Color(1.0, 0.65, 0.65)

func _update_ucs_debugger_ui() -> void:
	if ucs_step_label == null:
		return

	if ucs_debug_steps.is_empty():
		ucs_step_label.text = "Step: 0 / 0"
		ucs_expanded_label.text = "Expanded: 0"
		ucs_open_label.text = "Open: 0"
		ucs_closed_label.text = "Closed: 0"
		return

	var safe_step: int = clamp(ucs_current_step, 0, ucs_debug_steps.size() - 1)
	var snapshot: Dictionary = ucs_debug_steps[safe_step]
	var open_nodes: Array = snapshot.get("open", [])
	var closed_nodes: Array = snapshot.get("closed", [])

	ucs_step_label.text = "Step: %d / %d" % [safe_step + 1, ucs_debug_steps.size()]
	ucs_expanded_label.text = "Expanded: %d" % closed_nodes.size()
	ucs_open_label.text = "Open: %d" % open_nodes.size()
	ucs_closed_label.text = "Closed: %d" % closed_nodes.size()

func _on_ucs_play_pressed() -> void:
	if ucs_debug_steps.is_empty():
		return

	if ucs_is_animating:
		ucs_is_paused = not ucs_is_paused
		if ucs_is_paused:
			ucs_play_button.text = "PLAY"
			ucs_status_label.text = "PAUSED"
		else:
			ucs_play_button.text = "PAUSE"
			ucs_status_label.text = "PLAYING"
	else:
		ucs_is_paused = false
		ucs_is_animating = true
		ucs_play_button.text = "PAUSE"
		ucs_status_label.text = "PLAYING"

	_update_ucs_debugger_ui()

func _on_ucs_step_pressed() -> void:
	ucs_is_paused = true
	if ucs_status_label != null:
		ucs_status_label.text = "STEPPING"
	_step_ucs_once()

func _on_ucs_reset_pressed() -> void:
	reset_ucs_animation()

func _step_ucs_once() -> void:
	if ucs_debug_steps.is_empty():
		return
	if ucs_current_step >= ucs_debug_steps.size() - 1:
		return

	ucs_current_step += 1
	queue_redraw()
	_update_ucs_debugger_ui()

func play_ucs_animation(steps: Array, path: Array[Vector2i], npc_name: String = "NPC") -> bool:
	if not is_ucs_debug_enabled:
		ucs_debug_steps.clear()
		ucs_final_path.clear()
		queue_redraw()
		return true

	# Auto-open UCS panel if closed
	if ucs_panel != null and not ucs_panel.visible:
		ucs_panel.visible = true
		_update_menu_buttons()

	# If another NPC is already being animated, let this NPC proceed without conflicting
	if ucs_is_animating:
		return true

	ucs_animation_id += 1
	var my_animation_id: int = ucs_animation_id

	ucs_debug_steps = steps
	ucs_final_path = path
	ucs_active_npc_name = npc_name

	ucs_current_step = -1
	ucs_is_animating = true
	ucs_is_paused = false
	ucs_animation_finished = false

	if ucs_play_button != null:
		ucs_play_button.text = "PAUSE"
	if ucs_status_label != null:
		ucs_status_label.text = "PLAYING"
	if ucs_npc_label != null:
		ucs_npc_label.text = "NPC: " + npc_name

	_update_ucs_debugger_ui()
	queue_redraw()

	while ucs_current_step < ucs_debug_steps.size() - 1:
		if not is_ucs_debug_enabled:
			return true

		if my_animation_id != ucs_animation_id:
			return false

		if ucs_is_paused:
			await get_tree().process_frame
			continue

		ucs_current_step += 1
		_update_ucs_debugger_ui()
		queue_redraw()

		var delay: float = 0.5 - ucs_speed_slider.value if ucs_speed_slider != null else 0.2
		await get_tree().create_timer(max(0.01, delay)).timeout

	if not is_ucs_debug_enabled:
		return true

	if my_animation_id != ucs_animation_id:
		return false

	ucs_is_animating = false
	ucs_animation_finished = true
	ucs_is_paused = true

	if ucs_play_button != null:
		ucs_play_button.text = "PLAY"
	if ucs_status_label != null:
		ucs_status_label.text = "FINISHED"

	_update_ucs_debugger_ui()
	queue_redraw()

	return true

func reset_ucs_animation() -> void:
	ucs_animation_id += 1
	ucs_debug_steps.clear()
	ucs_final_path.clear()

	ucs_current_step = -1
	ucs_is_animating = false
	ucs_is_paused = true
	ucs_animation_finished = false
	ucs_active_npc_name = ""

	if ucs_play_button != null:
		ucs_play_button.text = "PLAY"
	if ucs_status_label != null:
		ucs_status_label.text = "READY"
	if ucs_npc_label != null:
		ucs_npc_label.text = "NPC: None"

	_update_ucs_debugger_ui()
	queue_redraw()

# =========================================
# DRAWING HELPERS
# =========================================
func _get_tile_center(cell: Vector2i) -> Vector2:
	var local_pos: Vector2 = path_map_layer.map_to_local(cell)
	var global_pos: Vector2 = path_map_layer.to_global(local_pos)
	return to_local(global_pos)

func _get_tile_size() -> Vector2:
	if path_map_layer and path_map_layer.tile_set:
		var tile_size: Vector2i = path_map_layer.tile_set.tile_size
		return Vector2(tile_size.x, tile_size.y)
	return Vector2(64, 64)

func _draw() -> void:
	if path_map_layer == null:
		return

	var tile_size := _get_tile_size()

	# =========================================
	# DRAW A* PATH DEBUG (PLAYER)
	# =========================================
	if is_path_debug_enabled and current_step >= 0 and current_step < debug_steps.size():
		var snapshot: Dictionary = debug_steps[current_step]

		# Closed
		var closed_nodes: Array = snapshot.get("closed", [])
		for node_data in closed_nodes:
			var cell: Vector2i = node_data["position"]
			var center := _get_tile_center(cell)
			var rect := Rect2(center - tile_size / 2.0, tile_size)
			draw_rect(rect, closed_color, true)
			_draw_values(center, node_data["g"], node_data["h"], node_data["f"])

		# Open
		var open_nodes: Array = snapshot.get("open", [])
		for node_data in open_nodes:
			var cell: Vector2i = node_data["position"]
			var center := _get_tile_center(cell)
			var rect := Rect2(center - tile_size / 2.0, tile_size)
			draw_rect(rect, open_color, true)
			_draw_values(center, node_data["g"], node_data["h"], node_data["f"])

		# Current Node
		var current_node: Dictionary = snapshot.get("current", {})
		if not current_node.is_empty():
			var current_cell: Vector2i = current_node["position"]
			var current_center := _get_tile_center(current_cell)
			var current_rect := Rect2(current_center - tile_size / 2.0, tile_size)
			draw_rect(current_rect, current_color, true)
			draw_rect(current_rect, text_color, false, 2.0)
			_draw_values(current_center, current_node["g"], current_node["h"], current_node["f"])

		# Final Path (appears after animation finishes)
		if not is_animating and current_step == debug_steps.size() - 1:
			for i in range(final_path.size()):
				var cell: Vector2i = final_path[i]
				var center := _get_tile_center(cell)
				var rect := Rect2(center - tile_size / 2.0, tile_size)
				draw_rect(rect, path_color, false, 2.0)
				var draw_font: Font = font_bold if font_bold != null else (font_regular if font_regular != null else ThemeDB.fallback_font)
				draw_string(draw_font, center + Vector2(-2, 2), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, path_color)

	# =========================================
	# DRAW UCS PATH DEBUG (NPC)
	# =========================================
	if is_ucs_debug_enabled and ucs_current_step >= 0 and ucs_current_step < ucs_debug_steps.size():
		var u_snapshot: Dictionary = ucs_debug_steps[ucs_current_step]

		# Closed
		var u_closed: Array = u_snapshot.get("closed", [])
		for node_data in u_closed:
			var cell: Vector2i = node_data["position"]
			var center := _get_tile_center(cell)
			var rect := Rect2(center - tile_size / 2.0, tile_size)
			draw_rect(rect, ucs_closed_color, true)
			_draw_values(center, node_data["g"], node_data["h"], node_data["f"])

		# Open
		var u_open: Array = u_snapshot.get("open", [])
		for node_data in u_open:
			var cell: Vector2i = node_data["position"]
			var center := _get_tile_center(cell)
			var rect := Rect2(center - tile_size / 2.0, tile_size)
			draw_rect(rect, ucs_open_color, true)
			_draw_values(center, node_data["g"], node_data["h"], node_data["f"])

		# Current Node
		var u_current: Dictionary = u_snapshot.get("current", {})
		if not u_current.is_empty():
			var current_cell: Vector2i = u_current["position"]
			var current_center := _get_tile_center(current_cell)
			var current_rect := Rect2(current_center - tile_size / 2.0, tile_size)
			draw_rect(current_rect, ucs_current_color, true)
			draw_rect(current_rect, Color(1.0, 0.95, 0.5), false, 2.0)
			_draw_values(current_center, u_current["g"], u_current["h"], u_current["f"])

		# Final Path (appears after animation finishes)
		if not ucs_is_animating and ucs_current_step == ucs_debug_steps.size() - 1:
			for i in range(ucs_final_path.size()):
				var cell: Vector2i = ucs_final_path[i]
				var center := _get_tile_center(cell)
				var rect := Rect2(center - tile_size / 2.0, tile_size)
				draw_rect(rect, ucs_path_color, false, 2.5)
				var draw_font: Font = font_bold if font_bold != null else (font_regular if font_regular != null else ThemeDB.fallback_font)
				draw_string(draw_font, center + Vector2(-2, 2), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ucs_path_color)

func _draw_values(center: Vector2, g: float, h: float, f: float) -> void:
	var font: Font = font_regular if font_regular != null else ThemeDB.fallback_font
	var tile_size := _get_tile_size()

	var left_x: float = center.x - tile_size.x / 2.0 + 1.0
	var top_y: float = center.y - tile_size.y / 2.0 + 8.0

	draw_string(font, Vector2(left_x, top_y), "G:" + str(int(g)), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_string(font, Vector2(left_x, top_y + 12.0), "H:" + str(int(h)), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_string(font, Vector2(left_x, top_y + 24.0), "F:" + str(int(f)), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
