@tool
class_name Viewport2DTracker
extends Node

signal peer_viewport_2d_updated(peer_id: int, world_rect: Rect2, world_center: Vector2, zoom: float)
signal peer_cursor_2d_updated(peer_id: int, world_pos: Vector2, is_active: bool)
signal redraw_requested()

const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")

var network: CoopNetwork
var editor_interface: EditorInterface

var _last_center: Vector2 = Vector2.ZERO
var _last_zoom: float = 0.0
var _last_size: Vector2 = Vector2.ZERO
var _viewport_update_timer: float = 0.0

var _last_mouse_world: Vector2 = Vector2(-99999, -99999)
var _last_mouse_active: bool = false
var _mouse_update_timer: float = 0.0

# Dictionary of peer_id -> Dictionary:
# { "world_rect": Rect2, "world_center": Vector2, "zoom": float }
var peer_viewports: Dictionary = {}

# Dictionary of peer_id -> Dictionary:
# { "current_pos": Vector2, "target_pos": Vector2, "opacity": float, "is_active": bool }
var peer_cursors: Dictionary = {}

func setup(p_network: CoopNetwork, p_editor_interface: EditorInterface) -> void:
	network = p_network
	editor_interface = p_editor_interface
	if network:
		if not network.viewport_2d_received.is_connected(_on_peer_viewport_received):
			network.viewport_2d_received.connect(_on_peer_viewport_received)
		if not network.cursor_2d_received.is_connected(_on_peer_cursor_received):
			network.cursor_2d_received.connect(_on_peer_cursor_received)
		if not network.peer_disconnected_coop.is_connected(_on_peer_disconnected):
			network.peer_disconnected_coop.connect(_on_peer_disconnected)
		if not network.connection_status_changed.is_connected(_on_connection_status_changed):
			network.connection_status_changed.connect(_on_connection_status_changed)

func _process(delta: float) -> void:
	# 1. Viewport presence broadcast (~15 FPS)
	_viewport_update_timer += delta
	if _viewport_update_timer >= 0.066:
		_viewport_update_timer = 0.0
		_check_and_broadcast_viewport()

	# 2. Local mouse tracking & broadcast (~30 FPS)
	_mouse_update_timer += delta
	if _mouse_update_timer >= 0.033:
		_mouse_update_timer = 0.0
		_check_and_broadcast_cursor()

	# 3. Lerp remote collaborator cursors every frame for fluid 60+ FPS motion
	var needs_redraw: bool = false
	for pid in peer_cursors.keys():
		var cur = peer_cursors[pid]
		var old_pos: Vector2 = cur["current_pos"]
		var target_pos: Vector2 = cur["target_pos"]
		var old_op: float = cur["opacity"]
		var target_op: float = 1.0 if cur["is_active"] else 0.0

		cur["current_pos"] = old_pos.lerp(target_pos, clampf(delta * 24.0, 0.0, 1.0))
		cur["opacity"] = lerpf(old_op, target_op, clampf(delta * 14.0, 0.0, 1.0))

		if cur["current_pos"].distance_to(old_pos) > 0.01 or absf(cur["opacity"] - old_op) > 0.005:
			needs_redraw = true

	if needs_redraw:
		redraw_requested.emit()

func _check_and_broadcast_viewport() -> void:
	if network == null or not network.is_connected_to_session or editor_interface == null:
		return
		
	var vp = editor_interface.get_editor_viewport_2d()
	if vp == null:
		return
		
	var vp_size = Vector2(vp.size)
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
		
	var canvas_xform = vp.global_canvas_transform
	var zoom = canvas_xform.get_scale().x
	var inv_xform = canvas_xform.affine_inverse()
	
	var world_top_left = inv_xform * Vector2.ZERO
	var world_bottom_right = inv_xform * vp_size
	var world_size = world_bottom_right - world_top_left
	var world_rect = Rect2(world_top_left, world_size)
	var world_center = world_top_left + world_size * 0.5
	
	# Only broadcast if there has been noticeable movement or zoom
	if world_center.distance_to(_last_center) > 1.0 or absf(zoom - _last_zoom) > 0.005 or vp_size != _last_size:
		_last_center = world_center
		_last_zoom = zoom
		_last_size = vp_size
		network.send_2d_viewport(world_rect, world_center, zoom)

func _check_and_broadcast_cursor() -> void:
	if network == null or not network.is_connected_to_session or editor_interface == null:
		if _last_mouse_active:
			_last_mouse_active = false
		return

	# Requirement 1: Only when window has focus to Godot
	var is_focused = DisplayServer.window_is_focused()

	# Requirement 2: Only when mouse is inside 2D canvas viewport and NOT in the Godot UI
	var vp = editor_interface.get_editor_viewport_2d()
	var vp_container = (vp.get_parent() as Control) if vp else null
	var is_in_canvas = false
	var mouse_screen_pos = Vector2.ZERO
	var canvas_rect = Rect2()

	var base_ctrl = editor_interface.get_base_control()
	if base_ctrl and vp and vp_container and vp_container.is_visible_in_tree():
		canvas_rect = vp_container.get_global_rect()
		mouse_screen_pos = base_ctrl.get_global_mouse_position()
		if canvas_rect.has_point(mouse_screen_pos):
			is_in_canvas = true

	# Requirement 3: Only when a scene is open
	var root = editor_interface.get_edited_scene_root()
	var has_scene = root != null and not root.scene_file_path.is_empty()

	var is_active = is_focused and is_in_canvas and has_scene

	if not is_active:
		if _last_mouse_active:
			_last_mouse_active = false
			network.send_2d_cursor(_last_mouse_world, false)
		return

	var local_mouse = mouse_screen_pos - canvas_rect.position
	var canvas_xform = vp.global_canvas_transform
	var world_mouse = canvas_xform.affine_inverse() * local_mouse
	var zoom = canvas_xform.get_scale().x

	var threshold = 1.5 / maxf(zoom, 0.01)
	if not _last_mouse_active or world_mouse.distance_to(_last_mouse_world) > threshold:
		_last_mouse_world = world_mouse
		_last_mouse_active = true
		network.send_2d_cursor(world_mouse, true)

func _on_peer_viewport_received(peer_id: int, world_rect: Rect2, world_center: Vector2, zoom: float) -> void:
	peer_viewports[peer_id] = {
		"world_rect": world_rect,
		"world_center": world_center,
		"zoom": zoom
	}
	peer_viewport_2d_updated.emit(peer_id, world_rect, world_center, zoom)

func _on_peer_cursor_received(peer_id: int, world_pos: Vector2, is_active: bool) -> void:
	if not peer_cursors.has(peer_id):
		peer_cursors[peer_id] = {
			"current_pos": world_pos,
			"target_pos": world_pos,
			"opacity": 1.0 if is_active else 0.0,
			"is_active": is_active
		}
	else:
		var cur = peer_cursors[peer_id]
		cur["target_pos"] = world_pos
		cur["is_active"] = is_active
		# Snap position if cursor was previously inactive/invisible
		if cur["opacity"] <= 0.01 and is_active:
			cur["current_pos"] = world_pos

	peer_cursor_2d_updated.emit(peer_id, world_pos, is_active)
	redraw_requested.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_viewports.has(peer_id):
		peer_viewports.erase(peer_id)
	if peer_cursors.has(peer_id):
		peer_cursors.erase(peer_id)
	redraw_requested.emit()

func _on_connection_status_changed(is_connected: bool, _is_host: bool, _msg: String) -> void:
	if not is_connected:
		peer_viewports.clear()
		peer_cursors.clear()
		_last_mouse_active = false
		redraw_requested.emit()
