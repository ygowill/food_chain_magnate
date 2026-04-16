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
	var appended_entries: Array[Dictionary] = [
		{
			"type": 2,
			"message": "玩家1: 培训",
			"details": {"command_index": 1},
			"step_index": 1,
			"command_index": 1,
			"event_seq": 2,
		},
	]
	var append_ok := bool(panel.call("append_step_timeline", timeline2, appended_entries))
	await tree.process_frame

	if not append_ok:
		_cleanup(panel)
		return Result.failure("直接 append_step_timeline 应成功")
	if panel.call("get_last_step_timeline_update_mode") != "append":
		_cleanup(panel)
		return Result.failure("尾部追加场景应走 append")
	if not is_instance_valid(first_child) or first_child.get_parent() != log_container:
		_cleanup(panel)
		return Result.failure("append 后旧节点不应被整体替换出容器")
	if log_container.get_child_count() != old_child_count + 1:
		_cleanup(panel)
		return Result.failure("append 后 child_count 应仅增加 1 个 action header: before=%d after=%d" % [old_child_count, log_container.get_child_count()])
	if _count_message_occurrences(log_container, "玩家1: 培训") != 1:
		_cleanup(panel)
		return Result.failure("append 后主日志不应重复显示“玩家1: 培训”")
	if int(last_phase_header.end_step_index) != 1:
		_cleanup(panel)
		return Result.failure("append 后最后一个 phase header.end_step_index 应扩展到 1，实际=%d" % int(last_phase_header.end_step_index))

	var async_timeline1 := _build_linear_timeline(119)
	var async_entries1 := _build_linear_entries(119)
	panel.call("load_step_timeline", async_timeline1, async_entries1)
	var async_loaded := await _wait_until(func() -> bool:
		var current_entries = panel.call("get_step_timeline_entries")
		return current_entries is Array and current_entries.size() == async_entries1.size()
	, tree, 180)
	if not async_loaded:
		_cleanup(panel)
		return Result.failure("大时间线首次加载未在限定帧数内完成（后台线程 rebuild）")
	if panel.call("get_last_step_timeline_update_mode") != "rebuild":
		_cleanup(panel)
		return Result.failure("大时间线首次加载完成后应为 rebuild")

	var async_first_child = log_container.get_child(0)
	var async_old_child_count := log_container.get_child_count()
	var async_last_phase_header = _find_last_phase_header(log_container)
	if async_last_phase_header == null:
		_cleanup(panel)
		return Result.failure("大时间线加载后未找到 phase header")

	var async_timeline2 := _build_linear_timeline(120)
	var async_entries2 := _build_linear_entries(120)
	panel.call("load_step_timeline", async_timeline2, async_entries2)
	var async_appended := await _wait_until(func() -> bool:
		var current_entries = panel.call("get_step_timeline_entries")
		return current_entries is Array and current_entries.size() == async_entries2.size() and panel.call("get_last_step_timeline_update_mode") == "append"
	, tree, 180)
	if not async_appended:
		_cleanup(panel)
		return Result.failure("大时间线尾部追加未在限定帧数内完成（后台线程 append）")
	if not is_instance_valid(async_first_child) or async_first_child.get_parent() != log_container:
		_cleanup(panel)
		return Result.failure("后台 append 后旧节点不应被整体替换出容器")
	if log_container.get_child_count() <= async_old_child_count:
		_cleanup(panel)
		return Result.failure("后台 append 后 child_count 应增加: before=%d after=%d" % [async_old_child_count, log_container.get_child_count()])
	if int(async_last_phase_header.end_step_index) != 119:
		_cleanup(panel)
		return Result.failure("后台 append 后最后一个 phase header.end_step_index 应扩展到 119，实际=%d" % int(async_last_phase_header.end_step_index))

	_cleanup(panel)
	return Result.success()

static func _build_linear_timeline(step_count: int) -> Dictionary:
	var steps: Array[Dictionary] = []
	for idx in range(step_count):
		steps.append({
			"round": 1 + int(idx / 20),
			"phase": "Working",
			"kind": "command",
			"action_id": "recruit" if idx % 2 == 0 else "train",
			"action_display_name": "招募" if idx % 2 == 0 else "培训",
			"actor": 0,
			"anchor_command_index": idx,
		})
	return {
		"initial_state_dict": {
			"round_number": 0,
			"phase": "Setup",
		},
		"steps": steps,
	}

static func _build_linear_entries(step_count: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for idx in range(step_count):
		entries.append({
			"type": 2,
			"message": "玩家1: %s %d" % [("招募" if idx % 2 == 0 else "培训"), idx],
			"details": {"command_index": idx},
			"step_index": idx,
			"command_index": idx,
			"event_seq": idx + 1,
		})
	return entries

static func _wait_until(predicate: Callable, st: SceneTree, max_frames: int) -> bool:
	for _i in range(maxi(1, int(max_frames))):
		if predicate.is_valid() and bool(predicate.call()):
			return true
		await st.process_frame
	return predicate.is_valid() and bool(predicate.call())

static func _find_last_phase_header(log_container: Node):
	if log_container == null or not is_instance_valid(log_container):
		return null
	for i in range(log_container.get_child_count() - 1, -1, -1):
		var child = log_container.get_child(i)
		if child != null and is_instance_valid(child) and str(child.get_meta("_log_pool_kind", "")).strip_edges() == "phase_header":
			return child
	return null

static func _count_message_occurrences(log_container: Node, expected_message: String) -> int:
	if log_container == null or not is_instance_valid(log_container):
		return 0
	var target := str(expected_message).strip_edges()
	if target.is_empty():
		return 0
	var count := 0
	for i in range(log_container.get_child_count()):
		var child = log_container.get_child(i)
		if child == null or not is_instance_valid(child):
			continue
		var kind := str(child.get_meta("_log_pool_kind", "")).strip_edges()
		if kind == "action_group_header":
			if str(child.get("summary")).strip_edges() == target:
				count += 1
		elif kind == "event_item":
			var entry_val = child.get("entry_data")
			if entry_val is Dictionary and str(Dictionary(entry_val).get("message", "")).strip_edges() == target:
				count += 1
	return count

static func _cleanup(panel: Node) -> void:
	if panel != null and is_instance_valid(panel):
		panel.free()
