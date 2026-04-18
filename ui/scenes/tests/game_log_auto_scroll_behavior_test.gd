extends RefCounted

const GameLogPanelScene: PackedScene = preload("res://ui/components/game_log/game_log_panel.tscn")

static func run() -> Result:
	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if GameLogPanelScene == null:
		return Result.failure("GameLogPanelScene preload 失败")

	var host := Control.new()
	host.custom_minimum_size = Vector2(480, 320)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)

	var panel = GameLogPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		host.queue_free()
		await tree.process_frame
		return Result.failure("实例化 GameLogPanel 失败")
	host.add_child(panel)
	await tree.process_frame

	var scroll_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer")
	if scroll_container == null or not is_instance_valid(scroll_container):
		return await _finish(Result.failure("未找到 ScrollContainer"), host, tree)

	panel.call("load_entries", _build_entries(80))
	var loaded_to_bottom := await _wait_until(func() -> bool:
		var max_value := int(scroll_container.get_v_scroll_bar().max_value)
		return max_value <= 0 or int(scroll_container.scroll_vertical) == max_value
	, tree, 20)
	if not loaded_to_bottom:
		var max_wait := int(scroll_container.get_v_scroll_bar().max_value)
		var scroll_wait := int(scroll_container.scroll_vertical)
		return await _finish(Result.failure("首次加载后应自动滚到底部: scroll=%d max=%d" % [scroll_wait, max_wait]), host, tree)

	var max_value := int(scroll_container.get_v_scroll_bar().max_value)
	var after_load := int(scroll_container.scroll_vertical)
	if max_value > 0 and after_load != max_value:
		return await _finish(Result.failure("首次加载后应自动滚到底部: scroll=%d max=%d" % [after_load, max_value]), host, tree)

	scroll_container.scroll_vertical = 0
	panel.call("_on_auto_scroll_toggled", true)
	var toggled_to_bottom := await _wait_until(func() -> bool:
		var max_value2 := int(scroll_container.get_v_scroll_bar().max_value)
		return max_value2 <= 0 or int(scroll_container.scroll_vertical) == max_value2
	, tree, 20)
	if not toggled_to_bottom:
		var max_wait2 := int(scroll_container.get_v_scroll_bar().max_value)
		var scroll_wait2 := int(scroll_container.scroll_vertical)
		return await _finish(Result.failure("重新开启自动滚动后应立即滚到底部: scroll=%d max=%d" % [scroll_wait2, max_wait2]), host, tree)

	var after_toggle := int(scroll_container.scroll_vertical)
	var max_after_toggle := int(scroll_container.get_v_scroll_bar().max_value)
	if max_after_toggle > 0 and after_toggle != max_after_toggle:
		return await _finish(Result.failure("重新开启自动滚动后应立即滚到底部: scroll=%d max=%d" % [after_toggle, max_after_toggle]), host, tree)

	panel.set("_timeline_head_index", 10)
	panel.set("_timeline_cursor_index", 5)
	scroll_container.scroll_vertical = 0
	panel.call("_request_scroll_to_bottom")
	await tree.process_frame
	await tree.process_frame

	if int(scroll_container.scroll_vertical) != 0:
		return await _finish(Result.failure("历史/回放态下不应强制自动滚动到底部"), host, tree)

	return await _finish(Result.success({}), host, tree)

static func _build_entries(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for idx in range(count):
		out.append({
			"id": idx,
			"type": 2,
			"message": "玩家1: 日志 %d" % idx,
			"timestamp": "2026-04-18T11:%02d:%02d" % [int(idx / 60), int(idx % 60)],
			"details": {"player_id": 0},
		})
	return out

static func _finish(result: Result, host: Node, tree: SceneTree) -> Result:
	if host != null and is_instance_valid(host):
		host.queue_free()
		await tree.process_frame
	return result

static func _wait_until(predicate: Callable, tree: SceneTree, max_frames: int = 12) -> bool:
	for _i in range(maxi(1, max_frames)):
		if predicate.call():
			return true
		await tree.process_frame
	return bool(predicate.call())
