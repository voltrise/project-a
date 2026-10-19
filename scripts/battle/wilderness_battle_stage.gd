class_name WildernessBattleStage
extends Node2D

## Wilderness Battle Controller
## Mengintegrasikan sistem battle turn-based adversarial untuk mode Wilderness.
## Menggunakan karakter Pawn untuk player dan musuh dinamis dari ENEMY_PRESETS.
## Mengaplikasikan efek item potion & weapon (HP 500, buffs, dsb).

@export_group("Background Scroll")
@export var scroll_speed: float = 60.0
@export var scroll_direction: Vector2 = Vector2.LEFT

@export_group("Camera Intro")
@export var camera_start_y: float = 300.0
@export var camera_tween_duration: float = 2.5

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

const StateScript = preload("res://scripts/battle/wilderness_battle_state.gd")
const AIScript = preload("res://scripts/battle/wilderness_battle_ai.gd")
const TemplateScene = preload("res://WildernessTemplate.tscn")

var state: StateScript
var ai: AIScript

# Config AI
var current_algo: int = AIScript.Algorithm.MINIMAX
var current_depth: int = 4
var current_eval: int = AIScript.EvalType.BALANCED
var current_ordering: int = AIScript.MoveOrdering.OPTIMAL

var is_processing_turn: bool = false

# Node references
var parallax_layers: Array[ParallaxLayer] = []
var camera: Camera2D
var _idle_time: float = 0.0
var sunrays_mat: ShaderMaterial

@onready var player_character: Node2D = get_node_or_null("PlayerCharacter")
@onready var player_sprite: Sprite2D = get_node_or_null("PlayerCharacter/PlayerSprite")
@onready var player_anim: AnimationPlayer = get_node_or_null("PlayerCharacter/AnimationPlayer")
@onready var enemy_anchor: Node2D = get_node_or_null("EnemyCharacter")
@onready var ally_hud: CharacterHUD = get_node_or_null("AllyHUD")
@onready var enemy_hud: CharacterHUD = get_node_or_null("EnemyHUD")
@onready var action_buttons: Control = get_node_or_null("CanvasLayer/PlayerActionButtons")
@onready var canvas_layer: CanvasLayer = get_node_or_null("CanvasLayer")
@onready var bgm_player: AudioStreamPlayer = get_node_or_null("BattleBGM")

# Enemy spawned instance
var spawned_enemy_node: Node2D = null
var enemy_anim_player: AnimationPlayer = null
var enemy_sprite: Sprite2D = null

# UI Feedback & Modals
var banner_label: Label
var game_over_modal: PanelContainer
var buffs_container: HBoxContainer = null

var player_fighter_name: String = "PAWN"
var enemy_fighter_name: String = "SKELETON"
var _player_orig_pos: Vector2 = Vector2.ZERO
var _enemy_orig_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_setup_camera()
	_setup_flipped_y_mirror()
	_gather_parallax_layers(self)
	_setup_bgm()
	_setup_now_playing()
	_setup_sunrays()

	_setup_player_character()
	_setup_enemy_character()

	if player_character:
		_player_orig_pos = player_character.position
	if enemy_anchor:
		_enemy_orig_pos = enemy_anchor.position

	_init_battle_system()
	_setup_action_buttons()
	_setup_banner_label()
	_build_buffs_display()

	_update_huds(false)
	_update_action_buttons_state()

	_show_banner("DUEL START! GILIRAN %s" % player_fighter_name.to_upper(), Color(0.3, 0.9, 1.0))


func _setup_camera() -> void:
	camera = get_node_or_null("Camera2D")
	if camera:
		camera.position.y = camera_start_y
		var tw = create_tween()
		tw.tween_property(camera, "position:y", 0.0, camera_tween_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _setup_flipped_y_mirror() -> void:
	for child in get_children():
		if child is ParallaxBackground:
			for pl in child.get_children():
				if pl is ParallaxLayer:
					for sp in pl.get_children():
						if sp is Sprite2D:
							sp.centered = false
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
	for layer in parallax_layers:
		if layer.motion_scale.x == 0.0:
			continue
		layer.motion_offset.x += scroll_direction.x * scroll_speed * layer.motion_scale.x * delta
		if layer.motion_mirroring.x > 0:
			layer.motion_offset.x = wrapf(layer.motion_offset.x, 0.0, layer.motion_mirroring.x)

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


func _setup_bgm() -> void:
	if bgm_player:
		if bgm_player.stream and bgm_player.stream is AudioStreamMP3:
			bgm_player.stream.loop = true
		if not bgm_player.playing:
			bgm_player.play()


func _setup_now_playing() -> void:
	var np_ui: Control = get_node_or_null("CanvasLayer/NowPlayingUI")
	if not np_ui:
		return
	np_ui.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(np_ui, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_property(np_ui, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): np_ui.visible = false)


# ══════════════════════════════════════════════════════════════════════
#  CHARACTER VISUALS & ANIMATIONS SETUP
# ══════════════════════════════════════════════════════════════════════

func _setup_player_character() -> void:
	if player_anim:
		if not player_anim.has_animation("attack"):
			var lib = player_anim.get_animation_library("")
			if lib:
				if player_anim.has_animation("interact_axe"):
					lib.add_animation("attack", player_anim.get_animation("interact_axe"))
				elif player_anim.has_animation("interact_knife"):
					lib.add_animation("attack", player_anim.get_animation("interact_knife"))
		player_anim.play("idle")

	var avatar_rect: TextureRect = get_node_or_null("CanvasLayer/PlayerAvatarUI/AvatarRect")
	if avatar_rect and ResourceLoader.exists("res://ui/avatar_pawn.png"):
		avatar_rect.texture = load("res://ui/avatar_pawn.png")


func _setup_enemy_character() -> void:
	if enemy_anchor == null:
		return

	# Clear any previous child
	for child in enemy_anchor.get_children():
		child.queue_free()

	var preset_key = "skeleton"
	if has_node("/root/WildernessManager"):
		var wm = get_node("/root/WildernessManager")
		if wm.get("current_enemy_key") != "":
			preset_key = wm.get("current_enemy_key")

	var tpl_inst = TemplateScene.instantiate()
	var e_node = tpl_inst.instantiate_enemy(preset_key)
	if e_node == null:
		e_node = tpl_inst.instantiate_enemy("Skeleton")

	if e_node:
		spawned_enemy_node = e_node
		e_node.position = Vector2.ZERO
		e_node.scale = Vector2(3.56, 3.56)

		if e_node.has_method("disable_hover"):
			e_node.disable_hover()
		e_node.set("enable_hover_card", false)

		enemy_anchor.add_child(e_node)

		# Flip horizontal agar musuh menghadap ke arah player di kiri
		var sp = e_node.get_node_or_null("Sprite2D") as Sprite2D
		if sp:
			sp.flip_h = true
			enemy_sprite = sp

		# Nonaktifkan collision dan pastikan popup hover card lenyap total dari enemy dalam battle
		var col = e_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col:
			col.disabled = true
		if e_node.has_method("disable_hover"):
			e_node.disable_hover()
		e_node.set("enable_hover_card", false)
		if "detail_card" in e_node and is_instance_valid(e_node.detail_card):
			e_node.detail_card.visible = false
			e_node.detail_card.queue_free()
			e_node.detail_card = null
		for child in e_node.get_children():
			if child is PanelContainer:
				child.visible = false
				child.queue_free()
		if "input_pickable" in e_node:
			e_node.input_pickable = false

		enemy_anim_player = e_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if e_node.has_method("play_animation"):
			e_node.play_animation("idle")
		elif enemy_anim_player and enemy_anim_player.has_animation("idle"):
			enemy_anim_player.play("idle")

	tpl_inst.queue_free()


# ══════════════════════════════════════════════════════════════════════
#  BATTLE SYSTEM INITIALIZATION
# ══════════════════════════════════════════════════════════════════════

func _init_battle_system() -> void:
	var p_hp = 500
	var p_max_hp = 500
	var enemy_preset: Dictionary = {}
	var buffs: Dictionary = {}

	if has_node("/root/WildernessManager"):
		var wm = get_node("/root/WildernessManager")
		p_hp = wm.get("player_hp")
		p_max_hp = wm.get("player_max_hp")
		var ek: String = wm.get("current_enemy_key")
		enemy_preset = wm.get_enemy_preset(ek)
		buffs = wm.get("active_buffs")
	else:
		enemy_preset = {
			"name": "Skeleton Guard",
			"tier": "Easy",
			"max_hp": 75,
			"attack_damage": 15,
			"heavy_damage": 25,
		}

	player_fighter_name = "PAWN"
	enemy_fighter_name = enemy_preset.get("name", "ENEMY").to_upper()

	state = StateScript.new(p_hp, enemy_preset, buffs, p_max_hp)
	ai = AIScript.new()

	# Petakan profil AI dinamis sesuai jenis musuh yang dihadapi
	current_eval = AIScript.get_personality_for_enemy(enemy_preset.get("node_name", enemy_preset.get("name", "Skeleton")))

	if ally_hud:
		ally_hud.set_character_name(player_fighter_name)
	if enemy_hud:
		enemy_hud.set_character_name(enemy_fighter_name)


func _build_buffs_display() -> void:
	if not canvas_layer:
		return

	buffs_container = HBoxContainer.new()
	buffs_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	buffs_container.position = Vector2(30, 105)
	buffs_container.add_theme_constant_override("separation", 8)
	canvas_layer.add_child(buffs_container)

	_update_buffs_display()


func _update_buffs_display() -> void:
	if buffs_container == null:
		return
	for c in buffs_container.get_children():
		c.queue_free()

	if state == null:
		return

	var b_data = state.buffs
	var any_buff = false

	if b_data.get("pothp", 0) > 0:
		_add_buff_badge("🧪 HP Potion (+25 HP Rest)", Color(0.95, 0.4, 0.5))
		any_buff = true
	if b_data.get("potstamina", 0) > 0:
		_add_buff_badge("⚡ Stamina Pot (-25% STM)", Color(0.3, 0.85, 1.0))
		any_buff = true
	if b_data.get("sword", 0) > 0:
		_add_buff_badge("⚔️ Sword (+10% Basic)", Color(1.0, 0.85, 0.25))
		any_buff = true
	if b_data.get("axe", 0) > 0:
		_add_buff_badge("🪓 Axe (+10% Heavy)", Color(1.0, 0.5, 0.2))
		any_buff = true


func _add_buff_badge(text: String, border_col: Color) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.18, 0.9)
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", border_col)
	p.add_child(lbl)
	buffs_container.add_child(p)


func _setup_action_buttons() -> void:
	if not action_buttons:
		return
	if action_buttons.has_signal("action_chosen"):
		if not action_buttons.action_chosen.is_connected(_on_action_chosen):
			action_buttons.action_chosen.connect(_on_action_chosen)


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

	# Visual aksi player
	_play_action_visual(true, action)

	var log_data := state.apply_action(action, false)

	_show_combat_feedback(true, log_data)
	_update_huds(true)
	_update_action_buttons_state()

	if state.is_terminal():
		_handle_game_over(state.get_winner() == StateScript.Side.PLAYER)
		return

	await get_tree().create_timer(0.65).timeout
	_execute_enemy_turn()


func _execute_enemy_turn() -> void:
	if state.is_terminal():
		is_processing_turn = false
		return

	var decision := ai.decide_action(
		state,
		current_depth,
		current_algo,
		current_eval,
		current_ordering,
		StateScript.Side.ENEMY
	)

	var chosen_action: int = decision.get("action", StateScript.Action.ATTACK)
	if chosen_action < 0:
		chosen_action = StateScript.Action.REST

	_play_action_visual(false, chosen_action)

	var log_data := state.apply_action(chosen_action, false)

	_show_combat_feedback(false, log_data)
	_update_huds(true)

	if state.is_terminal():
		_handle_game_over(state.get_winner() == StateScript.Side.PLAYER)
		return

	await get_tree().create_timer(0.55).timeout

	is_processing_turn = false
	_update_action_buttons_state()


# ══════════════════════════════════════════════════════════════════════
#  ANIMATION & VISUAL FEEDBACK
# ══════════════════════════════════════════════════════════════════════

func _play_action_visual(is_player: bool, action: int) -> void:
	var actor = player_character if is_player else enemy_anchor
	var target = enemy_anchor if is_player else player_character

	match action:
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			# Play setup attack animations
			if is_player and player_anim:
				var a_name = "attack" if player_anim.has_animation("attack") else "interact_axe"
				if player_anim.has_animation(a_name):
					player_anim.play(a_name)
					get_tree().create_timer(0.5).timeout.connect(func():
						if player_anim:
							player_anim.play("idle")
					)
			elif not is_player and spawned_enemy_node:
				if spawned_enemy_node.has_method("play_animation"):
					spawned_enemy_node.play_animation("attack")
					get_tree().create_timer(0.5).timeout.connect(func():
						if is_instance_valid(spawned_enemy_node) and spawned_enemy_node.has_method("play_animation"):
							spawned_enemy_node.play_animation("idle")
					)

			# Dash movement tween
			var dir = Vector2.RIGHT if is_player else Vector2.LEFT
			var dist = 75.0 if action == StateScript.Action.ATTACK else 120.0
			var orig_pos = _player_orig_pos if is_player else _enemy_orig_pos

			var tw := create_tween()
			tw.tween_property(actor, "position", orig_pos + dir * dist, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func():
				_flash_hurt(target)
			)
			tw.tween_property(actor, "position", orig_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

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
	var target_pos: Vector2 = Vector2(860, 480) if is_player_attacker else Vector2(420, 480)
	var actor_pos: Vector2 = Vector2(420, 480) if is_player_attacker else Vector2(860, 480)

	match log_data.get("action", 0):
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			if log_data.get("blocked", false):
				_spawn_floating_text(target_pos, "BLOCKED! (-%d STM)" % log_data.get("stamina_damage", 20), Color(0.4, 0.85, 1.0))
				if log_data.get("parry", false):
					_spawn_floating_text(target_pos + Vector2(0, -32), "⚡ PARRY! (Next: 0 STM / +100 HP)", Color(1.0, 0.88, 0.25))
					_show_banner("⚡ PARRY BERHASIL! Counter Attack Siap!", Color(1.0, 0.9, 0.3))
				elif log_data.get("guard_break", false):
					_spawn_floating_text(target_pos + Vector2(0, -32), "GUARD BROKEN!", Color(1.0, 0.25, 0.25))
					_show_banner("%s GUARD BROKEN!" % log_data.get("defender_name", "Target"), Color(1.0, 0.3, 0.3))
			else:
				var is_crit: bool = log_data.get("is_critical", false)
				var crit_txt = " CRIT!" if is_crit else ""
				var col = Color(1.0, 0.85, 0.2) if is_crit else Color(1.0, 0.35, 0.35)
				_spawn_floating_text(target_pos, "-%d HP%s" % [log_data.get("damage", 20), crit_txt], col)

			# Feedback Parry Trigger (pada saat player menyerang)
			if log_data.get("parry_triggered", false):
				if log_data.get("parry_type") == "heavy":
					_spawn_floating_text(actor_pos + Vector2(0, -32), "⚡ PARRY BURST! (0 STM)", Color(1.0, 0.85, 0.2))
				elif log_data.get("parry_type") == "light":
					_spawn_floating_text(actor_pos + Vector2(0, -32), "💚 PARRY HEAL! +25 HP", Color(0.35, 1.0, 0.55))

			# Feedback Retaliation Heal
			if log_data.get("retaliation_heal", 0) > 0:
				_spawn_floating_text(actor_pos + Vector2(0, -56), "🩸 RETALIATION! +%d HP" % log_data["retaliation_heal"], Color(0.35, 1.0, 0.55))

		StateScript.Action.DEFEND:
			_spawn_floating_text(actor_pos, "GUARD UP!", Color(0.4, 0.9, 1.0))

		StateScript.Action.REST:
			var hp_g: int = log_data.get("hp_gain", 0)
			var txt = "+%d STM" % log_data.get("stamina_gain", 50)
			if hp_g > 0:
				txt += " • +%d HP (Potion)" % hp_g
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
	add_child(label)

	var tw = create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 40.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
#  GAME OVER & RETURN FLOW
# ══════════════════════════════════════════════════════════════════════

func _handle_game_over(is_player_win: bool) -> void:
	is_processing_turn = true
	_update_action_buttons_state()

	var winner_name: String = player_fighter_name if is_player_win else enemy_fighter_name
	var msg: String = "VICTORY! %s MENANG!" % winner_name if is_player_win else "DEFEAT! %s MENANG!" % winner_name
	var col: Color = Color(0.3, 1.0, 0.4) if is_player_win else Color(1.0, 0.3, 0.3)
	_show_banner(msg, col)

	if is_player_win and enemy_anchor:
		var tw = create_tween()
		tw.tween_property(enemy_anchor, "modulate:a", 0.0, 0.8)
	elif not is_player_win and player_character:
		var tw = create_tween()
		tw.tween_property(player_character, "modulate:a", 0.0, 0.8)

	if has_node("/root/WildernessManager"):
		var wm = get_node("/root/WildernessManager")
		wm.on_battle_completed(is_player_win, state.player["hp"])

	_show_game_over_modal(is_player_win)


func _show_game_over_modal(is_player_win: bool) -> void:
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
	game_over_modal.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	game_over_modal.add_child(vbox)

	var title := Label.new()
	title.text = "🏆 PERTARUNGAN DIMENANGKAN!" if is_player_win else "💀 PLAYER DIKALAHKAN!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", theme_color)
	vbox.add_child(title)

	var subtitle := Label.new()
	if is_player_win:
		subtitle.text = "Pawn berhasil mengalahkan %s!\nSisa HP tersimpan: %d / %d" % [
			enemy_fighter_name,
			state.player["hp"],
			state.player["max_hp"]
		]
	else:
		subtitle.text = "Pawn telah gugur dalam petualangan di Wilderness..."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.9, 0.96))
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)

	if is_player_win:
		var resume_btn := Button.new()
		resume_btn.text = "🗺️ Lanjutkan Eksplorasi"
		resume_btn.custom_minimum_size = Vector2(200, 42)
		var rb := StyleBoxFlat.new()
		rb.bg_color = Color(0.12, 0.48, 0.32, 1.0)
		rb.border_color = Color(0.35, 0.95, 0.6, 1.0)
		rb.set_border_width_all(1)
		rb.set_corner_radius_all(8)
		resume_btn.add_theme_stylebox_override("normal", rb)
		resume_btn.pressed.connect(_return_to_wilderness)
		btn_box.add_child(resume_btn)
	else:
		var overworld_btn := Button.new()
		overworld_btn.text = "🏠 Kembali ke Overworld"
		overworld_btn.custom_minimum_size = Vector2(200, 42)
		var ob := StyleBoxFlat.new()
		ob.bg_color = Color(0.38, 0.16, 0.16, 1.0)
		ob.border_color = Color(0.95, 0.4, 0.4, 1.0)
		ob.set_border_width_all(1)
		ob.set_corner_radius_all(8)
		overworld_btn.add_theme_stylebox_override("normal", ob)
		overworld_btn.pressed.connect(_return_to_overworld)
		btn_box.add_child(overworld_btn)

	if canvas_layer:
		canvas_layer.add_child(game_over_modal)
	else:
		add_child(game_over_modal)


func _return_to_wilderness() -> void:
	get_tree().change_scene_to_file("res://Wilderness.tscn")


func _return_to_overworld() -> void:
	if has_node("/root/WildernessManager"):
		var wm = get_node("/root/WildernessManager")
		wm.clear_session()
	get_tree().change_scene_to_file("res://Overworld.tscn")
