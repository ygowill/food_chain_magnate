# ActionPanel：同一次 refresh 不应重复重建动作按钮；相同 refresh 也不应重复销毁/重建按钮树。
class_name ActionPanelRefreshSingleRebuildTest
extends RefCounted

const ActionPanelScene: PackedScene = preload("res://ui/components/action_panel/action_panel.tscn")
const GameEngineClass = preload("res://core/engine/game_engine.gd")

class _FakeExecutor:
	extends RefCounted

	var display_name: String
	var description: String
	var ui_hide_if_not_initiatable: bool = false

	func _init(title: String, desc: String) -> void:
		display_name = title
		description = desc

class _FakeActionRegistry:
	extends RefCounted

	var _executors: Dictionary = {}

	func _init() -> void:
		_executors = {
			"recruit": _FakeExecutor.new("招聘", "招聘"),
			"train": _FakeExecutor.new("培训", "培训"),
			"fire": _FakeExecutor.new("解雇", "解雇"),
			"skip": _FakeExecutor.new("确认结束", "确认结束"),
		}

	func get_available_actions(_state: GameState) -> Array[String]:
		return ["recruit", "train", "fire", "skip"]

	func get_player_initiatable_actions(_state: GameState, _player_id: int) -> Array[String]:
		return ["recruit", "train", "fire", "skip"]

	func get_mandatory_actions(_state: GameState) -> Array[String]:
		return []

	func get_executor(action_id: String):
		return _executors.get(str(action_id).strip_edges(), null)

class _ChildEnteredSpy:
	extends RefCounted

	var count: int = 0

	func _on_child_entered_tree(_node: Node) -> void:
		count += 1

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ActionPanel）")

	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345)
	if not init_r.ok:
		return await _finish(Result.failure("GameEngine.initialize 失败: %s" % init_r.error), null, engine, st)
	var state: GameState = engine.get_state()
	if state == null:
		return await _finish(Result.failure("state 为空"), null, engine, st)

	if ActionPanelScene == null:
		return await _finish(Result.failure("预加载 action_panel.tscn 失败"), null, engine, st)

	var panel = ActionPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return await _finish(Result.failure("实例化 ActionPanel 失败"), null, engine, st)
	host.add_child(panel)
	(panel as Control).visible = true
	await st.process_frame

	if not (panel is ActionPanel):
		return await _finish(Result.failure("实例不是 ActionPanel"), panel, engine, st)
	var action_panel: ActionPanel = panel

	var items_container = action_panel.get_node_or_null("MarginContainer/VBoxContainer/ItemsContainer")
	if items_container == null or not is_instance_valid(items_container):
		return await _finish(Result.failure("ItemsContainer 节点缺失"), panel, engine, st)

	var child_spy := _ChildEnteredSpy.new()
	items_container.child_entered_tree.connect(Callable(child_spy, "_on_child_entered_tree"))

	action_panel.set_action_registry(_FakeActionRegistry.new())
	child_spy.count = 0
	action_panel.set_display_context(state, 0)
	await st.process_frame

	var first_children := items_container.get_children()
	if first_children.size() != 2:
		return await _finish(Result.failure("首次 refresh 应只渲染 2 个普通动作按钮，实际=%d" % first_children.size()), panel, engine, st)
	if child_spy.count != 2:
		return await _finish(Result.failure("首次 refresh 不应重复重建按钮，预期 child_entered=2，实际=%d" % child_spy.count), panel, engine, st)

	var first_button_ids: Array[int] = []
	for child in first_children:
		if child is Node:
			first_button_ids.append(int((child as Node).get_instance_id()))

	child_spy.count = 0
	action_panel.refresh()
	await st.process_frame

	var second_children := items_container.get_children()
	if second_children.size() != 2:
		return await _finish(Result.failure("相同 refresh 后按钮数量应保持 2，实际=%d" % second_children.size()), panel, engine, st)
	if child_spy.count != 0:
		return await _finish(Result.failure("相同 refresh 不应重复 add_child，实际 child_entered=%d" % child_spy.count), panel, engine, st)

	var second_button_ids: Array[int] = []
	for child in second_children:
		if child is Node:
			second_button_ids.append(int((child as Node).get_instance_id()))
	if first_button_ids != second_button_ids:
		return await _finish(Result.failure("相同 refresh 不应重建按钮实例"), panel, engine, st)

	return await _finish(Result.success({}), panel, engine, st)

static func _finish(result: Result, panel: Node, engine: GameEngine, st: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await st.process_frame
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
