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
const ONLINE_RESUME_TARGET_LOBBY := "online_lobby"
const ONLINE_RESUME_TARGET_GAME := "game"

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

func set_online_resume_context(
	room_code: String,
	role: String,
	platform_base_url: String,
	target_scene: String = ONLINE_RESUME_TARGET_LOBBY
) -> void:
	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		online_resume_state = {}
		save_online_resume_state_to_disk()
		return
	var normalized_target := _normalize_online_resume_target_scene(target_scene, false)
	online_resume_state = {
		"room_code": code,
		"role": str(role).strip_edges(),
		"seat_index": -1,
		"platform_base_url": str(platform_base_url).strip_edges(),
		"in_game": normalized_target == ONLINE_RESUME_TARGET_GAME,
		"reconnecting": false,
		"session_id": str(PlatformSession.session_id).strip_edges() if PlatformSession != null else "",
		"user_id": str(PlatformSession.user_id).strip_edges() if PlatformSession != null else "",
		"checkpoint_id": "",
		"last_applied_sequence": 0,
		"last_state_hash": "",
		"target_scene": normalized_target,
		"resume_allowed": true,
		"terminal_reason": "",
	}
	save_online_resume_state_to_disk()

func clear_online_resume_context() -> void:
	online_resume_state = {}
	save_online_resume_state_to_disk()

func has_online_resume_context() -> bool:
	return _has_online_resume_record() and is_online_resume_allowed()

func get_online_resume_room_code() -> String:
	return str(online_resume_state.get("room_code", "")).strip_edges().to_upper()

func get_online_resume_role() -> String:
	return str(online_resume_state.get("role", "")).strip_edges()

func get_online_resume_seat_index() -> int:
	var seat_index_val = online_resume_state.get("seat_index", null)
	if seat_index_val is int or seat_index_val is float:
		return int(seat_index_val)
	return -1

func get_online_resume_platform_base_url() -> String:
	return str(online_resume_state.get("platform_base_url", "")).strip_edges()

func get_online_resume_session_id() -> String:
	return str(online_resume_state.get("session_id", "")).strip_edges()

func get_online_resume_user_id() -> String:
	return str(online_resume_state.get("user_id", "")).strip_edges()

func get_online_resume_checkpoint_id() -> String:
	return str(online_resume_state.get("checkpoint_id", "")).strip_edges()

func get_online_resume_last_applied_sequence() -> int:
	var sequence_val = online_resume_state.get("last_applied_sequence", 0)
	if sequence_val is int or sequence_val is float:
		return maxi(0, int(sequence_val))
	return 0

func get_online_resume_last_state_hash() -> String:
	return str(online_resume_state.get("last_state_hash", "")).strip_edges()

func get_online_resume_target_scene() -> String:
	return _normalize_online_resume_target_scene(
		str(online_resume_state.get("target_scene", "")),
		bool(online_resume_state.get("in_game", false))
	)

func get_online_resume_terminal_reason() -> String:
	return str(online_resume_state.get("terminal_reason", "")).strip_edges()

func has_online_resume_record() -> bool:
	return _has_online_resume_record()

func is_online_resume_allowed() -> bool:
	return _has_online_resume_record() and bool(online_resume_state.get("resume_allowed", true))

func mark_online_resume_in_game(active: bool) -> void:
	if not _has_online_resume_record():
		return
	var in_game := bool(active)
	online_resume_state["in_game"] = in_game
	online_resume_state["target_scene"] = ONLINE_RESUME_TARGET_GAME if in_game else ONLINE_RESUME_TARGET_LOBBY
	if not in_game:
		online_resume_state["reconnecting"] = false
	save_online_resume_state_to_disk()

func is_online_resume_in_game() -> bool:
	return _has_online_resume_record() and bool(online_resume_state.get("in_game", false))

func set_online_reconnecting(active: bool) -> void:
	if not _has_online_resume_record():
		return
	if not is_online_resume_allowed():
		online_resume_state["reconnecting"] = false
		save_online_resume_state_to_disk()
		return
	online_resume_state["reconnecting"] = bool(active)
	save_online_resume_state_to_disk()

func is_online_reconnecting() -> bool:
	return is_online_resume_allowed() and bool(online_resume_state.get("reconnecting", false))

func set_online_resume_terminal(reason: String) -> void:
	if not _has_online_resume_record():
		return
	online_resume_state["resume_allowed"] = false
	online_resume_state["terminal_reason"] = str(reason).strip_edges()
	online_resume_state["reconnecting"] = false
	save_online_resume_state_to_disk()

func set_online_resume_progress(last_applied_sequence: int, last_state_hash: String, checkpoint_id: String = "") -> void:
	if not _has_online_resume_record():
		return
	online_resume_state["last_applied_sequence"] = maxi(0, int(last_applied_sequence))
	online_resume_state["last_state_hash"] = str(last_state_hash).strip_edges()
	var normalized_checkpoint_id := str(checkpoint_id).strip_edges()
	if not normalized_checkpoint_id.is_empty():
		online_resume_state["checkpoint_id"] = normalized_checkpoint_id
	elif not online_resume_state.has("checkpoint_id"):
		online_resume_state["checkpoint_id"] = ""
	save_online_resume_state_to_disk()

func sync_online_resume_progress_from_engine(engine, checkpoint_id: String = "") -> void:
	if not _has_online_resume_record():
		return
	if engine == null:
		return
	var state = engine.get_state() if engine.has_method("get_state") else null
	if state == null or not state.has_method("compute_hash"):
		return
	var sequence := 0
	if engine is Object:
		var current_index_val = engine.get("current_command_index")
		if current_index_val is int or current_index_val is float:
			sequence = maxi(0, int(current_index_val) + 1)
		var history_val = engine.get("command_history")
		if history_val is Array:
			var history_size := Array(history_val).size()
			if not (current_index_val is int or current_index_val is float):
				sequence = history_size
			else:
				sequence = mini(sequence, history_size)
	set_online_resume_progress(sequence, str(state.compute_hash()), checkpoint_id)

func build_online_resume_cursor(force_snapshot: bool = false) -> Dictionary:
	if not _has_online_resume_record():
		return {}
	if not bool(online_resume_state.get("in_game", false)):
		return {}
	var cursor := {
		"checkpoint_id": get_online_resume_checkpoint_id(),
		"last_applied_sequence": get_online_resume_last_applied_sequence(),
		"last_state_hash": get_online_resume_last_state_hash(),
	}
	if bool(force_snapshot):
		cursor["force_snapshot"] = true
	return cursor

func sync_online_resume_context_from_room_state(room_state_dict: Dictionary) -> void:
	if not _has_online_resume_record():
		return
	var room_code := str(room_state_dict.get("room_code", "")).strip_edges().to_upper()
	if room_code.is_empty():
		return
	if room_code != get_online_resume_room_code():
		return
	var self_seat_val = room_state_dict.get("self_seat_index", null)
	if self_seat_val is int or self_seat_val is float:
		online_resume_state["seat_index"] = int(self_seat_val)
	var self_role := str(room_state_dict.get("self_role", "")).strip_edges()
	if not self_role.is_empty():
		online_resume_state["role"] = self_role
	mark_online_resume_in_game(str(room_state_dict.get("status", "")).strip_edges() == "InGame")

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
		"seat_index": cfg.get_value("resume", "seat_index", -1),
		"platform_base_url": cfg.get_value("resume", "platform_base_url", ""),
		"in_game": cfg.get_value("resume", "in_game", false),
		"reconnecting": cfg.get_value("resume", "reconnecting", false),
		"session_id": cfg.get_value("resume", "session_id", ""),
		"user_id": cfg.get_value("resume", "user_id", ""),
		"checkpoint_id": cfg.get_value("resume", "checkpoint_id", ""),
		"last_applied_sequence": cfg.get_value("resume", "last_applied_sequence", 0),
		"last_state_hash": cfg.get_value("resume", "last_state_hash", ""),
		"target_scene": cfg.get_value("resume", "target_scene", ""),
		"resume_allowed": cfg.get_value("resume", "resume_allowed", true),
		"terminal_reason": cfg.get_value("resume", "terminal_reason", ""),
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
		"seat_index": int(src.get("seat_index", -1)),
		"platform_base_url": str(src.get("platform_base_url", "")).strip_edges(),
		"in_game": bool(src.get("in_game", false)),
		"reconnecting": bool(src.get("reconnecting", false)),
		"session_id": str(src.get("session_id", "")).strip_edges(),
		"user_id": str(src.get("user_id", "")).strip_edges(),
		"checkpoint_id": str(src.get("checkpoint_id", "")).strip_edges(),
		"last_applied_sequence": maxi(0, int(src.get("last_applied_sequence", 0))),
		"last_state_hash": str(src.get("last_state_hash", "")).strip_edges(),
		"target_scene": _normalize_online_resume_target_scene(
			str(src.get("target_scene", "")),
			bool(src.get("in_game", false))
		),
		"resume_allowed": bool(src.get("resume_allowed", true)),
		"terminal_reason": str(src.get("terminal_reason", "")).strip_edges(),
	}

func _has_online_resume_record() -> bool:
	return not get_online_resume_room_code().is_empty()

func _normalize_online_resume_target_scene(target_scene: String, in_game: bool) -> String:
	var normalized := str(target_scene).strip_edges()
	if normalized == ONLINE_RESUME_TARGET_GAME:
		return ONLINE_RESUME_TARGET_GAME
	if normalized == ONLINE_RESUME_TARGET_LOBBY:
		return ONLINE_RESUME_TARGET_LOBBY
	return ONLINE_RESUME_TARGET_GAME if bool(in_game) else ONLINE_RESUME_TARGET_LOBBY

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
