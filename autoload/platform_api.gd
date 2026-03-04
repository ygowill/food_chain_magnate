# 平台 API 封装
# 封装 Backend HTTP 调用
extends Node

const _DEFAULT_PLATFORM_BASE_URL := "https://fcm.home.ygowill.net:8443"
const _PROJECT_SETTING_PLATFORM_BACKEND_URL := "fcm/platform_backend_url"
const _ENV_PLATFORM_BACKEND_URL := "FCM_PLATFORM_BACKEND_URL"
const _ENV_WEB_ORIGIN := "FCM_WEB_ORIGIN"

var base_url: String = _DEFAULT_PLATFORM_BASE_URL


func _ready() -> void:
	if OS.get_name() == "Web":
		# Web 平台：同源部署，使用当前页面 origin
		var origin = JavaScriptBridge.eval("window.location.origin")
		var web_origin := _normalize_base_url(str(origin) if origin != null else "")
		base_url = web_origin if not web_origin.is_empty() else _resolve_default_base_url()
	else:
		base_url = _resolve_default_base_url()

func _normalize_base_url(raw_url: String) -> String:
	var url := str(raw_url).strip_edges()
	while url.length() > 0 and url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	return url

func _resolve_default_base_url() -> String:
	var env_url := _normalize_base_url(str(OS.get_environment(_ENV_PLATFORM_BACKEND_URL)))
	if env_url.is_empty():
		env_url = _normalize_base_url(str(OS.get_environment(_ENV_WEB_ORIGIN)))
	if not env_url.is_empty():
		return env_url
	var configured := ""
	if ProjectSettings.has_setting(_PROJECT_SETTING_PLATFORM_BACKEND_URL):
		configured = _normalize_base_url(str(ProjectSettings.get_setting(_PROJECT_SETTING_PLATFORM_BACKEND_URL, "")))
	if not configured.is_empty():
		return configured
	return _DEFAULT_PLATFORM_BASE_URL

func _request(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	var url := base_url + path
	var headers := ["Content-Type: application/json"]
	var json_body := JSON.stringify(body) if not body.is_empty() else ""
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, method, json_body)
	if err != OK:
		http.queue_free()
		return {"error": "request_failed", "code": err}
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	return parse_http_json_response(response_code, response_body.get_string_from_utf8())

static func parse_http_json_response(response_code: int, body_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(str(body_text))
	if parsed == null:
		parsed = {}

	if response_code < 200 or response_code >= 300:
		if parsed is Dictionary:
			var err_body: Dictionary = Dictionary(parsed)
			err_body["_http_status"] = int(response_code)
			return {"error": err_body}
		return {"error": {
			"_http_status": int(response_code),
			"body": parsed,
		}}

	return {"ok": parsed}


# === Auth ===

func guest_login(device_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/guest", {"device_id": device_id})


func register(email: String, password: String, display_name: String = "") -> Dictionary:
	var payload := {"email": email, "password": password}
	var dn := str(display_name).strip_edges()
	if not dn.is_empty():
		payload["display_name"] = dn
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/register", payload)


func login(email: String, password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/login", {"email": email, "password": password})


func bind(session_id: String, provider: String, email: String, password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/bind", {
		"session_id": session_id, "provider": provider,
		"email": email, "password": password,
	})


func logout(session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/logout", {"session_id": session_id})


# === Rooms ===

func create_room(session_id: String, config_json: String = "{}", password: String = "") -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/rooms", {
		"session_id": session_id, "config_json": config_json, "password": password,
	})


func join_room(room_code: String, session_id: String, password: String = "") -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/rooms/%s/join" % room_code, {
		"session_id": session_id, "password": password,
	})


func spectate_room(room_code: String, session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/rooms/%s/spectate" % room_code, {
		"session_id": session_id,
	})


func get_room(room_code: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/rooms/%s" % room_code)

func list_rooms(session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/rooms?session_id=%s" % session_id)


# === Matches ===

func list_matches(session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/matches?session_id=%s" % session_id)


func get_match(match_id: String, session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/matches/%s?session_id=%s" % [match_id, session_id])


func get_replay(match_id: String, session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/matches/%s/replay?session_id=%s" % [match_id, session_id])


# === Device Auth ===

func request_device_code(device_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/device/code", {"device_id": device_id})


func poll_device_token(device_code: String, device_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/device/token", {
		"device_code": device_code, "device_id": device_id,
	})


func get_me(session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/auth/me?session_id=%s" % session_id)


func update_profile(session_id: String, display_name: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, "/v1/auth/profile", {
		"session_id": session_id,
		"display_name": str(display_name),
	})
