@tool
class_name FileSystemIndicatorManager
extends Node

const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")

var network: CoopNetwork
var editor_interface: EditorInterface
var plugin: EditorPlugin

var _current_main_screen: String = "2D"
var _last_active_file: String = ""
var _tree_overlays: Dictionary = {} # Tree -> Control
var _refresh_timer: Timer

func _enter_tree() -> void:
	if _refresh_timer == null:
		_refresh_timer = Timer.new()
		_refresh_timer.name = "FSRefreshTimer"
		_refresh_timer.wait_time = 0.35
		_refresh_timer.autostart = true
		_refresh_timer.timeout.connect(_on_refresh_tick)
		add_child(_refresh_timer)

func _exit_tree() -> void:
	if _refresh_timer:
		_refresh_timer.stop()
	_cleanup_overlays()

func setup(p_network: CoopNetwork, p_editor_interface: EditorInterface, p_plugin: EditorPlugin) -> void:
	network = p_network
	editor_interface = p_editor_interface
	plugin = p_plugin
	
	if plugin:
		if not plugin.main_screen_changed.is_connected(_on_main_screen_changed):
			plugin.main_screen_changed.connect(_on_main_screen_changed)
		if not plugin.scene_changed.is_connected(_on_scene_changed):
			plugin.scene_changed.connect(_on_scene_changed)
			
	if editor_interface:
		var se = editor_interface.get_script_editor()
		if se and not se.editor_script_changed.is_connected(_on_editor_script_changed):
			se.editor_script_changed.connect(_on_editor_script_changed)
		var fs = editor_interface.get_resource_filesystem()
		if fs and not fs.filesystem_changed.is_connected(_on_filesystem_changed):
			fs.filesystem_changed.connect(_on_filesystem_changed)
			
	if network:
		if not network.peer_active_file_changed.is_connected(_on_peer_active_file_changed):
			network.peer_active_file_changed.connect(_on_peer_active_file_changed)
		if not network.peer_connected_coop.is_connected(_on_peer_list_changed):
			network.peer_connected_coop.connect(_on_peer_list_changed)
		if not network.peer_disconnected_coop.is_connected(_on_peer_disconnected):
			network.peer_disconnected_coop.connect(_on_peer_disconnected)
		if not network.peer_avatar_received.is_connected(_on_peer_avatar_received):
			network.peer_avatar_received.connect(_on_peer_avatar_received)
		if not network.connection_status_changed.is_connected(_on_connection_status_changed):
			network.connection_status_changed.connect(_on_connection_status_changed)
			
	_attach_overlays()
	_update_local_active_file()

func _cleanup_overlays() -> void:
	for tree in _tree_overlays.keys():
		var overlay = _tree_overlays[tree]
		if is_instance_valid(overlay):
			overlay.queue_free()
	_tree_overlays.clear()

func _attach_overlays() -> void:
	if editor_interface == null:
		return
	var fsd = editor_interface.get_file_system_dock()
	if fsd == null:
		return
		
	var trees: Array[Tree] = []
	_find_trees(fsd, trees)
	
	for tree in trees:
		if not _tree_overlays.has(tree) or not is_instance_valid(_tree_overlays[tree]):
			var overlay = Control.new()
			overlay.name = "LiveCoopFileSystemOverlay"
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tree.add_child(overlay)
			
			overlay.draw.connect(_on_overlay_draw.bind(tree, overlay))
			if not tree.draw.is_connected(overlay.queue_redraw):
				tree.draw.connect(overlay.queue_redraw)
			if tree.has_signal("item_collapsed") and not tree.item_collapsed.is_connected(_on_tree_item_collapsed.bind(overlay)):
				tree.item_collapsed.connect(_on_tree_item_collapsed.bind(overlay))
				
			_tree_overlays[tree] = overlay

func _find_trees(node: Node, result: Array[Tree]) -> void:
	if node is Tree:
		result.append(node)
	for child in node.get_children():
		_find_trees(child, result)

func _on_tree_item_collapsed(_item: TreeItem, overlay: Control) -> void:
	if is_instance_valid(overlay):
		overlay.queue_redraw()

func _on_refresh_tick() -> void:
	_attach_overlays()
	_update_local_active_file()
	_queue_redraw_all()

func _queue_redraw_all() -> void:
	for tree in _tree_overlays.keys():
		var overlay = _tree_overlays[tree]
		if is_instance_valid(overlay):
			overlay.queue_redraw()

func _on_main_screen_changed(screen_name: String) -> void:
	_current_main_screen = screen_name
	_update_local_active_file()

func _on_scene_changed(_root: Node) -> void:
	_update_local_active_file()

func _on_editor_script_changed(_script: Script) -> void:
	_update_local_active_file()

func _on_filesystem_changed() -> void:
	_queue_redraw_all()

func _on_peer_active_file_changed(_peer_id: int, _file_path: String) -> void:
	_queue_redraw_all()

func _on_peer_list_changed(_peer_id: int, _data = null) -> void:
	_queue_redraw_all()

func _on_peer_disconnected(_peer_id: int) -> void:
	_queue_redraw_all()

func _on_peer_avatar_received(_peer_id: int, _tex: ImageTexture) -> void:
	_queue_redraw_all()

func _on_connection_status_changed(is_connected: bool, _is_host: bool, _msg: String) -> void:
	if is_connected:
		_last_active_file = ""
		_update_local_active_file(true)
	_queue_redraw_all()

func _update_local_active_file(force: bool = false) -> void:
	if editor_interface == null or network == null or not network.is_connected_to_session:
		return
		
	var path: String = ""
	if _current_main_screen == "Script":
		var se = editor_interface.get_script_editor()
		if se:
			var cur_script = se.get_current_script()
			if cur_script and not cur_script.resource_path.is_empty():
				path = cur_script.resource_path
	else:
		# 2D, 3D, or Node view
		var root = editor_interface.get_edited_scene_root()
		if root and not root.scene_file_path.is_empty():
			path = root.scene_file_path
			
	if path != _last_active_file or force:
		_last_active_file = path
		network.send_active_file(path)
		_queue_redraw_all()

## Renders highlights and avatar/circle indicators over active files in FileSystemDock
func _on_overlay_draw(tree: Tree, overlay: Control) -> void:
	if network == null or not network.is_connected_to_session:
		return
		
	var root_item = tree.get_root()
	if root_item == null:
		return
		
	var items_by_path: Dictionary = {} # path -> TreeItem
	_collect_tree_items(root_item, items_by_path)
	
	# Group peers by their active file
	var peers_by_file: Dictionary = {}
	for pid in network.peers.keys():
		var peer = network.peers[pid]
		var a_file: String = peer.get("active_file", "")
		if not a_file.is_empty():
			if not peers_by_file.has(a_file):
				peers_by_file[a_file] = []
			peers_by_file[a_file].append(peer)
			
	for file_path in peers_by_file.keys():
		if not items_by_path.has(file_path):
			continue
			
		var item: TreeItem = items_by_path[file_path]
		var rect: Rect2 = tree.get_item_area_rect(item, 0)
		
		# Only draw if currently visible within the Tree scroll view
		if rect.size.y <= 0 or rect.position.y + rect.size.y < 0 or rect.position.y > tree.size.y:
			continue
			
		var peer_list: Array = peers_by_file[file_path]
		if peer_list.is_empty():
			continue
			
		# 1. Draw subtle row highlight in collaborator's color
		var first_peer = peer_list[0]
		var primary_col: Color = Color.from_string(first_peer.get("color_hex", "3498db"), Color.DODGER_BLUE)
		var bg_rect = Rect2(Vector2(2, rect.position.y), Vector2(tree.size.x - 4, rect.size.y))
		
		var tint_col = Color(primary_col.r, primary_col.g, primary_col.b, 0.16)
		var border_col = Color(primary_col.r, primary_col.g, primary_col.b, 0.55)
		overlay.draw_rect(bg_rect, tint_col, true)
		overlay.draw_rect(bg_rect, border_col, false, 1.2)
		
		# 2. Draw circular avatar or colored circle indicator on the right side
		var center_y = rect.position.y + rect.size.y * 0.5
		var current_x = tree.size.x - 14.0
		
		for peer in peer_list:
			var pid = int(peer.get("id", 0))
			var col = Color.from_string(peer.get("color_hex", "3498db"), Color.DODGER_BLUE)
			var av_tex = network.get_peer_avatar_texture(pid)
			var circle_pos = Vector2(current_x - 7.0, center_y)
			
			if av_tex:
				# Collaborator has an avatar (e.g. from GitHub)
				var av_size = 15.0
				var av_rect = Rect2(circle_pos - Vector2(av_size * 0.5, av_size * 0.5), Vector2(av_size, av_size))
				overlay.draw_texture_rect(av_tex, av_rect, false)
				# Ring border in collaborator's color
				overlay.draw_arc(circle_pos, av_size * 0.5 + 1.0, 0, TAU, 28, col, 1.8, true)
			else:
				# Collaborator colored circle indicator
				var radius = 5.5
				overlay.draw_circle(circle_pos, radius, col)
				# Clean white/dark ring outline
				overlay.draw_arc(circle_pos, radius, 0, TAU, 24, Color(1, 1, 1, 0.8), 1.2, true)
				
			current_x -= 20.0

func _collect_tree_items(item: TreeItem, map: Dictionary) -> void:
	if item == null:
		return
	var path = _get_item_path(item)
	if not path.is_empty():
		map[path] = item
		
	var child = item.get_first_child()
	while child:
		_collect_tree_items(child, map)
		child = child.get_next()

func _get_item_path(item: TreeItem) -> String:
	if item == null:
		return ""
	var meta = item.get_metadata(0)
	if meta is String and meta.begins_with("res://"):
		return meta
		
	var tooltip = item.get_tooltip_text(0)
	if tooltip.begins_with("res://"):
		return tooltip
		
	# Fallback: traverse up tree hierarchy
	var parts: Array[String] = []
	var cur = item
	while cur != null:
		var txt = cur.get_text(0)
		if not txt.is_empty() and txt != "res://" and txt != "res:":
			parts.push_front(txt)
		cur = cur.get_parent()
		
	if not parts.is_empty():
		return "res://" + "/".join(parts)
	return ""
