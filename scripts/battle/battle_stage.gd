extends Node2D

@export_group("Player Avatar")
@export_enum("Pawn", "Archer") var active_player: String = "Pawn":
	set(val):
		active_player = val
		if is_node_ready():
			_setup_player_avatar()

@export_group("Background Scroll")
@export var scroll_speed: float = 60.0
@export var scroll_direction: Vector2 = Vector2.LEFT

@export_group("Camera Intro")
@export var camera_start_y: float = 300.0
@export var camera_tween_duration: float = 3.0

@export_group("Camera Idle & Shake")
@export var enable_idle_motion: bool = true
@export var idle_sway_amount: float = 12.0
@export var idle_sway_speed: float = 1.2
@export var idle_rotation_amount: float = 0.015
@export var micro_shake_amount: float = 1.6

@export_group("Camera Mouse Parallax")
@export var enable_mouse_follow: bool = true
@export var mouse_max_offset: float = 24.0
@export var mouse_max_rotation: float = 0.012
@export var camera_smoothing: float = 4.0

# ══════════════════════════════════════════════════════════════════════
#  BATTLE SCRIPTS (STATE & AI)
# ══════════════════════════════════════════════════════════════════════
const StateScript = preload("res://scripts/battle/battle_state.gd")
const AIScript = preload("res://scripts/battle/battle_ai.gd")

var state: StateScript
var ai: AIScript

# Config AI
var current_algo: int = AIScript.Algorithm.ALPHABETA
var current_depth: int = 4
var current_eval: int = AIScript.EvalType.BALANCED
var current_ordering: int = AIScript.MoveOrdering.OPTIMAL

var is_processing_turn: bool = false

# ══════════════════════════════════════════════════════════════════════
#  NODE REFERENCES
# ══════════════════════════════════════════════════════════════════════
var parallax_layers: Array[ParallaxLayer] = []
var camera: Camera2D
var _idle_time: float = 0.0
var sunrays_mat: ShaderMaterial

@onready var player_sprite: Sprite2D = get_node_or_null("NPCCharacter")
@onready var enemy_sprite: AnimatedSprite2D = get_node_or_null("EnemyCharacter")
@onready var ally_hud: CharacterHUD = get_node_or_null("AllyHUD")
@onready var enemy_hud: CharacterHUD = get_node_or_null("EnemyHUD")
@onready var action_buttons: Control = get_node_or_null("CanvasLayer/PlayerActionButtons")
@onready var canvas_layer: CanvasLayer = get_node_or_null("CanvasLayer")
@onready var bgm_player: AudioStreamPlayer = get_node_or_null("BattleBGM")

# Debug Overlay & Modals
var debug_panel: PanelContainer
var btn_toggle_debug: Button
var lbl_algo_display: Label
var slider_depth: HSlider
var lbl_depth_val: Label
var opt_eval_type: OptionButton
var opt_move_ordering: OptionButton
var lbl_nodes: Label
var lbl_pruned: Label
var lbl_time: Label
var candidates_container: VBoxContainer
var experiment_modal: PanelContainer
var experiment_text: RichTextLabel
var banner_label: Label
var game_over_modal: PanelContainer
var tree_viewer: MinimaxTreeViewer = null
var btn_top_tree: Button

var player_fighter_name: String = "BOCCHI"
var enemy_fighter_name: String = "SEVERED FANG"
var _player_orig_pos: Vector2 = Vector2.ZERO
var _enemy_orig_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_setup_camera()
	_setup_flipped_y_mirror()
	_gather_parallax_layers(self)
	_setup_followed_npc()
	_setup_player_avatar()
	_setup_bgm()
	_setup_now_playing()
	_setup_sunrays()

	if player_sprite:
		_player_orig_pos = player_sprite.position
	if enemy_sprite:
		_enemy_orig_pos = enemy_sprite.position

	_init_battle_system()
	_setup_action_buttons()
	_setup_banner_label()
	_build_debug_overlay()

	tree_viewer = MinimaxTreeViewer.new()
	if canvas_layer:
		canvas_layer.add_child(tree_viewer)
	else:
		add_child(tree_viewer)

	_update_huds(false)
	_update_action_buttons_state()

	_show_banner("DUEL START! GILIRAN %s" % player_fighter_name.to_upper(), Color(0.3, 0.9, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 or event.keycode == KEY_D:
			toggle_debug_panel()
		elif event.keycode == KEY_F4 or event.keycode == KEY_T:
			toggle_tree_visualizer()


# ══════════════════════════════════════════════════════════════════════
#  CAMERA & PARALLAX BACKGROUND
# ══════════════════════════════════════════════════════════════════════

func _setup_camera() -> void:
	camera = get_node_or_null("Camera2D")
	if camera:
		camera.position.y = camera_start_y
		var tw = create_tween()
		tw.tween_property(camera, "position:y", 0.0, camera_tween_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _setup_flipped_y_mirror() -> void:
	# Add vertically flipped mirror on the top (ceiling) for moving parallax layers
	for child in get_children():
		if child is ParallaxBackground:
			for pl in child.get_children():
				if pl is ParallaxLayer:
					for sp in pl.get_children():
						if sp is Sprite2D:
							sp.centered = false
			# Skip static background, lighting and mist
			if child.name in ["ParallaxBackground10", "ParallaxBackground9", "ParallaxBackground6"]:
				continue
			for pl in child.get_children():
				if pl is ParallaxLayer:
					var sp: Sprite2D = pl.get_node_or_null("Sprite2D")
					if sp and sp.texture:
						var tex_h: float = sp.texture.get_height()
						var top_sp: Sprite2D = sp.duplicate()
						top_sp.name = "Sprite2D_FlippedTop"
						top_sp.flip_v = true
						top_sp.position = Vector2(0.0, -tex_h)
						pl.add_child(top_sp)


func _gather_parallax_layers(node: Node) -> void:
	if node is ParallaxLayer:
		parallax_layers.append(node)
	for child in node.get_children():
		_gather_parallax_layers(child)


func _process(delta: float) -> void:
	# 1. Background parallax auto-scroll (only horizontal)
	for layer in parallax_layers:
		if layer.motion_scale.x == 0.0:
			continue
		layer.motion_offset.x += scroll_direction.x * scroll_speed * layer.motion_scale.x * delta
		if layer.motion_mirroring.x > 0:
			layer.motion_offset.x = wrapf(layer.motion_offset.x, 0.0, layer.motion_mirroring.x)

	# 2. Camera idle sway, shake & mouse follow
	if camera:
		var target_offset: Vector2 = Vector2.ZERO
		var target_rot: float = 0.0

		if enable_idle_motion:
			_idle_time += delta * idle_sway_speed
			var sway_x: float = sin(_idle_time) * idle_sway_amount
			var sway_y: float = cos(_idle_time * 0.85) * (idle_sway_amount * 0.7)
			var micro_shake: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * micro_shake_amount
			target_offset += Vector2(sway_x, sway_y) + micro_shake
			target_rot += sin(_idle_time * 0.7) * idle_rotation_amount

		if enable_mouse_follow:
			var vp: Viewport = get_viewport()
			if vp:
				var vp_size: Vector2 = vp.get_visible_rect().size
				if vp_size.x > 0.0 and vp_size.y > 0.0:
					var mouse_pos: Vector2 = vp.get_mouse_position()
					var norm_mouse: Vector2 = Vector2(
						clampf((mouse_pos.x - vp_size.x * 0.5) / (vp_size.x * 0.5), -1.0, 1.0),
						clampf((mouse_pos.y - vp_size.y * 0.5) / (vp_size.y * 0.5), -1.0, 1.0)
					)
					target_offset += norm_mouse * mouse_max_offset
					target_rot += norm_mouse.x * mouse_max_rotation

		camera.offset = camera.offset.lerp(target_offset, camera_smoothing * delta)
		camera.rotation = lerpf(camera.rotation, target_rot, camera_smoothing * delta)

	# 3. Update Volumetric Sunrays light origin tracking camera movement
	if sunrays_mat and camera:
		var vp_rect = get_viewport_rect()
		if vp_rect.size.x > 0.0 and vp_rect.size.y > 0.0:
			var world_light_origin = Vector2(920.0, 35.0)
			var screen_light_pos = (camera.get_canvas_transform() * world_light_origin) / vp_rect.size
			sunrays_mat.set_shader_parameter("light_pos", screen_light_pos)


func _setup_sunrays() -> void:
	var s_rect = get_node_or_null("SunraysCanvas/SunraysRect")
	if s_rect and s_rect.material is ShaderMaterial:
		sunrays_mat = s_rect.material


# ══════════════════════════════════════════════════════════════════════
#  CHARACTER VISUALS & AVATAR
# ══════════════════════════════════════════════════════════════════════

func _setup_followed_npc() -> void:
	if not player_sprite:
		return

	var char_image_path: String = ""

	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var p_fighter: Dictionary = {}
		if bm.has_method("get_battle_data"):
			p_fighter = bm.get_battle_data().get("player", {})
		elif bm.get("_player_fighter") is Dictionary:
			p_fighter = bm.get("_player_fighter")

		if p_fighter and p_fighter.has("image") and p_fighter["image"] != "":
			char_image_path = p_fighter["image"]

	if char_image_path != "" and ResourceLoader.exists(char_image_path):
		var tex = load(char_image_path)
		if tex is Texture2D:
			player_sprite.texture = tex
			player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var tex_h: float = float(tex.get_height())
			var target_h: float = 150.0
			var s: float = target_h / tex_h if tex_h > 0.0 else 3.56
			player_sprite.scale = Vector2(s, s)


func _clean_npc_name(raw_name: String) -> String:
	var clean = raw_name.strip_edges()
	if clean.contains("&"):
		var parts = clean.split("&")
		clean = parts[parts.size() - 1].strip_edges()
	for prefix in ["Pawn /", "Archer /", "Avatar /", "Player /", "Pawn -", "Archer -", "Avatar -", "Pawn", "Archer", "Avatar"]:
		if clean.begins_with(prefix + " "):
			clean = clean.substr(prefix.length() + 1).strip_edges()
	if clean.is_empty():
		clean = "BOCCHI"
	return clean


func _setup_player_avatar() -> void:
	var avatar_rect: TextureRect = get_node_or_null("CanvasLayer/PlayerAvatarUI/AvatarRect")
	if not avatar_rect:
		avatar_rect = find_child("AvatarRect", true, false)
	if not avatar_rect:
		return

	var is_archer: bool = active_player.to_lower() == "archer"
	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var p_data: Dictionary = {}
		if bm.has_method("get_battle_data"):
			p_data = bm.get_battle_data().get("player", {})
		elif bm.get("_player_fighter") is Dictionary:
			p_data = bm.get("_player_fighter")
		var leader: String = str(p_data.get("leader", ""))
		var role: String = str(p_data.get("role", ""))
		var p_id: String = str(p_data.get("id", ""))
		var avatar_override: String = str(p_data.get("avatar", ""))
		if avatar_override.contains("archer"):
			is_archer = true
		elif leader.to_lower().contains("archer") or role.to_lower().contains("archer") or p_id.to_lower().contains("archer"):
			is_archer = true
		elif leader.to_lower().contains("pawn") or role.to_lower().contains("pawn") or p_id.to_lower().contains("pawn"):
			is_archer = false

	var avatar_path = "res://ui/avatar_archer.png" if is_archer else "res://ui/avatar_pawn.png"
	if ResourceLoader.exists(avatar_path):
		var tex = load(avatar_path)
		if tex is Texture2D:
			avatar_rect.texture = tex


func _setup_bgm() -> void:
	if bgm_player:
		if bgm_player.stream and bgm_player.stream is AudioStreamMP3:
			bgm_player.stream.loop = true
		if not bgm_player.playing:
			bgm_player.play()
		if not bgm_player.finished.is_connected(bgm_player.play):
			bgm_player.finished.connect(bgm_player.play)


func _setup_now_playing() -> void:
	var np_ui: Control = get_node_or_null("CanvasLayer/NowPlayingUI")
	if not np_ui:
		return
	np_ui.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(np_ui, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.5)
	tw.tween_property(np_ui, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): np_ui.visible = false)


# ══════════════════════════════════════════════════════════════════════
#  BATTLE SYSTEM & STATE INITIALIZATION
# ══════════════════════════════════════════════════════════════════════

func _init_battle_system() -> void:
	var p_name: String = "BOCCHI"
	var e_name: String = "SEVERED FANG"

	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var b_data: Dictionary = {}
		if bm.has_method("get_battle_data"):
			b_data = bm.get_battle_data()
		var p_fighter: Dictionary = b_data.get("player", {})
		var e_fighter: Dictionary = b_data.get("enemy", {})
		if not p_fighter.is_empty():
			p_name = _clean_npc_name(p_fighter.get("name", "BOCCHI"))
		if not e_fighter.is_empty():
			e_name = e_fighter.get("name", "SEVERED FANG")

	player_fighter_name = p_name
	enemy_fighter_name = e_name

	# Stats seragam sama persis seperti Temp_Battle: 100 HP & 100 Stamina untuk Player & Enemy
	state = StateScript.new(100, 100)
	state.player["name"] = player_fighter_name
	state.enemy["name"] = enemy_fighter_name

	ai = AIScript.new()

	var l_type := get_active_leader_type()
	if l_type == "Archer":
		current_algo = AIScript.Algorithm.ALPHABETA
	else:
		current_algo = AIScript.Algorithm.MINIMAX
	_update_algo_display_text()

	if ally_hud:
		ally_hud.set_character_name(player_fighter_name)
	if enemy_hud:
		enemy_hud.set_character_name(enemy_fighter_name)


func _setup_action_buttons() -> void:
	if not action_buttons:
		return

	if action_buttons.has_signal("action_chosen"):
		if not action_buttons.action_chosen.is_connected(_on_action_chosen):
			action_buttons.action_chosen.connect(_on_action_chosen)
	else:
		if action_buttons.has_signal("attack_pressed"):
			action_buttons.attack_pressed.connect(func(): _on_player_action(StateScript.Action.ATTACK))
		if action_buttons.has_signal("special_pressed"):
			action_buttons.special_pressed.connect(func(): _on_player_action(StateScript.Action.HEAVY_ATTACK))
		if action_buttons.has_signal("defense_pressed"):
			action_buttons.defense_pressed.connect(func(): _on_player_action(StateScript.Action.DEFEND))
		if action_buttons.has_signal("item_pressed"):
			action_buttons.item_pressed.connect(func(): _on_player_action(StateScript.Action.REST))


func _setup_banner_label() -> void:
	if not canvas_layer:
		return
	banner_label = Label.new()
	banner_label.set_anchors_preset(Control.PRESET_CENTER)
	banner_label.custom_minimum_size = Vector2(700, 60)
	banner_label.offset_left = -350.0
	banner_label.offset_top = -140.0
	banner_label.offset_right = 350.0
	banner_label.offset_bottom = -80.0
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 28)
	banner_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 0.95))
	banner_label.add_theme_constant_override("outline_size", 6)
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		banner_label.add_theme_font_override("font", load("res://fonts/PixelifySans-Bold.ttf"))
	banner_label.modulate.a = 0.0
	banner_label.visible = false
	canvas_layer.add_child(banner_label)


# ══════════════════════════════════════════════════════════════════════
#  ACTION SELECTION & TURN LOOP
# ══════════════════════════════════════════════════════════════════════

func _on_action_chosen(action_name: String) -> void:
	match action_name:
		"attack":
			_on_player_action(StateScript.Action.ATTACK)
		"special":
			_on_player_action(StateScript.Action.HEAVY_ATTACK)
		"defense":
			_on_player_action(StateScript.Action.DEFEND)
		"item":
			_on_player_action(StateScript.Action.REST)


func _on_player_action(action: int) -> void:
	if is_processing_turn or state.is_terminal():
		return
	if state.current_turn != StateScript.Side.PLAYER:
		return

	var valid_actions = state.get_valid_actions()
	if not valid_actions.has(action):
		if state.player.get("is_guard_broken", false):
			_show_banner("GUARD BROKEN! Harus REST / Gunakan Item!", Color(1.0, 0.3, 0.3))
		else:
			_show_banner("Stamina Tidak Cukup!", Color(1.0, 0.4, 0.4))
		return

	is_processing_turn = true
	_update_action_buttons_state()

	# 1. Visual player action
	_play_action_visual(true, action)

	# 2. Apply action to state
	var is_stochastic: bool = (current_algo == AIScript.Algorithm.EXPECTIMAX)
	var log_data := state.apply_action(action, is_stochastic)

	# 3. Update HUDs & Floating feedback
	_show_combat_feedback(true, log_data)
	_update_huds(true)
	_update_action_buttons_state()

	# 4. Check if terminal
	if state.is_terminal():
		_handle_game_over(state.get_winner() == StateScript.Side.PLAYER)
		return

	# 5. Delay to let player visual settle before AI turn
	if tree_viewer and tree_viewer.visible:
		open_tree_visualizer()
	await get_tree().create_timer(0.65).timeout
	_execute_npc_turn()


func _execute_npc_turn() -> void:
	if state.is_terminal():
		is_processing_turn = false
		return

	# AI Decision
	var decision := ai.decide_action(
		state,
		current_depth,
		current_algo,
		current_eval,
		current_ordering,
		StateScript.Side.ENEMY
	)

	_update_debug_overlay(decision)

	var chosen_action: int = decision.get("action", StateScript.Action.ATTACK)
	if chosen_action < 0:
		chosen_action = StateScript.Action.REST

	# Visual enemy action
	_play_action_visual(false, chosen_action)

	var is_stochastic: bool = (current_algo == AIScript.Algorithm.EXPECTIMAX)
	var log_data := state.apply_action(chosen_action, is_stochastic)

	_show_combat_feedback(false, log_data)
	_update_huds(true)

	if state.is_terminal():
		_handle_game_over(state.get_winner() == StateScript.Side.PLAYER)
		return

	# Delay to let enemy visual settle
	await get_tree().create_timer(0.5).timeout

	is_processing_turn = false
	_update_action_buttons_state()
	if tree_viewer and tree_viewer.visible:
		open_tree_visualizer()


# ══════════════════════════════════════════════════════════════════════
#  HUD & BUTTONS UPDATE
# ══════════════════════════════════════════════════════════════════════

func _update_huds(animated: bool = true) -> void:
	if ally_hud:
		ally_hud.set_hp(state.player["hp"], state.player["max_hp"], animated)
		ally_hud.set_stamina(state.player["stamina"], state.player["max_stamina"], animated)
	if enemy_hud:
		enemy_hud.set_hp(state.enemy["hp"], state.enemy["max_hp"], animated)
		enemy_hud.set_stamina(state.enemy["stamina"], state.enemy["max_stamina"], animated)


func _update_action_buttons_state() -> void:
	if not action_buttons:
		return

	var is_player_turn: bool = (state != null) and (state.current_turn == StateScript.Side.PLAYER) and not is_processing_turn and not state.is_terminal()
	var valid_actions: Array = []
	if is_player_turn and state != null:
		valid_actions = state.get_valid_actions()

	var btn_attack = action_buttons.get_node_or_null("AttackButton") as TextureButton
	var btn_special = action_buttons.get_node_or_null("SpecialButton") as TextureButton
	var btn_defense = action_buttons.get_node_or_null("DefenseButton") as TextureButton
	var btn_item = action_buttons.get_node_or_null("ItemButton") as TextureButton

	_set_btn_state(btn_attack, valid_actions.has(StateScript.Action.ATTACK))
	_set_btn_state(btn_special, valid_actions.has(StateScript.Action.HEAVY_ATTACK))
	_set_btn_state(btn_defense, valid_actions.has(StateScript.Action.DEFEND))
	_set_btn_state(btn_item, valid_actions.has(StateScript.Action.REST))


func _set_btn_state(btn: TextureButton, enabled: bool) -> void:
	if not btn:
		return
	btn.disabled = not enabled
	var tw = create_tween()
	var target_col = Color.WHITE if enabled else Color(0.45, 0.45, 0.45, 0.55)
	tw.tween_property(btn, "modulate", target_col, 0.15)


# ══════════════════════════════════════════════════════════════════════
#  VISUAL EFFECTS & FLOATING COMBAT TEXT
# ══════════════════════════════════════════════════════════════════════

func _play_action_visual(is_player: bool, action: int) -> void:
	var actor = player_sprite if is_player else enemy_sprite
	var target = enemy_sprite if is_player else player_sprite
	if not actor:
		return

	var orig_pos: Vector2 = actor.position
	var dir: Vector2 = Vector2.RIGHT if is_player else Vector2.LEFT

	match action:
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			var dist: float = 55.0 if action == StateScript.Action.ATTACK else 85.0
			var tw := create_tween()
			tw.tween_property(actor, "position", orig_pos + dir * dist, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func():
				_flash_hurt(target)
			)
			tw.tween_property(actor, "position", orig_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		StateScript.Action.DEFEND:
			var tw := create_tween()
			tw.tween_property(actor, "modulate", Color(0.4, 0.85, 2.2, 1.0), 0.15)
			tw.tween_property(actor, "modulate", Color.WHITE, 0.3)

		StateScript.Action.REST:
			var tw := create_tween()
			tw.tween_property(actor, "modulate", Color(0.4, 2.2, 0.8, 1.0), 0.15)
			tw.tween_property(actor, "modulate", Color.WHITE, 0.3)


func _flash_hurt(target: CanvasItem) -> void:
	if not target:
		return
	var tw := create_tween()
	tw.tween_property(target, "modulate", Color(3.0, 0.3, 0.3, 1.0), 0.08)
	tw.tween_property(target, "modulate", Color.WHITE, 0.18)

	var orig_p: Vector2 = target.position
	var tw2 := create_tween()
	tw2.tween_property(target, "position", orig_p + Vector2(randf_range(-8, 8), randf_range(-3, 3)), 0.04)
	tw2.tween_property(target, "position", orig_p, 0.06)


func _show_combat_feedback(is_player_attacker: bool, log_data: Dictionary) -> void:
	var target_pos: Vector2 = Vector2(860, 480)
	if is_player_attacker:
		if enemy_sprite:
			target_pos = enemy_sprite.position
	else:
		if player_sprite:
			target_pos = player_sprite.position

	var actor_pos: Vector2 = Vector2(420, 480)
	if is_player_attacker:
		if player_sprite:
			actor_pos = player_sprite.position
	else:
		if enemy_sprite:
			actor_pos = enemy_sprite.position

	match log_data.get("action", 0):
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			if log_data.get("blocked", false):
				_spawn_floating_text(target_pos, "BLOCKED! (-%d STM)" % log_data.get("stamina_damage", 30), Color(0.4, 0.85, 1.0))
				if log_data.get("guard_break", false):
					_spawn_floating_text(target_pos + Vector2(0, -32), "GUARD BROKEN!", Color(1.0, 0.25, 0.25))
					_show_banner("%s GUARD BROKEN!" % log_data.get("defender_name", "Target"), Color(1.0, 0.3, 0.3))
			else:
				var is_crit: bool = log_data.get("is_critical", false)
				var crit_txt = " CRIT!" if is_crit else ""
				var col = Color(1.0, 0.85, 0.2) if is_crit else Color(1.0, 0.35, 0.35)
				_spawn_floating_text(target_pos, "-%d HP%s" % [log_data.get("damage", 20), crit_txt], col)

		StateScript.Action.DEFEND:
			var stm_g: int = log_data.get("stamina_gain", 0)
			var txt = "GUARD UP! (+%d STM)" % stm_g if stm_g > 0 else "GUARD UP!"
			_spawn_floating_text(actor_pos, txt, Color(0.4, 0.9, 1.0))

		StateScript.Action.REST:
			var hp_g: int = log_data.get("hp_gain", 0)
			var txt = "+%d STM" % log_data.get("stamina_gain", 50)
			if hp_g > 0:
				txt += " • +%d HP" % hp_g
			_spawn_floating_text(actor_pos, txt, Color(0.3, 1.0, 0.4))


func _spawn_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 120
	label.position = world_pos + Vector2(-90, -110)
	label.custom_minimum_size = Vector2(180, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		label.add_theme_font_override("font", load("res://fonts/PixelifySans-Bold.ttf"))
	add_child(label)

	var tw = create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 40.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.12)
	tw.chain().tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)


func _show_banner(msg: String, color: Color = Color.WHITE) -> void:
	if not banner_label:
		return
	banner_label.text = msg
	banner_label.add_theme_color_override("font_color", color)
	banner_label.visible = true
	var tw = create_tween()
	tw.tween_property(banner_label, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): banner_label.visible = false)


# ══════════════════════════════════════════════════════════════════════
#  GAME OVER & RESET
# ══════════════════════════════════════════════════════════════════════

func _handle_game_over(is_player_win: bool) -> void:
	is_processing_turn = true
	_update_action_buttons_state()

	var winner_name: String = player_fighter_name if is_player_win else enemy_fighter_name
	var msg: String = "VICTORY! %s MENANG!" % winner_name.to_upper() if is_player_win else "DEFEAT! %s MENANG!" % winner_name.to_upper()
	var col: Color = Color(0.3, 1.0, 0.4) if is_player_win else Color(1.0, 0.3, 0.3)
	_show_banner(msg, col)

	if is_player_win and enemy_sprite:
		var tw = create_tween()
		tw.tween_property(enemy_sprite, "modulate:a", 0.0, 0.8)
	elif not is_player_win and player_sprite:
		var tw = create_tween()
		tw.tween_property(player_sprite, "modulate:a", 0.0, 0.8)

	_show_game_over_modal(is_player_win)


func _show_game_over_modal(is_player_win: bool) -> void:
	# Always free any previous modal to prevent stale UI state
	if is_instance_valid(game_over_modal):
		game_over_modal.queue_free()
		game_over_modal = null

	game_over_modal = PanelContainer.new()
	game_over_modal.set_anchors_preset(Control.PRESET_CENTER)
	game_over_modal.custom_minimum_size = Vector2(460, 310)
	game_over_modal.offset_left = -230.0
	game_over_modal.offset_top = -155.0
	game_over_modal.offset_right = 230.0
	game_over_modal.offset_bottom = 155.0
	game_over_modal.z_index = 200

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.97)
	var theme_color: Color = Color(0.25, 0.95, 0.5, 1.0) if is_player_win else Color(1.0, 0.35, 0.35, 1.0)
	style.border_color = theme_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	style.shadow_size = 16
	style.shadow_color = Color(0.1, 0.6, 0.3, 0.35) if is_player_win else Color(0.65, 0.15, 0.15, 0.35)
	game_over_modal.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	game_over_modal.add_child(vbox)

	# 1. Title
	var title := Label.new()
	title.text = "🏆 DUEL VICTORY!" if is_player_win else "💀 DEFEAT!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", theme_color)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		title.add_theme_font_override("font", load("res://fonts/PixelifySans-Bold.ttf"))
	vbox.add_child(title)

	# 2. Subtitle: Winner narrative
	var winner_name: String = player_fighter_name if is_player_win else enemy_fighter_name
	var loser_name: String = enemy_fighter_name if is_player_win else player_fighter_name
	var subtitle := Label.new()
	if is_player_win:
		subtitle.text = "%s berhasil mengalahkan %s!" % [winner_name, loser_name]
	else:
		subtitle.text = "%s dikalahkan oleh %s!" % [loser_name, winner_name]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.9, 0.96))
	if ResourceLoader.exists("res://fonts/PixelifySans-Medium.ttf"):
		subtitle.add_theme_font_override("font", load("res://fonts/PixelifySans-Medium.ttf"))
	vbox.add_child(subtitle)

	# 3. Combat Stats Summary Card
	var summary_card := PanelContainer.new()
	var sum_style := StyleBoxFlat.new()
	sum_style.bg_color = Color(0.04, 0.06, 0.10, 0.85)
	sum_style.set_corner_radius_all(8)
	sum_style.set_content_margin_all(10)
	sum_style.border_color = Color(0.2, 0.25, 0.35, 0.6)
	sum_style.set_border_width_all(1)
	summary_card.add_theme_stylebox_override("panel", sum_style)
	vbox.add_child(summary_card)

	var sum_vbox := VBoxContainer.new()
	sum_vbox.add_theme_constant_override("separation", 6)
	summary_card.add_child(sum_vbox)

	var turns_lbl := Label.new()
	var total_turns: int = state.turn_count if state else 1
	turns_lbl.text = "⏱️ Total Giliran: %d" % total_turns
	turns_lbl.add_theme_font_size_override("font_size", 13)
	turns_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	sum_vbox.add_child(turns_lbl)

	var p_hp: int = max(0, state.player.get("hp", 0)) if state else 0
	var p_max_hp: int = state.player.get("max_hp", 100) if state else 100
	var p_stm: int = max(0, state.player.get("stamina", 0)) if state else 0
	var p_max_stm: int = state.player.get("max_stamina", 100) if state else 100

	var p_stats_lbl := Label.new()
	p_stats_lbl.text = "🛡️ %s: %d/%d HP • %d/%d Stamina" % [player_fighter_name, p_hp, p_max_hp, p_stm, p_max_stm]
	p_stats_lbl.add_theme_font_size_override("font_size", 13)
	p_stats_lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	sum_vbox.add_child(p_stats_lbl)

	var e_hp: int = max(0, state.enemy.get("hp", 0)) if state else 0
	var e_max_hp: int = state.enemy.get("max_hp", 100) if state else 100
	var e_stm: int = max(0, state.enemy.get("stamina", 0)) if state else 0
	var e_max_stm: int = state.enemy.get("max_stamina", 100) if state else 100

	var e_stats_lbl := Label.new()
	e_stats_lbl.text = "⚔️ %s: %d/%d HP • %d/%d Stamina" % [enemy_fighter_name, e_hp, e_max_hp, e_stm, e_max_stm]
	e_stats_lbl.add_theme_font_size_override("font_size", 13)
	e_stats_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	sum_vbox.add_child(e_stats_lbl)

	# 4. Action Buttons
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)

	var rematch_btn := Button.new()
	rematch_btn.text = "🔄 Rematch"
	rematch_btn.custom_minimum_size = Vector2(130, 38)
	var rb_style := StyleBoxFlat.new()
	rb_style.bg_color = Color(0.12, 0.42, 0.68, 1.0)
	rb_style.border_color = Color(0.35, 0.75, 1.0, 1.0)
	rb_style.set_border_width_all(1)
	rb_style.set_corner_radius_all(8)
	rematch_btn.add_theme_stylebox_override("normal", rb_style)
	var rb_hover := rb_style.duplicate()
	rb_hover.bg_color = Color(0.18, 0.54, 0.85, 1.0)
	rematch_btn.add_theme_stylebox_override("hover", rb_hover)
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		rematch_btn.add_theme_font_override("font", load("res://fonts/PixelifySans-Bold.ttf"))
	rematch_btn.pressed.connect(_reset_battle)
	btn_box.add_child(rematch_btn)

	var lobby_btn := Button.new()
	lobby_btn.text = "🏠 Overworld"
	lobby_btn.custom_minimum_size = Vector2(140, 38)
	var lb_style := StyleBoxFlat.new()
	lb_style.bg_color = Color(0.16, 0.20, 0.28, 1.0)
	lb_style.border_color = Color(0.4, 0.48, 0.62, 1.0)
	lb_style.set_border_width_all(1)
	lb_style.set_corner_radius_all(8)
	lobby_btn.add_theme_stylebox_override("normal", lb_style)
	var lb_hover := lb_style.duplicate()
	lb_hover.bg_color = Color(0.24, 0.30, 0.40, 1.0)
	lobby_btn.add_theme_stylebox_override("hover", lb_hover)
	if ResourceLoader.exists("res://fonts/PixelifySans-Bold.ttf"):
		lobby_btn.add_theme_font_override("font", load("res://fonts/PixelifySans-Bold.ttf"))
	lobby_btn.pressed.connect(_return_to_overworld)
	btn_box.add_child(lobby_btn)

	# Smooth entrance animation
	game_over_modal.modulate.a = 0.0
	if canvas_layer:
		canvas_layer.add_child(game_over_modal)
	else:
		add_child(game_over_modal)

	var tw = create_tween()
	tw.tween_property(game_over_modal, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _reset_battle() -> void:
	if is_instance_valid(game_over_modal):
		game_over_modal.queue_free()
		game_over_modal = null

	if player_sprite:
		if _player_orig_pos != Vector2.ZERO:
			player_sprite.position = _player_orig_pos
		player_sprite.modulate.a = 1.0
	if enemy_sprite:
		if _enemy_orig_pos != Vector2.ZERO:
			enemy_sprite.position = _enemy_orig_pos
		enemy_sprite.modulate.a = 1.0

	var p_hp: int = 100
	var e_hp: int = 100
	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var b_data: Dictionary = bm.get_battle_data() if bm.has_method("get_battle_data") else {}
		var p_fighter: Dictionary = b_data.get("player", {})
		var e_fighter: Dictionary = b_data.get("enemy", {})
		if not p_fighter.is_empty():
			player_fighter_name = _clean_npc_name(p_fighter.get("name", player_fighter_name))
			p_hp = p_fighter.get("hp", 100)
		if not e_fighter.is_empty():
			enemy_fighter_name = e_fighter.get("name", enemy_fighter_name)
			e_hp = e_fighter.get("hp", 100)

	state.reset(p_hp, e_hp)
	state.player["name"] = player_fighter_name
	state.enemy["name"] = enemy_fighter_name

	var l_type := get_active_leader_type()
	if l_type == "Archer":
		current_algo = AIScript.Algorithm.ALPHABETA
	else:
		current_algo = AIScript.Algorithm.MINIMAX
	_update_algo_display_text()

	if ally_hud:
		ally_hud.set_character_name(player_fighter_name)
	if enemy_hud:
		enemy_hud.set_character_name(enemy_fighter_name)

	is_processing_turn = false
	_update_huds(false)
	_update_action_buttons_state()
	_show_banner("DUEL DIRESET! GILIRAN %s" % player_fighter_name.to_upper(), Color(0.9, 0.85, 0.3))


func _return_to_overworld(_arg = null) -> void:
	if is_instance_valid(game_over_modal):
		game_over_modal.queue_free()
		game_over_modal = null

	var return_scene := "res://Overworld.tscn"
	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		if bm.get("_return_scene") and str(bm.get("_return_scene")) != "":
			return_scene = str(bm.get("_return_scene"))
		bm.end_battle({
			"winner": "player" if (state and state.get_winner() == StateScript.Side.PLAYER) else "enemy",
			"turns": state.turn_count if state else 0
		}, false)

	if not ResourceLoader.exists(return_scene):
		if ResourceLoader.exists("res://Overworld.tscn"):
			return_scene = "res://Overworld.tscn"

	var tree: SceneTree = get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree

	if tree:
		tree.change_scene_to_file(return_scene)
	else:
		push_error("[BattleStage] Fatal: Could not resolve SceneTree to return to overworld!")


# ══════════════════════════════════════════════════════════════════════
#  DEBUG OVERLAY & EXPERIMENT MODAL
# ══════════════════════════════════════════════════════════════════════

func toggle_debug_panel() -> void:
	if debug_panel:
		debug_panel.visible = not debug_panel.visible
		if btn_toggle_debug:
			btn_toggle_debug.text = "📊 Debug [%s]" % ("ON" if debug_panel.visible else "OFF")


func _build_debug_overlay() -> void:
	if not canvas_layer:
		return

	# Top Right Toggle Button
	btn_toggle_debug = Button.new()
	btn_toggle_debug.text = "📊 Debug AI [F3]"
	btn_toggle_debug.position = Vector2(1130, 20)
	btn_toggle_debug.custom_minimum_size = Vector2(120, 32)
	btn_toggle_debug.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.18, 0.85)
	sb.border_color = Color(0.3, 0.7, 0.9, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	btn_toggle_debug.add_theme_stylebox_override("normal", sb)
	btn_toggle_debug.pressed.connect(toggle_debug_panel)
	canvas_layer.add_child(btn_toggle_debug)

	# Top Right Tree Visualizer Button
	btn_top_tree = Button.new()
	btn_top_tree.text = "🌳 Tree AI [F4]"
	btn_top_tree.position = Vector2(980, 20)
	btn_top_tree.custom_minimum_size = Vector2(130, 32)
	btn_top_tree.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_top_tree.add_theme_stylebox_override("normal", sb)
	btn_top_tree.pressed.connect(toggle_tree_visualizer)
	canvas_layer.add_child(btn_top_tree)

	# Return to Lobby button at top-left
	var top_lobby_btn := Button.new()
	top_lobby_btn.text = "< Overworld"
	top_lobby_btn.position = Vector2(120, 24)
	top_lobby_btn.custom_minimum_size = Vector2(110, 30)
	top_lobby_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	top_lobby_btn.add_theme_stylebox_override("normal", sb)
	top_lobby_btn.pressed.connect(_return_to_overworld)
	canvas_layer.add_child(top_lobby_btn)

	# Debug Panel
	debug_panel = PanelContainer.new()
	debug_panel.visible = false
	debug_panel.position = Vector2(860, 56)
	debug_panel.size = Vector2(400, 640)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	p_style.border_color = Color(0.35, 0.45, 0.55, 0.9)
	p_style.set_border_width_all(1)
	p_style.set_corner_radius_all(8)
	p_style.set_content_margin_all(12)
	debug_panel.add_theme_stylebox_override("panel", p_style)
	canvas_layer.add_child(debug_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	debug_panel.add_child(vbox)

	var d_title := Label.new()
	d_title.text = "📊 ADVERSARIAL SEARCH DEBUG"
	d_title.add_theme_font_size_override("font_size", 13)
	d_title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	vbox.add_child(d_title)

	vbox.add_child(HSeparator.new())

	var cfg_grid := GridContainer.new()
	cfg_grid.columns = 2
	cfg_grid.add_theme_constant_override("h_separation", 8)
	cfg_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(cfg_grid)

	# 1. Algorithm (Auto-assigned based on party leader)
	var lbl_algo := Label.new()
	lbl_algo.text = "Algoritma (Leader):"
	lbl_algo.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_algo)

	lbl_algo_display = Label.new()
	lbl_algo_display.add_theme_font_size_override("font_size", 11)
	_update_algo_display_text()
	cfg_grid.add_child(lbl_algo_display)

	# 2. Depth
	var lbl_d := Label.new()
	lbl_d.text = "Kedalaman (Depth):"
	lbl_d.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_d)

	var depth_hbox := HBoxContainer.new()
	slider_depth = HSlider.new()
	slider_depth.min_value = 1
	slider_depth.max_value = 6
	slider_depth.value = 4
	slider_depth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_depth.value_changed.connect(func(v):
		lbl_depth_val.text = "%d" % int(v)
		current_depth = int(v)
	)
	depth_hbox.add_child(slider_depth)

	lbl_depth_val = Label.new()
	lbl_depth_val.text = "4"
	lbl_depth_val.custom_minimum_size.x = 20
	lbl_depth_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	depth_hbox.add_child(lbl_depth_val)
	cfg_grid.add_child(depth_hbox)

	# 3. Evaluation Function
	var lbl_ev := Label.new()
	lbl_ev.text = "Fungsi Evaluasi:"
	lbl_ev.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_ev)

	opt_eval_type = OptionButton.new()
	opt_eval_type.add_item("Balanced", AIScript.EvalType.BALANCED)
	opt_eval_type.add_item("Aggressive", AIScript.EvalType.AGGRESSIVE)
	opt_eval_type.add_item("Defensive", AIScript.EvalType.DEFENSIVE)
	opt_eval_type.add_item("HP Ratio", AIScript.EvalType.HP_RATIO)
	opt_eval_type.selected = 0
	opt_eval_type.item_selected.connect(func(_idx): current_eval = opt_eval_type.get_item_id(_idx))
	cfg_grid.add_child(opt_eval_type)

	# 4. Move Ordering
	var lbl_ord := Label.new()
	lbl_ord.text = "Move Ordering:"
	lbl_ord.add_theme_font_size_override("font_size", 11)
	cfg_grid.add_child(lbl_ord)

	opt_move_ordering = OptionButton.new()
	opt_move_ordering.add_item("Optimal (Heuristic)", AIScript.MoveOrdering.OPTIMAL)
	opt_move_ordering.add_item("Default (No Sort)", AIScript.MoveOrdering.DEFAULT)
	opt_move_ordering.add_item("Reverse (Worst)", AIScript.MoveOrdering.REVERSE)
	opt_move_ordering.selected = 0
	opt_move_ordering.item_selected.connect(func(_idx): current_ordering = opt_move_ordering.get_item_id(_idx))
	cfg_grid.add_child(opt_move_ordering)

	vbox.add_child(HSeparator.new())

	# Metrics
	var metrics_box := VBoxContainer.new()
	metrics_box.add_theme_constant_override("separation", 2)
	vbox.add_child(metrics_box)

	lbl_nodes = Label.new()
	lbl_nodes.text = "Nodes: 0"
	lbl_nodes.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_nodes)

	lbl_pruned = Label.new()
	lbl_pruned.text = "Pruned: 0"
	lbl_pruned.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_pruned)

	lbl_time = Label.new()
	lbl_time.text = "Waktu: 0.00 ms"
	lbl_time.add_theme_font_size_override("font_size", 11)
	metrics_box.add_child(lbl_time)

	vbox.add_child(HSeparator.new())

	# Root Candidates Breakdown
	var c_title := Label.new()
	c_title.text = "Aksi Dipertimbangkan NPC:"
	c_title.add_theme_font_size_override("font_size", 12)
	c_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	vbox.add_child(c_title)

	var cand_scroll := ScrollContainer.new()
	cand_scroll.custom_minimum_size.y = 120
	vbox.add_child(cand_scroll)

	candidates_container = VBoxContainer.new()
	candidates_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidates_container.add_theme_constant_override("separation", 2)
	cand_scroll.add_child(candidates_container)

	var empty_lbl := Label.new()
	empty_lbl.text = "Menunggu giliran NPC..."
	empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	empty_lbl.add_theme_font_size_override("font_size", 11)
	candidates_container.add_child(empty_lbl)

	vbox.add_child(HSeparator.new())

	# Benchmark Button
	var exp_btn := Button.new()
	exp_btn.text = "🔬 Jalankan Benchmark AI"
	exp_btn.custom_minimum_size.y = 30
	exp_btn.pressed.connect(_on_run_experiments)
	vbox.add_child(exp_btn)

	# Tree Visualizer Button
	var tree_btn := Button.new()
	tree_btn.text = "🌳 Visualisasi Tree Minimax [F4]"
	tree_btn.custom_minimum_size.y = 34
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.1, 0.35, 0.45, 0.95)
	tsb.border_color = Color(0.3, 0.85, 0.95, 0.9)
	tsb.set_border_width_all(1)
	tsb.set_corner_radius_all(6)
	tree_btn.add_theme_stylebox_override("normal", tsb)
	var tsb_h := tsb.duplicate()
	tsb_h.bg_color = Color(0.15, 0.48, 0.62, 1.0)
	tree_btn.add_theme_stylebox_override("hover", tsb_h)
	tree_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tree_btn.pressed.connect(open_tree_visualizer)
	vbox.add_child(tree_btn)

	_build_experiment_modal()


func _build_experiment_modal() -> void:
	experiment_modal = PanelContainer.new()
	experiment_modal.position = Vector2(80, 50)
	experiment_modal.size = Vector2(1120, 620)
	experiment_modal.visible = false
	experiment_modal.z_index = 250
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.98)
	style.border_color = Color(0.95, 0.75, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	experiment_modal.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(experiment_modal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	experiment_modal.add_child(vbox)

	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	var title := Label.new()
	title.text = "HASIL EKSPERIMEN ADVERSARIAL SEARCH"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	header_hbox.add_child(title)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(sp)

	var close_btn := Button.new()
	close_btn.text = "✖ Tutup"
	close_btn.pressed.connect(func(): experiment_modal.visible = false)
	header_hbox.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	experiment_text = RichTextLabel.new()
	experiment_text.bbcode_enabled = true
	experiment_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	experiment_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(experiment_text)


func _update_debug_overlay(decision: Dictionary) -> void:
	if lbl_nodes:
		lbl_nodes.text = "Nodes: %d" % decision.get("total_nodes", 0)
	if lbl_pruned:
		lbl_pruned.text = "Pruned: %d" % decision.get("prune_count", 0)
	if lbl_time:
		lbl_time.text = "Waktu: %.2f ms" % decision.get("time_ms", 0.0)

	if not candidates_container:
		return

	for child in candidates_container.get_children():
		child.queue_free()

	var candidates: Array = decision.get("candidates", [])
	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "Tidak ada aksi."
		candidates_container.add_child(lbl)
		return

	for c in candidates:
		var row := HBoxContainer.new()
		var is_best: bool = c.get("is_best", false)

		var name_lbl := Label.new()
		name_lbl.text = "%-13s" % c.get("name", "")
		name_lbl.add_theme_font_size_override("font_size", 11)
		if is_best:
			name_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		row.add_child(name_lbl)

		var score_lbl := Label.new()
		score_lbl.text = "Skor: %6.1f" % c.get("score", 0.0)
		score_lbl.add_theme_font_size_override("font_size", 11)
		score_lbl.custom_minimum_size.x = 80
		row.add_child(score_lbl)

		var nodes_lbl := Label.new()
		nodes_lbl.text = "(%d n)" % c.get("nodes", 0)
		nodes_lbl.add_theme_font_size_override("font_size", 10)
		nodes_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		row.add_child(nodes_lbl)

		if is_best:
			var best_badge := Label.new()
			best_badge.text = " ★"
			best_badge.add_theme_font_size_override("font_size", 11)
			best_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			row.add_child(best_badge)

		candidates_container.add_child(row)


func _on_run_experiments() -> void:
	if not experiment_modal or not experiment_text:
		return
	_show_banner("Menjalankan Benchmark AI...", Color(0.95, 0.75, 0.3))
	var results := ai.run_ai_experiments(state)

	var bb := ""
	bb += "[b][color=#f4d03f]═══ EKSPERIMEN 1: MINIMAX vs ALPHA-BETA vs MOVE ORDERING ═══[/color][/b]\n"
	bb += "[table=6]"
	bb += "[cell][b]Depth[/b][/cell][cell][b]Minimax[/b][/cell][cell][b]Alpha-Beta[/b][/cell][cell][b]Cutoffs[/b][/cell][cell][b]AB + Order[/b][/cell][cell][b]Match?[/b][/cell]"

	for row in results.get("depth_comparison", []):
		bb += "[cell]Depth %d[/cell]" % row["depth"]
		bb += "[cell]%d (%.2f ms)[/cell]" % [row["mm_nodes"], row["mm_time_ms"]]
		bb += "[cell]%d (%.2f ms)[/cell]" % [row["ab_nodes"], row["ab_time_ms"]]
		bb += "[cell]%d[/cell]" % row["ab_prunes"]
		bb += "[cell][color=#58d68d]%d (%.2f ms)[/color][/cell]" % [row["abo_nodes"], row["abo_time_ms"]]
		bb += "[cell][color=#5dade2]%s[/color][/cell]" % str(row["match"])
	bb += "[/table]\n\n"

	bb += "[b][color=#f4d03f]═══ EKSPERIMEN 2: FUNGSI EVALUASI (DEPTH 4) ═══[/color][/b]\n"
	bb += "[table=4]"
	bb += "[cell][b]Fungsi[/b][/cell][cell][b]Aksi Dipilih[/b][/cell][cell][b]Skor[/b][/cell][cell][b]Nodes[/b][/cell]"
	for row in results.get("eval_comparison", []):
		bb += "[cell]%s[/cell]" % row["eval_name"]
		bb += "[cell][color=#f39c12]%s[/color][/cell]" % row["action_name"]
		bb += "[cell]%7.2f[/cell]" % row["score"]
		bb += "[cell]%d[/cell]" % row["nodes"]
	bb += "[/table]\n\n"

	bb += "[b][color=#f4d03f]═══ EKSPERIMEN 3: MOVE ORDERING (DEPTH 4) ═══[/color][/b]\n"
	bb += "[table=4]"
	bb += "[cell][b]Mode Urutan[/b][/cell][cell][b]Aksi[/b][/cell][cell][b]Nodes[/b][/cell][cell][b]Cutoffs[/b][/cell]"
	for row in results.get("order_comparison", []):
		var col := "#58d68d" if "Optimal" in row["order_name"] else ("#ec7063" if "Reverse" in row["order_name"] else "#ffffff")
		bb += "[cell]%s[/cell]" % row["order_name"]
		bb += "[cell]%s[/cell]" % row["action_name"]
		bb += "[cell][color=%s]%d[/color][/cell]" % [col, row["nodes"]]
		bb += "[cell]%d[/cell]" % row["prunes"]
	bb += "[/table]\n"

	experiment_text.text = bb
	experiment_modal.visible = true


func get_active_leader_type() -> String:
	var leader_name: String = active_player
	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var p_data: Dictionary = {}
		if bm.has_method("get_battle_data"):
			p_data = bm.get_battle_data().get("player", {})
		elif bm.get("_player_fighter") is Dictionary:
			p_data = bm.get("_player_fighter")
		var l: String = str(p_data.get("leader", ""))
		if l != "":
			leader_name = l
		elif str(p_data.get("avatar", "")).contains("archer"):
			leader_name = "Archer"
		elif str(p_data.get("avatar", "")).contains("pawn"):
			leader_name = "Pawn"
	if leader_name.to_lower().contains("archer"):
		return "Archer"
	return "Pawn"


func _update_algo_display_text() -> void:
	if not lbl_algo_display:
		return
	var l_type := get_active_leader_type()
	if l_type == "Archer":
		current_algo = AIScript.Algorithm.ALPHABETA
		lbl_algo_display.text = "⚡ Alpha-Beta (Archer)"
		lbl_algo_display.add_theme_color_override("font_color", Color(0.35, 0.95, 0.85))
	else:
		current_algo = AIScript.Algorithm.MINIMAX
		lbl_algo_display.text = "🔍 Minimax (Pawn)"
		lbl_algo_display.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))


func open_tree_visualizer() -> void:
	if not tree_viewer:
		return
	var l_type := get_active_leader_type()
	var algo_to_use = AIScript.Algorithm.ALPHABETA if l_type == "Archer" else AIScript.Algorithm.MINIMAX
	var d_to_use = clampi(current_depth, 1, 4)
	tree_viewer.open_with_state(state, ai, algo_to_use, d_to_use, current_eval, current_ordering, l_type)


func toggle_tree_visualizer() -> void:
	if not tree_viewer:
		return
	if tree_viewer.visible:
		tree_viewer.close_visualizer()
	else:
		open_tree_visualizer()
