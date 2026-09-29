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
@export var camera_tween_duration: float = 3

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

var parallax_layers: Array[ParallaxLayer] = []
var camera: Camera2D
var _idle_time: float = 0.0
var sunrays_mat: ShaderMaterial

func _ready() -> void:
	camera = get_node_or_null("Camera2D")
	if camera:
		camera.position.y = camera_start_y
		var tw = create_tween()
		tw.tween_property(camera, "position:y", 0.0, camera_tween_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Ensure all background sprite layers start at (0, 0) to cover the full screen
	for child in get_children():
		if child is ParallaxBackground:
			for pl in child.get_children():
				if pl is ParallaxLayer:
					for sp in pl.get_children():
						if sp is Sprite2D:
							sp.centered = false

	_setup_flipped_y_mirror()
	_gather_parallax_layers(self)
	_setup_followed_npc()
	_setup_hud()
	_setup_player_avatar()
	_setup_bgm()
	_setup_now_playing()
	var s_rect = get_node_or_null("SunraysCanvas/SunraysRect")
	if s_rect and s_rect.material is ShaderMaterial:
		sunrays_mat = s_rect.material

func _setup_flipped_y_mirror() -> void:
	# Add vertically flipped mirror on the top (ceiling) for moving parallax layers
	for child in get_children():
		if child is ParallaxBackground:
			# Skip static background, lighting and mist
			if child.name in ["ParallaxBackground10", "ParallaxBackground9", "ParallaxBackground6"]:
				continue
			for pl in child.get_children():
				if pl is ParallaxLayer:
					var sp: Sprite2D = pl.get_node_or_null("Sprite2D")
					if sp and sp.texture:
						var tex_h: float = sp.texture.get_height()
						# Top flipped mirror (ceiling connects to ceiling)
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
func _setup_followed_npc() -> void:
	var npc_node: Sprite2D = get_node_or_null("NPCCharacter")
	if not npc_node:
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
			npc_node.texture = tex
			npc_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# Scale proportionally to fit standard battle character height (~150px)
			var tex_h: float = float(tex.get_height())
			var target_h: float = 150.0
			var s: float = target_h / tex_h if tex_h > 0.0 else 3.56
			npc_node.scale = Vector2(s, s)
			# Align feet precisely with platform ground surface (Y = 512.0)
			#npc_node.position.y = 512.0 - (tex_h * s * 0.5)
			print("[BattleStageNew] Loaded followed NPC texture: ", char_image_path)

func _setup_hud() -> void:
	var ally_hud: CharacterHUD = get_node_or_null("AllyHUD")
	var enemy_hud: CharacterHUD = get_node_or_null("EnemyHUD")
	
	if has_node("/root/BattleManager"):
		var bm = get_node("/root/BattleManager")
		var b_data: Dictionary = {}
		if bm.has_method("get_battle_data"):
			b_data = bm.get_battle_data()
		
		var p_fighter: Dictionary = b_data.get("player", {})
		var e_fighter: Dictionary = b_data.get("enemy", {})
		
		if ally_hud and not p_fighter.is_empty():
			var raw_p_name: String = p_fighter.get("name", "BOCCHI")
			var p_name: String = _clean_npc_name(raw_p_name)
			if p_name != "":
				ally_hud.set_character_name(p_name)
			var p_hp: int = p_fighter.get("hp", 100)
			var p_max_hp: int = p_fighter.get("max_hp", p_hp)
			ally_hud.set_hp(p_hp, p_max_hp, false)
			
			var p_stm: int = p_fighter.get("stamina", 100)
			var p_max_stm: int = p_fighter.get("max_stamina", p_stm)
			ally_hud.set_stamina(p_stm, p_max_stm, false)
		
		if enemy_hud and not e_fighter.is_empty():
			var e_name: String = e_fighter.get("name", "ENEMY")
			if e_name != "":
				enemy_hud.set_character_name(e_name)
			var e_hp: int = e_fighter.get("hp", 100)
			var e_max_hp: int = e_fighter.get("max_hp", e_hp)
			enemy_hud.set_hp(e_hp, e_max_hp, false)
			
			var e_stm: int = e_fighter.get("stamina", 100)
			var e_max_stm: int = e_fighter.get("max_stamina", e_stm)
			enemy_hud.set_stamina(e_stm, e_max_stm, false)

func _clean_npc_name(raw_name: String) -> String:
	var clean = raw_name.strip_edges()
	# If format is "Pawn & Bocchi" or "Avatar & Bocchi" or contains "&"
	if clean.contains("&"):
		var parts = clean.split("&")
		clean = parts[parts.size() - 1].strip_edges()
	# Also strip common prefixes like "Pawn / ", "Avatar / ", "Player / "
	for prefix in ["Pawn /", "Archer /", "Avatar /", "Player /", "Pawn -", "Archer -", "Avatar -", "Pawn", "Archer", "Avatar"]:
		if clean.begins_with(prefix + " "):
			clean = clean.substr(prefix.length() + 1).strip_edges()
	if clean.is_empty():
		clean = "BOCCHI"
	return clean

func _setup_player_avatar() -> void:
	var avatar_rect: TextureRect = get_node_or_null("CanvasLayer/PlayerAvatarUI/AvatarRect")
	if not avatar_rect:
		avatar_rect = get_node_or_null("CanvasLayer/PlayerAvatarUI/Frame/AvatarRect")
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
		var raw_name: String = str(p_data.get("name", ""))
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
			print("[BattleStageNew] Set player avatar to: ", avatar_path)

func _setup_bgm() -> void:
	var bgm_player: AudioStreamPlayer = get_node_or_null("BattleBGM")
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
	tw.tween_interval(1.0)
	tw.tween_property(np_ui, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.5)
	tw.tween_property(np_ui, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): np_ui.visible = false)
