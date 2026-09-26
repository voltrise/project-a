class_name TempBattleController
extends Node2D

## Main Battle Controller untuk Temp_Battle.
## Mengintegrasikan TempBattleState, TempBattleAI, TempBattleUI, dan 2D Sprite Visual.

const StateScript = preload("res://Temp_Battle/temp_battle_state.gd")
const AIScript = preload("res://Temp_Battle/temp_battle_ai.gd")
const UIScript = preload("res://Temp_Battle/temp_battle_ui.gd")

var state: StateScript = StateScript.new(100, 100)
var ai: AIScript = AIScript.new()
var ui: UIScript

# Config AI
var current_algo: int = AIScript.Algorithm.ALPHABETA
var current_depth: int = 4
var current_eval: int = AIScript.EvalType.BALANCED
var current_ordering: int = AIScript.MoveOrdering.OPTIMAL

# 2D Character References in Battle.tscn
@onready var player_node: Node2D = get_node_or_null("Player")
@onready var enemy_node: Node2D = get_node_or_null("Enemy")
@onready var player_anim: AnimationPlayer = get_node_or_null("Player/AnimationPlayer")
@onready var enemy_anim: AnimationPlayer = get_node_or_null("Enemy/AnimationPlayer")
@onready var player_sprite: Sprite2D = get_node_or_null("Player/PlayerSprite")
@onready var enemy_sprite: Sprite2D = get_node_or_null("Enemy/PlayerSprite")

var is_processing_turn: bool = false


func _ready() -> void:
	if enemy_sprite:
		enemy_sprite.flip_h = true

	state = StateScript.new(100, 100)
	ai = AIScript.new()

	ui = UIScript.new()
	add_child(ui)

	ui.player_action_selected.connect(_on_player_action)
	ui.reset_battle_requested.connect(reset_battle)
	ui.run_experiments_requested.connect(_on_run_experiments)
	ui.ai_config_changed.connect(_on_ai_config_changed)

	ui.update_state_display(state)
	ui.append_battle_log("Duel dimulai. Giliran Player.", Color(0.9, 0.8, 0.4))


# ══════════════════════════════════════════════════════════════════════
#  PLAYER TURN HANDLING
# ══════════════════════════════════════════════════════════════════════

func _on_player_action(action: int) -> void:
	if is_processing_turn or state.is_terminal():
		return
	if state.current_turn != StateScript.Side.PLAYER:
		return

	is_processing_turn = true

	_play_action_visual(true, action)

	var is_stochastic: bool = (current_algo == AIScript.Algorithm.EXPECTIMAX)
	var log_data := state.apply_action(action, is_stochastic)

	_log_action_result(log_data)
	ui.update_state_display(state)

	if state.is_terminal():
		_handle_game_over()
		is_processing_turn = false
		return

	await get_tree().create_timer(0.4).timeout
	_execute_npc_turn()


# ══════════════════════════════════════════════════════════════════════
#  NPC (AI) TURN HANDLING
# ══════════════════════════════════════════════════════════════════════

func _execute_npc_turn() -> void:
	if state.is_terminal():
		is_processing_turn = false
		return

	ui.update_state_display(state)

	var decision := ai.decide_action(
		state,
		current_depth,
		current_algo,
		current_eval,
		current_ordering,
		StateScript.Side.ENEMY
	)

	ui.update_ai_debug(decision)

	await get_tree().create_timer(0.5).timeout

	var chosen_action: int = decision["action"]
	if chosen_action < 0:
		chosen_action = StateScript.Action.ATTACK

	_play_action_visual(false, chosen_action)

	var is_stochastic: bool = (current_algo == AIScript.Algorithm.EXPECTIMAX)
	var log_data := state.apply_action(chosen_action, is_stochastic)

	_log_action_result(log_data)
	ui.update_state_display(state)

	if state.is_terminal():
		_handle_game_over()

	is_processing_turn = false


# ══════════════════════════════════════════════════════════════════════
#  VISUAL EFFECTS & ANIMATIONS
# ══════════════════════════════════════════════════════════════════════

func _play_action_visual(is_player: bool, action: int) -> void:
	var actor := player_node if is_player else enemy_node
	var target := enemy_node if is_player else player_node
	var anim := player_anim if is_player else enemy_anim
	var sprite := player_sprite if is_player else enemy_sprite

	if actor == null:
		return

	var orig_pos := actor.position
	var target_pos := target.position if target != null else (orig_pos + Vector2(60, 0) * (1 if is_player else -1))
	var dir := (target_pos - orig_pos).normalized()

	match action:
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			if anim and anim.has_animation("interact_axe"):
				anim.play("interact_axe")
			var dist: float = 40.0 if action == StateScript.Action.ATTACK else 60.0
			var tw := create_tween()
			tw.tween_property(actor, "position", orig_pos + dir * dist, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func():
				if target != null:
					_flash_hurt(target)
			)
			tw.tween_property(actor, "position", orig_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(func():
				if anim and anim.has_animation("idle"):
					anim.play("idle")
			)

		StateScript.Action.DEFEND:
			if sprite:
				var tw := create_tween()
				tw.tween_property(sprite, "modulate", Color(0.4, 0.8, 1.8, 1.0), 0.15)
				tw.tween_property(sprite, "modulate", Color.WHITE, 0.25)

		StateScript.Action.REST:
			if sprite:
				var tw := create_tween()
				tw.tween_property(sprite, "modulate", Color(0.4, 1.8, 0.8, 1.0), 0.15)
				tw.tween_property(sprite, "modulate", Color.WHITE, 0.25)


func _flash_hurt(target_node: Node2D) -> void:
	var sprite := target_node.get_node_or_null("PlayerSprite") as Sprite2D
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(2.0, 0.3, 0.3, 1.0), 0.08)
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.16)

	var orig := target_node.position
	var tw2 := create_tween()
	tw2.tween_property(target_node, "position", orig + Vector2(randf_range(-5, 5), 0), 0.04)
	tw2.tween_property(target_node, "position", orig, 0.06)


func _log_action_result(log: Dictionary) -> void:
	var side_col := Color(0.45, 0.8, 1.0) if log["side"] == StateScript.Side.PLAYER else Color(1.0, 0.55, 0.55)
	var actor: String = str(log["attacker_name"])
	var target: String = str(log["defender_name"])
	var act: String = str(log["action_name"])

	match log["action"]:
		StateScript.Action.ATTACK, StateScript.Action.HEAVY_ATTACK:
			var crit_str := " [CRIT]" if log.get("is_critical", false) else ""
			if log.get("blocked", false):
				ui.append_battle_log("%s: %s%s -> Blocked (-%d STM)" % [actor, act, crit_str, log["stamina_damage"]], side_col)
				if log.get("guard_break", false):
					ui.append_battle_log("⚠️ %s: Guard Broken!" % target, Color(1.0, 0.3, 0.3))
			else:
				ui.append_battle_log("%s: %s%s -> %d DMG" % [actor, act, crit_str, log["damage"]], side_col)

		StateScript.Action.DEFEND:
			ui.append_battle_log("%s: Defend -> Guard Raised" % actor, Color(0.8, 0.85, 0.5))

		StateScript.Action.REST:
			ui.append_battle_log("%s: Rest -> +%d STM" % [actor, log["stamina_gain"]], Color(0.4, 0.95, 0.5))


func _handle_game_over() -> void:
	var winner = state.get_winner()
	if winner == StateScript.Side.PLAYER:
		ui.append_battle_log("Hasil: Player Menang.", Color(0.3, 1.0, 0.4))
	else:
		ui.append_battle_log("Hasil: NPC Menang.", Color(1.0, 0.3, 0.3))


# ══════════════════════════════════════════════════════════════════════
#  CONTROLS & EXPERIMENTS
# ══════════════════════════════════════════════════════════════════════

func reset_battle() -> void:
	state.reset(100, 100)
	is_processing_turn = false
	ui.update_state_display(state)
	ui.append_battle_log("--- Duel Direset ---", Color(0.9, 0.8, 0.3))


func _on_run_experiments() -> void:
	ui.append_battle_log("Menjalankan benchmark AI...", Color(0.95, 0.75, 0.3))
	var exp_results := ai.run_ai_experiments(state)
	ui.display_experiment_results(exp_results)


func _on_ai_config_changed(algo: int, depth: int, eval_type: int, ordering: int) -> void:
	current_algo = algo
	current_depth = depth
	current_eval = eval_type
	current_ordering = ordering
