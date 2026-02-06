# Game scene：Working/Drinks Procurement 控制器
# 负责：采购饮料（非跑腿伙计）的地图选点、路线规划与 overlay 展示。
class_name GamePanelWorkingDrinksProcurementController
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _scene = null
var _map_controller = null
var _overlay_controller = null

var production_panel = null

var _procure_selected_employee_type: String = ""
var _procure_selected_sources: Array[Vector2i] = []
var _procure_selected_tiles: Array[Vector2i] = []
var _procure_air_start_restaurant_id: String = "" # only for air procure (zeppelin): chosen by first tile selection
var _procure_selected_start_restaurant_id: String = "" # UI-selected starting restaurant (road/air)
var _procure_hover_start_restaurant_id: String = "" # map-hover preview (road only)
var _procure_hover_preview_active: bool = false
var _procure_restaurant_id: String = ""
var _procure_route: Array[Vector2i] = []
var _procure_error: String = ""

func _init(scene, map_controller, overlay_controller) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller

	if _map_controller != null and _map_controller.has_signal("procure_drinks_source_selected"):
		var sig := Signal(_map_controller, &"procure_drinks_source_selected")
		var cb := Callable(self, "_on_procure_drinks_source_selected")
		if not sig.is_connected(cb):
			sig.connect(cb)
	if _map_controller != null and _map_controller.has_signal("procure_drinks_start_restaurant_selected"):
		var sig2 := Signal(_map_controller, &"procure_drinks_start_restaurant_selected")
		var cb2 := Callable(self, "_on_procure_drinks_start_restaurant_selected")
		if not sig2.is_connected(cb2):
			sig2.connect(cb2)
	if _map_controller != null and _map_controller.has_signal("procure_drinks_start_restaurant_hovered"):
		var sig3 := Signal(_map_controller, &"procure_drinks_start_restaurant_hovered")
		var cb3 := Callable(self, "_on_procure_drinks_start_restaurant_hovered")
		if not sig3.is_connected(cb3):
			sig3.connect(cb3)

func set_production_panel(panel) -> void:
	production_panel = panel

func get_procure_restaurant_id() -> String:
	return _procure_restaurant_id

func get_procure_route() -> Array[Vector2i]:
	return _procure_route

func get_procure_selected_sources() -> Array[Vector2i]:
	return _procure_selected_sources

func hide_procurement_route_overlay() -> void:
	if _overlay_controller != null and _overlay_controller.has_method("hide_procurement_route_overlay"):
		_overlay_controller.call("hide_procurement_route_overlay")

func clear_procure_restaurant_choice_ui_and_overlays() -> void:
	_clear_procure_restaurant_choice_ui_and_overlays()

func reset_procurement_selection_state(clear_employee: bool = true) -> void:
	if clear_employee:
		_procure_selected_employee_type = ""
	_procure_selected_sources.clear()
	_procure_selected_tiles.clear()
	_procure_air_start_restaurant_id = ""
	_procure_selected_start_restaurant_id = ""
	_procure_hover_start_restaurant_id = ""
	_procure_hover_preview_active = false
	_procure_restaurant_id = ""
	_procure_route.clear()
	_procure_error = ""

func on_drinks_producer_changed(state: GameState, employee_type: String) -> void:
	if state == null:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_GET_DRINKS:
		reset_procurement_selection_state()
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
		_clear_procure_restaurant_choice_ui_and_overlays()
		return
	if employee_type.is_empty():
		reset_procurement_selection_state()
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
		_clear_procure_restaurant_choice_ui_and_overlays()
		return

	_procure_selected_employee_type = employee_type

	# 跑腿伙计：不需要选点/路线
	if employee_type == "errand_boy":
		reset_procurement_selection_state()
		hide_procurement_route_overlay()
		if _map_controller != null and _map_controller.has_method("clear_selection"):
			_map_controller.clear_selection()
		_clear_procure_restaurant_choice_ui_and_overlays()
		return

	reset_procurement_selection_state(false)
	if _map_controller != null and _map_controller.has_method("begin_selection"):
		_map_controller.begin_selection("procure_drinks", {"employee_type": employee_type})
	if _is_air_procure_employee_type(employee_type):
		if not _try_auto_select_air_start_tile(state):
			_show_air_procure_start_tiles_overlay(state)
	else:
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
	_sync_procure_restaurant_choice_ui_and_overlays(state)

func on_drinks_start_restaurant_changed(state: GameState, restaurant_id: String) -> void:
	if state == null:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_GET_DRINKS:
		return
	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return

	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		_procure_selected_start_restaurant_id = ""
		if _is_air_procure_employee_type(_procure_selected_employee_type):
			_procure_air_start_restaurant_id = ""
			_procure_selected_tiles.clear()
			hide_procurement_route_overlay()
			_show_air_procure_start_tiles_overlay(state)
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(0, false, "")
		else:
			hide_procurement_route_overlay()
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, "")
		_sync_procure_restaurant_choice_ui_and_overlays(state)
		return

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty() or not restaurant_ids.has(rid):
		return

	_procure_selected_start_restaurant_id = rid

	if _is_air_procure_employee_type(_procure_selected_employee_type):
		var restaurants_val = state.map.get("restaurants", null)
		if not (restaurants_val is Dictionary):
			return
		var restaurants: Dictionary = restaurants_val
		if not restaurants.has(rid) or not (restaurants[rid] is Dictionary):
			return
		var rest: Dictionary = restaurants[rid]
		var ep = rest.get("entrance_pos", null)
		if not (ep is Vector2i):
			return
		var entrance_pos: Vector2i = Vector2i(ep)

		var entrance_tile := Vector2i.ZERO
		var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, entrance_pos)
		if tile_read.ok:
			entrance_tile = tile_read.value
		else:
			entrance_tile = MapUtils.world_to_tile(entrance_pos).board_pos

		_procure_air_start_restaurant_id = rid
		_procure_selected_tiles.clear()
		_procure_selected_tiles.append(entrance_tile)
		_procure_selected_sources.clear()
		_recompute_procurement_plan(state)
		_sync_procure_restaurant_choice_ui_and_overlays(state)
		return

	_recompute_procurement_plan(state)
	_sync_procure_restaurant_choice_ui_and_overlays(state)

func on_drinks_clear_requested() -> void:
	var state: GameState = _scene.game_engine.get_state() if _scene != null and _scene.game_engine != null else null
	reset_procurement_selection_state(false)
	if _is_air_procure_employee_type(_procure_selected_employee_type):
		if state != null:
			if not _try_auto_select_air_start_tile(state):
				_show_air_procure_start_tiles_overlay(state)
			_sync_procure_restaurant_choice_ui_and_overlays(state)
			return
	hide_procurement_route_overlay()
	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
		production_panel.set_drinks_procurement_state(0, false, "")
	if state != null:
		_sync_procure_restaurant_choice_ui_and_overlays(state)

func on_drinks_undo_requested() -> void:
	var state: GameState = _scene.game_engine.get_state() if _scene != null and _scene.game_engine != null else null
	if state == null:
		return
	if _is_air_procure_employee_type(_procure_selected_employee_type):
		if _procure_selected_tiles.is_empty():
			return
		_procure_selected_tiles.pop_back()
		if _procure_selected_tiles.is_empty():
			_procure_air_start_restaurant_id = ""
			_procure_selected_start_restaurant_id = ""
	else:
		if _procure_selected_sources.is_empty():
			return
		_procure_selected_sources.pop_back()
	_recompute_procurement_plan(state)
	if _is_air_procure_employee_type(_procure_selected_employee_type):
		_sync_procure_restaurant_choice_ui_and_overlays(state)

func _on_procure_drinks_source_selected(world_pos: Vector2i) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(production_panel) or not production_panel.visible:
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_GET_DRINKS:
		return

	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return

	var emp_def: EmployeeDef = _get_procure_employee_def(_procure_selected_employee_type)
	var is_air := (emp_def != null and str(emp_def.range_type) == "air") or _procure_selected_employee_type == "zeppelin_pilot"
	if is_air:
		var tile_pos := Vector2i.ZERO
		var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, world_pos)
		if tile_read.ok:
			tile_pos = tile_read.value
		else:
			tile_pos = MapUtils.world_to_tile(world_pos).board_pos
		var tile_positions_set := TileRouteUtilsClass.get_tile_positions_set(state)
		var bounds := _get_air_tile_bounds(state, tile_positions_set)
		if not _is_air_tile_valid(tile_pos, tile_positions_set, bounds):
			_procure_error = "板块不可选"
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(_procure_selected_tiles.size(), false, _procure_error)
			return

		if _procure_selected_tiles.is_empty():
			var rest_pick := _resolve_air_procure_restaurant_and_entrance_from_start_tile(state, tile_pos)
			if not rest_pick.ok:
				_procure_error = rest_pick.error
				if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
					production_panel.set_drinks_procurement_state(0, false, _procure_error)
				_show_air_procure_start_tiles_overlay(state)
				return
			_procure_air_start_restaurant_id = str(rest_pick.value.get("restaurant_id", ""))
			_procure_selected_start_restaurant_id = _procure_air_start_restaurant_id
			_procure_selected_tiles.append(tile_pos)
			_recompute_procurement_plan(state)
			_sync_procure_restaurant_choice_ui_and_overlays(state)
			return

		if _procure_selected_tiles.has(tile_pos):
			_procure_error = "不允许重复板块"
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(_procure_selected_tiles.size(), false, _procure_error)
			return
		var last_tile: Vector2i = _procure_selected_tiles[_procure_selected_tiles.size() - 1]
		if not MapUtils.are_adjacent(last_tile, tile_pos):
			_procure_error = "必须选择相邻板块"
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(_procure_selected_tiles.size(), false, _procure_error)
			return

		var max_tiles := _get_air_procure_max_tiles(state, emp_def)
		if max_tiles > 0 and _procure_selected_tiles.size() + 1 > max_tiles:
			_procure_error = "超出飞艇范围: tiles=%d > %d" % [_procure_selected_tiles.size() + 1, max_tiles]
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(_procure_selected_tiles.size(), false, _procure_error)
			return

		_procure_selected_tiles.append(tile_pos)
		_recompute_procurement_plan(state)
		return

	if _procure_selected_sources.has(world_pos):
		return
	if emp_def == null:
		_procure_selected_sources.append(world_pos)
		_recompute_procurement_plan(state)
		return

	var validate_r := _validate_road_procure_sources_after_adding(state, emp_def, world_pos)
	if not validate_r.ok:
		_toast_procure_drinks_invalid_source(validate_r.error)
		return

	_procure_selected_sources.append(world_pos)
	_recompute_procurement_plan(state)

func _toast_procure_drinks_invalid_source(error_text: String) -> void:
	var msg := str(error_text).strip_edges()
	if msg.is_empty():
		msg = "该进货点不可选"
	else:
		msg = "该进货点不可选：%s" % msg
	if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
		_overlay_controller.call("show_toast", msg)

func _validate_road_procure_sources_after_adding(state: GameState, emp_def: EmployeeDef, new_source_world_pos: Vector2i) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if emp_def == null:
		return Result.failure("员工缺失")
	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return Result.failure("员工未选择")

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")
	restaurant_ids.sort()

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = restaurants_val

	var chosen_restaurant_id := ""
	var entrance_pos: Vector2i = Vector2i(-1, -1)

	var requested_id := str(_procure_selected_start_restaurant_id).strip_edges()
	if not requested_id.is_empty() and restaurant_ids.has(requested_id):
		if restaurants.has(requested_id) and (restaurants[requested_id] is Dictionary):
			var rest_req: Dictionary = restaurants[requested_id]
			var ep_req = rest_req.get("entrance_pos", null)
			if ep_req is Vector2i:
				chosen_restaurant_id = requested_id
				entrance_pos = Vector2i(ep_req)

	if chosen_restaurant_id.is_empty():
		for rid in restaurant_ids:
			if not restaurants.has(rid):
				continue
			var rest_val = restaurants[rid]
			if not (rest_val is Dictionary):
				continue
			var rest: Dictionary = rest_val
			var ep = rest.get("entrance_pos", null)
			if ep is Vector2i:
				chosen_restaurant_id = str(rid)
				entrance_pos = Vector2i(ep)
				break

	if chosen_restaurant_id.is_empty():
		return Result.failure("无法解析餐厅入口位置")

	var candidate_sources: Array[Vector2i] = []
	for p in _procure_selected_sources:
		candidate_sources.append(p)
	candidate_sources.append(new_source_world_pos)

	var route_r := _build_road_route(state, entrance_pos, candidate_sources)
	if not route_r.ok:
		return route_r
	var route: Array[Vector2i] = route_r.value

	var cmd := Command.create("procure_drinks", player_id, {
		"employee_type": _procure_selected_employee_type,
		"restaurant_id": chosen_restaurant_id,
		"route": DrinksProcurementClass.serialize_route(route),
		"selected_sources": DrinksProcurementClass.serialize_route(candidate_sources),
	})
	return DrinksProcurementClass.resolve_procurement_plan(state, cmd, restaurant_ids, emp_def)

func _on_procure_drinks_start_restaurant_selected(restaurant_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(production_panel) or not production_panel.visible:
		return
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	on_drinks_start_restaurant_changed(state, str(restaurant_id))

func _on_procure_drinks_start_restaurant_hovered(restaurant_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(production_panel) or not production_panel.visible:
		return
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_GET_DRINKS:
		return
	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return
	_set_procure_hover_start_restaurant_id(state, str(restaurant_id))

func _set_procure_hover_start_restaurant_id(state: GameState, restaurant_id: String) -> void:
	var next := str(restaurant_id).strip_edges()
	if _procure_hover_start_restaurant_id == next:
		return
	_procure_hover_start_restaurant_id = next
	_apply_procure_hover_preview(state, true)

func _set_procure_hover_preview_text(text: String) -> void:
	if not is_instance_valid(production_panel):
		return
	if production_panel.has_method("set_drinks_hover_preview_text"):
		production_panel.call("set_drinks_hover_preview_text", str(text))

func _sync_procure_hover_restaurant_anchor(state: GameState, restaurant_id: String) -> void:
	var canvas = _get_map_canvas()
	if canvas == null:
		return
	if state == null:
		return
	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		if canvas.has_method("clear_procure_drinks_hovered_restaurant_anchor"):
			canvas.call("clear_procure_drinks_hovered_restaurant_anchor")
		return

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return
	var restaurants: Dictionary = restaurants_val
	if not restaurants.has(rid) or not (restaurants[rid] is Dictionary):
		return
	var rest: Dictionary = restaurants[rid]
	var ep = rest.get("entrance_pos", null)
	if not (ep is Vector2i):
		return
	var anchor: Vector2i = Vector2i(ep)
	if canvas.has_method("set_procure_drinks_hovered_restaurant_anchor"):
		canvas.call("set_procure_drinks_hovered_restaurant_anchor", anchor)

func _clear_procure_hover_preview_ui(state: GameState, restore_selected_overlay: bool) -> void:
	_set_procure_hover_preview_text("")
	_sync_procure_hover_restaurant_anchor(state, "")
	if _procure_hover_preview_active and restore_selected_overlay:
		_procure_hover_preview_active = false
		_recompute_procurement_plan(state)
	else:
		_procure_hover_preview_active = false

func _apply_procure_hover_preview(state: GameState, restore_selected_overlay_when_clearing: bool) -> void:
	if state == null:
		return
	_sync_procure_hover_restaurant_anchor(state, _procure_hover_start_restaurant_id)

	var hover_id := str(_procure_hover_start_restaurant_id).strip_edges()
	var selected_id := str(_procure_selected_start_restaurant_id).strip_edges()
	if hover_id.is_empty():
		_clear_procure_hover_preview_ui(state, restore_selected_overlay_when_clearing)
		return
	if hover_id == selected_id:
		# Hover 到当前选中起点：不改变 overlay，只显示预览信息；若之前在预览其它餐厅，则先恢复选中路线。
		if _procure_hover_preview_active and restore_selected_overlay_when_clearing:
			_procure_hover_preview_active = false
			_recompute_procurement_plan(state)
		else:
			_procure_hover_preview_active = false
		_set_procure_hover_preview_text("预览：当前起点（点击餐厅或按 1-9 切换）")
		return

	# 仅对“道路采购”提供悬停预览：起点餐厅会改变自动路径。
	if _is_air_procure_employee_type(_procure_selected_employee_type):
		_set_procure_hover_preview_text("提示：点击餐厅可选择起点")
		_procure_hover_preview_active = false
		return
	if _procure_selected_sources.is_empty():
		_set_procure_hover_preview_text("预览：请先选择至少 1 个进货点")
		_procure_hover_preview_active = false
		return

	var emp_def: EmployeeDef = _get_procure_employee_def(_procure_selected_employee_type)
	if emp_def == null:
		var msg := "EmployeeRegistry 未初始化"
		if EmployeeRegistryClass.is_loaded():
			msg = "未知员工类型: %s" % _procure_selected_employee_type
		_set_procure_hover_preview_text("预览：%s" % msg)
		_procure_hover_preview_active = false
		return

	var preview_r := _build_road_procure_preview_plan(state, emp_def, hover_id, _procure_selected_sources)
	if not preview_r.ok:
		_set_procure_hover_preview_text("预览：%s" % preview_r.error)
		if _procure_hover_preview_active and restore_selected_overlay_when_clearing:
			_procure_hover_preview_active = false
			_recompute_procurement_plan(state)
		else:
			_procure_hover_preview_active = false
		return
	if not (preview_r.value is Dictionary):
		_set_procure_hover_preview_text("预览：路线解析失败")
		if _procure_hover_preview_active and restore_selected_overlay_when_clearing:
			_procure_hover_preview_active = false
			_recompute_procurement_plan(state)
		else:
			_procure_hover_preview_active = false
		return

	var plan: Dictionary = preview_r.value
	var entrance_pos := Vector2i(-1, -1)
	var ep_val = plan.get("entrance_pos", null)
	if ep_val is Vector2i:
		entrance_pos = Vector2i(ep_val)

	var route: Array[Vector2i] = []
	var route_val = plan.get("route", null)
	if route_val is Array:
		for p in (route_val as Array):
			if p is Vector2i:
				route.append(Vector2i(p))

	var picked_sources_pos: Array[Vector2i] = []
	var picked_val = plan.get("picked_sources", null)
	if picked_val is Array:
		for s_val in (picked_val as Array):
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			var wp = s.get("world_pos", null)
			if wp is Vector2i:
				picked_sources_pos.append(Vector2i(wp))

	var used := _count_road_boundary_crossings(route)
	var max_dist := _get_road_procure_max_distance(state, emp_def)
	var hover_idx := 0
	var restaurant_ids := StructuresClass.get_player_restaurants(state, state.get_current_player_id())
	restaurant_ids.sort()
	var find_idx := restaurant_ids.find(hover_id)
	if find_idx >= 0:
		hover_idx = find_idx + 1
	var start_label := ("餐厅 %d" % hover_idx) if hover_idx > 0 else hover_id
	if entrance_pos != Vector2i(-1, -1):
		start_label = "%s @ (%d,%d)" % [start_label, entrance_pos.x, entrance_pos.y]
	_set_procure_hover_preview_text("预览：%s，距离=%d/%d（点击餐厅或按 1-9 选择起点）" % [start_label, used, max_dist])

	if _overlay_controller != null and _overlay_controller.has_method("show_procurement_route_overlay"):
		_overlay_controller.call("show_procurement_route_overlay", entrance_pos, route, picked_sources_pos, {"preview": true})
		_procure_hover_preview_active = true
	else:
		_procure_hover_preview_active = false

func _build_road_procure_preview_plan(
	state: GameState,
	emp_def: EmployeeDef,
	restaurant_id: String,
	selected_sources: Array[Vector2i]
) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if emp_def == null:
		return Result.failure("员工缺失")
	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty() or not restaurant_ids.has(restaurant_id):
		return Result.failure("餐厅不存在或不属于当前玩家: %s" % restaurant_id)

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = restaurants_val
	if not restaurants.has(restaurant_id) or not (restaurants[restaurant_id] is Dictionary):
		return Result.failure("餐厅不存在: %s" % restaurant_id)
	var rest: Dictionary = restaurants[restaurant_id]
	var ep = rest.get("entrance_pos", null)
	if not (ep is Vector2i):
		return Result.failure("无法解析餐厅入口位置: %s" % restaurant_id)
	var entrance_pos: Vector2i = Vector2i(ep)

	var road_r := _build_road_route(state, entrance_pos, selected_sources)
	if not road_r.ok:
		return road_r
	var route: Array[Vector2i] = road_r.value

	var cmd := Command.create("procure_drinks", player_id, {
		"employee_type": _procure_selected_employee_type,
		"restaurant_id": restaurant_id,
		"route": DrinksProcurementClass.serialize_route(route),
		"selected_sources": DrinksProcurementClass.serialize_route(selected_sources)
	})
	return DrinksProcurementClass.resolve_procurement_plan(state, cmd, restaurant_ids, emp_def)

func _get_road_procure_max_distance(state: GameState, emp_def: EmployeeDef) -> int:
	if emp_def == null:
		return 0
	var max_dist := int(emp_def.range_value)
	if state == null:
		return max_dist
	var bonus_read := DrinksProcurementClass._get_distance_range_bonus_from_milestones(
		state, state.get_current_player_id(), str(emp_def.id)
	)
	if bonus_read.ok:
		max_dist += int(bonus_read.value)
	return max_dist

func _count_road_boundary_crossings(route: Array[Vector2i]) -> int:
	var count := 0
	for i in range(1, route.size()):
		if MapUtils.crosses_tile_boundary(route[i - 1], route[i]):
			count += 1
	return count

func _recompute_procurement_plan(state: GameState) -> void:
	_procure_error = ""
	_procure_restaurant_id = ""
	_procure_route.clear()

	if state == null:
		return
	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return
	var is_air := _is_air_procure_employee_type(_procure_selected_employee_type)
	var selected_count := _procure_selected_tiles.size() if is_air else _procure_selected_sources.size()

	if is_air and _procure_selected_tiles.is_empty():
		_procure_air_start_restaurant_id = ""
		_show_air_procure_start_tiles_overlay(state)
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
		return
	if (not is_air) and _procure_selected_sources.is_empty():
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
		return

	if not EmployeeRegistryClass.is_loaded():
		_procure_error = "EmployeeRegistry 未初始化"
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
		return

	var def_val = EmployeeRegistryClass.get_def(_procure_selected_employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		_procure_error = "未知员工类型: %s" % _procure_selected_employee_type
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
		return
	var emp_def: EmployeeDef = def_val

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		_procure_error = "你没有餐厅，无法采购饮料"
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
		return
	restaurant_ids.sort()

	var map_data: Dictionary = state.map
	var restaurants_val = map_data.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		_procure_error = "state.map.restaurants 缺失或类型错误"
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
		return
	var restaurants: Dictionary = restaurants_val

	var chosen_restaurant_id := ""
	var entrance_pos: Vector2i = Vector2i(-1, -1)
	if str(emp_def.range_type) == "air":
		var requested_id := str(_procure_selected_start_restaurant_id).strip_edges()
		if not requested_id.is_empty() and restaurant_ids.has(requested_id):
			if restaurants.has(requested_id) and (restaurants[requested_id] is Dictionary):
				var rest_req: Dictionary = restaurants[requested_id]
				var ep_req = rest_req.get("entrance_pos", null)
				if ep_req is Vector2i:
					chosen_restaurant_id = requested_id
					entrance_pos = Vector2i(ep_req)
					_procure_air_start_restaurant_id = chosen_restaurant_id

		var start_tile := _procure_selected_tiles[0] if not _procure_selected_tiles.is_empty() else Vector2i(-1, -1)
		if chosen_restaurant_id.is_empty() and not _procure_air_start_restaurant_id.is_empty():
			var rid := _procure_air_start_restaurant_id
			if restaurants.has(rid) and (restaurants[rid] is Dictionary):
				var rest: Dictionary = restaurants[rid]
				var ep = rest.get("entrance_pos", null)
				if ep is Vector2i:
					chosen_restaurant_id = rid
					entrance_pos = Vector2i(ep)
		if chosen_restaurant_id.is_empty() and start_tile != Vector2i(-1, -1):
			var pick := _resolve_air_procure_restaurant_and_entrance_from_start_tile(state, start_tile)
			if pick.ok:
				chosen_restaurant_id = str(pick.value.get("restaurant_id", ""))
				entrance_pos = pick.value.get("entrance_pos", Vector2i(-1, -1))
				_procure_air_start_restaurant_id = chosen_restaurant_id
				_procure_selected_start_restaurant_id = chosen_restaurant_id
	else:
		var requested_id2 := str(_procure_selected_start_restaurant_id).strip_edges()
		if not requested_id2.is_empty() and restaurant_ids.has(requested_id2):
			if restaurants.has(requested_id2) and (restaurants[requested_id2] is Dictionary):
				var rest_req2: Dictionary = restaurants[requested_id2]
				var ep_req2 = rest_req2.get("entrance_pos", null)
				if ep_req2 is Vector2i:
					chosen_restaurant_id = requested_id2
					entrance_pos = Vector2i(ep_req2)

		if chosen_restaurant_id.is_empty():
			for rest_id in restaurant_ids:
				if not restaurants.has(rest_id):
					continue
				var rest_val = restaurants[rest_id]
				if not (rest_val is Dictionary):
					continue
				var rest: Dictionary = rest_val
				var ep = rest.get("entrance_pos", null)
				if ep is Vector2i:
					chosen_restaurant_id = str(rest_id)
					entrance_pos = Vector2i(ep)
					break
			if not chosen_restaurant_id.is_empty():
				_procure_selected_start_restaurant_id = chosen_restaurant_id

	if chosen_restaurant_id.is_empty():
		_procure_error = "无法解析餐厅入口位置"
		hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
		return

	var route: Array[Vector2i] = []
	var selected_sources: Array[Vector2i] = []
	var picked_sources_pos: Array[Vector2i] = []
	if emp_def.range_type == "air":
		route = _procure_selected_tiles.duplicate()
		selected_sources = _collect_air_sources_in_tiles(state, route)
		_procure_route = route.duplicate()
		_procure_selected_sources = selected_sources.duplicate()
		picked_sources_pos = selected_sources.duplicate()
		_show_air_procure_overlay(state, emp_def, entrance_pos, picked_sources_pos)
		if selected_sources.is_empty():
			_procure_error = "所选板块没有饮料源"
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
			return
	else:
		var road_r := _build_road_route(state, entrance_pos, _procure_selected_sources)
		if not road_r.ok:
			_procure_error = road_r.error
			hide_procurement_route_overlay()
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
			return
		route = road_r.value
		selected_sources = _procure_selected_sources

	_procure_selected_sources = selected_sources.duplicate()
	var cmd := Command.create("procure_drinks", player_id, {
		"employee_type": _procure_selected_employee_type,
		"restaurant_id": chosen_restaurant_id,
		"route": DrinksProcurementClass.serialize_route(route),
		"selected_sources": DrinksProcurementClass.serialize_route(selected_sources)
	})

	var plan_r := DrinksProcurementClass.resolve_procurement_plan(state, cmd, restaurant_ids, emp_def)
	if not plan_r.ok:
		_procure_error = plan_r.error
		if not is_air:
			hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
		return
	if not (plan_r.value is Dictionary):
		_procure_error = "采购计划解析失败"
		if not is_air:
			hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(selected_count, false, _procure_error)
		return

	var plan: Dictionary = plan_r.value
	_procure_restaurant_id = str(plan.get("restaurant_id", ""))

	var route_val = plan.get("route", [])
	if route_val is Array:
		var out_route: Array[Vector2i] = []
		for p in route_val:
			if p is Vector2i:
				out_route.append(p)
		_procure_route = out_route

	picked_sources_pos = []
	var ps_val = plan.get("picked_sources", [])
	if ps_val is Array:
		for s_val in ps_val:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			var wp = s.get("world_pos", null)
			if wp is Vector2i:
				picked_sources_pos.append(Vector2i(wp))

	if _overlay_controller != null and _overlay_controller.has_method("show_procurement_route_overlay"):
		var overlay_route := _procure_route
		var overlay_entrance := entrance_pos
		var overlay_options: Dictionary = {}
		if emp_def.range_type == "air":
			var entrance_tile: Vector2i = MapUtils.world_to_tile(entrance_pos).board_pos
			var tile_size_cells := _get_air_tile_size_cells(state)
			overlay_route = _build_air_tile_display_route(_procure_route, tile_size_cells)
			overlay_entrance = _get_tile_center_world_pos(entrance_tile, tile_size_cells)
			overlay_options = _build_air_procure_overlay_options(state, emp_def, entrance_tile)
		_overlay_controller.call("show_procurement_route_overlay", overlay_entrance, overlay_route, picked_sources_pos, overlay_options)

	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
		production_panel.set_drinks_procurement_state(selected_count, true, "")

func _build_road_route(state: GameState, entrance_pos: Vector2i, sources: Array[Vector2i]) -> Result:
	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	var start_candidates_r := RangeUtilsClass.get_adjacent_road_cells(state, entrance_pos)
	if not start_candidates_r.ok:
		return start_candidates_r
	var start_candidates: Array[Vector2i] = start_candidates_r.value
	if start_candidates.is_empty():
		return Result.failure("餐厅入口未邻接道路")

	var route: Array[Vector2i] = []
	var current_pos: Vector2i = Vector2i.ZERO

	for src in sources:
		var end_candidates_r := RangeUtilsClass.get_adjacent_road_cells(state, src)
		if not end_candidates_r.ok:
			return end_candidates_r
		var end_candidates: Array[Vector2i] = end_candidates_r.value
		if end_candidates.is_empty():
			return Result.failure("饮料源未邻接道路: %s" % str(src))

		var best_path: Array[Vector2i] = []
		var best_dist := INF
		var best_steps := INF

		if route.is_empty():
			for from_cell in start_candidates:
				for to_cell in end_candidates:
					var sp_r = road_graph.find_shortest_path(from_cell, to_cell)
					if not sp_r.ok:
						continue
					var sp: Dictionary = sp_r.value
					var d: int = int(sp.get("distance", INF))
					var steps: int = int(sp.get("steps", INF))
					var path_val = sp.get("path", null)
					if not (path_val is Array):
						continue
					var path: Array = path_val
					if d < best_dist or (d == best_dist and steps < best_steps):
						best_dist = d
						best_steps = steps
						best_path = []
						for p in path:
							if p is Vector2i:
								best_path.append(p)

			if best_path.is_empty():
				return Result.failure("找不到到饮料源的道路路径: %s" % str(src))
			route = best_path
			current_pos = route[route.size() - 1]
			continue

		for to_cell2 in end_candidates:
			var sp_r2 = road_graph.find_shortest_path(current_pos, to_cell2)
			if not sp_r2.ok:
				continue
			var sp2: Dictionary = sp_r2.value
			var d2: int = int(sp2.get("distance", INF))
			var steps2: int = int(sp2.get("steps", INF))
			var path_val2 = sp2.get("path", null)
			if not (path_val2 is Array):
				continue
			var path2: Array = path_val2
			if d2 < best_dist or (d2 == best_dist and steps2 < best_steps):
				best_dist = d2
				best_steps = steps2
				best_path = []
				for p in path2:
					if p is Vector2i:
						best_path.append(p)

		if best_path.is_empty():
			return Result.failure("找不到到饮料源的道路路径: %s" % str(src))

		# 拼接（避免重复 current_pos）
		for j in range(1, best_path.size()):
			route.append(best_path[j])
		current_pos = route[route.size() - 1]

	return Result.success(route)

func _collect_air_sources_in_tiles(state: GameState, tiles: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null:
		return out
	var sources_val = state.map.get("drink_sources", null)
	if not (sources_val is Array):
		return out
	var tile_set := {}
	for t in tiles:
		tile_set[t] = true
	var sources: Array = sources_val
	for s_val in sources:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var wp = s.get("world_pos", null)
		if wp is Vector2i:
			var tile_pos: Vector2i = MapUtils.world_to_tile(Vector2i(wp)).board_pos
			if tile_set.has(tile_pos):
				out.append(Vector2i(wp))
	return out

func _build_air_tile_display_route(tiles: Array[Vector2i], tile_size_cells: int = -1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var size := tile_size_cells if tile_size_cells > 0 else int(MapUtils.TILE_SIZE)
	for t in tiles:
		out.append(_get_tile_center_world_pos(t, size))
	return out

func _get_tile_center_world_pos(tile_pos: Vector2i, tile_size_cells: int = -1) -> Vector2i:
	var size := tile_size_cells if tile_size_cells > 0 else int(MapUtils.TILE_SIZE)
	return tile_pos * size + Vector2i(size / 2, size / 2)

func _get_air_tile_size_cells(state: GameState) -> int:
	var size := int(MapUtils.TILE_SIZE)
	if state == null:
		return size
	var read := TileRouteUtilsClass.get_tile_size(state)
	if read.ok:
		size = int(read.value)
	return size

func _get_air_tile_bounds(state: GameState, tile_positions_set: Dictionary) -> Dictionary:
	var bounds: Dictionary = {}
	if state == null:
		return bounds
	if not tile_positions_set.is_empty():
		return bounds
	var read := TileRouteUtilsClass.get_tile_bounds(state)
	if read.ok and (read.value is Dictionary):
		bounds = read.value
	return bounds

func _is_air_tile_valid(tile_pos: Vector2i, tile_positions_set: Dictionary, bounds: Dictionary) -> bool:
	if not tile_positions_set.is_empty():
		return tile_positions_set.has(tile_pos)
	if bounds.is_empty():
		return true
	var min_tile = bounds.get("min", null)
	var max_tile = bounds.get("max", null)
	if min_tile is Vector2i and max_tile is Vector2i:
		return tile_pos.x >= min_tile.x and tile_pos.y >= min_tile.y and tile_pos.x <= max_tile.x and tile_pos.y <= max_tile.y
	return true

func _get_air_procure_legal_tiles(state: GameState, emp_def: EmployeeDef, entrance_tile: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null or emp_def == null:
		return out
	var max_tiles := _get_air_procure_max_tiles(state, emp_def)
	if max_tiles <= 0:
		return out

	var tile_positions_set := TileRouteUtilsClass.get_tile_positions_set(state)
	var bounds := _get_air_tile_bounds(state, tile_positions_set)

	if _procure_selected_tiles.is_empty():
		for start_tile in _get_air_procure_start_tiles(state):
			if _is_air_tile_valid(start_tile, tile_positions_set, bounds):
				out.append(start_tile)
		return out

	if _procure_selected_tiles.size() >= max_tiles:
		return out

	var last_tile: Vector2i = _procure_selected_tiles[_procure_selected_tiles.size() - 1]
	for offset_val in MapUtils.DIR_OFFSETS.values():
		if not (offset_val is Vector2i):
			continue
		var offset: Vector2i = offset_val
		var candidate: Vector2i = last_tile + offset
		if _procure_selected_tiles.has(candidate):
			continue
		if not _is_air_tile_valid(candidate, tile_positions_set, bounds):
			continue
		out.append(candidate)

	return out

func _build_air_procure_overlay_options(state: GameState, emp_def: EmployeeDef, entrance_tile: Vector2i) -> Dictionary:
	return {
		"tile_mode": true,
		"tile_size_cells": _get_air_tile_size_cells(state),
		"selected_tiles": _procure_selected_tiles.duplicate(),
		"legal_tiles": _get_air_procure_legal_tiles(state, emp_def, entrance_tile)
	}

func _show_air_procure_start_tiles_overlay(state: GameState) -> void:
	if state == null:
		return
	if not _is_air_procure_employee_type(_procure_selected_employee_type):
		return
	if _overlay_controller == null or not _overlay_controller.has_method("show_procurement_route_overlay"):
		return

	var start_tiles: Array[Vector2i] = _get_air_procure_start_tiles(state)
	if start_tiles.is_empty():
		hide_procurement_route_overlay()
		return

	var tile_size_cells := _get_air_tile_size_cells(state)
	var empty_tiles: Array[Vector2i] = []
	var empty_route: Array[Vector2i] = []
	var empty_sources: Array[Vector2i] = []
	var opts := {
		"tile_mode": true,
		"tile_size_cells": tile_size_cells,
		"selected_tiles": empty_tiles,
		"legal_tiles": start_tiles
	}
	_overlay_controller.call("show_procurement_route_overlay", Vector2i(-1, -1), empty_route, empty_sources, opts)

func _show_air_procure_overlay(state: GameState, emp_def: EmployeeDef, entrance_pos: Vector2i, picked_sources: Array[Vector2i]) -> void:
	if _overlay_controller == null or not _overlay_controller.has_method("show_procurement_route_overlay"):
		return
	var entrance_tile: Vector2i = MapUtils.world_to_tile(entrance_pos).board_pos
	var tile_size_cells := _get_air_tile_size_cells(state)
	var overlay_route := _build_air_tile_display_route(_procure_selected_tiles, tile_size_cells)
	var overlay_entrance := _get_tile_center_world_pos(entrance_tile, tile_size_cells)
	var overlay_options := _build_air_procure_overlay_options(state, emp_def, entrance_tile)
	_overlay_controller.call("show_procurement_route_overlay", overlay_entrance, overlay_route, picked_sources, overlay_options)

func _try_auto_select_air_start_tile(state: GameState) -> bool:
	if state == null:
		return false
	var emp_def: EmployeeDef = _get_procure_employee_def(_procure_selected_employee_type)
	if emp_def == null or str(emp_def.range_type) != "air":
		return false

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.size() != 1:
		return false
	var pick_id: String = restaurant_ids[0]

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return false
	var restaurants: Dictionary = restaurants_val
	if not restaurants.has(pick_id) or not (restaurants[pick_id] is Dictionary):
		return false
	var rest: Dictionary = restaurants[pick_id]
	var ep = rest.get("entrance_pos", null)
	if not (ep is Vector2i):
		return false
	var entrance_pos: Vector2i = Vector2i(ep)

	var entrance_tile := Vector2i.ZERO
	var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, entrance_pos)
	if tile_read.ok:
		entrance_tile = tile_read.value
	else:
		entrance_tile = MapUtils.world_to_tile(entrance_pos).board_pos

	_procure_air_start_restaurant_id = pick_id
	_procure_selected_start_restaurant_id = pick_id
	_procure_selected_tiles.clear()
	_procure_selected_tiles.append(entrance_tile)
	_recompute_procurement_plan(state)
	return true

func _get_procure_employee_def(employee_type: String) -> EmployeeDef:
	if employee_type.is_empty():
		return null
	if not EmployeeRegistryClass.is_loaded():
		return null
	var def_val = EmployeeRegistryClass.get_def(employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		return null
	return def_val

func _is_air_procure_employee_type(employee_type: String) -> bool:
	var def := _get_procure_employee_def(employee_type)
	if def != null:
		return str(def.range_type) == "air"
	return employee_type == "zeppelin_pilot"

func _get_air_procure_max_tiles(state: GameState, emp_def: EmployeeDef) -> int:
	if emp_def == null:
		return 0
	var max_tiles := int(emp_def.range_value)
	if state == null:
		return max_tiles
	var bonus_read := DrinksProcurementClass._get_distance_range_bonus_from_milestones(
		state, state.get_current_player_id(), str(emp_def.id)
	)
	if bonus_read.ok:
		max_tiles += int(bonus_read.value)
	return max_tiles

func _get_air_procure_start_tiles(state: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null:
		return out
	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return out
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return out
	var restaurants: Dictionary = restaurants_val

	var seen := {}
	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			continue
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var ep = rest.get("entrance_pos", null)
		if not (ep is Vector2i):
			continue
		var entrance_pos: Vector2i = Vector2i(ep)

		var tile_pos := Vector2i.ZERO
		var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, entrance_pos)
		if tile_read.ok:
			tile_pos = tile_read.value
		else:
			tile_pos = MapUtils.world_to_tile(entrance_pos).board_pos

		if seen.has(tile_pos):
			continue
		seen[tile_pos] = true
		out.append(tile_pos)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return out

func _resolve_air_procure_restaurant_and_entrance_from_start_tile(state: GameState, start_tile: Vector2i) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if start_tile == Vector2i(-1, -1):
		return Result.failure("未选择起点板块")

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = restaurants_val

	var matches: Array[String] = []
	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			continue
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var ep = rest.get("entrance_pos", null)
		if not (ep is Vector2i):
			continue
		var entrance_pos: Vector2i = Vector2i(ep)

		var entrance_tile := Vector2i.ZERO
		var tile_read := TileRouteUtilsClass.world_to_tile_pos(state, entrance_pos)
		if tile_read.ok:
			entrance_tile = tile_read.value
		else:
			entrance_tile = MapUtils.world_to_tile(entrance_pos).board_pos

		if entrance_tile == start_tile:
			matches.append(str(rest_id))

	if matches.is_empty():
		return Result.failure("第一格必须选择餐厅所在板块")

	matches.sort()
	var chosen_id: String = matches[0]
	var chosen: Dictionary = restaurants.get(chosen_id, {})
	var ep2 = chosen.get("entrance_pos", null)
	if not (ep2 is Vector2i):
		return Result.failure("无法解析餐厅入口位置: %s" % chosen_id)

	return Result.success({
		"restaurant_id": chosen_id,
		"entrance_pos": Vector2i(ep2),
	})

func _get_map_canvas():
	if _scene == null or not (_scene is Node):
		return null
	var canvas = (_scene as Node).get("map_canvas")
	if canvas != null and is_instance_valid(canvas):
		return canvas
	return null

func _clear_procure_restaurant_choice_ui_and_overlays() -> void:
	var canvas = _get_map_canvas()
	if canvas != null and canvas.has_method("clear_procure_drinks_restaurant_indices"):
		canvas.call("clear_procure_drinks_restaurant_indices")
	elif canvas != null and canvas.has_method("clear_procure_drinks_selected_restaurant_anchor"):
		canvas.call("clear_procure_drinks_selected_restaurant_anchor")
	if canvas != null and canvas.has_method("clear_procure_drinks_hovered_restaurant_anchor"):
		canvas.call("clear_procure_drinks_hovered_restaurant_anchor")

	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procure_restaurants"):
		var empty: Array[Dictionary] = []
		production_panel.set_drinks_procure_restaurants(empty, "", false)
	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_hover_preview_text"):
		production_panel.call("set_drinks_hover_preview_text", "")

	_procure_hover_start_restaurant_id = ""
	_procure_hover_preview_active = false

func _sync_procure_restaurant_choice_ui_and_overlays(state: GameState) -> void:
	if state == null:
		return
	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return
	restaurant_ids.sort()

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return
	var restaurants: Dictionary = restaurants_val

	var index_by_id: Dictionary = {}
	for i in range(restaurant_ids.size()):
		index_by_id[str(restaurant_ids[i])] = i + 1

	var options: Array[Dictionary] = []
	var index_by_anchor: Dictionary = {}
	for rid in restaurant_ids:
		if not restaurants.has(rid):
			continue
		var rest_val = restaurants[rid]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var idx := int(index_by_id.get(rid, options.size() + 1))
		var ep = rest.get("entrance_pos", null)
		var entrance_pos: Vector2i = Vector2i(-1, -1)
		if ep is Vector2i:
			entrance_pos = Vector2i(ep)

		var label := "餐厅 %d" % idx
		if entrance_pos != Vector2i(-1, -1):
			label = "餐厅 %d @ (%d,%d)" % [idx, entrance_pos.x, entrance_pos.y]
		options.append({"id": rid, "label": label})

		if restaurant_ids.size() > 1 and entrance_pos != Vector2i(-1, -1):
			index_by_anchor[entrance_pos] = idx

	var is_air := _is_air_procure_employee_type(_procure_selected_employee_type)
	var require_selection := is_air and restaurant_ids.size() > 1

	var selected_id := str(_procure_selected_start_restaurant_id).strip_edges()
	if selected_id.is_empty() and is_air:
		selected_id = str(_procure_air_start_restaurant_id).strip_edges()
	if selected_id.is_empty() and (not is_air):
		selected_id = str(restaurant_ids[0]).strip_edges()
		_procure_selected_start_restaurant_id = selected_id

	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procure_restaurants"):
		production_panel.set_drinks_procure_restaurants(options, selected_id, require_selection)

	var canvas = _get_map_canvas()
	if canvas != null:
		if canvas.has_method("set_procure_drinks_restaurant_indices"):
			if restaurant_ids.size() > 1:
				canvas.call("set_procure_drinks_restaurant_indices", index_by_anchor)
			elif canvas.has_method("clear_procure_drinks_restaurant_indices"):
				canvas.call("clear_procure_drinks_restaurant_indices")

		var selected_anchor := Vector2i(-1, -1)
		if not selected_id.is_empty() and restaurants.has(selected_id) and (restaurants[selected_id] is Dictionary):
			var rest2: Dictionary = restaurants[selected_id]
			var ep2 = rest2.get("entrance_pos", null)
			if ep2 is Vector2i:
				selected_anchor = Vector2i(ep2)

		if canvas.has_method("set_procure_drinks_selected_restaurant_anchor"):
			if selected_anchor != Vector2i(-1, -1):
				canvas.call("set_procure_drinks_selected_restaurant_anchor", selected_anchor)
			elif canvas.has_method("clear_procure_drinks_selected_restaurant_anchor"):
				canvas.call("clear_procure_drinks_selected_restaurant_anchor")
