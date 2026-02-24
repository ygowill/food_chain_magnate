# 平台会话管理
# 管理 user_id、session_id、is_guest，持久化到 user://
extends Node

signal session_changed

const _SAVE_PATH_DEFAULT := "user://platform_session.cfg"
const _SAVE_PATH_PREFIX := "user://platform_session_"
const _MAX_PROFILE_ID_LEN := 24

var profile_id: String = ""
var _save_path: String = _SAVE_PATH_DEFAULT

var user_id: String = ""
var session_id: String = ""
var is_guest: bool = true
var device_id: String = ""

var is_logged_in: bool:
	get: return session_id != ""


func _ready() -> void:
	profile_id = _get_profile_id()
	_save_path = _build_save_path(profile_id)
	_load()
	if device_id.is_empty():
		device_id = _generate_device_id()
		_save()

func _get_profile_id() -> String:
	# 同机多开：允许为不同客户端指定不同 profile，以避免共享 user:// 下的 session/device_id。
	var env := str(OS.get_environment("FCM_PLATFORM_PROFILE")).strip_edges()
	if not env.is_empty():
		return _sanitize_profile_id(env)

	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a := str(args[i]).strip_edges()
		if a.begins_with("--platform-profile=") or a.begins_with("--platform_profile="):
			var kv: PackedStringArray = a.split("=", false, 1)
			if kv.size() >= 2:
				return _sanitize_profile_id(str(kv[1]))
		if a == "--platform-profile" or a == "--platform_profile":
			if i + 1 < args.size():
				return _sanitize_profile_id(str(args[i + 1]))
	return ""

func _sanitize_profile_id(raw: String) -> String:
	var s := str(raw).strip_edges()
	if s.is_empty():
		return ""
	var out := ""
	for i in range(s.length()):
		var u := s.unicode_at(i)
		var ch := s.substr(i, 1)
		var ok := (u >= 48 and u <= 57) \
			or (u >= 65 and u <= 90) \
			or (u >= 97 and u <= 122) \
			or ch == "_" \
			or ch == "-"
		out += ch if ok else "_"
	if out.length() > _MAX_PROFILE_ID_LEN:
		out = out.substr(0, _MAX_PROFILE_ID_LEN)
	return out

func _build_save_path(profile: String) -> String:
	var p := _sanitize_profile_id(profile)
	if p.is_empty():
		return _SAVE_PATH_DEFAULT
	return "%s%s.cfg" % [_SAVE_PATH_PREFIX, p]


func auto_guest_login() -> Dictionary:
	if is_logged_in:
		return {"ok": {"user_id": user_id, "session_id": session_id}}
	var result: Dictionary = await PlatformApi.guest_login(device_id)
	if result.has("ok"):
		_apply_auth(result["ok"], true)
	return result


func login(email: String, password: String) -> Dictionary:
	var result: Dictionary = await PlatformApi.login(email, password)
	if result.has("ok"):
		_apply_auth(result["ok"], false)
	return result


func register(email: String, password: String) -> Dictionary:
	var result: Dictionary = await PlatformApi.register(email, password)
	if result.has("ok"):
		_apply_auth(result["ok"], false)
	return result


func bind_email(email: String, password: String) -> Dictionary:
	var result: Dictionary = await PlatformApi.bind(session_id, "email", email, password)
	if result.has("ok"):
		is_guest = false
		_save()
	return result


func logout() -> void:
	if session_id != "":
		await PlatformApi.logout(session_id)
	user_id = ""
	session_id = ""
	is_guest = true
	_save()
	session_changed.emit()


func _apply_auth(data: Dictionary, guest: bool) -> void:
	user_id = str(data.get("user_id", ""))
	session_id = str(data.get("session_id", ""))
	is_guest = guest
	_save()
	# 同步到 NetContext（不覆盖昵称：name 仍由用户/UI 控制）
	if NetContext != null:
		NetContext.player_profile["user_id"] = user_id
	session_changed.emit()


func _generate_device_id() -> String:
	# 生成持久化的设备 ID
	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(16)
	return bytes.hex_encode()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "user_id", user_id)
	cfg.set_value("session", "session_id", session_id)
	cfg.set_value("session", "is_guest", is_guest)
	cfg.set_value("session", "device_id", device_id)
	cfg.save(_save_path)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		return
	user_id = cfg.get_value("session", "user_id", "")
	session_id = cfg.get_value("session", "session_id", "")
	is_guest = cfg.get_value("session", "is_guest", true)
	device_id = cfg.get_value("session", "device_id", "")
