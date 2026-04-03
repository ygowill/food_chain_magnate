# 联机上下文（运行模式/房间信息/本地玩家信息）
extends Node

enum Mode {
	HOTSEAT = 0,
	ONLINE_CLIENT = 1,
	ONLINE_SERVER = 2,
}

const PROTOCOL_VERSION := 1

const COMMAND_PRIVACY_SPECTATOR_VIEWER_PLAYER_ID := 999999
const ONLINE_RESUME_SAVE_PATH := "user://online_resume_state.cfg"
const ONLINE_RESUME_WEB_STORAGE_KEY := "fcm_online_resume_state"

var mode: Mode = Mode.HOTSEAT
var local_player_id: int = -1
var local_role: String = ""

var server_url: String = ""
var connect_token: String = ""
var room_state: Dictionary = {}
var room_list: Array = []
var player_profile: Dictionary = {}
var online_resume_state: Dictionary = {}
var _online_resume_save_path := ONLINE_RESUME_SAVE_PATH
var _is_web: bool = false

func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	_ensure_default_profile()
	reload_online_resume_state_from_disk()

func get_command_privacy_viewer_player_id() -> int:
	# Hotseat/local：无需脱敏；联机 spectator：应视为“非本人”，避免 history/debug 误显示隐信息。
	if mode == Mode.ONLINE_CLIENT and local_player_id < 0:
		return COMMAND_PRIVACY_SPECTATOR_VIEWER_PLAYER_ID
	return local_player_id

func set_online_resume_context(room_code: String, role: String, platform_base_url: String) -> void:
	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		online_resume_state = {}
		save_online_resume_state_to_disk()
		return
	online_resume_state = {
		"room_code": code,
		"role": str(role).strip_edges(),
		"platform_base_url": str(platform_base_url).strip_edges(),
		"in_game": false,
		"reconnecting": false,
		"session_id": str(PlatformSession.session_id).strip_edges() if PlatformSession != null else "",
		"user_id": str(PlatformSession.user_id).strip_edges() if PlatformSession != null else "",
	}
	save_online_resume_state_to_disk()

func clear_online_resume_context() -> void:
	online_resume_state = {}
	save_online_resume_state_to_disk()

func has_online_resume_context() -> bool:
	return not get_online_resume_room_code().is_empty()

func get_online_resume_room_code() -> String:
	return str(online_resume_state.get("room_code", "")).strip_edges().to_upper()

func get_online_resume_role() -> String:
	return str(online_resume_state.get("role", "")).strip_edges()

func get_online_resume_platform_base_url() -> String:
	return str(online_resume_state.get("platform_base_url", "")).strip_edges()

func get_online_resume_session_id() -> String:
	return str(online_resume_state.get("session_id", "")).strip_edges()

func get_online_resume_user_id() -> String:
	return str(online_resume_state.get("user_id", "")).strip_edges()

func mark_online_resume_in_game(active: bool) -> void:
	if not has_online_resume_context():
		return
	online_resume_state["in_game"] = bool(active)
	if not bool(active):
		online_resume_state["reconnecting"] = false
	save_online_resume_state_to_disk()

func is_online_resume_in_game() -> bool:
	return has_online_resume_context() and bool(online_resume_state.get("in_game", false))

func set_online_reconnecting(active: bool) -> void:
	if not has_online_resume_context():
		return
	online_resume_state["reconnecting"] = bool(active)
	save_online_resume_state_to_disk()

func is_online_reconnecting() -> bool:
	return has_online_resume_context() and bool(online_resume_state.get("reconnecting", false))

func reset() -> void:
	mode = Mode.HOTSEAT
	local_player_id = -1
	local_role = ""
	server_url = ""
	connect_token = ""
	room_state = {}
	room_list = []
	online_resume_state = {}
	_ensure_default_profile()
	save_online_resume_state_to_disk()

func get_online_resume_save_path() -> String:
	return _online_resume_save_path

func set_online_resume_save_path_for_test(path: String) -> void:
	var next_path := str(path).strip_edges()
	_online_resume_save_path = ONLINE_RESUME_SAVE_PATH if next_path.is_empty() else next_path

func save_online_resume_state_to_disk() -> Result:
	if _is_web:
		return _save_online_resume_state_web()
	var cfg := ConfigFile.new()
	if not online_resume_state.is_empty():
		for key in online_resume_state.keys():
			cfg.set_value("resume", str(key), online_resume_state.get(key, null))
	var err := cfg.save(_online_resume_save_path)
	if err != OK:
		return Result.failure("save online resume state failed: %s" % str(err))
	return Result.success()

func reload_online_resume_state_from_disk() -> Result:
	if _is_web:
		return _load_online_resume_state_web()
	var cfg := ConfigFile.new()
	if cfg.load(_online_resume_save_path) != OK:
		online_resume_state = {}
		return Result.success()

	online_resume_state = _normalize_online_resume_state({
		"room_code": cfg.get_value("resume", "room_code", ""),
		"role": cfg.get_value("resume", "role", ""),
		"platform_base_url": cfg.get_value("resume", "platform_base_url", ""),
		"in_game": cfg.get_value("resume", "in_game", false),
		"reconnecting": cfg.get_value("resume", "reconnecting", false),
		"session_id": cfg.get_value("resume", "session_id", ""),
		"user_id": cfg.get_value("resume", "user_id", ""),
	})
	return Result.success()

func _save_online_resume_state_web() -> Result:
	if online_resume_state.is_empty():
		JavaScriptBridge.eval("localStorage.removeItem('fcm_online_resume_state')")
		return Result.success()
	var encoded := JSON.stringify(online_resume_state)
	JavaScriptBridge.eval(
		"localStorage.setItem('%s', %s)" % [ONLINE_RESUME_WEB_STORAGE_KEY, JSON.stringify(encoded)]
	)
	return Result.success()

func _load_online_resume_state_web() -> Result:
	var raw = JavaScriptBridge.eval("localStorage.getItem('%s') || ''" % ONLINE_RESUME_WEB_STORAGE_KEY)
	var text := str(raw).strip_edges()
	if text.is_empty():
		online_resume_state = {}
		return Result.success()
	var parsed: Variant = JSON.parse_string(text)
	online_resume_state = _normalize_online_resume_state(parsed)
	return Result.success()

func _normalize_online_resume_state(value) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var src: Dictionary = Dictionary(value)
	var room_code := str(src.get("room_code", "")).strip_edges().to_upper()
	if room_code.is_empty():
		return {}
	return {
		"room_code": room_code,
		"role": str(src.get("role", "")).strip_edges(),
		"platform_base_url": str(src.get("platform_base_url", "")).strip_edges(),
		"in_game": bool(src.get("in_game", false)),
		"reconnecting": bool(src.get("reconnecting", false)),
		"session_id": str(src.get("session_id", "")).strip_edges(),
		"user_id": str(src.get("user_id", "")).strip_edges(),
	}

func _ensure_default_profile() -> void:
	var name := "玩家"
	var color_index := 0
	var restaurant_logo_id := -1
	if Globals != null:
		if Globals.player_names is Array and not Globals.player_names.is_empty():
			name = str(Globals.player_names[0])
		if Globals.player_color_indices is Array and not Globals.player_color_indices.is_empty():
			color_index = int(Globals.player_color_indices[0])
		if Globals.player_restaurant_logo_choices is Array and not Globals.player_restaurant_logo_choices.is_empty():
			restaurant_logo_id = int(Globals.player_restaurant_logo_choices[0])
	if player_profile != null and not player_profile.is_empty():
		if str(player_profile.get("name", "")).strip_edges().is_empty():
			player_profile["name"] = name
		if not player_profile.has("color_index"):
			player_profile["color_index"] = color_index
		if not player_profile.has("restaurant_logo_id"):
			player_profile["restaurant_logo_id"] = restaurant_logo_id
		return
	player_profile = {
		"name": name,
		"color_index": color_index,
		"restaurant_logo_id": restaurant_logo_id,
	}
