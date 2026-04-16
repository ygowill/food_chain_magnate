class_name GameLogTimelineRuntimeEventSourceTest
extends RefCounted

const GameLogPanelScene: PackedScene = preload("res://ui/components/game_log/game_log_panel.tscn")
const GameEventLogControllerClass = preload("res://ui/scenes/game/event_log/controller.gd")

static func run() -> Result:
	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if GameLogPanelScene == null:
		return Result.failure("GameLogPanelScene preload 失败")

	if EventBus != null:
		EventBus.clear_history()

	var panel = GameLogPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 GameLogPanel 失败")
	tree.root.add_child(panel)
	await tree.process_frame

	var controller = GameEventLogControllerClass.new()
	if controller == null or not is_instance_valid(controller):
		_cleanup(panel, null)
		return Result.failure("创建 GameEventLogController 失败")
	controller.setup(panel, false)

	var timeline1 := {
		"initial_state_dict": {
			"round_number": 0,
			"phase": "Setup",
		},
		"steps": [
			{
				"round": 1,
				"phase": "Working",
				"kind": "command",
				"action_id": "recruit",
				"action_display_name": "招聘",
				"actor": 0,
				"anchor_command_index": 0,
			},
		],
	}
	var entries1: Array[Dictionary] = [
		{
			"type": GameLogPanel.LogType.PLAYER,
			"message": "玩家1: 招聘 管理培训生",
			"details": {
				"command_index": 0,
				"step_index": 0,
				"event_type": EventBus.EventType.EMPLOYEE_RECRUITED,
			},
			"step_index": 0,
			"command_index": 0,
			"event_type": EventBus.EventType.EMPLOYEE_RECRUITED,
			"is_stage_event": false,
		},
	]
	panel.call("load_step_timeline", timeline1, entries1)
	await tree.process_frame

	EventBus.emit_event(EventBus.EventType.EMPLOYEE_TRAINED, {
		"player_id": 0,
		"from_employee": "management_trainee",
		"to_employee": "trainer",
		"steps": 1,
		"trainer_id": "trainer",
	})
	await tree.process_frame

	var timeline2 := {
		"initial_state_dict": {
			"round_number": 0,
			"phase": "Setup",
		},
		"steps": [
			{
				"round": 1,
				"phase": "Working",
				"kind": "command",
				"action_id": "recruit",
				"action_display_name": "招聘",
				"actor": 0,
				"anchor_command_index": 0,
			},
			{
				"round": 1,
				"phase": "Working",
				"kind": "command",
				"action_id": "train",
				"action_display_name": "培训",
				"actor": 0,
				"anchor_command_index": 1,
			},
		],
	}
	var entries2: Array[Dictionary] = [
		entries1[0].duplicate(true),
		{
			"type": GameLogPanel.LogType.PLAYER,
			"message": "玩家1: 培训 管理培训生 -> 培训讲师（1步，培训员：培训讲师）",
			"details": {
				"command_index": 1,
				"step_index": 1,
				"event_type": EventBus.EventType.EMPLOYEE_TRAINED,
			},
			"step_index": 1,
			"command_index": 1,
			"event_type": EventBus.EventType.EMPLOYEE_TRAINED,
			"is_stage_event": false,
		},
	]
	panel.call("load_step_timeline", timeline2, entries2)
	await tree.process_frame

	var trained_count := 0
	var entries_val = panel.call("get_entries")
	if entries_val is Array:
		for entry_val in entries_val:
			if not (entry_val is Dictionary):
				continue
			var entry: Dictionary = entry_val
			var event_type := str(entry.get("event_type", "")).strip_edges()
			if event_type.is_empty():
				var details_val = entry.get("details", {})
				if details_val is Dictionary:
					event_type = str(Dictionary(details_val).get("event_type", "")).strip_edges()
			if event_type == EventBus.EventType.EMPLOYEE_TRAINED:
				trained_count += 1

	_cleanup(panel, controller)
	if trained_count != 1:
		return Result.failure("step_timeline 模式下 employee_trained 应仅由 timeline 提供 1 份，实际=%d" % trained_count)
	return Result.success({})

static func _cleanup(panel: Node, controller) -> void:
	if controller != null and is_instance_valid(controller):
		if controller.has_method("dispose"):
			controller.dispose()
	if EventBus != null:
		EventBus.clear_history()
	if panel != null and is_instance_valid(panel):
		panel.free()
