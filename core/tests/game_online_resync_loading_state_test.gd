class_name GameOnlineResyncLoadingStateTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if NetClient == null:
		return Result.failure("NetClient autoload missing")

	var prev_mode = NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_connected := bool(NetClient.get("_client_transport_connected"))

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop
	var host := Node.new()
	tree.root.add_child(host)

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 0
	NetContext.room_state = {"room_code": "LOAD"}
	NetClient.set("_client_transport_connected", true)

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
		Callable(harness, "show_loading"),
		Callable(harness, "hide_loading"),
		Callable(),
		Callable(),
		Callable(),
		Callable(harness, "request_resync")
	)

	var started := bool(controller.call("_begin_full_resync_request", "loading_state_test", true))
	if not started:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("full resync request 应成功进入同步状态")
	if harness.loading_messages.size() != 1:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("full resync request 应显示一次 loading，实际=%s" % str(harness.loading_messages))
	if str(harness.loading_messages[0]).find("同步") < 0:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("loading 文案应说明正在同步，实际=%s" % str(harness.loading_messages[0]))

	controller.call("_on_online_request_rejected", "mock_resync_1", "resync_failed", "boom")
	if harness.hide_loading_calls != 1:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("resync 请求被拒绝后应隐藏 loading，实际=%d" % int(harness.hide_loading_calls))
	if harness.update_ui_calls != 1:
		controller.dispose()
		host.queue_free()
		_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
		return Result.failure("resync 请求被拒绝后应刷新 UI，实际=%d" % int(harness.update_ui_calls))
	controller.dispose()
	host.queue_free()
	_restore(prev_mode, prev_local_player_id, prev_room_state, prev_connected)
	return Result.success({})

static func _restore(prev_mode, prev_local_player_id: int, prev_room_state: Dictionary, prev_connected: bool) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = int(prev_local_player_id)
	NetContext.room_state = prev_room_state.duplicate(true)
	NetClient.set("_client_transport_connected", bool(prev_connected))

class _Harness:
	extends RefCounted

	var loading_messages: Array[String] = []
	var hide_loading_calls: int = 0
	var update_ui_calls: int = 0
	var show_confirm_calls: int = 0
	var request_resync_calls: int = 0

	func update_ui() -> void:
		update_ui_calls += 1

	func show_confirm(_title: String, _body: String, _confirmed: Callable, _cancelled: Callable, _ok: String, _close: String) -> void:
		show_confirm_calls += 1

	func show_loading(message: String) -> void:
		loading_messages.append(str(message))

	func hide_loading() -> void:
		hide_loading_calls += 1

	func request_resync(_force_snapshot: bool = false) -> String:
		request_resync_calls += 1
		return "mock_resync_%d" % request_resync_calls
