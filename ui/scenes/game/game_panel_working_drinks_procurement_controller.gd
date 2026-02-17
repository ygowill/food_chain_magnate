# Game scene：Working/Drinks Procurement 控制器
# 负责：采购饮料（非跑腿伙计）的地图选点、路线规划与 overlay 展示。
class_name GamePanelWorkingDrinksProcurementController
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const AirHelpersClass = preload("res://ui/scenes/game/game_panel_working_drinks_procurement_air_helpers.gd")
const HoverPreviewControllerClass = preload("res://ui/scenes/game/game_panel_working_drinks_procurement_hover_preview_controller.gd")
const RoadHelpersClass = preload("res://ui/scenes/game/game_panel_working_drinks_procurement_road_helpers.gd")
const RestaurantChoiceControllerClass = preload("res://ui/scenes/game/game_panel_working_drinks_procurement_restaurant_choice_controller.gd")

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _hover_preview_controller = null
var _restaurant_choice_controller = null

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
	_hover_preview_controller = HoverPreviewControllerClass.new()
	_hover_preview_controller.setup(self)
	_restaurant_choice_controller = RestaurantChoiceControllerClass.new()
	_restaurant_choice_controller.setup(self)

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
		var bounds := AirHelpersClass.get_air_tile_bounds(state, tile_positions_set)
		if not AirHelpersClass.is_air_tile_valid(tile_pos, tile_positions_set, bounds):
			_procure_error = "板块不可选"
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(_procure_selected_tiles.size(), false, _procure_error)
			return

		if _procure_selected_tiles.is_empty():
			var rest_pick := AirHelpersClass.resolve_air_procure_restaurant_and_entrance_from_start_tile(state, tile_pos)
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

		var max_tiles := AirHelpersClass.get_air_procure_max_tiles(state, emp_def)
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

	var route_r := RoadHelpersClass.build_road_route(state, entrance_pos, candidate_sources)
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
	if _hover_preview_controller != null and is_instance_valid(_hover_preview_controller):
		_hover_preview_controller.set_hover_start_restaurant_id(state, str(restaurant_id))

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
			var pick := AirHelpersClass.resolve_air_procure_restaurant_and_entrance_from_start_tile(state, start_tile)
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
		selected_sources = AirHelpersClass.collect_air_sources_in_tiles(state, route)
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
		var road_r := RoadHelpersClass.build_road_route(state, entrance_pos, _procure_selected_sources)
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
			var tile_size_cells := AirHelpersClass.get_air_tile_size_cells(state)
			overlay_route = AirHelpersClass.build_air_tile_display_route(_procure_route, tile_size_cells)
			overlay_entrance = AirHelpersClass.get_tile_center_world_pos(entrance_tile, tile_size_cells)
			overlay_options = AirHelpersClass.build_air_procure_overlay_options(state, emp_def, _procure_selected_tiles, entrance_tile)
		overlay_options["start_restaurant_cells"] = _get_restaurant_cells(state, chosen_restaurant_id)
		_overlay_controller.call("show_procurement_route_overlay", overlay_entrance, overlay_route, picked_sources_pos, overlay_options)

	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
		production_panel.set_drinks_procurement_state(selected_count, true, "")

func _show_air_procure_start_tiles_overlay(state: GameState) -> void:
	if state == null:
		return
	if not _is_air_procure_employee_type(_procure_selected_employee_type):
		return
	if _overlay_controller == null or not _overlay_controller.has_method("show_procurement_route_overlay"):
		return

	var start_tiles: Array[Vector2i] = AirHelpersClass.get_air_procure_start_tiles(state)
	if start_tiles.is_empty():
		hide_procurement_route_overlay()
		return

	var tile_size_cells := AirHelpersClass.get_air_tile_size_cells(state)
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
	var tile_size_cells := AirHelpersClass.get_air_tile_size_cells(state)
	var overlay_route := AirHelpersClass.build_air_tile_display_route(_procure_selected_tiles, tile_size_cells)
	var overlay_entrance := AirHelpersClass.get_tile_center_world_pos(entrance_tile, tile_size_cells)
	var overlay_options := AirHelpersClass.build_air_procure_overlay_options(state, emp_def, _procure_selected_tiles, entrance_tile)
	var rid := str(_procure_air_start_restaurant_id).strip_edges()
	if rid.is_empty():
		rid = str(_procure_selected_start_restaurant_id).strip_edges()
	overlay_options["start_restaurant_cells"] = _get_restaurant_cells(state, rid)
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

func _get_map_canvas():
	if _scene == null or not (_scene is Node):
		return null
	var canvas = (_scene as Node).get("map_canvas")
	if canvas != null and is_instance_valid(canvas):
		return canvas
	return null

func _get_restaurant_cells(state: GameState, restaurant_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null:
		return out
	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		return out
	if state.map == null or not (state.map is Dictionary):
		return out
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return out
	var rest_val = (restaurants_val as Dictionary).get(rid, null)
	if not (rest_val is Dictionary):
		return out
	var cells_val = (rest_val as Dictionary).get("cells", null)
	if cells_val is Array:
		for p in (cells_val as Array):
			if p is Vector2i:
				out.append(Vector2i(p))
			elif p is Array:
				var a: Array = p
				if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
					out.append(Vector2i(int(a[0]), int(a[1])))
	return out

func _clear_procure_restaurant_choice_ui_and_overlays() -> void:
	if _restaurant_choice_controller != null and is_instance_valid(_restaurant_choice_controller):
		_restaurant_choice_controller.clear_ui_and_overlays()

func _sync_procure_restaurant_choice_ui_and_overlays(state: GameState) -> void:
	if _restaurant_choice_controller != null and is_instance_valid(_restaurant_choice_controller):
		_restaurant_choice_controller.sync_ui_and_overlays(state)
