# GameOnlineResyncController：in-game 重连获取 resume ticket 时，不应在第一次 room already ended 后立刻清空恢复上下文
class_name GameOnlineResyncResumeTicketRetryPolicyTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop
	var host := Node.new()
	tree.root.add_child(host)

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_local_role := str(NetContext.local_role)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_session_id := str(PlatformSession.session_id)
	var prev_user_id := str(PlatformSession.user_id)
	var prev_is_guest := bool(PlatformSession.is_guest)
	var prev_display_name := str(PlatformSession.display_name)

	PlatformSession.session_id = "sess_retry_resume_ticket"
	PlatformSession.user_id = "u_retry_resume_ticket"
	PlatformSession.is_guest = true
	PlatformSession.display_name = "游客#5678"

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.set_online_resume_context("RTRYP1", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)

	var harness := _Harness.new()
	var controller = ControllerClass.new(
		host,
		null,
		Callable(harness, "get_engine"),
		Callable(harness, "apply_timeline"),
		Callable(),
		Callable(harness, "update_ui"),
		Callable(harness, "reset_timeline"),
		Callable(harness, "show_confirm"),
		Callable(harness, "goto_lobby"),
		Callable(harness, "show_loading"),
		Callable(harness, "hide_loading"),
		Callable(harness, "resume_room_request"),
		Callable(harness, "connect_to_server"),
		Callable(harness, "shutdown_net"),
		Callable(harness, "request_resync"),
		Callable(harness, "ensure_platform_session")
	)

	var first_r: Result = await controller._request_resume_ticket()
	if first_r.ok:
		controller.dispose()
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"第一次 resume_room 返回 room already ended 时应先失败"
		)
	if harness.resume_calls != 1:
		controller.dispose()
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"第一次调用后 resume_calls 错误: %d" % harness.resume_calls
		)
	if not NetContext.has_online_resume_context():
		controller.dispose()
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"in-game 重连第一次失败后不应立刻清理 resume 上下文"
		)
	if not NetContext.get_online_resume_terminal_reason().is_empty():
		controller.dispose()
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"第一次失败后不应写入 terminal_reason: %s" % NetContext.get_online_resume_terminal_reason()
		)

	var second_r: Result = await controller._request_resume_ticket()
	if not second_r.ok:
		controller.dispose()
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"第二次 resume_room 应恢复成功: %s" % second_r.error
		)
	if harness.resume_calls != 2:
		controller.dispose()
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"第二次调用后 resume_calls 错误: %d" % harness.resume_calls
		)
	var ticket_payload: Dictionary = Dictionary(second_r.value)
	if str(ticket_payload.get("room_code", "")).strip_edges() != "RTRYP1":
		controller.dispose()
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"第二次成功返回的 room_code 错误: %s" % str(ticket_payload.get("room_code", ""))
		)

	controller.dispose()
	host.queue_free()
	_restore(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_session_id,
		prev_user_id,
		prev_is_guest,
		prev_display_name
	)
	return Result.success()

static func _restore(
	prev_mode,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	prev_session_id: String,
	prev_user_id: String,
	prev_is_guest: bool,
	prev_display_name: String
) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.local_role = prev_local_role
	NetContext.server_url = prev_server_url
	NetContext.connect_token = prev_connect_token
	NetContext.room_state = prev_room_state.duplicate(true)
	NetContext.room_list = prev_room_list.duplicate(true)
	NetContext.player_profile = prev_player_profile.duplicate(true)
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	if NetContext.has_method("save_online_resume_state_to_disk"):
		NetContext.save_online_resume_state_to_disk()
	PlatformSession.session_id = prev_session_id
	PlatformSession.user_id = prev_user_id
	PlatformSession.is_guest = prev_is_guest
	PlatformSession.display_name = prev_display_name

static func _restore_and_fail(
	prev_mode,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	prev_session_id: String,
	prev_user_id: String,
	prev_is_guest: bool,
	prev_display_name: String,
	message: String
) -> Result:
	_restore(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_session_id,
		prev_user_id,
		prev_is_guest,
		prev_display_name
	)
	return Result.failure(message)

class _Harness:
	extends RefCounted

	var resume_calls: int = 0

	func get_engine():
		return null

	func apply_timeline() -> void:
		pass

	func update_ui() -> void:
		pass

	func reset_timeline() -> void:
		pass

	func show_confirm(_title: String, _body: String, _confirmed: Callable, _cancelled: Callable, _ok: String, _close: String) -> void:
		pass

	func goto_lobby() -> void:
		pass

	func show_loading(_message: String) -> void:
		pass

	func hide_loading() -> void:
		pass

	func ensure_platform_session() -> Result:
		return Result.success()

	func resume_room_request(room_code: String) -> Dictionary:
		resume_calls += 1
		var normalized_room_code := str(room_code).strip_edges().to_upper()
		if resume_calls == 1:
			return {
				"error": {
					"_http_status": 409,
					"detail": "room already ended",
				}
			}
		return {
			"ok": {
				"room_code": normalized_room_code,
				"ws_url": "ws://resume.example.test",
				"connect_token": "resume-token",
			}
		}

	func connect_to_server(_url: String) -> Result:
		return Result.success()

	func shutdown_net(_reset_context: bool = false) -> void:
		pass

	func request_resync(_force_snapshot: bool = false) -> String:
		return ""
