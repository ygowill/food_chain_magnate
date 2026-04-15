extends RefCounted

const GameLogPanelScene: PackedScene = preload("res://ui/components/game_log/game_log_panel.tscn")

static func run() -> Result:
	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if GameLogPanelScene == null:
		return Result.failure("GameLogPanelScene preload 失败")

	var panel = GameLogPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 GameLogPanel 失败")
	tree.root.add_child(panel)
	await tree.process_frame

	var button = panel.get_node_or_null("MarginContainer/VBoxContainer/TitleRow/TopRow/ReplayToggleButton")
	if button == null or not is_instance_valid(button):
		_cleanup(panel)
		return Result.failure("未找到 ReplayToggleButton")

	panel.call(
		"set_replay_toggle_availability",
		false,
		"完整历史加载中",
		"联机完整历史加载中，请稍后再试"
	)
	await tree.process_frame

	if not bool(button.disabled):
		_cleanup(panel)
		return Result.failure("完整历史未就绪时 ReplayToggleButton 应为 disabled")
	if str(button.text) != "完整历史加载中":
		_cleanup(panel)
		return Result.failure("完整历史未就绪文案错误: %s" % str(button.text))
	if str(button.tooltip_text).find("联机完整历史加载中") < 0:
		_cleanup(panel)
		return Result.failure("完整历史未就绪 tooltip 错误: %s" % str(button.tooltip_text))

	panel.call("set_replay_toggle_active", true)
	await tree.process_frame

	if bool(button.disabled):
		_cleanup(panel)
		return Result.failure("回放已激活时按钮应允许退出，不应保持 disabled")
	if str(button.text) != "退出回放":
		_cleanup(panel)
		return Result.failure("回放激活文案错误: %s" % str(button.text))

	panel.call("set_replay_toggle_active", false)
	panel.call("set_replay_toggle_availability", true, "进入回放", "")
	await tree.process_frame

	if bool(button.disabled):
		_cleanup(panel)
		return Result.failure("完整历史就绪后 ReplayToggleButton 不应 disabled")
	if str(button.text) != "进入回放":
		_cleanup(panel)
		return Result.failure("完整历史就绪后文案错误: %s" % str(button.text))
	if not str(button.tooltip_text).is_empty():
		_cleanup(panel)
		return Result.failure("完整历史就绪后 tooltip 应清空: %s" % str(button.tooltip_text))

	_cleanup(panel)
	return Result.success()

static func _cleanup(panel: Node) -> void:
	if panel != null and is_instance_valid(panel):
		panel.free()
