class_name GameLogDescriptorCommitChunkingTest
extends RefCounted

const GameLogPanelScene: PackedScene = preload("res://ui/components/game_log/game_log_panel.tscn")

static func run() -> Result:
	var tree_val = Engine.get_main_loop()
	var st: SceneTree = tree_val if tree_val is SceneTree else null
	if st == null or st.root == null:
		return Result.failure("SceneTree.root 不可用")
	if GameLogPanelScene == null:
		return Result.failure("GameLogPanelScene preload 失败")

	var panel = GameLogPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 GameLogPanel 失败")
	st.root.add_child(panel)
	await st.process_frame
	panel.set("_BACKGROUND_TIMELINE_MIN_STEPS", 8)
	panel.set("_BACKGROUND_TIMELINE_MIN_ENTRIES", 8)

	var timeline := _build_linear_timeline(140)
	var entries := _build_linear_entries(140)
	panel.call("load_step_timeline", timeline, entries)
	var started_chunk_commit := await _wait_until(func() -> bool:
		return bool(panel.call("has_pending_descriptor_commit"))
	, st, 40)
	if not started_chunk_commit:
		return await _finish(Result.failure("大时间线首次加载应进入分帧 descriptor commit"), panel, st)

	var log_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/LogContainer")
	if log_container == null or not is_instance_valid(log_container):
		return await _finish(Result.failure("未找到 LogContainer"), panel, st)
	if log_container.get_child_count() <= 0:
		return await _finish(Result.failure("分帧 commit 首帧后应已有部分日志项挂载"), panel, st)

	var committed := await _wait_until(func() -> bool:
		return not bool(panel.call("has_pending_descriptor_commit"))
	, st, 240)
	if not committed:
		return await _finish(Result.failure("descriptor commit 未在限定帧数内完成"), panel, st)

	var timeline_entries_val = panel.call("get_step_timeline_entries")
	if not (timeline_entries_val is Array):
		return await _finish(Result.failure("get_step_timeline_entries 返回类型错误"), panel, st)
	var timeline_entries: Array = timeline_entries_val
	if timeline_entries.size() != entries.size():
		return await _finish(Result.failure("commit 完成后 timeline entries 数量错误: %d" % timeline_entries.size()), panel, st)

	return await _finish(Result.success({}), panel, st)

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
			"message": "玩家1: 日志 %d" % idx,
			"details": {"command_index": idx},
			"step_index": idx,
			"command_index": idx,
			"event_seq": idx + 1,
		})
	return entries

static func _wait_until(predicate: Callable, st: SceneTree, max_frames: int) -> bool:
	for _i in range(maxi(1, max_frames)):
		if predicate.call():
			return true
		await st.process_frame
	return bool(predicate.call())

static func _finish(result: Result, panel: Node, st: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await st.process_frame
	return result
