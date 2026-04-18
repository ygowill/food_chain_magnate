# Game scene：Working/Production 面板控制器
# 负责：ProductionPanel 的生命周期、同步与命令分发；并委托 DrinksProcurementController 处理“采购饮料”的选点/路线。
class_name GamePanelWorkingProductionController
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const DrinksProcurementControllerClass = preload("res://ui/scenes/game/panel/working/procurement/controller.gd")
const ProductionPanelScene = preload("res://ui/components/production_panel/production_panel.tscn")

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()
var _center_popup: Callable = Callable()
var _procure_controller = null

var production_panel = null
var _last_context_token: String = ""
var _last_production_type: String = ""

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable, center_popup: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup
	_procure_controller = DrinksProcurementControllerClass.new(_scene, _map_controller, _overlay_controller)

func hide() -> void:
	if is_instance_valid(production_panel):
		production_panel.visible = false
	if _procure_controller != null and _procure_controller.has_method("clear_procure_restaurant_choice_ui_and_overlays"):
		_procure_controller.call("clear_procure_restaurant_choice_ui_and_overlays")
	_last_context_token = ""
	_last_production_type = ""

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(production_panel) or not production_panel.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING:
		production_panel.visible = false
		if _procure_controller != null:
			_procure_controller.hide_procurement_route_overlay()
			_procure_controller.call("clear_procure_restaurant_choice_ui_and_overlays")
		return
	if state.sub_phase != DefsClass.SUB_PHASE_GET_FOOD and state.sub_phase != DefsClass.SUB_PHASE_GET_DRINKS:
		production_panel.visible = false
		if _procure_controller != null:
			_procure_controller.hide_procurement_route_overlay()
			_procure_controller.call("clear_procure_restaurant_choice_ui_and_overlays")
		return

	var current_player: Dictionary = state.get_current_player()
	var production_type := "food" if state.sub_phase == DefsClass.SUB_PHASE_GET_FOOD else "drinks"
	var context_token := "%d|%d|%s|%s" % [
		int(state.get_current_player_id()),
		int(state.round_number),
		str(state.phase),
		str(state.sub_phase),
	]
	var needs_refresh := force_full_refresh or (production_type != _last_production_type) or (context_token != _last_context_token)
	_last_production_type = production_type
	_last_context_token = context_token

	# Always keep usage token in sync so the panel can reset per-round/per-subphase UI state when needed.
	if production_panel.has_method("set_usage_token"):
		production_panel.set_usage_token(context_token)

	if needs_refresh:

		# 记录“回合/子阶段/玩家”上下文：用于 ProductionPanel 跨关闭/重开保持“本次用了哪张卡”的禁用态；
		# 当上下文变化（换人/换回合/换子阶段）时自动清空。
		if production_panel.has_method("set_production_type"):
			production_panel.set_production_type(production_type)
			if is_instance_valid(production_panel):
				production_panel.set_meta("production_type", production_type)
		if is_instance_valid(production_panel):
			production_panel.set_meta("popup_title", "生产" if production_type == "food" else "采购")

		# 时间线变化：清空上一次地图选点/路线缓存，避免残留旧状态
		if _procure_controller != null:
			_procure_controller.hide_procurement_route_overlay()
		if production_type == "drinks":
			if _procure_controller != null:
				_procure_controller.reset_procurement_selection_state()
				_procure_controller.hide_procurement_route_overlay()
			if _map_controller != null and _map_controller.has_method("clear_selection"):
				_map_controller.clear_selection()
			if production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(0, false, "")

		if production_panel.has_method("set_producer_items"):
			production_panel.set_producer_items(_build_producer_items(state, production_type))
		elif production_panel.has_method("set_available_producers"):
			production_panel.set_available_producers(_build_legacy_producers(state, production_type))

		if production_panel.has_method("set_current_inventory"):
			production_panel.set_current_inventory(current_player.get("inventory", {}))

		if production_type == "drinks":
			if production_panel.has_method("set_available_drink_types"):
				production_panel.set_available_drink_types(_get_all_drink_types())
			if production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(0, false, "")

	# Inventory changes frequently; keep it fresh even without a full refresh.
	if production_panel != null and is_instance_valid(production_panel) and production_panel.has_method("set_current_inventory"):
		production_panel.set_current_inventory(current_player.get("inventory", {}))

	if state.sub_phase != DefsClass.SUB_PHASE_GET_DRINKS:
		if _procure_controller != null:
			_procure_controller.hide_procurement_route_overlay()
			_procure_controller.call("clear_procure_restaurant_choice_ui_and_overlays")

func show(production_type: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if production_panel == null:
		production_panel = ProductionPanelScene.instantiate()
		production_panel.visible = false
		production_panel.set_meta("popup_layout", "dock_right")
		if production_panel.has_signal("production_requested"):
			production_panel.production_requested.connect(_on_production_requested)
		if production_panel.has_signal("producer_changed"):
			production_panel.producer_changed.connect(_on_producer_changed)
		if production_panel.has_signal("drinks_clear_requested"):
			production_panel.drinks_clear_requested.connect(_on_drinks_clear_requested)
		if production_panel.has_signal("drinks_undo_requested"):
			production_panel.drinks_undo_requested.connect(_on_drinks_undo_requested)
		if production_panel.has_signal("drinks_restaurant_changed"):
			production_panel.drinks_restaurant_changed.connect(_on_drinks_restaurant_changed)
		if production_panel.has_signal("cancelled"):
			production_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(production_panel)

	if _procure_controller != null and _procure_controller.has_method("set_production_panel"):
		_procure_controller.set_production_panel(production_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	# 记录“回合/子阶段/玩家”上下文：用于 ProductionPanel 跨关闭/重开保持“本次用了哪张卡”的禁用态；
	# 当上下文变化（换人/换回合/换子阶段）时自动清空。
	if is_instance_valid(production_panel) and production_panel.has_method("set_usage_token"):
		var token := "%d|%d|%s|%s" % [
			int(state.get_current_player_id()),
			int(state.round_number),
			str(state.phase),
			str(state.sub_phase),
		]
		production_panel.set_usage_token(token)

	if production_panel.has_method("set_production_type"):
		production_panel.set_production_type(production_type)
	if is_instance_valid(production_panel):
		if production_type == "food":
			production_panel.set_meta("popup_title", "生产")
		else:
			production_panel.set_meta("popup_title", "采购")

	# drinks：先清空上一次选择状态（注意：set_available_producers 会触发 producer_changed，从而重新进入选点模式）
	if production_type == "drinks":
		if _procure_controller != null:
			_procure_controller.reset_procurement_selection_state()

	if production_panel.has_method("set_producer_items"):
		production_panel.set_producer_items(_build_producer_items(state, production_type))
	elif production_panel.has_method("set_available_producers"):
		production_panel.set_available_producers(_build_legacy_producers(state, production_type))

	if production_panel.has_method("set_current_inventory"):
		production_panel.set_current_inventory(current_player.get("inventory", {}))

	if production_type == "drinks":
		if is_instance_valid(production_panel) and production_panel.has_method("set_available_drink_types"):
			production_panel.set_available_drink_types(_get_all_drink_types())
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")

	if _center_popup.is_valid():
		_center_popup.call(production_panel)
	production_panel.visible = true

func _get_all_drink_types() -> Array[String]:
	var out: Array[String] = []
	if not ProductRegistryClass.is_loaded():
		return out
	for pid in ProductRegistryClass.get_all_ids():
		if ProductRegistryClass.is_drink(pid):
			out.append(pid)
	return out

func _build_producer_items(state: GameState, production_type: String) -> Array[Dictionary]:
	if state == null:
		return []
	var player_id := int(state.get_current_player_id())
	if production_type == "food":
		return EmployeeRulesClass.get_food_producers_for_working(state, player_id)
	return EmployeeRulesClass.get_drinks_procurers_for_working(state, player_id)

func _build_legacy_producers(state: GameState, production_type: String) -> Array[String]:
	var out: Array[String] = []
	for provider_val in _build_producer_items(state, production_type):
		if not (provider_val is Dictionary):
			continue
		var provider: Dictionary = provider_val
		var emp_id := str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
		if emp_id.is_empty():
			continue
		var capacity := maxi(1, int(provider.get("capacity", 1)))
		for i in range(capacity):
			out.append(emp_id)
	return out

func _on_production_requested(employee_type: String, product_type: String, staff_id: int = -1) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var action_id := "produce_food" if product_type == "food" else "procure_drinks"
	var params := {"employee_type": employee_type}
	if staff_id > 0:
		params["staff_id"] = staff_id
	if product_type == "food":
		var food_type := ""
		if is_instance_valid(production_panel) and production_panel.has_method("get_selected_food_type"):
			food_type = str(production_panel.call("get_selected_food_type")).strip_edges()
		if not food_type.is_empty():
			params["food_type"] = food_type
	if product_type == "drinks":
		if employee_type == "errand_boy":
			var drink_type := ""
			if is_instance_valid(production_panel) and production_panel.has_method("get_selected_drink_type"):
				drink_type = str(production_panel.call("get_selected_drink_type")).strip_edges()
			params["drink_type"] = drink_type
		else:
			if _procure_controller == null:
				return
			var restaurant_id: String = _procure_controller.get_procure_restaurant_id()
			var route: Array[Vector2i] = _procure_controller.get_procure_route()
			var selected_sources: Array[Vector2i] = _procure_controller.get_procure_selected_sources()
			if restaurant_id.is_empty() or route.is_empty() or selected_sources.is_empty():
				return
			params["restaurant_id"] = restaurant_id
			params["route"] = DrinksProcurementClass.serialize_route(route)
			params["selected_sources"] = DrinksProcurementClass.serialize_route(selected_sources)

	var result: Result = _execute_command.call(Command.create(action_id, current_player_id, params))

	if result.ok:
		if product_type == "drinks":
			if _procure_controller != null:
				_procure_controller.reset_procurement_selection_state()
				_procure_controller.hide_procurement_route_overlay()
			if _map_controller != null and _map_controller.has_method("clear_selection"):
				_map_controller.clear_selection()
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(0, false, "")

		if is_instance_valid(production_panel):
			var state = _scene.game_engine.get_state()
			var current_player: Dictionary = state.get_current_player()
			if production_panel.has_method("set_producer_items"):
				production_panel.set_producer_items(_build_producer_items(state, product_type))
			if production_panel.has_method("set_current_inventory"):
				production_panel.set_current_inventory(current_player.get("inventory", {}))

func _on_producer_changed(employee_type: String, product_type: String, staff_id: int = -1) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if product_type != "drinks":
		if _procure_controller != null:
			_procure_controller.reset_procurement_selection_state()
			_procure_controller.hide_procurement_route_overlay()
		if _map_controller != null and _map_controller.has_method("clear_selection"):
			_map_controller.clear_selection()
		return
	if _procure_controller == null:
		return
	var state: GameState = _scene.game_engine.get_state()
	_procure_controller.on_drinks_producer_changed(state, employee_type, staff_id)

func _on_drinks_clear_requested() -> void:
	if _procure_controller != null:
		_procure_controller.on_drinks_clear_requested()

func _on_drinks_undo_requested() -> void:
	if _procure_controller != null:
		_procure_controller.on_drinks_undo_requested()

func _on_drinks_restaurant_changed(restaurant_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _procure_controller == null:
		return
	var state: GameState = _scene.game_engine.get_state()
	if _procure_controller.has_method("on_drinks_start_restaurant_changed"):
		_procure_controller.call("on_drinks_start_restaurant_changed", state, restaurant_id)

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
