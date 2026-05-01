# 平台 API 封装
# 封装 Backend HTTP 调用
extends Node

const _DEFAULT_PLATFORM_BASE_URL := "https://fcm.home.ygowill.net:8443"
const _PROJECT_SETTING_PLATFORM_BACKEND_URL := "fcm/platform_backend_url"
const _ENV_PLATFORM_BACKEND_URL := "FCM_PLATFORM_BACKEND_URL"
const _ENV_WEB_ORIGIN := "FCM_WEB_ORIGIN"
const _ENV_PLATFORM_TLS_INSECURE := "FCM_PLATFORM_TLS_INSECURE"

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
	if _should_use_insecure_tls(url):
		http.set_tls_options(TLSOptions.client_unsafe())
	add_child(http)
	var err := http.request(url, headers, method, json_body)
	if err != OK:
		http.queue_free()
		return {"error": "request_failed", "code": err}
	var result: Array = await http.request_completed
	http.queue_free()
	var request_result: int = int(result[0]) if result.size() > 0 else HTTPRequest.RESULT_REQUEST_FAILED
	var response_code: int = int(result[1]) if result.size() > 1 else 0
	var response_body: PackedByteArray = PackedByteArray(result[3]) if result.size() > 3 else PackedByteArray()
	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {"error": _build_transport_error(url, request_result, response_code)}
	return parse_http_json_response(response_code, response_body.get_string_from_utf8())

func _should_use_insecure_tls(url: String) -> bool:
	var normalized := str(url).strip_edges().to_lower()
	if not normalized.begins_with("https://"):
		return false
	var raw := str(OS.get_environment(_ENV_PLATFORM_TLS_INSECURE)).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes" or raw == "on"

static func _http_request_result_name(code: int) -> String:
	match int(code):
		HTTPRequest.RESULT_SUCCESS:
			return "success"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "chunked_body_size_mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "cant_connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "cant_resolve"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection_error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "tls_handshake_error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no_response"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "body_size_limit_exceeded"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "body_decompress_failed"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "request_failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "download_file_cant_open"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "download_file_write_error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "redirect_limit_reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		_:
			return "unknown_%d" % int(code)

func _build_transport_error(url: String, request_result: int, response_code: int) -> Dictionary:
	var result_name := _http_request_result_name(request_result)
	var detail := "网络请求失败：%s（result=%d, http_status=%d）" % [result_name, int(request_result), int(response_code)]
	if int(request_result) == HTTPRequest.RESULT_CANT_CONNECT and str(url).begins_with("https://"):
		detail += "。若是自建 HTTPS 服务器，请优先检查证书链与域名匹配；排障时可临时设置 FCM_PLATFORM_TLS_INSECURE=1。"
	return {
		"_http_status": int(response_code),
		"_http_result": int(request_result),
		"_http_result_name": result_name,
		"_url": str(url),
		"detail": detail,
	}

static func parse_http_json_response(response_code: int, body_text: String) -> Dictionary:
	var parser := JSON.new()
	var parse_err := parser.parse(str(body_text))
	if parse_err != OK:
		return {"error": {
			"_http_status": int(response_code),
			"parse_error": parser.get_error_message(),
			"parse_error_line": parser.get_error_line(),
			"body_text": str(body_text),
		}}
	var parsed: Variant = parser.data

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


func resume_room(room_code: String, session_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/rooms/%s/resume" % room_code, {
		"session_id": session_id,
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


func update_email(session_id: String, email: String, password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, "/v1/auth/email", {
		"session_id": session_id,
		"email": str(email),
		"password": str(password),
	})


func change_password(session_id: String, old_password: String, new_password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, "/v1/auth/password", {
		"session_id": session_id,
		"old_password": str(old_password),
		"new_password": str(new_password),
	})
