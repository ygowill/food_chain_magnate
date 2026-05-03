class_name GameLogTimelineWindowingTest
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

	panel.set("_timeline_window_min_steps", 16)
	panel.set("_timeline_window_step_count", 8)
	panel.set("_virtual_descriptor_window_item_count", 10)
	panel.set("_virtual_descriptor_buffer_items", 2)
	panel.set("_virtual_item_estimated_height", 24.0)

	var scroll_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer")
	if scroll_container == null or not is_instance_valid(scroll_container):
		return await _finish(Result.failure("未找到 ScrollContainer"), panel, st)

	var log_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/LogContainer")
	if log_container == null or not is_instance_valid(log_container):
		return await _finish(Result.failure("未找到 LogContainer"), panel, st)

	var timeline := _build_linear_timeline(40)
	var entries := _build_linear_entries(40)
	panel.call("load_step_timeline", timeline, entries)
	await st.process_frame

	var window = panel.call("get_step_timeline_display_window")
	if not (window is Dictionary) or not bool(window.get("windowed", false)):
		return await _finish(Result.failure("大时间线应启用窗口化显示"), panel, st)
	if not bool(window.get("virtualized", false)):
		return await _finish(Result.failure("大时间线应启用虚拟化显示: %s" % str(window)), panel, st)
	if int(window.get("descriptor_count", 0)) <= int(window.get("display_item_count", 0)):
		return await _finish(Result.failure("虚拟化应保留全量 descriptor 且只渲染可见切片: %s" % str(window)), panel, st)
	if panel.call("get_last_step_timeline_update_mode") != "rebuild_virtual":
		return await _finish(Result.failure("首次大时间线加载应标记 rebuild_virtual，实际=%s" % str(panel.call("get_last_step_timeline_update_mode"))), panel, st)
	if int(panel.call("get_display_item_count")) > 10:
		return await _finish(Result.failure("虚拟化后 Control 数量应保持固定切片，实际=%d" % int(panel.call("get_display_item_count"))), panel, st)
	if log_container.get_child_count() > int(panel.call("get_display_item_count")) + 2:
		return await _finish(Result.failure("LogContainer 子节点数只能额外包含上下 spacer，实际=%d display=%d" % [log_container.get_child_count(), int(panel.call("get_display_item_count"))]), panel, st)
	var loaded_entries = panel.call("get_step_timeline_entries")
	if not (loaded_entries is Array) or loaded_entries.size() != entries.size():
		return await _finish(Result.failure("窗口化不应裁剪 timeline entries 状态"), panel, st)
	var first_items: Dictionary = panel.get("_timeline_first_item_by_index")
	if not first_items.has(39):
		return await _finish(Result.failure("初始虚拟窗口应定位到 live tail"), panel, st)

	panel.set("_auto_scroll", false)
	panel.set("_scroll_to_bottom_requested", false)
	scroll_container.scroll_vertical = 0
	await st.process_frame

	panel.call("_render_virtual_descriptor_window", 0, true)
	await st.process_frame
	window = panel.call("get_step_timeline_display_window")
	if int(window.get("descriptor_start_index", -1)) != 0:
		return await _finish(Result.failure("虚拟日志应能自由滚动到头部 descriptor，实际=%s" % str(window)), panel, st)
	if int(panel.call("get_display_item_count")) > 10 or log_container.get_child_count() > int(panel.call("get_display_item_count")) + 2:
		return await _finish(Result.failure("滚动到头部后 Control 数应保持固定，display=%d children=%d" % [int(panel.call("get_display_item_count")), log_container.get_child_count()]), panel, st)

	panel.call("_render_virtual_descriptor_window", 20, true)
	await st.process_frame
	window = panel.call("get_step_timeline_display_window")
	if int(window.get("descriptor_start_index", -1)) != 20:
		return await _finish(Result.failure("虚拟日志应能自由滚动到中段 descriptor，实际=%s" % str(window)), panel, st)
	if int(panel.call("get_display_item_count")) > 10 or log_container.get_child_count() > int(panel.call("get_display_item_count")) + 2:
		return await _finish(Result.failure("滚动到中段后 Control 数应保持固定，display=%d children=%d" % [int(panel.call("get_display_item_count")), log_container.get_child_count()]), panel, st)

	panel.set("_auto_scroll", true)
	panel.set("_scroll_to_bottom_requested", false)
	var timeline_appended := _build_linear_timeline(41)
	var entries_appended := _build_linear_entries(41)
	panel.call("load_step_timeline", timeline_appended, entries_appended)
	await st.process_frame
	window = panel.call("get_step_timeline_display_window")
	if panel.call("get_last_step_timeline_update_mode") != "append_virtual":
		return await _finish(Result.failure("大时间线尾部追加应走 append_virtual，实际=%s" % str(panel.call("get_last_step_timeline_update_mode"))), panel, st)
	if not bool(window.get("virtualized", false)):
		return await _finish(Result.failure("append 后应保持虚拟化显示: %s" % str(window)), panel, st)
	first_items = panel.get("_timeline_first_item_by_index")
	if not first_items.has(40):
		return await _finish(Result.failure("append_virtual 后 tail 窗口应包含新增 step，实际=%s" % str(window)), panel, st)
	if int(panel.call("get_display_item_count")) > 10:
		return await _finish(Result.failure("append_virtual 后 Control 数量应保持固定切片，实际=%d" % int(panel.call("get_display_item_count"))), panel, st)

	panel.call("set_timeline_head_cursor", 40, 5, true)
	await st.process_frame
	window = panel.call("get_step_timeline_display_window")
	if not bool(window.get("virtualized", false)):
		return await _finish(Result.failure("seek 后仍应保持虚拟化显示: %s" % str(window)), panel, st)
	first_items = panel.get("_timeline_first_item_by_index")
	if not first_items.has(5):
		return await _finish(Result.failure("seek 后窗口应包含 cursor step 的可见 item"), panel, st)
	if int(panel.call("get_display_item_count")) > 10:
		return await _finish(Result.failure("seek 窗口重建后 Control 数量应保持固定切片，实际=%d" % int(panel.call("get_display_item_count"))), panel, st)

	return await _finish(Result.success({}), panel, st)

static func _build_linear_timeline(step_count: int) -> Dictionary:
	var steps: Array[Dictionary] = []
	for idx in range(step_count):
		steps.append({
			"round": 1 + int(idx / 10),
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
		"_build_meta": {
			"processed_command_count": int(step_count),
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

static func _finish(result: Result, panel: Node, st: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await st.process_frame
	return result
