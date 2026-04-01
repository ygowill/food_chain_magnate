# 联机大厅：冷启动恢复控制器
class_name OnlineLobbyResumeController
extends RefCounted

const ResumeErrorPolicyClass = preload("res://ui/scenes/online/online_resume_error_policy.gd")
const RETRY_DELAYS_SEC := [0.0, 0.5, 1.5]
const CONNECT_TIMEOUT_SEC := 3.0

var _ensure_session: Callable = Callable()
var _resume_room: Callable = Callable()
var _connect_to_ws: Callable = Callable()
var _mark_platform_ready: Callable = Callable()
var _set_connect_status: Callable = Callable()
var _set_browse_status: Callable = Callable()
var _show_error: Callable = Callable()
var _hide_loading: Callable = Callable()
var _refresh_ui: Callable = Callable()
var _attempted: bool = false
var _connected: bool = false
var _disconnected: bool = false
var _disconnect_reason: String = ""

func setup(
	ensure_session: Callable,
	resume_room: Callable,
	connect_to_ws: Callable,
	mark_platform_ready: Callable,
	set_connect_status: Callable,
	set_browse_status: Callable,
	show_error: Callable,
	hide_loading: Callable,
	refresh_ui: Callable
) -> void:
	_ensure_session = ensure_session
	_resume_room = resume_room
	_connect_to_ws = connect_to_ws
	_mark_platform_ready = mark_platform_ready
	_set_connect_status = set_connect_status
	_set_browse_status = set_browse_status
	_show_error = show_error
	_hide_loading = hide_loading
	_refresh_ui = refresh_ui

func has_attempted() -> bool:
	return _attempted

func should_attempt_auto_resume() -> bool:
	if _attempted:
		return false
	if NetContext == null or not NetContext.has_method("has_online_resume_context"):
		return false
	if not NetContext.has_online_resume_context():
		return false
	if Globals != null and str(Globals.pending_replay_file_path).strip_edges() != "":
		return false
	if NetClient != null and NetClient.is_online_client_connected():
		return false
	return true

func attempt_auto_resume_if_needed() -> void:
	if not should_attempt_auto_resume():
		return
	_attempted = true
	_set_auto_resume_reconnecting(true)
	_connect_netclient_signals()

	var last_message := "自动恢复失败"
	for attempt_index in range(RETRY_DELAYS_SEC.size()):
		if attempt_index == 0:
			_set_retry_status("检测到未完成联机对局，正在恢复...")
		else:
			await _wait_seconds(float(RETRY_DELAYS_SEC[attempt_index]))
			_set_retry_status("恢复失败，正在重试（%d/%d）..." % [attempt_index + 1, RETRY_DELAYS_SEC.size()])

		var ensure_r = await _ensure_session.call()
		if not (ensure_r is Result) or not ensure_r.ok:
			var err_text: String = str(ensure_r.error) if ensure_r is Result else "平台登录返回类型错误"
			var ensure_policy := ResumeErrorPolicyClass.classify_resume_failure("平台登录失败：%s" % err_text)
			last_message = str(ensure_policy.get("user_message", err_text))
			if bool(ensure_policy.get("clear_resume_context", false)):
				_clear_resume_context_if_needed()
				_fail("自动恢复失败", last_message)
				return
			if attempt_index == RETRY_DELAYS_SEC.size() - 1:
				_fail("自动恢复失败", last_message)
				return
			continue

		if _mark_platform_ready.is_valid():
			_mark_platform_ready.call()
		var user_policy := ResumeErrorPolicyClass.classify_user_mismatch(
			NetContext.get_online_resume_user_id() if NetContext != null and NetContext.has_method("get_online_resume_user_id") else "",
			PlatformSession.user_id if PlatformSession != null else ""
		)
		if bool(user_policy.get("clear_resume_context", false)):
			_clear_resume_context_if_needed()
			_fail("自动恢复已取消", str(user_policy.get("user_message", "账号不匹配")))
			return

		var room_code := NetContext.get_online_resume_room_code() if NetContext != null else ""
		var resume_resp = await _resume_room.call(room_code)
		if not (resume_resp is Dictionary):
			last_message = "resume_room 返回格式错误"
			if attempt_index == RETRY_DELAYS_SEC.size() - 1:
				_fail("自动恢复失败", last_message)
				return
			continue
		var resume_dict: Dictionary = Dictionary(resume_resp)
		if resume_dict.has("error"):
			var policy := ResumeErrorPolicyClass.classify_resume_failure(resume_dict.get("error", ""))
			last_message = str(policy.get("user_message", _stringify_platform_error(resume_dict.get("error", ""))))
			if bool(policy.get("clear_resume_context", false)):
				_clear_resume_context_if_needed()
				_fail("自动恢复失败", last_message)
				return
			if attempt_index == RETRY_DELAYS_SEC.size() - 1:
				_fail("自动恢复失败", last_message)
				return
			continue
		var ok_val = resume_dict.get("ok", null)
		if not (ok_val is Dictionary):
			last_message = "resume_room 响应缺少 ok"
			if attempt_index == RETRY_DELAYS_SEC.size() - 1:
				_fail("自动恢复失败", last_message)
				return
			continue
		var ok: Dictionary = Dictionary(ok_val)
		var ws_url := str(ok.get("ws_url", "")).strip_edges()
		var connect_token := str(ok.get("connect_token", "")).strip_edges()
		if ws_url.is_empty() or connect_token.is_empty():
			last_message = "resume_room 缺少 ws_url/connect_token"
			if attempt_index == RETRY_DELAYS_SEC.size() - 1:
				_fail("自动恢复失败", last_message)
				return
			continue

		_reset_connect_wait_state()
		var connect_r = _connect_to_ws.call(ws_url, connect_token)
		if connect_r is Result and not connect_r.ok:
			last_message = str(connect_r.error)
			if attempt_index == RETRY_DELAYS_SEC.size() - 1:
				_set_auto_resume_reconnecting(false)
				_disconnect_netclient_signals()
				_fail("自动恢复失败", last_message)
				return
			continue

		var connected_ok := await _wait_for_connect_result()
		if connected_ok:
			_set_auto_resume_reconnecting(false)
			_disconnect_netclient_signals()
			return

		last_message = _disconnect_reason if not _disconnect_reason.is_empty() else "连接服务器超时"
		if NetClient != null:
			NetClient.shutdown(false)
		if attempt_index == RETRY_DELAYS_SEC.size() - 1:
			_set_auto_resume_reconnecting(false)
			_disconnect_netclient_signals()
			_fail("自动恢复失败", last_message)
			return

	_set_auto_resume_reconnecting(false)
	_disconnect_netclient_signals()
	_fail("自动恢复失败", last_message)

func _fail(title: String, message: String) -> void:
	if _hide_loading.is_valid():
		_hide_loading.call()
	if _set_connect_status.is_valid():
		_set_connect_status.call(message)
	if _set_browse_status.is_valid():
		_set_browse_status.call("")
	if _refresh_ui.is_valid():
		_refresh_ui.call()
	if not OS.has_feature("headless") and _show_error.is_valid():
		_show_error.call(title, message)

func _clear_resume_context_if_needed() -> void:
	if NetContext == null or not NetContext.has_method("clear_online_resume_context"):
		return
	NetContext.clear_online_resume_context()

func _set_retry_status(message: String) -> void:
	if _set_connect_status.is_valid():
		_set_connect_status.call(str(message))
	if _set_browse_status.is_valid():
		_set_browse_status.call("正在恢复房间...")
	if _refresh_ui.is_valid():
		_refresh_ui.call()

func _wait_seconds(duration_sec: float) -> void:
	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	await (loop as SceneTree).create_timer(duration_sec).timeout

func _connect_netclient_signals() -> void:
	if NetClient == null:
		return
	var cb_connected := Callable(self, "_on_net_connected")
	var cb_disconnected := Callable(self, "_on_net_disconnected")
	if not NetClient.connected.is_connected(cb_connected):
		NetClient.connected.connect(cb_connected)
	if not NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.connect(cb_disconnected)

func _disconnect_netclient_signals() -> void:
	if NetClient == null:
		return
	var cb_connected := Callable(self, "_on_net_connected")
	var cb_disconnected := Callable(self, "_on_net_disconnected")
	if NetClient.connected.is_connected(cb_connected):
		NetClient.connected.disconnect(cb_connected)
	if NetClient.disconnected.is_connected(cb_disconnected):
		NetClient.disconnected.disconnect(cb_disconnected)

func _reset_connect_wait_state() -> void:
	_connected = false
	_disconnected = false
	_disconnect_reason = ""

func _wait_for_connect_result() -> bool:
	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var deadline := Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() <= deadline:
		if _connected:
			return true
		if _disconnected:
			return false
		await (loop as SceneTree).process_frame
	return false

func _on_net_connected() -> void:
	_connected = true

func _on_net_disconnected(reason: String) -> void:
	_disconnected = true
	_disconnect_reason = str(reason)

func _set_auto_resume_reconnecting(active: bool) -> void:
	if NetContext == null or not NetContext.has_method("set_online_reconnecting"):
		return
	if not NetContext.has_online_resume_context():
		return
	NetContext.set_online_reconnecting(bool(active))

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
