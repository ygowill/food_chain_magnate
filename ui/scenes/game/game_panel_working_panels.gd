# Game scene：Working 阶段面板（Recruit/Train/Price/Production/Milestone）
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")

const RecruitPanelScene = preload("res://ui/components/recruit_panel/recruit_panel.tscn")
const TrainPanelScene = preload("res://ui/components/train_panel/train_panel.tscn")
const PricePanelScene = preload("res://ui/components/price_panel/price_setting_panel.tscn")
const ProductionPanelScene = preload("res://ui/components/production_panel/production_panel.tscn")
const MilestonePanelScene = preload("res://ui/components/milestone_panel/milestone_panel.tscn")

var _scene = null
var _map_controller = null
var _execute_command: Callable
var _hide_all: Callable
var _center_popup: Callable
var _overlay_controller = null

var recruit_panel = null
var train_panel = null
var price_panel = null
var production_panel = null
var milestone_panel = null

var _procure_selected_employee_type: String = ""
var _procure_selected_sources: Array[Vector2i] = []
var _procure_restaurant_id: String = ""
var _procure_route: Array[Vector2i] = []
var _procure_error: String = ""

func _init(scene, map_controller, execute_command: Callable, hide_all: Callable, center_popup: Callable, overlay_controller = null) -> void:
	_scene = scene
	_map_controller = map_controller
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup
	_overlay_controller = overlay_controller

	if _map_controller != null and _map_controller.has_signal("procure_drinks_source_selected"):
		var sig := Signal(_map_controller, &"procure_drinks_source_selected")
		var cb := Callable(self, "_on_procure_drinks_source_selected")
		if not sig.is_connected(cb):
			sig.connect(cb)

func hide() -> void:
	if is_instance_valid(recruit_panel):
		recruit_panel.visible = false
	if is_instance_valid(train_panel):
		train_panel.visible = false
	if is_instance_valid(price_panel):
		price_panel.visible = false
	if is_instance_valid(production_panel):
		production_panel.visible = false
	if is_instance_valid(milestone_panel):
		milestone_panel.visible = false

func sync(state: GameState) -> void:
	_sync_recruit_panel(state)
	_sync_train_panel(state)
	_sync_production_panel(state)
	_sync_price_panel(state)

func show_recruit_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if recruit_panel == null:
		recruit_panel = RecruitPanelScene.instantiate()
		recruit_panel.visible = false
		recruit_panel.set_meta("popup_layout", "dock_right")
		recruit_panel.set_meta("popup_title", "招聘")
		recruit_panel.recruit_requested.connect(_on_recruit_requested)
		if recruit_panel.has_signal("cancelled"):
			recruit_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(recruit_panel)

	var state = _scene.game_engine.get_state()

	if recruit_panel.has_method("set_employee_pool"):
		recruit_panel.set_employee_pool(state.employee_pool)

	if recruit_panel.has_method("set_recruit_count"):
		var actor = state.get_current_player_id()
		var counts := _compute_recruit_counts(state, actor)
		recruit_panel.set_recruit_count(int(counts.remaining), int(counts.total))

	if recruit_panel.has_method("clear_selection"):
		recruit_panel.clear_selection()

	if _center_popup.is_valid():
		_center_popup.call(recruit_panel)
	recruit_panel.visible = true

func _sync_recruit_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(recruit_panel) or not recruit_panel.visible:
		return
	if state.phase != "Working" or state.sub_phase != "Recruit":
		recruit_panel.visible = false
		return
	if recruit_panel.has_method("set_recruit_count"):
		var actor := state.get_current_player_id()
		var counts := _compute_recruit_counts(state, actor)
		recruit_panel.set_recruit_count(int(counts.remaining), int(counts.total))

func _compute_recruit_counts(state: GameState, player_id: int) -> Dictionary:
	if state == null:
		return {"remaining": 0, "total": 0}
	var total: int = EmployeeRulesClass.get_recruit_limit_for_working(state, player_id)
	var used: int = EmployeeRulesClass.get_action_count(state, player_id, "recruit")
	return {"remaining": maxi(0, total - used), "total": total}

func _compute_train_counts(state: GameState, player_id: int) -> Dictionary:
	if state == null:
		return {"remaining": 0, "total": 0}
	var total: int = EmployeeRulesClass.get_train_limit_for_working(state, player_id)
	var used: int = EmployeeRulesClass.get_action_count(state, player_id, "train")
	return {"remaining": maxi(0, total - used), "total": total}

func _build_employee_type_counts(values: Array) -> Dictionary:
	var counts := {}
	for v in values:
		if not (v is String):
			continue
		var emp_id: String = str(v)
		if emp_id.is_empty():
			continue
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1
	return counts

func _read_immediate_train_pending_sources(state: GameState, player_id: int) -> Dictionary:
	var sources := {}
	if state == null or not (state.round_state is Dictionary):
		return sources
	var rs: Dictionary = state.round_state
	var all_val = rs.get("immediate_train_pending", null)
	if not (all_val is Dictionary):
		return sources
	var all: Dictionary = all_val

	var per_val = null
	if all.has(player_id):
		per_val = all.get(player_id, null)
	elif all.has(str(player_id)):
		per_val = all.get(str(player_id), null)
	if not (per_val is Dictionary):
		return sources
	var per: Dictionary = per_val

	for k in per.keys():
		if not (k is String):
			continue
		var emp_id: String = str(k)
		if emp_id.is_empty():
			continue
		var v = per.get(k, 0)
		var count := 0
		if v is int:
			count = int(v)
		elif v is float:
			var f: float = float(v)
			if f == int(f):
				count = int(f)
		if count <= 0:
			continue
		sources[emp_id] = count

	return sources

func show_train_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if train_panel == null:
		train_panel = TrainPanelScene.instantiate()
		train_panel.visible = false
		train_panel.set_meta("popup_layout", "dock_right")
		train_panel.set_meta("popup_title", "培训")
		train_panel.train_requested.connect(_on_train_requested)
		_scene.add_child(train_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if train_panel.has_method("set_employee_pool"):
		train_panel.set_employee_pool(state.employee_pool)

	if train_panel.has_method("set_trainable_employees"):
		var actor_id: int = int(state.get_current_player_id())
		var pending_total := int(EmployeeRulesClass.get_immediate_train_pending_total(state, actor_id))
		var sources := {}
		var requires_same_color := {}
		var section_text := "待命区员工（点击选择）"
		var badges := {}

		if pending_total > 0:
			sources = _read_immediate_train_pending_sources(state, actor_id)
			section_text = "缺货预支待培训（必须先清账）"
			for emp_id in sources.keys():
				badges[str(emp_id)] = "预支"
		else:
			var reserve_counts := _build_employee_type_counts(Array(current_player.get("reserve_employees", [])))
			sources = reserve_counts.duplicate(true)
			var can_train_from_active := bool(current_player.get("train_from_active_same_color", false))
			if can_train_from_active:
				section_text = "待命/在岗员工（点击选择；在岗同色培训：目标需同色）"
				var active_counts := _build_employee_type_counts(Array(current_player.get("employees", [])))
				for emp_id in active_counts.keys():
					sources[str(emp_id)] = int(sources.get(emp_id, 0)) + int(active_counts.get(emp_id, 0))
				for emp_id in sources.keys():
					var active_count: int = int(active_counts.get(emp_id, 0))
					var reserve_count: int = int(reserve_counts.get(emp_id, 0))
					if active_count > 0 and reserve_count <= 0:
						requires_same_color[str(emp_id)] = true

		if train_panel.has_method("set_source_requires_same_color"):
			train_panel.set_source_requires_same_color(requires_same_color)
		if train_panel.has_method("set_source_badges"):
			train_panel.set_source_badges(badges)
		if train_panel.has_method("set_trainable_sources"):
			train_panel.set_trainable_sources(sources, section_text)
		else:
			var reserve: Array[String] = []
			for emp_id in sources.keys():
				reserve.append(str(emp_id))
			reserve.sort()
			train_panel.set_trainable_employees(reserve)

	if train_panel.has_method("set_train_count"):
		var actor: int = int(state.get_current_player_id())
		var counts := _compute_train_counts(state, actor)
		train_panel.set_train_count(int(counts.remaining), int(counts.total))

	if _center_popup.is_valid():
		_center_popup.call(train_panel)
	train_panel.visible = true

func _sync_train_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(train_panel) or not train_panel.visible:
		return
	if state.phase != "Working" or state.sub_phase != "Train":
		train_panel.visible = false
		return
	if train_panel.has_method("set_train_count"):
		var actor: int = int(state.get_current_player_id())
		var counts := _compute_train_counts(state, actor)
		train_panel.set_train_count(int(counts.remaining), int(counts.total))

func show_price_panel(action_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if price_panel == null:
		price_panel = PricePanelScene.instantiate()
		price_panel.visible = false
		price_panel.set_meta("popup_layout", "dock_right")
		if price_panel.has_signal("price_confirmed"):
			price_panel.price_confirmed.connect(_on_price_confirmed)
		if price_panel.has_signal("cancelled"):
			price_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(price_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if price_panel.has_method("set_mode"):
		match action_id:
			"set_price":
				price_panel.set_meta("popup_title", "定价")
				price_panel.set_mode("price")
			"set_luxury_price":
				price_panel.set_meta("popup_title", "奢侈品定价")
				price_panel.set_mode("luxury")
			"set_discount":
				price_panel.set_meta("popup_title", "折扣")
				price_panel.set_mode("discount")

	if price_panel.has_method("set_current_prices"):
		var prices: Dictionary = current_player.get("prices", {})
		price_panel.set_current_prices(prices)

	if _center_popup.is_valid():
		_center_popup.call(price_panel)
	price_panel.visible = true

func _sync_price_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(price_panel) or not price_panel.visible:
		return
	if state.phase != "Working":
		price_panel.visible = false
		return

func show_production_panel(production_type: String) -> void:
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
		if production_panel.has_signal("cancelled"):
			production_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(production_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if production_panel.has_method("set_production_type"):
		production_panel.set_production_type(production_type)
	if is_instance_valid(production_panel):
		if production_type == "food":
			production_panel.set_meta("popup_title", "生产")
		else:
			production_panel.set_meta("popup_title", "采购")

	if production_panel.has_method("set_available_producers"):
		var producers: Array[String] = []
		if EmployeeRegistryClass.is_loaded():
			for e in Array(current_player.get("employees", [])):
				if not (e is String):
					continue
				var emp_id := str(e)
				if emp_id.is_empty():
					continue
				var def_val = EmployeeRegistryClass.get_def(emp_id)
				if def_val == null or not (def_val is EmployeeDef):
					continue
				var def: EmployeeDef = def_val
				if production_type == "food" and def.can_produce():
					producers.append(emp_id)
				elif production_type == "drinks" and def.can_procure():
					producers.append(emp_id)
		else:
			for e in Array(current_player.get("employees", [])):
				producers.append(str(e))
		production_panel.set_available_producers(producers)

	if production_panel.has_method("set_current_inventory"):
		production_panel.set_current_inventory(current_player.get("inventory", {}))

	if production_type == "drinks":
		_reset_procurement_selection_state()
		if is_instance_valid(production_panel) and production_panel.has_method("set_available_drink_types"):
			production_panel.set_available_drink_types(_get_drink_types_from_map(state))
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")

	if _center_popup.is_valid():
		_center_popup.call(production_panel)
	production_panel.visible = true

func _sync_production_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(production_panel) or not production_panel.visible:
		return
	if state.phase != "Working":
		production_panel.visible = false
		_hide_procurement_route_overlay()
		return
	if state.sub_phase != "GetFood" and state.sub_phase != "GetDrinks":
		production_panel.visible = false
		_hide_procurement_route_overlay()
		return
	if state.sub_phase != "GetDrinks":
		_hide_procurement_route_overlay()

func show_milestone_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if milestone_panel == null:
		milestone_panel = MilestonePanelScene.instantiate()
		milestone_panel.visible = false
		milestone_panel.set_meta("popup_layout", "dock_right")
		milestone_panel.set_meta("popup_title", "里程碑")
		if milestone_panel.has_signal("cancelled"):
			milestone_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(milestone_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if milestone_panel.has_method("set_milestone_pool"):
		milestone_panel.set_milestone_pool(state.milestone_pool)
	if milestone_panel.has_method("set_player_milestones"):
		milestone_panel.set_player_milestones(current_player.get("milestones", []))

	if _center_popup.is_valid():
		_center_popup.call(milestone_panel)
	milestone_panel.visible = true

func _on_recruit_requested(employee_type: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var result: Result = _execute_command.call(Command.create("recruit", current_player_id, {"employee_type": employee_type}))

	if result.ok:
		var state = _scene.game_engine.get_state()
		if is_instance_valid(recruit_panel) and recruit_panel.has_method("set_employee_pool"):
			recruit_panel.set_employee_pool(state.employee_pool)
		_sync_recruit_panel(state)

func _on_train_requested(from_employee: String, to_employee: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var result: Result = _execute_command.call(Command.create("train", current_player_id, {
		"from_employee": from_employee,
		"to_employee": to_employee
	}))

	if result.ok:
		var state: GameState = _scene.game_engine.get_state()
		if state != null and state.phase == "Working" and state.sub_phase == "Train":
			show_train_panel()

func _on_price_confirmed(action_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	if action_id.is_empty():
		return
	var result: Result = _execute_command.call(Command.create(action_id, current_player_id))

	if result.ok and _hide_all.is_valid():
		_hide_all.call()

func _on_production_requested(employee_type: String, product_type: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var action_id := "produce_food" if product_type == "food" else "procure_drinks"
	var params := {"employee_type": employee_type}
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
			if _procure_restaurant_id.is_empty() or _procure_route.is_empty() or _procure_selected_sources.is_empty():
				return
			params["restaurant_id"] = _procure_restaurant_id
			params["route"] = DrinksProcurementClass.serialize_route(_procure_route)
			params["selected_sources"] = DrinksProcurementClass.serialize_route(_procure_selected_sources)

	var result: Result = _execute_command.call(Command.create(action_id, current_player_id, params))

	if result.ok:
		if product_type == "drinks":
			_reset_procurement_selection_state()
			_hide_procurement_route_overlay()
			if _map_controller != null and _map_controller.has_method("clear_selection"):
				_map_controller.clear_selection()
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(0, false, "")

		if is_instance_valid(production_panel):
			var state = _scene.game_engine.get_state()
			var current_player: Dictionary = state.get_current_player()
			if production_panel.has_method("set_current_inventory"):
				production_panel.set_current_inventory(current_player.get("inventory", {}))

func _on_producer_changed(employee_type: String, product_type: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if product_type != "drinks":
		_reset_procurement_selection_state()
		_hide_procurement_route_overlay()
		if _map_controller != null and _map_controller.has_method("clear_selection"):
			_map_controller.clear_selection()
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	if state.phase != "Working" or state.sub_phase != "GetDrinks":
		_reset_procurement_selection_state()
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
		return
	if employee_type.is_empty():
		_reset_procurement_selection_state()
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
		return

	_procure_selected_employee_type = employee_type

	# 跑腿伙计：不需要选点/路线
	if employee_type == "errand_boy":
		_reset_procurement_selection_state()
		_hide_procurement_route_overlay()
		if _map_controller != null and _map_controller.has_method("clear_selection"):
			_map_controller.clear_selection()
		return

	_reset_procurement_selection_state(false)
	if _map_controller != null and _map_controller.has_method("begin_selection"):
		_map_controller.begin_selection("procure_drinks", {"employee_type": employee_type})
	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
		production_panel.set_drinks_procurement_state(0, false, "")

func _preview_procurement_route(state: GameState, employee_type: String) -> void:
	if _overlay_controller == null:
		return
	if not EmployeeRegistryClass.is_loaded():
		_hide_procurement_route_overlay()
		return
	var def_val = EmployeeRegistryClass.get_def(employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		_hide_procurement_route_overlay()
		return
	var emp_def: EmployeeDef = def_val
	if not emp_def.can_procure():
		_hide_procurement_route_overlay()
		return

	var player_id := state.get_current_player_id()
	var restaurant_ids := MapRuntimeClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		_hide_procurement_route_overlay()
		return

	var cmd := Command.create("procure_drinks", player_id, {"employee_type": employee_type})
	var plan_r := DrinksProcurementClass.resolve_procurement_plan(state, cmd, restaurant_ids, emp_def)
	if not plan_r.ok:
		_hide_procurement_route_overlay()
		return
	if not (plan_r.value is Dictionary):
		_hide_procurement_route_overlay()
		return

	var plan: Dictionary = plan_r.value
	var entrance_pos: Vector2i = plan.get("entrance_pos", Vector2i(-1, -1))
	var route_val = plan.get("route", [])
	if not (route_val is Array):
		_hide_procurement_route_overlay()
		return
	var route: Array[Vector2i] = []
	for p in route_val:
		if p is Vector2i:
			route.append(p)
	if route.is_empty():
		_hide_procurement_route_overlay()
		return

	var picked_sources_pos: Array[Vector2i] = []
	var ps_val = plan.get("picked_sources", [])
	if ps_val is Array:
		for s in ps_val:
			if not (s is Dictionary):
				continue
			var src: Dictionary = s
			var wp = src.get("world_pos", null)
			if wp is Vector2i:
				picked_sources_pos.append(wp)

	if _overlay_controller.has_method("show_procurement_route_overlay"):
		_overlay_controller.call("show_procurement_route_overlay", entrance_pos, route, picked_sources_pos)

func _hide_procurement_route_overlay() -> void:
	if _overlay_controller != null and _overlay_controller.has_method("hide_procurement_route_overlay"):
		_overlay_controller.call("hide_procurement_route_overlay")

func _reset_procurement_selection_state(clear_employee: bool = true) -> void:
	if clear_employee:
		_procure_selected_employee_type = ""
	_procure_selected_sources.clear()
	_procure_restaurant_id = ""
	_procure_route.clear()
	_procure_error = ""

func _get_drink_types_from_map(state: GameState) -> Array[String]:
	var set := {}
	if state == null:
		return []
	var sources_val = state.map.get("drink_sources", null)
	if sources_val is Array:
		var sources: Array = sources_val
		for s_val in sources:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			var t := str(s.get("type", "")).strip_edges()
			if t.is_empty():
				continue
			set[t] = true

	var out: Array[String] = []
	for k in set.keys():
		out.append(str(k))
	out.sort()
	return out

func _on_drinks_clear_requested() -> void:
	_reset_procurement_selection_state(false)
	_hide_procurement_route_overlay()
	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
		production_panel.set_drinks_procurement_state(0, false, "")

func _on_drinks_undo_requested() -> void:
	if _procure_selected_sources.is_empty():
		return
	_procure_selected_sources.pop_back()
	var state: GameState = _scene.game_engine.get_state() if _scene != null and _scene.game_engine != null else null
	if state == null:
		return
	_recompute_procurement_plan(state)

func _on_procure_drinks_source_selected(world_pos: Vector2i) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(production_panel) or not production_panel.visible:
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	if state.phase != "Working" or state.sub_phase != "GetDrinks":
		return

	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return

	if _procure_selected_sources.has(world_pos):
		return
	_procure_selected_sources.append(world_pos)
	_recompute_procurement_plan(state)

func _recompute_procurement_plan(state: GameState) -> void:
	_procure_error = ""
	_procure_restaurant_id = ""
	_procure_route.clear()

	if state == null:
		return
	if _procure_selected_employee_type.is_empty() or _procure_selected_employee_type == "errand_boy":
		return

	if _procure_selected_sources.is_empty():
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(0, false, "")
		return

	if not EmployeeRegistryClass.is_loaded():
		_procure_error = "EmployeeRegistry 未初始化"
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
		return

	var def_val = EmployeeRegistryClass.get_def(_procure_selected_employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		_procure_error = "未知员工类型: %s" % _procure_selected_employee_type
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
		return
	var emp_def: EmployeeDef = def_val

	var player_id := state.get_current_player_id()
	var restaurant_ids := MapRuntimeClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		_procure_error = "你没有餐厅，无法采购饮料"
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
		return
	restaurant_ids.sort()

	var map_data: Dictionary = state.map
	var restaurants_val = map_data.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		_procure_error = "state.map.restaurants 缺失或类型错误"
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
		return
	var restaurants: Dictionary = restaurants_val

	var chosen_restaurant_id := ""
	var entrance_pos: Vector2i = Vector2i(-1, -1)
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

	if chosen_restaurant_id.is_empty():
		_procure_error = "无法解析餐厅入口位置"
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
		return

	var route: Array[Vector2i] = []
	if emp_def.range_type == "air":
		route = _build_air_route(entrance_pos, _procure_selected_sources)
	else:
		var road_r := _build_road_route(state, entrance_pos, _procure_selected_sources)
		if not road_r.ok:
			_procure_error = road_r.error
			_hide_procurement_route_overlay()
			if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
				production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
			return
		route = road_r.value

	var cmd := Command.create("procure_drinks", player_id, {
		"employee_type": _procure_selected_employee_type,
		"restaurant_id": chosen_restaurant_id,
		"route": DrinksProcurementClass.serialize_route(route),
		"selected_sources": DrinksProcurementClass.serialize_route(_procure_selected_sources)
	})

	var plan_r := DrinksProcurementClass.resolve_procurement_plan(state, cmd, restaurant_ids, emp_def)
	if not plan_r.ok:
		_procure_error = plan_r.error
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
		return
	if not (plan_r.value is Dictionary):
		_procure_error = "采购计划解析失败"
		_hide_procurement_route_overlay()
		if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
			production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), false, _procure_error)
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

	var picked_sources_pos: Array[Vector2i] = []
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
		_overlay_controller.call("show_procurement_route_overlay", entrance_pos, _procure_route, picked_sources_pos)

	if is_instance_valid(production_panel) and production_panel.has_method("set_drinks_procurement_state"):
		production_panel.set_drinks_procurement_state(_procure_selected_sources.size(), true, "")

func _build_air_route(entrance_pos: Vector2i, sources: Array[Vector2i]) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	route.append(entrance_pos)
	var cur := entrance_pos
	for src in sources:
		_append_air_segment(route, cur, src)
		cur = src
	return route

func _append_air_segment(route: Array[Vector2i], from_pos: Vector2i, to_pos: Vector2i) -> void:
	var x := from_pos.x
	var y := from_pos.y
	while x != to_pos.x:
		x += 1 if to_pos.x > x else -1
		route.append(Vector2i(x, y))
	while y != to_pos.y:
		y += 1 if to_pos.y > y else -1
		route.append(Vector2i(x, y))

func _build_road_route(state: GameState, entrance_pos: Vector2i, sources: Array[Vector2i]) -> Result:
	var road_graph = MapRuntimeClass.get_road_graph(state)
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

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
