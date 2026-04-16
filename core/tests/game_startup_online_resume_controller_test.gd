# Game scene：冷启动后直接恢复到 Game 的启动控制器
class_name GameStartupOnlineResumeControllerTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/controllers/startup_online_resume_controller.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop
	var host := Node.new()
	tree.root.add_child(host)

	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_pending_replay := str(Globals.pending_replay_file_path)
	var prev_user_id := str(PlatformSession.user_id)

	NetContext.online_resume_state = {}
	Globals.pending_replay_file_path = ""
	var idle_harness := _Harness.new(host)
	var idle_controller = ControllerClass.new(
		host,
		Callable(idle_harness, "ensure_session"),
		Callable(idle_harness, "resume_room"),
		Callable(idle_harness, "connect_to_server"),
		Callable(idle_harness, "on_game_started"),
		Callable(idle_harness, "on_failure"),
		Callable(idle_harness, "on_status")
	)
	var idle_started = await idle_controller.attempt_startup_resume_if_needed()
	if idle_started:
		_dispose_controllers([idle_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "无恢复上下文时不应启动 Game 冷启动恢复")

	NetContext.set_online_resume_context("ROOM99", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var harness := _Harness.new(host)
	var controller = ControllerClass.new(
		host,
		Callable(harness, "ensure_session"),
		Callable(harness, "resume_room"),
		Callable(harness, "connect_to_server"),
		Callable(harness, "on_game_started"),
		Callable(harness, "on_failure"),
		Callable(harness, "on_status")
	)

	var started = await controller.attempt_startup_resume_if_needed()
	if not started:
		_dispose_controllers([idle_controller, controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "有恢复上下文时应启动成功: %s" % harness.failure_message)
	if harness.ensure_calls != 1 or harness.resume_calls != 1 or harness.connect_calls != 1:
		_dispose_controllers([idle_controller, controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "冷启动恢复调用次数错误")
	if harness.game_started_calls != 1:
		_dispose_controllers([idle_controller, controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "on_game_started 应被调用一次")
	if harness.statuses.is_empty():
		_dispose_controllers([idle_controller, controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "恢复过程中应产生状态文案")

	NetContext.set_online_resume_context("ROOM98", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var delta_harness := _Harness.new(host)
	delta_harness.use_delta_restore_signal = true
	var delta_controller = ControllerClass.new(
		host,
		Callable(delta_harness, "ensure_session"),
		Callable(delta_harness, "resume_room"),
		Callable(delta_harness, "connect_to_server"),
		Callable(delta_harness, "on_game_started"),
		Callable(delta_harness, "on_failure"),
		Callable(delta_harness, "on_status")
	)
	var delta_started = await delta_controller.attempt_startup_resume_if_needed()
	if not delta_started:
		_dispose_controllers([idle_controller, controller, delta_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "delta 恢复路径应判定为启动成功")
	if delta_harness.game_started_calls != 1:
		_dispose_controllers([idle_controller, controller, delta_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "delta 恢复路径应触发 on_game_started")

	NetContext.set_online_resume_context("ROOM97", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var fast_harness := _Harness.new(host)
	fast_harness.use_fast_start_signal = true
	var fast_controller = ControllerClass.new(
		host,
		Callable(fast_harness, "ensure_session"),
		Callable(fast_harness, "resume_room"),
		Callable(fast_harness, "connect_to_server"),
		Callable(fast_harness, "on_game_started"),
		Callable(fast_harness, "on_failure"),
		Callable(fast_harness, "on_status")
	)
	var fast_started = await fast_controller.attempt_startup_resume_if_needed()
	if not fast_started:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "fast-start 恢复路径应判定为启动成功")
	if fast_harness.game_started_calls != 1:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "fast-start 恢复路径应触发 on_game_started")

	NetContext.set_online_resume_context("ROOM96", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var full_history_harness := _Harness.new(host)
	full_history_harness.use_fast_start_signal = true
	full_history_harness.fast_start_payload = {
		"has_full_archive_payload": true,
		"full_history_source_mode": "archive_payload",
	}
	full_history_harness.use_full_history_ready_signal = true
	var full_history_controller = ControllerClass.new(
		host,
		Callable(full_history_harness, "ensure_session"),
		Callable(full_history_harness, "resume_room"),
		Callable(full_history_harness, "connect_to_server"),
		Callable(full_history_harness, "on_game_started"),
		Callable(full_history_harness, "on_failure"),
		Callable(full_history_harness, "on_status")
	)
	var full_history_started = await full_history_controller.attempt_startup_resume_if_needed()
	if not full_history_started:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "带完整历史的 fast-start 恢复路径应判定为启动成功")
	if full_history_harness.game_started_calls != 1:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "带完整历史的 fast-start 恢复路径应触发 on_game_started")
	if full_history_harness.statuses.find("已完成完整历史加载，正在进入对局...") < 0:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "带完整历史的 fast-start 恢复路径应等待 full history ready")

	NetContext.set_online_resume_context("ROOM101", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var retry_harness := _Harness.new(host)
	retry_harness.resume_failures_before_success = 1
	var retry_controller = ControllerClass.new(
		host,
		Callable(retry_harness, "ensure_session"),
		Callable(retry_harness, "resume_room"),
		Callable(retry_harness, "connect_to_server"),
		Callable(retry_harness, "on_game_started"),
		Callable(retry_harness, "on_failure"),
		Callable(retry_harness, "on_status")
	)
	var retry_started = await retry_controller.attempt_startup_resume_if_needed()
	if not retry_started:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller, retry_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "可重试失败后应最终恢复成功")
	if retry_harness.resume_calls != 2:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller, retry_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "冷启动可重试失败后应再次调用 resume_room")

	NetContext.set_online_resume_context("ROOM100", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	NetContext.online_resume_state["user_id"] = "u_expected"
	PlatformSession.user_id = "u_other"
	var mismatch_harness := _Harness.new(host)
	var mismatch_controller = ControllerClass.new(
		host,
		Callable(mismatch_harness, "ensure_session"),
		Callable(mismatch_harness, "resume_room"),
		Callable(mismatch_harness, "connect_to_server"),
		Callable(mismatch_harness, "on_game_started"),
		Callable(mismatch_harness, "on_failure"),
		Callable(mismatch_harness, "on_status")
	)
	var mismatch_started = await mismatch_controller.attempt_startup_resume_if_needed()
	if mismatch_started:
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller, retry_controller, mismatch_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "账号不匹配时不应继续启动恢复")
	if NetContext.has_online_resume_context():
		_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller, retry_controller, mismatch_controller])
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, prev_user_id, "账号不匹配时应清理 resume 上下文")

	_dispose_controllers([idle_controller, controller, delta_controller, fast_controller, full_history_controller, retry_controller, mismatch_controller])
	host.queue_free()
	_restore(prev_resume_state, prev_pending_replay, prev_user_id)
	return Result.success()

static func _restore(prev_resume_state: Dictionary, prev_pending_replay: String, prev_user_id: String) -> void:
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	if NetContext.has_method("save_online_resume_state_to_disk"):
		NetContext.save_online_resume_state_to_disk()
	Globals.pending_replay_file_path = prev_pending_replay
	PlatformSession.user_id = prev_user_id

static func _restore_and_fail(prev_resume_state: Dictionary, prev_pending_replay: String, prev_user_id: String, message: String) -> Result:
	_restore(prev_resume_state, prev_pending_replay, prev_user_id)
	return Result.failure(message)

static func _dispose_controllers(controllers: Array) -> void:
	for c in controllers:
		if c != null and is_instance_valid(c) and c.has_method("dispose"):
			c.dispose()

class _Harness:
	extends RefCounted

	var host: Node = null
	var ensure_calls: int = 0
	var resume_calls: int = 0
	var connect_calls: int = 0
	var game_started_calls: int = 0
	var failure_message: String = ""
	var resume_failures_before_success: int = 0
	var statuses: Array[String] = []
	var use_delta_restore_signal: bool = false
	var use_fast_start_signal: bool = false
	var fast_start_payload: Dictionary = {}
	var use_full_history_ready_signal: bool = false

	func _init(p_host: Node) -> void:
		host = p_host

	func ensure_session() -> Result:
		ensure_calls += 1
		return Result.success()

	func resume_room(_room_code: String) -> Dictionary:
		resume_calls += 1
		if resume_calls <= resume_failures_before_success:
			return {"error": {"detail": "request_failed", "_http_result_name": "cant_connect"}}
		return {
			"ok": {
				"ws_url": "ws://resume.example.test",
				"connect_token": "resume-token",
			}
		}

	func connect_to_server(_url: String) -> Result:
		connect_calls += 1
		NetClient.call_deferred("emit_signal", "game_started", {})
		if use_fast_start_signal:
			NetClient.call_deferred("emit_signal", "resume_fast_start_ready", fast_start_payload.duplicate(true))
			if use_full_history_ready_signal:
				NetClient.call_deferred("emit_signal", "resume_full_history_ready", {})
		elif use_delta_restore_signal:
			NetClient.call_deferred("emit_signal", "resync_delta_applied", {})
		else:
			NetClient.call_deferred("emit_signal", "resync_archive_received", {})
		return Result.success()

	func on_game_started(_payload: Dictionary) -> void:
		game_started_calls += 1

	func on_failure(message: String) -> void:
		failure_message = str(message)

	func on_status(message: String) -> void:
		statuses.append(str(message))
