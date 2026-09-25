@tool
class_name CoopNetwork
extends Node

## Signals
signal connection_status_changed(is_connected: bool, is_host: bool, message: String)
signal peer_connected_coop(peer_id: int, profile: Dictionary)
signal peer_disconnected_coop(peer_id: int)
signal peer_profile_updated(peer_id: int, profile: Dictionary)
signal peer_avatar_received(peer_id: int, texture: ImageTexture)

# Network Discovery & UPnP signals
signal upnp_status_updated(success: bool, message: String, public_ip: String)
signal lan_host_discovered(host_name: String, host_ip: String, host_port: int, color_hex: String)

# Script sync signals
signal text_delta_received(sender_id: int, script_path: String, delta: Dictionary)
signal full_file_received(sender_id: int, script_path: String, content: String)
signal caret_moved_received(sender_id: int, script_path: String, line: int, col: int, selection_data: Dictionary)
signal chat_message_received(sender_id: int, username: String, color_hex: String, message: String, timestamp: String)

# Viewport 2D Presence signals
signal viewport_2d_received(sender_id: int, world_rect: Rect2, world_center: Vector2, zoom: float)
signal cursor_2d_received(sender_id: int, world_pos: Vector2, is_active: bool)

signal session_joined()
signal peer_active_file_changed(peer_id: int, file_path: String)

# Live Runtime Scene Sync signals
signal scene_node_updated(sender_id: int, scene_path: String, node_path: String, properties: Dictionary)
signal scene_node_added(sender_id: int, scene_path: String, parent_path: String, node_class: String, scene_file_path: String, properties: Dictionary)
signal scene_node_deleted(sender_id: int, scene_path: String, node_path: String)
signal scene_node_renamed(sender_id: int, scene_path: String, old_path: String, new_name: String)
signal scene_node_reordered(sender_id: int, scene_path: String, parent_path: String, ordered_names: Array)
signal peer_scene_selection_changed(sender_id: int, scene_path: String, node_paths: Array)

# Res:// File Sync signals
signal project_files_requested(sender_id: int, client_hashes: Dictionary)
signal project_download_started(file_count: int)
signal project_file_chunk_received(sender_id: int, path: String, chunk: PackedByteArray, chunk_index: int, total_chunks: int)
signal project_file_deleted(sender_id: int, path: String)

## State
var is_connected_to_session: bool = false
var is_host_peer: bool = false
var host_port: int = 7777
var local_username: String = "Developer"
var local_color: Color = Color.DODGER_BLUE
var local_active_script: String = ""
var local_active_file: String = ""
var local_avatar_bytes: PackedByteArray = []

# UPnP state
var upnp_thread: Thread = null
var upnp: UPNP = null
var upnp_mapped_port: int = -1
var upnp_public_ip: String = ""
var upnp_status_message: String = ""
var is_upnp_active: bool = false

# LAN Auto-Discovery state
const LAN_BEACON_PORT: int = 7788
var lan_broadcaster: PacketPeerUDP = null
var lan_listener: PacketPeerUDP = null
var lan_beacon_timer: float = 0.0

# Dictionary of peer_id -> Dictionary profile
var peers: Dictionary = {}
# Dictionary of peer_id -> ImageTexture
var peer_avatar_textures: Dictionary = {}

var custom_mp: SceneMultiplayer
var enet_peer: ENetMultiplayerPeer

func _enter_tree() -> void:
	_setup_multiplayer_api()

func _exit_tree() -> void:
	disconnect_coop()

func _setup_multiplayer_api() -> void:
	if custom_mp != null:
		return
	custom_mp = SceneMultiplayer.new()
	custom_mp.peer_connected.connect(_on_peer_connected)
	custom_mp.peer_disconnected.connect(_on_peer_disconnected)
	custom_mp.connected_to_server.connect(_on_connected_to_server)
	custom_mp.connection_failed.connect(_on_connection_failed)
	custom_mp.server_disconnected.connect(_on_server_disconnected)
	
	if is_inside_tree():
		get_tree().set_multiplayer(custom_mp, get_path())

func _process(delta: float) -> void:
	if custom_mp != null and custom_mp.has_multiplayer_peer():
		custom_mp.poll()

	# LAN Discovery handling
	if is_connected_to_session and is_host_peer:
		if lan_listener != null:
			lan_listener.close()
			lan_listener = null
		
		lan_beacon_timer += delta
		if lan_beacon_timer >= 1.5:
			lan_beacon_timer = 0.0
			_broadcast_lan_beacon()
	elif not is_connected_to_session:
		if lan_broadcaster != null:
			lan_broadcaster.close()
			lan_broadcaster = null
		_poll_lan_discovery()
	else:
		if lan_broadcaster != null:
			lan_broadcaster.close()
			lan_broadcaster = null
		if lan_listener != null:
			lan_listener.close()
			lan_listener = null

## Broadcasts presence over UDP on the local network so other clients can auto-discover
func _broadcast_lan_beacon() -> void:
	if lan_broadcaster == null:
		lan_broadcaster = PacketPeerUDP.new()
		lan_broadcaster.set_broadcast_enabled(true)
		lan_broadcaster.set_dest_address("255.255.255.255", LAN_BEACON_PORT)
	
	var beacon = {
		"app": "godot_live_coop",
		"name": local_username,
		"port": host_port,
		"lan_ip": get_local_lan_ip(),
		"color": local_color.to_html(false)
	}
	var json_str = JSON.stringify(beacon)
	lan_broadcaster.put_packet(json_str.to_utf8_buffer())

## Polls for UDP beacons from hosts on the local network
func _poll_lan_discovery() -> void:
	if lan_listener == null:
		lan_listener = PacketPeerUDP.new()
		var err = lan_listener.bind(LAN_BEACON_PORT)
		if err != OK:
			lan_listener = null
			return
			
	while lan_listener.get_available_packet_count() > 0:
		var pkt = lan_listener.get_packet()
		var sender_ip = lan_listener.get_packet_ip()
		var json = JSON.new()
		var parse_err = json.parse(pkt.get_string_from_utf8())
		if parse_err == OK and json.data is Dictionary:
			var d = json.data
			if d.get("app") == "godot_live_coop":
				var h_name = str(d.get("name", "Host"))
				var h_port = int(d.get("port", 7777))
				var h_color = str(d.get("color", "3498db"))
				var h_ip = sender_ip
				if h_ip.is_empty() or h_ip == "127.0.0.1":
					h_ip = str(d.get("lan_ip", "127.0.0.1"))
				lan_host_discovered.emit(h_name, h_ip, h_port, h_color)

## Helper to retrieve a peer's avatar ImageTexture
func get_peer_avatar_texture(peer_id: int) -> ImageTexture:
	if peer_id == (custom_mp.get_unique_id() if custom_mp else 1):
		return _create_texture_from_bytes(local_avatar_bytes)
	return peer_avatar_textures.get(peer_id, null)

func _create_texture_from_bytes(bytes: PackedByteArray) -> ImageTexture:
	if bytes.is_empty():
		return null
	var img = Image.new()
	if img.load_png_from_buffer(bytes) == OK:
		return ImageTexture.create_from_image(img)
	return null

func get_local_lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			return ip
		if ip.begins_with("172."):
			var parts = ip.split(".")
			if parts.size() >= 2:
				var second = int(parts[1])
				if second >= 16 and second <= 31:
					return ip
	return "127.0.0.1"

## --- Connection Management ---

func start_host(port: int, username: String, color: Color, avatar_bytes: PackedByteArray = [], p_use_upnp: bool = false) -> Error:
	disconnect_coop()
	_setup_multiplayer_api()
	
	host_port = port
	local_username = username
	local_color = color
	local_avatar_bytes = avatar_bytes
	
	enet_peer = ENetMultiplayerPeer.new()
	var err = enet_peer.create_server(port, 16)
	if err != OK:
		var err_msg = "Failed to host on port %d (Error %d)" % [port, err]
		connection_status_changed.emit(false, false, err_msg)
		return err
		
	custom_mp.multiplayer_peer = enet_peer
	is_connected_to_session = true
	is_host_peer = true
	
	peers.clear()
	peer_avatar_textures.clear()
	
	if not local_avatar_bytes.is_empty():
		peer_avatar_textures[1] = _create_texture_from_bytes(local_avatar_bytes)
		
	peers[1] = {
		"id": 1,
		"username": local_username,
		"color_hex": local_color.to_html(false),
		"active_script": local_active_script,
		"active_file": local_active_file,
		"caret_line": 0,
		"caret_col": 0,
		"selection": {},
		"avatar_bytes": local_avatar_bytes
	}
	
	connection_status_changed.emit(true, true, "Hosting on port %d" % port)
	
	# Start UPnP discovery in background thread if enabled
	if p_use_upnp:
		upnp_status_message = "Discovering UPnP gateway..."
		upnp_status_updated.emit(false, upnp_status_message, "")
		_start_upnp_discovery(port)
	else:
		is_upnp_active = false
		upnp_status_message = ""
		
	# Broadcast initial LAN beacon immediately
	_broadcast_lan_beacon()
	return OK

func _start_upnp_discovery(port: int) -> void:
	if upnp_thread != null and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
	upnp_thread = Thread.new()
	upnp_thread.start(_thread_upnp_work.bind(port))

func _thread_upnp_work(port: int) -> void:
	var u = UPNP.new()
	var disc_err = u.discover(2000, 2, "InternetGatewayDevice")
	if disc_err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_on_upnp_result", false, "UPnP discover failed (code %d)" % disc_err, "", null, -1)
		return
	var gw = u.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		call_deferred("_on_upnp_result", false, "No valid UPnP gateway found on router", "", null, -1)
		return
	var map_err = u.add_port_mapping(port, port, "GodotLiveCoOp", "UDP")
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_on_upnp_result", false, "Port mapping failed (code %d)" % map_err, "", null, -1)
		return
	var ext_ip = u.query_external_address()
	call_deferred("_on_upnp_result", true, "Port %d forwarded via UPnP" % port, ext_ip, u, port)

func _on_upnp_result(success: bool, msg: String, ext_ip: String, u_obj: UPNP, mapped_p: int) -> void:
	if upnp_thread != null and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
		upnp_thread = null
		
	if not is_connected_to_session or not is_host_peer:
		if u_obj != null and mapped_p > 0:
			u_obj.delete_port_mapping(mapped_p, "UDP")
		return
		
	if success:
		upnp = u_obj
		upnp_mapped_port = mapped_p
		upnp_public_ip = ext_ip
		is_upnp_active = true
		upnp_status_message = "Port %d forwarded (Public: %s)" % [mapped_p, ext_ip]
	else:
		is_upnp_active = false
		upnp_status_message = msg
		
	upnp_status_updated.emit(success, upnp_status_message, ext_ip)

func join_host(host_ip: String, port: int, username: String, color: Color, avatar_bytes: PackedByteArray = []) -> Error:
	disconnect_coop()
	_setup_multiplayer_api()
	
	local_username = username
	local_color = color
	local_avatar_bytes = avatar_bytes
	
	enet_peer = ENetMultiplayerPeer.new()
	var err = enet_peer.create_client(host_ip, port)
	if err != OK:
		var err_msg = "Failed to connect to %s:%d (Error %d)" % [host_ip, port, err]
		connection_status_changed.emit(false, false, err_msg)
		return err
		
	custom_mp.multiplayer_peer = enet_peer
	is_host_peer = false
	connection_status_changed.emit(false, false, "Connecting to %s:%d..." % [host_ip, port])
	return OK

func disconnect_coop() -> void:
	# Cleanup UPnP
	if upnp_thread != null and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
		upnp_thread = null
	if upnp != null and upnp_mapped_port > 0:
		upnp.delete_port_mapping(upnp_mapped_port, "UDP")
		upnp = null
		upnp_mapped_port = -1
	is_upnp_active = false
	upnp_public_ip = ""
	upnp_status_message = ""
	
	# Cleanup LAN sockets
	if lan_broadcaster != null:
		lan_broadcaster.close()
		lan_broadcaster = null
	if lan_listener != null:
		lan_listener.close()
		lan_listener = null
	lan_beacon_timer = 0.0
	
	if custom_mp != null and custom_mp.has_multiplayer_peer():
		custom_mp.multiplayer_peer.close()
		custom_mp.multiplayer_peer = null
	
	enet_peer = null
	is_connected_to_session = false
	is_host_peer = false
	peers.clear()
	peer_avatar_textures.clear()
	connection_status_changed.emit(false, false, "Disconnected")

## --- Low-Level Multiplayer Signals ---

func _on_peer_connected(peer_id: int) -> void:
	if is_host_peer:
		pass

func _on_peer_disconnected(peer_id: int) -> void:
	if peers.has(peer_id):
		var prof = peers[peer_id]
		peers.erase(peer_id)
		peer_avatar_textures.erase(peer_id)
		peer_disconnected_coop.emit(peer_id)
		if is_host_peer:
			_broadcast_peer_left(peer_id)
			_system_chat("%s has disconnected." % prof.get("username", "Peer %d" % peer_id))

func _on_connected_to_server() -> void:
	is_connected_to_session = true
	var my_id = custom_mp.get_unique_id()
	if not local_avatar_bytes.is_empty():
		peer_avatar_textures[my_id] = _create_texture_from_bytes(local_avatar_bytes)
	connection_status_changed.emit(true, false, "Connected to Host!")
	var cur_file = local_active_file if not local_active_file.is_empty() else local_active_script
	rpc_id(1, "_rpc_register_client", local_username, local_color.to_html(false), cur_file, local_avatar_bytes)

func _on_connection_failed() -> void:
	disconnect_coop()
	connection_status_changed.emit(false, false, "Connection to host failed.")

func _on_server_disconnected() -> void:
	disconnect_coop()
	connection_status_changed.emit(false, false, "Host disconnected.")

## --- User Registration & Sync RPCs ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_client(username: String, color_hex: String, active_file: String, avatar_bytes: PackedByteArray = []) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	var new_peer = {
		"id": sender_id,
		"username": username,
		"color_hex": color_hex,
		"active_script": active_file if active_file.ends_with(".gd") else "",
		"active_file": active_file,
		"caret_line": 0,
		"caret_col": 0,
		"selection": {},
		"avatar_bytes": avatar_bytes
	}
	peers[sender_id] = new_peer
	if not avatar_bytes.is_empty():
		var tex = _create_texture_from_bytes(avatar_bytes)
		if tex:
			peer_avatar_textures[sender_id] = tex
			peer_avatar_received.emit(sender_id, tex)
	
	rpc_id(sender_id, "_rpc_sync_all_peers", peers)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_peer_joined", new_peer)
			
	peer_connected_coop.emit(sender_id, new_peer)
	_system_chat("%s joined the session!" % username)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_all_peers(peer_dict: Dictionary) -> void:
	peers = peer_dict.duplicate(true)
	for pid_str in peers.keys():
		var pid = int(pid_str)
		var pinfo = peers[pid_str]
		var av_bytes: PackedByteArray = pinfo.get("avatar_bytes", [])
		if not av_bytes.is_empty():
			var tex = _create_texture_from_bytes(av_bytes)
			if tex:
				peer_avatar_textures[pid] = tex
				peer_avatar_received.emit(pid, tex)
		peer_connected_coop.emit(pid, pinfo)
	session_joined.emit()

@rpc("authority", "call_remote", "reliable")
func _rpc_peer_joined(peer_profile: Dictionary) -> void:
	var pid = int(peer_profile.get("id", 0))
	peers[pid] = peer_profile
	var av_bytes: PackedByteArray = peer_profile.get("avatar_bytes", [])
	if not av_bytes.is_empty():
		var tex = _create_texture_from_bytes(av_bytes)
		if tex:
			peer_avatar_textures[pid] = tex
			peer_avatar_received.emit(pid, tex)
	peer_connected_coop.emit(pid, peer_profile)

func _broadcast_peer_left(peer_id: int) -> void:
	for pid in peers.keys():
		if pid != 1 and pid != peer_id:
			rpc_id(pid, "_rpc_peer_left", peer_id)

@rpc("authority", "call_remote", "reliable")
func _rpc_peer_left(peer_id: int) -> void:
	if peers.has(peer_id):
		peers.erase(peer_id)
		peer_avatar_textures.erase(peer_id)
		peer_disconnected_coop.emit(peer_id)

## --- 2D Viewport Camera Presence ---

func send_2d_viewport(world_rect: Rect2, world_center: Vector2, zoom: float) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_viewport_2d", 1, world_rect, world_center, zoom)
	else:
		rpc_id(1, "_rpc_client_send_viewport_2d", world_rect, world_center, zoom)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_client_send_viewport_2d(world_rect: Rect2, world_center: Vector2, zoom: float) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	viewport_2d_received.emit(sender_id, world_rect, world_center, zoom)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_viewport_2d", sender_id, world_rect, world_center, zoom)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_receive_viewport_2d(sender_id: int, world_rect: Rect2, world_center: Vector2, zoom: float) -> void:
	viewport_2d_received.emit(sender_id, world_rect, world_center, zoom)

## --- 2D Collaborator Mouse Presence ---

func send_2d_cursor(world_pos: Vector2, is_active: bool) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_cursor_2d", 1, world_pos, is_active)
	else:
		rpc_id(1, "_rpc_client_send_cursor_2d", world_pos, is_active)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_client_send_cursor_2d(world_pos: Vector2, is_active: bool) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	cursor_2d_received.emit(sender_id, world_pos, is_active)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_cursor_2d", sender_id, world_pos, is_active)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_cursor_2d(sender_id: int, world_pos: Vector2, is_active: bool) -> void:
	cursor_2d_received.emit(sender_id, world_pos, is_active)

## --- Live Runtime Scene Synchronization ---

func send_scene_node_update(scene_path: String, node_path: String, properties: Dictionary) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_scene_node_update", 1, scene_path, node_path, properties)
	else:
		rpc_id(1, "_rpc_client_send_scene_node_update", scene_path, node_path, properties)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_scene_node_update(scene_path: String, node_path: String, properties: Dictionary) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	scene_node_updated.emit(sender_id, scene_path, node_path, properties)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_scene_node_update", sender_id, scene_path, node_path, properties)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_scene_node_update(sender_id: int, scene_path: String, node_path: String, properties: Dictionary) -> void:
	scene_node_updated.emit(sender_id, scene_path, node_path, properties)

func send_scene_node_add(scene_path: String, parent_path: String, node_class: String, scene_file_path: String, properties: Dictionary) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_scene_node_add", 1, scene_path, parent_path, node_class, scene_file_path, properties)
	else:
		rpc_id(1, "_rpc_client_send_scene_node_add", scene_path, parent_path, node_class, scene_file_path, properties)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_scene_node_add(scene_path: String, parent_path: String, node_class: String, scene_file_path: String, properties: Dictionary) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	scene_node_added.emit(sender_id, scene_path, parent_path, node_class, scene_file_path, properties)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_scene_node_add", sender_id, scene_path, parent_path, node_class, scene_file_path, properties)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_scene_node_add(sender_id: int, scene_path: String, parent_path: String, node_class: String, scene_file_path: String, properties: Dictionary) -> void:
	scene_node_added.emit(sender_id, scene_path, parent_path, node_class, scene_file_path, properties)

func send_scene_node_delete(scene_path: String, node_path: String) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_scene_node_delete", 1, scene_path, node_path)
	else:
		rpc_id(1, "_rpc_client_send_scene_node_delete", scene_path, node_path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_scene_node_delete(scene_path: String, node_path: String) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	scene_node_deleted.emit(sender_id, scene_path, node_path)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_scene_node_delete", sender_id, scene_path, node_path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_scene_node_delete(sender_id: int, scene_path: String, node_path: String) -> void:
	scene_node_deleted.emit(sender_id, scene_path, node_path)

func send_scene_node_rename(scene_path: String, old_path: String, new_name: String) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_scene_node_rename", 1, scene_path, old_path, new_name)
	else:
		rpc_id(1, "_rpc_client_send_scene_node_rename", scene_path, old_path, new_name)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_scene_node_rename(scene_path: String, old_path: String, new_name: String) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	scene_node_renamed.emit(sender_id, scene_path, old_path, new_name)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_scene_node_rename", sender_id, scene_path, old_path, new_name)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_scene_node_rename(sender_id: int, scene_path: String, old_path: String, new_name: String) -> void:
	scene_node_renamed.emit(sender_id, scene_path, old_path, new_name)

func send_scene_node_reorder(scene_path: String, parent_path: String, ordered_names: Array) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_scene_node_reorder", 1, scene_path, parent_path, ordered_names)
	else:
		rpc_id(1, "_rpc_client_send_scene_node_reorder", scene_path, parent_path, ordered_names)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_scene_node_reorder(scene_path: String, parent_path: String, ordered_names: Array) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	scene_node_reordered.emit(sender_id, scene_path, parent_path, ordered_names)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_scene_node_reorder", sender_id, scene_path, parent_path, ordered_names)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_scene_node_reorder(sender_id: int, scene_path: String, parent_path: String, ordered_names: Array) -> void:
	scene_node_reordered.emit(sender_id, scene_path, parent_path, ordered_names)

## --- Scene Selection Sync ---

func send_scene_selection(scene_path: String, node_paths: Array) -> void:
	if not is_connected_to_session:
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_scene_selection", 1, scene_path, node_paths)
	else:
		rpc_id(1, "_rpc_client_send_scene_selection", scene_path, node_paths)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_client_send_scene_selection(scene_path: String, node_paths: Array) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	peer_scene_selection_changed.emit(sender_id, scene_path, node_paths)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_scene_selection", sender_id, scene_path, node_paths)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_scene_selection(sender_id: int, scene_path: String, node_paths: Array) -> void:
	peer_scene_selection_changed.emit(sender_id, scene_path, node_paths)

## --- Script & Delta Synchronization ---

func send_delta(script_path: String, delta: Dictionary) -> void:
	if not is_connected_to_session or delta.get("empty", false):
		return
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_delta", script_path, delta)
	else:
		rpc_id(1, "_rpc_client_send_delta", script_path, delta)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_delta(script_path: String, delta: Dictionary) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	text_delta_received.emit(sender_id, script_path, delta)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_delta", script_path, delta)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_delta(script_path: String, delta: Dictionary) -> void:
	var sender_id = custom_mp.get_remote_sender_id()
	text_delta_received.emit(sender_id, script_path, delta)

func send_caret(script_path: String, line: int, col: int, selection_data: Dictionary) -> void:
	if not is_connected_to_session:
		return
	local_active_script = script_path
	if is_host_peer:
		peers[1]["active_script"] = script_path
		peers[1]["caret_line"] = line
		peers[1]["caret_col"] = col
		peers[1]["selection"] = selection_data
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_caret", 1, script_path, line, col, selection_data)
	else:
		rpc_id(1, "_rpc_client_send_caret", script_path, line, col, selection_data)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_client_send_caret(script_path: String, line: int, col: int, selection_data: Dictionary) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	if peers.has(sender_id):
		peers[sender_id]["active_script"] = script_path
		peers[sender_id]["caret_line"] = line
		peers[sender_id]["caret_col"] = col
		peers[sender_id]["selection"] = selection_data
	caret_moved_received.emit(sender_id, script_path, line, col, selection_data)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_caret", sender_id, script_path, line, col, selection_data)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_receive_caret(sender_id: int, script_path: String, line: int, col: int, selection_data: Dictionary) -> void:
	if peers.has(sender_id):
		peers[sender_id]["active_script"] = script_path
		peers[sender_id]["caret_line"] = line
		peers[sender_id]["caret_col"] = col
		peers[sender_id]["selection"] = selection_data
	caret_moved_received.emit(sender_id, script_path, line, col, selection_data)

func request_full_file(script_path: String) -> void:
	if not is_connected_to_session or is_host_peer:
		return
	rpc_id(1, "_rpc_request_file", script_path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_file(script_path: String) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	if FileAccess.file_exists(script_path):
		var file = FileAccess.open(script_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			rpc_id(sender_id, "_rpc_receive_full_file", script_path, content)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_full_file(script_path: String, content: String) -> void:
	var sender_id = custom_mp.get_remote_sender_id()
	full_file_received.emit(sender_id, script_path, content)

## --- Team Chat ---

func send_chat(message: String) -> void:
	if not is_connected_to_session or message.strip_edges().is_empty():
		return
	var now = Time.get_time_string_from_system()
	var my_id = custom_mp.get_unique_id() if custom_mp else 1
	# Emit locally so sender always sees their own message immediately
	chat_message_received.emit(my_id, local_username, local_color.to_html(false), message, now)
	
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_chat", 1, local_username, local_color.to_html(false), message, now)
	else:
		rpc_id(1, "_rpc_client_send_chat", message, now)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_chat(message: String, timestamp: String) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	var username = peers.get(sender_id, {}).get("username", "Peer %d" % sender_id)
	var color_hex = peers.get(sender_id, {}).get("color_hex", "ffffff")
	chat_message_received.emit(sender_id, username, color_hex, message, timestamp)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_chat", sender_id, username, color_hex, message, timestamp)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_chat(sender_id: int, username: String, color_hex: String, message: String, timestamp: String) -> void:
	chat_message_received.emit(sender_id, username, color_hex, message, timestamp)

func _system_chat(text: String) -> void:
	var now = Time.get_time_string_from_system()
	chat_message_received.emit(0, "System", "aaaaaa", text, now)
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_chat", 0, "System", "aaaaaa", text, now)

## --- Res:// Project File Syncing ---

func request_project_files(local_hashes: Dictionary) -> void:
	if not is_connected_to_session or is_host_peer:
		return
	rpc_id(1, "_rpc_project_files_request", local_hashes)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_project_files_request(client_hashes: Dictionary) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	project_files_requested.emit(sender_id, client_hashes)

func send_begin_project_download(target_id: int, file_count: int) -> void:
	if not is_connected_to_session:
		return
	rpc_id(target_id, "_rpc_begin_project_download", file_count)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_begin_project_download(file_count: int) -> void:
	project_download_started.emit(file_count)

func send_project_file_chunk(target_id: int, path: String, chunk: PackedByteArray, chunk_index: int, total_chunks: int) -> void:
	if not is_connected_to_session:
		return
	rpc_id(target_id, "_rpc_receive_project_file_chunk", path, chunk, chunk_index, total_chunks)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_project_file_chunk(path: String, chunk: PackedByteArray, chunk_index: int, total_chunks: int) -> void:
	var sender_id = custom_mp.get_remote_sender_id()
	project_file_chunk_received.emit(sender_id, path, chunk, chunk_index, total_chunks)

func send_project_file_delete(target_id: int, path: String) -> void:
	if not is_connected_to_session:
		return
	rpc_id(target_id, "_rpc_receive_project_file_delete", path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_project_file_delete(path: String) -> void:
	var sender_id = custom_mp.get_remote_sender_id()
	project_file_deleted.emit(sender_id, path)

## --- Active File Synchronization ---

func send_active_file(file_path: String) -> void:
	if not is_connected_to_session:
		return
	local_active_file = file_path
	var my_id = custom_mp.get_unique_id() if custom_mp else 1
	if peers.has(my_id):
		peers[my_id]["active_file"] = file_path
	peer_active_file_changed.emit(my_id, file_path)
	
	if is_host_peer:
		for pid in peers.keys():
			if pid != 1:
				rpc_id(pid, "_rpc_receive_active_file", 1, file_path)
	else:
		rpc_id(1, "_rpc_client_send_active_file", file_path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_send_active_file(file_path: String) -> void:
	if not is_host_peer:
		return
	var sender_id = custom_mp.get_remote_sender_id()
	if peers.has(sender_id):
		peers[sender_id]["active_file"] = file_path
	peer_active_file_changed.emit(sender_id, file_path)
	for pid in peers.keys():
		if pid != sender_id and pid != 1:
			rpc_id(pid, "_rpc_receive_active_file", sender_id, file_path)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_active_file(sender_id: int, file_path: String) -> void:
	if peers.has(sender_id):
		peers[sender_id]["active_file"] = file_path
	peer_active_file_changed.emit(sender_id, file_path)



