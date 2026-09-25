@tool
class_name SceneSyncManager
extends Node

const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")

var network: CoopNetwork
var editor_interface: EditorInterface
var undo_redo: Object

var _check_timer: Timer
var _last_scene_path: String = ""
var _last_selected_paths: Array[String] = []

# node -> { "name": String, "last_path": String, "property_hashes": Dictionary }
var _observed_nodes: Dictionary = {}
var _suppressed_nodes: Dictionary = {}

# peer_id -> { "scene_path": String, "node_paths": Array }
var peer_selections: Dictionary = {}

var _was_mouse_down: bool = false

# Scene Dock overlay
var _scene_tree: Tree
var _scene_overlay: Control

const IGNORED_PROPERTIES: Dictionary = {
	"Node": [
		"owner",
		"multiplayer"
	],
	"Control": [
		"offset_left", "offset_right",
		"offset_top", "offset_bottom"
	],
	"Node2D": [
		"global_position",
		"global_rotation",
		"global_scale",
		"global_transform"
	],
	"Node3D": [
		"global_transform",
		"global_basis",
		"global_position",
		"global_rotation",
		"global_rotation_degrees"
	]
}

func _enter_tree() -> void:
	set_process(true)
	if _check_timer == null:
		_check_timer = Timer.new()
		_check_timer.name = "SceneSyncCheckTimer"
		_check_timer.wait_time = 0.066 # ~15 FPS continuous live transform/gizmo drag streaming
		_check_timer.autostart = true
		_check_timer.timeout.connect(_on_check_timer_timeout)
		add_child(_check_timer)

func _process(_delta: float) -> void:
	var mouse_down = _is_mouse_down()
	if _was_mouse_down and not mouse_down:
		# Left/right mouse button was released! Completed tile stroke or gizmo drop!
		_check_changes(false)
	_was_mouse_down = mouse_down

func _is_mouse_down() -> bool:
	return (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or
		Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)

func _exit_tree() -> void:
	if _check_timer:
		_check_timer.stop()
	_cleanup_overlay()
	_clear_observed()

func setup(p_network: CoopNetwork, p_editor_interface: EditorInterface, p_undo_redo: Object = null) -> void:
	network = p_network
	editor_interface = p_editor_interface
	undo_redo = p_undo_redo

	if undo_redo:
		if undo_redo.has_signal("version_changed") and not undo_redo.version_changed.is_connected(_on_undo_version_changed):
			undo_redo.version_changed.connect(_on_undo_version_changed)
		elif undo_redo.has_signal("history_changed") and not undo_redo.history_changed.is_connected(_on_undo_version_changed):
			undo_redo.history_changed.connect(_on_undo_version_changed)

	if editor_interface:
		var sel = editor_interface.get_selection()
		if sel and not sel.selection_changed.is_connected(_on_local_selection_changed):
			sel.selection_changed.connect(_on_local_selection_changed)

	if network:
		if not network.scene_node_updated.is_connected(_on_remote_node_update):
			network.scene_node_updated.connect(_on_remote_node_update)
		if not network.scene_node_added.is_connected(_on_remote_node_add):
			network.scene_node_added.connect(_on_remote_node_add)
		if not network.scene_node_deleted.is_connected(_on_remote_node_delete):
			network.scene_node_deleted.connect(_on_remote_node_delete)
		if not network.scene_node_renamed.is_connected(_on_remote_node_rename):
			network.scene_node_renamed.connect(_on_remote_node_rename)
		if not network.scene_node_reordered.is_connected(_on_remote_node_reorder):
			network.scene_node_reordered.connect(_on_remote_node_reorder)
		if not network.peer_scene_selection_changed.is_connected(_on_remote_scene_selection):
			network.peer_scene_selection_changed.connect(_on_remote_scene_selection)
		if not network.peer_disconnected_coop.is_connected(_on_peer_disconnected):
			network.peer_disconnected_coop.connect(_on_peer_disconnected)
		if not network.connection_status_changed.is_connected(_on_connection_status_changed):
			network.connection_status_changed.connect(_on_connection_status_changed)

	_attach_scene_tree_overlay()
	observe_current_scene()

func can_sync() -> bool:
	return (
		network != null and
		network.is_connected_to_session and
		editor_interface != null
	)

func _on_connection_status_changed(is_connected: bool, _is_host: bool, _msg: String) -> void:
	if not is_connected:
		peer_selections.clear()
		if is_instance_valid(_scene_overlay):
			_scene_overlay.queue_redraw()
	else:
		observe_current_scene()

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_selections.has(peer_id):
		peer_selections.erase(peer_id)
		if is_instance_valid(_scene_overlay):
			_scene_overlay.queue_redraw()

func _on_undo_version_changed() -> void:
	# Built-in Godot UndoRedo listener: triggers on action commit (e.g. stroke released, inspector edit)
	var mouse_down = _is_mouse_down()
	_check_changes(mouse_down)

func _on_check_timer_timeout() -> void:
	_attach_scene_tree_overlay()
	_check_scene_switch()
	var mouse_down = _is_mouse_down()
	_check_changes(mouse_down)

func _check_scene_switch() -> void:
	if editor_interface == null:
		return
	var root = editor_interface.get_edited_scene_root()
	var cur_path = root.scene_file_path if root else ""
	if cur_path != _last_scene_path:
		_last_scene_path = cur_path
		_clear_observed()
		observe_current_scene()
		_on_local_selection_changed()

func _clear_observed() -> void:
	for node in _observed_nodes.keys():
		if is_instance_valid(node):
			_disconnect_node_signals(node)
	_observed_nodes.clear()
	_suppressed_nodes.clear()

## Observes all nodes in the active edited scene root
func observe_current_scene() -> void:
	if editor_interface == null:
		return
	var root = editor_interface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty():
		return
	_observe_recursive(root)

func _observe_recursive(node: Node) -> void:
	if not _is_user_node(node):
		return
	observe_node(node)
	for child in node.get_children():
		_observe_recursive(child)

func observe_node(node: Node) -> void:
	if not _is_user_node(node) or _observed_nodes.has(node):
		return

	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null:
		return

	var path = str(root.get_path_to(node))
	var hashes = get_property_hash_dict(node)

	_observed_nodes[node] = {
		"name": node.name,
		"last_path": path,
		"property_hashes": hashes
	}

	# Connect tree lifecycle signals
	if not node.child_entered_tree.is_connected(_on_child_entered_tree.bind(node)):
		node.child_entered_tree.connect(_on_child_entered_tree.bind(node))
	if not node.child_order_changed.is_connected(_on_child_order_changed.bind(node)):
		node.child_order_changed.connect(_on_child_order_changed.bind(node))
	if not node.tree_exiting.is_connected(_on_tree_exiting.bind(node)):
		node.tree_exiting.connect(_on_tree_exiting.bind(node))

func unobserve_node(node: Node) -> void:
	if _observed_nodes.has(node):
		_disconnect_node_signals(node)
		_observed_nodes.erase(node)
	_suppressed_nodes.erase(node)

func _disconnect_node_signals(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.child_entered_tree.is_connected(_on_child_entered_tree.bind(node)):
		node.child_entered_tree.disconnect(_on_child_entered_tree.bind(node))
	if node.child_order_changed.is_connected(_on_child_order_changed.bind(node)):
		node.child_order_changed.disconnect(_on_child_order_changed.bind(node))
	if node.tree_exiting.is_connected(_on_tree_exiting.bind(node)):
		node.tree_exiting.disconnect(_on_tree_exiting.bind(node))

## Periodic or trigger-based change checking
func _check_changes(skip_tiles: bool = false) -> void:
	if not can_sync():
		return

	var root = editor_interface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty():
		return

	var scene_path = root.scene_file_path
	var dead_nodes: Array = []

	for node in _observed_nodes.keys():
		if not is_instance_valid(node) or not node.is_inside_tree():
			dead_nodes.append(node)
			continue

		if _suppressed_nodes.has(node):
			continue

		# When mouse button is held down (e.g. actively painting tiles), skip tile nodes to prevent lag!
		if skip_tiles and _is_tile_node(node):
			continue

		var data = _observed_nodes[node]
		var last_hashes: Dictionary = data.get("property_hashes", {})
		var new_hashes = get_property_hash_dict(node, skip_tiles)

		# Check rename
		if node.name != data.get("name", ""):
			var old_path = data.get("last_path", "")
			var new_path = str(root.get_path_to(node))
			data["name"] = node.name
			data["last_path"] = new_path
			print("[Live Co-Op] Node renamed: %s -> %s" % [old_path, node.name])
			network.send_scene_node_rename(scene_path, old_path, node.name)

		# Check property diffs
		var diff_keys: Array[String] = []
		for prop in new_hashes.keys():
			if not last_hashes.has(prop) or last_hashes[prop] != new_hashes[prop]:
				diff_keys.append(prop)

		if not diff_keys.is_empty():
			for k in new_hashes.keys():
				last_hashes[k] = new_hashes[k]
			data["property_hashes"] = last_hashes
			var node_path = str(root.get_path_to(node))
			data["last_path"] = node_path
			var prop_dict = get_select_property_dict(node, diff_keys)
			if not prop_dict.is_empty():
				network.send_scene_node_update(scene_path, node_path, prop_dict)

	for dead in dead_nodes:
		unobserve_node(dead)

## Node Lifecycle Signal Handlers

func _on_child_entered_tree(child: Node, parent: Node) -> void:
	if not can_sync() or not _is_user_node(child) or not _is_user_node(parent):
		return
	if _suppressed_nodes.has(child) or _suppressed_nodes.has(parent):
		return

	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path.is_empty():
		return
	if not root.is_ancestor_of(parent) and parent != root:
		return

	# Deferred to ensure owner and properties are initialized by Godot
	_handle_child_added_deferred.call_deferred(child, parent, root.scene_file_path)

func _handle_child_added_deferred(child: Node, parent: Node, scene_path: String) -> void:
	if not is_instance_valid(child) or not is_instance_valid(parent) or _suppressed_nodes.has(child):
		return

	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path != scene_path:
		return

	if child.owner == null:
		child.owner = root

	_observe_recursive(child)

	var parent_path = str(root.get_path_to(parent))
	var child_class = child.get_class()
	var scene_file_path = child.scene_file_path if not child.scene_file_path.is_empty() else ""

	var all_props = get_select_property_dict(child, get_property_keys(child))
	all_props["name"] = child.name

	print("[Live Co-Op] Node added: %s in %s (class: %s)" % [child.name, parent_path, child_class])
	network.send_scene_node_add(scene_path, parent_path, child_class, scene_file_path, all_props)

func _on_tree_exiting(node: Node) -> void:
	if not can_sync() or not _is_user_node(node) or _suppressed_nodes.has(node):
		return

	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path.is_empty() or node == root:
		return
	if not root.is_ancestor_of(node):
		return

	var scene_path = root.scene_file_path
	var node_path = str(root.get_path_to(node))

	unobserve_node(node)
	print("[Live Co-Op] Node deleted: %s" % node_path)
	network.send_scene_node_delete(scene_path, node_path)

func _on_child_order_changed(parent: Node) -> void:
	if not can_sync() or not _is_user_node(parent) or _suppressed_nodes.has(parent):
		return

	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path.is_empty():
		return
	if not root.is_ancestor_of(parent) and parent != root:
		return

	var parent_path = str(root.get_path_to(parent))
	var names: Array = []
	for child in parent.get_children():
		if _is_user_node(child):
			names.append(child.name)

	network.send_scene_node_reorder(root.scene_file_path, parent_path, names)

## --- Remote Update Handlers ---

func _on_remote_node_update(sender_id: int, scene_path: String, node_path: String, properties: Dictionary) -> void:
	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path != scene_path:
		return

	var node = root.get_node_or_null(NodePath(node_path))
	if node == null:
		return

	_suppressed_nodes[node] = true
	apply_property_dict(node, properties)

	if _observed_nodes.has(node):
		_observed_nodes[node]["property_hashes"] = get_property_hash_dict(node, false)

	if node is CanvasItem:
		node.queue_redraw()

	_suppressed_nodes.erase(node)
	editor_interface.mark_scene_as_unsaved()

func _on_remote_node_add(sender_id: int, scene_path: String, parent_path: String, node_class: String, scene_file_path: String, properties: Dictionary) -> void:
	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path != scene_path:
		return

	var parent = root.get_node_or_null(NodePath(parent_path))
	if parent == null:
		return

	var node_name = str(properties.get("name", ""))
	if not node_name.is_empty() and parent.has_node(NodePath(node_name)):
		# Node already exists
		return

	var new_node: Node = null
	if not scene_file_path.is_empty() and ResourceLoader.exists(scene_file_path):
		var packed_scene = load(scene_file_path) as PackedScene
		if packed_scene:
			new_node = packed_scene.instantiate()

	if new_node == null:
		if ClassDB.can_instantiate(node_class):
			new_node = ClassDB.instantiate(node_class) as Node

	if new_node == null:
		return

	if not node_name.is_empty():
		new_node.name = node_name

	_suppressed_nodes[new_node] = true
	_suppressed_nodes[parent] = true

	parent.add_child(new_node)
	new_node.owner = root
	apply_property_dict(new_node, properties)

	_observe_recursive(new_node)

	_suppressed_nodes.erase(new_node)
	_suppressed_nodes.erase(parent)
	editor_interface.mark_scene_as_unsaved()

func _on_remote_node_delete(sender_id: int, scene_path: String, node_path: String) -> void:
	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path != scene_path:
		return

	var node = root.get_node_or_null(NodePath(node_path))
	if node == null or node == root:
		return

	var sel = editor_interface.get_selection()
	if sel:
		sel.remove_node(node)

	_suppressed_nodes[node] = true
	unobserve_node(node)
	node.queue_free()
	editor_interface.mark_scene_as_unsaved()

func _on_remote_node_rename(sender_id: int, scene_path: String, old_path: String, new_name: String) -> void:
	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path != scene_path:
		return

	var node = root.get_node_or_null(NodePath(old_path))
	if node == null:
		return

	_suppressed_nodes[node] = true
	node.name = new_name
	if _observed_nodes.has(node):
		_observed_nodes[node]["name"] = new_name
		_observed_nodes[node]["last_path"] = str(root.get_path_to(node))
	_suppressed_nodes.erase(node)
	editor_interface.mark_scene_as_unsaved()

func _on_remote_node_reorder(sender_id: int, scene_path: String, parent_path: String, ordered_names: Array) -> void:
	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path != scene_path:
		return

	var parent = root.get_node_or_null(NodePath(parent_path))
	if parent == null:
		return

	_suppressed_nodes[parent] = true
	for i in ordered_names.size():
		var child_name = str(ordered_names[i])
		var child = parent.get_node_or_null(NodePath(child_name))
		if child:
			parent.move_child(child, i)
	_suppressed_nodes.erase(parent)
	editor_interface.mark_scene_as_unsaved()

## --- Property Serialization & Encoding ---

static func get_property_keys(obj: Object) -> Array[String]:
	var res: Array[String] = []
	if obj == null:
		return res

	var ignored = get_ignored_properties(obj)
	for prop in obj.get_property_list():
		var name: String = prop["name"]
		var usage: int = prop["usage"]

		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if usage & PROPERTY_USAGE_INTERNAL != 0:
			continue
		if usage & PROPERTY_USAGE_READ_ONLY != 0:
			continue
		if ignored.has(name):
			continue
		if name.begins_with("metadata/") or name.begins_with("script") or name == "script":
			continue

		res.append(name)
	return res

static func get_ignored_properties(obj: Object) -> Array:
	var res = []
	for cls in IGNORED_PROPERTIES.keys():
		if obj.is_class(cls):
			res.append_array(IGNORED_PROPERTIES[cls])
	return res

static func _is_tile_node(node: Node) -> bool:
	if node == null:
		return false
	var cls = node.get_class()
	return cls == "TileMapLayer" or cls == "TileMap"

static func _is_tile_property(prop: String) -> bool:
	return (
		prop == "tile_map_data" or
		prop.contains("tile_data") or
		prop.contains("tile_map")
	)

static func get_property_hash_dict(obj: Object, skip_tiles: bool = false) -> Dictionary:
	var res = {}
	if obj == null:
		return res
	var is_tile = _is_tile_node(obj) if obj is Node else false
	if skip_tiles and is_tile:
		return res

	for key in get_property_keys(obj):
		if skip_tiles and (is_tile or _is_tile_property(key)):
			continue
		var val = obj.get(key)
		if val is Resource:
			if not val.resource_path.is_empty() and not val.resource_path.contains("::"):
				res[key] = hash(val.resource_path)
			else:
				res[key] = hash(var_to_bytes_with_objects(val))
		else:
			res[key] = hash(val)
	return res

static func get_select_property_dict(obj: Object, keys: Array) -> Dictionary:
	var res = {}
	if obj == null:
		return res
	for key in keys:
		var val = obj.get(key)
		res[key] = encode_value(val)
	return res

static func apply_property_dict(obj: Object, dict: Dictionary) -> void:
	if obj == null:
		return
	for key in dict.keys():
		var val = decode_value(dict[key])
		obj.set(key, val)

static func encode_value(val: Variant) -> Variant:
	if val is Resource:
		if not val.resource_path.is_empty() and not val.resource_path.contains("::"):
			return { "_res_type": "file", "path": val.resource_path }
		else:
			return { "_res_type": "bytes", "buf": var_to_bytes_with_objects(val) }
	return val

static func decode_value(val: Variant) -> Variant:
	if val is Dictionary and val.has("_res_type"):
		var type = val.get("_res_type")
		if type == "file":
			var path = val.get("path", "")
			if ResourceLoader.exists(path):
				return load(path)
		elif type == "bytes":
			var buf = val.get("buf", PackedByteArray())
			if not buf.is_empty():
				return bytes_to_var_with_objects(buf)
	return val

static func _is_user_node(node: Node) -> bool:
	return node != null and is_instance_valid(node) and not node.name.begins_with("@")

## --- Scene Dock Tree Highlight Overlay ---

func _on_local_selection_changed() -> void:
	if not can_sync():
		return

	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path.is_empty():
		return

	var sel = editor_interface.get_selection()
	if sel == null:
		return

	var selected_paths: Array[String] = []
	for node in sel.get_selected_nodes():
		if is_instance_valid(node) and (node == root or root.is_ancestor_of(node)):
			selected_paths.append(str(root.get_path_to(node)))

	if selected_paths != _last_selected_paths:
		_last_selected_paths = selected_paths
		network.send_scene_selection(root.scene_file_path, selected_paths)

func _on_remote_scene_selection(sender_id: int, scene_path: String, node_paths: Array) -> void:
	peer_selections[sender_id] = {
		"scene_path": scene_path,
		"node_paths": node_paths
	}
	if is_instance_valid(_scene_overlay):
		_scene_overlay.queue_redraw()

func _attach_scene_tree_overlay() -> void:
	if editor_interface == null:
		return

	if _scene_tree != null and is_instance_valid(_scene_tree) and _scene_overlay != null and is_instance_valid(_scene_overlay):
		return

	var base_ctrl = editor_interface.get_base_control()
	if base_ctrl == null:
		return

	var tree = _find_scene_tree(base_ctrl)
	if tree == null:
		return

	_scene_tree = tree

	if _scene_overlay == null or not is_instance_valid(_scene_overlay):
		_scene_overlay = Control.new()
		_scene_overlay.name = "LiveCoopSceneTreeOverlay"
		_scene_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scene_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scene_tree.add_child(_scene_overlay)

		_scene_overlay.draw.connect(_on_scene_tree_overlay_draw)
		if not _scene_tree.draw.is_connected(_scene_overlay.queue_redraw):
			_scene_tree.draw.connect(_scene_overlay.queue_redraw)
		if _scene_tree.has_signal("item_collapsed") and not _scene_tree.item_collapsed.is_connected(_on_tree_item_collapsed):
			_scene_tree.item_collapsed.connect(_on_tree_item_collapsed)

func _on_tree_item_collapsed(_item: TreeItem) -> void:
	if is_instance_valid(_scene_overlay):
		_scene_overlay.queue_redraw()

func _cleanup_overlay() -> void:
	if is_instance_valid(_scene_overlay):
		_scene_overlay.queue_free()
		_scene_overlay = null
	_scene_tree = null

func _find_scene_tree(node: Node) -> Tree:
	if node == null:
		return null
	if node.get_class() == "SceneTreeEditor":
		for child in node.get_children():
			if child is Tree:
				return child as Tree
	for child in node.get_children():
		var t = _find_scene_tree(child)
		if t != null:
			return t
	return null

func _on_scene_tree_overlay_draw() -> void:
	if _scene_tree == null or not is_instance_valid(_scene_tree) or network == null or not network.is_connected_to_session:
		return

	var root = editor_interface.get_edited_scene_root() if editor_interface else null
	if root == null or root.scene_file_path.is_empty():
		return

	var current_scene_path = root.scene_file_path
	var root_item = _scene_tree.get_root()
	if root_item == null:
		return

	var font = ThemeDB.fallback_font
	var font_size: int = 10

	for pid in peer_selections.keys():
		var peer_id = int(pid)
		var psel = peer_selections[peer_id]
		var p_scene = psel.get("scene_path", "")

		# Must be in the EXACT same active scene
		if p_scene != current_scene_path:
			continue

		var node_paths: Array = psel.get("node_paths", [])
		if node_paths.is_empty():
			continue

		var peer_prof = network.peers.get(peer_id, {})
		var col_hex = peer_prof.get("color_hex", "3498db")
		var peer_col = Color.from_string(col_hex, Color.DODGER_BLUE)
		var username = peer_prof.get("username", "Peer %d" % peer_id)
		var avatar_tex = network.get_peer_avatar_texture(peer_id)

		for n_path in node_paths:
			var target_node = root.get_node_or_null(str(n_path))
			if target_node == null:
				continue

			var item = _find_tree_item_for_node(root_item, target_node, root)
			if item == null:
				continue

			var rect = _scene_tree.get_item_area_rect(item, 0)
			# Check vertical visibility within Tree bounds
			if rect.size.y <= 0 or rect.end.y < 0 or rect.position.y > _scene_tree.size.y:
				continue

			# Full row highlight spanning tree width
			var row_rect = Rect2(0, rect.position.y, _scene_tree.size.x, rect.size.y)

			# 1. Shaded background highlight
			var bg_color = Color(peer_col.r, peer_col.g, peer_col.b, 0.18)
			_scene_overlay.draw_rect(row_rect, bg_color, true)

			# 2. Left accent border line
			_scene_overlay.draw_line(
				Vector2(2.0, row_rect.position.y),
				Vector2(2.0, row_rect.end.y),
				peer_col,
				2.5
			)

			# 3. Right edge collaborator badge with avatar / username pill
			var badge_pad = Vector2(4, 1)
			var text_sz = font.get_string_size(username, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var av_sz = Vector2(14, 14) if avatar_tex != null else Vector2.ZERO
			var av_gap = 3.0 if avatar_tex != null else 0.0

			var badge_w = text_sz.x + av_sz.x + av_gap + badge_pad.x * 2.0
			var badge_h = maxf(text_sz.y + badge_pad.y * 2.0, 16.0)
			var badge_x = maxf(row_rect.end.x - badge_w - 6.0, row_rect.position.x + 30.0)
			var badge_y = row_rect.position.y + (row_rect.size.y - badge_h) * 0.5
			var badge_rect = Rect2(badge_x, badge_y, badge_w, badge_h)

			# Badge background pill
			_scene_overlay.draw_rect(badge_rect, peer_col, true)
			_scene_overlay.draw_rect(badge_rect, peer_col.darkened(0.3), false, 1.0)

			# Avatar texture or circle
			var text_x = badge_rect.position.x + badge_pad.x
			if avatar_tex != null:
				var av_rect = Rect2(
					text_x,
					badge_rect.position.y + (badge_h - av_sz.y) * 0.5,
					av_sz.x,
					av_sz.y
				)
				_scene_overlay.draw_texture_rect(avatar_tex, av_rect, false)
				text_x += av_sz.x + av_gap

			var text_col = Color.BLACK if peer_col.get_luminance() > 0.55 else Color.WHITE
			var text_pos = Vector2(text_x, badge_rect.position.y + text_sz.y + badge_pad.y - 1)
			_scene_overlay.draw_string(font, text_pos, username, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)

func _find_tree_item_for_node(item: TreeItem, target_node: Node, scene_root: Node) -> TreeItem:
	if item == null or target_node == null:
		return null

	if _matches_node(item, target_node, scene_root):
		return item

	var child = item.get_first_child()
	while child != null:
		var found = _find_tree_item_for_node(child, target_node, scene_root)
		if found != null:
			return found
		child = child.get_next()

	return null

func _matches_node(item: TreeItem, target_node: Node, scene_root: Node) -> bool:
	var meta = item.get_metadata(0)
	if meta is Node and meta == target_node:
		return true
	if meta is NodePath:
		if scene_root.get_tree() and scene_root.get_tree().root.get_node_or_null(meta) == target_node:
			return true
		if scene_root.get_node_or_null(meta) == target_node:
			return true
	if item.get_text(0) == target_node.name:
		var p_item = item.get_parent()
		var p_node = target_node.get_parent()
		if p_item == null or p_node == null or p_node == scene_root.get_parent():
			return true
		if p_item.get_text(0) == p_node.name:
			return true
	return false
