class_name ReelItem
extends Control

## Displays a single character card within the vertical rolling RNG reel

@onready var icon_rect: TextureRect = $Icon
@onready var aura_rect: TextureRect = $Aura
@onready var chance_label: Label = $ChanceLabel
@onready var name_label: Label = $NameLabel

var character_data: Dictionary = {}
var tier_data: Dictionary = {}

var _is_centered: bool = false
var _aura_rot_speed: float = 1.8

static var _cached_aura_tex: Texture2D = null

static func load_texture_safe(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

static func load_audio_safe(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			var bytes = f.get_buffer(f.get_length())
			if bytes.size() > 44:
				var wav = AudioStreamWAV.new()
				wav.format = AudioStreamWAV.FORMAT_16_BITS
				wav.mix_rate = 44100
				wav.stereo = false
				var data_pos = 44
				for i in range(12, bytes.size() - 8):
					if bytes[i] == 100 and bytes[i+1] == 97 and bytes[i+2] == 116 and bytes[i+3] == 97: # 'data'
						data_pos = i + 8
						break
				wav.data = bytes.slice(data_pos)
				return wav
	return null

static func get_aura_texture() -> Texture2D:
	if _cached_aura_tex == null:
		_cached_aura_tex = load_texture_safe("res://ui/aura_starburst.png")
	return _cached_aura_tex

func _ready() -> void:
	pivot_offset = size * 0.5
	if aura_rect:
		aura_rect.pivot_offset = aura_rect.size * 0.5
		if aura_rect.texture == null:
			aura_rect.texture = get_aura_texture()

func set_character(char_data: Dictionary, t_data: Dictionary) -> void:
	character_data = char_data
	tier_data = t_data

	# Character sprite
	var img_path = char_data.get("image", "")
	var tex = load_texture_safe(img_path)
	if tex:
		icon_rect.texture = tex
	
	# Chance Text (e.g. 1 / 32)
	var chance_val = char_data.get("chance", 1)
	chance_label.text = "1 / %d" % chance_val

	# Name Text
	name_label.text = char_data.get("name", "Unknown")

	# Tier Color Styling
	var t_color = Color(tier_data.get("color", "#FFFFFF"))
	var glow_col = Color(tier_data.get("glow_color", "#FFFFFF"))

	name_label.modulate = Color.WHITE
	chance_label.modulate = t_color
	if aura_rect:
		if aura_rect.texture == null:
			aura_rect.texture = get_aura_texture()
		aura_rect.modulate = glow_col
		var aura_scale_mult = float(tier_data.get("aura_scale", 1.2))
		aura_rect.scale = Vector2(aura_scale_mult, aura_scale_mult)

func update_focus(focus_ratio: float, delta: float = 0.0) -> void:
	# focus_ratio is 1.0 when perfectly centered, down to 0.0 when 200+ px away
	var target_scale_val = lerpf(0.65, 1.6, ease(focus_ratio, 0.5))
	scale = Vector2(target_scale_val, target_scale_val)

	# Fades to 0.0 when far from center so items disappear smoothly without hard clipping
	var target_alpha = lerpf(0.0, 1.0, ease(focus_ratio, 0.35))
	modulate.a = target_alpha

	# Rotate aura and control its brightness
	if aura_rect:
		if focus_ratio > 0.25:
			aura_rect.visible = true
			aura_rect.modulate.a = lerpf(0.0, 0.95, (focus_ratio - 0.25) / 0.75)
			if delta > 0.0:
				aura_rect.rotation += _aura_rot_speed * delta
		else:
			aura_rect.visible = false

func play_winner_pop() -> void:
	# Extra juicy punch when final winner is locked
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.9, 1.9), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(name_label, "modulate", Color(1.4, 1.4, 1.1), 0.12)
	
	tween.chain().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.6, 1.6), 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(name_label, "modulate", Color.WHITE, 0.28)
