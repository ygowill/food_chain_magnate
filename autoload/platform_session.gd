# 平台会话管理
# 管理 user_id、session_id、is_guest，持久化到 user://
extends Node

signal session_changed

const SAVE_PATH := "user://platform_session.cfg"

var user_id: String = ""
var session_id: String = ""
var is_guest: bool = true
var device_id: String = ""

var is_logged_in: bool:
	get: return session_id != ""


func _ready() -> void:
	_load()
	if device_id.is_empty():
		device_id = _generate_device_id()
		_save()


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
	# 同步到 NetContext
	if NetContext != null:
		NetContext.player_profile["name"] = user_id.substr(0, 8) if is_guest else user_id
	session_changed.emit()


func _generate_device_id() -> String:
	# 生成持久化的设备 ID
	var bytes := PackedByteArray()
	for i in range(16):
		bytes.append(randi() % 256)
	return bytes.hex_encode()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "user_id", user_id)
	cfg.set_value("session", "session_id", session_id)
	cfg.set_value("session", "is_guest", is_guest)
	cfg.set_value("session", "device_id", device_id)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	user_id = cfg.get_value("session", "user_id", "")
	session_id = cfg.get_value("session", "session_id", "")
	is_guest = cfg.get_value("session", "is_guest", true)
	device_id = cfg.get_value("session", "device_id", "")
