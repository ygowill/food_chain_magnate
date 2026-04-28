# GameOverPanel：支持根据联机/单机动态切换返回按钮文案
class_name GameOverPanelReturnButtonTextTest
extends RefCounted

const GameOverPanelScene = preload("res://ui/components/game_over/game_over_panel.tscn")


static func run() -> Result:
	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")

	var panel = GameOverPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("GameOverPanel 实例化失败")
	tree.root.add_child(panel)
	await tree.process_frame

	if not panel.has_method("set_return_button_text"):
		_cleanup(panel)
		return Result.failure("GameOverPanel 缺少 set_return_button_text")
	panel.set_return_button_text("返回房间列表")

	var btn = panel.get_node_or_null("CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/ReturnButton")
	if btn == null or not (btn is Button):
		_cleanup(panel)
		return Result.failure("ReturnButton 缺失")
	if str((btn as Button).text) != "返回房间列表":
		_cleanup(panel)
		return Result.failure("ReturnButton 文案未更新，实际: %s" % str((btn as Button).text))

	var close_btn = panel.get_node_or_null("CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/CloseButton")
	if close_btn == null or not (close_btn is Button):
		_cleanup(panel)
		return Result.failure("CloseButton 缺失")
	if str((close_btn as Button).text) != "继续查看":
		_cleanup(panel)
		return Result.failure("CloseButton 文案错误，实际: %s" % str((close_btn as Button).text))
	if not panel.has_signal("closed_requested"):
		_cleanup(panel)
		return Result.failure("GameOverPanel 缺少 closed_requested 信号")
	var closed_events: Array[String] = []
	panel.closed_requested.connect(func() -> void:
		closed_events.append("closed")
	)
	(close_btn as Button).emit_signal("pressed")
	if closed_events.size() != 1:
		_cleanup(panel)
		return Result.failure("点击 CloseButton 应发出 closed_requested")

	_cleanup(panel)
	return Result.success({})


static func _cleanup(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
