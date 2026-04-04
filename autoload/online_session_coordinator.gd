extends Node

const ResumeErrorPolicyClass = preload("res://ui/scenes/online/online_resume_error_policy.gd")

const TARGET_LOBBY := "online_lobby"
const TARGET_GAME := "game"
const LOBBY_AUTO_RESUME_RETRY_DELAYS_SEC := [0.0, 0.5, 1.5]
const STARTUP_GAME_RESUME_RETRY_DELAYS_SEC := [0.0, 0.5, 1.5]
const LOBBY_CONNECT_TIMEOUT_SEC := 3.0
const STARTUP_GAME_RESUME_TIMEOUT_SEC := 6.0

signal resume_context_changed(state: Dictionary)
signal resume_terminal(reason: String)

class _ResumeWaitState:
	extends RefCounted

	var mode: String = ""
	var target_room_code: String = ""
	var connected: bool = false
	var disconnected: bool = false
	var disconnect_reason: String = ""
	var request_rejected: bool = false
	var rejection_code: String = ""
	var rejection_message: String = ""
	var room_state_ready: bool = false
	var game_started_received: bool = false
	var archive_received: bool = false
	var delta_applied: bool = false
	var delta_failed: bool = false
	var delta_error: String = ""

func remember_online_room(
	room_code: String,
	role: String,
	platform_base_url: String,
	target_scene: String = TARGET_LOBBY
) -> void:
	if NetContext == null or not NetContext.has_method("set_online_resume_context"):
		return
	NetContext.set_online_resume_context(room_code, role, platform_base_url, target_scene)
	_emit_resume_context_changed()

func clear_online_resume_context() -> void:
	if NetContext == null or not NetContext.has_method("clear_online_resume_context"):
		return
	NetContext.clear_online_resume_context()
	_emit_resume_context_changed()

func mark_resume_terminal(reason: String) -> void:
	if NetContext == null:
		return
	if NetContext.has_method("set_online_resume_terminal"):
		NetContext.set_online_resume_terminal(reason)
	elif NetContext.has_method("clear_online_resume_context"):
		NetContext.clear_online_resume_context()
	_emit_resume_context_changed()
	resume_terminal.emit(str(reason).strip_edges())

func has_active_resume_context() -> bool:
	if NetContext == null or not NetContext.has_method("has_online_resume_context"):
		return false
	return bool(NetContext.has_online_resume_context())

func has_resume_record() -> bool:
	if NetContext == null:
		return false
	if NetContext.has_method("has_online_resume_record"):
		return bool(NetContext.has_online_resume_record())
	if NetContext.has_method("has_online_resume_context"):
		return bool(NetContext.has_online_resume_context())
	return false

func get_resume_target_scene() -> String:
	if NetContext == null or not NetContext.has_method("get_online_resume_target_scene"):
		return TARGET_LOBBY
	return str(NetContext.get_online_resume_target_scene()).strip_edges()

func should_auto_resume_from_main_menu() -> bool:
	if Globals != null and str(Globals.pending_replay_file_path).strip_edges() != "":
		return false
	if not has_active_resume_context():
		return false
	if NetClient != null and NetClient.is_online_client_connected():
		return false
	return true

func should_attempt_lobby_auto_resume() -> bool:
	if not should_auto_resume_from_main_menu():
		return false
	if NetContext != null and NetContext.has_method("is_online_resume_in_game") and NetContext.is_online_resume_in_game():
		return false
	return get_resume_target_scene() != TARGET_GAME

func should_attempt_startup_game_resume() -> bool:
	if Globals != null and str(Globals.pending_replay_file_path).strip_edges() != "":
		return false
	if not has_active_resume_context():
		return false
	if NetContext == null or not NetContext.has_method("is_online_resume_in_game"):
		return false
	if not NetContext.is_online_resume_in_game():
		return false
	return true

func sync_room_state(room_state: Dictionary) -> void:
	if NetContext == null or not NetContext.has_method("sync_online_resume_context_from_room_state"):
		return
	NetContext.sync_online_resume_context_from_room_state(room_state)
	_emit_resume_context_changed()

func mark_game_started() -> void:
	if NetContext == null or not NetContext.has_method("mark_online_resume_in_game"):
		return
	NetContext.mark_online_resume_in_game(true)
	_emit_resume_context_changed()

func begin_in_game_reconnect() -> void:
	if NetContext == null or not NetContext.has_method("set_online_reconnecting"):
		return
	if not can_attempt_in_game_resume():
		return
	NetContext.set_online_reconnecting(true)
	_emit_resume_context_changed()

func finish_in_game_reconnect(success: bool, terminal_reason: String = "") -> void:
	if NetContext != null and NetContext.has_method("set_online_reconnecting"):
		NetContext.set_online_reconnecting(false)
	if not bool(success) and not str(terminal_reason).strip_edges().is_empty():
		mark_resume_terminal(str(terminal_reason))
		return
	_emit_resume_context_changed()

func can_attempt_in_game_resume() -> bool:
	if not has_active_resume_context():
		return false
	if NetContext == null or not NetContext.has_method("is_online_resume_in_game"):
		return false
	return bool(NetContext.is_online_resume_in_game())

func request_leave_room(net_client_override = null) -> String:
	mark_resume_terminal("leave_room")
	var net = net_client_override if net_client_override != null else NetClient
	if net == null or not net.has_method("request_leave_room"):
		return ""
	return str(net.request_leave_room())

func request_forfeit_and_leave_room(net_client_override = null) -> String:
	mark_resume_terminal("forfeit_and_leave_room")
	var net = net_client_override if net_client_override != null else NetClient
	if net == null or not net.has_method("request_forfeit_and_leave_room"):
		return ""
	return str(net.request_forfeit_and_leave_room())

func request_resume_ticket(options: Dictionary = {}) -> Result:
	if NetContext == null or not NetContext.has_method("get_online_resume_room_code"):
		return Result.failure("联机恢复状态缺失")
	if not has_active_resume_context():
		return Result.failure("联机恢复状态缺失")

	var ensure_session := _get_callable_option(options, "ensure_session", Callable(self, "_default_ensure_session"))
	var resume_room := _get_callable_option(options, "resume_room", Callable(self, "_default_resume_room"))

	var ensure_r = await ensure_session.call()
	if not (ensure_r is Result) or not ensure_r.ok:
		var ensure_error := str(ensure_r.error) if ensure_r is Result else "平台登录返回类型错误"
		var ensure_policy := ResumeErrorPolicyClass.classify_resume_failure("平台登录失败：%s" % ensure_error)
		if bool(ensure_policy.get("clear_resume_context", false)):
			mark_resume_terminal(str(ensure_policy.get("user_message", ensure_error)))
		return Result.failure(str(ensure_policy.get("user_message", ensure_error)))

	var expected_user_id := NetContext.get_online_resume_user_id() if NetContext.has_method("get_online_resume_user_id") else ""
	var active_user_id := PlatformSession.user_id if PlatformSession != null else ""
	var user_policy := ResumeErrorPolicyClass.classify_user_mismatch(expected_user_id, active_user_id)
	if bool(user_policy.get("clear_resume_context", false)):
		mark_resume_terminal(str(user_policy.get("user_message", "账号不匹配")))
		return Result.failure(str(user_policy.get("user_message", "账号不匹配")))

	var room_code := NetContext.get_online_resume_room_code()
	if str(room_code).strip_edges().is_empty():
		return Result.failure("联机恢复 room_code 缺失")

	var resume_resp = await resume_room.call(room_code)
	if not (resume_resp is Dictionary):
		return Result.failure("resume_room 返回格式错误")
	var resume_dict: Dictionary = Dictionary(resume_resp)
	if resume_dict.has("error"):
		var policy := ResumeErrorPolicyClass.classify_resume_failure(resume_dict.get("error", ""))
		var message := str(policy.get("user_message", _stringify_platform_error(resume_dict.get("error", ""))))
		if bool(policy.get("clear_resume_context", false)):
			mark_resume_terminal(message)
		return Result.failure(message)
	var ok_val = resume_dict.get("ok", null)
	if not (ok_val is Dictionary):
		return Result.failure("resume_room 响应缺少 ok")
	var ok: Dictionary = Dictionary(ok_val)
	var ws_url := str(ok.get("ws_url", "")).strip_edges()
	var connect_token := str(ok.get("connect_token", "")).strip_edges()
	if ws_url.is_empty() or connect_token.is_empty():
		return Result.failure("resume_room 缺少 ws_url/connect_token")

	return Result.success({
		"room_code": str(room_code).strip_edges().to_upper(),
		"ws_url": ws_url,
		"connect_token": connect_token,
	})

func attempt_lobby_auto_resume(options: Dictionary = {}) -> Dictionary:
	return await _attempt_auto_resume_flow("lobby", options)

func attempt_startup_game_resume(options: Dictionary = {}) -> Dictionary:
	return await _attempt_auto_resume_flow("startup_game", options)

func _attempt_auto_resume_flow(mode: String, options: Dictionary) -> Dictionary:
	var should_attempt := false
	match mode:
		"startup_game":
			should_attempt = should_attempt_startup_game_resume()
		_:
			should_attempt = should_attempt_lobby_auto_resume()
	if not should_attempt:
		return {
			"attempted": false,
			"ok": false,
		}

	var connect_resume := _get_callable_option(options, "connect_resume", Callable(self, "_default_connect_resume"))
	var on_game_started := _get_callable_option(options, "on_game_started", Callable())
	var on_status_changed := _get_callable_option(options, "on_status_changed", Callable())
	var host_node := _get_wait_host(options)
	var retry_delays: Array = _get_retry_delays(mode, options)
	var timeout_sec := _get_timeout_sec(mode, options)
	var shutdown_on_wait_failure := bool(options.get("shutdown_on_wait_failure", true))

	for attempt_index in range(retry_delays.size()):
		if attempt_index == 0:
			_emit_status(
				on_status_changed,
				"正在恢复联机对局..." if mode == "startup_game" else "检测到未完成联机对局，正在恢复..."
			)
		else:
			await _wait_seconds(host_node, float(retry_delays[attempt_index]))
			_emit_status(
				on_status_changed,
				"恢复失败，正在重试（%d/%d）..." % [attempt_index + 1, retry_delays.size()]
			)

		var ticket_r: Result = await request_resume_ticket(options)
		if not ticket_r.ok:
			if attempt_index == retry_delays.size() - 1:
				return {
					"attempted": true,
					"ok": false,
					"title": "自动恢复失败" if mode == "lobby" else "联机恢复失败",
					"message": str(ticket_r.error),
				}
			continue

		var ticket_payload: Dictionary = Dictionary(ticket_r.value)
		_emit_status(
			on_status_changed,
			"正在重新连接服务器..." if mode == "startup_game" else "正在恢复房间连接..."
		)
		var connect_r = connect_resume.call(
			str(ticket_payload.get("ws_url", "")),
			str(ticket_payload.get("connect_token", ""))
		)
		if not (connect_r is Result) or not connect_r.ok:
			var connect_error := str(connect_r.error) if connect_r is Result else "connect_resume 返回类型错误"
			if attempt_index == retry_delays.size() - 1:
				return {
					"attempted": true,
					"ok": false,
					"title": "自动恢复失败" if mode == "lobby" else "联机恢复失败",
					"message": connect_error,
				}
			continue

		var wait_result := await _wait_for_resume_ready(
			mode,
			host_node,
			str(ticket_payload.get("room_code", "")),
			timeout_sec,
			on_game_started,
			on_status_changed
		)
		if bool(wait_result.get("ok", false)):
			if NetContext != null and NetContext.has_method("set_online_reconnecting"):
				NetContext.set_online_reconnecting(false)
			_emit_resume_context_changed()
			return {
				"attempted": true,
				"ok": true,
			}

		if shutdown_on_wait_failure:
			_shutdown_net(false)
		if bool(wait_result.get("terminal", false)):
			mark_resume_terminal(str(wait_result.get("message", "")))
		if attempt_index == retry_delays.size() - 1:
			return {
				"attempted": true,
				"ok": false,
				"title": "自动恢复失败" if mode == "lobby" else "联机恢复失败",
				"message": str(wait_result.get("message", "恢复超时")),
			}

	return {
		"attempted": true,
		"ok": false,
		"title": "自动恢复失败" if mode == "lobby" else "联机恢复失败",
		"message": "恢复失败",
	}

func _wait_for_resume_ready(
	mode: String,
	host_node: Node,
	target_room_code: String,
	timeout_sec: float,
	on_game_started: Callable,
	on_status_changed: Callable
) -> Dictionary:
	if host_node == null or not is_instance_valid(host_node):
		return {
			"ok": false,
			"message": "Resume wait host missing",
		}
	if NetClient == null:
		return {
			"ok": false,
			"message": "NetClient autoload missing",
		}

	var wait_state := _ResumeWaitState.new()
	wait_state.mode = str(mode)
	wait_state.target_room_code = str(target_room_code).strip_edges().to_upper()
	var callbacks := _connect_resume_wait_signals(wait_state, on_game_started, on_status_changed)
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)

	while Time.get_ticks_msec() <= deadline:
		if mode == "startup_game":
			if wait_state.game_started_received and (wait_state.archive_received or wait_state.delta_applied):
				_disconnect_resume_wait_signals(callbacks)
				return {"ok": true}
		elif wait_state.room_state_ready:
			_disconnect_resume_wait_signals(callbacks)
			return {"ok": true}

		if wait_state.request_rejected:
			_disconnect_resume_wait_signals(callbacks)
			return {
				"ok": false,
				"message": "%s: %s" % [wait_state.rejection_code, wait_state.rejection_message],
				"terminal": _is_terminal_resume_rejection(wait_state.rejection_code),
			}

		if wait_state.delta_failed:
			_disconnect_resume_wait_signals(callbacks)
			return {
				"ok": false,
				"message": wait_state.delta_error if not wait_state.delta_error.is_empty() else "delta 恢复失败",
				"terminal": false,
			}

		if wait_state.disconnected:
			_disconnect_resume_wait_signals(callbacks)
			return {
				"ok": false,
				"message": wait_state.disconnect_reason if not wait_state.disconnect_reason.is_empty() else "连接服务器超时",
				"terminal": false,
			}

		await host_node.get_tree().process_frame

	_disconnect_resume_wait_signals(callbacks)
	return {
		"ok": false,
		"message": "恢复对局超时" if mode == "startup_game" else "连接服务器超时",
		"terminal": false,
	}

func _connect_resume_wait_signals(wait_state: _ResumeWaitState, on_game_started: Callable, on_status_changed: Callable) -> Dictionary:
	var callbacks := {
		"connected": Callable(self, "_on_wait_connected").bind(wait_state),
		"disconnected": Callable(self, "_on_wait_disconnected").bind(wait_state),
		"request_rejected": Callable(self, "_on_wait_request_rejected").bind(wait_state),
		"room_state_updated": Callable(self, "_on_wait_room_state_updated").bind(wait_state),
		"game_started": Callable(self, "_on_wait_game_started").bind(wait_state, on_game_started, on_status_changed),
		"resync_archive_received": Callable(self, "_on_wait_resync_archive_received").bind(wait_state, on_status_changed),
		"resync_delta_applied": Callable(self, "_on_wait_resync_delta_applied").bind(wait_state, on_status_changed),
		"resync_delta_failed": Callable(self, "_on_wait_resync_delta_failed").bind(wait_state),
	}
	if not NetClient.connected.is_connected(callbacks["connected"]):
		NetClient.connected.connect(callbacks["connected"])
	if not NetClient.disconnected.is_connected(callbacks["disconnected"]):
		NetClient.disconnected.connect(callbacks["disconnected"])
	if not NetClient.request_rejected.is_connected(callbacks["request_rejected"]):
		NetClient.request_rejected.connect(callbacks["request_rejected"])
	if not NetClient.room_state_updated.is_connected(callbacks["room_state_updated"]):
		NetClient.room_state_updated.connect(callbacks["room_state_updated"])
	if not NetClient.game_started.is_connected(callbacks["game_started"]):
		NetClient.game_started.connect(callbacks["game_started"])
	if not NetClient.resync_archive_received.is_connected(callbacks["resync_archive_received"]):
		NetClient.resync_archive_received.connect(callbacks["resync_archive_received"])
	if not NetClient.resync_delta_applied.is_connected(callbacks["resync_delta_applied"]):
		NetClient.resync_delta_applied.connect(callbacks["resync_delta_applied"])
	if not NetClient.resync_delta_failed.is_connected(callbacks["resync_delta_failed"]):
		NetClient.resync_delta_failed.connect(callbacks["resync_delta_failed"])
	return callbacks

func _disconnect_resume_wait_signals(callbacks: Dictionary) -> void:
	if NetClient == null:
		return
	if callbacks.has("connected") and NetClient.connected.is_connected(callbacks["connected"]):
		NetClient.connected.disconnect(callbacks["connected"])
	if callbacks.has("disconnected") and NetClient.disconnected.is_connected(callbacks["disconnected"]):
		NetClient.disconnected.disconnect(callbacks["disconnected"])
	if callbacks.has("request_rejected") and NetClient.request_rejected.is_connected(callbacks["request_rejected"]):
		NetClient.request_rejected.disconnect(callbacks["request_rejected"])
	if callbacks.has("room_state_updated") and NetClient.room_state_updated.is_connected(callbacks["room_state_updated"]):
		NetClient.room_state_updated.disconnect(callbacks["room_state_updated"])
	if callbacks.has("game_started") and NetClient.game_started.is_connected(callbacks["game_started"]):
		NetClient.game_started.disconnect(callbacks["game_started"])
	if callbacks.has("resync_archive_received") and NetClient.resync_archive_received.is_connected(callbacks["resync_archive_received"]):
		NetClient.resync_archive_received.disconnect(callbacks["resync_archive_received"])
	if callbacks.has("resync_delta_applied") and NetClient.resync_delta_applied.is_connected(callbacks["resync_delta_applied"]):
		NetClient.resync_delta_applied.disconnect(callbacks["resync_delta_applied"])
	if callbacks.has("resync_delta_failed") and NetClient.resync_delta_failed.is_connected(callbacks["resync_delta_failed"]):
		NetClient.resync_delta_failed.disconnect(callbacks["resync_delta_failed"])

func _on_wait_connected(wait_state: _ResumeWaitState) -> void:
	if wait_state == null:
		return
	wait_state.connected = true

func _on_wait_disconnected(reason: String, wait_state: _ResumeWaitState) -> void:
	if wait_state == null:
		return
	wait_state.disconnected = true
	wait_state.disconnect_reason = str(reason)

func _on_wait_request_rejected(_request_id: String, code: String, message: String, wait_state: _ResumeWaitState) -> void:
	if wait_state == null:
		return
	wait_state.request_rejected = true
	wait_state.rejection_code = str(code).strip_edges()
	wait_state.rejection_message = str(message).strip_edges()

func _on_wait_room_state_updated(room_state: Dictionary, wait_state: _ResumeWaitState) -> void:
	if wait_state == null:
		return
	sync_room_state(room_state)
	var room_code := str(room_state.get("room_code", "")).strip_edges().to_upper()
	if room_code.is_empty():
		return
	if wait_state.target_room_code.is_empty():
		return
	if room_code != wait_state.target_room_code:
		return
	wait_state.room_state_ready = true

func _on_wait_game_started(
	payload: Dictionary,
	wait_state: _ResumeWaitState,
	on_game_started: Callable,
	on_status_changed: Callable
) -> void:
	if wait_state == null:
		return
	wait_state.game_started_received = true
	mark_game_started()
	_emit_status(on_status_changed, "已连接，正在同步对局...")
	if on_game_started.is_valid():
		on_game_started.call(payload)

func _on_wait_resync_archive_received(
	_archive: Dictionary,
	wait_state: _ResumeWaitState,
	on_status_changed: Callable
) -> void:
	if wait_state == null:
		return
	wait_state.archive_received = true
	_emit_status(on_status_changed, "已收到对局快照，正在应用...")

func _on_wait_resync_delta_applied(
	_payload: Dictionary,
	wait_state: _ResumeWaitState,
	on_status_changed: Callable
) -> void:
	if wait_state == null:
		return
	wait_state.delta_applied = true
	_emit_status(on_status_changed, "已完成增量恢复，正在进入对局...")

func _on_wait_resync_delta_failed(message: String, wait_state: _ResumeWaitState) -> void:
	if wait_state == null:
		return
	wait_state.delta_failed = true
	wait_state.delta_error = str(message)

func _default_ensure_session() -> Result:
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")
	if PlatformApi == null:
		return Result.failure("PlatformApi autoload missing")
	if PlatformSession.is_logged_in:
		return Result.success()
	if NetContext != null and NetContext.has_method("get_online_resume_platform_base_url"):
		var base_url := NetContext.get_online_resume_platform_base_url()
		if not str(base_url).is_empty():
			PlatformApi.base_url = str(base_url)
	var res: Dictionary = await PlatformSession.auto_guest_login()
	if res.has("error"):
		return Result.failure(str(res.get("error", "platform login failed")))
	if not PlatformSession.is_logged_in:
		return Result.failure("platform login failed")
	return Result.success()

func _default_resume_room(room_code: String) -> Dictionary:
	if PlatformApi == null:
		return {"error": "PlatformApi autoload missing"}
	if PlatformSession == null or not PlatformSession.is_logged_in:
		return {"error": "PlatformSession unavailable"}
	if NetContext != null and NetContext.has_method("get_online_resume_platform_base_url"):
		var base_url := NetContext.get_online_resume_platform_base_url()
		if not str(base_url).is_empty():
			PlatformApi.base_url = str(base_url)
	return await PlatformApi.resume_room(str(room_code).strip_edges().to_upper(), PlatformSession.session_id)

func _default_connect_resume(ws_url: String, connect_token: String) -> Result:
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
	var url := _build_connect_url(ws_url, connect_token)
	if url.is_empty():
		return Result.failure("无效的 ws_url")
	return NetClient.connect_to_server(url, true)

func _build_connect_url(ws_url: String, connect_token: String) -> String:
	var base := str(ws_url).strip_edges()
	var token := str(connect_token).strip_edges()
	if base.is_empty() or token.is_empty():
		return ""
	var sep := "?" if base.find("?") < 0 else "&"
	return base + sep + "connect_token=" + token.uri_encode()

func _get_callable_option(options: Dictionary, key: String, default_callable: Callable = Callable()) -> Callable:
	var value = options.get(key, null)
	if value is Callable:
		return value
	return default_callable

func _get_wait_host(options: Dictionary) -> Node:
	var value = options.get("host", null)
	if value != null and value is Node and is_instance_valid(value):
		return value
	return self

func _get_retry_delays(mode: String, options: Dictionary) -> Array:
	var provided = options.get("retry_delays_sec", null)
	if provided is Array and not Array(provided).is_empty():
		return Array(provided)
	if mode == "startup_game":
		return STARTUP_GAME_RESUME_RETRY_DELAYS_SEC.duplicate(true)
	return LOBBY_AUTO_RESUME_RETRY_DELAYS_SEC.duplicate(true)

func _get_timeout_sec(mode: String, options: Dictionary) -> float:
	var key := "timeout_sec"
	if options.has(key):
		var timeout_val = options.get(key, null)
		if timeout_val is int or timeout_val is float:
			return float(timeout_val)
	if mode == "startup_game":
		return STARTUP_GAME_RESUME_TIMEOUT_SEC
	return LOBBY_CONNECT_TIMEOUT_SEC

func _emit_status(status_changed: Callable, message: String) -> void:
	if status_changed.is_valid():
		status_changed.call(str(message))

func _emit_resume_context_changed() -> void:
	var state: Dictionary = {}
	if NetContext != null and NetContext.online_resume_state is Dictionary:
		state = Dictionary(NetContext.online_resume_state).duplicate(true)
	resume_context_changed.emit(state)

func _wait_seconds(host_node: Node, duration_sec: float) -> void:
	if host_node == null or not is_instance_valid(host_node):
		return
	var tree := host_node.get_tree()
	if tree == null:
		return
	await tree.create_timer(duration_sec).timeout

func _shutdown_net(reset_context: bool) -> void:
	if NetClient != null and NetClient.has_method("shutdown"):
		NetClient.shutdown(bool(reset_context))

func _is_terminal_resume_rejection(code: String) -> bool:
	var normalized := str(code).strip_edges()
	return normalized == "protocol_version_mismatch" \
		or normalized == "missing_connect_token" \
		or normalized == "invalid_connect_token" \
		or normalized == "platform_join_failed" \
		or normalized == "server_misconfigured" \
		or normalized == "not_in_room" \
		or normalized == "not_in_game" \
		or normalized == "seat_forfeited" \
		or normalized == "seat_released" \
		or normalized == "room_ended" \
		or normalized == "generation_conflict"

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
