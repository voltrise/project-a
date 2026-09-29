extends Control

signal attack_pressed
signal special_pressed
signal defense_pressed
signal item_pressed
signal action_chosen(action_name: String)

@onready var btn_attack: TextureButton = $AttackButton
@onready var btn_special: TextureButton = $SpecialButton
@onready var btn_item: TextureButton = $ItemButton
@onready var btn_defense: TextureButton = $DefenseButton

# Preloaded Audio Streams
const SFX_HOVER = preload("res://audio/sfx/btn_hover.wav")
const SFX_ATTACK = preload("res://audio/sfx/btn_click_attack.wav")
const SFX_SPECIAL = preload("res://audio/sfx/btn_click_special.wav")
const SFX_DEFENSE = preload("res://audio/sfx/btn_click_defense.wav")
const SFX_ITEM = preload("res://audio/sfx/btn_click_item.wav")

var _base_positions: Dictionary = {}
var _tweens: Dictionary = {}
var _is_animating_click: Dictionary = {}

func _ready() -> void:
	_setup_button(btn_attack, "attack", SFX_ATTACK, attack_pressed, _play_attack_effects)
	_setup_button(btn_special, "special", SFX_SPECIAL, special_pressed, _play_special_effects)
	_setup_button(btn_item, "item", SFX_ITEM, item_pressed, _play_item_effects)
	_setup_button(btn_defense, "defense", SFX_DEFENSE, defense_pressed, _play_defense_effects)

func _setup_button(btn: TextureButton, action_name: String, click_sfx: AudioStream, sig: Signal, custom_effects: Callable) -> void:
	if not btn:
		return
	
	btn.pivot_offset = btn.custom_minimum_size / 2.0
	_base_positions[btn] = btn.position
	_is_animating_click[btn] = false

	btn.mouse_entered.connect(func(): _on_button_hover(btn))
	btn.mouse_exited.connect(func(): _on_button_unhover(btn))
	btn.button_down.connect(func(): _on_button_down(btn))
	btn.button_up.connect(func(): _on_button_up(btn))
	btn.pressed.connect(func():
		_play_sfx(click_sfx, randf_range(0.96, 1.04))
		custom_effects.call(btn)
		sig.emit()
		action_chosen.emit(action_name)
	)

# ── Hover & Press Base Handling ────────────────────────────────────────

func _on_button_hover(btn: TextureButton) -> void:
	if _is_animating_click.get(btn, false):
		return
	_play_sfx(SFX_HOVER, randf_range(0.98, 1.05))
	btn.z_index = 10
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)

	_kill_tween(btn)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(btn, "scale", Vector2(1.15, 1.15), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position:y", base_pos.y - 4.0, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tweens[btn] = tw

func _on_button_unhover(btn: TextureButton) -> void:
	if _is_animating_click.get(btn, false):
		return
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)

	_kill_tween(btn)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position", base_pos, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "rotation", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		if not btn.is_hovered() and not _is_animating_click.get(btn, false):
			btn.z_index = 0
	)
	_tweens[btn] = tw

func _on_button_down(btn: TextureButton) -> void:
	if _is_animating_click.get(btn, false):
		return
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)

	_kill_tween(btn)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(btn, "scale", Vector2(0.92, 0.92), 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position:y", base_pos.y + 2.0, 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "modulate", Color(0.9, 0.9, 0.9, 1.0), 0.06)
	_tweens[btn] = tw

func _on_button_up(btn: TextureButton) -> void:
	if _is_animating_click.get(btn, false):
		return
	if btn.is_hovered():
		_on_button_hover(btn)
	else:
		_on_button_unhover(btn)

# ══════════════════════════════════════════════════════════════════════
#  SUPER JUICY & UNIQUE PER-ACTION CLICK ANIMATIONS
# ══════════════════════════════════════════════════════════════════════

# 1. ATTACK: Dramatic sword windup recoil + diagonal lunge slash thrust!
func _play_attack_effects(btn: TextureButton) -> void:
	_is_animating_click[btn] = true
	btn.z_index = 20
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	_kill_tween(btn)

	var tw = create_tween()
	
	# Phase 1: Pull back anticipation (coiling the sword strike)
	tw.tween_property(btn, "position", base_pos + Vector2(-18.0, 10.0), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", -0.45, 0.08).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(btn, "scale", Vector2(0.82, 1.28), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(btn, "modulate", Color(2.8, 2.2, 0.8), 0.08)

	# Phase 2: SLAM FORWARD THRUST (snappy razor slash!)
	tw.chain().tween_property(btn, "position", base_pos + Vector2(26.0, -18.0), 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", 0.35, 0.06).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(btn, "scale", Vector2(1.42, 0.72), 0.06).set_trans(Tween.TRANS_EXPO)

	# Phase 3: Recoil blade vibration
	tw.chain().tween_property(btn, "position", base_pos + Vector2(14.0, -10.0), 0.04)
	tw.tween_property(btn, "position", base_pos + Vector2(20.0, -14.0), 0.04)
	tw.tween_property(btn, "position", base_pos + Vector2(16.0, -12.0), 0.04)

	# Phase 4: Settle back with smooth spring
	var end_scale = Vector2(1.15, 1.15) if btn.is_hovered() else Vector2(1.0, 1.0)
	var end_pos = Vector2(base_pos.x, base_pos.y - 4.0) if btn.is_hovered() else base_pos
	var end_mod = Color(1.2, 1.2, 1.2) if btn.is_hovered() else Color.WHITE

	tw.chain().tween_property(btn, "position", end_pos, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", 0.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "scale", end_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "modulate", end_mod, 0.16)

	tw.chain().tween_callback(func():
		_is_animating_click[btn] = false
		if not btn.is_hovered():
			btn.z_index = 0
	)
	_tweens[btn] = tw

	# Spawn visual slash arc VFX
	var vfx := AttackSlashVFX.new()
	vfx.position = btn.pivot_offset
	btn.add_child(vfx)


# 2. SPECIAL: Energy implosion squeeze -> 1.58x DETONATION -> violent earthquake tremor!
func _play_special_effects(btn: TextureButton) -> void:
	_is_animating_click[btn] = true
	btn.z_index = 20
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	_kill_tween(btn)

	var tw = create_tween()
	
	# Phase 1: Energy Implosion squeeze (inhale)
	tw.tween_property(btn, "scale", Vector2(0.68, 0.68), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(btn, "modulate", Color(4.0, 0.6, 2.5), 0.09)
	tw.parallel().tween_property(btn, "rotation", -0.15, 0.09)

	# Phase 2: KABOOM! Explosive expansion pop
	tw.chain().tween_property(btn, "scale", Vector2(1.58, 1.58), 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", 0.12, 0.07)
	tw.parallel().tween_property(btn, "modulate", Color(3.5, 1.2, 2.0), 0.07)

	# Phase 3: Violent earthquake tremors (8 frames of high-frequency rumble)
	for i in range(8):
		var ox = randf_range(-9.0, 9.0)
		var oy = randf_range(-8.0, 8.0)
		tw.tween_property(btn, "position", base_pos + Vector2(ox, oy), 0.02)

	# Phase 4: Settle back with decay
	var end_scale = Vector2(1.15, 1.15) if btn.is_hovered() else Vector2(1.0, 1.0)
	var end_pos = Vector2(base_pos.x, base_pos.y - 4.0) if btn.is_hovered() else base_pos
	var end_mod = Color(1.2, 1.2, 1.2) if btn.is_hovered() else Color.WHITE

	tw.chain().tween_property(btn, "position", end_pos, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", 0.0, 0.15).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(btn, "scale", end_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "modulate", end_mod, 0.18)

	tw.chain().tween_callback(func():
		_is_animating_click[btn] = false
		if not btn.is_hovered():
			btn.z_index = 0
	)
	_tweens[btn] = tw

	# Spawn visual shockwave VFX
	var vfx := SpecialEnergyVFX.new()
	vfx.position = btn.pivot_offset
	btn.add_child(vfx)


# 3. DEFENSE: Authoritative Shield Parry & Steel Armor Ring (grounded, solid, zero goofy squash)
func _play_defense_effects(btn: TextureButton) -> void:
	_is_animating_click[btn] = true
	btn.z_index = 20
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	_kill_tween(btn)

	var tw = create_tween()
	
	# Phase 1: Firm Shield Brace (crisp micro-angle anticipation)
	tw.tween_property(btn, "scale", Vector2(0.92, 0.92), 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", -0.12, 0.05).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(btn, "modulate", Color(1.3, 2.8, 3.8), 0.05)

	# Phase 2: SOLID PARRY SNAP (authoritative shield thrust outward!)
	tw.chain().tween_property(btn, "scale", Vector2(1.26, 1.26), 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", 0.08, 0.06).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(btn, "modulate", Color(2.2, 3.8, 4.5), 0.06)

	# Phase 3: Steel Armor Reverberation (absorbing the impact: rapid horizontal steel shudder)
	for i in range(6):
		var ox = (1.0 if i % 2 == 0 else -1.0) * (4.5 - i * 0.7)
		tw.tween_property(btn, "position:x", base_pos.x + ox, 0.02)
	tw.tween_property(btn, "position:x", base_pos.x, 0.03)

	# Phase 4: Authoritative snap back to stance
	var end_scale = Vector2(1.15, 1.15) if btn.is_hovered() else Vector2(1.0, 1.0)
	var end_pos = Vector2(base_pos.x, base_pos.y - 4.0) if btn.is_hovered() else base_pos
	var end_mod = Color(1.2, 1.2, 1.2) if btn.is_hovered() else Color.WHITE

	tw.chain().tween_property(btn, "position", end_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "scale", end_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(btn, "modulate", end_mod, 0.15)

	tw.chain().tween_callback(func():
		_is_animating_click[btn] = false
		if not btn.is_hovered():
			btn.z_index = 0
	)
	_tweens[btn] = tw

	# Spawn crisp honeycomb shield barrier & deflection ricochet VFX
	var vfx := DefenseShieldVFX.new()
	vfx.position = btn.pivot_offset
	btn.add_child(vfx)


# 4. ITEM: Deep squish -> CORK POP 30px SKYWARD LAUNCH -> delicious cartoon jelly wobble!
func _play_item_effects(btn: TextureButton) -> void:
	_is_animating_click[btn] = true
	btn.z_index = 20
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	_kill_tween(btn)

	var tw = create_tween()
	
	# Phase 1: Squish down (Compression)
	tw.tween_property(btn, "scale", Vector2(1.50, 0.58), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "position:y", base_pos.y + 14.0, 0.08).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(btn, "modulate", Color(1.3, 3.5, 1.6), 0.08)

	# Phase 2: CORK POP! Skyward launch!
	tw.chain().tween_property(btn, "position:y", base_pos.y - 30.0, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "scale", Vector2(0.65, 1.60), 0.09).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(btn, "rotation", 0.28, 0.09)

	# Phase 3: Liquid jelly wobble oscillations
	tw.chain().tween_property(btn, "scale", Vector2(1.38, 0.74), 0.07).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(btn, "position:y", base_pos.y - 6.0, 0.07)
	tw.parallel().tween_property(btn, "rotation", -0.18, 0.07)

	tw.chain().tween_property(btn, "scale", Vector2(0.86, 1.22), 0.06).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(btn, "position:y", base_pos.y - 12.0, 0.06)
	tw.parallel().tween_property(btn, "rotation", 0.09, 0.06)

	tw.chain().tween_property(btn, "scale", Vector2(1.18, 0.90), 0.06).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(btn, "rotation", -0.04, 0.06)

	# Phase 4: Settle
	var end_scale = Vector2(1.15, 1.15) if btn.is_hovered() else Vector2(1.0, 1.0)
	var end_pos = Vector2(base_pos.x, base_pos.y - 4.0) if btn.is_hovered() else base_pos
	var end_mod = Color(1.2, 1.2, 1.2) if btn.is_hovered() else Color.WHITE

	tw.chain().tween_property(btn, "position", end_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "scale", end_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "rotation", 0.0, 0.12)
	tw.parallel().tween_property(btn, "modulate", end_mod, 0.15)

	tw.chain().tween_callback(func():
		_is_animating_click[btn] = false
		if not btn.is_hovered():
			btn.z_index = 0
	)
	_tweens[btn] = tw

	# Spawn visual potion sparkles VFX
	var vfx := ItemSparkleVFX.new()
	vfx.position = btn.pivot_offset
	btn.add_child(vfx)


func _kill_tween(btn: TextureButton) -> void:
	if _tweens.has(btn) and is_instance_valid(_tweens[btn]) and _tweens[btn].is_running():
		_tweens[btn].kill()

func _play_sfx(stream: AudioStream, pitch: float = 1.0) -> void:
	if not stream:
		return
	var asp := AudioStreamPlayer.new()
	asp.stream = stream
	asp.pitch_scale = pitch
	asp.bus = "Master"
	add_child(asp)
	asp.play()
	asp.finished.connect(asp.queue_free)


# ══════════════════════════════════════════════════════════════════════
#  PROCEDURAL VFX CANVAS ITEM CLASSES
# ══════════════════════════════════════════════════════════════════════

class AttackSlashVFX extends Node2D:
	var progress: float = 0.0
	var particles: Array = []
	
	func _ready() -> void:
		z_index = 25
		for i in range(12):
			var angle = -PI/4.0 + randf_range(-0.6, 0.6)
			if randf() > 0.5:
				angle += PI
			var spd = randf_range(90.0, 200.0)
			particles.append({
				"pos": Vector2.ZERO,
				"vel": Vector2(cos(angle), sin(angle)) * spd,
				"size": randf_range(3.0, 6.0),
				"color": Color(1.0, randf_range(0.75, 0.98), 0.2)
			})
		var tw = create_tween()
		tw.tween_property(self, "progress", 1.0, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(queue_free)
	
	func _process(delta: float) -> void:
		for p in particles:
			p["pos"] += p["vel"] * delta
			p["vel"] *= 0.90
		queue_redraw()
	
	func _draw() -> void:
		var alpha = 1.0 - progress
		var slash_len = lerp(25.0, 150.0, progress)
		var slash_width = lerp(8.0, 0.0, progress)
		var dir = Vector2(1, -1).normalized()
		var p1 = -dir * slash_len * 0.5
		var p2 = dir * slash_len * 0.5
		draw_line(p1, p2, Color(1.0, 0.85, 0.2, alpha * 0.95), slash_width + 5.0)
		draw_line(p1 * 0.85, p2 * 0.85, Color(1.0, 1.0, 0.9, alpha), slash_width)
		
		for p in particles:
			var c = p["color"]
			c.a = alpha
			draw_circle(p["pos"], p["size"] * (1.0 - progress * 0.5), c)
			draw_line(p["pos"], p["pos"] - p["vel"] * 0.04, c, p["size"] * 0.6)


class SpecialEnergyVFX extends Node2D:
	var progress: float = 0.0
	var particles: Array = []
	
	func _ready() -> void:
		z_index = 25
		for i in range(16):
			var angle = randf() * TAU
			var spd = randf_range(80.0, 220.0)
			particles.append({
				"pos": Vector2.ZERO,
				"vel": Vector2(cos(angle), sin(angle)) * spd,
				"size": randf_range(3.5, 7.0),
				"color": Color(1.0, randf_range(0.15, 0.45), randf_range(0.5, 0.95))
			})
		var tw = create_tween()
		tw.tween_property(self, "progress", 1.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(queue_free)
	
	func _process(delta: float) -> void:
		for p in particles:
			p["pos"] += p["vel"] * delta
			p["vel"] *= 0.88
		queue_redraw()
	
	func _draw() -> void:
		var alpha = 1.0 - progress
		var radius = lerp(15.0, 125.0, progress)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(1.0, 0.15, 0.35, alpha * 0.9), lerp(9.0, 1.0, progress))
		draw_arc(Vector2.ZERO, radius * 0.78, 0, TAU, 32, Color(1.0, 0.4, 0.9, alpha * 0.8), lerp(6.0, 0.5, progress))
		if progress < 0.35:
			var flash_a = (1.0 - progress / 0.35) * 0.8
			draw_circle(Vector2.ZERO, lerp(6.0, 45.0, progress / 0.35), Color(1.0, 0.85, 0.95, flash_a))
		
		for p in particles:
			var c = p["color"]
			c.a = alpha
			draw_circle(p["pos"], p["size"] * (1.0 - progress * 0.4), c)


class DefenseShieldVFX extends Node2D:
	var progress: float = 0.0
	var sparks: Array = []
	
	func _ready() -> void:
		z_index = 25
		# Ricochet deflection sparks flying off at high speed
		for i in range(12):
			var angle = randf_range(-PI * 0.75, PI * 0.75)
			var spd = randf_range(90.0, 220.0)
			sparks.append({
				"pos": Vector2.ZERO,
				"vel": Vector2(cos(angle), sin(angle)) * spd,
				"size": randf_range(3.0, 6.0),
				"color": Color(0.7, 0.95, 1.0)
			})
		var tw = create_tween()
		tw.tween_property(self, "progress", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(queue_free)
	
	func _process(delta: float) -> void:
		for s in sparks:
			s["pos"] += s["vel"] * delta
			s["vel"] *= 0.88
		queue_redraw()
	
	func _draw() -> void:
		var alpha = 1.0 - progress
		var r = lerp(16.0, 115.0, progress)
		
		# 1. Outer Electric Cyan Hexagonal Barrier
		var hex_points: PackedVector2Array = []
		for i in range(7):
			var a = i * (TAU / 6.0) - PI/6.0
			hex_points.append(Vector2(cos(a), sin(a)) * r)
		draw_polyline(hex_points, Color(0.2, 0.85, 1.0, alpha * 0.95), lerp(8.0, 1.0, progress))
		
		# 2. Concentric Inner Honeycomb Grid Lines
		var r_inner = r * 0.7
		var inner_points: PackedVector2Array = []
		for i in range(7):
			var a = i * (TAU / 6.0) - PI/6.0
			var pt = Vector2(cos(a), sin(a)) * r_inner
			inner_points.append(pt)
			# Spoke lines connecting inner to outer hexagon (energy mesh)
			draw_line(pt, hex_points[i], Color(0.5, 0.95, 1.0, alpha * 0.6), lerp(2.5, 0.5, progress))
		draw_polyline(inner_points, Color(0.5, 0.95, 1.0, alpha * 0.8), lerp(4.0, 0.8, progress))
		
		# 3. Central Forcefield Flare
		if progress < 0.4:
			var flare_a = (1.0 - progress / 0.4) * 0.6
			draw_circle(Vector2.ZERO, lerp(8.0, 40.0, progress / 0.4), Color(0.6, 0.95, 1.0, flare_a))
		
		# 4. Ricochet Sparks with Trailing Streaks
		for s in sparks:
			var c = s["color"]
			c.a = alpha
			draw_circle(s["pos"], s["size"] * (1.0 - progress * 0.5), c)
			draw_line(s["pos"], s["pos"] - s["vel"] * 0.05, c, s["size"] * 0.6)


class ItemSparkleVFX extends Node2D:
	var progress: float = 0.0
	var bubbles: Array = []
	
	func _ready() -> void:
		z_index = 25
		for i in range(14):
			bubbles.append({
				"pos": Vector2(randf_range(-28.0, 28.0), randf_range(-10.0, 20.0)),
				"vel_y": randf_range(-80.0, -160.0),
				"sway_speed": randf_range(4.0, 8.0),
				"sway_amp": randf_range(14.0, 32.0),
				"phase": randf() * TAU,
				"size": randf_range(3.0, 6.5),
				"color": Color(randf_range(0.3, 0.6), 1.0, randf_range(0.25, 0.55)),
				"is_cross": randf() > 0.5
			})
		var tw = create_tween()
		tw.tween_property(self, "progress", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(queue_free)
	
	func _process(delta: float) -> void:
		for b in bubbles:
			b["pos"].y += b["vel_y"] * delta
			b["phase"] += b["sway_speed"] * delta
			b["pos"].x += sin(b["phase"]) * b["sway_amp"] * delta
		queue_redraw()
	
	func _draw() -> void:
		var alpha = 1.0 - progress
		var aura_r = lerp(18.0, 105.0, progress)
		draw_circle(Vector2.ZERO, aura_r, Color(0.3, 1.0, 0.4, alpha * 0.25))
		draw_arc(Vector2.ZERO, aura_r, 0, TAU, 32, Color(0.6, 1.0, 0.5, alpha * 0.8), lerp(6.0, 0.8, progress))
		
		for b in bubbles:
			var c = b["color"]
			c.a = alpha
			var sz = b["size"] * (1.0 - progress * 0.3)
			if b["is_cross"]:
				draw_line(b["pos"] - Vector2(0, sz), b["pos"] + Vector2(0, sz), c, 2.5)
				draw_line(b["pos"] - Vector2(sz, 0), b["pos"] + Vector2(sz, 0), c, 2.5)
			else:
				draw_circle(b["pos"], sz, c)
				draw_circle(b["pos"] - Vector2(sz * 0.3, sz * 0.3), sz * 0.3, Color(1, 1, 1, alpha))
