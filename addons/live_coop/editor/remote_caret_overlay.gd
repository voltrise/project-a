@tool
class_name RemoteCaretOverlay
extends Control

const CoopNetwork = preload("res://addons/live_coop/network/coop_network.gd")

var code_edit: CodeEdit
var network: CoopNetwork
var script_path: String = ""

var _blink_time: float = 0.0
var _blink_visible: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	if code_edit != null:
		# Connect to scrollbars so carets stay anchored during scrolling
		var v_bar = code_edit.get_v_scroll_bar()
		if v_bar and not v_bar.value_changed.is_connected(_on_scroll):
			v_bar.value_changed.connect(_on_scroll)
		var h_bar = code_edit.get_h_scroll_bar()
		if h_bar and not h_bar.value_changed.is_connected(_on_scroll):
			h_bar.value_changed.connect(_on_scroll)

func _process(delta: float) -> void:
	_blink_time += delta
	if _blink_time >= 0.5:
		_blink_time = 0.0
		_blink_visible = not _blink_visible
		queue_redraw()

func _on_scroll(_val: float) -> void:
	queue_redraw()

func _draw() -> void:
	if code_edit == null or network == null or not network.is_connected_to_session:
		return
		
	var my_id = network.custom_mp.get_unique_id() if network.custom_mp else 1
	var font = ThemeDB.fallback_font
	var font_size: int = 11
	
	for pid in network.peers.keys():
		var peer_id = int(pid)
		if peer_id == my_id:
			continue
			
		var peer = network.peers[peer_id]
		if peer.get("active_script", "") != script_path:
			continue
			
		var col_hex = peer.get("color_hex", "3498db")
		var peer_color = Color.from_string(col_hex, Color.DODGER_BLUE)
		var line = peer.get("caret_line", 0)
		var col = peer.get("caret_col", 0)
		var username = peer.get("username", "Peer %d" % peer_id)
		
		# Draw Selection Highlights if present
		var sel = peer.get("selection", {})
		if sel.get("active", false):
			var sel_from_line: int = sel.get("from_line", 0)
			var sel_from_col: int = sel.get("from_col", 0)
			var sel_to_line: int = sel.get("to_line", 0)
			var sel_to_col: int = sel.get("to_col", 0)
			var highlight_col = Color(peer_color.r, peer_color.g, peer_color.b, 0.28)
			
			for l in range(sel_from_line, sel_to_line + 1):
				if l < 0 or l >= code_edit.get_line_count():
					continue
				var c_start = sel_from_col if l == sel_from_line else 0
				var c_end = sel_to_col if l == sel_to_line else code_edit.get_line(l).length()
				var r_start = code_edit.get_rect_at_line_column(l, c_start)
				var r_end = code_edit.get_rect_at_line_column(l, c_end)
				var sel_width = maxf(float(r_end.position.x - r_start.position.x), 6.0)
				draw_rect(Rect2(float(r_start.position.x), float(r_start.position.y), sel_width, float(r_start.size.y)), highlight_col, true)
		
		# Draw Caret and Username Badge
		if line >= 0 and line < code_edit.get_line_count():
			var caret_rect = code_edit.get_rect_at_line_column(line, col)
			var caret_pos = Vector2(caret_rect.position)
			var caret_size = Vector2(caret_rect.size)
			
			# Draw vertical cursor
			if _blink_visible:
				var line_top = caret_pos
				var line_bottom = caret_pos + Vector2(0, caret_size.y)
				draw_line(line_top, line_bottom, peer_color, 2.5)
			
			# Draw floating username pill badge
			var text_size = font.get_string_size(username, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var pad = Vector2(4.0, 1.5)
			var badge_w = text_size.x + pad.x * 2.0
			var badge_h = text_size.y + pad.y * 2.0
			var badge_pos = Vector2(caret_pos.x, caret_pos.y - badge_h)
			
			# If badge is cut off at the top of the editor, display it right below the line instead
			if badge_pos.y < 0:
				badge_pos.y = caret_pos.y + caret_size.y
				
			var badge_rect = Rect2(badge_pos, Vector2(badge_w, badge_h))
			
			# Pill background
			draw_rect(badge_rect, peer_color, true)
			# Pill outline
			draw_rect(badge_rect, peer_color.darkened(0.3), false, 1.0)
			
			# Name text with adaptive contrast
			var text_color = Color.BLACK if peer_color.get_luminance() > 0.55 else Color.WHITE
			var text_pos = badge_pos + Vector2(pad.x, text_size.y + pad.y - 1.0)
			draw_string(font, text_pos, username, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

