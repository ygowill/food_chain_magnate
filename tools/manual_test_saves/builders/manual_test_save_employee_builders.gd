extends "res://tools/manual_test_saves/builders/manual_test_save_builder_support.gd"

func get_registry() -> Dictionary:
	return {
		"employee_produce_food_fixed": Callable(self, "_build_employee_produce_food_fixed"),
		"employee_kitchen_trainee_get_food": Callable(self, "_build_employee_kitchen_trainee_get_food"),
		"employee_restructuring_showcase": Callable(self, "_build_employee_restructuring_showcase"),
		"employee_train_panel_refresh": Callable(self, "_build_employee_train_panel_refresh"),
		"employee_payday_fire_panel_refresh": Callable(self, "_build_employee_payday_fire_panel_refresh"),
		"employee_waitress_tips": Callable(self, "_build_employee_waitress_tips"),
		"employee_cfo_bonus_on_tips": Callable(self, "_build_employee_cfo_bonus_on_tips"),
		"employee_kimchi_master_cleanup": Callable(self, "_build_employee_kimchi_master_cleanup"),
		"employee_fry_chef_dinnertime_bonus": Callable(self, "_build_employee_fry_chef_dinnertime_bonus"),
		"employee_movie_star_order_of_business": Callable(self, "_build_employee_movie_star_order_of_business"),
		"employee_mass_marketeer_marketing_rounds": Callable(self, "_build_employee_mass_marketeer_marketing_rounds"),
		"employee_procure_drinks_errand_boy": Callable(self, "_build_employee_procure_drinks_errand_boy"),
		"employee_procure_drinks_route": Callable(self, "_build_employee_procure_drinks_route"),
		"employee_initiate_marketing": Callable(self, "_build_employee_initiate_marketing"),
		"employee_marketing_trainee_billboard": Callable(self, "_build_employee_marketing_trainee_billboard"),
		"employee_mandatory_action": Callable(self, "_build_employee_mandatory_action"),
		"employee_recruit_capacity": Callable(self, "_build_employee_recruit_capacity"),
		"employee_train_once": Callable(self, "_build_employee_train_once"),
		"employee_rural_marketeer_giant_billboard": Callable(self, "_build_employee_rural_marketeer_giant_billboard"),
		"employee_night_shift_manager_double_action": Callable(self, "_build_employee_night_shift_manager_double_action"),

		# milestone wrappers (reuse employee builders)
		"milestone_first_airplane": Callable(self, "_build_milestone_first_airplane"),
		"milestone_first_billboard": Callable(self, "_build_milestone_first_billboard"),
		"milestone_first_radio": Callable(self, "_build_milestone_first_radio"),
		"milestone_first_burger_produced": Callable(self, "_build_milestone_first_burger_produced"),
		"milestone_first_pizza_produced": Callable(self, "_build_milestone_first_pizza_produced"),
		"milestone_first_hire_3": Callable(self, "_build_milestone_first_hire_3"),
		"milestone_first_cart_operator": Callable(self, "_build_milestone_first_cart_operator"),
		"milestone_first_errand_boy": Callable(self, "_build_milestone_first_errand_boy"),
		"milestone_first_rural_marketeer_used": Callable(self, "_build_milestone_first_rural_marketeer_used"),
		"milestone_first_marketing_trainee_used": Callable(self, "_build_milestone_first_marketing_trainee_used"),
		"milestone_first_campaign_manager_used": Callable(self, "_build_milestone_first_campaign_manager_used"),
		"milestone_first_brand_manager_used": Callable(self, "_build_milestone_first_brand_manager_used"),
		"milestone_first_brand_director_used": Callable(self, "_build_milestone_first_brand_director_used"),
		"milestone_first_marketeer_used": Callable(self, "_build_milestone_first_marketeer_used"),
		"milestone_first_trainer_used": Callable(self, "_build_milestone_first_trainer_used"),
		"milestone_first_recruiting_girl_used": Callable(self, "_build_milestone_first_recruiting_girl_used"),
		"milestone_first_discount_manager_used": Callable(self, "_build_milestone_first_discount_manager_used"),
		"milestone_first_cart_operator_used": Callable(self, "_build_milestone_first_cart_operator_used"),
	}

func _build_employee_kitchen_trainee_get_food(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetFood")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "kitchen_trainee", false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({})

func _build_employee_restructuring_showcase(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Restructuring")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var to_reserve := bool(params.get("to_reserve", true))
	var count := int(params.get("count", 1))
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	if count <= 0:
		count = 1

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, to_reserve, count)
	if not ensure.ok:
		return ensure

	return Result.success()

func _build_employee_train_panel_refresh(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Train")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_trainers := _ensure_employee(state, actor, "trainer", false, 2)
	if not ensure_trainers.ok:
		return ensure_trainers

	var ensure_marketing_trainee := _ensure_employee(state, actor, "marketing_trainee", true, 1)
	if not ensure_marketing_trainee.ok:
		return ensure_marketing_trainee

	var ensure_management_trainee := _ensure_employee(state, actor, "management_trainee", true, 1)
	if not ensure_management_trainee.ok:
		return ensure_management_trainee

	if not (state.employee_pool is Dictionary) or int(state.employee_pool.get("campaign_manager", 0)) <= 0:
		return Result.failure("employee_pool has no campaign_manager (required for training)")

	return Result.success({
		"scenario": [
			"玩家 0 有 2 张 trainer，第一次培训后 Train 子阶段仍会停留在当前面板，便于观察可用员工列表是否即时刷新。",
			"待命区同时放入 marketing_trainee 与 management_trainee；推荐先培训前者，这样刷新后应只剩 management_trainee 可继续培训。",
			"training 成功后，新得到的 campaign_manager 本回合不应立刻再次作为培训来源出现，否则就会错误允许同一员工继续被重复培训。",
		],
		"suggested_command": {
			"action_id": "train",
			"actor": actor,
			"params": {
				"from_employee": "marketing_trainee",
				"to_employee": "campaign_manager",
			},
		},
	})

func _build_employee_payday_fire_panel_refresh(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_active_waitress := _ensure_employee(state, actor, "waitress", false, 1)
	if not ensure_active_waitress.ok:
		return ensure_active_waitress

	var ensure_reserve_trainer := _ensure_employee(state, actor, "trainer", true, 1)
	if not ensure_reserve_trainer.ok:
		return ensure_reserve_trainer

	state.players[actor]["cash"] = 42

	return Result.success({
		"scenario": [
			"Payday 面板同时存在一名在岗 waitress 与一名待命 trainer，解雇后仍保留至少一个列表项，便于确认面板是即时刷新而不是整面板关闭/重开。",
			"waitress 需要薪水、trainer 不需要薪水，因此解雇 waitress 后，员工列表和薪资汇总都会立刻变化，适合人工复核。",
		],
		"suggested_command": {
			"action_id": "fire",
			"actor": actor,
			"params": {
				"employee_id": "waitress",
				"location": "active",
			},
		},
	})

func _build_employee_waitress_tips(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：验证 waitress 在晚餐阶段提供固定小费（默认 $3），无需依赖售卖发生。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "waitress", false, 1)
	if not ensure.ok:
		return ensure

	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _build_employee_cfo_bonus_on_tips(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：用“waitress tips”制造 base_gain，避免额外构造售卖场景；
	# 这样 CFO 的 +50%（向上取整）会稳定触发：ceil(3 * 50%) = 2。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	# 让双方都有 waitress（都获得 $3 tips），仅玩家 0 有 CFO（额外获得 $2）。
	for pid in range(state.players.size()):
		var ensure_w := _ensure_employee(state, pid, "waitress", false, 1)
		if not ensure_w.ok:
			return ensure_w

	var ensure_cfo := _ensure_employee(state, 0, "cfo", false, 1)
	if not ensure_cfo.ok:
		return ensure_cfo

	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _build_employee_kimchi_master_cleanup(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：验证 Cleanup 丢弃食物后 kimchi_master 自动产出 1 个 kimchi 并保留到下一阶段。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "kimchi_master", false, 1)
	if not ensure.ok:
		return ensure

	# 构造“会被丢弃”的食物库存：不设置需求，确保晚餐不会消耗。
	var inv := _exec_system(engine, "debug_add_inventory", {
		"player_id": actor,
		"product": "burger",
		"amount": 1,
	})
	if not inv.ok:
		return inv

	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _build_employee_fry_chef_dinnertime_bonus(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：构造“玩家 0 卖出 1 个房屋”的局面，验证 fry_chef 会为该房屋结算额外 +$10（按房屋算）。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var ensure := _ensure_employee(state, 0, "fry_chef", false, 1)
	if not ensure.ok:
		return ensure

	var rid0_r := _get_player_first_restaurant_id(state, 0)
	if not rid0_r.ok:
		return rid0_r
	var rid1_r := _get_player_first_restaurant_id(state, 1)
	if not rid1_r.ok:
		return rid1_r
	var rid0: String = rid0_r.value
	var rid1: String = rid1_r.value

	if not (state.map is Dictionary):
		return Result.failure("state.map is not a Dictionary")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("state.map.grid_size missing or invalid")
	var grid_size: Vector2i = state.map["grid_size"]

	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants missing or invalid")
	var restaurants: Dictionary = state.map["restaurants"]
	if not restaurants.has(rid0) or not restaurants.has(rid1):
		return Result.failure("restaurants missing player restaurant ids")
	if not (restaurants[rid0] is Dictionary) or not (restaurants[rid1] is Dictionary):
		return Result.failure("restaurants[%s/%s] invalid type" % [rid0, rid1])
	var rest0: Dictionary = restaurants[rid0]
	var rest1: Dictionary = restaurants[rid1]

	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("state.map.houses missing or invalid")
	var houses: Dictionary = state.map["houses"]
	var house_ids: Array[String] = []
	for k in houses.keys():
		if k is String:
			house_ids.append(str(k))
	house_ids.sort()
	if house_ids.is_empty():
		return Result.failure("no houses on map")

	var road_graph = _get_road_graph(state)
	if road_graph == null:
		return Result.failure("road_graph is null")

	var house0 := ""
	for hid in house_ids:
		if not (houses[hid] is Dictionary):
			continue
		var house: Dictionary = houses[hid]
		var d0_r := _get_distance_rest_to_house(road_graph, state, grid_size, rid0, rest0, hid, house)
		if not d0_r.ok:
			continue
		var d1_r := _get_distance_rest_to_house(road_graph, state, grid_size, rid1, rest1, hid, house)
		if not d1_r.ok:
			continue
		var d0 := int(d0_r.value)
		var d1 := int(d1_r.value)
		if d0 >= 0 and d1 >= 0 and d0 < d1:
			house0 = hid
			break

	if house0.is_empty():
		return Result.failure("cannot find a house where player 0 is strictly closer")

		# 1) 放 1 个 burger 需求（用于稳定触发 fry_chef 房屋售卖奖励）
	var dem0 := _exec_system(engine, "debug_add_house_demand", {"house_id": house0, "product": "burger", "amount": 1})
	if not dem0.ok:
		return dem0

	# 2) 给玩家 0 1 个 burger 库存（避免因缺货导致需求无法满足）
	var inv0 := _exec_system(engine, "debug_add_inventory", {"player_id": 0, "product": "burger", "amount": 1})
	if not inv0.ok:
		return inv0

	# 3) 推进到 Payday（中间会自动结算 Dinnertime/Marketing/Cleanup）
	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _build_employee_movie_star_order_of_business(engine: GameEngine, c: Dictionary) -> Result:
	# 目标：让“无电影明星时应由玩家 1 先选顺序”的局面，在拥有 movie_star_* 后被强制改为玩家 0 优先。
	var to_restructuring := _advance_to_phase(engine, "Restructuring")
	if not to_restructuring.ok:
		return to_restructuring

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var star_id := str(params.get("star_id", "movie_star_d")).strip_edges()
	if star_id.is_empty():
		return Result.failure("builder_params.star_id is empty")

	var state := engine.get_state()
	_force_turn_order(state)

	# 玩家 0：movie_star + 2 张填充员工，使 empty_slots 降到 0（CEO slots=3）
	var ensure_star := _ensure_employee(state, 0, star_id, false, 1)
	if not ensure_star.ok:
		return ensure_star
	var ensure_fill_1 := _ensure_employee(state, 0, "kitchen_trainee", false, 1)
	if not ensure_fill_1.ok:
		return ensure_fill_1
	var ensure_fill_2 := _ensure_employee(state, 0, "marketing_trainee", false, 1)
	if not ensure_fill_2.ok:
		return ensure_fill_2

	# 推进到 OrderOfBusiness：注意不要覆盖 turn_order/selection_order（这里不调用 _force_turn_order）
	var to_oob := TestPhaseUtils.advance_until_phase(engine, "OrderOfBusiness", 80)
	if not to_oob.ok:
		return to_oob
	if str(engine.get_state().phase) != "OrderOfBusiness":
		return Result.failure("expected OrderOfBusiness, got: %s" % str(engine.get_state().phase))

	return Result.success()

func _build_employee_mass_marketeer_marketing_rounds(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：验证 mass_marketeer 会把当回合的 marketing_rounds 从 1 提升为 1 + 在岗数量。
	# 这里用 marketing_trainee 放置 1 个 billboard，便于手工观察“需求增加次数=2”。
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_mm := _ensure_employee(state, actor, "mass_marketeer", false, 1)
	if not ensure_mm.ok:
		return ensure_mm
	var ensure_mt := _ensure_employee(state, actor, "marketing_trainee", false, 1)
	if not ensure_mt.ok:
		return ensure_mt

	var find := _find_first_valid_initiate_marketing(engine, actor, "marketing_trainee", 14, "burger", 1)
	if not find.ok:
		return find

	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_marketing_trainee_billboard(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "marketing_trainee", false, 1)
	if not ensure.ok:
		return ensure

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var board_number := int(params.get("board_number", 14))
	var product := str(params.get("product", "burger")).strip_edges()
	var duration := int(params.get("duration", 1))
	var find := _find_first_valid_initiate_marketing(engine, actor, "marketing_trainee", board_number, product, duration)
	if not find.ok:
		return find

	return Result.success({
		"suggested_command": find.value
	})

func _find_first_valid_initiate_marketing(engine: GameEngine, actor: int, employee_type: String, board_number: int, product: String, duration: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("initiate_marketing")
	if ex == null:
		return Result.failure("cannot find executor: initiate_marketing")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("initiate_marketing", actor, {
					"employee_type": employee_type,
					"board_number": board_number,
					"product": product,
					"duration": duration,
					"position": [x, y],
					"rotation": int(rot),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "initiate_marketing",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})

	return Result.failure("no valid initiate_marketing placement found (board=%d product=%s)" % [board_number, product])

func _build_employee_produce_food_fixed(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetFood")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({
		"suggested_command": {
			"action_id": "produce_food",
			"actor": actor,
			"params": {
				"employee_type": employee_type,
			},
		}
	})

func _build_employee_procure_drinks_errand_boy(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetDrinks")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "errand_boy", false, 1)
	if not ensure.ok:
		return ensure

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var drink_type := str(params.get("drink_type", "soda")).strip_edges()
	if drink_type.is_empty():
		drink_type = "soda"

	return Result.success({
		"suggested_command": {
			"action_id": "procure_drinks",
			"actor": actor,
			"params": {
				"employee_type": "errand_boy",
				"drink_type": drink_type,
			},
		}
	})

func _build_employee_procure_drinks_route(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetDrinks")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	# 采购路线/来源由 UI 交互生成（route/selected_sources），这里不强行指定参数，避免误导。
	return Result.success()

func _build_employee_initiate_marketing(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	var board_number := int(params.get("board_number", 14))
	var product := str(params.get("product", "burger")).strip_edges()
	var duration := int(params.get("duration", 1))

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_initiate_marketing(engine, actor, employee_type, board_number, product, duration)
	if not find.ok:
		return find

	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_mandatory_action(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var action_id := str(params.get("action_id", "")).strip_edges()
	if employee_type.is_empty() or action_id.is_empty():
		return Result.failure("builder_params.employee_type/action_id is empty")

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({
		"suggested_command": {
			"action_id": action_id,
			"actor": actor,
			"params": {},
		}
	})

func _build_employee_recruit_capacity(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Recruit")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	var recruit_target := str(params.get("recruit_target", "waitress")).strip_edges()
	if recruit_target.is_empty():
		recruit_target = "waitress"

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({
		"suggested_command": {
			"action_id": "recruit",
			"actor": actor,
			"params": {
				"employee_type": recruit_target,
			},
		}
	})

func _build_employee_train_once(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Train")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var trainer_type := str(params.get("trainer_type", "trainer")).strip_edges()
	var from_employee := str(params.get("from_employee", "management_trainee")).strip_edges()
	var to_employee := str(params.get("to_employee", "new_business_developer")).strip_edges()
	if trainer_type.is_empty() or from_employee.is_empty() or to_employee.is_empty():
		return Result.failure("builder_params trainer_type/from_employee/to_employee is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_trainer := _ensure_employee(state, actor, trainer_type, false, 1)
	if not ensure_trainer.ok:
		return ensure_trainer

	var ensure_from := _ensure_employee(state, actor, from_employee, true, 1)
	if not ensure_from.ok:
		return ensure_from

	# 目标员工需要在池中存在（train.validate 会检查）
	if not (state.employee_pool is Dictionary) or int(state.employee_pool.get(to_employee, 0)) <= 0:
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

func _build_employee_rural_marketeer_giant_billboard(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "rural_marketeer", false, 1)
	if not ensure.ok:
		return ensure

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var side := str(params.get("side", "N")).strip_edges()
	if side.is_empty():
		side = "N"
	var product := str(params.get("product", "burger")).strip_edges()
	if product.is_empty():
		product = "burger"

	return Result.success({
		"suggested_command": {
			"action_id": "place_giant_billboard",
			"actor": actor,
			"params": {
				"side": side,
				"product": product,
			},
		}
	})

func _build_employee_night_shift_manager_double_action(engine: GameEngine, c: Dictionary) -> Result:
	# 目标：验证夜班经理让“免薪员工”本子阶段可用次数 *2（最简单：kitchen_trainee produce_food 两次）
	var adv := _advance_to_working_sub_phase(engine, "GetFood")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_nsm := _ensure_employee(state, actor, "night_shift_manager", false, 1)
	if not ensure_nsm.ok:
		return ensure_nsm

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var target_employee := str(params.get("target_employee", "kitchen_trainee")).strip_edges()
	if target_employee.is_empty():
		target_employee = "kitchen_trainee"
	var ensure_target := _ensure_employee(state, actor, target_employee, false, 1)
	if not ensure_target.ok:
		return ensure_target

	# 手工复核存档构造：由于 auto_advance 会在“无可做动作的子阶段”自动跳过，
	# 上面的 _advance_to_working_sub_phase() 可能在添加员工前就错过 GetFood；
	# 同时夜班经理的 multipliers 在进入 Working 时写入，需要在这里补一次。
	var apply := _apply_night_shift_managers_working_multipliers(state)
	if not apply.ok:
		return apply

	return Result.success({
		"suggested_command": {
			"action_id": "produce_food",
			"actor": actor,
			"params": {
				"employee_type": target_employee,
				# multi-produce 的员工需要 food_type；留空会在 validate 阶段提示测试者选择。
			},
		}
	})

func _apply_night_shift_managers_working_multipliers(state: GameState) -> Result:
	# 复用模块实现逻辑，确保手工存档与真实运行时一致。
	var script = load("res://modules/night_shift_managers/rules/entry.gd")
	if script == null:
		return Result.failure("cannot load night_shift_managers rules entry.gd")
	var rules = script.new()
	if rules == null or not rules.has_method("_on_working_before_enter"):
		return Result.failure("night_shift_managers rules script missing _on_working_before_enter")
	var r = rules._on_working_before_enter(state)
	if r is Result:
		return r
	return Result.failure("night_shift_managers._on_working_before_enter returned non-Result: %s" % str(r))

func _build_milestone_first_airplane(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_billboard(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_radio(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_burger_produced(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_produce_food_fixed(engine, c)

func _build_milestone_first_pizza_produced(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_produce_food_fixed(engine, c)

func _build_milestone_first_hire_3(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_recruit_capacity(engine, c)

func _build_milestone_first_cart_operator(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_procure_drinks_route(engine, c)

func _build_milestone_first_errand_boy(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_procure_drinks_errand_boy(engine, c)

func _build_milestone_first_rural_marketeer_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_rural_marketeer_giant_billboard(engine, c)

func _build_milestone_first_marketing_trainee_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_campaign_manager_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_brand_manager_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_brand_director_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_marketeer_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_trainer_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_train_once(engine, c)

func _build_milestone_first_recruiting_girl_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_recruit_capacity(engine, c)

func _build_milestone_first_discount_manager_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_mandatory_action(engine, c)

func _build_milestone_first_cart_operator_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_procure_drinks_route(engine, c)
