# 晚餐结算动画：布局稳定等待与布局变化监控辅助
class_name DinnertimeAnimationLayoutHelpers
extends RefCounted

static func is_structure_index_ready_for_orders(map_canvas, orders: Array[Dictionary]) -> bool:
	if map_canvas == null or not is_instance_valid(map_canvas):
		return false
	var by_anchor_val = map_canvas.get("_structures_by_anchor")
	if not (by_anchor_val is Dictionary):
		return false
	var by_anchor: Dictionary = by_anchor_val
	if by_anchor.is_empty():
		return false

	var required: Dictionary = {}
	for order in orders:
		if bool(order.get("is_skipped", false)):
			continue
		var hid := str(order.get("house_id", "")).strip_edges()
		if not hid.is_empty():
			required[hid] = true
	if required.is_empty():
		return true

	var present: Dictionary = {}
	for k in by_anchor.keys():
		var info_val = by_anchor.get(k, null)
		if not (info_val is Dictionary):
			continue
		var info: Dictionary = info_val
		var hid2 := str(info.get("house_id", "")).strip_edges()
		if not hid2.is_empty():
			present[hid2] = true

	for hid3 in required.keys():
		if not present.has(hid3):
			return false

	return true

static func wait_until_layout_stable(
	scene: Node,
	map_canvas,
	is_playing_cb: Callable,
	is_started_preview_cb: Callable,
	get_cell_size_cb: Callable,
	get_world_origin_cb: Callable,
	is_index_ready_cb: Callable,
	on_ready_cb: Callable,
	required_stable_ticks: int = 4,
	max_wait_ticks: int = 40
) -> void:
	var last_cell_size := int(get_cell_size_cb.call()) if get_cell_size_cb.is_valid() else -1
	var last_origin := Vector2i.ZERO
	if get_world_origin_cb.is_valid():
		var ov = get_world_origin_cb.call()
		if ov is Vector2i:
			last_origin = ov
	var stable_ticks := 0
	var wait_ticks := 0

	while true:
		if not _call_bool(is_playing_cb) or _call_bool(is_started_preview_cb):
			return
		if scene == null or not is_instance_valid(scene) or map_canvas == null or not is_instance_valid(map_canvas):
			return

		var cs := int(get_cell_size_cb.call()) if get_cell_size_cb.is_valid() else -1
		var origin := Vector2i.ZERO
		if get_world_origin_cb.is_valid():
			var origin_val = get_world_origin_cb.call()
			if origin_val is Vector2i:
				origin = origin_val

		if cs != last_cell_size or origin != last_origin:
			last_cell_size = cs
			last_origin = origin
			stable_ticks = 0
		else:
			stable_ticks += 1

		wait_ticks += 1
		var index_ready := _call_bool(is_index_ready_cb)
		if (stable_ticks >= required_stable_ticks and index_ready) or wait_ticks >= max_wait_ticks:
			if on_ready_cb.is_valid():
				on_ready_cb.call()
			return

		var tree := scene.get_tree()
		if tree == null:
			return
		await tree.process_frame

static func monitor_layout_during_playback(
	scene: Node,
	map_canvas,
	is_monitor_running_cb: Callable,
	is_playing_cb: Callable,
	get_cell_size_cb: Callable,
	get_world_origin_cb: Callable,
	on_layout_changed_cb: Callable
) -> void:
	var last_cell_size := int(get_cell_size_cb.call()) if get_cell_size_cb.is_valid() else -1
	var last_origin := Vector2i.ZERO
	if get_world_origin_cb.is_valid():
		var ov = get_world_origin_cb.call()
		if ov is Vector2i:
			last_origin = ov

	while _call_bool(is_monitor_running_cb):
		if not _call_bool(is_playing_cb):
			return
		if map_canvas == null or not is_instance_valid(map_canvas):
			return

		var cs := int(get_cell_size_cb.call()) if get_cell_size_cb.is_valid() else -1
		var origin := Vector2i.ZERO
		if get_world_origin_cb.is_valid():
			var origin_val = get_world_origin_cb.call()
			if origin_val is Vector2i:
				origin = origin_val
		if cs != last_cell_size or origin != last_origin:
			last_cell_size = cs
			last_origin = origin
			if on_layout_changed_cb.is_valid():
				on_layout_changed_cb.call()

		if scene == null or not is_instance_valid(scene):
			return
		var tree := scene.get_tree()
		if tree == null:
			return
		await tree.process_frame

static func _call_bool(cb: Callable) -> bool:
	if not cb.is_valid():
		return false
	var v = cb.call()
	if v is bool:
		return bool(v)
	return false
