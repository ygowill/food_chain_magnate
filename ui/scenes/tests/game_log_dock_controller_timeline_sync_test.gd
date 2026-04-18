# Regression: when log panel is auto-opened (not via manual toggle), it should request
# a deferred timeline refresh without blocking the current UI update path.
class_name GameLogDockControllerTimelineSyncTest
extends RefCounted

const GameLogDockControllerClass = preload("res://ui/scenes/game/controllers/log_dock_controller.gd")

class _TimelineSpy:
	extends RefCounted
	var apply_count: int = 0
	var request_count: int = 0
	var request_deferred_count: int = 0
	func apply_live_log_timeline_from_engine() -> void:
		apply_count += 1
	func request_live_log_timeline_refresh() -> void:
		request_count += 1
	func request_live_log_timeline_refresh_deferred() -> void:
		request_deferred_count += 1

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载测试节点）")

	var right_dock_host := Control.new()
	right_dock_host.name = "RightDockHost"
	host.add_child(right_dock_host)

	var game_log_panel := Control.new()
	game_log_panel.name = "GameLogPanelStub"
	game_log_panel.visible = false
	host.add_child(game_log_panel)

	var timeline := _TimelineSpy.new()

	var noop := func() -> void:
		pass
	var dock_popup := func(panel: Control) -> void:
		if panel == null or not is_instance_valid(panel):
			return
		if panel.get_parent() != right_dock_host:
			if panel.get_parent() != null:
				panel.reparent(right_dock_host)
			else:
				right_dock_host.add_child(panel)
		panel.visible = true

	var controller = GameLogDockControllerClass.new(
		noop,
		noop,
		noop,
		noop,
		dock_popup,
		game_log_panel,
		right_dock_host,
		timeline
	)

	controller.show_game_log_panel_in_right_panel()
	if timeline.request_deferred_count != 1:
		if controller != null and controller.has_method("dispose"):
			controller.dispose()
		await _cleanup_nodes([game_log_panel, right_dock_host], st)
		return Result.failure("首次 show 应触发 1 次 deferred 时间线刷新请求，实际=%d" % timeline.request_deferred_count)
	if timeline.request_count != 0:
		if controller != null and controller.has_method("dispose"):
			controller.dispose()
		await _cleanup_nodes([game_log_panel, right_dock_host], st)
		return Result.failure("自动 show 不应走即时 request_live_log_timeline_refresh，实际=%d" % timeline.request_count)
	if timeline.apply_count != 0:
		if controller != null and controller.has_method("dispose"):
			controller.dispose()
		await _cleanup_nodes([game_log_panel, right_dock_host], st)
		return Result.failure("自动 show 不应同步执行时间线刷新，实际 apply=%d" % timeline.apply_count)
	if game_log_panel.get_parent() != right_dock_host or not game_log_panel.visible:
		if controller != null and controller.has_method("dispose"):
			controller.dispose()
		await _cleanup_nodes([game_log_panel, right_dock_host], st)
		return Result.failure("show 后日志面板未正确 dock 到右侧")

	# 已经显示在右侧时重复调用，不应重复触发刷新。
	controller.show_game_log_panel_in_right_panel()
	if timeline.request_deferred_count != 1:
		if controller != null and controller.has_method("dispose"):
			controller.dispose()
		await _cleanup_nodes([game_log_panel, right_dock_host], st)
		return Result.failure("重复 show 不应重复请求刷新，实际=%d" % timeline.request_deferred_count)

	if controller != null and controller.has_method("dispose"):
		controller.dispose()
	await _cleanup_nodes([game_log_panel, right_dock_host], st)
	return Result.success({})

static func _cleanup_nodes(nodes: Array, st: SceneTree) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	await st.process_frame
