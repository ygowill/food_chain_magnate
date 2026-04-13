class_name ActionPanelRestaurantDualActionsTest
extends RefCounted

const ActionPanelScene: PackedScene = preload("res://ui/components/action_panel/action_panel.tscn")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

class _ActionCapture:
	extends RefCounted

	var action_id: String = ""
	var params: Dictionary = {}

	func on_action_requested(requested_action_id: String, requested_params: Dictionary) -> void:
		action_id = str(requested_action_id).strip_edges()
		params = Dictionary(requested_params)

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
		return Result.failure("实例化 ActionPanel 失败")
	host.add_child(panel)
	(panel as Control).visible = true
	await st.process_frame

	if not (panel is ActionPanel):
		await _cleanup_panel(panel, st)
		return Result.failure("实例不是 ActionPanel")
	var action_panel: ActionPanel = panel

	var capture := _ActionCapture.new()
	action_panel.action_requested.connect(Callable(capture, "on_action_requested"))
	action_panel.set_available_actions(["move_restaurant", "place_restaurant", ActionIdsClass.SKIP])
	await st.process_frame

	var guided_action_id := action_panel.get_guided_action_id()
	if guided_action_id != "place_restaurant":
		await _cleanup_panel(panel, st)
		return Result.failure("餐厅双动作场景下应优先引导放置餐厅，实际: %s" % guided_action_id)

	if action_panel.items_container == null or not is_instance_valid(action_panel.items_container):
		await _cleanup_panel(panel, st)
		return Result.failure("ItemsContainer 节点缺失")
	if not action_panel.items_container.visible:
		await _cleanup_panel(panel, st)
		return Result.failure("存在次级餐厅动作时，ItemsContainer 应可见")

	var move_button = action_panel.items_container.get_node_or_null("ActionButton_move_restaurant")
	if not (move_button is Button):
		await _cleanup_panel(panel, st)
		return Result.failure("应为 move_restaurant 渲染切换按钮")
	if action_panel.items_container.get_node_or_null("ActionButton_place_restaurant") != null:
		await _cleanup_panel(panel, st)
		return Result.failure("guided action 不应在次级按钮列表中重复渲染")
	if (move_button as Button).disabled:
		await _cleanup_panel(panel, st)
		return Result.failure("move_restaurant 切换按钮不应被禁用")

	(move_button as Button).emit_signal("pressed")
	await st.process_frame

	if capture.action_id != "move_restaurant":
		await _cleanup_panel(panel, st)
		return Result.failure("点击次级动作按钮后应请求 move_restaurant，实际: %s" % capture.action_id)
	if not capture.params.is_empty():
		await _cleanup_panel(panel, st)
		return Result.failure("切换按钮不应附带额外参数，实际: %s" % str(capture.params))

	await _cleanup_panel(panel, st)
	return Result.success({})

static func _cleanup_panel(panel: Node, st: SceneTree) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	await st.process_frame
