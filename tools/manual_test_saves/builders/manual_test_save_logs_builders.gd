extends "res://tools/manual_test_saves/builders/manual_test_save_placement_support.gd"

func get_registry() -> Dictionary:
	return {
		"logs_event_review": Callable(self, "_build_logs_event_review"),
		"logs_employee_recruit_train": Callable(self, "_build_logs_employee_recruit_train"),
		"logs_employee_fire": Callable(self, "_build_logs_employee_fire"),
		"logs_build_and_move": Callable(self, "_build_logs_build_and_move"),
		"logs_produce_and_cleanup": Callable(self, "_build_logs_produce_and_cleanup"),
		"logs_dinnertime_sale": Callable(self, "_build_logs_dinnertime_sale"),
		"logs_game_over_bankruptcy": Callable(self, "_build_logs_game_over_bankruptcy"),
	}

func _build_logs_event_review(engine: GameEngine, _c: Dictionary) -> Result:
	# Logs review case:
	# - Build a small "ready-to-run" initial state (restaurants/houses/employees), then freeze as initial_state.
	# - Execute a short command history to generate EventBus.history (marketing demand + drinks procure route),
	#   so loading the archive replays and populates the log panel for manual inspection.
	var adv := _advance_to_working_sub_phase(engine, "PlaceHouses")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	# Ensure employees needed for pre-setup (place_house) and log-generating commands.
	# place_house 与 add_garden 共享 house_placement_counts，需 >=2 次数才能在同一 PlaceHouses 子阶段做两步。
	var ensure_house := _ensure_employee(state, actor, "new_business_developer", false, 2)
	if not ensure_house.ok:
		return ensure_house
	var ensure_marketer := _ensure_employee(state, actor, "brand_director", false, 1)
	if not ensure_marketer.ok:
		return ensure_marketer
	var ensure_procure := _ensure_employee(state, actor, "zeppelin_pilot", false, 1)
	if not ensure_procure.ok:
		return ensure_procure

	# Ensure Payday can resolve even with salary employees in this scenario.
	# Use the debug system command to inject reserve (keeps cash invariants via reserve_added_total).
	for pid in range(state.players.size()):
		var give := engine.execute_command(Command.create_system("debug_give_money", {"player_id": pid, "amount": 50}))
		if not give.ok:
			return Result.failure("debug_give_money failed: %s" % give.error)

	# Place at least one house so marketing settlement will generate demand + affected house numbers.
	var numbers := _get_remaining_house_numbers_from_state(state)
	if numbers.is_empty():
		return Result.failure("no remaining house numbers")

	var placed_house_numbers: Array[int] = []
	var want := mini(2, numbers.size())
	for i in range(want):
		var house_number := int(numbers[i])
		var find := _find_first_valid_place_house(engine, actor, house_number)
		if not find.ok:
			continue
		var info: Dictionary = find.value if (find.value is Dictionary) else {}
		var params: Dictionary = info.get("params", {}) if (info.get("params", null) is Dictionary) else {}
		params["employee_type"] = "new_business_developer"
		var exec := engine.execute_command(Command.create("place_house", actor, params))
		if not exec.ok:
			return Result.failure("place_house failed: %s" % exec.error)
		placed_house_numbers.append(house_number)

	if placed_house_numbers.is_empty():
		return Result.failure("failed to place any house for logs review")

	# Prepare initial state at Working/Marketing (so replay starts from a meaningful interactive moment).
	state = engine.get_state()
	_force_turn_order(state)
	state.sub_phase = "Marketing"

	# Freeze here: we want houses/restaurants/employees in archive.initial_state,
	# but we want to keep the upcoming command history for replay/log verification.
	_freeze_engine_as_initial(engine)

	# === Commands to generate logs ===
	# 1) Place a radio marketing that affects at least one of the placed houses.
	var mk_cmd_r := _logs_find_radio_marketing_command_affecting_houses(
		engine, actor, "brand_director", 1, "burger", 1
	)
	if not mk_cmd_r.ok:
		return mk_cmd_r
	var mk_cmd: Command = mk_cmd_r.value
	var mk_exec := engine.execute_command(mk_cmd)
	if not mk_exec.ok:
		return Result.failure("initiate_marketing failed: %s" % mk_exec.error)

	# 2) Advance to GetDrinks and procure drinks with an explicit route + selected_sources.
	var to_get_drinks := TestPhaseUtils.advance_until_working_sub_phase(engine, "GetDrinks", 40)
	if not to_get_drinks.ok:
		return to_get_drinks

	var procure_cmd_r := _logs_find_zeppelin_procure_drinks_command(engine, actor)
	if not procure_cmd_r.ok:
		return procure_cmd_r
	var procure_cmd: Command = procure_cmd_r.value
	var procure_exec := engine.execute_command(procure_cmd)
	if not procure_exec.ok:
		return Result.failure("procure_drinks failed: %s" % procure_exec.error)

	# Sanity (before Dinnertime might consume inventory): procure_drinks should add at least one drink.
	var state_after_procure := engine.get_state()
	var player_after := state_after_procure.get_player(actor)
	var inv_after_val = player_after.get("inventory", null)
	if not (inv_after_val is Dictionary):
		return Result.failure("procure_drinks succeeded but player.inventory is missing/invalid")
	var inv_after: Dictionary = inv_after_val
	var has_drink_after := false
	for k_after in inv_after.keys():
		if not (k_after is String):
			continue
		var amount_after_val = inv_after.get(k_after, null)
		if not (amount_after_val is int):
			continue
		var amount_after: int = int(amount_after_val)
		if amount_after <= 0:
			continue
		if ProductRegistry.is_drink(str(k_after)):
			has_drink_after = true
			break
	if not has_drink_after:
		return Result.failure("procure_drinks did not add any drinks (inventory still has no drinks)")

	# 3) Complete Working to trigger Marketing settlement (auto-skipped) and DEMAND_GENERATED events.
	var done := TestPhaseUtils.complete_working_phase(engine, 200)
	if not done.ok:
		return done
	# Marketing happens after Payday (phase order: ... -> Payday -> Marketing -> Cleanup -> Restructuring).
	# Advance to the next stable phase so the settlement actually runs during replay.
	var to_restructuring := TestPhaseUtils.advance_until_phase(engine, "Restructuring", 200)
	if not to_restructuring.ok:
		return to_restructuring

	# Sanity (no autoload singletons in `--script` mode): ensure marketing created at least one demand
	# and procure_drinks actually added some inventory.
	state = engine.get_state()
	var any_demand := false
	var houses_val2 = state.map.get("houses", null) if (state.map is Dictionary) else null
	if houses_val2 is Dictionary:
		for h2_val in (houses_val2 as Dictionary).values():
			if not (h2_val is Dictionary):
				continue
			var h2: Dictionary = h2_val
			var demands_val = h2.get("demands", null)
			if demands_val is Array and not (demands_val as Array).is_empty():
				any_demand = true
				break
	if not any_demand:
		return Result.failure("logs case did not generate any house demands (marketing settlement may not have run)")

	return Result.success({
		"placed_house_numbers": placed_house_numbers,
	})

func _build_logs_employee_recruit_train(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Recruit")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_recruit := _ensure_employee(state, actor, "recruiting_girl", false, 1)
	if not ensure_recruit.ok:
		return ensure_recruit
	var ensure_trainer := _ensure_employee(state, actor, "trainer", false, 1)
	if not ensure_trainer.ok:
		return ensure_trainer
	var ensure_pricing := _ensure_employee(state, actor, "pricing_manager", false, 1)
	if not ensure_pricing.ok:
		return ensure_pricing

	# Ensure enough cash so the replayed commands won't fail due to economy constraints.
	for pid in range(state.players.size()):
		var give := engine.execute_command(Command.create_system("debug_give_money", {"player_id": pid, "amount": 50}))
		if not give.ok:
			return Result.failure("debug_give_money failed: %s" % give.error)

	_freeze_engine_as_initial(engine)

	var set_price := engine.execute_command(Command.create("set_price", actor, {}))
	if not set_price.ok:
		return Result.failure("set_price failed: %s" % set_price.error)

	var recruit := engine.execute_command(Command.create("recruit", actor, {"employee_type": "management_trainee"}))
	if not recruit.ok:
		return Result.failure("recruit failed: %s" % recruit.error)

	var to_train := TestPhaseUtils.advance_until_working_sub_phase(engine, "Train", 20)
	if not to_train.ok:
		return to_train

	var train := engine.execute_command(Command.create("train", actor, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
	}))
	if not train.ok:
		return Result.failure("train failed: %s" % train.error)

	return Result.success()

func _build_logs_employee_fire(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "burger_cook", true, 1)
	if not ensure.ok:
		return ensure

	_freeze_engine_as_initial(engine)

	var fire := engine.execute_command(Command.create("fire", actor, {"employee_id": "burger_cook", "location": "reserve"}))
	if not fire.ok:
		return Result.failure("fire failed: %s" % fire.error)

	return Result.success()

func _build_logs_build_and_move(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceHouses")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	# place_house 与 add_garden 共享 house_placement_counts，需 >=2 次数才能在同一 PlaceHouses 子阶段做两步。
	var ensure_house := _ensure_employee(state, actor, "new_business_developer", false, 2)
	if not ensure_house.ok:
		return ensure_house
	# Need >=2 eligible actions to do "place + move" in one Working/PlaceRestaurants.
	var ensure_place := _ensure_employee(state, actor, "local_manager", false, 1)
	if not ensure_place.ok:
		return ensure_place
	var ensure_move := _ensure_employee(state, actor, "regional_manager", false, 1)
	if not ensure_move.ok:
		return ensure_move

	var give := engine.execute_command(Command.create_system("debug_give_money", {"player_id": actor, "amount": 50}))
	if not give.ok:
		return Result.failure("debug_give_money failed: %s" % give.error)

	_freeze_engine_as_initial(engine)

	# 1) Place a house + add a garden (find a combo that doesn't block itself).
	var numbers := _get_remaining_house_numbers_from_state(engine.get_state())
	if numbers.is_empty():
		return Result.failure("no remaining house numbers")
	var house_number := int(numbers[0])
	var plan_r := _find_first_valid_place_house_then_add_garden(engine, actor, house_number)
	if not plan_r.ok:
		return plan_r
	var plan: Dictionary = plan_r.value if (plan_r.value is Dictionary) else {}

	var house_params: Dictionary = plan.get("place_house_params", {}) if (plan.get("place_house_params", null) is Dictionary) else {}
	house_params["employee_type"] = "new_business_developer"
	var place_house := engine.execute_command(Command.create("place_house", actor, house_params))
	if not place_house.ok:
		return Result.failure("place_house failed: %s" % place_house.error)

	var garden_params: Dictionary = plan.get("add_garden_params", {}) if (plan.get("add_garden_params", null) is Dictionary) else {}
	garden_params["employee_type"] = "new_business_developer"
	var add_garden := engine.execute_command(Command.create("add_garden", actor, garden_params))
	if not add_garden.ok:
		return Result.failure("add_garden failed: %s" % add_garden.error)

	# 3) Move to PlaceRestaurants and place+move a restaurant.
	var to_place_restaurants := TestPhaseUtils.advance_until_working_sub_phase(engine, "PlaceRestaurants", 10)
	if not to_place_restaurants.ok:
		return to_place_restaurants

	var find_place_rest := _find_first_valid_place_restaurant(engine, actor)
	if not find_place_rest.ok:
		return find_place_rest
	var place_rest_info: Dictionary = find_place_rest.value if (find_place_rest.value is Dictionary) else {}
	var place_rest_params: Dictionary = place_rest_info.get("params", {}) if (place_rest_info.get("params", null) is Dictionary) else {}
	place_rest_params["employee_type"] = "local_manager"
	var place_rest := engine.execute_command(Command.create("place_restaurant", actor, place_rest_params))
	if not place_rest.ok:
		return Result.failure("place_restaurant failed: %s" % place_rest.error)

	var rest_ids_val = engine.get_state().get_player(actor).get("restaurants", [])
	var rest_ids: Array = rest_ids_val if (rest_ids_val is Array) else []
	if rest_ids.is_empty():
		return Result.failure("player has no restaurants after place_restaurant")
	var restaurant_id := str(rest_ids[0]).strip_edges()
	if restaurant_id.is_empty():
		return Result.failure("invalid restaurant_id")

	var find_move := _find_first_valid_move_restaurant(engine, actor, restaurant_id)
	if not find_move.ok:
		return find_move
	var move_info: Dictionary = find_move.value if (find_move.value is Dictionary) else {}
	var move_params: Dictionary = move_info.get("params", {}) if (move_info.get("params", null) is Dictionary) else {}
	move_params["employee_type"] = "regional_manager"
	var move_rest := engine.execute_command(Command.create("move_restaurant", actor, move_params))
	if not move_rest.ok:
		return Result.failure("move_restaurant failed: %s" % move_rest.error)

	return Result.success()

func _build_logs_produce_and_cleanup(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetFood")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "burger_cook", false, 1)
	if not ensure.ok:
		return ensure

	# 进入 Payday 需要支付薪水；为避免“薪水不足需要解雇”打断本日志用例，提前补足现金并冻结为 initial_state。
	var give := engine.execute_command(Command.create_system("debug_give_money", {"player_id": actor, "amount": 50}))
	if not give.ok:
		return Result.failure("debug_give_money failed: %s" % give.error)

	_freeze_engine_as_initial(engine)

	var prod := engine.execute_command(Command.create("produce_food", actor, {"employee_type": "burger_cook", "food_type": "burger"}))
	if not prod.ok:
		return Result.failure("produce_food failed: %s" % prod.error)

	var done := TestPhaseUtils.complete_working_phase(engine, 200)
	if not done.ok:
		return done
	var to_restructuring := TestPhaseUtils.advance_until_phase(engine, "Restructuring", 200)
	if not to_restructuring.ok:
		return to_restructuring

	return Result.success()

func _build_logs_dinnertime_sale(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_dinnertime_sale_complex(state)

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("logs_dinnertime_sale: cannot resolve current player")

	# Ensure employee-based bonuses:
	# - waitress: tips + tiebreaker
	# - cfo: income bonus (+50%)
	# - fry_chef: per-house bonus (+$10)
	var ensure_waitress := _ensure_employee(state, actor, "waitress", false, 2)
	if not ensure_waitress.ok:
		return ensure_waitress
	var ensure_cfo := _ensure_employee(state, actor, "cfo", false, 1)
	if not ensure_cfo.ok:
		return ensure_cfo
	var ensure_fry_chef := _ensure_employee(state, actor, "fry_chef", false, 2)
	if not ensure_fry_chef.ok:
		return ensure_fry_chef

	# Seed milestone-based marketing bonuses (sell_bonus).
	state.players[actor]["milestones"] = [
		"first_burger_marketed",
		"first_drink_marketed",
		"first_pizza_marketed",
	]

	var houses: Dictionary = state.map.get("houses", {}) if (state.map is Dictionary) else {}
	if not houses.has("h0") or not (houses["h0"] is Dictionary):
		return Result.failure("logs_dinnertime_sale: test house missing (h0)")
	if not houses.has("h1") or not (houses["h1"] is Dictionary):
		return Result.failure("logs_dinnertime_sale: test house missing (h1)")
	if not houses.has("h2") or not (houses["h2"] is Dictionary):
		return Result.failure("logs_dinnertime_sale: test house missing (h2)")

	# h0: garden + multiple products (food+drink) to cover garden bonus + marketing bonus.
	var h0: Dictionary = houses["h0"]
	h0["demands"] = [{"product": "burger"}, {"product": "beer"}]
	h0["has_garden"] = true
	houses["h0"] = h0

	# h1: pizza to cover per-product marketing bonus.
	var h1: Dictionary = houses["h1"]
	h1["demands"] = [{"product": "pizza"}]
	houses["h1"] = h1

	# h2: soda sale by player 2 (also enables route purchase income split).
	var h2: Dictionary = houses["h2"]
	h2["demands"] = [{"product": "soda"}]
	houses["h2"] = h2

	state.map["houses"] = houses

	# Keep cells structure in sync for garden visualization (optional, but avoids confusing state).
	if state.map.has("cells") and (state.map["cells"] is Array) and h0.has("anchor_pos") and (h0["anchor_pos"] is Vector2i):
		var p: Vector2i = h0["anchor_pos"]
		var cells: Array = state.map["cells"]
		if p.y >= 0 and p.y < cells.size() and (cells[p.y] is Array):
			var row: Array = cells[p.y]
			if p.x >= 0 and p.x < row.size() and (row[p.x] is Dictionary):
				var cell: Dictionary = row[p.x]
				var s_val = cell.get("structure", null)
				if s_val is Dictionary:
					var s: Dictionary = s_val
					s["has_garden"] = true
					cell["structure"] = s
					row[p.x] = cell
					cells[p.y] = row
					state.map["cells"] = cells

	# Inventory:
	# - player 1 wins h0/h1 (food+drink, pizza)
	# - player 2 wins h2 (soda) and sells coffee along the route to generate route_purchase_income
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["inventory"]["beer"] = 1
	state.players[0]["inventory"]["pizza"] = 1
	state.players[0]["inventory"]["soda"] = 0
	state.players[0]["inventory"]["coffee"] = 0

	if state.players.size() > 1:
		state.players[1]["inventory"]["burger"] = 0
		state.players[1]["inventory"]["beer"] = 0
		state.players[1]["inventory"]["pizza"] = 0
		state.players[1]["inventory"]["soda"] = 1
		state.players[1]["inventory"]["coffee"] = 4

	_freeze_engine_as_initial(engine)

	# Advance to Payday: Dinnertime is auto-skipped. The Dinnertime settlement step should emit:
	# - FOOD_SOLD first
	# - PLAYER_CASH_CHANGED after
	var to_payday := TestPhaseUtils.advance_until_phase(engine, "Payday", 60)
	if not to_payday.ok:
		return to_payday

	return Result.success({
		"scenario": [
			"地图：水平道路 y=3；rest_0/rest_1 位于道路下方；h0(花园)/h1/h2 位于道路上方。",
			"h0：花园房屋，需求 burger+beer（覆盖：花园翻倍 + 营销加成 + 薯条主厨房屋奖）。",
			"h1：需求 pizza（覆盖：按品类营销加成）。",
			"h2：需求 soda（由玩家2售出）。",
			"沿路购买：玩家2在 rest_1 持有 coffee 库存；玩家1从 rest_0 前往 h0/h1 的路径会路过 rest_1，触发咖啡沿路购买收入。",
			"玩家1：waitress x2（tips + 平局）、cfo x1（+50%）、fry_chef x2（每房屋+$10）；里程碑 first_*_marketed 提供 sell_bonus。",
		],
	})

func _build_logs_game_over_bankruptcy(engine: GameEngine, _c: Dictionary) -> Result:
	# GameOver case:
	# - Force a tiny map with 1 restaurant + 1 house.
	# - Drain the bank to $0 and set small reserve cards so Dinnertime triggers 2nd bankruptcy.
	# - Start at Working/PlaceHouses so the player can click:
	#   1) skip_sub_phase -> PlaceRestaurants
	#   2) skip -> Working -> Dinnertime -> GameOver
	var adv := _advance_to_working_sub_phase(engine, "PlaceHouses")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	# Reserve cards (small): first bankruptcy injects $20 total, still not enough for $30 income -> triggers 2nd bankruptcy.
	for pid in range(state.players.size()):
		state.players[pid]["reserve_cards"] = [{"type": 10, "cash": 10, "ceo_slots": 4}]
		state.players[pid]["reserve_card_selected"] = 0
		state.players[pid]["reserve_card_revealed"] = false

	# Drain bank to 0 (keep cash invariants: transfer to player 0).
	var bank_before: int = int(state.bank.get("total", 0))
	if bank_before <= 0:
		return Result.failure("logs_game_over_bankruptcy: bank.total must be > 0, got: %d" % bank_before)
	var drain := StateUpdater.player_receive_from_bank(state, 0, bank_before)
	if not drain.ok:
		return Result.failure("logs_game_over_bankruptcy: pre-drain bank failed: %s" % drain.error)
	if int(state.bank.get("total", 0)) != 0:
		return Result.failure("logs_game_over_bankruptcy: expected bank.total=0 after drain, got: %d" % int(state.bank.get("total", 0)))
	state.bank["broke_count"] = 0

	# Ensure a deterministic Dinnertime payment ($30): 3x burger demand, player 0 has 3 burgers.
	if not (state.map is Dictionary):
		return Result.failure("logs_game_over_bankruptcy: state.map is invalid")
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary) or not (houses_val as Dictionary).has("h0"):
		return Result.failure("logs_game_over_bankruptcy: test house missing (h0)")
	var houses: Dictionary = houses_val
	var h0_val = houses.get("h0", null)
	if not (h0_val is Dictionary):
		return Result.failure("logs_game_over_bankruptcy: test house invalid (h0)")
	var demands: Array = []
	for _i in range(3):
		demands.append({"product": "burger"})
	var h0: Dictionary = h0_val
	h0["demands"] = demands
	houses["h0"] = h0
	state.map["houses"] = houses

	if not (state.players[0] is Dictionary):
		return Result.failure("logs_game_over_bankruptcy: players[0] is invalid")
	if not state.players[0].has("inventory") or not (state.players[0]["inventory"] is Dictionary):
		state.players[0]["inventory"] = {}
	state.players[0]["inventory"]["burger"] = 3
	if state.players.size() > 1:
		if not state.players[1].has("inventory") or not (state.players[1]["inventory"] is Dictionary):
			state.players[1]["inventory"] = {}
		state.players[1]["inventory"]["burger"] = 0

	# Pre-mark other players as "passed" so the final skip ends Working immediately.
	if not (state.round_state is Dictionary):
		return Result.failure("logs_game_over_bankruptcy: round_state is invalid")
	if not state.round_state.has("sub_phase_passed") or not (state.round_state["sub_phase_passed"] is Dictionary):
		_reset_sub_phase_passed(state)
	var passed: Dictionary = state.round_state["sub_phase_passed"]
	for pid in range(state.players.size()):
		passed[pid] = true
	var current_pid := int(state.get_current_player_id())
	if current_pid >= 0:
		passed[current_pid] = false
	state.round_state["sub_phase_passed"] = passed

	return Result.success({
		"scenario": [
			"预置：银行余额被清空为 $0；两名玩家储备卡均为 cash=$10（第一次破产注资总额=$20）。",
			"地图：单餐厅 rest_0 + 单房屋 h0（3 个 burger 需求）。",
			"玩家 1（P1）库存 burger=3，可在晚餐结算获得 $30；触发第二次破产并在晚餐结束后进入 GameOver。",
			"起始位置：Working/PlaceHouses；先点「跳过放置房屋」，再点「确认结束」触发终局。",
		],
	})

func _logs_find_radio_marketing_command_affecting_houses(
	engine: GameEngine,
	actor: int,
	employee_type: String,
	board_number: int,
	product: String,
	duration: int
) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("initiate_marketing")
	if ex == null:
		return Result.failure("cannot find executor: initiate_marketing")

	var houses_val = state.map.get("houses", null) if (state.map is Dictionary) else null
	if not (houses_val is Dictionary) or (houses_val as Dictionary).is_empty():
		return Result.failure("state.map.houses missing or empty")
	var houses: Dictionary = houses_val

	# Pick one reference house anchor to focus the search.
	var house_ids: Array[String] = []
	for hid in houses.keys():
		if hid is String and not str(hid).is_empty():
			house_ids.append(str(hid))
	house_ids.sort()
	if house_ids.is_empty():
		return Result.failure("no house ids")
	var h_val = houses.get(house_ids[0], null)
	if not (h_val is Dictionary):
		return Result.failure("house entry invalid: %s" % house_ids[0])
	var h: Dictionary = h_val
	if not h.has("anchor_pos") or not (h["anchor_pos"] is Vector2i):
		return Result.failure("house.anchor_pos missing or invalid: %s" % house_ids[0])
	var anchor_pos: Vector2i = h["anchor_pos"]

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)

	var tile: Vector2i = MapUtils.world_to_tile(anchor_pos).board_pos
	var candidate_tiles: Array[Vector2i] = []
	for ty in range(tile.y - 1, tile.y + 2):
		for tx in range(tile.x - 1, tile.x + 2):
			candidate_tiles.append(Vector2i(tx, ty))

	var calc := MarketingRangeCalculator.new()

	# Prefer nearby tiles to ensure affected houses are non-empty (radio covers 3x3 tiles).
	for t in candidate_tiles:
		var base := Vector2i(t.x * MapUtils.TILE_SIZE, t.y * MapUtils.TILE_SIZE)
		for y in range(base.y, base.y + MapUtils.TILE_SIZE):
			for x in range(base.x, base.x + MapUtils.TILE_SIZE):
				var wp := Vector2i(x, y)
				if wp.x < minp.x or wp.x > maxp.x or wp.y < minp.y or wp.y > maxp.y:
					continue
				var cmd := Command.create("initiate_marketing", actor, {
					"employee_type": employee_type,
					"board_number": int(board_number),
					"product": product,
					"duration": int(duration),
					"position": [wp.x, wp.y],
					"rotation": 0,
				})
				var vr := ex.validate(state, cmd)
				if not vr.ok:
					continue
				var affected_r := calc.get_affected_house_ids(state, {"type": "radio", "world_pos": wp})
				if not affected_r.ok:
					continue
				var affected_val = affected_r.value
				if affected_val is Array and not (affected_val as Array).is_empty():
					return Result.success(cmd)

	# Fallback: scan the whole map.
	for y2 in range(minp.y, maxp.y + 1):
		for x2 in range(minp.x, maxp.x + 1):
			var wp2 := Vector2i(x2, y2)
			var cmd2 := Command.create("initiate_marketing", actor, {
				"employee_type": employee_type,
				"board_number": int(board_number),
				"product": product,
				"duration": int(duration),
				"position": [wp2.x, wp2.y],
				"rotation": 0,
			})
			var vr2 := ex.validate(state, cmd2)
			if not vr2.ok:
				continue
			var affected_r2 := calc.get_affected_house_ids(state, {"type": "radio", "world_pos": wp2})
			if not affected_r2.ok:
				continue
			var affected_val2 = affected_r2.value
			if affected_val2 is Array and not (affected_val2 as Array).is_empty():
				return Result.success(cmd2)

	return Result.failure("no valid radio marketing placement found that affects houses")

func _logs_find_zeppelin_procure_drinks_command(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	if str(state.phase) != "Working" or str(state.sub_phase) != "GetDrinks":
		return Result.failure("expected Working/GetDrinks, got: %s/%s" % [str(state.phase), str(state.sub_phase)])

	var ex := engine.action_registry.get_executor("procure_drinks")
	if ex == null:
		return Result.failure("cannot find executor: procure_drinks")

	var rest_ids := _logs_get_player_restaurant_ids(state, actor)
	if rest_ids.is_empty():
		return Result.failure("player has no restaurants")
	var restaurant_id := rest_ids[0]
	var entrance_r := _logs_get_restaurant_entrance_pos(state, restaurant_id)
	if not entrance_r.ok:
		return entrance_r
	var entrance_pos: Vector2i = entrance_r.value

	var tile_size_r := _logs_get_tile_size(state)
	if not tile_size_r.ok:
		return tile_size_r
	var tile_size: int = int(tile_size_r.value)

	var start_tile := _logs_world_to_tile_pos(tile_size, entrance_pos)
	var tiles_set := _logs_get_tile_positions_set(state)

	var bounds := {}
	if tiles_set.is_empty():
		var coords_script = _get_coords_script()
		if coords_script == null:
			return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
		var minp: Vector2i = coords_script.get_world_min(state)
		var maxp: Vector2i = coords_script.get_world_max(state)
		bounds["min"] = Vector2i(_logs_floor_div(minp.x, tile_size), _logs_floor_div(minp.y, tile_size))
		bounds["max"] = Vector2i(_logs_floor_div(maxp.x, tile_size), _logs_floor_div(maxp.y, tile_size))

	var sources_val = state.map.get("drink_sources", null) if (state.map is Dictionary) else null
	if not (sources_val is Array) or (sources_val as Array).is_empty():
		return Result.failure("state.map.drink_sources missing or empty")
	var sources: Array = sources_val

	var sources_by_tile := {}
	for s_val in sources:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var wp_val = s.get("world_pos", null)
		if not (wp_val is Vector2i):
			continue
		var wp: Vector2i = wp_val
		var tp := _logs_world_to_tile_pos(tile_size, wp)
		if not sources_by_tile.has(tp):
			sources_by_tile[tp] = []
		(sources_by_tile[tp] as Array).append(wp)

	# Zeppelin pilot: air route on tiles, max_steps=4.
	var max_steps := 4
	var route_find := _logs_bfs_find_route_to_any_source_tile(start_tile, sources_by_tile, tiles_set, bounds, max_steps)
	if not route_find.ok:
		return route_find
	var rf: Dictionary = route_find.value
	var route: Array[Vector2i] = rf.get("route", []) if rf.get("route", null) is Array else []
	var picked_source_pos: Vector2i = rf.get("source_world_pos", Vector2i.ZERO)
	if route.is_empty():
		return Result.failure("internal error: route is empty")

	var cmd := Command.create("procure_drinks", actor, {
		"employee_type": "zeppelin_pilot",
		"restaurant_id": restaurant_id,
		"route": _logs_serialize_vec2i_array(route),
		"selected_sources": _logs_serialize_vec2i_array([picked_source_pos]),
	})
	var vr := ex.validate(state, cmd)
	if not vr.ok:
		return Result.failure("generated procure_drinks command is invalid: %s" % vr.error)
	return Result.success(cmd)

func _logs_get_player_restaurant_ids(state: GameState, player_id: int) -> Array[String]:
	var out: Array[String] = []
	if state == null or not (state.map is Dictionary):
		return out
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return out
	var restaurants: Dictionary = restaurants_val
	for rid_val in restaurants.keys():
		if not (rid_val is String):
			continue
		var rid := str(rid_val).strip_edges()
		if rid.is_empty():
			continue
		var rest_val = restaurants.get(rid, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var owner_val = rest.get("owner", null)
		if owner_val is int and int(owner_val) == player_id:
			out.append(rid)
	out.sort()
	return out

func _logs_get_restaurant_entrance_pos(state: GameState, restaurant_id: String) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map missing")
	if restaurant_id.is_empty():
		return Result.failure("restaurant_id is empty")
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.failure("state.map.restaurants missing or invalid")
	var restaurants: Dictionary = restaurants_val
	if not restaurants.has(restaurant_id):
		return Result.failure("restaurant not found: %s" % restaurant_id)
	var rest_val = restaurants.get(restaurant_id, null)
	if not (rest_val is Dictionary):
		return Result.failure("restaurant invalid: %s" % restaurant_id)
	var rest: Dictionary = rest_val
	var ep_val = rest.get("entrance_pos", null)
	if not (ep_val is Vector2i):
		return Result.failure("restaurant.entrance_pos missing or invalid: %s" % restaurant_id)
	return Result.success(Vector2i(ep_val))

func _logs_get_tile_size(state: GameState) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map missing or invalid")
	var map: Dictionary = state.map
	var grid_val = map.get("grid_size", null)
	var tile_grid_val = map.get("tile_grid_size", null)
	if not (grid_val is Vector2i) or not (tile_grid_val is Vector2i):
		return Result.failure("grid_size/tile_grid_size missing or invalid")
	var grid: Vector2i = grid_val
	var tile_grid: Vector2i = tile_grid_val
	if tile_grid.x <= 0 or tile_grid.y <= 0:
		return Result.failure("tile_grid_size invalid: %s" % str(tile_grid))
	if grid.x % tile_grid.x != 0 or grid.y % tile_grid.y != 0:
		return Result.failure("grid_size not divisible by tile_grid_size: %s/%s" % [str(grid), str(tile_grid)])
	var sx := grid.x / tile_grid.x
	var sy := grid.y / tile_grid.y
	if sx != sy or sx <= 0:
		return Result.failure("tile_size invalid: %d/%d" % [sx, sy])
	return Result.success(int(sx))

func _logs_world_to_tile_pos(tile_size: int, world_pos: Vector2i) -> Vector2i:
	return Vector2i(_logs_floor_div(world_pos.x, tile_size), _logs_floor_div(world_pos.y, tile_size))

func _logs_floor_div(a: int, b: int) -> int:
	if b == 0:
		return 0
	return int(floor(float(a) / float(b)))

func _logs_get_tile_positions_set(state: GameState) -> Dictionary:
	var out := {}
	if state == null or not (state.map is Dictionary):
		return out
	var map: Dictionary = state.map
	var placements_val = map.get("tile_placements", null)
	if placements_val is Array:
		for p_val in Array(placements_val):
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var bp = p.get("board_pos", null)
			if bp is Vector2i:
				out[Vector2i(bp)] = true
	var ext_val = map.get("external_tile_placements", null)
	if ext_val is Array:
		for p_val2 in Array(ext_val):
			if not (p_val2 is Dictionary):
				continue
			var p2: Dictionary = p_val2
			var bp2 = p2.get("board_pos", null)
			if bp2 is Vector2i:
				out[Vector2i(bp2)] = true
	return out

func _logs_bfs_find_route_to_any_source_tile(
	start_tile: Vector2i,
	sources_by_tile: Dictionary,
	tiles_set: Dictionary,
	bounds: Dictionary,
	max_steps: int
) -> Result:
	var visited := {}
	var queue: Array[Dictionary] = []
	queue.append({"pos": start_tile, "route": [start_tile]})
	visited[start_tile] = true

	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var pos: Vector2i = item.get("pos", Vector2i.ZERO)
		var route: Array = item.get("route", [])
		if sources_by_tile.has(pos):
			var arr = sources_by_tile.get(pos, null)
			if arr is Array and not (arr as Array).is_empty():
				var wp: Vector2i = (arr as Array)[0]
				return Result.success({
					"route": route,
					"source_world_pos": wp,
				})

		if route.size() >= max_steps:
			continue

		for dir in MapUtils.DIRECTIONS:
			var next: Vector2i = MapUtils.get_neighbor_pos(pos, dir)
			if visited.has(next):
				continue
			if not tiles_set.is_empty():
				if not tiles_set.has(next):
					continue
			else:
				var min_t: Vector2i = bounds.get("min", Vector2i.ZERO)
				var max_t: Vector2i = bounds.get("max", Vector2i.ZERO)
				if next.x < min_t.x or next.x > max_t.x or next.y < min_t.y or next.y > max_t.y:
					continue

			visited[next] = true
			var new_route: Array[Vector2i] = []
			for v in route:
				if v is Vector2i:
					new_route.append(Vector2i(v))
			new_route.append(next)
			queue.append({"pos": next, "route": new_route})

	return Result.failure("no reachable drink source tile within steps=%d" % max_steps)

func _logs_serialize_vec2i_array(points: Array) -> Array:
	var out: Array = []
	for p in points:
		if p is Vector2i:
			var v: Vector2i = p
			out.append([v.x, v.y])
	return out
