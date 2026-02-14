# ActionPanel guided action placeholder regression test
# 目标：当动作 UI 被取消/关闭后，右侧 ActionPanel 不应为空白，应显示“当前操作”占位卡片并可一键重新打开。
class_name ActionPanelGuidedActionPlaceholderTest
extends RefCounted

const ActionPanelScene: PackedScene = preload("res://ui/components/action_panel/action_panel.tscn")

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ActionPanel）")

	if ActionPanelScene == null:
		return Result.failure("预加载 action_panel.tscn 失败（PackedScene 为空）")

	var panel = ActionPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 ActionPanel 失败（instantiate 为空）")
	host.add_child(panel)
	(panel as Control).visible = true

	# 等待一帧，确保 onready 节点已就绪
	await st.process_frame

	# 设置动作：应渲染 guided placeholder（当前操作=招聘）
	if panel is ActionPanel:
		var ap: ActionPanel = panel
		var actions: Array[String] = ["recruit", "skip"]
		ap.set_available_actions(actions)
	else:
		await _cleanup_panel(panel, st)
		return Result.failure("实例不是 ActionPanel（无法设置动作）")

	var guided_panel = panel.get_node_or_null("MarginContainer/VBoxContainer/GuidedActionPanel")
	if guided_panel == null or not is_instance_valid(guided_panel):
		await _cleanup_panel(panel, st)
		return Result.failure("GuidedActionPanel 节点缺失")
	if not (guided_panel as Control).visible:
		await _cleanup_panel(panel, st)
		return Result.failure("设置动作后 GuidedActionPanel 应可见（避免空白）")

	var open_btn = panel.get_node_or_null("MarginContainer/VBoxContainer/GuidedActionPanel/MarginContainer/VBoxContainer/OpenGuidedActionButton")
	if open_btn == null or not is_instance_valid(open_btn):
		await _cleanup_panel(panel, st)
		return Result.failure("OpenGuidedActionButton 节点缺失")

	# 点击“继续”应 emit action_requested("recruit")
	var requested: Array[Dictionary] = []
	if panel.has_signal("action_requested"):
		panel.action_requested.connect(func(aid: String, params: Dictionary) -> void:
			requested.append({"action_id": aid, "params": params})
		)
	open_btn.emit_signal("pressed")

	if requested.size() != 1 or str(requested[0].get("action_id", "")) != "recruit":
		await _cleanup_panel(panel, st)
		return Result.failure("点击继续应请求 recruit，实际=%s" % str(requested))

	# 当 ContextPanel 显示（代表具体动作 UI 打开）时，占位卡片应隐藏
	var ctx = panel.get_node_or_null("MarginContainer/VBoxContainer/ContextPanel")
	if ctx == null or not is_instance_valid(ctx):
		await _cleanup_panel(panel, st)
		return Result.failure("ContextPanel 节点缺失")
	(ctx as Control).visible = true
	await st.process_frame

	if (guided_panel as Control).visible:
		await _cleanup_panel(panel, st)
		return Result.failure("ContextPanel 可见时 GuidedActionPanel 应隐藏")

	await _cleanup_panel(panel, st)
	return Result.success({})

static func _cleanup_panel(panel: Node, st: SceneTree) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	await st.process_frame
