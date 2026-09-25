@tool
class_name ResSyncManager
extends Node

signal sync_started(total_files: int)
signal file_synced(path: String, current: int, total: int)
signal sync_completed(total_files: int)

const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")

var network: CoopNetwork
var editor_interface: EditorInterface
var undo_redo: Object

var _is_initial_syncing: bool = false
var _is_remote_writing: bool = false
var _is_local_auto_saving: bool = false

var _target_file_count: int = 0
var _downloaded_file_count: int = 0
var _incoming_chunks: Dictionary = {} # path -> PackedByteArray
var _has_synced_this_connection: bool = false
var _file_hashes: Dictionary = {} # path -> sha256

var _scan_timer: Timer
var _auto_save_timer: Timer

const IGNORED_PREFIXES = [
	"res://.godot",
	"res://.git",
	"res://.import",
	"res://.vscode",
	"res://.idea",
	"res://addons/live_coop",
	"res://tests"
]

const CHUNK_SIZE = 262144 # 256 KB per packet chunk

func _enter_tree() -> void:
	if _scan_timer == null:
		_scan_timer = Timer.new()
		_scan_timer.name = "ResScanTimer"
		_scan_timer.wait_time = 1.2
		_scan_timer.one_shot = false
		_scan_timer.autostart = false
		_scan_timer.timeout.connect(_check_filesystem_changes)
		add_child(_scan_timer)
		
	if _auto_save_timer == null:
		_auto_save_timer = Timer.new()
		_auto_save_timer.name = "AutoSaveTimer"
		_auto_save_timer.wait_time = 4.0
		_auto_save_timer.one_shot = true
		_auto_save_timer.timeout.connect(_on_auto_save_timeout)
		add_child(_auto_save_timer)

func _exit_tree() -> void:
	if _scan_timer:
		_scan_timer.stop()
	if _auto_save_timer:
		_auto_save_timer.stop()

func setup(p_network: CoopNetwork, p_editor_interface: EditorInterface, p_undo_redo: Object = null) -> void:
	network = p_network
	editor_interface = p_editor_interface
	undo_redo = p_undo_redo
	
	if undo_redo:
		if undo_redo.has_signal("version_changed"):
			if not undo_redo.version_changed.is_connected(_on_undo_version_changed):
				undo_redo.version_changed.connect(_on_undo_version_changed)
		elif undo_redo.has_signal("history_changed"):
			if not undo_redo.history_changed.is_connected(_on_undo_version_changed):
				undo_redo.history_changed.connect(_on_undo_version_changed)
				
	if editor_interface:
		var fs = editor_interface.get_resource_filesystem()
		if fs and not fs.filesystem_changed.is_connected(_on_filesystem_changed):
			fs.filesystem_changed.connect(_on_filesystem_changed)
			
	if network:
		if not network.project_files_requested.is_connected(_on_project_files_requested):
			network.project_files_requested.connect(_on_project_files_requested)
		if not network.project_download_started.is_connected(_on_project_download_started):
			network.project_download_started.connect(_on_project_download_started)
		if not network.project_file_chunk_received.is_connected(_on_project_file_chunk_received):
			network.project_file_chunk_received.connect(_on_project_file_chunk_received)
		if not network.project_file_deleted.is_connected(_on_project_file_deleted):
			network.project_file_deleted.connect(_on_project_file_deleted)
		if not network.session_joined.is_connected(_on_session_joined):
			network.session_joined.connect(_on_session_joined)
		if not network.connection_status_changed.is_connected(_on_connection_status_changed):
			network.connection_status_changed.connect(_on_connection_status_changed)

func _on_connection_status_changed(is_connected: bool, is_host: bool, _msg: String) -> void:
	if not is_connected:
		_has_synced_this_connection = false
		_is_initial_syncing = false
		_incoming_chunks.clear()
		_file_hashes.clear()
		if _scan_timer: _scan_timer.stop()
		if _auto_save_timer: _auto_save_timer.stop()
	elif is_connected:
		# Populate initial local hashes
		_file_hashes = get_file_tree_hashes()
		if _scan_timer:
			_scan_timer.start()
			
		if not is_host:
			start_client_res_sync()

func _on_session_joined() -> void:
	if network and not network.is_host_peer:
		start_client_res_sync()

func can_sync_live() -> bool:
	return (
		network != null and
		network.is_connected_to_session and
		not _is_initial_syncing and
		not _is_remote_writing
	)

## Called when user makes an undoable change in the editor (moves node, changes property, adds node)
func _on_undo_version_changed() -> void:
	if not can_sync_live():
		return
	if _auto_save_timer:
		_auto_save_timer.start(4.0)

## Auto-saves active scene so changes sync live in runtime without needing Ctrl+S
func _on_auto_save_timeout() -> void:
	if not can_sync_live() or editor_interface == null:
		return
		
	var root = editor_interface.get_edited_scene_root()
	if root and not root.scene_file_path.is_empty():
		if is_path_safe(root.scene_file_path):
			_is_local_auto_saving = true
			editor_interface.save_scene()
			_is_local_auto_saving = false
			_check_filesystem_changes()

func _on_filesystem_changed() -> void:
	if can_sync_live() and not _is_local_auto_saving:
		_check_filesystem_changes()

## Checks for modified, added, or deleted files in res:// and syncs them live
func _check_filesystem_changes() -> void:
	if not can_sync_live():
		return
		
	var current_hashes = get_file_tree_hashes()
	
	# Detect modified or newly created files
	for path in current_hashes.keys():
		var cur_hash = current_hashes[path]
		if not _file_hashes.has(path) or _file_hashes[path] != cur_hash:
			_file_hashes[path] = cur_hash
			print("[Live Co-Op] Runtime sync: broadcasting modified file: ", path)
			broadcast_file_at_path(path)
			
	# Detect deleted files
	var deleted_paths: Array[String] = []
	for path in _file_hashes.keys():
		if not current_hashes.has(path):
			deleted_paths.append(path)
			
	for path in deleted_paths:
		_file_hashes.erase(path)
		print("[Live Co-Op] Runtime sync: broadcasting deleted file: ", path)
		broadcast_file_delete(path)

func broadcast_file_at_path(path: String, exclude_peer: int = 0) -> void:
	if not FileAccess.file_exists(path) or not is_path_safe(path):
		return
	var buf = FileAccess.get_file_as_bytes(path)
	_send_buffer_to_peers(path, buf, exclude_peer)

func broadcast_file_delete(path: String, exclude_peer: int = 0) -> void:
	if not is_path_safe(path) or network == null or not network.is_connected_to_session:
		return
	if network.is_host_peer:
		for pid in network.peers.keys():
			if pid != 1 and pid != exclude_peer:
				network.send_project_file_delete(pid, path)
	else:
		network.send_project_file_delete(1, path)

func _send_buffer_to_peers(path: String, buf: PackedByteArray, exclude_peer: int = 0) -> void:
	if network == null or not network.is_connected_to_session:
		return
		
	var total_size = buf.size()
	var total_chunks = maxi(1, int(ceil(float(total_size) / float(CHUNK_SIZE))))
	
	if network.is_host_peer:
		for pid in network.peers.keys():
			if pid != 1 and pid != exclude_peer:
				for c_idx in range(total_chunks):
					var start_offset = c_idx * CHUNK_SIZE
					var slice = buf.slice(start_offset, start_offset + CHUNK_SIZE)
					network.send_project_file_chunk(pid, path, slice, c_idx, total_chunks)
	else:
		for c_idx in range(total_chunks):
			var start_offset = c_idx * CHUNK_SIZE
			var slice = buf.slice(start_offset, start_offset + CHUNK_SIZE)
			network.send_project_file_chunk(1, path, slice, c_idx, total_chunks)

## Initial sync requested by client upon connection
func start_client_res_sync() -> void:
	if _has_synced_this_connection or _is_initial_syncing:
		return
	if network == null or network.is_host_peer or not network.is_connected_to_session:
		return
		
	_has_synced_this_connection = true
	_file_hashes = get_file_tree_hashes()
	print("[Live Co-Op] Client requesting auto res:// sync from Host (%d local files)..." % _file_hashes.size())
	network.request_project_files(_file_hashes)

## Host receives file hashes request from client
func _on_project_files_requested(client_id: int, client_hashes: Dictionary) -> void:
	if network == null or not network.is_host_peer:
		return
		
	var host_hashes = get_file_tree_hashes()
	_file_hashes = host_hashes
	var files_to_send: Array[String] = []
	
	for path in host_hashes.keys():
		var h_hash = host_hashes[path]
		if not client_hashes.has(path) or client_hashes[path] != h_hash:
			if FileAccess.file_exists(path):
				files_to_send.append(path)
				
	print("[Live Co-Op] Host evaluated client sync request: %d files to transmit." % files_to_send.size())
	network.send_begin_project_download(client_id, files_to_send.size())
	
	if files_to_send.is_empty():
		return
		
	for path in files_to_send:
		var buf = FileAccess.get_file_as_bytes(path)
		var total_size = buf.size()
		var total_chunks = maxi(1, int(ceil(float(total_size) / float(CHUNK_SIZE))))
		
		for c_idx in range(total_chunks):
			var start_offset = c_idx * CHUNK_SIZE
			var slice = buf.slice(start_offset, start_offset + CHUNK_SIZE)
			network.send_project_file_chunk(client_id, path, slice, c_idx, total_chunks)

## Client receives confirmation of incoming initial download
func _on_project_download_started(file_count: int) -> void:
	_target_file_count = file_count
	_downloaded_file_count = 0
	_incoming_chunks.clear()
	
	if file_count == 0:
		_is_initial_syncing = false
		print("[Live Co-Op] All project files (res://) are already up to date with Host!")
		if network:
			network._system_chat("Project files are up to date with Host.")
		sync_completed.emit(0)
		return
		
	_is_initial_syncing = true
	print("[Live Co-Op] Auto-sync started: downloading %d project files from Host..." % file_count)
	if network:
		network._system_chat("Syncing %d project files from Host..." % file_count)
	sync_started.emit(file_count)

## Handles received chunks for both initial sync and live runtime sync
func _on_project_file_chunk_received(sender_id: int, path: String, chunk: PackedByteArray, chunk_index: int, total_chunks: int) -> void:
	if not _incoming_chunks.has(path) or chunk_index == 0:
		_incoming_chunks[path] = PackedByteArray()
		
	_incoming_chunks[path].append_array(chunk)
	
	if chunk_index == total_chunks - 1:
		var file_buffer: PackedByteArray = _incoming_chunks[path]
		_incoming_chunks.erase(path)
		
		# If Host received this file from a client, forward it to all other peers
		if network and network.is_host_peer and sender_id != 1:
			_send_buffer_to_peers(path, file_buffer, sender_id)
			
		_is_remote_writing = true
		_save_synced_file(path, file_buffer)
		_file_hashes[path] = FileAccess.get_sha256(path)
		_is_remote_writing = false
		
		if _is_initial_syncing:
			_downloaded_file_count += 1
			file_synced.emit(path, _downloaded_file_count, _target_file_count)
			print("[Live Co-Op] Initial sync [%d/%d]: %s" % [_downloaded_file_count, _target_file_count, path])
			
			if _downloaded_file_count >= _target_file_count:
				_is_initial_syncing = false
				_on_all_initial_files_downloaded()
		else:
			# Live runtime sync update!
			print("[Live Co-Op] Live file received from peer: ", path)
			file_synced.emit(path, 1, 1)
			_reload_file_in_editor(path)

func _reload_file_in_editor(path: String) -> void:
	if editor_interface == null:
		return
		
	# If the received file is a scene, live SceneSyncManager keeps the active scene in sync in-memory.
	# Disk write is already complete above, so we don't disrupt the user's active viewport/selection.
	if path.ends_with(".tscn"):
		pass
	elif path.ends_with(".gd"):
		var se = editor_interface.get_script_editor()
		if se and se.has_method("reload_open_files"):
			se.reload_open_files.call_deferred()
			
	var fs = editor_interface.get_resource_filesystem()
	if fs:
		fs.scan.call_deferred()

func _on_project_file_deleted(sender_id: int, path: String) -> void:
	if not is_path_safe(path):
		return
		
	if network and network.is_host_peer and sender_id != 1:
		broadcast_file_delete(path, sender_id)
		
	_file_hashes.erase(path)
	_is_remote_writing = true
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		print("[Live Co-Op] Live deleted file from remote: ", path)
	_is_remote_writing = false
	
	if editor_interface:
		var fs = editor_interface.get_resource_filesystem()
		if fs:
			fs.scan.call_deferred()

func _on_all_initial_files_downloaded() -> void:
	print("[Live Co-Op] All %d project files successfully synced from Host!" % _target_file_count)
	if network:
		network._system_chat("All %d project files synchronized with Host." % _target_file_count)
		
	if editor_interface:
		var fs = editor_interface.get_resource_filesystem()
		if fs:
			fs.scan.call_deferred()
		var se = editor_interface.get_script_editor()
		if se and se.has_method("reload_open_files"):
			se.reload_open_files.call_deferred()
			
	sync_completed.emit(_target_file_count)

func _save_synced_file(path: String, buffer: PackedByteArray) -> bool:
	if not is_path_safe(path):
		printerr("[Live Co-Op] Blocked attempt to write to unsafe path: %s" % path)
		return false
		
	var base_dir = path.get_base_dir()
	if base_dir != "res://" and base_dir != "res:/" and not DirAccess.dir_exists_absolute(base_dir):
		var err = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
		if err != OK and err != ERR_ALREADY_EXISTS:
			printerr("[Live Co-Op] Failed creating directory: %s (Error: %d)" % [base_dir, err])
			
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		printerr("[Live Co-Op] Failed to write file: %s (Error: %d)" % [path, FileAccess.get_open_error()])
		return false
		
	file.store_buffer(buffer)
	file.close()
	return true

## Generates dictionary of all valid syncable files in res:// -> SHA-256 hash
func get_file_tree_hashes(root: String = "res://") -> Dictionary:
	var hashes: Dictionary = {}
	_scan_dir_hashes(root, hashes)
	return hashes

func _scan_dir_hashes(dir_path: String, hashes: Dictionary) -> void:
	for ig in IGNORED_PREFIXES:
		if dir_path == ig or dir_path.begins_with(ig + "/"):
			return
			
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
		
	dir.list_dir_begin()
	var item_name = dir.get_next()
	
	while not item_name.is_empty():
		if item_name != "." and item_name != "..":
			var full_path = dir_path.path_join(item_name)
			if dir.current_is_dir():
				_scan_dir_hashes(full_path, hashes)
			else:
				if is_path_safe(full_path):
					var h = FileAccess.get_sha256(full_path)
					if h.is_empty():
						h = FileAccess.get_md5(full_path)
					hashes[full_path] = h
		item_name = dir.get_next()
	dir.list_dir_end()

static func is_path_safe(path: String) -> bool:
	if not path.begins_with("res://") or path.contains(".."):
		return false
	for ig in IGNORED_PREFIXES:
		if path == ig or path.begins_with(ig + "/"):
			return false
	var fname = path.get_file()
	if fname.begins_with(".") or fname.ends_with(".tmp"):
		return false
	return true
