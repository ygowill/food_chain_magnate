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

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop
	var host := Node.new()
	tree.root.add_child(host)

	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_pending_replay := str(Globals.pending_replay_file_path)

	NetContext.online_resume_state = {}
	Globals.pending_replay_file_path = ""
	var idle_harness := _Harness.new(host)
	var idle_controller = ControllerClass.new(
		host,
		Callable(idle_harness, "ensure_session"),
		Callable(idle_harness, "resume_room"),
		Callable(idle_harness, "connect_to_server"),
		Callable(idle_harness, "on_game_started"),
		Callable(idle_harness, "on_failure")
	)
	var idle_started = await idle_controller.attempt_startup_resume_if_needed()
	if idle_started:
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, "无恢复上下文时不应启动 Game 冷启动恢复")

	NetContext.set_online_resume_context("ROOM99", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var harness := _Harness.new(host)
	var controller = ControllerClass.new(
		host,
		Callable(harness, "ensure_session"),
		Callable(harness, "resume_room"),
		Callable(harness, "connect_to_server"),
		Callable(harness, "on_game_started"),
		Callable(harness, "on_failure")
	)

	var started = await controller.attempt_startup_resume_if_needed()
	if not started:
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, "有恢复上下文时应启动成功: %s" % harness.failure_message)
	if harness.ensure_calls != 1 or harness.resume_calls != 1 or harness.connect_calls != 1:
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, "冷启动恢复调用次数错误")
	if harness.game_started_calls != 1:
		host.queue_free()
		return _restore_and_fail(prev_resume_state, prev_pending_replay, "on_game_started 应被调用一次")

	host.queue_free()
	_restore(prev_resume_state, prev_pending_replay)
	return Result.success()

static func _restore(prev_resume_state: Dictionary, prev_pending_replay: String) -> void:
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	Globals.pending_replay_file_path = prev_pending_replay

static func _restore_and_fail(prev_resume_state: Dictionary, prev_pending_replay: String, message: String) -> Result:
	_restore(prev_resume_state, prev_pending_replay)
	return Result.failure(message)

class _Harness:
	extends RefCounted

	var host: Node = null
	var ensure_calls: int = 0
	var resume_calls: int = 0
	var connect_calls: int = 0
	var game_started_calls: int = 0
	var failure_message: String = ""

	func _init(p_host: Node) -> void:
		host = p_host

	func ensure_session() -> Result:
		ensure_calls += 1
		return Result.success()

	func resume_room(_room_code: String) -> Dictionary:
		resume_calls += 1
		return {
			"ok": {
				"ws_url": "ws://resume.example.test",
				"connect_token": "resume-token",
			}
		}

	func connect_to_server(_url: String) -> Result:
		connect_calls += 1
		NetClient.call_deferred("emit_signal", "game_started", {})
		NetClient.call_deferred("emit_signal", "resync_archive_received", {})
		return Result.success()

	func on_game_started(_payload: Dictionary) -> void:
		game_started_calls += 1

	func on_failure(message: String) -> void:
		failure_message = str(message)
