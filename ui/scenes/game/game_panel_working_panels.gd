# Game scene：Working 阶段面板（Recruit/Train/Price/Production/Milestone）
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const RecruitPanelScene = preload("res://ui/components/recruit_panel/recruit_panel.tscn")
const TrainPanelScene = preload("res://ui/components/train_panel/train_panel.tscn")
const PricePanelScene = preload("res://ui/components/price_panel/price_setting_panel.tscn")
const ProductionPanelScene = preload("res://ui/components/production_panel/production_panel.tscn")
const MilestonePanelScene = preload("res://ui/components/milestone_panel/milestone_panel.tscn")

var _scene = null
var _execute_command: Callable
var _hide_all: Callable
var _center_popup: Callable
var _overlay_controller = null

var recruit_panel = null
var train_panel = null
var price_panel = null
var production_panel = null
var milestone_panel = null

func _init(scene, execute_command: Callable, hide_all: Callable, center_popup: Callable, overlay_controller = null) -> void:
	_scene = scene
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup
	_overlay_controller = overlay_controller

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
		recruit_panel.recruit_requested.connect(_on_recruit_requested)
		_scene.add_child(recruit_panel)

	var state = _scene.game_engine.get_state()

	if recruit_panel.has_method("set_employee_pool"):
		recruit_panel.set_employee_pool(state.employee_pool)

	if recruit_panel.has_method("set_recruit_count"):
		var actor = state.get_current_player_id()
		var counts := _compute_recruit_counts(state, actor)
		recruit_panel.set_recruit_count(int(counts.remaining), int(counts.total))

	recruit_panel.visible = true
	if _center_popup.is_valid():
		_center_popup.call(recruit_panel)

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

	train_panel.visible = true
	if _center_popup.is_valid():
		_center_popup.call(train_panel)

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
				price_panel.set_mode("price")
			"set_luxury_price":
				price_panel.set_mode("luxury")
			"set_discount":
				price_panel.set_mode("discount")

	if price_panel.has_method("set_current_prices"):
		var prices: Dictionary = current_player.get("prices", {})
		price_panel.set_current_prices(prices)

	price_panel.visible = true
	if _center_popup.is_valid():
		_center_popup.call(price_panel)

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
		if production_panel.has_signal("production_requested"):
			production_panel.production_requested.connect(_on_production_requested)
		if production_panel.has_signal("producer_changed"):
			production_panel.producer_changed.connect(_on_producer_changed)
		if production_panel.has_signal("cancelled"):
			production_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(production_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if production_panel.has_method("set_production_type"):
		production_panel.set_production_type(production_type)

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

	production_panel.visible = true
	if _center_popup.is_valid():
		_center_popup.call(production_panel)

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
		if milestone_panel.has_signal("cancelled"):
			milestone_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(milestone_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if milestone_panel.has_method("set_milestone_pool"):
		milestone_panel.set_milestone_pool(state.milestone_pool)
	if milestone_panel.has_method("set_player_milestones"):
		milestone_panel.set_player_milestones(current_player.get("milestones", []))

	milestone_panel.visible = true
	if _center_popup.is_valid():
		_center_popup.call(milestone_panel)

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
	var result: Result = _execute_command.call(Command.create(action_id, current_player_id, {
		"employee_type": employee_type
	}))

	if result.ok:
		if is_instance_valid(production_panel):
			var state = _scene.game_engine.get_state()
			var current_player: Dictionary = state.get_current_player()
			if production_panel.has_method("set_current_inventory"):
				production_panel.set_current_inventory(current_player.get("inventory", {}))

func _on_producer_changed(employee_type: String, product_type: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if product_type != "drinks":
		_hide_procurement_route_overlay()
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	if state.phase != "Working" or state.sub_phase != "GetDrinks":
		_hide_procurement_route_overlay()
		return
	if employee_type.is_empty():
		_hide_procurement_route_overlay()
		return
	_preview_procurement_route(state, employee_type)

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

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
