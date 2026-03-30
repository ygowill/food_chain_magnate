# Game scene：冷启动联机恢复控制器
class_name GameStartupOnlineResumeController
extends RefCounted

const STARTUP_RESUME_TIMEOUT_SEC := 6.0

var _host: Node = null
var _ensure_session: Callable = Callable()
var _resume_room: Callable = Callable()
var _connect_to_server: Callable = Callable()
var _on_game_started: Callable = Callable()
var _on_failure: Callable = Callable()

var _game_started_received: bool = false
var _archive_received: bool = false
var _failed: bool = false
var _failure_message: String = ""

func _init(
	host: Node,
	ensure_session: Callable,
	resume_room: Callable,
	connect_to_server: Callable,
	on_game_started: Callable,
	on_failure: Callable
) -> void:
	_host = host
	_ensure_session = ensure_session
	_resume_room = resume_room
	_connect_to_server = connect_to_server
	_on_game_started = on_game_started
	_on_failure = on_failure

func should_attempt_startup_resume() -> bool:
	if _host == null or not is_instance_valid(_host):
		return false
	if NetContext == null or not NetContext.has_method("has_online_resume_context"):
		return false
	if not NetContext.has_online_resume_context():
		return false
	if not NetContext.has_method("is_online_resume_in_game") or not NetContext.is_online_resume_in_game():
		return false
	if Globals != null and str(Globals.pending_replay_file_path).strip_edges() != "":
		return false
	return true

func attempt_startup_resume_if_needed() -> bool:
	if not should_attempt_startup_resume():
		return false
	if NetClient == null:
		_fail("NetClient autoload missing")
		return false

	_game_started_received = false
	_archive_received = false
	_failed = false
	_failure_message = ""
	_connect_net_signals()

	var ensure_r = await _ensure_session.call()
	if not (ensure_r is Result) or not ensure_r.ok:
		_disconnect_net_signals()
		var err_text: String = str(ensure_r.error) if ensure_r is Result else "平台登录返回类型错误"
		_fail("平台登录失败：%s" % err_text)
		return false

	var room_code := NetContext.get_online_resume_room_code() if NetContext != null else ""
	var resume_resp = await _resume_room.call(room_code)
	if not (resume_resp is Dictionary):
		_disconnect_net_signals()
		_fail("resume_room 返回格式错误")
		return false
	var resume_dict: Dictionary = Dictionary(resume_resp)
	if resume_dict.has("error"):
		_disconnect_net_signals()
		_fail(_stringify_platform_error(resume_dict.get("error", "")))
		return false
	var ok_val = resume_dict.get("ok", null)
	if not (ok_val is Dictionary):
		_disconnect_net_signals()
		_fail("resume_room 响应缺少 ok")
		return false
	var ok: Dictionary = Dictionary(ok_val)
	var ws_url := str(ok.get("ws_url", "")).strip_edges()
	var connect_token := str(ok.get("connect_token", "")).strip_edges()
	if ws_url.is_empty() or connect_token.is_empty():
		_disconnect_net_signals()
		_fail("resume_room 缺少 ws_url/connect_token")
		return false

	var connect_r = _connect_to_server.call(_build_connect_url(ws_url, connect_token))
	if not (connect_r is Result) or not connect_r.ok:
		_disconnect_net_signals()
		var connect_err: String = str(connect_r.error) if connect_r is Result else "connect_to_server 返回类型错误"
		_fail(connect_err)
		return false

	var ok_startup := await _wait_for_startup_resume()
	_disconnect_net_signals()
	if not ok_startup:
		_fail(_failure_message if not _failure_message.is_empty() else "联机恢复超时")
		return false
	return true

func _connect_net_signals() -> void:
	var cb_game_started := Callable(self, "_on_net_game_started")
	var cb_archive := Callable(self, "_on_net_resync_archive_received")
	var cb_rejected := Callable(self, "_on_net_request_rejected")
	var cb_disconnected := Callable(self, "_on_net_disconnected")
	if not NetClient.game_started.is_connected(cb_game_started):
		NetClient.game_started.connect(cb_game_started)
	if not NetClient.resync_archive_received.is_connected(cb_archive):
		NetClient.resync_archive_received.connect(cb_archive)
	if not NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.connect(cb_rejected)
	if not NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.connect(cb_disconnected)

func _disconnect_net_signals() -> void:
	if NetClient == null:
		return
	var cb_game_started := Callable(self, "_on_net_game_started")
	var cb_archive := Callable(self, "_on_net_resync_archive_received")
	var cb_rejected := Callable(self, "_on_net_request_rejected")
	var cb_disconnected := Callable(self, "_on_net_disconnected")
	if NetClient.game_started.is_connected(cb_game_started):
		NetClient.game_started.disconnect(cb_game_started)
	if NetClient.resync_archive_received.is_connected(cb_archive):
		NetClient.resync_archive_received.disconnect(cb_archive)
	if NetClient.request_rejected.is_connected(cb_rejected):
		NetClient.request_rejected.disconnect(cb_rejected)
	if NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.disconnect(cb_disconnected)

func _wait_for_startup_resume() -> bool:
	if _host == null or not is_instance_valid(_host):
		return false
	var deadline := Time.get_ticks_msec() + int(STARTUP_RESUME_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() <= deadline:
		if _failed:
			return false
		if _game_started_received and _archive_received:
			return true
		await _host.get_tree().process_frame
	return false

func _on_net_game_started(payload: Dictionary) -> void:
	_game_started_received = true
	if _on_game_started.is_valid():
		_on_game_started.call(payload)

func _on_net_resync_archive_received(_archive: Dictionary) -> void:
	_archive_received = true

func _on_net_request_rejected(_request_id: String, code: String, message: String) -> void:
	_failed = true
	_failure_message = "%s: %s" % [str(code), str(message)]

func _on_net_disconnected(reason: String) -> void:
	_failed = true
	_failure_message = str(reason)

func _build_connect_url(ws_url: String, connect_token: String) -> String:
	var base := str(ws_url).strip_edges()
	var token := str(connect_token).strip_edges()
	var sep := "?" if base.find("?") < 0 else "&"
	return base + sep + "connect_token=" + token.uri_encode()

func _fail(message: String) -> void:
	_failed = true
	_failure_message = str(message)
	if _on_failure.is_valid():
		_on_failure.call(str(message))

func _stringify_platform_error(error_val) -> String:
	if error_val is Dictionary:
		var err_dict: Dictionary = Dictionary(error_val)
		var detail := str(err_dict.get("detail", "")).strip_edges()
		if not detail.is_empty():
			return detail
		var body: Variant = err_dict.get("body", null)
		if body != null:
			return str(body)
		return JSON.stringify(err_dict)
	var text := str(error_val).strip_edges()
	if text.is_empty():
		return "未知错误"
	return text
