@tool
class_name CoopDock
extends Control

signal toggle_viewports_requested(enabled: bool)
signal toggle_mouse_requested(enabled: bool)

const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")
const ScriptSyncManager = preload("res://addons/live_coop/editor/script_sync_manager.gd")
const ResSyncManager = preload("res://addons/live_coop/editor/res_sync_manager.gd")
const GithubService = preload("res://addons/live_coop/network/github_service.gd")

var network: CoopNetwork
var script_sync_manager: ScriptSyncManager
var res_sync_manager: ResSyncManager
var github_service: GithubService

@onready var status_badge: Label = $VBox/Header/StatusBadge

# Profile & GitHub controls
@onready var username_input: LineEdit = $VBox/TabContainer/Session/VBox/ProfileGroup/UsernameInput
@onready var color_picker: ColorPickerButton = $VBox/TabContainer/Session/VBox/ProfileGroup/ColorPicker

@onready var github_token_input: LineEdit = $VBox/TabContainer/Session/VBox/GithubGroup/TokenHBox/TokenInput
@onready var github_connect_btn: Button = $VBox/TabContainer/Session/VBox/GithubGroup/TokenHBox/ConnectBtn
@onready var github_generate_token_btn: Button = $VBox/TabContainer/Session/VBox/GithubGroup/GenerateTokenBtn
@onready var github_profile_box: HBoxContainer = $VBox/TabContainer/Session/VBox/GithubGroup/ProfileHBox
@onready var github_avatar_rect: TextureRect = $VBox/TabContainer/Session/VBox/GithubGroup/ProfileHBox/AvatarRect
@onready var github_user_label: Label = $VBox/TabContainer/Session/VBox/GithubGroup/ProfileHBox/UserLabel
@onready var github_disconnect_btn: Button = $VBox/TabContainer/Session/VBox/GithubGroup/ProfileHBox/DisconnectGithubBtn
@onready var github_status_label: Label = $VBox/TabContainer/Session/VBox/GithubGroup/StatusLabel
@onready var token_hbox: HBoxContainer = $VBox/TabContainer/Session/VBox/GithubGroup/TokenHBox

# Host / Join controls
@onready var host_port_spin: SpinBox = $VBox/TabContainer/Session/VBox/HostGroup/PortSpin
@onready var upnp_chk: CheckBox = $VBox/TabContainer/Session/VBox/HostGroup/UPNPChk
@onready var host_btn: Button = $VBox/TabContainer/Session/VBox/HostGroup/HostBtn
@onready var lan_quick_join_btn: Button = $VBox/TabContainer/Session/VBox/JoinGroup/LanQuickJoinBtn
@onready var join_ip_input: LineEdit = $VBox/TabContainer/Session/VBox/JoinGroup/IPInput
@onready var join_port_spin: SpinBox = $VBox/TabContainer/Session/VBox/JoinGroup/PortSpin
@onready var join_btn: Button = $VBox/TabContainer/Session/VBox/JoinGroup/JoinBtn
@onready var disconnect_btn: Button = $VBox/TabContainer/Session/VBox/DisconnectBtn

var discovered_lan_host: Dictionary = {}
var discovered_lan_timer: float = 0.0

# Viewport & Mouse presence controls
@onready var show_viewport_chk: CheckBox = $VBox/TabContainer/Session/VBox/ShowViewportChk
@onready var show_mouse_chk: CheckBox = $VBox/TabContainer/Session/VBox/ShowMouseChk

# Collaborators controls
@onready var peers_list_container: VBoxContainer = $VBox/TabContainer/Collaborators/VBox/Scroll/PeerList
@onready var peer_count_label: Label = $VBox/TabContainer/Collaborators/VBox/Header/CountLabel

# Chat controls
@onready var chat_scroll: ScrollContainer = $VBox/TabContainer/Chat/VBox/ChatScroll
@onready var chat_message_list: VBoxContainer = $VBox/TabContainer/Chat/VBox/ChatScroll/ChatMessageList
@onready var chat_input_panel: PanelContainer = $VBox/TabContainer/Chat/VBox/InputPanel
@onready var chat_input: LineEdit = $VBox/TabContainer/Chat/VBox/InputPanel/InputHBox/ChatInput
@onready var chat_send_btn: Button = $VBox/TabContainer/Chat/VBox/InputPanel/InputHBox/SendBtn

const PALETTE = [
	Color("#3498db"), Color("#2ecc71"), Color("#e74c3c"), Color("#f39c12"),
	Color("#9b59b6"), Color("#1abc9c"), Color("#e67e22"), Color("#ff6b81")
]

func _ready() -> void:
	if color_picker and color_picker.color == Color.WHITE:
		color_picker.color = PALETTE[randi() % PALETTE.size()]
	
	if username_input and username_input.text.is_empty():
		var env_user = OS.get_environment("USERNAME")
		if env_user.is_empty():
			env_user = OS.get_environment("USER")
		username_input.text = env_user if not env_user.is_empty() else "Dev_%d" % (randi() % 900 + 100)

	if chat_scroll:
		var empty_sb = StyleBoxEmpty.new()
		chat_scroll.add_theme_stylebox_override("panel", empty_sb)

	# Discord-style chat input bar setup
	if chat_input_panel:
		var pill_sb = StyleBoxFlat.new()
		pill_sb.bg_color = Color("#383a40")
		pill_sb.set_corner_radius_all(18)
		pill_sb.content_margin_left = 14
		pill_sb.content_margin_right = 8
		pill_sb.content_margin_top = 6
		pill_sb.content_margin_bottom = 6
		chat_input_panel.add_theme_stylebox_override("panel", pill_sb)

	if chat_input:
		chat_input.add_theme_color_override("font_color", Color("#dbdee1"))
		chat_input.add_theme_color_override("font_placeholder_color", Color("#949ba4"))
		chat_input.add_theme_font_size_override("font_size", 14)
		var empty_sb = StyleBoxEmpty.new()
		chat_input.add_theme_stylebox_override("normal", empty_sb)
		chat_input.add_theme_stylebox_override("focus", empty_sb)

	if chat_send_btn:
		var send_sb = StyleBoxFlat.new()
		send_sb.bg_color = Color("#5865f2") # Discord blurple
		send_sb.set_corner_radius_all(14)
		send_sb.content_margin_left = 14
		send_sb.content_margin_right = 14
		send_sb.content_margin_top = 6
		send_sb.content_margin_bottom = 6
		chat_send_btn.add_theme_stylebox_override("normal", send_sb)
		chat_send_btn.add_theme_font_size_override("font_size", 13)
		var send_hover = send_sb.duplicate()
		send_hover.bg_color = Color("#4752c4")
		chat_send_btn.add_theme_stylebox_override("hover", send_hover)

	_setup_signals()
	_update_ui_state()

func _process(delta: float) -> void:
	if discovered_lan_timer > 0.0:
		discovered_lan_timer -= delta
		if discovered_lan_timer <= 0.0:
			discovered_lan_host.clear()
			if lan_quick_join_btn:
				lan_quick_join_btn.visible = false

func setup(p_network: CoopNetwork, p_script_sync: ScriptSyncManager, p_res_sync: ResSyncManager = null, p_github: GithubService = null) -> void:
	network = p_network
	script_sync_manager = p_script_sync
	res_sync_manager = p_res_sync
	github_service = p_github
	
	if network:
		network.connection_status_changed.connect(_on_connection_status_changed)
		network.peer_connected_coop.connect(_on_peer_list_changed)
		network.peer_disconnected_coop.connect(_on_peer_list_changed)
		network.peer_avatar_received.connect(func(_pid, _tex): _rebuild_peer_list())
		network.caret_moved_received.connect(_on_caret_or_script_updated)
		network.chat_message_received.connect(_on_chat_message_received)
		network.upnp_status_updated.connect(_on_upnp_status_updated)
		network.lan_host_discovered.connect(_on_lan_host_discovered)
		
	if github_service:
		github_service.authenticated.connect(_on_github_authenticated)
		github_service.auth_failed.connect(_on_github_auth_failed)
		github_service.logged_out.connect(_on_github_logged_out)
		github_service.avatar_updated.connect(func(tex):
			if github_avatar_rect:
				github_avatar_rect.texture = tex
		)
		if github_service.is_authenticated:
			_on_github_authenticated({
				"username": github_service.github_username,
				"id": github_service.github_id,
				"color": github_service.user_color,
				"avatar_texture": github_service.avatar_texture
			})
		
	_update_ui_state()

func _setup_signals() -> void:
	if host_btn and not host_btn.pressed.is_connected(_on_host_pressed):
		host_btn.pressed.connect(_on_host_pressed)
	if lan_quick_join_btn and not lan_quick_join_btn.pressed.is_connected(_on_lan_quick_join_pressed):
		lan_quick_join_btn.pressed.connect(_on_lan_quick_join_pressed)
	if join_btn and not join_btn.pressed.is_connected(_on_join_pressed):
		join_btn.pressed.connect(_on_join_pressed)
	if disconnect_btn and not disconnect_btn.pressed.is_connected(_on_disconnect_pressed):
		disconnect_btn.pressed.connect(_on_disconnect_pressed)
	if chat_send_btn and not chat_send_btn.pressed.is_connected(_on_send_chat_pressed):
		chat_send_btn.pressed.connect(_on_send_chat_pressed)
	if chat_input and not chat_input.text_submitted.is_connected(_on_chat_submitted):
		chat_input.text_submitted.connect(_on_chat_submitted)
		
	if show_viewport_chk and not show_viewport_chk.toggled.is_connected(_on_show_viewport_toggled):
		show_viewport_chk.toggled.connect(_on_show_viewport_toggled)
	if show_mouse_chk and not show_mouse_chk.toggled.is_connected(_on_show_mouse_toggled):
		show_mouse_chk.toggled.connect(_on_show_mouse_toggled)

	# GitHub signals
	if github_generate_token_btn and not github_generate_token_btn.pressed.is_connected(_on_generate_token_pressed):
		github_generate_token_btn.pressed.connect(_on_generate_token_pressed)
	if github_connect_btn and not github_connect_btn.pressed.is_connected(_on_connect_github_pressed):
		github_connect_btn.pressed.connect(_on_connect_github_pressed)
	if github_disconnect_btn and not github_disconnect_btn.pressed.is_connected(_on_disconnect_github_pressed):
		github_disconnect_btn.pressed.connect(_on_disconnect_github_pressed)

## --- GitHub Event Handlers ---

func _on_generate_token_pressed() -> void:
	var url = "https://github.com/settings/tokens/new?scopes=repo,read:user&description=Godot%20Live%20Co-Op"
	OS.shell_open(url)
	if github_status_label:
		github_status_label.text = "Browser opened. Generate and paste your token below."
		github_status_label.modulate = Color(0.3, 0.7, 1.0)

func _on_connect_github_pressed() -> void:
	if github_service == null or github_token_input == null:
		return
	var token = github_token_input.text.strip_edges()
	if token.is_empty():
		if github_status_label:
			github_status_label.text = "Please enter a Personal Access Token."
		return
	if github_status_label:
		github_status_label.text = "Connecting to GitHub..."
	github_service.connect_with_token(token)

func _on_disconnect_github_pressed() -> void:
	if github_service:
		github_service.logout()

func _on_github_authenticated(profile: Dictionary) -> void:
	var uname = profile.get("username", "")
	var col: Color = profile.get("color", Color.DODGER_BLUE)
	var tex = profile.get("avatar_texture", null)
	
	if username_input:
		username_input.text = uname
	if color_picker:
		color_picker.color = col
		
	if github_generate_token_btn:
		github_generate_token_btn.visible = false
	if token_hbox:
		token_hbox.visible = false
	if github_profile_box:
		github_profile_box.visible = true
	if github_avatar_rect:
		github_avatar_rect.texture = tex
	if github_user_label:
		github_user_label.text = "@%s (Synced)" % uname
	if github_status_label:
		github_status_label.text = "Color & Profile connected from GitHub."
		github_status_label.modulate = Color("#2ecc71")

func _on_github_auth_failed(msg: String) -> void:
	if github_status_label:
		github_status_label.text = msg
		github_status_label.modulate = Color("#e74c3c")

func _on_github_logged_out() -> void:
	if github_generate_token_btn:
		github_generate_token_btn.visible = true
	if token_hbox:
		token_hbox.visible = true
	if github_profile_box:
		github_profile_box.visible = false
	if github_token_input:
		github_token_input.text = ""
	if github_status_label:
		github_status_label.text = "Not connected to GitHub."
		github_status_label.modulate = Color(0.7, 0.7, 0.7)

## --- Host & Join Handlers ---

func _on_host_pressed() -> void:
	if network == null:
		return
	var uname = username_input.text.strip_edges()
	if uname.is_empty(): uname = "Host"
	var col = color_picker.color
	var port = int(host_port_spin.value)
	var use_upnp = upnp_chk.button_pressed if upnp_chk else false
	var av_bytes = github_service.avatar_bytes if (github_service and github_service.is_authenticated) else PackedByteArray()
	network.start_host(port, uname, col, av_bytes, use_upnp)

func _on_join_pressed() -> void:
	if network == null:
		return
	var uname = username_input.text.strip_edges()
	if uname.is_empty(): uname = "Guest"
	var col = color_picker.color
	var ip = join_ip_input.text.strip_edges()
	if ip.is_empty(): ip = "127.0.0.1"
	var port = int(join_port_spin.value)
	var av_bytes = github_service.avatar_bytes if (github_service and github_service.is_authenticated) else PackedByteArray()
	network.join_host(ip, port, uname, col, av_bytes)

func _on_lan_quick_join_pressed() -> void:
	if discovered_lan_host.is_empty():
		return
	if join_ip_input:
		join_ip_input.text = str(discovered_lan_host.get("ip", "127.0.0.1"))
	if join_port_spin:
		join_port_spin.value = int(discovered_lan_host.get("port", 7777))
	_on_join_pressed()

func _on_lan_host_discovered(h_name: String, h_ip: String, h_port: int, _h_color: String) -> void:
	if network != null and network.is_connected_to_session:
		if lan_quick_join_btn:
			lan_quick_join_btn.visible = false
		return
		
	discovered_lan_host = {
		"name": h_name,
		"ip": h_ip,
		"port": h_port
	}
	discovered_lan_timer = 4.0
	
	if lan_quick_join_btn:
		lan_quick_join_btn.text = "⚡ Found Host '%s' on LAN (%s:%d) - Click to Join" % [h_name, h_ip, h_port]
		lan_quick_join_btn.visible = true

func _on_upnp_status_updated(_success: bool, _message: String, _public_ip: String) -> void:
	_update_ui_state()

func _on_disconnect_pressed() -> void:
	if network:
		network.disconnect_coop()
	discovered_lan_host.clear()
	discovered_lan_timer = 0.0
	if lan_quick_join_btn:
		lan_quick_join_btn.visible = false


func _on_show_viewport_toggled(button_pressed: bool) -> void:
	toggle_viewports_requested.emit(button_pressed)

func _on_show_mouse_toggled(button_pressed: bool) -> void:
	toggle_mouse_requested.emit(button_pressed)

func _on_connection_status_changed(_is_connected: bool, _is_host: bool, msg: String) -> void:
	_update_ui_state(msg)
	_rebuild_peer_list()

func _on_peer_list_changed(_peer_id: int, _data = null) -> void:
	_rebuild_peer_list()

func _on_caret_or_script_updated(_sender_id: int, _path: String, _line: int, _col: int, _sel: Dictionary) -> void:
	_rebuild_peer_list()

func _update_ui_state(_msg: String = "") -> void:
	if not is_inside_tree() or network == null:
		return
		
	var connected = network.is_connected_to_session
	if host_btn: host_btn.disabled = connected
	if join_btn: join_btn.disabled = connected
	if disconnect_btn: disconnect_btn.visible = connected
	if connected and lan_quick_join_btn:
		lan_quick_join_btn.visible = false
		discovered_lan_host.clear()

	if status_badge:
		if connected:
			if network.is_host_peer:
				var lan_ip = network.get_local_lan_ip()
				var port = int(host_port_spin.value) if host_port_spin else 7777
				if network.is_upnp_active and not network.upnp_public_ip.is_empty():
					status_badge.text = "● Hosting (%s:%d | WAN: %s)" % [lan_ip, port, network.upnp_public_ip]
				elif not network.upnp_status_message.is_empty():
					status_badge.text = "● Hosting (%s:%d) [%s]" % [lan_ip, port, network.upnp_status_message]
				else:
					status_badge.text = "● Hosting (%s:%d)" % [lan_ip, port]
			else:
				status_badge.text = "● Connected"
			status_badge.modulate = Color("#2ecc71")
		else:
			status_badge.text = "○ Offline"
			status_badge.modulate = Color("#95a5a6")

func _rebuild_peer_list() -> void:
	if peers_list_container == null or network == null:
		return
		
	for child in peers_list_container.get_children():
		child.queue_free()
		
	var peer_count = network.peers.size()
	if peer_count_label:
		peer_count_label.text = "ONLINE — %d" % peer_count
		
	for pid in network.peers.keys():
		var peer = network.peers[pid]
		var card = _create_peer_card(int(pid), peer)
		peers_list_container.add_child(card)

## Creates a Discord-style circular avatar (crops image or shows initial letter on colored circle)
func _create_circular_avatar(avatar_tex: Texture2D, username: String, bg_color: Color, avatar_size: float = 40.0, show_status_dot: bool = false, status_border_color: Color = Color("#1e1f22")) -> Control:
	var root_ctrl = Control.new()
	root_ctrl.custom_minimum_size = Vector2(avatar_size, avatar_size)
	root_ctrl.size = Vector2(avatar_size, avatar_size)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Circular clipped container
	var mask_panel = PanelContainer.new()
	mask_panel.custom_minimum_size = Vector2(avatar_size, avatar_size)
	mask_panel.size = Vector2(avatar_size, avatar_size)
	mask_panel.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	mask_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var mask_sb = StyleBoxFlat.new()
	mask_sb.set_corner_radius_all(int(avatar_size * 0.5))
	mask_sb.bg_color = bg_color
	mask_panel.add_theme_stylebox_override("panel", mask_sb)
	
	if avatar_tex != null:
		var tex_rect = TextureRect.new()
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.custom_minimum_size = Vector2(avatar_size, avatar_size)
		tex_rect.size = Vector2(avatar_size, avatar_size)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture = avatar_tex
		tex_rect.mouse_filter = Control.MOUSE_FILTER_PASS
		mask_panel.add_child(tex_rect)
	else:
		var letter_lbl = Label.new()
		var initial = username.strip_edges().substr(0, 1).to_upper()
		letter_lbl.text = initial if not initial.is_empty() else "?"
		letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter_lbl.add_theme_color_override("font_color", Color.WHITE)
		letter_lbl.add_theme_font_size_override("font_size", int(avatar_size * 0.48))
		letter_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		mask_panel.add_child(letter_lbl)
		
	root_ctrl.add_child(mask_panel)
	
	# Discord online status dot (overlapping bottom right of avatar)
	if show_status_dot:
		var dot_size: float = 12.0
		var dot_panel = PanelContainer.new()
		dot_panel.custom_minimum_size = Vector2(dot_size, dot_size)
		dot_panel.size = Vector2(dot_size, dot_size)
		dot_panel.position = Vector2(avatar_size - dot_size + 1.0, avatar_size - dot_size + 1.0)
		dot_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var dot_sb = StyleBoxFlat.new()
		dot_sb.bg_color = Color("#23a55a") # Discord Online Green
		dot_sb.border_color = status_border_color
		dot_sb.set_border_width_all(2)
		dot_sb.set_corner_radius_all(int(dot_size * 0.5))
		dot_panel.add_theme_stylebox_override("panel", dot_sb)
		
		root_ctrl.add_child(dot_panel)
		
	return root_ctrl

## Creates a Discord member list item card (matching Image 2: large, clean, vertically centered)
func _create_peer_card(peer_id: int, peer: Dictionary) -> Control:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var col_hex = peer.get("color_hex", "5865f2")
	var peer_color = Color.from_string(col_hex, Color("#5865f2"))
	
	# Clean transparent background by default, subtle rounded highlight on hover
	var normal_sb = StyleBoxFlat.new()
	normal_sb.bg_color = Color(0, 0, 0, 0)
	normal_sb.set_corner_radius_all(6)
	normal_sb.content_margin_left = 10
	normal_sb.content_margin_top = 8
	normal_sb.content_margin_right = 10
	normal_sb.content_margin_bottom = 8
	
	var hover_sb = normal_sb.duplicate()
	hover_sb.bg_color = Color(0.22, 0.23, 0.26, 0.7) # Discord hover highlight
	
	panel.add_theme_stylebox_override("panel", normal_sb)
	panel.mouse_entered.connect(func(): panel.add_theme_stylebox_override("panel", hover_sb))
	panel.mouse_exited.connect(func(): panel.add_theme_stylebox_override("panel", normal_sb))
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Circular avatar with online status badge (40x40)
	var avatar_tex = network.get_peer_avatar_texture(peer_id) if network else null
	var username = peer.get("username", "Peer %d" % peer_id)
	var avatar_ctrl = _create_circular_avatar(avatar_tex, username, peer_color, 40.0, true, Color("#1e1f22"))
	hbox.add_child(avatar_ctrl)
	
	# Username vertically centered (clean Discord style from Image 2)
	var name_hbox = HBoxContainer.new()
	name_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	name_hbox.add_theme_constant_override("separation", 8)
	name_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var name_label = Label.new()
	name_label.text = username
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("#f2f3f5"))
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_hbox.add_child(name_label)
	
	if peer_id == 1:
		var host_badge = Label.new()
		host_badge.text = "👑 Host"
		host_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		host_badge.add_theme_font_size_override("font_size", 12)
		host_badge.add_theme_color_override("font_color", Color("#f0b232"))
		host_badge.mouse_filter = Control.MOUSE_FILTER_PASS
		name_hbox.add_child(host_badge)
		
	hbox.add_child(name_hbox)
	panel.add_child(hbox)
	return panel

func _on_send_chat_pressed() -> void:
	if chat_input == null:
		return
	_on_chat_submitted(chat_input.text)

func _on_chat_submitted(text: String) -> void:
	var msg = text.strip_edges()
	if msg.is_empty() or network == null:
		return
	network.send_chat(msg)
	if chat_input:
		chat_input.text = ""

func _on_chat_message_received(sender_id: int, username: String, color_hex: String, message: String, timestamp: String) -> void:
	if chat_message_list == null:
		return
	var item = _create_chat_message_item(sender_id, username, color_hex, message, timestamp)
	chat_message_list.add_child(item)
	
	# Keep chat list bounded to recent 100 messages
	if chat_message_list.get_child_count() > 100:
		var oldest = chat_message_list.get_child(0)
		chat_message_list.remove_child(oldest)
		oldest.queue_free()
		
	# Auto-scroll to latest message
	if chat_scroll:
		await get_tree().process_frame
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

## Creates a Discord-style date divider line (matching reference image)
func _create_date_divider(date_str: String) -> Control:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	
	var sep1 = HSeparator.new()
	sep1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sep_sb = StyleBoxLine.new()
	sep_sb.color = Color("#3f4147")
	sep_sb.thickness = 1
	sep1.add_theme_stylebox_override("separator", sep_sb)
	hbox.add_child(sep1)
	
	var lbl = Label.new()
	lbl.text = date_str
	lbl.add_theme_color_override("font_color", Color("#949ba4"))
	lbl.add_theme_font_size_override("font_size", 11)
	if has_theme_font("bold", "EditorFonts"):
		lbl.add_theme_font_override("font", get_theme_font("bold", "EditorFonts"))
	hbox.add_child(lbl)
	
	var sep2 = HSeparator.new()
	sep2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep2.add_theme_stylebox_override("separator", sep_sb)
	hbox.add_child(sep2)
	
	return hbox

## Creates a Discord-style chat message row (matching Image 1) - PURE TEXT, ZERO BACKGROUND
func _create_chat_message_item(sender_id: int, username: String, color_hex: String, message: String, timestamp: String) -> Control:
	var item_panel = PanelContainer.new()
	item_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var normal_sb = StyleBoxEmpty.new()
	normal_sb.content_margin_left = 6
	normal_sb.content_margin_right = 6
	normal_sb.content_margin_top = 3
	normal_sb.content_margin_bottom = 3
	item_panel.add_theme_stylebox_override("panel", normal_sb)
	
	var hover_sb = StyleBoxFlat.new()
	hover_sb.bg_color = Color(1.0, 1.0, 1.0, 0.03) # Subtle 3% Discord hover highlight
	hover_sb.set_corner_radius_all(4)
	hover_sb.content_margin_left = 6
	hover_sb.content_margin_right = 6
	hover_sb.content_margin_top = 3
	hover_sb.content_margin_bottom = 3
	item_panel.mouse_entered.connect(func(): item_panel.add_theme_stylebox_override("panel", hover_sb))
	item_panel.mouse_exited.connect(func(): item_panel.add_theme_stylebox_override("panel", normal_sb))
	
	# Handle System messages
	if sender_id == 0:
		var sys_box = HBoxContainer.new()
		sys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sys_box.alignment = BoxContainer.ALIGNMENT_BEGIN
		sys_box.add_theme_constant_override("separation", 6)
		
		var sys_icon = Label.new()
		sys_icon.text = "➜"
		sys_icon.add_theme_color_override("font_color", Color("#57f287"))
		sys_icon.add_theme_font_size_override("font_size", 13)
		sys_box.add_child(sys_icon)
		
		var sys_lbl = Label.new()
		sys_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sys_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sys_lbl.text = "[%s] %s" % [timestamp, message]
		sys_lbl.add_theme_color_override("font_color", Color("#949ba4"))
		sys_lbl.add_theme_font_size_override("font_size", 13)
		sys_box.add_child(sys_lbl)
		
		item_panel.add_child(sys_box)
		return item_panel

	var peer_col = Color.from_string(color_hex, Color("#5865f2"))
	var avatar_tex = network.get_peer_avatar_texture(sender_id) if network else null
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Circular Avatar on left (centered vertically with message block)
	var avatar_box = VBoxContainer.new()
	avatar_box.alignment = BoxContainer.ALIGNMENT_CENTER
	avatar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var avatar_ctrl = _create_circular_avatar(avatar_tex, username, peer_col, 40.0, false)
	avatar_box.add_child(avatar_ctrl)
	hbox.add_child(avatar_box)
	
	# Message details column (centered vertically with avatar)
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Top line: Username + Timestamp right next to each other
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	header_hbox.add_theme_constant_override("separation", 6)
	header_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var user_lbl = Label.new()
	user_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	user_lbl.text = username
	user_lbl.add_theme_color_override("font_color", peer_col)
	user_lbl.add_theme_font_size_override("font_size", 16)
	if has_theme_font("bold", "EditorFonts"):
		user_lbl.add_theme_font_override("font", get_theme_font("bold", "EditorFonts"))
	user_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	header_hbox.add_child(user_lbl)
	
	var time_lbl = Label.new()
	time_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	time_lbl.text = timestamp # keeps current time format
	time_lbl.add_theme_color_override("font_color", Color("#949ba4"))
	time_lbl.add_theme_font_size_override("font_size", 12)
	time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	time_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	header_hbox.add_child(time_lbl)
	
	vbox.add_child(header_hbox)
	
	# Message content: pure clean text with ZERO background, size 16
	var text_lbl = Label.new()
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.add_theme_color_override("font_color", Color("#dbdee1"))
	text_lbl.add_theme_font_size_override("font_size", 16)
	text_lbl.text = message
	text_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(text_lbl)
	
	hbox.add_child(vbox)
	item_panel.add_child(hbox)
	return item_panel
