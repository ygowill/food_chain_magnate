# 平台会话管理
# 管理 user_id、session_id、is_guest，持久化到 user://
# Web 平台通过 JavaScriptBridge 与 Vue SPA 共享 localStorage
extends Node

signal session_changed
signal device_auth_status(status: String)  # "waiting" | "success" | "expired" | "cancelled"

const _SAVE_PATH_DEFAULT := "user://platform_session.cfg"
const _SAVE_PATH_PREFIX := "user://platform_session_"
const _MAX_PROFILE_ID_LEN := 24
const _GUEST_NAME_PREFIX := "游客#"
const _ACCOUNT_NAME_PREFIX := "账号#"
const _DEFAULT_NAME_SUFFIX := "0000"

var profile_id: String = ""
var _save_path: String = _SAVE_PATH_DEFAULT

var user_id: String = ""
var session_id: String = ""
var is_guest: bool = true
var display_name: String = ""
var device_id: String = ""

var _device_auth_cancelled: bool = false
var _is_web: bool = false

var is_logged_in: bool:
	get: return session_id != ""


func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	profile_id = _get_profile_id()
	_save_path = _build_save_path(profile_id)
	_load()
	if is_logged_in:
		_ensure_local_display_name()
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

func _name_suffix(raw_id: String) -> String:
	var s := str(raw_id).strip_edges()
	if s.is_empty():
		return _DEFAULT_NAME_SUFFIX
	if s.length() >= 4:
		return s.substr(s.length() - 4, 4)
	while s.length() < 4:
		s = "0" + s
	return s

func _default_display_name(uid: String, guest: bool) -> String:
	var prefix := _GUEST_NAME_PREFIX if guest else _ACCOUNT_NAME_PREFIX
	return "%s%s" % [prefix, _name_suffix(uid)]

func _ensure_local_display_name() -> void:
	var dn := str(display_name).strip_edges()
	if dn.is_empty():
		display_name = _default_display_name(user_id, is_guest)


func auto_guest_login() -> Dictionary:
	if is_logged_in:
		_ensure_local_display_name()
		return {"ok": {
			"user_id": user_id,
			"session_id": session_id,
			"display_name": display_name,
			"is_guest": is_guest,
		}}
	var result: Dictionary = await PlatformApi.guest_login(device_id)
	if result.has("ok"):
		_apply_auth(result["ok"], true)
	return result


func login(email: String, password: String) -> Dictionary:
	var result: Dictionary = await PlatformApi.login(email, password)
	if result.has("ok"):
		_apply_auth(result["ok"], false)
	return result


func register(email: String, password: String, nickname: String = "") -> Dictionary:
	var result: Dictionary = await PlatformApi.register(email, password, nickname)
	if result.has("ok"):
		_apply_auth(result["ok"], false)
	return result


func bind_email(email: String, password: String) -> Dictionary:
	var result: Dictionary = await PlatformApi.bind(session_id, "email", email, password)
	if result.has("ok"):
		_apply_auth(result["ok"], false)
	return result


func update_display_name(new_name: String) -> Dictionary:
	if not is_logged_in:
		return {"error": "not logged in"}
	var result: Dictionary = await PlatformApi.update_profile(session_id, new_name)
	if result.has("ok"):
		var ok_val = result.get("ok", null)
		if ok_val is Dictionary:
			var ok: Dictionary = Dictionary(ok_val)
			display_name = str(ok.get("display_name", "")).strip_edges()
			is_guest = bool(ok.get("is_guest", is_guest))
			_ensure_local_display_name()
			_save()
			session_changed.emit()
	return result


func logout() -> void:
	if session_id != "":
		await PlatformApi.logout(session_id)
	user_id = ""
	session_id = ""
	is_guest = true
	display_name = ""
	_save()
	session_changed.emit()


func start_device_auth() -> Dictionary:
	_device_auth_cancelled = false
	var code_result: Dictionary = await PlatformApi.request_device_code(device_id)
	if code_result.has("error"):
		device_auth_status.emit("error")
		return code_result

	var data: Dictionary = code_result["ok"]
	var dc: String = str(data.get("device_code", ""))
	var user_code: String = str(data.get("user_code", ""))
	var uri: String = str(data.get("verification_uri", ""))
	var interval: int = int(data.get("interval", 5))

	OS.shell_open(uri)
	device_auth_status.emit("waiting")

	# 轮询直到成功、过期或取消
	while not _device_auth_cancelled:
		await get_tree().create_timer(interval).timeout
		if _device_auth_cancelled:
			break
		var poll: Dictionary = await PlatformApi.poll_device_token(dc, device_id)
		if poll.has("ok"):
			_apply_auth(poll["ok"], false)
			device_auth_status.emit("success")
			return {"ok": poll["ok"], "user_code": user_code}
		var err: Dictionary = poll.get("error", {})
		var http_status: int = int(err.get("_http_status", 0))
		if http_status == 428:
			continue  # authorization_pending
		if http_status == 410:
			device_auth_status.emit("expired")
			return {"error": "expired"}
		device_auth_status.emit("error")
		return poll

	device_auth_status.emit("cancelled")
	return {"error": "cancelled"}


func cancel_device_auth() -> void:
	_device_auth_cancelled = true


func _apply_auth(data: Dictionary, guest: bool) -> void:
	user_id = str(data.get("user_id", ""))
	session_id = str(data.get("session_id", ""))
	is_guest = bool(data.get("is_guest", guest))
	display_name = str(data.get("display_name", "")).strip_edges()
	_ensure_local_display_name()
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
	if _is_web:
		_save_web()
		return
	var cfg := ConfigFile.new()
	cfg.set_value("session", "user_id", user_id)
	cfg.set_value("session", "session_id", session_id)
	cfg.set_value("session", "is_guest", is_guest)
	cfg.set_value("session", "display_name", display_name)
	cfg.set_value("session", "device_id", device_id)
	cfg.save(_save_path)


func _load() -> void:
	if _is_web:
		_load_web()
		return
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		return
	user_id = cfg.get_value("session", "user_id", "")
	session_id = cfg.get_value("session", "session_id", "")
	is_guest = cfg.get_value("session", "is_guest", true)
	display_name = cfg.get_value("session", "display_name", "")
	device_id = cfg.get_value("session", "device_id", "")


func _save_web() -> void:
	JavaScriptBridge.eval("localStorage.setItem('fcm_session_id', %s)" % JSON.stringify(session_id))
	JavaScriptBridge.eval("localStorage.setItem('fcm_user_id', %s)" % JSON.stringify(user_id))
	JavaScriptBridge.eval("localStorage.setItem('fcm_is_guest', %s)" % JSON.stringify(str(is_guest).to_lower()))
	JavaScriptBridge.eval("localStorage.setItem('fcm_display_name', %s)" % JSON.stringify(display_name))
	JavaScriptBridge.eval("localStorage.setItem('fcm_device_id', %s)" % JSON.stringify(device_id))


func _load_web() -> void:
	var sid = JavaScriptBridge.eval("localStorage.getItem('fcm_session_id') || ''")
	var uid = JavaScriptBridge.eval("localStorage.getItem('fcm_user_id') || ''")
	var guest_str = JavaScriptBridge.eval("localStorage.getItem('fcm_is_guest') || 'true'")
	var dn = JavaScriptBridge.eval("localStorage.getItem('fcm_display_name') || ''")
	var did = JavaScriptBridge.eval("localStorage.getItem('fcm_device_id') || ''")
	session_id = str(sid) if sid != null else ""
	user_id = str(uid) if uid != null else ""
	is_guest = str(guest_str) != "false"
	display_name = str(dn) if dn != null else ""
	device_id = str(did) if did != null else ""
