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

	var log_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/LogContainer")
	if log_container == null or not is_instance_valid(log_container):
		_cleanup(panel)
		return Result.failure("未找到 LogContainer")

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
				"action_display_name": "招募",
				"actor": 0,
				"anchor_command_index": 0,
			},
		],
	}
	var entries1: Array[Dictionary] = [
		{
			"type": 2,
			"message": "玩家1: 招募",
			"details": {"command_index": 0},
			"step_index": 0,
			"command_index": 0,
			"event_seq": 1,
		},
	]
	panel.call("load_step_timeline", timeline1, entries1)
	await tree.process_frame

	if panel.call("get_last_step_timeline_update_mode") != "rebuild":
		_cleanup(panel)
		return Result.failure("首次 load_step_timeline 应为 rebuild")
	if log_container.get_child_count() <= 0:
		_cleanup(panel)
		return Result.failure("首次加载后日志 UI 为空")

	var first_child = log_container.get_child(0)
	var old_child_count := log_container.get_child_count()
	var last_phase_header = _find_last_phase_header(log_container)
	if last_phase_header == null:
		_cleanup(panel)
		return Result.failure("首次加载后未找到 phase header")

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
				"action_display_name": "招募",
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
		{
			"type": 2,
			"message": "玩家1: 招募",
			"details": {"command_index": 0},
			"step_index": 0,
			"command_index": 0,
			"event_seq": 1,
		},
		{
			"type": 2,
			"message": "玩家1: 培训",
			"details": {"command_index": 1},
			"step_index": 1,
			"command_index": 1,
			"event_seq": 2,
		},
	]
	panel.call("load_step_timeline", timeline2, entries2)
	await tree.process_frame

	if panel.call("get_last_step_timeline_update_mode") != "append":
		_cleanup(panel)
		return Result.failure("尾部追加场景应走 append")
	if not is_instance_valid(first_child) or first_child.get_parent() != log_container:
		_cleanup(panel)
		return Result.failure("append 后旧节点不应被整体替换出容器")
	if log_container.get_child_count() <= old_child_count:
		_cleanup(panel)
		return Result.failure("append 后 child_count 应增加: before=%d after=%d" % [old_child_count, log_container.get_child_count()])
	if int(last_phase_header.end_step_index) != 1:
		_cleanup(panel)
		return Result.failure("append 后最后一个 phase header.end_step_index 应扩展到 1，实际=%d" % int(last_phase_header.end_step_index))

	_cleanup(panel)
	return Result.success()

static func _find_last_phase_header(log_container: Node):
	if log_container == null or not is_instance_valid(log_container):
		return null
	for i in range(log_container.get_child_count() - 1, -1, -1):
		var child = log_container.get_child(i)
		if child != null and is_instance_valid(child) and str(child.get_meta("_log_pool_kind", "")).strip_edges() == "phase_header":
			return child
	return null

static func _cleanup(panel: Node) -> void:
	if panel != null and is_instance_valid(panel):
		panel.free()
