# GameLogPanel：timeline state 更新应优先命中局部 index，而不是每次全量扫描所有日志项。
class_name GameLogTimelineLocalStateDeltaTest
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

class _TimelinePhaseHeaderSpy:
	extends Control

	var start_step_index: int = -1
	var end_step_index: int = -1
	var apply_calls: int = 0

	func _init(next_start_step_index: int, next_end_step_index: int) -> void:
		start_step_index = int(next_start_step_index)
		end_step_index = int(next_end_step_index)

	func get_timeline_index() -> int:
		return int(start_step_index)

	func apply_timeline_state(_cursor_index: int, _head_index: int) -> void:
		apply_calls += 1

class _TimelineRoundHeaderSpy:
	extends Control

	var start_step_index: int = -1
	var apply_calls: int = 0

	func _init(next_start_step_index: int) -> void:
		start_step_index = int(next_start_step_index)

	func get_timeline_index() -> int:
		return int(start_step_index)

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

	panel.set("_auto_scroll", false)

	var phase_a := _TimelinePhaseHeaderSpy.new(0, 4)
	phase_a.set_meta("_log_pool_kind", "phase_header")
	var phase_b := _TimelinePhaseHeaderSpy.new(5, 9)
	phase_b.set_meta("_log_pool_kind", "phase_header")
	var round_a := _TimelineRoundHeaderSpy.new(0)
	round_a.set_meta("_log_pool_kind", "round_header")

	var exact_items: Array[_TimelineExactItemSpy] = []
	var log_items: Array[Control] = [round_a, phase_a]
	for idx in range(5):
		var item := _TimelineExactItemSpy.new(idx)
		item.set_meta("_log_pool_kind", "event_item")
		exact_items.append(item)
		log_items.append(item)
	log_items.append(phase_b)
	for idx in range(5, 10):
		var item := _TimelineExactItemSpy.new(idx)
		item.set_meta("_log_pool_kind", "event_item")
		exact_items.append(item)
		log_items.append(item)

	panel.set("_log_items", log_items)
	panel.call("_rebuild_timeline_item_indexes")
	panel.set("_timeline_head_index", 5)
	panel.set("_timeline_cursor_index", 5)
	_reset_apply_counts(exact_items, [phase_a, phase_b, round_a])

	panel.call("set_timeline_head_cursor", 6, 6)

	if _sum_apply_calls(exact_items) != 2:
		return await _finish(Result.failure("live 推进一步只应更新 2 个 exact item，实际=%d" % _sum_apply_calls(exact_items)), panel, st)
	for idx in range(exact_items.size()):
		var expected_calls := 1 if idx == 5 or idx == 6 else 0
		if exact_items[idx].apply_calls != expected_calls:
			return await _finish(
				Result.failure("exact item %d apply_calls 错误：预期=%d 实际=%d" % [idx, expected_calls, exact_items[idx].apply_calls]),
				panel,
				st
			)
	if phase_a.apply_calls != 1 or phase_b.apply_calls != 1:
		return await _finish(Result.failure("phase header 应各更新 1 次，实际=[%d,%d]" % [phase_a.apply_calls, phase_b.apply_calls]), panel, st)
	if round_a.apply_calls != 1:
		return await _finish(Result.failure("round header 应更新 1 次，实际=%d" % round_a.apply_calls), panel, st)

	panel.set("_timeline_head_index", 9)
	panel.set("_timeline_cursor_index", 5)
	_reset_apply_counts(exact_items, [phase_a, phase_b, round_a])

	panel.call("set_timeline_head", 10)

	if _sum_apply_calls(exact_items) != 0:
		return await _finish(Result.failure("历史视图下仅 head 前进不应重刷 exact items，实际=%d" % _sum_apply_calls(exact_items)), panel, st)
	if phase_a.apply_calls != 0 or phase_b.apply_calls != 0 or round_a.apply_calls != 0:
		return await _finish(
			Result.failure(
				"历史视图下仅 head 前进不应重刷 header，实际 phase=[%d,%d] round=%d"
					% [phase_a.apply_calls, phase_b.apply_calls, round_a.apply_calls]
			),
			panel,
			st
		)

	return await _finish(Result.success({}), panel, st)

static func _reset_apply_counts(exact_items: Array[_TimelineExactItemSpy], header_items: Array) -> void:
	for item in exact_items:
		item.apply_calls = 0
	for item in header_items:
		if item != null:
			item.apply_calls = 0

static func _sum_apply_calls(items: Array[_TimelineExactItemSpy]) -> int:
	var total := 0
	for item in items:
		total += int(item.apply_calls)
	return total

static func _finish(result: Result, panel: Node, st: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await st.process_frame
	return result
