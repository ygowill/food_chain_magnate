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

	var harness := _Harness.new()
	var controller = ControllerClass.new(
		host,
		null,
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
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("完整 resync 应记录 request_id")
	if not controller.is_resync_in_progress():
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("发送 resync 后应进入同步中状态")
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
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("第二次 resync 也应记录 request_id")
	controller._on_online_request_rejected(second_request_id, "resync_rate_limited", "slow down")
	if controller.is_resync_in_progress():
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("resync_rate_limited 后不应继续卡在同步中")
	if harness.request_resync_calls != 2:
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("request_resync 调用次数错误: %d" % harness.request_resync_calls)
	if harness.update_ui_calls < 2:
		host.queue_free()
		_restore(prev_mode, prev_room_state, prev_connected)
		return Result.failure("拒绝 resync 后应刷新 UI: %d" % harness.update_ui_calls)

	host.queue_free()
	_restore(prev_mode, prev_room_state, prev_connected)
	return Result.success()

static func _restore(prev_mode, prev_room_state: Dictionary, prev_connected: bool) -> void:
	NetContext.mode = prev_mode
	NetContext.room_state = prev_room_state.duplicate(true)
	NetClient._client_transport_connected = prev_connected

class _Harness:
	extends RefCounted

	var request_resync_calls: int = 0
	var update_ui_calls: int = 0
	var show_confirm_calls: int = 0

	func request_resync() -> String:
		request_resync_calls += 1
		return "mock_resync_%d" % request_resync_calls

	func update_ui() -> void:
		update_ui_calls += 1

	func show_confirm(_title: String, _body: String, _confirmed: Callable, _cancelled: Callable, _ok: String, _close: String) -> void:
		show_confirm_calls += 1
