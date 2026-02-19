# 晚餐结算动画：路线计算与路线高亮辅助
class_name DinnertimeAnimationRouteHelpers
extends RefCounted

const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")

static func get_dinnertime_distance_script(cached_script):
	if cached_script != null:
		return cached_script
	var base_dir := ModulesBaseDirClass.get_base_dir()
	if base_dir.is_empty():
		return null
	var script_path := base_dir.path_join("base_rules/rules/phase/dinnertime/dinnertime_distance.gd")
	return load(script_path)

static func compute_route_path_for_order(game_state: GameState, order: Dictionary, dinnertime_distance_script) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if game_state == null:
		return out
	if bool(order.get("is_skipped", false)):
		return out
	if not (game_state.map is Dictionary):
		return out

	var house_id := str(order.get("house_id", "")).strip_edges()
	var restaurant_id := str(order.get("matched_restaurant", order.get("winner_restaurant_id", ""))).strip_edges()
	if house_id.is_empty() or restaurant_id.is_empty():
		return out

	var road_graph = RoadGraphCacheClass.get_road_graph(game_state)
	if road_graph == null:
		return out

	var map: Dictionary = game_state.map
	var grid_size_val = map.get("grid_size", null)
	if not (grid_size_val is Vector2i):
		return out
	var grid_size: Vector2i = grid_size_val

	var house := StructuresClass.get_house(game_state, house_id)
	var restaurant := StructuresClass.get_restaurant(game_state, restaurant_id)
	if house.is_empty() or restaurant.is_empty():
		return out
	if dinnertime_distance_script == null:
		return out

	var route_read: Result = dinnertime_distance_script.get_restaurant_to_house_distance(
		road_graph,
		game_state,
		grid_size,
		restaurant_id,
		restaurant,
		house_id,
		house
	)
	if not route_read.ok:
		return out
	if not (route_read.value is Dictionary):
		return out
	var route: Dictionary = route_read.value
	var path_val = route.get("path", null)
	if not (path_val is Array):
		return out

	for p in path_val:
		if p is Vector2i:
			out.append(p)

	return out

static func create_route_highlight(
	map_anim_layer: Control,
	path: Array[Vector2i],
	cell_size: float,
	origin: Vector2i,
	speed: float,
	alpha_min: float,
	alpha_max: float
) -> Dictionary:
	var nodes: Array[Control] = []
	if not is_instance_valid(map_anim_layer):
		return {"nodes": nodes, "tween": null}
	if path.is_empty():
		return {"nodes": nodes, "tween": null}

	for world_pos in path:
		var view_pos := world_pos - origin
		var cell := ColorRect.new()
		cell.color = Color(0.15, 1.0, 0.85, 0.35)
		cell.modulate.a = alpha_min
		cell.position = Vector2(float(view_pos.x) * cell_size, float(view_pos.y) * cell_size)
		cell.size = Vector2(cell_size, cell_size)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_anim_layer.add_child(cell)
		nodes.append(cell)

	if nodes.is_empty():
		return {"nodes": nodes, "tween": null}

	var tween := map_anim_layer.create_tween().set_loops()
	var flash_dur := maxf(0.08, 0.40 / maxf(speed, 0.01))
	tween.tween_method(func(v: float):
		for n in nodes:
			if n is ColorRect and is_instance_valid(n):
				(n as ColorRect).modulate.a = v
	, alpha_min, alpha_max, flash_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(v: float):
		for n in nodes:
			if n is ColorRect and is_instance_valid(n):
				(n as ColorRect).modulate.a = v
	, alpha_max, alpha_min, flash_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	return {"nodes": nodes, "tween": tween}

static func clear_route_highlight(route_nodes: Array[Control], route_tween: Tween) -> void:
	if is_instance_valid(route_tween):
		route_tween.kill()
	for n in route_nodes:
		if n is Control and is_instance_valid(n):
			n.queue_free()
