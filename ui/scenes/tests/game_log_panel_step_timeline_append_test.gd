extends RefCounted

const GameLogPanelScene: PackedScene = preload("res://ui/components/game_log/game_log_panel.tscn")

class _TimelineStateApplySpy:
	extends Control

	var apply_calls: int = 0

	func apply_timeline_state(_cursor_index: int, _head_index: int) -> void:
		apply_calls += 1

class _PhaseHeaderTailSpy:
	extends Control

	var start_step_index: int = -1
	var end_step_index: int = -1

	func get_timeline_index() -> int:
		return int(start_step_index)

	func apply_timeline_state(_cursor_index: int, _head_index: int) -> void:
		pass

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
	var entry_count_label = panel.get_node_or_null("MarginContainer/VBoxContainer/BottomRow/EntryCountLabel")
	if entry_count_label == null or not is_instance_valid(entry_count_label):
		_cleanup(panel)
		return Result.failure("未找到 EntryCountLabel")

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
	if str(entry_count_label.text) != "显示 1 / 1":
		_cleanup(panel)
		return Result.failure("首次加载后可见条目数错误，实际=%s" % str(entry_count_label.text))

	var first_child = log_container.get_child(0)
	var old_child_count := log_container.get_child_count()
	var last_phase_header = _find_last_phase_header(log_container)
	if last_phase_header == null:
		_cleanup(panel)
		return Result.failure("首次加载后未找到 phase header")
	var sync_apply_spy := _TimelineStateApplySpy.new()
	sync_apply_spy.visible = false
	panel.add_child(sync_apply_spy)
	var stale_phase_header_spy := _PhaseHeaderTailSpy.new()
	stale_phase_header_spy.visible = false
	stale_phase_header_spy.set_meta("_log_pool_kind", "phase_header")
	panel.add_child(stale_phase_header_spy)
	var direct_log_items: Array = panel.get("_log_items")
	direct_log_items.append(sync_apply_spy)
	direct_log_items.append(stale_phase_header_spy)
	panel.set("_log_items", direct_log_items)

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
	var entries2: Array[Dictionary] = []
	entries2.append(entries1[0].duplicate(true))
	entries2.append(appended_entries[0].duplicate(true))
	if not bool(panel.call("_can_append_step_timeline", timeline2, entries2, false)):
		_cleanup(panel)
		return Result.failure("signature append 校验应接受正常尾部追加")
	var id_changed_entries: Array[Dictionary] = []
	id_changed_entries.append(entries1[0].duplicate(true))
	id_changed_entries[0]["id"] = 9999
	id_changed_entries.append(appended_entries[0].duplicate(true))
	if not bool(panel.call("_can_append_step_timeline", timeline2, id_changed_entries, false)):
		_cleanup(panel)
		return Result.failure("signature append 校验应忽略旧 entry id 差异")
	var bad_initial_timeline := timeline2.duplicate(true)
	bad_initial_timeline["initial_state_dict"] = {
		"round_number": 0,
		"phase": "Different",
	}
	if bool(panel.call("_can_append_step_timeline", bad_initial_timeline, entries2, false)):
		_cleanup(panel)
		return Result.failure("signature append 校验应拒绝 initial_state 不一致")
	var bad_tail_timeline := timeline2.duplicate(true)
	var bad_tail_steps: Array = bad_tail_timeline.get("steps", [])
	bad_tail_steps[0] = Dictionary(bad_tail_steps[0]).duplicate(true)
	bad_tail_steps[0]["action_id"] = "fire"
	bad_tail_timeline["steps"] = bad_tail_steps
	if bool(panel.call("_can_append_step_timeline", bad_tail_timeline, entries2, false)):
		_cleanup(panel)
		return Result.failure("signature append 校验应拒绝旧 tail step 不一致")
	var bad_boundary_entries: Array[Dictionary] = []
	bad_boundary_entries.append(entries1[0].duplicate(true))
	bad_boundary_entries[0]["message"] = "玩家1: 被篡改"
	bad_boundary_entries.append(appended_entries[0].duplicate(true))
	if bool(panel.call("_can_append_step_timeline", timeline2, bad_boundary_entries, false)):
		_cleanup(panel)
		return Result.failure("signature append 校验应拒绝旧 tail entry 不一致")
	var bad_sequence_entries: Array[Dictionary] = []
	bad_sequence_entries.append(entries1[0].duplicate(true))
	bad_sequence_entries.append(appended_entries[0].duplicate(true))
	bad_sequence_entries[1]["event_seq"] = 1
	if bool(panel.call("_can_append_step_timeline", timeline2, bad_sequence_entries, false)):
		_cleanup(panel)
		return Result.failure("signature append 校验应拒绝新增 entry sequence 未增长")
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
	var step_entries_after_append = panel.call("get_step_timeline_entries")
	if not (step_entries_after_append is Array) or step_entries_after_append.size() != 2:
		_cleanup(panel)
		return Result.failure("append 后 step timeline entries 应只增加新增项")
	var entries_after_append = panel.call("get_entries")
	if not (entries_after_append is Array) or entries_after_append.size() != 2:
		_cleanup(panel)
		return Result.failure("append 后 merged entries 应只增加新增项")
	if int(last_phase_header.end_step_index) != 1:
		_cleanup(panel)
		return Result.failure("append 后最后一个 phase header.end_step_index 应扩展到 1，实际=%d" % int(last_phase_header.end_step_index))
	if stale_phase_header_spy.end_step_index != -1:
		_cleanup(panel)
		return Result.failure("append 不应通过扫描 _log_items 命中尾部 stray phase header，实际=%d" % stale_phase_header_spy.end_step_index)
	var exact_index_after_append: Dictionary = panel.get("_timeline_exact_items_by_index")
	var step_one_items_val = exact_index_after_append.get(1, [])
	if not (step_one_items_val is Array) or (step_one_items_val as Array).is_empty():
		_cleanup(panel)
		return Result.failure("直接 append 新增 action header 应增量写入 timeline exact index")
	if str(entry_count_label.text) != "显示 2 / 2":
		_cleanup(panel)
		return Result.failure("append 后可见条目数错误，实际=%s" % str(entry_count_label.text))
	if sync_apply_spy.apply_calls != 0:
		_cleanup(panel)
		return Result.failure("直接 append 后不应全量刷新已有 log item timeline state，实际 apply_calls=%d" % sync_apply_spy.apply_calls)
	var direct_log_items_after_checks: Array = panel.get("_log_items")
	direct_log_items_after_checks.erase(sync_apply_spy)
	direct_log_items_after_checks.erase(stale_phase_header_spy)
	panel.set("_log_items", direct_log_items_after_checks)
	sync_apply_spy.queue_free()
	stale_phase_header_spy.queue_free()

	var load_append_result := await _run_load_step_timeline_append_case(tree)
	if not load_append_result.ok:
		_cleanup(panel)
		return load_append_result

	var async_timeline1 := _build_linear_timeline(119)
	var async_entries1 := _build_linear_entries(119)
	panel.call("load_step_timeline", async_timeline1, async_entries1)
	var async_loaded := await _wait_until(func() -> bool:
		var current_entries = panel.call("get_step_timeline_entries")
		return current_entries is Array \
			and current_entries.size() == async_entries1.size() \
			and not bool(panel.call("has_pending_descriptor_commit")) \
			and panel.call("get_last_step_timeline_update_mode") == "rebuild"
	, tree, 180)
	if not async_loaded:
		_cleanup(panel)
		return Result.failure("大时间线首次加载未在限定帧数内完成（后台线程 rebuild）")
	if str(entry_count_label.text) != "显示 119 / 119":
		_cleanup(panel)
		return Result.failure("大时间线首次加载后可见条目数错误，实际=%s" % str(entry_count_label.text))

	var async_first_child = log_container.get_child(0)
	var async_old_child_count := log_container.get_child_count()
	var async_last_phase_header = _find_last_phase_header(log_container)
	if async_last_phase_header == null:
		_cleanup(panel)
		return Result.failure("大时间线加载后未找到 phase header")
	var async_sync_apply_spy := _TimelineStateApplySpy.new()
	async_sync_apply_spy.visible = false
	panel.add_child(async_sync_apply_spy)
	var async_log_items: Array = panel.get("_log_items")
	async_log_items.append(async_sync_apply_spy)
	panel.set("_log_items", async_log_items)

	var async_timeline2 := _build_linear_timeline(120)
	var async_entries2 := _build_linear_entries(120)
	panel.call("load_step_timeline", async_timeline2, async_entries2)
	await tree.process_frame
	var late_small_delta_appended := await _wait_until(func() -> bool:
		var current_entries = panel.call("get_step_timeline_entries")
		return current_entries is Array \
			and current_entries.size() == async_entries2.size() \
			and not bool(panel.call("has_pending_descriptor_commit")) \
			and panel.call("get_last_step_timeline_update_mode") == "append"
	, tree, 180)
	if not late_small_delta_appended:
		_cleanup(panel)
		return Result.failure("大时间线小 delta 尾部追加应同步走 append")
	if bool(panel.call("has_pending_descriptor_commit")):
		_cleanup(panel)
		return Result.failure("大时间线小 delta append 不应启动 descriptor commit")
	if not is_instance_valid(async_first_child) or async_first_child.get_parent() != log_container:
		_cleanup(panel)
		return Result.failure("后期小 delta append 后旧节点不应被整体替换出容器")
	if log_container.get_child_count() != async_old_child_count + 1:
		_cleanup(panel)
		return Result.failure("后期小 delta append 后 child_count 应仅增加 1: before=%d after=%d" % [async_old_child_count, log_container.get_child_count()])
	if int(async_last_phase_header.end_step_index) != 119:
		_cleanup(panel)
		return Result.failure("后期小 delta append 后最后一个 phase header.end_step_index 应扩展到 119，实际=%d" % int(async_last_phase_header.end_step_index))
	if str(entry_count_label.text) != "显示 120 / 120":
		_cleanup(panel)
		return Result.failure("后期小 delta append 后可见条目数错误，实际=%s" % str(entry_count_label.text))
	if async_sync_apply_spy.apply_calls != 0:
		_cleanup(panel)
		return Result.failure("后期小 delta append 不应全量刷新已有 log item timeline state，实际 apply_calls=%d" % async_sync_apply_spy.apply_calls)

	_cleanup(panel)
	return Result.success()

static func _run_load_step_timeline_append_case(tree: SceneTree) -> Result:
	var panel = GameLogPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("load_step_timeline append 测试实例化 GameLogPanel 失败")
	tree.root.add_child(panel)
	await tree.process_frame

	var log_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/LogContainer")
	if log_container == null or not is_instance_valid(log_container):
		return await _finish_with_panel(Result.failure("load_step_timeline append 测试未找到 LogContainer"), panel, tree)

	var timeline1 := _build_linear_timeline(1)
	var entries1 := _build_linear_entries(1)
	panel.call("load_step_timeline", timeline1, entries1)
	await tree.process_frame
	if panel.call("get_last_step_timeline_update_mode") != "rebuild":
		return await _finish_with_panel(Result.failure("load_step_timeline 首次加载应为 rebuild"), panel, tree)
	if log_container.get_child_count() <= 0:
		return await _finish_with_panel(Result.failure("load_step_timeline 首次加载后日志 UI 为空"), panel, tree)

	var first_child = log_container.get_child(0)
	var old_child_count := log_container.get_child_count()
	var timeline2 := _build_linear_timeline(2)
	var entries2 := _build_linear_entries(2)
	panel.call("load_step_timeline", timeline2, entries2)
	await tree.process_frame

	if panel.call("get_last_step_timeline_update_mode") != "append":
		return await _finish_with_panel(Result.failure("load_step_timeline 尾部增长应走 append"), panel, tree)
	if not is_instance_valid(first_child) or first_child.get_parent() != log_container:
		return await _finish_with_panel(Result.failure("load_step_timeline append 后旧节点不应被替换出容器"), panel, tree)
	if log_container.get_child_count() <= old_child_count:
		return await _finish_with_panel(
			Result.failure("load_step_timeline append 后 child_count 应增加: before=%d after=%d" % [old_child_count, log_container.get_child_count()]),
			panel,
			tree
		)
	var loaded_entries = panel.call("get_step_timeline_entries")
	if not (loaded_entries is Array) or loaded_entries.size() != entries2.size():
		return await _finish_with_panel(Result.failure("load_step_timeline append 后 step entries 应为 2 条"), panel, tree)

	return await _finish_with_panel(Result.success({}), panel, tree)

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

static func _finish_with_panel(result: Result, panel: Node, tree: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await tree.process_frame
	return result
