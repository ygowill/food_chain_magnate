# ActionPanel no-more-actions hint regression test
# 目标：当仅剩“确认结束(skip)”时，应显示“当前没有更多可执行动作”的说明卡，避免误以为 UI 出错。
class_name ActionPanelNoAvailableActionsHintTest
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

	await st.process_frame

	if not (panel is ActionPanel):
		await _cleanup_panel(panel, st)
		return Result.failure("实例不是 ActionPanel")

	var ap: ActionPanel = panel
	var modal_btn = panel.get_node_or_null("MarginContainer/VBoxContainer/ModalReopenButton")
	if not (modal_btn is Button):
		await _cleanup_panel(panel, st)
		return Result.failure("ModalReopenButton 节点缺失")
	if (modal_btn as Button).visible:
		await _cleanup_panel(panel, st)
		return Result.failure("ModalReopenButton 默认应隐藏")
	var title_label_main = panel.get_node_or_null("MarginContainer/VBoxContainer/TitleLabel")
	if title_label_main == null:
		await _cleanup_panel(panel, st)
		return Result.failure("TitleLabel 节点缺失")
	if (modal_btn as Button).get_index() != title_label_main.get_index() + 1:
		await _cleanup_panel(panel, st)
		return Result.failure("ModalReopenButton 应紧跟在可用动作标题下方")

	var emitted := {"id": "", "params": {}}
	ap.action_requested.connect(func(action_id: String, params: Dictionary) -> void:
		emitted["id"] = action_id
		emitted["params"] = params
	)
	ap.set_modal_reopen_action("__test_modal", "打开测试面板", true, "继续测试面板")
	if not (modal_btn as Button).visible:
		await _cleanup_panel(panel, st)
		return Result.failure("设置 reopen action 后 ModalReopenButton 应显示")
	if str((modal_btn as Button).text) != "打开测试面板":
		await _cleanup_panel(panel, st)
		return Result.failure("ModalReopenButton 文案错误: %s" % str((modal_btn as Button).text))
	(modal_btn as Button).emit_signal("pressed")
	if str(emitted.get("id", "")) != "__test_modal":
		await _cleanup_panel(panel, st)
		return Result.failure("ModalReopenButton 未发出 action_requested，实际: %s" % str(emitted.get("id", "")))
	ap.clear_modal_reopen_action()
	if (modal_btn as Button).visible:
		await _cleanup_panel(panel, st)
		return Result.failure("清除 reopen action 后 ModalReopenButton 应隐藏")

	var actions: Array[String] = ["skip"]
	ap.set_available_actions(actions)

	var guided_panel = panel.get_node_or_null("MarginContainer/VBoxContainer/GuidedActionPanel")
	if guided_panel == null or not is_instance_valid(guided_panel):
		await _cleanup_panel(panel, st)
		return Result.failure("GuidedActionPanel 节点缺失")
	if not (guided_panel as Control).visible:
		await _cleanup_panel(panel, st)
		return Result.failure("仅剩 skip 时应显示无动作说明卡")

	var title_label = panel.get_node_or_null("MarginContainer/VBoxContainer/GuidedActionPanel/MarginContainer/VBoxContainer/GuidedActionTitleLabel")
	if not (title_label is Label):
		await _cleanup_panel(panel, st)
		return Result.failure("GuidedActionTitleLabel 节点缺失")
	if str((title_label as Label).text).find("没有更多可执行动作") == -1:
		await _cleanup_panel(panel, st)
		return Result.failure("无动作说明卡标题不正确: %s" % str((title_label as Label).text))

	var open_btn = panel.get_node_or_null("MarginContainer/VBoxContainer/GuidedActionPanel/MarginContainer/VBoxContainer/OpenGuidedActionButton")
	if not (open_btn is Button):
		await _cleanup_panel(panel, st)
		return Result.failure("OpenGuidedActionButton 节点缺失")
	if (open_btn as Button).visible:
		await _cleanup_panel(panel, st)
		return Result.failure("无动作说明卡显示时不应再显示打开动作按钮")

	await _cleanup_panel(panel, st)
	return Result.success({})

static func _cleanup_panel(panel: Node, st: SceneTree) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	await st.process_frame
