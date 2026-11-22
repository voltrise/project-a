extends Node2D

## Kingdom Defense Controller
## Orchestrates Guard Observations (Noisy Clues) -> Bayesian Multi-Post Threat -> KB Resolution Logic
## -> PDDL King Mobilization & Troop Deployment -> Execution & Debug Overlay

const ResolutionEngine = preload("res://scripts/ai/logic/resolution_engine.gd")
const KingdomPDDLPlanner = preload("res://scripts/ai/planning/kingdom_pddl_planner.gd")
const KingdomUncertaintySolver = preload("res://scripts/ai/uncertainty/kingdom_uncertainty_solver.gd")

# Scene References - Characters
@onready var king: CharacterBody2D = $Characters/King
@onready var builder: CharacterBody2D = $Characters/Builder
@onready var archer: CharacterBody2D = $Characters/Archer
@onready var warrior: CharacterBody2D = $Characters/Warrior

@onready var guard_main_gate: CharacterBody2D = $Characters/Guard_MainGate
@onready var guard_cave: CharacterBody2D = $Characters/Guard_Cave
@onready var guard_docks: CharacterBody2D = $Characters/Guard_Docks

# Scene References - Camera
@onready var camera: Camera2D = $Camera2D
var initial_camera_pos: Vector2 = Vector2.ZERO
var initial_camera_zoom: Vector2 = Vector2.ONE

# Scene References - Markers
@onready var marker_sentry: Marker2D = $Markers/Marker_SentryPost
@onready var marker_main_gate: Marker2D = $Markers/Marker_MainGate
@onready var marker_cave: Marker2D = $Markers/Marker_Cave
@onready var marker_docks: Marker2D = $Markers/Marker_Docks
@onready var marker_bell: Marker2D = $Markers/Marker_Bell

@onready var marker_builders: Marker2D = $Markers/Marker_Builders
@onready var marker_archers: Marker2D = $Markers/Marker_Archers
@onready var marker_warriors: Marker2D = $Markers/Marker_Warriors

@onready var marker_threat_main_gate: Marker2D = $Markers/Marker_MainGateThreat
@onready var marker_threat_cave: Marker2D = $Markers/Marker_CaveThreat
@onready var marker_threat_docks: Marker2D = $Markers/Marker_DocksThreat

# Scene References - Objects
@onready var defense_main_gate: Node2D = $InteractiveObjects/Defense_MainGate
@onready var defense_cave: Node2D = $InteractiveObjects/Defense_Cave
@onready var defense_docks: Node2D = $InteractiveObjects/Defense_Docks

@onready var threat_main_gate: Node2D = $InteractiveObjects/Threat_MainGate
@onready var threat_cave: Node2D = $InteractiveObjects/Threat_Cave
@onready var threat_docks: Node2D = $InteractiveObjects/Threat_Docks

# UI Containers
@onready var ui_canvas: CanvasLayer = $UI
@onready var control_panel_container: PanelContainer = $UI/ControlPanel
@onready var debug_overlay_container: PanelContainer = $UI/DebugOverlay

# Environmental Effect Layer
var env_tint_rect: ColorRect = null
var env_texture_overlay: TextureRect = null
var env_particles: CPUParticles2D = null

# Weather Textures
var tex_fog = preload("res://assets/fog.png")
var tex_rain = preload("res://assets/rain.png")

# State
var kb_rules_path: String = "res://data/kingdom_defense_rules.json"
var kb_clauses: Array = []
var is_simulating: bool = false

var threat_widget_panels: Array[PanelContainer] = []

var selected_env: String = "Clear" # "Clear", "Night", "Foggy", "Rain"
var selected_clues = {
	"MainGate": "None",
	"Cave": "None",
	"Docks": "None"
}

var initial_character_positions: Dictionary = {}

# Simulation calculation caches
var last_assessment = null
var last_kb_proofs: Dictionary = {}
var last_pddl_result = null

# Debug UI Controls
var dbg_tab_container: TabContainer
var dbg_bayes_label: RichTextLabel
var dbg_kb_label: RichTextLabel
var dbg_pddl_label: RichTextLabel
var dbg_meu_label: RichTextLabel
var status_bar_label: Label

func _ready():
	print("[KingdomDefense] Initializing Kingdom Defense Controller...")
	kb_clauses = ResolutionEngine.load_rules_from_file(kb_rules_path)

	if camera:
		initial_camera_pos = camera.global_position
		initial_camera_zoom = camera.zoom

	_record_initial_positions()
	_setup_environment_effects()
	_setup_speech_bubble_styling()
	_create_marker_threat_popups()
	_setup_control_panel()
	_setup_debug_overlay()
	reset_simulation()

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			toggle_debug_overlay()

func _record_initial_positions():
	var chars = [king, builder, archer, warrior, guard_main_gate, guard_cave, guard_docks]
	for ch in chars:
		if ch:
			initial_character_positions[ch] = ch.global_position

func _setup_environment_effects():
	# Screen tint for Night/Fog/Rain (World Space z_index = 50, below UI and Dropdowns)
	env_tint_rect = ColorRect.new()
	env_tint_rect.name = "EnvTintRect"
	env_tint_rect.z_index = 50
	env_tint_rect.z_as_relative = false
	env_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	env_tint_rect.position = Vector2(-2000, -2000)
	env_tint_rect.size = Vector2(8000, 8000)
	env_tint_rect.color = Color(0, 0, 0, 0)
	add_child(env_tint_rect)

	# Texture overlay for fog / rain patterns (World Space z_index = 51)
	env_texture_overlay = TextureRect.new()
	env_texture_overlay.name = "EnvTextureOverlay"
	env_texture_overlay.z_index = 51
	env_texture_overlay.z_as_relative = false
	env_texture_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	env_texture_overlay.position = Vector2(-2000, -2000)
	env_texture_overlay.size = Vector2(8000, 8000)
	env_texture_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	env_texture_overlay.stretch_mode = TextureRect.STRETCH_TILE
	env_texture_overlay.modulate = Color(1, 1, 1, 0.55)
	add_child(env_texture_overlay)

	# Rain particles (World Space z_index = 52)
	env_particles = CPUParticles2D.new()
	env_particles.name = "RainParticles"
	env_particles.z_index = 52
	env_particles.z_as_relative = false
	env_particles.position = Vector2(1600, 200)
	env_particles.amount = 400
	env_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	env_particles.emission_rect_extents = Vector2(2500, 100)
	env_particles.direction = Vector2(-0.2, 1.0)
	env_particles.spread = 5.0
	env_particles.gravity = Vector2(0, 980)
	env_particles.initial_velocity_min = 600
	env_particles.initial_velocity_max = 850
	env_particles.scale_amount_min = 2.0
	env_particles.scale_amount_max = 3.5
	env_particles.color = Color(0.65, 0.8, 1.0, 0.6)
	env_particles.emitting = false
	add_child(env_particles)

func apply_environment(env_type: String):
	selected_env = env_type
	match env_type:
		"Clear":
			env_tint_rect.color = Color(0, 0, 0, 0)
			env_texture_overlay.texture = null
			env_particles.emitting = false
		"Night":
			env_tint_rect.color = Color(0.05, 0.08, 0.25, 0.45)
			env_texture_overlay.texture = null
			env_particles.emitting = false
		"Foggy":
			env_tint_rect.color = Color(0.85, 0.9, 0.95, 0.25)
			env_texture_overlay.texture = tex_fog
			env_texture_overlay.modulate = Color(1, 1, 1, 0.60)
			env_particles.emitting = false
		"Rain":
			env_tint_rect.color = Color(0.1, 0.15, 0.3, 0.30)
			env_texture_overlay.texture = tex_rain
			env_texture_overlay.modulate = Color(1, 1, 1, 0.50)
			env_particles.emitting = true

func _setup_speech_bubble_styling():
	var chars = [king, builder, archer, warrior, guard_main_gate, guard_cave, guard_docks]
	for ch in chars:
		if ch:
			var lbl: Label = ch.get_node_or_null("SpeechLabel")
			if lbl:
				lbl.position = Vector2(-120, -70)
				lbl.size = Vector2(240, 36)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl.add_theme_font_size_override("font_size", 14)
				lbl.add_theme_color_override("font_color", Color.YELLOW)
				lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
				lbl.add_theme_constant_override("shadow_offset_x", 1)
				lbl.add_theme_constant_override("shadow_offset_y", 1)
				lbl.text = ""

func show_speech(character: Node2D, text: String, duration: float = 3.0):
	if not character:
		return
	var lbl: Label = character.get_node_or_null("SpeechLabel")
	if lbl:
		lbl.text = text
		var tween = create_tween()
		tween.tween_interval(duration)
		tween.tween_callback(func(): if lbl: lbl.text = "")

func toggle_debug_overlay():
	if debug_overlay_container:
		debug_overlay_container.visible = not debug_overlay_container.visible

# ==============================================================================
# WORLD THREAT MARKER UI (Floating Option Panels at Threats)
# ==============================================================================

func _create_marker_threat_popups():
	_build_threat_widget(marker_threat_main_gate, "MainGate", [
		"None (All Quiet)",
		"Distant Drums",
		"Campfire Smoke",
		"War Horn"
	])
	_build_threat_widget(marker_threat_cave, "Cave", [
		"None (All Quiet)",
		"Faint Hissing",
		"Earthquake Vibration",
		"Low Growl"
	])
	_build_threat_widget(marker_threat_docks, "Docks", [
		"None (All Quiet)",
		"Splashing Waves",
		"Fog Siren",
		"Water Shadow"
	])

func _build_threat_widget(marker_node: Marker2D, post_id: String, clue_options: Array):
	if not marker_node:
		return
	var pnl = PanelContainer.new()
	# Ensure UI renders on top of all 2D world sprites/walls
	pnl.z_index = 100
	pnl.z_as_relative = false
	# 2x size scaling for 0.5/0.4 camera zoom
	pnl.custom_minimum_size = Vector2(240, 85)
	pnl.scale = Vector2(2.5, 2.5)
	pnl.position = Vector2(-216, -95)

	var vb = VBoxContainer.new()
	pnl.add_child(vb)

	var lbl = Label.new()
	lbl.text = post_id + " Clue:"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.ORANGE)
	vb.add_child(lbl)

	var opt = OptionButton.new()
	opt.add_theme_font_size_override("font_size", 13)
	for cl in clue_options:
		opt.add_item(cl)

	opt.item_selected.connect(func(idx):
		var raw_name = clue_options[idx].split(" (")[0]
		selected_clues[post_id] = raw_name
		# Sprite threat only appears when simulation runs and threat is confirmed!
	)
	vb.add_child(opt)

	marker_node.add_child(pnl)
	threat_widget_panels.append(pnl)

func _set_threat_widgets_visible(visible_state: bool):
	for pnl in threat_widget_panels:
		if is_instance_valid(pnl):
			pnl.visible = visible_state

func _update_threat_visibility(post_id: String, has_threat: bool):
	match post_id:
		"MainGate":
			if threat_main_gate: threat_main_gate.visible = has_threat
		"Cave":
			if threat_cave: threat_cave.visible = has_threat
		"Docks":
			if threat_docks: threat_docks.visible = has_threat

# ==============================================================================
# SIMULATION WORKFLOW
# ==============================================================================

func run_simulation():
	if is_simulating:
		return
	is_simulating = true
	_set_ui_phase_running()
	status_bar_label.text = "Status: Guards assessing perimeter signs..."

	# --- STAGE 1: BAYESIAN MULTI-POST THREAT ASSESSMENT ---
	last_assessment = KingdomUncertaintySolver.assess_kingdom(selected_clues, selected_env)

	# --- STAGE 2: GUARDS REPORTING TO KING (NPC-to-NPC CASCADE) ---
	var any_reported = false
	var kb_facts = {
		"Threat_MainGate": last_assessment.beliefs["MainGate"].is_confirmed,
		"Threat_Cave": last_assessment.beliefs["Cave"].is_confirmed,
		"Threat_Docks": last_assessment.beliefs["Docks"].is_confirmed
	}

	# Run KB resolution refutations
	last_kb_proofs.clear()
	for post in ["MainGate", "Cave", "Docks"]:
		var query = "Report_" + post
		var prf = ResolutionEngine.prove(kb_clauses, kb_facts, query)
		last_kb_proofs[post] = prf

	# Emergency bell & TotalMobilization proofs
	last_kb_proofs["TotalMobilization"] = ResolutionEngine.prove(kb_clauses, kb_facts, "TotalMobilization")
	last_kb_proofs["KingdomSecure"] = ResolutionEngine.prove(kb_clauses, kb_facts, "KingdomSecure")

	# Visual Guard actions: Guards walk to King to report, then return to post
	var king_pos = king.global_position if king else Vector2.ZERO
	for post in ["MainGate", "Cave", "Docks"]:
		var is_threat = last_assessment.beliefs[post].is_confirmed
		var guard_node = _get_guard_for_post(post)
		if is_threat and guard_node:
			any_reported = true
			var post_origin_pos = initial_character_positions[guard_node]
			# Guard runs to King to report
			var report_pos = king_pos + Vector2(randf_range(-60, 60), randf_range(40, 80))
			await _move_character_to(guard_node, report_pos, 1.1)
			show_speech(guard_node, "Lapor Paduka! Tanda bahaya di %s!" % post, 1.8)
			await get_tree().create_timer(1.0).timeout
			# Guard returns to post
			show_speech(guard_node, "Kembali ke pos jaga %s!" % post, 1.2)
			await _move_character_to(guard_node, post_origin_pos, 1.1)
		elif guard_node:
			show_speech(guard_node, "Area %s aman terkendali." % post, 1.8)

	await get_tree().create_timer(0.6).timeout

	# --- STAGE 3: KING DECISION VIA KB & MEU ---
	if not any_reported:
		show_speech(king, "Semua pos aman. Para prajurit tetap bersiaga di barak.", 4.0)
		status_bar_label.text = "Status: All Clear. No deployment needed."
		_update_debug_text_views()
		is_simulating = false
		_set_ui_phase_postrun()
		return

	# Speech King commanding troops (Multiple troops per post or 1 to each if all 3 threatened)
	var orders_speech: Array[String] = []
	for post in last_assessment.priority_order:
		var assigned_list = last_assessment.post_troop_assignments.get(post, [])
		if not assigned_list.is_empty():
			orders_speech.append("%s ke %s!" % [" & ".join(assigned_list), post])
	show_speech(king, "Titah Raja: " + ", ".join(orders_speech), 4.0)
	await get_tree().create_timer(1.5).timeout

	# --- STAGE 4: AUTOMATED PLANNING (PDDL) ---
	var locations: Array[String] = [
		"Marker_SentryPost", "Marker_MainGate", "Marker_Cave", "Marker_Docks",
		"Marker_Builders", "Marker_Archers", "Marker_Warriors", "Marker_Bell"
	]
	var troops: Array[String] = ["Archer", "Warrior", "Builder"]
	var posts: Array[String] = ["MainGate", "Cave", "Docks"]
	var domain_actions = KingdomPDDLPlanner.get_kingdom_domain_actions(locations, troops, posts)

	var init_state = {
		"KingAt": "Marker_SentryPost",
		"ArcherMobilized": false, "ArcherDeployed": false,
		"WarriorMobilized": false, "WarriorDeployed": false,
		"BuilderMobilized": false, "BuilderDeployed": false,
		"BellRang": false
	}

	var goal_state = {}
	for tr in last_assessment.troop_to_post.keys():
		var assigned_post = last_assessment.troop_to_post[tr]
		if last_assessment.beliefs[assigned_post].is_confirmed:
			goal_state[tr + "Deployed"] = true
			goal_state[tr + "_At_" + assigned_post] = true

	last_pddl_result = KingdomPDDLPlanner.plan(init_state, goal_state, domain_actions)
	_update_debug_text_views()

	if not last_pddl_result.is_success:
		show_speech(king, "Gagal merencanakan mobilisasi pasukan!", 3.0)
		status_bar_label.text = "Status: PDDL Planner could not formulate deployment plan."
		is_simulating = false
		_set_ui_phase_postrun()
		return

	# --- STAGE 5: EXECUTE PDDL PLAN ---
	await _execute_kingdom_plan(last_pddl_result.plan_actions)
	if camera:
		await _move_camera_to(king.global_position, Vector2(0.85, 0.85), 0.8)
	show_speech(king, "Pertahanan kerajaan telah kokoh!", 2.5)
	await get_tree().create_timer(2.0).timeout

	# Cinematic Panning across all defended/threatened posts
	await _cinematic_pan_posts()

	status_bar_label.text = "Status: Kingdom Defense Deployed Successfully!"
	is_simulating = false
	_set_ui_phase_postrun()

func _cinematic_pan_posts():
	if not camera:
		return
	status_bar_label.text = "Status: Surveying attacked perimeters..."
	for post in ["MainGate", "Cave", "Docks"]:
		# Only pan to posts that actually have confirmed incoming threats!
		if last_assessment and last_assessment.beliefs[post].is_confirmed:
			var marker = _get_marker_node("Marker_" + post)
			if marker:
				await _move_camera_to(marker.global_position, Vector2(0.75, 0.75), 1.0)
				# Threat reveals dramatically when the camera focuses on the attacked post!
				_update_threat_visibility(post, true)
				await get_tree().create_timer(1.8).timeout

	# Zoom back out to full kingdom view
	await _move_camera_to(initial_camera_pos, initial_camera_zoom, 1.2)

func _execute_kingdom_plan(actions: Array):
	for act in actions:
		status_bar_label.text = "Executing Plan: " + act.to_action_string()
		match act.name:
			"KingMove":
				var dest_marker_name = act.parameters[1]
				var dest_marker = _get_marker_node(dest_marker_name)
				if dest_marker:
					await _move_character_to(king, dest_marker.global_position, 1.0)
			"MobilizeTroop":
				var troop_name = act.parameters[0]
				var troop_node = _get_troop_node(troop_name)
				show_speech(king, "%s, berangkat ke pos tugasmu!" % troop_name, 1.2)
				show_speech(troop_node, "Siap Paduka!", 1.2)
				await get_tree().create_timer(1.0).timeout
			"DeployTroop":
				var troop_name = act.parameters[0]
				var post_name = act.parameters[1]
				var troop_node = _get_troop_node(troop_name)
				var post_marker = _get_marker_node("Marker_" + post_name)
				if troop_node and post_marker:
					show_speech(troop_node, "Menuju pos %s!" % post_name, 1.5)
					await _move_character_to(troop_node, post_marker.global_position, 1.3)
					# Hide deployed character so the detailed sprite in the defense node takes over!
					troop_node.visible = false
					# Reveal defense subnode (Archers, Warriors, or Builders) under Defense_<Post>
					_activate_defense_subnode(post_name, troop_name)
					show_speech(troop_node, "Pertahanan %s di pos %s siap!" % [troop_name, post_name], 1.8)
					await get_tree().create_timer(0.6).timeout

func _activate_defense_subnode(post_name: String, troop_name: String):
	var post_defense_parent = null
	match post_name:
		"MainGate": post_defense_parent = defense_main_gate
		"Cave": post_defense_parent = defense_cave
		"Docks": post_defense_parent = defense_docks

	if post_defense_parent:
		post_defense_parent.visible = true
		# Plural node name mapping: Archer -> Archers, Warrior -> Warriors, Builder -> Builders
		var subnode_name = troop_name + "s"
		var sub = post_defense_parent.get_node_or_null(subnode_name)
		if sub:
			sub.visible = true

func _get_guard_for_post(post: String) -> CharacterBody2D:
	match post:
		"MainGate": return guard_main_gate
		"Cave": return guard_cave
		"Docks": return guard_docks
	return null

func _get_troop_node(troop_name: String) -> CharacterBody2D:
	match troop_name:
		"Archer": return archer
		"Warrior": return warrior
		"Builder": return builder
	return null

func _get_marker_node(marker_name: String) -> Marker2D:
	match marker_name:
		"Marker_SentryPost": return marker_sentry
		"Marker_MainGate": return marker_main_gate
		"Marker_Cave": return marker_cave
		"Marker_Docks": return marker_docks
		"Marker_Builders": return marker_builders
		"Marker_Archers": return marker_archers
		"Marker_Warriors": return marker_warriors
		"Marker_Bell": return marker_bell
	return null

func _move_character_to(character: CharacterBody2D, target_pos: Vector2, duration: float, follow_camera: bool = true) -> void:
	if not character:
		return

	# Smooth camera follow and zoom in on moving character
	if follow_camera and camera:
		_move_camera_to(target_pos, Vector2(0.85, 0.85), duration * 0.9)

	var tween = create_tween()
	var spr = character.get_node_or_null("PlayerSprite")
	if not spr:
		spr = character.get_node_or_null("Sprite2D")
	if spr:
		spr.flip_h = (target_pos.x < character.global_position.x)
	tween.tween_property(character, "global_position", target_pos, duration)
	await tween.finished

func _move_camera_to(target_pos: Vector2, target_zoom: Vector2, duration: float):
	if not camera:
		return
	var tween = create_tween().set_parallel(true)
	tween.tween_property(camera, "global_position", target_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "zoom", target_zoom, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished

func reset_simulation():
	for ch in initial_character_positions.keys():
		if ch:
			ch.global_position = initial_character_positions[ch]
			ch.visible = true
			var lbl: Label = ch.get_node_or_null("SpeechLabel")
			if lbl: lbl.text = ""

	if camera:
		_move_camera_to(initial_camera_pos, initial_camera_zoom, 0.5)

	_hide_all_defense_nodes()

	# Keep threat sprites hidden initially; they only appear when arriving/after fortification
	if threat_main_gate: threat_main_gate.visible = false
	if threat_cave: threat_cave.visible = false
	if threat_docks: threat_docks.visible = false

	if status_bar_label:
		status_bar_label.text = "Status: Ready (Configure environment/clues & Run)"
	is_simulating = false
	_set_ui_phase_prerun()

func _hide_all_defense_nodes():
	for def_parent in [defense_main_gate, defense_cave, defense_docks]:
		if def_parent:
			def_parent.visible = true
			for sub in def_parent.get_children():
				if sub is CanvasItem:
					sub.visible = false

# ==============================================================================
# UI SETUP & DEBUG INSPECTOR
# ==============================================================================

var btn_run: Button
var btn_reset: Button
var btn_f3: Button
var env_container: VBoxContainer

func _setup_control_panel():
	if not control_panel_container:
		return
	var viewport_size = get_viewport_rect().size
	control_panel_container.position = Vector2(20, max(20.0, viewport_size.y - 250.0))
	control_panel_container.size = Vector2(340, 220)

	var vb = VBoxContainer.new()
	control_panel_container.add_child(vb)

	var title = Label.new()
	title.text = "KINGDOM DEFENSE CONTROL"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.GOLD)
	vb.add_child(title)

	vb.add_child(HSeparator.new())

	# Environment Options container
	env_container = VBoxContainer.new()
	vb.add_child(env_container)

	var lbl_env = Label.new()
	lbl_env.text = "Environment Condition:"
	env_container.add_child(lbl_env)

	var opt_env = OptionButton.new()
	opt_env.add_item("Clear Weather (Normal Prior)")
	opt_env.add_item("Night Time (Darkness Boosts Cave)")
	opt_env.add_item("Foggy Horizon (Low Vision Boosts Gate)")
	opt_env.add_item("Rain & Storm (Waves Boost Docks)")
	opt_env.item_selected.connect(func(idx):
		match idx:
			0: apply_environment("Clear")
			1: apply_environment("Night")
			2: apply_environment("Foggy")
			3: apply_environment("Rain")
	)
	env_container.add_child(opt_env)

	# Action Buttons
	btn_run = Button.new()
	btn_run.text = "RUN SIMULATION"
	btn_run.custom_minimum_size = Vector2(0, 36)
	btn_run.pressed.connect(run_simulation)
	vb.add_child(btn_run)

	var post_run_hb = HBoxContainer.new()
	vb.add_child(post_run_hb)

	btn_reset = Button.new()
	btn_reset.text = "RESET"
	btn_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reset.custom_minimum_size = Vector2(0, 36)
	btn_reset.pressed.connect(reset_simulation)
	post_run_hb.add_child(btn_reset)

	btn_f3 = Button.new()
	btn_f3.text = "SHOW REASONING OVERLAY (F3)"
	btn_f3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_f3.custom_minimum_size = Vector2(0, 36)
	btn_f3.pressed.connect(toggle_debug_overlay)
	post_run_hb.add_child(btn_f3)

	status_bar_label = Label.new()
	status_bar_label.text = "Status: Ready"
	status_bar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_bar_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	vb.add_child(status_bar_label)

	_set_ui_phase_prerun()

func _set_ui_phase_prerun():
	if control_panel_container: control_panel_container.visible = true
	if env_container: env_container.visible = true
	if btn_run: btn_run.visible = true
	if btn_reset: btn_reset.visible = false
	if btn_f3: btn_f3.visible = false
	if debug_overlay_container: debug_overlay_container.visible = false
	_set_threat_widgets_visible(true)

func _set_ui_phase_running():
	if control_panel_container: control_panel_container.visible = false
	if debug_overlay_container: debug_overlay_container.visible = false
	_set_threat_widgets_visible(false)

func _set_ui_phase_postrun():
	if control_panel_container: control_panel_container.visible = true
	if env_container: env_container.visible = false
	if btn_run: btn_run.visible = false
	if btn_reset: btn_reset.visible = true
	if btn_f3: btn_f3.visible = true
	_set_threat_widgets_visible(false)

func _setup_debug_overlay():
	if not debug_overlay_container:
		return
	debug_overlay_container.position = Vector2(400, 20)
	debug_overlay_container.size = Vector2(800, 560)
	debug_overlay_container.visible = false

	var vb = VBoxContainer.new()
	debug_overlay_container.add_child(vb)

	var header_hb = HBoxContainer.new()
	vb.add_child(header_hb)

	var title = Label.new()
	title.text = "AI REASONING INSPECTOR (Tubes Tahap 4 Multi-Agent)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.ORANGE)
	header_hb.add_child(title)

	var btn_close = Button.new()
	btn_close.text = " X "
	btn_close.pressed.connect(func(): debug_overlay_container.visible = false)
	header_hb.add_spacer(false)
	header_hb.add_child(btn_close)

	dbg_tab_container = TabContainer.new()
	dbg_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(dbg_tab_container)

	# Tab 1: Bayes & MEU
	var tab_bayes = VBoxContainer.new()
	tab_bayes.name = "1. Bayes & MEU"
	dbg_tab_container.add_child(tab_bayes)

	dbg_bayes_label = RichTextLabel.new()
	dbg_bayes_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dbg_bayes_label.bbcode_enabled = true
	dbg_bayes_label.text = "[color=yellow]Jalankan simulasi untuk melihat kalkulasi probabilitas Bayes tiap pos...[/color]"
	tab_bayes.add_child(dbg_bayes_label)

	# Tab 2: KB Resolution
	var tab_kb = VBoxContainer.new()
	tab_kb.name = "2. Logic KB (Resolution)"
	dbg_tab_container.add_child(tab_kb)

	dbg_kb_label = RichTextLabel.new()
	dbg_kb_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dbg_kb_label.bbcode_enabled = true
	dbg_kb_label.text = "[color=yellow]Jalankan simulasi untuk melihat pohon resolusi pembuktian perintah Raja...[/color]"
	tab_kb.add_child(dbg_kb_label)

	# Tab 3: PDDL Planning
	var tab_pddl = VBoxContainer.new()
	tab_pddl.name = "3. PDDL King Plan"
	dbg_tab_container.add_child(tab_pddl)

	dbg_pddl_label = RichTextLabel.new()
	dbg_pddl_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dbg_pddl_label.bbcode_enabled = true
	dbg_pddl_label.text = "[color=yellow]Jalankan simulasi untuk melihat tabel urutan aksi mobilisasi pasukan PDDL...[/color]"
	tab_pddl.add_child(dbg_pddl_label)

func _update_debug_text_views():
	# 1. Update Bayes & MEU View
	if dbg_bayes_label and last_assessment:
		var txt = "[b][color=cyan]=== MULTI-POST BAYESIAN THREAT EVALUATION ===[/color][/b]\n"
		txt += "Active Environment: [b][color=yellow]%s[/color][/b]\n\n" % last_assessment.environment
		for post in ["MainGate", "Cave", "Docks"]:
			var b = last_assessment.beliefs[post]
			var col = "red" if b.is_confirmed else "green"
			txt += "[b]%s:[/b] Clue=[color=yellow]'%s'[/color] | Posterior P(Threat|E)=[b][color=%s]%.1f%%[/color][/b] -> Status: [color=%s]%s[/color]\n" % [
				post, b.clue_name, col, b.posterior * 100.0, col, "HIGH THREAT" if b.is_confirmed else "SAFE"
			]
			txt += "   Formula: %s\n\n" % b.calculation_text

		txt += "[b][color=cyan]=== MAXIMUM EXPECTED UTILITY (MEU) TROOP ALLOCATION ===[/color][/b]\n"
		txt += "Defense Priority Order: [b][color=orange]%s[/color][/b]\n\n" % " > ".join(last_assessment.priority_order)
		for post in ["MainGate", "Cave", "Docks"]:
			var assigned_troops = last_assessment.post_troop_assignments.get(post, [])
			var threat_status = "CONFIRMED" if last_assessment.beliefs[post].is_confirmed else "SAFE"
			if assigned_troops.is_empty():
				txt += "  -> [color=yellow]%s[/color] (%s): [color=gray]No Troops Deployed (Idle)[/color]\n" % [post, threat_status]
			else:
				txt += "  -> [color=yellow]%s[/color] (%s): [b][color=green]%s[/color][/b] (Count: %d)\n" % [
					post, threat_status, " & ".join(assigned_troops), assigned_troops.size()
				]
		dbg_bayes_label.text = txt

	# 2. Update KB View
	if dbg_kb_label and last_kb_proofs:
		var txt = "[b][color=cyan]=== KNOWLEDGE BASE RESOLUTION REFUTATION ===[/color][/b]\n"
		txt += "Decoupled Rules: [color=yellow]res://data/kingdom_defense_rules.json[/color]\n\n"
		for k in last_kb_proofs.keys():
			var prf = last_kb_proofs[k]
			txt += "[b]Query:[/b] Prove [color=yellow]%s[/color] -> Result: %s (Time: %.2f ms)\n" % [
				prf.query,
				"[color=green]PROVED[/color]" if prf.is_proved else "[color=gray]NOT PROVED[/color]",
				prf.execution_time_ms
			]
			if prf.is_proved and not prf.steps.is_empty():
				txt += "  Derivation (First & Last Steps):\n"
				txt += "    " + prf.steps[0].to_display_string() + "\n"
				if prf.steps.size() > 1:
					txt += "    ...\n"
					txt += "    " + prf.steps[prf.steps.size() - 1].to_display_string() + "\n"
			txt += "\n"
		dbg_kb_label.text = txt

	# 3. Update PDDL View
	if dbg_pddl_label and last_pddl_result:
		var txt = "[b][color=cyan]=== PDDL KING ACTION PLAN (FORWARD STATE-SPACE) ===[/color][/b]\n"
		txt += "Status: %s (Steps: %d, States Explored: %d, Time: %.2f ms)\n\n" % [
			"[color=green]SUCCESS[/color]" if last_pddl_result.is_success else "[color=red]FAILED[/color]",
			last_pddl_result.plan_actions.size(),
			last_pddl_result.visited_states_count,
			last_pddl_result.execution_time_ms
		]
		txt += "[b]Goal Conditions:[/b] " + str(last_pddl_result.goal_state) + "\n\n"
		txt += "[b]Mobilization Sequence:[/b]\n"
		for i in range(last_pddl_result.plan_actions.size()):
			var a = last_pddl_result.plan_actions[i]
			txt += "  [b]%d. %s[/b]\n" % [i + 1, a.to_action_string()]
		dbg_pddl_label.text = txt
