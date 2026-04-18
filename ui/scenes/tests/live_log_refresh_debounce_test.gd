class_name LiveLogRefreshDebounceTest
extends RefCounted

const GameTimelineControllerClass = preload("res://ui/scenes/game/timeline/controller.gd")

class _HostControl:
	extends Control

class _GameLogPanelSpy:
	extends Control

	var replay_toggle_calls: int = 0

	func get_replay_bar():
		return null

	func set_timeline_head_cursor(_head_index: int, _cursor_index: int, _update_visible_items: bool = true) -> void:
		pass

	func set_replay_toggle_availability(
		_available: bool,
		_inactive_text: String = "进入回放",
		_disabled_reason: String = ""
	) -> void:
		replay_toggle_calls += 1

class _EngineStub:
	extends RefCounted

	var command_history: Array = []
	var current_command_index: int = -1

	func _init(history_size: int = 0) -> void:
		for i in range(history_size):
			command_history.append({"index": i})
		current_command_index = maxi(-1, history_size - 1)

class _ControllerProbe:
	extends GameTimelineControllerClass

	var live_apply_calls: int = 0

	func apply_live_log_timeline_from_engine(_force_rebuild: bool = false) -> void:
		live_apply_calls += 1

static func run() -> Result:
	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree")
	var st: SceneTree = loop

	var host := _HostControl.new()
	st.root.add_child(host)
	await st.process_frame

	var panel := _GameLogPanelSpy.new()
	host.add_child(panel)
	await st.process_frame

	var engine := _EngineStub.new(4)
	var controller = _ControllerProbe.new(
		host,
		panel,
		null,
		func(): return engine,
		func(): return engine,
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable()
	)
	controller.initialize()

	controller.request_live_log_timeline_refresh()
	controller.request_live_log_timeline_refresh()
	controller.request_live_log_timeline_refresh()

	await st.create_timer(0.05).timeout
	if controller.live_apply_calls != 0:
		return await _finish(Result.failure("debounce 窗口内不应提前触发 live log refresh，实际=%d" % controller.live_apply_calls), controller, host, panel, st)

	await st.create_timer(0.12).timeout
	if controller.live_apply_calls != 1:
		return await _finish(Result.failure("多次 request_live_log_timeline_refresh 应被合并为 1 次，实际=%d" % controller.live_apply_calls), controller, host, panel, st)

	controller.request_live_log_timeline_refresh_deferred()
	await st.process_frame
	if controller.live_apply_calls != 2:
		return await _finish(Result.failure("deferred refresh 应在下一轮事件循环触发，实际=%d" % controller.live_apply_calls), controller, host, panel, st)

	panel.visible = false
	controller.request_live_log_timeline_refresh()
	await st.create_timer(0.15).timeout
	if controller.live_apply_calls != 2:
		return await _finish(Result.failure("日志隐藏时不应触发 live log refresh，实际=%d" % controller.live_apply_calls), controller, host, panel, st)

	return await _finish(Result.success({}), controller, host, panel, st)

static func _finish(result: Result, controller, host: Node, panel: Node, st: SceneTree) -> Result:
	if controller != null and is_instance_valid(controller) and controller.has_method("dispose"):
		controller.dispose()
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	if host != null and is_instance_valid(host):
		host.queue_free()
	await st.process_frame
	return result
