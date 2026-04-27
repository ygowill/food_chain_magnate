class_name GameOnlineResyncRequestRejectionTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if NetClient == null:
		return Result.failure("NetClient autoload missing")

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop
	var host := Node.new()
	tree.root.add_child(host)

	var prev_mode = NetContext.mode
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_connected := bool(NetClient._client_transport_connected)

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "ROOMRS",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetClient._client_transport_connected = true

	var apply_failure_harness := _Harness.new(_FailingEngine.new())
	var apply_failure_controller = ControllerClass.new(
		host,
		null,
		Callable(apply_failure_harness, "get_engine"),
		Callable(),
		Callable(),
		Callable(apply_failure_harness, "update_ui"),
		Callable(),
		Callable(apply_failure_harness, "show_confirm"),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(apply_failure_harness, "request_resync")
	)
	apply_failure_controller._on_online_command_applied({
		"index": 0,
		"action_id": "forced_apply_failure",
		"actor": 0,
		"params": {},
		"phase": "test",
		"sub_phase": "",
		"timestamp": 1,
		"metadata": {},
	}, "unused_hash")
	if apply_failure_harness.request_resync_calls != 1:
		apply_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("命令回放失败后应立刻请求 resync: %d" % apply_failure_harness.request_resync_calls)
	if not apply_failure_controller.is_resync_in_progress():
		apply_failure_controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("命令回放失败后应进入同步中状态")
	apply_failure_controller.dispose()

	var harness := _Harness.new()
	var controller = ControllerClass.new(
		host,
		null,
		Callable(),
		Callable(),
		Callable(),
		Callable(harness, "update_ui"),
		Callable(),
		Callable(harness, "show_confirm"),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(harness, "request_resync")
	)

	controller._request_online_resync("forced_mismatch")
	var first_request_id := str(controller._resync_request_id).strip_edges()
	if first_request_id.is_empty():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("完整 resync 应记录 request_id")
	if not controller.is_resync_in_progress():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("发送 resync 后应进入同步中状态")
	if harness.request_resync_force_flags.size() != 1 or bool(harness.request_resync_force_flags[0]):
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("普通 resync 不应携带 force_snapshot")
	controller._on_online_request_rejected(first_request_id, "resync_archive_too_large", "too large")
	if controller.is_resync_in_progress():
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("resync 被拒绝后不应继续卡在同步中")
	if not str(controller._resync_request_id).strip_edges().is_empty():
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("resync 被拒绝后应清理 request_id")

	controller._request_online_resync("forced_rate_limit")
	var second_request_id := str(controller._resync_request_id).strip_edges()
	if second_request_id.is_empty():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("第二次 resync 也应记录 request_id")
	controller._on_online_request_rejected(second_request_id, "resync_rate_limited", "slow down")
	if controller.is_resync_in_progress():
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("resync_rate_limited 后不应继续卡在同步中")
	if harness.request_resync_calls != 2:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("request_resync 调用次数错误: %d" % harness.request_resync_calls)
	if harness.update_ui_calls < 2:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("拒绝 resync 后应刷新 UI: %d" % harness.update_ui_calls)

	controller._resync_in_progress = true
	controller._on_online_resync_delta_failed("delta mismatch")
	if harness.request_resync_calls != 3:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("delta 失败后应立刻发起 snapshot fallback: %d" % harness.request_resync_calls)
	if harness.request_resync_force_flags.size() != 3 or not bool(harness.request_resync_force_flags[2]):
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("delta 失败后的 fallback 应携带 force_snapshot")
	if not controller.is_resync_in_progress():
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("delta 失败后重新发起 snapshot fallback 时应保持同步中状态")

	controller.dispose()
	host.queue_free()
	_restore(prev_mode, prev_room_state, prev_connected)
	return Result.success()

static func _restore(prev_mode, prev_room_state: Dictionary, prev_connected: bool) -> void:
	NetContext.mode = prev_mode
	NetContext.room_state = prev_room_state.duplicate(true)
	NetClient._client_transport_connected = prev_connected

class _Harness:
	extends RefCounted

	var _engine = null
	var request_resync_calls: int = 0
	var request_resync_force_flags: Array[bool] = []
	var update_ui_calls: int = 0
	var show_confirm_calls: int = 0

	func _init(engine = null) -> void:
		_engine = engine

	func get_engine():
		return _engine

	func request_resync(force_snapshot: bool = false) -> String:
		request_resync_calls += 1
		request_resync_force_flags.append(bool(force_snapshot))
		return "mock_resync_%d" % request_resync_calls

	func update_ui() -> void:
		update_ui_calls += 1

	func show_confirm(_title: String, _body: String, _confirmed: Callable, _cancelled: Callable, _ok: String, _close: String) -> void:
		show_confirm_calls += 1

class _FailingEngine:
	extends RefCounted

	var command_history: Array = []

	func execute_command(_cmd, _is_replay: bool = false) -> Result:
		return Result.failure("forced apply failure")
