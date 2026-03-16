extends "res://tools/manual_test_saves/builders/manual_test_save_map_support.gd"

func get_registry() -> Dictionary:
	return {
		"milestone_first_lower_prices": Callable(self, "_build_milestone_first_lower_prices"),
		"milestone_first_train": Callable(self, "_build_milestone_first_train"),
		"milestone_status_matrix": Callable(self, "_build_milestone_status_matrix"),
		"milestone_first_burger_marketed": Callable(self, "_build_milestone_first_burger_marketed"),
		"milestone_first_drink_marketed": Callable(self, "_build_milestone_first_drink_marketed"),
		"milestone_first_pizza_marketed": Callable(self, "_build_milestone_first_pizza_marketed"),
		"milestone_first_pay_20_salaries": Callable(self, "_build_milestone_first_pay_20_salaries"),
		"milestone_first_throw_away": Callable(self, "_build_milestone_first_throw_away"),
		"milestone_first_waitress": Callable(self, "_build_milestone_first_waitress"),
		"milestone_first_waitress_used": Callable(self, "_build_milestone_first_waitress_used"),
		"milestone_first_have_20": Callable(self, "_build_milestone_first_have_20"),
		"milestone_first_have_100": Callable(self, "_build_milestone_first_have_100"),
		"milestone_ketchup_sold_your_demand": Callable(self, "_build_milestone_ketchup_sold_your_demand"),
		"milestone_first_beer_sold": Callable(self, "_build_milestone_first_beer_sold"),
		"milestone_first_coffee_sold": Callable(self, "_build_milestone_first_coffee_sold"),
		"milestone_first_coke_sold": Callable(self, "_build_milestone_first_coke_sold"),
		"milestone_first_lemonade_sold": Callable(self, "_build_milestone_first_lemonade_sold"),
		"milestone_first_burger_sold": Callable(self, "_build_milestone_first_burger_sold"),
		"milestone_first_pizza_sold": Callable(self, "_build_milestone_first_pizza_sold"),
	}

func _build_milestone_first_burger_marketed(engine: GameEngine, _c: Dictionary) -> Result:
	return _build_milestone_demand_marked(engine, "burger")

func _build_milestone_first_drink_marketed(engine: GameEngine, _c: Dictionary) -> Result:
	return _build_milestone_demand_marked(engine, "soda")

func _build_milestone_first_pizza_marketed(engine: GameEngine, _c: Dictionary) -> Result:
	return _build_milestone_demand_marked(engine, "pizza")

func _build_milestone_demand_marked(engine: GameEngine, product: String) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv
	if product.is_empty():
		return Result.failure("product is empty")

	var state := engine.get_state()
	_force_turn_order(state)

	state.map = _build_billboard_map_for_demand_marked()
	_invalidate_road_graph(state)

	var board_number := 14
	var owner := 0
	var employee_type := "marketing_trainee"

	var take := StateUpdater.take_from_pool(state, employee_type, 1)
	if not take.ok:
		return Result.failure("take_from_pool(%s) failed: %s" % [employee_type, take.error])
	state.players[owner]["busy_marketers"] = [employee_type]

	state.marketing_instances = [{
		"board_number": board_number,
		"type": "billboard",
		"owner": owner,
		"employee_type": employee_type,
		"product": product,
		"world_pos": Vector2i(1, 2),
		"rotation": 0,
		"footprint_size": Vector2i(2, 1),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}]
	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": "billboard",
		"owner": owner,
		"product": product,
		"world_pos": Vector2i(1, 2),
		"rotation": 0,
		"footprint_size": Vector2i(2, 1),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}

	return Result.success()

func _build_milestone_first_pay_20_salaries(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv
	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "burger_cook", false, 4)
	if not ensure.ok:
		return ensure

	var grant := StateUpdater.player_receive_from_bank(state, actor, 50)
	if not grant.ok:
		return Result.failure("player_receive_from_bank failed: %s" % grant.error)

	return Result.success()

func _build_milestone_first_throw_away(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var p_val = state.players[0]
	if not (p_val is Dictionary):
		return Result.failure("player[0] is not Dictionary")
	var p: Dictionary = p_val
	var inv_val = p.get("inventory", null)
	if not (inv_val is Dictionary):
		return Result.failure("player[0].inventory is not Dictionary")
	var inv: Dictionary = inv_val
	inv["burger"] = 2
	inv["soda"] = 1
	p["inventory"] = inv
	state.players[0] = p

	return Result.success()

func _build_milestone_first_waitress(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var ensure := _ensure_employee(state, 0, "waitress", false, 1)
	if not ensure.ok:
		return ensure

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_waitress_used(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var ensure_w := _ensure_employee(state, 0, "waitress", false, 1)
	if not ensure_w.ok:
		return ensure_w
	var ensure_paid := _ensure_employee(state, 0, "burger_cook", false, 1)
	if not ensure_paid.ok:
		return ensure_paid

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_have_20(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "burger"}]
	houses["h0"] = h
	state.map["houses"] = houses
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["cash"] = 15

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_have_100(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "burger"}]
	houses["h0"] = h
	state.map["houses"] = houses
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["cash"] = 95

	return _mark_all_players_passed_for_working(state)

func _build_milestone_ketchup_sold_your_demand(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_ketchup(state)

	var houses: Dictionary = state.map["houses"]
	var house: Dictionary = houses["house_left"]
	house["demands"] = [{
		"product": "burger",
		"from_player": 0,
		"board_number": 11,
		"type": "billboard"
	}]
	houses["house_left"] = house
	state.map["houses"] = houses

	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 1

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_beer_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var ensure := _ensure_employee(state, 0, "burger_cook", false, 4)
	if not ensure.ok:
		return ensure

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "beer"}]
	houses["h0"] = h
	state.map["houses"] = houses

	var inv: Dictionary = state.players[0]["inventory"]
	inv["beer"] = 1
	inv["pizza"] = 2
	state.players[0]["inventory"] = inv
	state.players[0]["cash"] = 0

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_coffee_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	if state.players.size() < 3:
		return Result.failure("first_coffee_sold 需要至少 3 名玩家")
	_force_turn_order(state)
	_apply_test_map_first_coffee_sold(state)

	var houses: Dictionary = state.map["houses"]
	var house: Dictionary = houses["house_left"]
	house["demands"] = [{"product": "burger"}]
	houses["house_left"] = house
	state.map["houses"] = houses

	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 0
	state.players[2]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["coffee"] = 1
	state.players[2]["inventory"]["coffee"] = 1

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_coke_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "soda"}]
	houses["h0"] = h
	state.map["houses"] = houses

	var inv: Dictionary = state.players[0]["inventory"]
	inv["soda"] = 12
	state.players[0]["inventory"] = inv

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_lemonade_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "lemonade"}]
	houses["h0"] = h
	state.map["houses"] = houses

	state.players[0]["inventory"]["lemonade"] = 1

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_burger_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "burger"}]
	houses["h0"] = h
	state.map["houses"] = houses

	state.players[0]["inventory"]["burger"] = 1

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_pizza_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_pizza_sale(state)

	var inv: Dictionary = state.players[0]["inventory"]
	inv["pizza"] = 3
	state.players[0]["inventory"] = inv

	var houses: Dictionary = state.map["houses"]
	for hid in ["h1", "h2", "h3"]:
		var h: Dictionary = houses[hid]
		h["demands"] = [{"product": "pizza"}]
		houses[hid] = h
	state.map["houses"] = houses

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_lower_prices(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	state.sub_phase = "Recruit"
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var take := StateUpdater.take_from_pool(state, "pricing_manager", 1)
	if not take.ok:
		return Result.failure("take_from_pool(pricing_manager) failed: %s" % take.error)
	var add := StateUpdater.add_employee(state, actor, "pricing_manager", false)
	if not add.ok:
		return Result.failure("add_employee(pricing_manager) failed: %s" % add.error)

	return Result.success({
		"suggested_command": {
			"action_id": "set_price",
			"actor": actor,
			"params": {},
		}
	})

func _build_milestone_first_train(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var to_train := TestPhaseUtils.advance_until_working_sub_phase(engine, "Train", 30)
	if not to_train.ok:
		engine.get_state().sub_phase = "Train"

	var state := engine.get_state()
	_force_turn_order(state)
	state.sub_phase = "Train"
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	# 1) 准备 trainer（提供 train_limit）
	var take_trainer := StateUpdater.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("take_from_pool(trainer) failed: %s" % take_trainer.error)
	var add_trainer := StateUpdater.add_employee(state, actor, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("add_employee(trainer) failed: %s" % add_trainer.error)

	# 2) 准备待培训员工：放在 reserve_employees
	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var from_employee := str(params.get("from_employee", "management_trainee")).strip_edges()
	var to_employee := str(params.get("to_employee", "new_business_developer")).strip_edges()
	if from_employee.is_empty() or to_employee.is_empty():
		return Result.failure("builder_params.from_employee/to_employee is empty")

	var take_from := StateUpdater.take_from_pool(state, from_employee, 1)
	if not take_from.ok:
		return Result.failure("take_from_pool(%s) failed: %s" % [from_employee, take_from.error])
	var add_from := StateUpdater.add_employee(state, actor, from_employee, true)
	if not add_from.ok:
		return Result.failure("add_employee(%s,reserve) failed: %s" % [from_employee, add_from.error])

	# 目标员工需要在池中存在（train.validate 会检查）
	if int(state.employee_pool.get(to_employee, 0)) <= 0:
		return Result.failure("employee_pool has no %s (required for training)" % to_employee)

	return Result.success({
		"suggested_command": {
			"action_id": "train",
			"actor": actor,
			"params": {
				"from_employee": from_employee,
				"to_employee": to_employee,
			},
		}
	})

func _build_milestone_status_matrix(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：一次存档覆盖三态（可获得/不可获得/已获得）+ 拥有者图标 + 过期提示。
	# - 使用 hard_choices：为部分里程碑注入 expires_at
	# - 设置 round=3：expires_at=2 的里程碑应显示“已过期”，expires_at=3 的里程碑显示“剩余 0 回合”
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	if not MilestoneRegistry.is_loaded():
		return Result.failure("MilestoneRegistry is not loaded (module setup failed?)")

	var state := engine.get_state()
	_force_turn_order(state)
	state.sub_phase = "Recruit"
	state.round_number = 3

	if state.players.size() < 2:
		return Result.failure("milestone_status_matrix requires at least 2 players")

	var obtained_id := "first_billboard"
	var owned_but_obtainable_id := "first_burger_produced"
	var expiring_id := "first_hire_3" # hard_choices: expires_at=3
	var expired_ids: Array[String] = [
		"first_burger_marketed",
		"first_pizza_marketed",
		"first_drink_marketed",
		"first_train",
	]

	var must_exist: Array[String] = []
	must_exist.append_array(expired_ids)
	must_exist.append_array([obtained_id, owned_but_obtainable_id, expiring_id])
	for mid in must_exist:
		if not MilestoneRegistry.has(mid):
			return Result.failure("milestone id not found in registry: %s" % mid)

	# 1) 过期且不可获得：从池中移除这些里程碑，且不授予任何玩家。
	var remove_set := {}
	for mid2 in expired_ids:
		remove_set[mid2] = true

	var remaining_pool: Array[String] = []
	for v in Array(state.milestone_pool):
		var mid3 := str(v).strip_edges()
		if mid3.is_empty():
			continue
		if remove_set.has(mid3):
			continue
		remaining_pool.append(mid3)
	state.milestone_pool = remaining_pool

	# 2) 已获得：玩家0 拥有，且从池中移除 -> “已获得（浅绿色背景）”
	var p0 := state.get_player(0)
	if not (p0.get("milestones", []) is Array):
		p0["milestones"] = []
	var p0_ms: Array = p0.get("milestones", [])
	if not p0_ms.has(obtained_id):
		p0_ms.append(obtained_id)
	p0["milestones"] = p0_ms
	state.players[0] = p0

	var pool2: Array[String] = []
	for v2 in Array(state.milestone_pool):
		var mid4 := str(v2).strip_edges()
		if mid4.is_empty():
			continue
		if mid4 == obtained_id:
			continue
		pool2.append(mid4)
	state.milestone_pool = pool2

	# 3) 可获得但已有拥有者：玩家1 拥有，但池中保留 -> “可获得（浅绿色边框）” + 右下角 icon
	var p1 := state.get_player(1)
	if not (p1.get("milestones", []) is Array):
		p1["milestones"] = []
	var p1_ms: Array = p1.get("milestones", [])
	if not p1_ms.has(owned_but_obtainable_id):
		p1_ms.append(owned_but_obtainable_id)
	p1["milestones"] = p1_ms
	state.players[1] = p1

	# 4) 过期提示（非过期）：hard_choices 的 first_hire_3 在 round=3 应显示 “剩余 0 回合”
	#	确保仍在池中（若缺失则追加 1 个以便验收）。
	if not state.milestone_pool.has(expiring_id):
		state.milestone_pool.append(expiring_id)

	return Result.success()
