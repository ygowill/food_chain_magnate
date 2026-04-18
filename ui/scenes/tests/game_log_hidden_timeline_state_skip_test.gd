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

	return await _finish(Result.success({}), panel, st)

static func _finish(result: Result, panel: Node, st: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await st.process_frame
	return result
