@tool
class_name ScriptSyncManager
extends Node

const CoopTextDelta = preload("res://addons/live_coop/diff/text_delta.gd")
const RemoteCaretOverlay = preload("res://addons/live_coop/editor/remote_caret_overlay.gd")
const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")

var network: CoopNetwork
var script_editor: ScriptEditor

# Dictionary of script_path -> Dictionary:
# {
#   "code_edit": CodeEdit,
#   "overlay": RemoteCaretOverlay,
#   "last_text": String,
#   "script_path": String
# }
var _tracked_editors: Dictionary = {}
var _is_remote_applying: bool = false

func _enter_tree() -> void:
	# In editor, EditorInterface is available
	if Engine.is_editor_hint():
		_init_script_editor()

func _exit_tree() -> void:
	_cleanup()

func setup(p_network: CoopNetwork, p_script_editor: ScriptEditor) -> void:
	network = p_network
	script_editor = p_script_editor
	_init_script_editor()
	_connect_network_signals()

func _init_script_editor() -> void:
	if script_editor == null:
		return
		
	if not script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.connect(_on_editor_script_changed)
	if not script_editor.script_close.is_connected(_on_script_closed):
		script_editor.script_close.connect(_on_script_closed)
		
	# Hook current script if already open
	var cur_script = script_editor.get_current_script()
	if cur_script != null:
		_on_editor_script_changed(cur_script)

func _connect_network_signals() -> void:
	if network == null:
		return
	if not network.text_delta_received.is_connected(_on_remote_delta_received):
		network.text_delta_received.connect(_on_remote_delta_received)
	if not network.caret_moved_received.is_connected(_on_remote_caret_received):
		network.caret_moved_received.connect(_on_remote_caret_received)
	if not network.full_file_received.is_connected(_on_remote_full_file_received):
		network.full_file_received.connect(_on_remote_full_file_received)

func _on_editor_script_changed(script: Script) -> void:
	if script == null or script_editor == null:
		return
	var script_path = script.resource_path
	if script_path.is_empty():
		return
		
	var base_editor = script_editor.get_current_editor()
	if base_editor == null:
		return
		
	var code_edit = base_editor.get_base_editor()
	if code_edit is CodeEdit:
		_register_editor(script_path, code_edit)

func _register_editor(script_path: String, code_edit: CodeEdit) -> void:
	if _tracked_editors.has(script_path):
		var existing = _tracked_editors[script_path]
		if existing.code_edit == code_edit:
			# Notify network of our active script and caret
			_send_local_caret(script_path, code_edit)
			return
		else:
			# Stale reference, unregister old
			_unregister_editor(script_path)
			
	# Attach RemoteCaretOverlay
	var overlay = RemoteCaretOverlay.new()
	overlay.code_edit = code_edit
	overlay.network = network
	overlay.script_path = script_path
	code_edit.add_child(overlay)
	
	_tracked_editors[script_path] = {
		"code_edit": code_edit,
		"overlay": overlay,
		"last_text": code_edit.text,
		"script_path": script_path
	}
	
	# Connect signals
	if not code_edit.text_changed.is_connected(_on_local_text_changed.bind(script_path)):
		code_edit.text_changed.connect(_on_local_text_changed.bind(script_path))
	if not code_edit.caret_changed.is_connected(_on_local_caret_changed.bind(script_path)):
		code_edit.caret_changed.connect(_on_local_caret_changed.bind(script_path))
		
	_send_local_caret(script_path, code_edit)

func _unregister_editor(script_path: String) -> void:
	if not _tracked_editors.has(script_path):
		return
	var entry = _tracked_editors[script_path]
	var code_edit = entry.code_edit
	if is_instance_valid(code_edit):
		if code_edit.text_changed.is_connected(_on_local_text_changed.bind(script_path)):
			code_edit.text_changed.disconnect(_on_local_text_changed.bind(script_path))
		if code_edit.caret_changed.is_connected(_on_local_caret_changed.bind(script_path)):
			code_edit.caret_changed.disconnect(_on_local_caret_changed.bind(script_path))
	if is_instance_valid(entry.overlay):
		entry.overlay.queue_free()
	_tracked_editors.erase(script_path)

func _on_script_closed(script: Script) -> void:
	if script != null:
		_unregister_editor(script.resource_path)

## --- Local Editor Event Handlers ---

func _on_local_text_changed(script_path: String) -> void:
	if _is_remote_applying or not _tracked_editors.has(script_path):
		return
	var entry = _tracked_editors[script_path]
	var code_edit = entry.code_edit
	if not is_instance_valid(code_edit):
		return
		
	var cur_text = code_edit.text
	if cur_text == entry.last_text:
		return
		
	# Compute minimal delta
	var delta = CoopTextDelta.compute_delta(entry.last_text, cur_text)
	entry.last_text = cur_text
	
	if not delta.get("empty", false) and network != null:
		network.send_delta(script_path, delta)

func _on_local_caret_changed(script_path: String) -> void:
	if _is_remote_applying or not _tracked_editors.has(script_path):
		return
	var entry = _tracked_editors[script_path]
	var code_edit = entry.code_edit
	if not is_instance_valid(code_edit):
		return
		
	_send_local_caret(script_path, code_edit)

func _send_local_caret(script_path: String, code_edit: CodeEdit) -> void:
	if network == null or not network.is_connected_to_session:
		return
	var line = code_edit.get_caret_line()
	var col = code_edit.get_caret_column()
	var sel_data = {}
	if code_edit.has_selection():
		sel_data = {
			"active": true,
			"from_line": code_edit.get_selection_from_line(),
			"from_col": code_edit.get_selection_from_column(),
			"to_line": code_edit.get_selection_to_line(),
			"to_col": code_edit.get_selection_to_column()
		}
	else:
		sel_data = { "active": false }
		
	network.send_caret(script_path, line, col, sel_data)

## --- Remote Incoming Network Event Handlers ---

func _on_remote_delta_received(_sender_id: int, script_path: String, delta: Dictionary) -> void:
	if not _tracked_editors.has(script_path):
		return
	var entry = _tracked_editors[script_path]
	var code_edit = entry.code_edit
	if not is_instance_valid(code_edit):
		return
		
	_is_remote_applying = true
	
	# Preserve local caret offset and scroll positions
	var cur_line = code_edit.get_caret_line()
	var cur_col = code_edit.get_caret_column()
	var cur_offset = CoopTextDelta.line_col_to_offset(code_edit.text, cur_line, cur_col)
	var new_caret_offset = CoopTextDelta.adjust_caret_offset(cur_offset, delta)
	
	var v_scroll = code_edit.scroll_vertical
	var h_scroll = code_edit.scroll_horizontal
	
	# Apply delta
	var new_text = CoopTextDelta.apply_delta(entry.last_text, delta)
	code_edit.text = new_text
	entry.last_text = new_text
	
	# Restore caret position adjusted for the delta
	var new_pos = CoopTextDelta.offset_to_line_col(new_text, new_caret_offset)
	code_edit.set_caret_line(new_pos.x)
	code_edit.set_caret_column(new_pos.y)
	code_edit.scroll_vertical = v_scroll
	code_edit.scroll_horizontal = h_scroll
	
	_is_remote_applying = false
	
	if entry.overlay and is_instance_valid(entry.overlay):
		entry.overlay.queue_redraw()

func _on_remote_caret_received(_sender_id: int, script_path: String, _line: int, _col: int, _sel_data: Dictionary) -> void:
	if _tracked_editors.has(script_path):
		var entry = _tracked_editors[script_path]
		if entry.overlay and is_instance_valid(entry.overlay):
			entry.overlay.queue_redraw()

func _on_remote_full_file_received(_sender_id: int, script_path: String, content: String) -> void:
	if not _tracked_editors.has(script_path):
		return
	var entry = _tracked_editors[script_path]
	var code_edit = entry.code_edit
	if not is_instance_valid(code_edit):
		return
		
	_is_remote_applying = true
	code_edit.text = content
	entry.last_text = content
	_is_remote_applying = false
	
	if entry.overlay and is_instance_valid(entry.overlay):
		entry.overlay.queue_redraw()

func _cleanup() -> void:
	for path in _tracked_editors.keys():
		_unregister_editor(path)
	_tracked_editors.clear()
