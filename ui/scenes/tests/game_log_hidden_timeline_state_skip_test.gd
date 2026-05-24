class_name GameLogHiddenTimelineStateSkipTest
extends RefCounted

const GameLogPanelScene: PackedScene = preload("res://ui/components/game_log/game_log_panel.tscn")

class _TimelineExactItemSpy:
	extends Control

	var timeline_index: int = -1
	var apply_calls: int = 0

	func _init(next_timeline_index: int) -> void:
		timeline_index = int(next_timeline_index)

	func get_timeline_index() -> int:
		return int(timeline_index)

	func apply_timeline_state(_cursor_index: int, _head_index: int) -> void:
		apply_calls += 1

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

	var exact_items: Array[_TimelineExactItemSpy] = []
	var log_items: Array[Control] = []
	for idx in range(4):
		var item := _TimelineExactItemSpy.new(idx)
		item.set_meta("_log_pool_kind", "event_item")
		exact_items.append(item)
		log_items.append(item)

	panel.set("_log_items", log_items)
	panel.call("_rebuild_timeline_item_indexes")
	panel.set("_timeline_head_index", 2)
	panel.set("_timeline_cursor_index", 2)
	panel.visible = false
	await st.process_frame

	panel.call("set_timeline_head_cursor", 3, 3, false)

	for item in exact_items:
		if item.apply_calls != 0:
			return await _finish(Result.failure("隐藏态 set_timeline_head_cursor 不应刷新 item，timeline_index=%d calls=%d" % [item.timeline_index, item.apply_calls]), panel, st)

	if int(panel.get("_timeline_head_index")) != 3 or int(panel.get("_timeline_cursor_index")) != 3:
		return await _finish(Result.failure("隐藏态仍应更新内部 cursor/head 状态"), panel, st)

	panel.visible = true
	await st.process_frame
	panel.call("set_timeline_head_cursor", 3, 3, true)

	for item in exact_items:
		if item.apply_calls != 0:
			return await _finish(Result.failure("相同 cursor/head 不应在可见后重复刷新 item"), panel, st)

	var hidden_load_result := await _run_hidden_load_step_timeline_case(st)
	if not hidden_load_result.ok:
		return await _finish(hidden_load_result, panel, st)

	return await _finish(Result.success({}), panel, st)

static func _run_hidden_load_step_timeline_case(st: SceneTree) -> Result:
	var panel = GameLogPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("隐藏态测试实例化 GameLogPanel 失败")
	st.root.add_child(panel)
	await st.process_frame

	var log_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/LogContainer")
	if log_container == null or not is_instance_valid(log_container):
		return await _finish(Result.failure("隐藏态测试未找到 LogContainer"), panel, st)

	panel.visible = false
	await st.process_frame

	var timeline := _build_linear_timeline(100)
	var entries := _build_linear_entries(100)
	panel.call("load_step_timeline", timeline, entries)
	await st.process_frame

	if log_container.get_child_count() != 0:
		return await _finish(
			Result.failure("隐藏态 load_step_timeline 不应构建 UI 子节点，实际=%d" % log_container.get_child_count()),
			panel,
			st
		)
	if bool(panel.call("has_pending_descriptor_commit")):
		return await _finish(Result.failure("隐藏态 load_step_timeline 不应启动 descriptor commit"), panel, st)
	if panel.call("get_last_step_timeline_update_mode") != "rebuild_hidden":
		return await _finish(
			Result.failure("隐藏态 load_step_timeline 应标记 rebuild_hidden，实际=%s" % str(panel.call("get_last_step_timeline_update_mode"))),
			panel,
			st
		)
	var loaded_entries = panel.call("get_step_timeline_entries")
	if not (loaded_entries is Array) or loaded_entries.size() != entries.size():
		return await _finish(Result.failure("隐藏态仍应提交 step timeline entries 状态"), panel, st)

	var hidden_append_timeline := _build_linear_timeline(101)
	var hidden_append_entries: Array[Dictionary] = [_build_linear_entries(101)[100]]
	if bool(panel.call("append_step_timeline", hidden_append_timeline, hidden_append_entries)):
		return await _finish(Result.failure("隐藏态 append_step_timeline 不应直接构建或追加 UI"), panel, st)
	if log_container.get_child_count() != 0:
		return await _finish(
			Result.failure("隐藏态 append_step_timeline 不应产生 UI 子节点，实际=%d" % log_container.get_child_count()),
			panel,
			st
		)

	var timeline2 := _build_linear_timeline(101)
	var entries2 := _build_linear_entries(101)
	panel.call("load_step_timeline", timeline2, entries2)
	await st.process_frame
	var loaded_entries2 = panel.call("get_step_timeline_entries")
	if not (loaded_entries2 is Array) or loaded_entries2.size() != entries2.size():
		return await _finish(Result.failure("隐藏态 fallback load_step_timeline 应提交最新 step timeline entries 状态"), panel, st)

	panel.visible = true
	await st.process_frame
	await st.process_frame

	if log_container.get_child_count() <= 0:
		return await _finish(Result.failure("显示后 ensure_display_ready 应补建日志 UI"), panel, st)

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
			"message": "玩家1: %s %d" % [("招募" if idx % 2 == 0 else "培训"), idx],
			"details": {"command_index": idx},
			"step_index": idx,
			"command_index": idx,
			"event_seq": idx + 1,
		})
	return entries

static func _finish(result: Result, panel: Node, st: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await st.process_frame
	return result
