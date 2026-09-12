class_name NpcCharacter
extends Node2D

## World NPC representation of a rolled character (stationary, no AI, no collision)
## Shows unclipped white outline and billboard-style zoom-resistant detail card on mouse hover.

@export var character_scale: float = 1.7
const PADDING: int = 4

@onready var sprite: Sprite2D = $Sprite2D
@onready var hover_area: Area2D = $HoverArea
@onready var detail_card: PanelContainer = $DetailCard
@onready var name_label: Label = $DetailCard/Margin/VBox/NameLabel
@onready var rarity_label: Label = $DetailCard/Margin/VBox/RarityChanceHBox/RarityLabel
@onready var chance_label: Label = $DetailCard/Margin/VBox/RarityChanceHBox/ChanceLabel
@onready var action_hint_label: Label = $DetailCard/Margin/VBox/ActionHintLabel

@onready var footstep_player: AudioStreamPlayer2D = $FootstepAudio if has_node("FootstepAudio") else null

var footstep_sounds: Array[AudioStream] = [
	preload("res://audio/sfx/grass_step_1.wav"),
	preload("res://audio/sfx/grass_step_2.wav"),
	preload("res://audio/sfx/grass_step_3.wav"),
	preload("res://audio/sfx/grass_step_4.wav")
]
var last_footstep_index: int = -1
var step_distance_threshold: float = 40.0
var distance_accumulated: float = 0.0
var step_cooldown: float = 0.0
const MAX_AUDIBLE_DIST: float = 650.0

var character_data: Dictionary = {}
var tier_data: Dictionary = {}

var _base_sprite_y: float = 16.0
var _orig_h: float = 40.0
var _idle_timer: float = 0.0
var _anim_speed: float = 3.0
var _bob_height: float = 2.0

var _is_hovered: bool = false
var _area_hovered: bool = false
var _card_tween: Tween = null
var _outline_material: ShaderMaterial = null

@onready var ground_map_layer: TileMapLayer = $"../../Ground" if has_node("../../Ground") else get_node_or_null("../Ground")
@onready var deco_ground_map_layer: TileMapLayer = $"../../Deco_Ground" if has_node("../../Deco_Ground") else get_node_or_null("../Deco_Ground")
@onready var obstacle_map_layer: TileMapLayer = $"../../Obstacles" if has_node("../../Obstacles") else get_node_or_null("../Obstacles")
@onready var path_debug: Node2D = $"../../PathDebug" if has_node("../../PathDebug") else get_node_or_null("../PathDebug")

var current_path: Array[Vector2] = []
var wander_timer: float = 0.0
@export var move_speed: float = 120.0

var is_following: bool = false
var follow_target: Node2D = null
var follow_repath_timer: float = 0.0
var follow_is_repathing: bool = false

## Loads a character sprite with transparent padding on all sides
## so the outline shader is never clipped at the image edges.
static func load_texture_padded(path: String, padding: int = 4) -> Texture2D:
	var img: Image = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			img = res.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(path)

	if img != null and not img.is_empty():
		var w = img.get_width()
		var h = img.get_height()
		# Create a padded image with transparent borders
		var padded = Image.create(w + padding * 2, h + padding * 2, false, Image.FORMAT_RGBA8)
		padded.fill(Color(0, 0, 0, 0))
		img.convert(Image.FORMAT_RGBA8)
		padded.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(padding, padding))
		return ImageTexture.create_from_image(padded)

	return null

func _ready() -> void:
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Initialize footstep audio player
	if footstep_player == null:
		if has_node("FootstepAudio"):
			footstep_player = $FootstepAudio as AudioStreamPlayer2D
		else:
			footstep_player = AudioStreamPlayer2D.new()
			footstep_player.name = "FootstepAudio"
			add_child(footstep_player)

	footstep_player.volume_db = -16.0
	footstep_player.max_polyphony = 2
	footstep_player.max_distance = 600.0
	footstep_player.attenuation = 1.5
	footstep_player.panning_strength = 1.0

	var vp = get_viewport()
	if vp:
		vp.audio_listener_enable_2d = true

	# Initialize unique white outline shader material on sprite
	var outline_shader = preload("res://white_outline.gdshader")
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = outline_shader
	_outline_material.set_shader_parameter("enabled", false)
	_outline_material.set_shader_parameter("outline_color", Color(1.0, 1.0, 1.0, 1.0))
	_outline_material.set_shader_parameter("outline_width", 1.0)

	if sprite:
		_base_sprite_y = sprite.position.y
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.material = _outline_material

	# Setup hover area connections
	if hover_area:
		if not hover_area.mouse_entered.is_connected(_on_mouse_entered):
			hover_area.mouse_entered.connect(_on_mouse_entered)
		if not hover_area.mouse_exited.is_connected(_on_mouse_exited):
			hover_area.mouse_exited.connect(_on_mouse_exited)

	# DetailCard initially hidden
	if detail_card:
		detail_card.visible = false
		detail_card.modulate.a = 0.0

	# Add to groups
	add_to_group("npcs")
	add_to_group("characters")

	# Small random phase offset so multiple NPCs don't bob in sync
	_idle_timer = randf() * TAU
	wander_timer = randf_range(1.0, 3.0)

	# Spawn pop-in bounce animation from feet
	scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_hovered:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			toggle_follow()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			get_viewport().set_input_as_handled()
			remove_npc()

func _exit_tree() -> void:
	if is_following:
		is_following = false
		if path_debug != null and path_debug.has_method("on_npc_follow_changed"):
			path_debug.on_npc_follow_changed(self, false)
		elif path_debug != null and path_debug.has_method("reset_ucs_animation"):
			path_debug.reset_ucs_animation()

func toggle_follow() -> void:
	is_following = not is_following
	current_path.clear()
	follow_is_repathing = false
	if is_following:
		# Ensure only this NPC is following
		for other in get_tree().get_nodes_in_group("npcs"):
			if other != self and is_instance_valid(other) and other.get("is_following") == true:
				other.set("is_following", false)
				other.set("follow_target", null)
				other.set("wander_timer", randf_range(1.5, 3.5))
				if other.has_method("_update_action_hint"):
					other._update_action_hint()

		follow_target = _get_active_player()
		follow_repath_timer = 0.0
		if path_debug != null and path_debug.has_method("on_npc_follow_changed"):
			path_debug.on_npc_follow_changed(self, true)
	else:
		follow_target = null
		wander_timer = randf_range(1.5, 3.5)
		if path_debug != null and path_debug.has_method("on_npc_follow_changed"):
			path_debug.on_npc_follow_changed(self, false)
		elif path_debug != null and path_debug.has_method("reset_ucs_animation"):
			path_debug.reset_ucs_animation()
	_update_action_hint()

func remove_npc() -> void:
	if not is_inside_tree():
		return
	_is_hovered = false
	if _outline_material:
		_outline_material.set_shader_parameter("enabled", false)
	if detail_card:
		detail_card.visible = false

	# If this NPC was following, cleanly notify path_debug to hide UCS debugger
	if is_following:
		is_following = false
		if path_debug != null and path_debug.has_method("on_npc_follow_changed"):
			path_debug.on_npc_follow_changed(self, false)
		elif path_debug != null and path_debug.has_method("reset_ucs_animation"):
			path_debug.reset_ucs_animation()

	# Remove from CharacterManager if present
	var char_id = character_data.get("id", character_data.get("name", "").to_lower())
	if char_id != "":
		var cm = get_node_or_null("/root/CharacterManager")
		if cm and cm.has_method("remove_character"):
			cm.remove_character(char_id)

	# Play pop sound if available
	if ResourceLoader.exists("res://audio/sfx/hover_pop.wav"):
		var snd = AudioStreamPlayer2D.new()
		snd.stream = load("res://audio/sfx/hover_pop.wav")
		snd.pitch_scale = 0.85
		var p = get_parent()
		if p:
			p.add_child(snd)
			snd.global_position = global_position
			snd.play()
			snd.finished.connect(snd.queue_free)

	# Quick pop-out shrink animation before freeing
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _get_active_player() -> Node2D:
	var tree = get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("players"):
		if p is Node2D and is_instance_valid(p):
			if p.get("is_active_character") == true:
				return p
	var players = tree.get_nodes_in_group("players")
	if players.size() > 0 and is_instance_valid(players[0]):
		return players[0] as Node2D
	return null

func _process_follow(delta: float) -> void:
	if follow_is_repathing:
		return

	if follow_target == null or not is_instance_valid(follow_target):
		follow_target = _get_active_player()
		if follow_target == null:
			return

	var dist_to_player: float = global_position.distance_to(follow_target.global_position)

	# If close enough to player (within ~72px / ~1 tile), stop and face player
	if dist_to_player <= 72.0:
		current_path.clear()
		follow_repath_timer = 0.0
		var diff_x: float = follow_target.global_position.x - global_position.x
		if diff_x < -2.0:
			if sprite:
				sprite.flip_h = true
		elif diff_x > 2.0:
			if sprite:
				sprite.flip_h = false
		return

	# Only compute UCS path if we don't currently have an active path to walk
	if current_path.is_empty():
		follow_repath_timer -= delta
		if follow_repath_timer <= 0.0:
			if obstacle_map_layer:
				var start_tile: Vector2i = obstacle_map_layer.local_to_map(
					obstacle_map_layer.to_local(global_position)
				)
				var target_tile: Vector2i = obstacle_map_layer.local_to_map(
					obstacle_map_layer.to_local(follow_target.global_position)
				)

				if start_tile != target_tile:
					var ground_layers: Array = []
					if ground_map_layer:
						ground_layers.append(ground_map_layer)
					if deco_ground_map_layer:
						ground_layers.append(deco_ground_map_layer)

					# UCS Debugger ONLY triggers for following NPC
					if is_following and path_debug != null and path_debug.get("is_ucs_debug_enabled") == true and path_debug.has_method("play_ucs_animation"):
						follow_is_repathing = true
						var debug_result: Dictionary = CustomUCS.find_path_debug(
							ground_layers,
							obstacle_map_layer,
							start_tile,
							target_tile
						)
						var ucs_path: Array[Vector2i] = debug_result.get("path", [])
						var debug_steps: Array = debug_result.get("steps", [])

						if ucs_path.size() > 1:
							var char_name: String = character_data.get("name", "NPC")
							var anim_completed: bool = await path_debug.play_ucs_animation(
								debug_steps,
								ucs_path,
								char_name
							)
							follow_is_repathing = false
							if not anim_completed or not is_following:
								return

							current_path.clear()
							for i in range(1, ucs_path.size()):
								var tile: Vector2i = ucs_path[i]
								var pixel_pos: Vector2 = obstacle_map_layer.to_global(
									obstacle_map_layer.map_to_local(tile)
								)
								current_path.append(pixel_pos)
							follow_repath_timer = 0.0
						else:
							follow_is_repathing = false
							follow_repath_timer = 0.5
					else:
						var ucs_path: Array[Vector2i] = CustomUCS.find_path(
							ground_layers,
							obstacle_map_layer,
							start_tile,
							target_tile
						)

						if ucs_path.size() > 1:
							current_path.clear()
							for i in range(1, ucs_path.size()):
								var tile: Vector2i = ucs_path[i]
								var pixel_pos: Vector2 = obstacle_map_layer.to_global(
									obstacle_map_layer.map_to_local(tile)
								)
								current_path.append(pixel_pos)
							follow_repath_timer = 0.0
						else:
							follow_repath_timer = 0.5

	# Move along path towards player
	if not current_path.is_empty():
		var target_pos: Vector2 = current_path[0]
		var to_target: Vector2 = target_pos - global_position
		var follow_speed: float = move_speed * 1.8
		var step_amount: float = follow_speed * delta

		if to_target.length() <= step_amount:
			global_position = target_pos
			current_path.pop_front()
		else:
			global_position += to_target.normalized() * step_amount
			if to_target.x < -1.0:
				if sprite:
					sprite.flip_h = true
			elif to_target.x > 1.0:
				if sprite:
					sprite.flip_h = false

func _physics_process(delta: float) -> void:
	if step_cooldown > 0.0:
		step_cooldown -= delta

	var prev_pos: Vector2 = global_position

	if is_following:
		_process_follow(delta)
	else:
		if not current_path.is_empty():
			var target_pos: Vector2 = current_path[0]
			var to_target: Vector2 = target_pos - global_position
			var step_amount: float = move_speed * delta

			if to_target.length() <= step_amount:
				global_position = target_pos
				current_path.pop_front()
				if current_path.is_empty():
					wander_timer = randf_range(2.0, 5.0)
			else:
				global_position += to_target.normalized() * step_amount
				if to_target.x < -1.0:
					if sprite:
						sprite.flip_h = true
				elif to_target.x > 1.0:
					if sprite:
						sprite.flip_h = false
		else:
			wander_timer -= delta
			if wander_timer <= 0.0:
				wander()

	# Footstep audio triggering for both wander and follow
	var moved_dist: float = prev_pos.distance_to(global_position)
	if moved_dist > 0.05:
		distance_accumulated += moved_dist
		if distance_accumulated >= step_distance_threshold and step_cooldown <= 0.0:
			play_footstep()
			distance_accumulated = 0.0
			step_cooldown = 0.18 if is_following else 0.28
	else:
		# Retain partial distance so restarting walk feels immediately responsive
		if distance_accumulated > step_distance_threshold * 0.5:
			distance_accumulated = step_distance_threshold * 0.5

func wander() -> void:
	if not obstacle_map_layer:
		return

	var start_tile: Vector2i = obstacle_map_layer.local_to_map(
		obstacle_map_layer.to_local(global_position)
	)

	var offset := Vector2i(randi_range(-4, 4), randi_range(-4, 4))
	if offset == Vector2i.ZERO:
		wander_timer = 1.0
		return

	var target_tile: Vector2i = start_tile + offset

	var ground_layers: Array = []
	if ground_map_layer:
		ground_layers.append(ground_map_layer)
	if deco_ground_map_layer:
		ground_layers.append(deco_ground_map_layer)

	# Wandering NPCs never trigger the debugger
	var ucs_path: Array[Vector2i] = CustomUCS.find_path(
		ground_layers,
		obstacle_map_layer,
		start_tile,
		target_tile
	)

	if ucs_path.size() <= 1:
		wander_timer = randf_range(1.0, 2.0)
		return

	current_path.clear()
	for i in range(1, ucs_path.size()):
		var tile: Vector2i = ucs_path[i]
		var pixel_pos: Vector2 = obstacle_map_layer.to_global(
			obstacle_map_layer.map_to_local(tile)
		)
		current_path.append(pixel_pos)

func _process(delta: float) -> void:
	# Subtle living idle/walk bobbing upwards from feet, pixel-snapped
	var is_moving := not current_path.is_empty()
	var anim_speed: float = (16.0 if is_following else 10.0) if is_moving else _anim_speed
	var bob_amt: float = (4.0 if is_following else 3.0) if is_moving else _bob_height

	_idle_timer += delta * anim_speed
	if sprite:
		sprite.position.y = _base_sprite_y - abs(round(sin(_idle_timer) * bob_amt))

	# Continuous mouse hover check (immune to camera zoom or physics picking quirks)
	_check_mouse_hover()

	# Keep detail card scale resistant to camera zoom (billboard UI behavior)
	if detail_card and detail_card.visible and not (_card_tween and _card_tween.is_valid()):
		_update_detail_card_transform()

func _get_billboard_scale() -> float:
	var cam_zoom: float = 1.0
	var vp = get_viewport()
	if vp:
		var cam = vp.get_camera_2d()
		if cam:
			cam_zoom = cam.zoom.x
		else:
			cam_zoom = vp.get_canvas_transform().get_scale().x

	if cam_zoom <= 0.0:
		cam_zoom = 1.0

	# Counter-scale when camera zooms out so text stays readable on screen
	return clamp(1.0 / cam_zoom, 1.0, 4)*1.3

func _update_detail_card_transform() -> void:
	if detail_card == null:
		return
	var b_scale = _get_billboard_scale()
	var head_top_y = _base_sprite_y - (_orig_h * character_scale)
	detail_card.scale = Vector2(b_scale, b_scale)
	detail_card.position.x = -detail_card.size.x * 0.5
	detail_card.position.y = head_top_y - detail_card.size.y - (14.0 * b_scale)
	detail_card.pivot_offset = Vector2(detail_card.size.x * 0.5, detail_card.size.y)

func _check_mouse_hover() -> void:
	var local_m = to_local(get_global_mouse_position())
	var b_scale = _get_billboard_scale()
	var half_w = 34.0 * (character_scale / 1.7) * (1.0 + (b_scale - 1.0) * 0.3)
	# Increased Y hover range upwards for easy hovering even when zoomed
	var top_y = _base_sprite_y - (_orig_h * character_scale) - (20.0 * b_scale)
	var bottom_y = _base_sprite_y + 8.0
	var is_inside = (local_m.x >= -half_w and local_m.x <= half_w and local_m.y >= top_y and local_m.y <= bottom_y)

	var should_hover = is_inside or _area_hovered
	if should_hover != _is_hovered:
		_is_hovered = should_hover
		_set_hover_state(_is_hovered)

func _set_hover_state(hovered: bool) -> void:
	if _outline_material:
		_outline_material.set_shader_parameter("enabled", hovered)
	if hovered:
		_show_detail_card()
	else:
		_hide_detail_card()

func _on_mouse_entered() -> void:
	_area_hovered = true

func _on_mouse_exited() -> void:
	_area_hovered = false

func setup(char_data: Dictionary, t_data: Dictionary = {}) -> void:
	character_data = char_data
	tier_data = t_data

	# 1. Setup padded Sprite texture (prevents outline clipping)
	var img_path = char_data.get("image", "")
	var tex = load_texture_padded(img_path, PADDING)
	_orig_h = 40.0
	if tex and sprite:
		sprite.texture = tex
		var padded_h = float(tex.get_height())
		_orig_h = max(20.0, padded_h - (PADDING * 2))
		# Anchor from bottom center: feet always stay at _base_sprite_y (y = 16)
		sprite.offset = Vector2(0.0, PADDING - (padded_h * 0.5))
		sprite.scale = Vector2(character_scale, character_scale)

	# 2. Get Tier Color
	var tier_name = char_data.get("tier", "Common")
	var tier_color_hex = tier_data.get("color", "")
	if tier_color_hex == "":
		match tier_name:
			"Common": tier_color_hex = "#CBD5E1"
			"Uncommon": tier_color_hex = "#4ADE80"
			"Rare": tier_color_hex = "#38BDF8"
			"Epic": tier_color_hex = "#C084FC"
			"Legendary": tier_color_hex = "#FBBF24"
			"Mythic": tier_color_hex = "#F43F5E"
			"Secret": tier_color_hex = "#EC4899"
			_: tier_color_hex = "#FFFFFF"

	var tier_col = Color(tier_color_hex)

	# 3. Populate Detail Card
	# Line 1: Name
	var char_name = char_data.get("name", "Unknown")
	if name_label:
		name_label.text = char_name
		name_label.modulate = tier_col

	# Line 2: Rarity (in tier color) + chance (in white)
	if rarity_label:
		rarity_label.text = tier_name
		rarity_label.modulate = tier_col

	if chance_label:
		var chance_val = char_data.get("chance", 1)
		chance_label.text = "1/%d" % chance_val
		chance_label.modulate = Color.WHITE

	# Line 3: Action hints (Right click follow/unfollow, Middle click to remove)
	_update_action_hint()

	# 4. Style Detail Card Panel
	if detail_card:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.08, 0.12, 0.94)
		sb.border_color = tier_col
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
		sb.shadow_size = 5
		detail_card.add_theme_stylebox_override("panel", sb)

		_update_detail_card_transform()

	# Randomly face left or right for variety
	if sprite and randf() > 0.5:
		sprite.flip_h = true

	queue_redraw()

func _update_action_hint() -> void:
	if action_hint_label:
		var follow_txt = "(Right click to unfollow)" if is_following else "(Right click to follow)"
		action_hint_label.text = "%s\n(Middle click to remove)" % follow_txt
		action_hint_label.modulate = Color(0.68, 0.74, 0.82, 0.9)
		_update_detail_card_transform()

func _show_detail_card() -> void:
	if detail_card == null:
		return
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()

	_update_action_hint()
	var b_scale = _get_billboard_scale()
	_update_detail_card_transform()
	detail_card.visible = true
	detail_card.scale = Vector2(b_scale * 0.88, b_scale * 0.88)

	_card_tween = create_tween().set_parallel(true)
	_card_tween.tween_property(detail_card, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_SINE)
	_card_tween.tween_property(detail_card, "scale", Vector2(b_scale, b_scale), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_detail_card() -> void:
	if detail_card == null:
		return
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()

	var b_scale = _get_billboard_scale()
	_card_tween = create_tween().set_parallel(true)
	_card_tween.tween_property(detail_card, "modulate:a", 0.0, 0.1).set_trans(Tween.TRANS_SINE)
	_card_tween.tween_property(detail_card, "scale", Vector2(b_scale * 0.92, b_scale * 0.92), 0.1).set_trans(Tween.TRANS_SINE)
	_card_tween.chain().tween_callback(func():
		if not _is_hovered and detail_card:
			detail_card.visible = false
	)

func _draw() -> void:
	# Ground shadow drawn directly under feet at y = 16
	var shadow_col = Color(0.0, 0.0, 0.0, 0.28)
	var center = Vector2(0, 16)
	var radius_x = 18.0 * (character_scale / 1.7)
	var radius_y = 6.5 * (character_scale / 1.7)
	var points: PackedVector2Array = []
	var segments = 16
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(points, shadow_col)

func play_footstep() -> void:
	if not is_inside_tree() or footstep_sounds.is_empty() or footstep_player == null:
		return

	# Don't play if too far from listener (camera / active player)
	var listener_pos := _get_listener_position()
	if global_position.distance_to(listener_pos) > MAX_AUDIBLE_DIST:
		return

	var idx: int = randi() % footstep_sounds.size()
	if idx == last_footstep_index and footstep_sounds.size() > 1:
		idx = (idx + 1) % footstep_sounds.size()
	last_footstep_index = idx

	footstep_player.stream = footstep_sounds[idx]
	footstep_player.pitch_scale = randf_range(0.92, 1.08)
	footstep_player.volume_db = -16.0 + randf_range(-1.0, 1.0)
	footstep_player.play()

func _get_listener_position() -> Vector2:
	var vp = get_viewport()
	if vp:
		var cam = vp.get_camera_2d()
		if cam and is_instance_valid(cam):
			return cam.global_position
	var p = _get_active_player()
	if p and is_instance_valid(p):
		return p.global_position
	return global_position
