# 联机大厅：冷启动自动恢复控制器
class_name OnlineLobbyResumeControllerTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/online/online_lobby_resume_controller.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")

	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_pending_replay := str(Globals.pending_replay_file_path)
	var prev_user_id := str(PlatformSession.user_id)

	NetContext.online_resume_state = {}
	Globals.pending_replay_file_path = ""
	var harness_idle := _Harness.new()
	var controller_idle: RefCounted = _build_controller(harness_idle)
	await controller_idle.attempt_auto_resume_if_needed()
	if harness_idle.ensure_calls != 0 or harness_idle.resume_calls != 0 or harness_idle.connect_calls != 0:
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "无 resume 上下文时不应发起自动恢复")

	NetContext.set_online_resume_context("ROOM88", "player", "https://platform.example.test")
	var harness := _Harness.new()
	var controller: RefCounted = _build_controller(harness)
	await controller.attempt_auto_resume_if_needed()

	if harness.ensure_calls != 1:
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "ensure_session 调用次数错误: %d" % harness.ensure_calls)
	if harness.resume_calls != 1:
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "resume_room 调用次数错误: %d" % harness.resume_calls)
	if harness.connect_calls != 1:
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "connect_to_ws 调用次数错误: %d" % harness.connect_calls)
	if harness.last_room_code != "ROOM88":
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "resume_room room_code 错误: %s" % harness.last_room_code)
	if harness.last_ws_url != "ws://resume.example.test" or harness.last_connect_token != "resume-token":
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "connect_to_ws 参数错误")
	if not harness.platform_marked_ready:
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "成功恢复前应标记 platform ready")

	NetContext.set_online_resume_context("ROOM89", "player", "https://platform.example.test")
	NetContext.online_resume_state["user_id"] = "u_expected"
	PlatformSession.user_id = "u_other"
	var mismatch_harness := _Harness.new()
	var mismatch_controller: RefCounted = _build_controller(mismatch_harness)
	await mismatch_controller.attempt_auto_resume_if_needed()
	if NetContext.has_online_resume_context():
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "账号不匹配时应清理 resume 上下文")

	_restore(prev_resume_state, prev_pending_replay, prev_user_id)
	return Result.success()

static func _build_controller(harness: _Harness) -> RefCounted:
	var controller = ControllerClass.new()
	controller.setup(
		Callable(harness, "ensure_session"),
		Callable(harness, "resume_room"),
		Callable(harness, "connect_to_ws"),
		Callable(harness, "mark_platform_ready"),
		Callable(harness, "set_connect_status"),
		Callable(harness, "set_browse_status"),
		Callable(harness, "show_error"),
		Callable(harness, "hide_loading"),
		Callable(harness, "refresh_ui")
	)
	return controller

static func _restore(prev_resume_state: Dictionary, prev_pending_replay: String, prev_user_id: String) -> void:
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	Globals.pending_replay_file_path = prev_pending_replay
	PlatformSession.user_id = prev_user_id

static func _restore_and_fail(prev_resume_state: Dictionary, prev_pending_replay: String, prev_user_id: String, message: String) -> Result:
	_restore(prev_resume_state, prev_pending_replay, prev_user_id)
	return Result.failure(message)

class _Harness:
	extends RefCounted

	var ensure_calls: int = 0
	var resume_calls: int = 0
	var connect_calls: int = 0
	var platform_marked_ready: bool = false
	var last_room_code: String = ""
	var last_ws_url: String = ""
	var last_connect_token: String = ""

	func ensure_session() -> Result:
		ensure_calls += 1
		return Result.success()

	func resume_room(room_code: String) -> Dictionary:
		resume_calls += 1
		last_room_code = str(room_code)
		return {
			"ok": {
				"ws_url": "ws://resume.example.test",
				"connect_token": "resume-token",
			}
		}

	func connect_to_ws(ws_url: String, connect_token: String) -> void:
		connect_calls += 1
		last_ws_url = str(ws_url)
		last_connect_token = str(connect_token)

	func mark_platform_ready() -> void:
		platform_marked_ready = true

	func set_connect_status(_text: String) -> void:
		pass

	func set_browse_status(_text: String) -> void:
		pass

	func show_error(_title: String, _message: String) -> void:
		pass

	func hide_loading() -> void:
		pass

	func refresh_ui() -> void:
		pass
