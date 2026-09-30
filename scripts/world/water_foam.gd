class_name WaterFoam
extends Node2D

## Water Foam Manager
## Mengikuti panduan resmi Tiny Swords:
## Sprite Water Foam dirancang bekerja dengan konfigurasi yang sama seperti Shadow
## (efektif berukuran 128x128 pada grid 64x64 sehingga tepian buih overlap ~32px ke arah air).
## Karena kanvas bawaan 'Water Foam.png' adalah 192x192 dengan visual buih ~84px,
## skala default 1.5x (84 * 1.5 = 126px) memberikan overlap 31-32px persis seperti di panduan.

enum PlacementMode {
	COASTLINE_LAND,    ## Ditempatkan di tile daratan tepi pantai (overlap keluar ke arah air)
	SURROUNDING_WATER  ## Ditempatkan di tile air yang mengelilingi daratan
}

@export var foam_scale: float = 1.0
@export var animation_fps: float = 10.0
@export var placement_mode: PlacementMode = PlacementMode.COASTLINE_LAND
@export var ground_path: NodePath = NodePath("../Ground")
@export var deco_ground_path: NodePath = NodePath("../Deco_Ground")
@export var randomize_start_frame: bool = true
@export var auto_generate: bool = true
@export var foam_offset: Vector2 = Vector2.ZERO

var _sprite_frames: SpriteFrames = null
var _foam_texture: Texture2D = null

func _ready() -> void:
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if auto_generate:
		generate_foam()

func _ensure_resources() -> void:
	if _foam_texture == null:
		if ResourceLoader.exists("res://Tiny Swords (Free Pack)/Terrain/Tileset/Water Foam.png"):
			_foam_texture = load("res://Tiny Swords (Free Pack)/Terrain/Tileset/Water Foam.png") as Texture2D
		else:
			push_error("WaterFoam: 'Water Foam.png' not found!")
			return

	if _sprite_frames == null and _foam_texture != null:
		_sprite_frames = SpriteFrames.new()
		if not _sprite_frames.has_animation("default"):
			_sprite_frames.add_animation("default")
		_sprite_frames.clear("default")
		_sprite_frames.set_animation_speed("default", animation_fps)
		_sprite_frames.set_animation_loop("default", true)

		# Water Foam is 3072x192 with 16 frames of 192x192
		for i in range(16):
			var at := AtlasTexture.new()
			at.atlas = _foam_texture
			at.region = Rect2(i * 192, 0, 192, 192)
			_sprite_frames.add_frame("default", at)

func clear_foam() -> void:
	for child in get_children():
		child.queue_free()

func generate_foam() -> void:
	_ensure_resources()
	if _sprite_frames == null:
		push_error("WaterFoam: SpriteFrames could not be initialized.")
		return

	# Clear any previous foam sprites immediately
	for child in get_children():
		child.free()

	# Ensure any water obstacles at z_index > -1 don't occlude the foam
	var obstacle_layer: TileMapLayer = get_node_or_null(NodePath("../Obstacles")) as TileMapLayer
	if obstacle_layer == null and get_parent() != null:
		obstacle_layer = get_parent().get_node_or_null("Obstacles") as TileMapLayer
	if obstacle_layer and obstacle_layer.tile_set:
		var ts = obstacle_layer.tile_set
		for i in ts.get_source_count():
			var sid = ts.get_source_id(i)
			var src = ts.get_source(sid)
			if src is TileSetAtlasSource and src.texture:
				if "Water Background" in src.texture.resource_path:
					if ResourceLoader.exists("res://transparent_tile.png"):
						src.texture = load("res://transparent_tile.png")
					else:
						var img = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
						src.texture = ImageTexture.create_from_image(img)

	var ground_layer: TileMapLayer = get_node_or_null(ground_path) as TileMapLayer
	if ground_layer == null and get_parent() != null:
		ground_layer = get_parent().get_node_or_null("Ground") as TileMapLayer

	if ground_layer == null:
		push_error("WaterFoam: Ground TileMapLayer not found!")
		return

	var deco_layer: TileMapLayer = get_node_or_null(deco_ground_path) as TileMapLayer
	if deco_layer == null and get_parent() != null:
		deco_layer = get_parent().get_node_or_null("Deco_Ground") as TileMapLayer

	# 1. Collect all land tiles (Ground + Deco_Ground)
	var land_cells: Dictionary = {}
	for c in ground_layer.get_used_cells():
		land_cells[c] = true
	if deco_layer:
		for c in deco_layer.get_used_cells():
			land_cells[c] = true

	# 2. Check 8-way neighbors to identify boundary tiles
	var offsets := [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1,  0),                   Vector2i(1,  0),
		Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1)
	]

	var target_cells: Dictionary = {}

	if placement_mode == PlacementMode.COASTLINE_LAND:
		for cell in land_cells.keys():
			for offset in offsets:
				if not land_cells.has(cell + offset):
					target_cells[cell] = true
					break
	else:
		# PlacementMode.SURROUNDING_WATER:
		for cell in land_cells.keys():
			for offset in offsets:
				var neighbor: Vector2i = cell + offset
				if not land_cells.has(neighbor):
					target_cells[neighbor] = true

	var spawned_count := 0
	for cell in target_cells.keys():
		var asp := AnimatedSprite2D.new()
		asp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		asp.sprite_frames = _sprite_frames
		asp.animation = &"default"
		asp.scale = Vector2(foam_scale, foam_scale)
		
		# Align with center of grid cell
		var cell_world_pos: Vector2 = ground_layer.to_global(ground_layer.map_to_local(cell))
		asp.position = to_local(cell_world_pos) + foam_offset

		if randomize_start_frame:
			var random_frame: int = randi() % 16
			var random_progress: float = randf()
			asp.set_frame_and_progress(random_frame, random_progress)

		asp.play("default")
		add_child(asp)
		spawned_count += 1

	print("[WaterFoam] Successfully spawned %d animated foam sprites (mode: %s, scale: %.2f)." % [
		spawned_count,
		"COASTLINE_LAND" if placement_mode == PlacementMode.COASTLINE_LAND else "SURROUNDING_WATER",
		foam_scale
	])
