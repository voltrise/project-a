@tool
class_name LiveCoopPlugin
extends EditorPlugin

const CoopDockScene = preload("res://addons/live_coop/ui/coop_dock.tscn")
const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")
const ScriptSyncManager = preload("res://addons/live_coop/editor/script_sync_manager.gd")
const Viewport2DTracker = preload("res://addons/live_coop/editor/viewport_2d_tracker.gd")
const ResSyncManager = preload("res://addons/live_coop/editor/res_sync_manager.gd")
const GithubService = preload("res://addons/live_coop/network/github_service.gd")
const FileSystemIndicatorManager = preload("res://addons/live_coop/editor/filesystem_indicator_manager.gd")
const SceneSyncManager = preload("res://addons/live_coop/editor/scene_sync_manager.gd")

var dock: CoopDock
var network: CoopNetwork
var script_sync_manager: ScriptSyncManager
var viewport_tracker: Viewport2DTracker
var res_sync_manager: ResSyncManager
var github_service: GithubService
var fs_indicator_manager: FileSystemIndicatorManager
var scene_sync_manager: SceneSyncManager

var show_2d_viewports: bool = true
var show_2d_cursors: bool = true

func _enter_tree() -> void:
	# 1. Enable force drawing over 2D and 3D editor viewports
	set_force_draw_over_forwarding_enabled()
	
	# 2. Instantiate isolated network node
	network = CoopNetwork.new()
	network.name = "LiveCoopNetwork"
	add_child(network)
	
	# 3. Instantiate and dock UI
	dock = CoopDockScene.instantiate()
	dock.name = "Live Co-Op"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# 4. Instantiate Subsystem Managers
	var editor_if = get_editor_interface()
	
	github_service = GithubService.new()
	github_service.name = "GithubService"
	add_child(github_service)
	
	script_sync_manager = ScriptSyncManager.new()
	script_sync_manager.name = "ScriptSyncManager"
	add_child(script_sync_manager)
	script_sync_manager.setup(network, editor_if.get_script_editor())
	
	viewport_tracker = Viewport2DTracker.new()
	viewport_tracker.name = "Viewport2DTracker"
	add_child(viewport_tracker)
	viewport_tracker.setup(network, editor_if)
	viewport_tracker.peer_viewport_2d_updated.connect(func(_id, _r, _c, _z): update_overlays())
	viewport_tracker.redraw_requested.connect(func(): update_overlays())
	
	res_sync_manager = ResSyncManager.new()
	res_sync_manager.name = "ResSyncManager"
	add_child(res_sync_manager)
	res_sync_manager.setup(network, editor_if, get_undo_redo())
	
	fs_indicator_manager = FileSystemIndicatorManager.new()
	fs_indicator_manager.name = "FileSystemIndicatorManager"
	add_child(fs_indicator_manager)
	fs_indicator_manager.setup(network, editor_if, self)
	
	scene_sync_manager = SceneSyncManager.new()
	scene_sync_manager.name = "SceneSyncManager"
	add_child(scene_sync_manager)
	scene_sync_manager.setup(network, editor_if, get_undo_redo())
	
	# 5. Wire Dock with all managers
	dock.setup(network, script_sync_manager, res_sync_manager, github_service)
	dock.toggle_viewports_requested.connect(func(enabled: bool):
		show_2d_viewports = enabled
		update_overlays()
	)
	dock.toggle_mouse_requested.connect(func(enabled: bool):
		show_2d_cursors = enabled
		update_overlays()
	)
	
	print("[Live Co-Op] Full Plugin Suite with GitHub integration initialized successfully!")

func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
		
	if github_service != null:
		github_service.queue_free()
		github_service = null
		
	if res_sync_manager != null:
		res_sync_manager.queue_free()
		res_sync_manager = null
		
	if fs_indicator_manager != null:
		fs_indicator_manager.queue_free()
		fs_indicator_manager = null
		
	if scene_sync_manager != null:
		scene_sync_manager.queue_free()
		scene_sync_manager = null
		
	if viewport_tracker != null:
		viewport_tracker.queue_free()
		viewport_tracker = null
		
	if script_sync_manager != null:
		script_sync_manager.queue_free()
		script_sync_manager = null
		
	if network != null:
		network.queue_free()
		network = null
		
	print("[Live Co-Op] Plugin unloaded.")

func _get_plugin_name() -> String:
	return "Live Co-Op"

func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("Multiplayer", "EditorIcons")

## --- 2D Canvas Editor Collaborator Viewport & Cursor Rendering ---

func _forward_canvas_force_draw_over_viewport(overlay_control: Control) -> void:
	if (!show_2d_viewports and !show_2d_cursors) or network == null or not network.is_connected_to_session or viewport_tracker == null:
		return
		
	var vp = get_editor_interface().get_editor_viewport_2d()
	if vp == null:
		return
		
	var my_scene = ""
	var root = get_editor_interface().get_edited_scene_root()
	if root and not root.scene_file_path.is_empty():
		my_scene = root.scene_file_path
		
	if my_scene.is_empty():
		return
		
	var canvas_xform = vp.global_canvas_transform
	var font = ThemeDB.fallback_font
	var font_size: int = 12
	var my_id = network.custom_mp.get_unique_id() if network.custom_mp else 1
	
	# Collect unique peer IDs
	var active_peers: Array = []
	for pid in viewport_tracker.peer_viewports.keys():
		if not active_peers.has(int(pid)):
			active_peers.append(int(pid))
	for pid in viewport_tracker.peer_cursors.keys():
		if not active_peers.has(int(pid)):
			active_peers.append(int(pid))
			
	for peer_id in active_peers:
		if peer_id == my_id:
			continue
			
		var peer_prof = network.peers.get(peer_id, {})
		var peer_scene = peer_prof.get("active_file", "")
		# Only display collaborator's 2D elements if both are in the same active scene
		if peer_scene.is_empty() or my_scene != peer_scene:
			continue
			
		var col_hex = peer_prof.get("color_hex", "3498db")
		var peer_col = Color.from_string(col_hex, Color.DODGER_BLUE)
		var username = peer_prof.get("username", "Peer %d" % peer_id)
		var avatar_tex = network.get_peer_avatar_texture(peer_id)
		
		# 1. Draw 2D Viewport Camera Frame if enabled
		if show_2d_viewports and viewport_tracker.peer_viewports.has(peer_id):
			var pdata = viewport_tracker.peer_viewports[peer_id]
			var world_rect: Rect2 = pdata.get("world_rect", Rect2())
			if world_rect.size.x > 0 and world_rect.size.y > 0:
				var zoom_val = pdata.get("zoom", 1.0)
				var screen_tl = canvas_xform * world_rect.position
				var screen_br = canvas_xform * world_rect.end
				var screen_rect = Rect2(screen_tl, screen_br - screen_tl)
				
				# Subtle shaded tint inside collaborator's viewport
				var tint_col = Color(peer_col.r, peer_col.g, peer_col.b, 0.04)
				overlay_control.draw_rect(screen_rect, tint_col, true)
				
				# Viewport boundary frame
				overlay_control.draw_rect(screen_rect, peer_col, false, 2.0)
				
				# Center crosshairs
				var screen_center = canvas_xform * pdata.get("world_center", world_rect.get_center())
				overlay_control.draw_line(screen_center - Vector2(8, 0), screen_center + Vector2(8, 0), peer_col, 2.0)
				overlay_control.draw_line(screen_center - Vector2(0, 8), screen_center + Vector2(0, 8), peer_col, 2.0)
				
				# Floating Badge Tag with Photo Profile and Username
				var badge_text = " %s (2D: %.1fx) " % [username, zoom_val]
				var text_sz = font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				var pad = Vector2(4, 2)
				var av_size = Vector2(18, 18) if avatar_tex != null else Vector2.ZERO
				var extra_w = (av_size.x + 2.0) if avatar_tex != null else 0.0
				
				var badge_w = text_sz.x + extra_w + pad.x * 2.0
				var badge_h = maxf(text_sz.y + pad.y * 2.0, av_size.y + 4.0)
				var badge_pos = Vector2(screen_rect.position.x, screen_rect.position.y - badge_h)
				if badge_pos.y < 0:
					badge_pos.y = screen_rect.position.y + screen_rect.size.y
					
				var badge_rect = Rect2(badge_pos, Vector2(badge_w, badge_h))
				overlay_control.draw_rect(badge_rect, peer_col, true)
				overlay_control.draw_rect(badge_rect, peer_col.darkened(0.3), false, 1.0)
				
				var text_col = Color.BLACK if peer_col.get_luminance() > 0.55 else Color.WHITE
				var text_start_x = badge_rect.position.x + pad.x
				if avatar_tex != null:
					var av_rect = Rect2(
						badge_rect.position.x + pad.x,
						badge_rect.position.y + (badge_h - av_size.y) * 0.5,
						av_size.x,
						av_size.y
					)
					overlay_control.draw_texture_rect(avatar_tex, av_rect, false)
					text_start_x += av_size.x + 2.0
					
				var text_pos = Vector2(text_start_x, badge_rect.position.y + text_sz.y + pad.y - 2)
				overlay_control.draw_string(font, text_pos, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)

		# 2. Draw Collaborator Mouse Cursor if enabled
		if show_2d_cursors and viewport_tracker.peer_cursors.has(peer_id):
			var cur = viewport_tracker.peer_cursors[peer_id]
			var opacity: float = cur.get("opacity", 0.0)
			if opacity > 0.01:
				var world_pos: Vector2 = cur.get("current_pos", Vector2.ZERO)
				var screen_pos: Vector2 = canvas_xform * world_pos
				_draw_collaborator_cursor(overlay_control, screen_pos, peer_col, opacity, username, avatar_tex, font)

func _draw_collaborator_cursor(
	overlay: Control,
	pos: Vector2,
	color: Color,
	opacity: float,
	username: String,
	avatar_tex: Texture2D,
	font: Font
) -> void:
	var fill_col = Color(color.r, color.g, color.b, opacity)
	var outline_col = Color(0.08, 0.08, 0.08, 0.75 * opacity)
	
	# 1. Cursor Arrow: sleek pointer with drop shadow
	var p0 = pos
	var p1 = pos + Vector2(0, 17)
	var p2 = pos + Vector2(4.5, 13)
	var p3 = pos + Vector2(7.5, 19.5)
	var p4 = pos + Vector2(10.5, 18.2)
	var p5 = pos + Vector2(7.5, 12.0)
	var p6 = pos + Vector2(13.5, 12.0)
	
	var shadow_offset = Vector2(1.0, 1.5)
	var shadow_col = Color(0, 0, 0, 0.25 * opacity)
	var shadow_poly = PackedVector2Array([
		p0 + shadow_offset, p1 + shadow_offset, p2 + shadow_offset,
		p3 + shadow_offset, p4 + shadow_offset, p5 + shadow_offset,
		p6 + shadow_offset
	])
	overlay.draw_colored_polygon(shadow_poly, shadow_col)
	
	var arrow_poly = PackedVector2Array([p0, p1, p2, p3, p4, p5, p6])
	overlay.draw_colored_polygon(arrow_poly, fill_col)
	
	var arrow_outline = PackedVector2Array([p0, p1, p2, p3, p4, p5, p6, p0])
	overlay.draw_polyline(arrow_outline, outline_col, 1.2, true)
	
	# 2. Name Tag Badge (attached below-right of cursor)
	var font_size: int = 11
	var text_sz = font.get_string_size(username, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad = Vector2(4, 2)
	var av_size = Vector2(14, 14) if avatar_tex != null else Vector2.ZERO
	var av_gap = 3.0 if avatar_tex != null else 0.0
	
	var badge_w = text_sz.x + av_size.x + av_gap + pad.x * 2.0
	var badge_h = maxf(text_sz.y + pad.y * 2.0, av_size.y + 4.0)
	
	var badge_pos = pos + Vector2(12, 14)
	var badge_rect = Rect2(badge_pos, Vector2(badge_w, badge_h))
	
	var badge_shadow = Rect2(badge_pos + shadow_offset, Vector2(badge_w, badge_h))
	overlay.draw_rect(badge_shadow, shadow_col, true)
	
	overlay.draw_rect(badge_rect, fill_col, true)
	overlay.draw_rect(badge_rect, outline_col, false, 1.0)
	
	var text_start_x = badge_rect.position.x + pad.x
	if avatar_tex != null:
		var av_rect = Rect2(
			badge_rect.position.x + pad.x,
			badge_rect.position.y + (badge_h - av_size.y) * 0.5,
			av_size.x,
			av_size.y
		)
		overlay.draw_texture_rect(avatar_tex, av_rect, false, Color(1, 1, 1, opacity))
		text_start_x += av_size.x + av_gap
		
	var text_col = Color(0, 0, 0, opacity) if color.get_luminance() > 0.55 else Color(1, 1, 1, opacity)
	var text_pos = Vector2(text_start_x, badge_rect.position.y + text_sz.y + pad.y - 1)
	overlay.draw_string(font, text_pos, username, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)
