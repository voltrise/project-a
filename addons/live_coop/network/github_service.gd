@tool
class_name GithubService
extends Node

signal authenticated(profile_data: Dictionary)
signal auth_failed(error_message: String)
signal avatar_updated(texture: ImageTexture)
signal logged_out()

const AUTH_FILE_PATH = "res://addons/live_coop/github_auth.json"
const AVATAR_CACHE_PATH = "res://addons/live_coop/avatar_cache.png"

var http_user: HTTPRequest
var http_avatar: HTTPRequest

var is_authenticated: bool = false
var current_token: String = ""
var github_username: String = ""
var github_id: int = 0
var github_avatar_url: String = ""
var user_color: Color = Color.DODGER_BLUE
var avatar_texture: ImageTexture = null
var avatar_bytes: PackedByteArray = []

func _enter_tree() -> void:
	if http_user == null:
		http_user = HTTPRequest.new()
		http_user.name = "GithubUserReq"
		add_child(http_user)
		http_user.request_completed.connect(_on_user_request_completed)
		
	if http_avatar == null:
		http_avatar = HTTPRequest.new()
		http_avatar.name = "GithubAvatarReq"
		add_child(http_avatar)
		http_avatar.request_completed.connect(_on_avatar_request_completed)
		
	load_saved_profile()

## Computes a deterministic, vibrant HSV color from an account ID or username
static func get_deterministic_color(identifier: String) -> Color:
	if identifier.is_empty():
		return Color.DODGER_BLUE
	var h: int = identifier.hash()
	var hue: float = fposmod(float(abs(h) % 360) / 360.0, 1.0)
	var sat: float = 0.72 + fposmod(float(abs(h >> 8) % 18) / 100.0, 0.18)
	var val: float = 0.85 + fposmod(float(abs(h >> 16) % 12) / 100.0, 0.12)
	return Color.from_hsv(hue, sat, val)

## Connect using Personal Access Token (classic, repo / read:user)
func connect_with_token(token: String) -> void:
	current_token = token.strip_edges()
	if current_token.is_empty():
		auth_failed.emit("Token cannot be empty.")
		return
		
	var headers = [
		"Authorization: token " + current_token,
		"User-Agent: Godot-Live-CoOp-Plugin",
		"Accept: application/vnd.github.v3+json"
	]
	
	var err = http_user.request("https://api.github.com/user", headers, HTTPClient.METHOD_GET)
	if err != OK:
		auth_failed.emit("Failed to initiate HTTP request (Error %d)" % err)

func _on_user_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		var err_msg = "GitHub Auth failed (HTTP %d)" % response_code
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
			var msg = json.data.get("message", "")
			if not msg.is_empty():
				err_msg += ": " + msg
		auth_failed.emit(err_msg)
		return
		
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		auth_failed.emit("Invalid JSON received from GitHub API.")
		return
		
	var data: Dictionary = json.data
	github_username = data.get("login", "")
	github_id = int(data.get("id", 0))
	github_avatar_url = data.get("avatar_url", "")
	
	# Compute deterministic color using GitHub ID (or username if ID is missing)
	var color_seed = str(github_id) if github_id != 0 else github_username
	user_color = get_deterministic_color(color_seed)
	
	# Download avatar
	if not github_avatar_url.is_empty():
		var headers = ["User-Agent: Godot-Live-CoOp-Plugin"]
		http_avatar.request(github_avatar_url, headers, HTTPClient.METHOD_GET)
	else:
		_finalize_authentication()

func _on_avatar_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200 and body.size() > 0:
		var img = Image.new()
		var err = img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_webp_from_buffer(body)
			
		if err == OK:
			# Downscale to 48x48 for crisp UI display & minimal peer network transfer
			img.resize(48, 48, Image.INTERPOLATE_LANCZOS)
			avatar_bytes = img.save_png_to_buffer()
			avatar_texture = ImageTexture.create_from_image(img)
			
			# Save cached avatar image
			var f = FileAccess.open(AVATAR_CACHE_PATH, FileAccess.WRITE)
			if f:
				f.store_buffer(avatar_bytes)
				f.close()
			avatar_updated.emit(avatar_texture)
			
	_finalize_authentication()

func _finalize_authentication() -> void:
	is_authenticated = true
	save_profile()
	
	var prof = {
		"username": github_username,
		"id": github_id,
		"avatar_url": github_avatar_url,
		"color": user_color,
		"color_hex": user_color.to_html(false),
		"avatar_texture": avatar_texture,
		"avatar_bytes": avatar_bytes
	}
	authenticated.emit(prof)

func save_profile() -> void:
	var dict = {
		"connected": is_authenticated,
		"token": current_token,
		"username": github_username,
		"id": github_id,
		"avatar_url": github_avatar_url,
		"color_hex": user_color.to_html(false)
	}
	var f = FileAccess.open(AUTH_FILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(dict, "\t"))
		f.close()

func load_saved_profile() -> bool:
	if not FileAccess.file_exists(AUTH_FILE_PATH):
		return false
		
	var f = FileAccess.open(AUTH_FILE_PATH, FileAccess.READ)
	if f == null:
		return false
		
	var json = JSON.new()
	if json.parse(f.get_as_text()) != OK or not (json.data is Dictionary):
		f.close()
		return false
	f.close()
	
	var data: Dictionary = json.data
	if not data.get("connected", false):
		return false
		
	current_token = data.get("token", "")
	github_username = data.get("username", "")
	github_id = int(data.get("id", 0))
	github_avatar_url = data.get("avatar_url", "")
	
	var color_seed = str(github_id) if github_id != 0 else github_username
	user_color = get_deterministic_color(color_seed)
	
	# Load cached avatar if available
	if FileAccess.file_exists(AVATAR_CACHE_PATH):
		avatar_bytes = FileAccess.get_file_as_bytes(AVATAR_CACHE_PATH)
		var img = Image.new()
		if img.load_png_from_buffer(avatar_bytes) == OK:
			avatar_texture = ImageTexture.create_from_image(img)
			
	is_authenticated = true
	var prof = {
		"username": github_username,
		"id": github_id,
		"avatar_url": github_avatar_url,
		"color": user_color,
		"color_hex": user_color.to_html(false),
		"avatar_texture": avatar_texture,
		"avatar_bytes": avatar_bytes
	}
	authenticated.emit(prof)
	return true

func logout() -> void:
	is_authenticated = false
	current_token = ""
	github_username = ""
	github_id = 0
	github_avatar_url = ""
	avatar_texture = null
	avatar_bytes.clear()
	
	if FileAccess.file_exists(AUTH_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTH_FILE_PATH))
	if FileAccess.file_exists(AVATAR_CACHE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AVATAR_CACHE_PATH))
		
	logged_out.emit()
