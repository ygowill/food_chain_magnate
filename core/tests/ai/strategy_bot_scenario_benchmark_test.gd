class_name StrategyBotScenarioBenchmarkTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRaceAnalyzerClass = preload("res://core/ai/analysis/milestone_race_analyzer.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var registry_read := _load_registries(seed_val)
	if not registry_read.ok:
		return registry_read

	var names: Array[String] = []
	var marketing_pipeline := _scenario_marketing_pipeline_requires_active_food_supply()
	if not marketing_pipeline.ok:
		return _scenario_failure("marketing_pipeline_requires_active_food_supply", marketing_pipeline)
	names.append("marketing_pipeline_requires_active_food_supply")

	var marketing_next_round_supply := _scenario_marketing_values_next_round_supply_capacity()
	if not marketing_next_round_supply.ok:
		return _scenario_failure("marketing_values_next_round_supply_capacity", marketing_next_round_supply)
	names.append("marketing_values_next_round_supply_capacity")

	var marketing_next_round_sale := _scenario_marketing_next_round_route_produces_and_sells(seed_val)
	if not marketing_next_round_sale.ok:
		return _scenario_failure("marketing_next_round_route_produces_and_sells", marketing_next_round_sale)
	names.append("marketing_next_round_route_produces_and_sells")

	var training_food_supply := _scenario_income_route_trains_food_supply_for_serviceable_demand(seed_val)
	if not training_food_supply.ok:
		return _scenario_failure("income_route_trains_food_supply_for_serviceable_demand", training_food_supply)
	names.append("income_route_trains_food_supply_for_serviceable_demand")

	var training_food_capacity := _scenario_income_route_trains_food_capacity_for_serviceable_demand(seed_val)
	if not training_food_capacity.ok:
		return _scenario_failure("income_route_trains_food_capacity_for_serviceable_demand", training_food_capacity)
	names.append("income_route_trains_food_capacity_for_serviceable_demand")

	var trainable_supply := _scenario_trainable_supply_stays_structure_candidate(seed_val)
	if not trainable_supply.ok:
		return _scenario_failure("trainable_supply_stays_structure_candidate", trainable_supply)
	names.append("trainable_supply_stays_structure_candidate")

	var pending_drinks_deferred := _scenario_pending_marketing_drink_supply_deferred_without_fridge()
	if not pending_drinks_deferred.ok:
		return _scenario_failure("pending_marketing_drink_supply_deferred_without_fridge", pending_drinks_deferred)
	names.append("pending_marketing_drink_supply_deferred_without_fridge")

	var pending_drinks_fridge := _scenario_pending_marketing_drink_supply_targets_product_with_fridge()
	if not pending_drinks_fridge.ok:
		return _scenario_failure("pending_marketing_drink_supply_targets_product_with_fridge", pending_drinks_fridge)
	names.append("pending_marketing_drink_supply_targets_product_with_fridge")

	var first_errand_boy := _scenario_first_errand_boy_counts_two_drinks(seed_val)
	if not first_errand_boy.ok:
		return _scenario_failure("first_errand_boy_counts_two_drinks", first_errand_boy)
	names.append("first_errand_boy_counts_two_drinks")

	var route_drink_sale := _scenario_route_drink_demand_produces_and_sells(seed_val)
	if not route_drink_sale.ok:
		return _scenario_failure("route_drink_demand_produces_and_sells", route_drink_sale)
	names.append("route_drink_demand_produces_and_sells")

	var first_cart_range := _scenario_first_cart_operator_range_bonus_routes_drinks(seed_val)
	if not first_cart_range.ok:
		return _scenario_failure("first_cart_operator_range_bonus_routes_drinks", first_cart_range)
	names.append("first_cart_operator_range_bonus_routes_drinks")

	var first_recruit := _scenario_income_route_first_recruit_gets_food_supply(seed_val)
	if not first_recruit.ok:
		return _scenario_failure("income_route_first_recruit_gets_food_supply", first_recruit)
	names.append("income_route_first_recruit_gets_food_supply")

	var marketing_recruit := _scenario_income_route_recruits_marketing_after_food_supply(seed_val)
	if not marketing_recruit.ok:
		return _scenario_failure("income_route_recruits_marketing_after_food_supply", marketing_recruit)
	names.append("income_route_recruits_marketing_after_food_supply")

	var drink_recruit := _scenario_income_route_recruits_drink_supply_for_drink_demand(seed_val)
	if not drink_recruit.ok:
		return _scenario_failure("income_route_recruits_drink_supply_for_drink_demand", drink_recruit)
	names.append("income_route_recruits_drink_supply_for_drink_demand")

	var training_drink_capacity := _scenario_income_route_trains_drink_capacity_for_serviceable_demand(seed_val)
	if not training_drink_capacity.ok:
		return _scenario_failure("income_route_trains_drink_capacity_for_serviceable_demand", training_drink_capacity)
	names.append("income_route_trains_drink_capacity_for_serviceable_demand")

	var pricing_recruit := _scenario_income_route_recruits_pricing_after_stable_serviceable_demand(seed_val)
	if not pricing_recruit.ok:
		return _scenario_failure("income_route_recruits_pricing_after_stable_serviceable_demand", pricing_recruit)
	names.append("income_route_recruits_pricing_after_stable_serviceable_demand")

	var pricing_structure := _scenario_income_route_structures_pricing_after_price_recruit()
	if not pricing_structure.ok:
		return _scenario_failure("income_route_structures_pricing_after_price_recruit", pricing_structure)
	names.append("income_route_structures_pricing_after_price_recruit")

	var pricing_action := _scenario_income_route_executes_price_action_after_price_structure(seed_val)
	if not pricing_action.ok:
		return _scenario_failure("income_route_executes_price_action_after_price_structure", pricing_action)
	names.append("income_route_executes_price_action_after_price_structure")

	var waitress_recruit := _scenario_income_route_recruits_waitress_after_price_support(seed_val)
	if not waitress_recruit.ok:
		return _scenario_failure("income_route_recruits_waitress_after_price_support", waitress_recruit)
	names.append("income_route_recruits_waitress_after_price_support")

	var waitress_structure := _scenario_income_route_structures_waitress_after_support_recruit()
	if not waitress_structure.ok:
		return _scenario_failure("income_route_structures_waitress_after_support_recruit", waitress_structure)
	names.append("income_route_structures_waitress_after_support_recruit")

	var third_recruit_milestone := _scenario_milestone_third_recruit_values_first_hire_3()
	if not third_recruit_milestone.ok:
		return _scenario_failure("milestone_third_recruit_values_first_hire_3", third_recruit_milestone)
	names.append("milestone_third_recruit_values_first_hire_3")

	var lower_price_milestone := _scenario_milestone_lower_price_ignores_luxury_price()
	if not lower_price_milestone.ok:
		return _scenario_failure("milestone_lower_price_ignores_luxury_price", lower_price_milestone)
	names.append("milestone_lower_price_ignores_luxury_price")

	var cash_reached_milestone := _scenario_dinner_preview_values_cash_reached_milestone(seed_val)
	if not cash_reached_milestone.ok:
		return _scenario_failure("dinner_preview_values_cash_reached_milestone", cash_reached_milestone)
	names.append("dinner_preview_values_cash_reached_milestone")

	var waitress_milestone := _scenario_dinner_preview_values_waitress_milestone(seed_val)
	if not waitress_milestone.ok:
		return _scenario_failure("dinner_preview_values_waitress_milestone", waitress_milestone)
	names.append("dinner_preview_values_waitress_milestone")

	var marketing_sell_bonus := _scenario_milestone_marketing_sell_bonus_is_valued()
	if not marketing_sell_bonus.ok:
		return _scenario_failure("milestone_marketing_sell_bonus_is_valued", marketing_sell_bonus)
	names.append("milestone_marketing_sell_bonus_is_valued")

	var airplane_trigger := _scenario_milestone_airplane_trigger_uses_marketing_board()
	if not airplane_trigger.ok:
		return _scenario_failure("milestone_airplane_trigger_uses_marketing_board", airplane_trigger)
	names.append("milestone_airplane_trigger_uses_marketing_board")

	var support_effect_values := _scenario_milestone_effect_values_base_support()
	if not support_effect_values.ok:
		return _scenario_failure("milestone_effect_values_base_support", support_effect_values)
	names.append("milestone_effect_values_base_support")

	return Result.success({
		"scenarios": names.size(),
		"names": names.duplicate(),
	})

static func _load_registries(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed while loading registries: %s" % init.error)
	return Result.success()

static func _scenario_marketing_values_next_round_supply_capacity() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var no_supply_observation := _synthetic_food_income_observation()
	no_supply_observation.phase = DefsClass.PHASE_WORKING
	no_supply_observation.sub_phase = DefsClass.SUB_PHASE_MARKETING
	no_supply_observation.own_player["employees"] = ["campaign_manager"]
	no_supply_observation.own_player["reserve_employees"] = []
	no_supply_observation.own_player["inventory"] = {}
	_set_observation_house_demand_count(no_supply_observation, "house_near", "burger", 0)

	var future_supply_observation := _synthetic_food_income_observation()
	future_supply_observation.phase = DefsClass.PHASE_WORKING
	future_supply_observation.sub_phase = DefsClass.SUB_PHASE_MARKETING
	future_supply_observation.own_player["employees"] = ["campaign_manager"]
	future_supply_observation.own_player["reserve_employees"] = ["burger_cook"]
	future_supply_observation.own_player["inventory"] = {}
	_set_observation_house_demand_count(future_supply_observation, "house_near", "burger", 0)

	var marketing_macro := MacroAction.create(
		"market_burger_for_next_round",
		[Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager", "marketing_type": "mailbox", "board_number": 8, "product": "burger", "position": [2, 2]})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_near"]}
	)
	var skip_macro := MacroAction.create(
		"skip_marketing_without_supply",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)

	var no_supply_score: Dictionary = StrategyScorerClass.score_macro(no_supply_observation, marketing_macro, profile)
	var future_supply_score: Dictionary = StrategyScorerClass.score_macro(future_supply_observation, marketing_macro, profile)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(no_supply_observation, skip_macro, profile)
	var no_supply_features: Dictionary = Dictionary(no_supply_score.get("features", {}))
	var future_supply_features: Dictionary = Dictionary(future_supply_score.get("features", {}))
	if bool(no_supply_features.get("marketing_can_future_supply_product", true)):
		return Result.failure("expected no future burger supply when no production employee exists: %s" % str(no_supply_features))
	if not bool(future_supply_features.get("marketing_can_future_supply_product", false)):
		return Result.failure("expected reserve burger cook to count as next-round supply capacity: %s" % str(future_supply_features))
	if float(no_supply_features.get("marketing_supply_readiness_penalty", 0.0)) >= -100.0:
		return Result.failure("expected severe marketing readiness penalty with no future supply: %s" % str(no_supply_features))
	if float(future_supply_features.get("marketing_supply_readiness_penalty", 0.0)) < -20.0:
		return Result.failure("expected only mild marketing readiness penalty when next-round supply exists: %s" % str(future_supply_features))
	if float(no_supply_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("expected marketing with no future supply to lose to skip: marketing=%s skip=%s" % [str(no_supply_score), str(skip_score)])
	if float(future_supply_score.get("score", 0.0)) <= float(no_supply_score.get("score", 0.0)) + 50.0:
		return Result.failure("expected next-round supply capacity to materially raise marketing value: future=%s no_supply=%s" % [str(future_supply_score), str(no_supply_score)])
	return Result.success()

static func _scenario_marketing_next_round_route_produces_and_sells(seed_val: int) -> Result:
	var engine_read := _build_marketing_next_round_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()

	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("marketing route step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected StrategyBot to initiate burger marketing for next-round supply, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	if str(marketing_params.get("product", "")) != "burger":
		return Result.failure("expected next-round route marketing product burger, got %s" % str(marketing_trace))
	var state := engine.get_state()
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("marketing action should not create same-round burger demand before Marketing settlement")
	if _player_inventory_units_for_product(state, 0, "burger") != 0:
		return Result.failure("marketing action should not create same-round burger inventory")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	if _state_product_demand_count(state, "burger") <= 0:
		return Result.failure("Marketing settlement should create burger demand for next round")

	var prepare_next_round := _prepare_next_round_restructuring(engine)
	if not prepare_next_round.ok:
		return prepare_next_round
	var structure_controller := BotControllerClass.new()
	var structure_step := structure_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not structure_step.ok:
		return Result.failure("next-round restructuring step failed: %s" % structure_step.error)
	var structure_trace: Dictionary = structure_step.value
	if str(structure_trace.get("action_id", "")) != "set_company_structure_direct":
		return Result.failure("expected next-round route to activate burger_cook, got %s" % str(structure_trace))
	var structure_params: Dictionary = Dictionary(structure_trace.get("params", {}))
	if str(structure_params.get("employee_id", "")) != "burger_cook":
		return Result.failure("expected next-round route structure employee burger_cook, got %s" % str(structure_trace))

	var prepare_get_food := _prepare_next_round_get_food(engine)
	if not prepare_get_food.ok:
		return prepare_get_food
	var produce_controller := BotControllerClass.new()
	var produce_step := produce_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("next-round production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected next-round route to produce burger for settled demand, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("food_type", "")) != "burger":
		return Result.failure("expected next-round production food burger, got %s" % str(produce_trace))

	state = engine.get_state()
	var cash_before_dinner := int(state.players[0].get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(state.players[0].get("cash", 0)) <= cash_before_dinner:
		return Result.failure("next-round route should sell produced burger at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(state.players[0].get("cash", 0))])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("next-round Dinnertime should clear marketed burger demand")
	return Result.success()

static func _build_marketing_next_round_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	_force_route_turn_order(state, 2)
	var map_result := _build_route_marketing_sale_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 50)
	if not seed_cash.ok:
		return Result.failure("seed route cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 0,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[1]["inventory"] = {
		"burger": 0,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[0]["employees"] = ["ceo"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["employees_staff_ids"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["staff_registry"] = {}
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	var take_campaign := StateUpdaterClass.take_from_pool(state, "campaign_manager", 1)
	if not take_campaign.ok:
		return Result.failure("take campaign_manager failed: %s" % take_campaign.error)
	var add_campaign := StateUpdaterClass.add_employee(state, 0, "campaign_manager", false)
	if not add_campaign.ok:
		return Result.failure("add campaign_manager failed: %s" % add_campaign.error)
	var take_cook := StateUpdaterClass.take_from_pool(state, "burger_cook", 1)
	if not take_cook.ok:
		return Result.failure("take burger_cook failed: %s" % take_cook.error)
	var add_cook := StateUpdaterClass.add_employee(state, 0, "burger_cook", true)
	if not add_cook.ok:
		return Result.failure("add burger_cook failed: %s" % add_cook.error)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _scenario_income_route_trains_food_supply_for_serviceable_demand(seed_val: int) -> Result:
	var engine_read := _build_training_income_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("training route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "train":
		return Result.failure("expected StrategyBot to train food supply for serviceable burger demand, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("from_employee", "")) != "kitchen_trainee" or str(params.get("to_employee", "")) != "burger_cook":
		return Result.failure("expected kitchen_trainee -> burger_cook training route, got %s" % str(trace))
	var state := engine.get_state()
	var reserve: Array = Array(Dictionary(state.players[0]).get("reserve_employees", []))
	if not reserve.has("burger_cook"):
		return Result.failure("training route should leave burger_cook in reserve after training, reserve=%s" % str(reserve))
	if reserve.has("kitchen_trainee"):
		return Result.failure("training route should consume kitchen_trainee source card, reserve=%s" % str(reserve))
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_train"):
		return Result.failure("training route should trigger first_train milestone, milestones=%s" % str(milestones))
	return Result.success()

static func _scenario_income_route_trains_food_capacity_for_serviceable_demand(seed_val: int) -> Result:
	var engine_read := _build_training_capacity_upgrade_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("training capacity route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "train":
		return Result.failure("expected StrategyBot to train advanced food capacity, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("from_employee", "")) != "burger_cook" or str(params.get("to_employee", "")) != "burger_chef":
		return Result.failure("expected burger_cook -> burger_chef capacity upgrade, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if float(features.get("train_capacity_upgrade_value", 0.0)) <= 0.0:
		return Result.failure("capacity upgrade should expose positive train_capacity_upgrade_value: %s" % str(trace))
	var state := engine.get_state()
	var reserve: Array = Array(Dictionary(state.players[0]).get("reserve_employees", []))
	if not reserve.has("burger_chef"):
		return Result.failure("training capacity route should leave burger_chef in reserve after training, reserve=%s" % str(reserve))
	if reserve.has("burger_cook"):
		return Result.failure("training capacity route should consume burger_cook source card, reserve=%s" % str(reserve))
	return Result.success()

static func _build_training_income_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	_force_route_turn_order(state, 2)
	var map_result := _build_route_marketing_sale_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	var house: Dictionary = Dictionary(Dictionary(state.map.get("houses", {})).get("house_route", {})).duplicate(true)
	house["demands"] = [
		{"product": "burger"},
		{"product": "burger"},
		{"product": "burger"},
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 30)
	if not seed_cash.ok:
		return Result.failure("seed training route cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 0,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[0]["employees"] = ["ceo"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["employees_staff_ids"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["staff_registry"] = {}
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for employee_id in ["trainer", "campaign_manager"]:
		var take_active := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [employee_id, add_active.error])
	for reserve_employee_id in ["kitchen_trainee", "marketing_trainee"]:
		var take_reserve := StateUpdaterClass.take_from_pool(state, reserve_employee_id, 1)
		if not take_reserve.ok:
			return Result.failure("take %s failed: %s" % [reserve_employee_id, take_reserve.error])
		var add_reserve := StateUpdaterClass.add_employee(state, 0, reserve_employee_id, true)
		if not add_reserve.ok:
			return Result.failure("add %s failed: %s" % [reserve_employee_id, add_reserve.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "trainer", "reports": []},
			{"employee_id": "campaign_manager", "reports": []},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.current_player_index = 0
	state.milestone_pool = ["first_train"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_training_capacity_upgrade_engine(seed_val: int) -> Result:
	var engine_read := _build_training_income_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	var house: Dictionary = Dictionary(houses.get("house_route", {})).duplicate(true)
	var demands: Array = []
	for _i in range(9):
		demands.append({"product": "burger"})
	house["demands"] = demands
	houses["house_route"] = house
	state.map["houses"] = houses
	RoadGraphCacheClass.invalidate_road_graph(state)
	var take_active_cook := StateUpdaterClass.take_from_pool(state, "burger_cook", 1)
	if not take_active_cook.ok:
		return Result.failure("take active burger_cook failed: %s" % take_active_cook.error)
	var add_active_cook := StateUpdaterClass.add_employee(state, 0, "burger_cook", false)
	if not add_active_cook.ok:
		return Result.failure("add active burger_cook failed: %s" % add_active_cook.error)
	var take_reserve_cook := StateUpdaterClass.take_from_pool(state, "burger_cook", 1)
	if not take_reserve_cook.ok:
		return Result.failure("take reserve burger_cook failed: %s" % take_reserve_cook.error)
	var add_reserve_cook := StateUpdaterClass.add_employee(state, 0, "burger_cook", true)
	if not add_reserve_cook.ok:
		return Result.failure("add reserve burger_cook failed: %s" % add_reserve_cook.error)
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "trainer", "reports": []},
			{"employee_id": "campaign_manager", "reports": []},
			{"employee_id": "burger_cook", "reports": []},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _scenario_first_errand_boy_counts_two_drinks(seed_val: int) -> Result:
	var engine_read := _build_first_errand_boy_drink_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("first errand boy route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "procure_drinks":
		return Result.failure("expected StrategyBot to procure drinks with first Errand Boy, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("employee_type", "")) != "errand_boy" or str(params.get("drink_type", "")) != "soda":
		return Result.failure("expected first Errand Boy to target soda demand, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if int(features.get("product_supply_expected_units", 0)) != 2:
		return Result.failure("StrategyScorer should estimate first Errand Boy as 2 drinks, features=%s trace=%s" % [str(features), str(trace)])
	var state := engine.get_state()
	var inventory: Dictionary = Dictionary(Dictionary(state.players[0]).get("inventory", {}))
	if int(inventory.get("soda", 0)) != 2:
		return Result.failure("first Errand Boy should actually procure 2 soda, inventory=%s" % str(inventory))
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_errand_boy"):
		return Result.failure("first Errand Boy route should trigger first_errand_boy, milestones=%s" % str(milestones))
	return Result.success()

static func _build_first_errand_boy_drink_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	_force_route_turn_order(state, 2)
	var map_result := _build_route_marketing_sale_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	var house: Dictionary = Dictionary(Dictionary(state.map.get("houses", {})).get("house_route", {})).duplicate(true)
	house["demands"] = [
		{"product": "soda"},
		{"product": "soda"},
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 20)
	if not seed_cash.ok:
		return Result.failure("seed errand route cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 0,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[0]["employees"] = ["ceo"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["employees_staff_ids"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["staff_registry"] = {}
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	var take_errand := StateUpdaterClass.take_from_pool(state, "errand_boy", 1)
	if not take_errand.ok:
		return Result.failure("take errand_boy failed: %s" % take_errand.error)
	var add_errand := StateUpdaterClass.add_employee(state, 0, "errand_boy", false)
	if not add_errand.ok:
		return Result.failure("add errand_boy failed: %s" % add_errand.error)
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "errand_boy", "reports": []},
			{},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.current_player_index = 0
	state.milestone_pool = ["first_errand_boy"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _scenario_route_drink_demand_produces_and_sells(seed_val: int) -> Result:
	var engine_read := _build_route_drink_sale_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("route drink step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "procure_drinks":
		return Result.failure("expected StrategyBot to procure route drinks for soda demand, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("employee_type", "")) != "truck_driver":
		return Result.failure("expected route drink employee truck_driver, got %s" % str(trace))
	var selected_sources: Array = Array(params.get("selected_sources", []))
	if not selected_sources.has([7, 2]):
		return Result.failure("expected route drink source [7, 2] to be selected, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	var expected_by_product: Dictionary = Dictionary(features.get("drink_route_expected_units_by_product", {}))
	if int(expected_by_product.get("soda", 0)) != 2:
		return Result.failure("expected route drink scorer to estimate 2 soda, features=%s trace=%s" % [str(features), str(trace)])
	if str(features.get("product_supply_primary_product", "")) != "soda":
		return Result.failure("expected route drink primary product soda, features=%s trace=%s" % [str(features), str(trace)])
	var state := engine.get_state()
	var inventory: Dictionary = Dictionary(Dictionary(state.players[0]).get("inventory", {}))
	if int(inventory.get("soda", 0)) != 2:
		return Result.failure("route drink command should procure 2 soda, inventory=%s" % str(inventory))
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("cash", 0)) <= cash_before_dinner:
		return Result.failure("route drink demand should sell at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(Dictionary(state.players[0]).get("cash", 0))])
	if _state_product_demand_count(state, "soda") != 0:
		return Result.failure("route drink Dinnertime should clear soda demand")
	return Result.success()

static func _scenario_first_cart_operator_range_bonus_routes_drinks(seed_val: int) -> Result:
	var engine_read := _build_first_cart_operator_range_bonus_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("first cart operator route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "procure_drinks":
		return Result.failure("expected StrategyBot to procure drinks with first Cart Operator range bonus, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("employee_type", "")) != "cart_operator":
		return Result.failure("expected first Cart Operator route employee cart_operator, got %s" % str(trace))
	var selected_sources: Array = Array(params.get("selected_sources", []))
	if not selected_sources.has([19, 0]):
		return Result.failure("expected first Cart Operator route source [19, 0] to be selected, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	var expected_by_product: Dictionary = Dictionary(features.get("drink_route_expected_units_by_product", {}))
	if int(expected_by_product.get("soda", 0)) != 2:
		return Result.failure("expected first Cart Operator scorer to estimate 2 soda, features=%s trace=%s" % [str(features), str(trace)])
	var state := engine.get_state()
	var inventory: Dictionary = Dictionary(Dictionary(state.players[0]).get("inventory", {}))
	if int(inventory.get("soda", 0)) != 2:
		return Result.failure("first Cart Operator route command should procure 2 soda, inventory=%s" % str(inventory))
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_cart_operator"):
		return Result.failure("first Cart Operator route should trigger first_cart_operator, milestones=%s" % str(milestones))
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("cash", 0)) <= cash_before_dinner:
		return Result.failure("first Cart Operator range route should sell at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(Dictionary(state.players[0]).get("cash", 0))])
	if _state_product_demand_count(state, "soda") != 0:
		return Result.failure("first Cart Operator Dinnertime should clear soda demand")
	return Result.success()

static func _scenario_income_route_trains_drink_capacity_for_serviceable_demand(seed_val: int) -> Result:
	var engine_read := _build_training_drink_capacity_upgrade_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("training drink capacity route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "train":
		return Result.failure("expected StrategyBot to train drink capacity, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("from_employee", "")) != "errand_boy" or str(params.get("to_employee", "")) != "cart_operator":
		return Result.failure("expected errand_boy -> cart_operator drink capacity upgrade, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if float(features.get("train_drink_route_upgrade_value", 0.0)) <= 0.0:
		return Result.failure("drink upgrade should expose positive train_drink_route_upgrade_value: %s" % str(trace))
	var state := engine.get_state()
	var reserve: Array = Array(Dictionary(state.players[0]).get("reserve_employees", []))
	if not reserve.has("cart_operator"):
		return Result.failure("training drink route should leave cart_operator in reserve after training, reserve=%s" % str(reserve))
	if reserve.has("errand_boy"):
		return Result.failure("training drink route should consume errand_boy source card, reserve=%s" % str(reserve))
	return Result.success()

static func _build_route_drink_sale_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	_force_route_turn_order(state, 2)
	var map_result := _build_route_marketing_sale_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	var house: Dictionary = Dictionary(Dictionary(state.map.get("houses", {})).get("house_route", {})).duplicate(true)
	house["demands"] = [
		{"product": "soda"},
		{"product": "soda"},
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	state.map["drink_sources"] = [
		{"world_pos": Vector2i(7, 2), "type": "soda", "tile_id": "R"},
	]
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 20)
	if not seed_cash.ok:
		return Result.failure("seed route drink cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 0,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[0]["employees"] = ["ceo"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["employees_staff_ids"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["staff_registry"] = {}
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	var take_truck := StateUpdaterClass.take_from_pool(state, "truck_driver", 1)
	if not take_truck.ok:
		return Result.failure("take truck_driver failed: %s" % take_truck.error)
	var add_truck := StateUpdaterClass.add_employee(state, 0, "truck_driver", false)
	if not add_truck.ok:
		return Result.failure("add truck_driver failed: %s" % add_truck.error)
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "truck_driver", "reports": []},
			{},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_first_cart_operator_range_bonus_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	_force_route_turn_order(state, 2)
	var map_result := _build_first_cart_operator_range_bonus_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 20)
	if not seed_cash.ok:
		return Result.failure("seed first cart route drink cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 0,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[0]["employees"] = ["ceo"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["employees_staff_ids"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["staff_registry"] = {}
	state.players[0]["milestones"] = []
	var take_cart := StateUpdaterClass.take_from_pool(state, "cart_operator", 1)
	if not take_cart.ok:
		return Result.failure("take cart_operator failed: %s" % take_cart.error)
	var add_cart := StateUpdaterClass.add_employee(state, 0, "cart_operator", false)
	if not add_cart.ok:
		return Result.failure("add cart_operator failed: %s" % add_cart.error)
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "cart_operator", "reports": []},
			{},
			{},
		],
	}
	state.milestone_pool = ["first_cart_operator"]
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_training_drink_capacity_upgrade_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	_force_route_turn_order(state, 2)
	var map_result := _build_route_marketing_sale_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	var house: Dictionary = Dictionary(Dictionary(state.map.get("houses", {})).get("house_route", {})).duplicate(true)
	house["demands"] = [
		{"product": "soda"},
		{"product": "soda"},
		{"product": "soda"},
		{"product": "soda"},
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	state.map["drink_sources"] = [
		{"world_pos": Vector2i(7, 2), "type": "soda", "tile_id": "R"},
	]
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 30)
	if not seed_cash.ok:
		return Result.failure("seed drink training route cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 0,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[0]["employees"] = ["ceo"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["employees_staff_ids"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["staff_registry"] = {}
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for employee_id in ["trainer", "errand_boy"]:
		var take_active := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [employee_id, add_active.error])
	for reserve_employee_id in ["errand_boy", "kitchen_trainee", "marketing_trainee"]:
		var take_reserve := StateUpdaterClass.take_from_pool(state, reserve_employee_id, 1)
		if not take_reserve.ok:
			return Result.failure("take %s failed: %s" % [reserve_employee_id, take_reserve.error])
		var add_reserve := StateUpdaterClass.add_employee(state, 0, reserve_employee_id, true)
		if not add_reserve.ok:
			return Result.failure("add %s failed: %s" % [reserve_employee_id, add_reserve.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "trainer", "reports": []},
			{"employee_id": "errand_boy", "reports": []},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.current_player_index = 0
	state.milestone_pool = ["first_train", "first_cart_operator"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _force_route_turn_order(state: GameState, player_count: int) -> void:
	state.turn_order.clear()
	for i in range(player_count):
		state.turn_order.append(i)
	state.current_player_index = 0

static func _build_route_marketing_sale_map(owner: int) -> Result:
	var grid_size := Vector2i(8, 6)
	var cells := _build_route_empty_cells(grid_size)

	for y in range(grid_size.y):
		var dirs: Array = []
		if y > 0:
			dirs.append("N")
		if y < grid_size.y - 1:
			dirs.append("S")
		_set_route_road(cells, Vector2i(0, y), dirs.duplicate())
		_set_route_road(cells, Vector2i(6, y), dirs.duplicate())
	for x in range(0, 7):
		var dirs2: Array = []
		if x > 0:
			dirs2.append("W")
		if x < 6:
			dirs2.append("E")
		_set_route_road(cells, Vector2i(x, 5), dirs2)
	_set_route_road(cells, Vector2i(0, 5), ["N", "E"])
	_set_route_road(cells, Vector2i(6, 5), ["N", "W"])

	var house_cells: Array[Vector2i] = [
		Vector2i(4, 2), Vector2i(5, 2),
		Vector2i(4, 3), Vector2i(5, 3),
	]
	var rest_cells: Array[Vector2i] = [
		Vector2i(4, 4), Vector2i(5, 4),
	]
	_set_route_house(cells, "house_route", 1, house_cells)
	_set_route_restaurant(cells, "rest_0", owner, rest_cells)

	return Result.success({
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 2),
		"cells": cells,
		"houses": {
			"house_route": {
				"house_id": "house_route",
				"house_number": 1,
				"anchor_pos": Vector2i(4, 2),
				"cells": house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": [],
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": owner,
				"anchor_pos": Vector2i(4, 4),
				"entrance_pos": Vector2i(6, 4),
				"cells": rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {},
	})

static func _build_first_cart_operator_range_bonus_map(owner: int) -> Result:
	var grid_size := Vector2i(20, 5)
	var cells := _build_route_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_route_road(cells, Vector2i(x, 1), dirs)

	var house_cells: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(2, 3), Vector2i(3, 3),
	]
	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 0),
	]
	_set_route_house(cells, "house_route", 1, house_cells)
	_set_route_restaurant(cells, "rest_0", owner, rest_cells)

	return Result.success({
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(4, 1),
		"cells": cells,
		"houses": {
			"house_route": {
				"house_id": "house_route",
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"cells": house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": [
					{"product": "soda"},
					{"product": "soda"},
				],
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": owner,
				"anchor_pos": Vector2i(0, 0),
				"entrance_pos": Vector2i(0, 0),
				"cells": rest_cells,
			},
		},
		"drink_sources": [
			{"world_pos": Vector2i(19, 0), "type": "soda", "tile_id": "C"},
		],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {},
	})

static func _build_route_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false,
			})
		cells.append(row)
	return cells

static func _set_route_road(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_route_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": false,
			"dynamic": true,
		}

static func _set_route_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"restaurant_id": restaurant_id,
			"owner": owner,
			"dynamic": true,
		}

static func _advance_direct_payday_to_marketing(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	state.current_player_index = 0
	var adv := engine.phase_manager.advance_phase(state)
	if not adv.ok:
		return Result.failure("advance Payday to Marketing failed: %s" % adv.error)
	state = engine.get_state()
	var marketing_report_val = state.round_state.get("marketing", null)
	if not (marketing_report_val is Dictionary):
		return Result.failure("Marketing settlement report missing after advance")
	return Result.success()

static func _prepare_next_round_restructuring(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.round_number += 1
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.sub_phase = ""
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var player: Dictionary = state.players[0]
	player["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	state.players[0] = player
	return _sync_initial_checkpoint_to_current_state(engine)

static func _prepare_next_round_get_food(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	return _sync_initial_checkpoint_to_current_state(engine)

static func _reset_round_state_for_ai_step(state: GameState) -> void:
	if state == null:
		return
	state.round_state["mandatory_actions_completed"] = {
		0: [],
		1: [],
	}
	state.round_state["actions_this_round"] = []
	state.round_state["action_counts"] = {}
	state.round_state["sub_phase_passed"] = {
		0: false,
		1: false,
	}
	state.round_state["train_events"] = []
	state.round_state["staff_usage"] = {}
	state.round_state["staff_train_event_counts"] = {}

static func _state_product_demand_count(state: GameState, product_id: String) -> int:
	if state == null or product_id.is_empty():
		return 0
	var houses_val = state.map.get("houses", {})
	if not (houses_val is Dictionary):
		return 0
	var total := 0
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		var demands_val = Dictionary(house_val).get("demands", [])
		if not (demands_val is Array):
			continue
		for demand_val in Array(demands_val):
			if demand_val is Dictionary and str(Dictionary(demand_val).get("product", "")) == product_id:
				total += 1
	return total

static func _player_inventory_units_for_product(state: GameState, player_id: int, product_id: String) -> int:
	if state == null or product_id.is_empty() or player_id < 0 or player_id >= state.players.size():
		return 0
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return 0
	var inventory_val = Dictionary(player_val).get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	return maxi(0, int(Dictionary(inventory_val).get(product_id, 0)))

static func _scenario_failure(name: String, result: Result) -> Result:
	return Result.failure("%s failed: %s" % [name, result.error])

static func _scenario_marketing_pipeline_requires_active_food_supply() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["cash"] = 20
	observation.own_player["employees"] = ["campaign_manager"]
	observation.own_player["reserve_employees"] = ["kitchen_trainee", "errand_boy"]
	observation.own_player["inventory"] = {}
	_set_observation_house_demand_count(observation, "house_near", "burger", 0)

	var kitchen_macro := MacroAction.create(
		"structure_kitchen_for_marketing",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 0, "employee_id": "kitchen_trainee"})],
		0.0,
		["restructuring", "direct"],
		{}
	)
	var errand_macro := MacroAction.create(
		"structure_errand_without_food",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 0, "employee_id": "errand_boy"})],
		0.0,
		["restructuring", "direct"],
		{}
	)
	var submit_macro := MacroAction.create(
		"submit_without_food_supply",
		[Command.create("submit_restructuring", 0, {})],
		0.0,
		["restructuring"],
		{}
	)

	var kitchen_score: Dictionary = StrategyScorerClass.score_macro(observation, kitchen_macro, profile)
	var errand_score: Dictionary = StrategyScorerClass.score_macro(observation, errand_macro, profile)
	var submit_score: Dictionary = StrategyScorerClass.score_macro(observation, submit_macro, profile)
	if float(kitchen_score.get("score", 0.0)) <= float(errand_score.get("score", 0.0)):
		return Result.failure("expected active burger supply to beat unrelated drink supply: kitchen=%s errand=%s" % [str(kitchen_score), str(errand_score)])
	if float(kitchen_score.get("score", 0.0)) <= float(submit_score.get("score", 0.0)):
		return Result.failure("expected active burger supply to beat submitting structure: kitchen=%s submit=%s" % [str(kitchen_score), str(submit_score)])
	var features: Dictionary = Dictionary(kitchen_score.get("features", {}))
	var marketing_products: Array = Array(features.get("structure_marketing_supply_products", []))
	if not marketing_products.has("burger"):
		return Result.failure("expected burger in structure_marketing_supply_products: %s" % str(features))
	return Result.success()

static func _scenario_trainable_supply_stays_structure_candidate(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["employees"] = ["trainer", "campaign_manager"]
	observation.own_player["reserve_employees"] = ["burger_cook", "errand_boy"]
	observation.own_player["inventory"] = {}
	observation.own_player["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	observation.employee_pool_public = {
		"burger_chef": 2,
		"cart_operator": 2,
	}
	_set_observation_house_demand_count(observation, "house_near", "burger", 4)

	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_RESTRUCTURING,
		"",
		1,
		seed_val,
		[]
	)
	var generated := CandidateGeneratorClass.generate(
		observation,
		context,
		["set_company_structure_direct", "submit_restructuring"],
		Callable(),
		{"max_valid_per_action": 12}
	)
	if not generated.ok:
		return generated
	var candidates: Array = Array(Dictionary(generated.value).get("candidates", []))
	var candidate_ids: Array[String] = []
	for candidate_val in candidates:
		if not (candidate_val is MacroAction):
			continue
		var candidate: MacroAction = candidate_val
		candidate_ids.append(str(candidate.id))
		if str(candidate.id).find("burger_cook") >= 0:
			return Result.success()
	return Result.failure("expected burger_cook direct structure candidate while trainer exists: %s" % str(candidate_ids))

static func _scenario_pending_marketing_drink_supply_deferred_without_fridge() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_drink_route_observation()
	_set_observation_house_demand_count(observation, "house_near", "soda", 0)
	observation.own_player["milestones"] = []
	observation.marketing_instances_public = [
		{"owner": 0, "product": "beer", "remaining_duration": 2},
	]

	var beer_macro := MacroAction.create(
		"procure_route_beer_without_fridge",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [8, 2]], "selected_sources": [[8, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)

	var beer_score: Dictionary = StrategyScorerClass.score_macro(observation, beer_macro, profile)
	var beer_features: Dictionary = Dictionary(beer_score.get("features", {}))
	if int(beer_features.get("product_pending_marketing_demand", 0)) != 1:
		return Result.failure("expected product_pending_marketing_demand=1: %s" % str(beer_features))
	if bool(beer_features.get("product_future_supply_storage_available", true)):
		return Result.failure("expected no future storage without fridge: %s" % str(beer_features))
	if not bool(beer_features.get("product_pending_marketing_supply_deferred", false)):
		return Result.failure("expected pending marketing supply to be deferred without fridge: %s" % str(beer_features))
	if int(beer_features.get("product_supply_future_covered_units", 0)) != 0:
		return Result.failure("expected no future supply coverage without fridge: %s" % str(beer_features))
	if int(beer_features.get("product_effective_pending_marketing_demand", -1)) != 0:
		return Result.failure("expected effective pending demand=0 without fridge: %s" % str(beer_features))
	return Result.success()

static func _scenario_pending_marketing_drink_supply_targets_product_with_fridge() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_drink_route_observation()
	_set_observation_house_demand_count(observation, "house_near", "soda", 0)
	observation.own_player["milestones"] = ["first_throw_away"]
	observation.marketing_instances_public = [
		{"owner": 0, "product": "beer", "remaining_duration": 2},
	]

	var soda_macro := MacroAction.create(
		"procure_route_soda_without_pending",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [4, 2]], "selected_sources": [[4, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var beer_macro := MacroAction.create(
		"procure_route_beer_for_pending_with_fridge",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [8, 2]], "selected_sources": [[8, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)

	var soda_score: Dictionary = StrategyScorerClass.score_macro(observation, soda_macro, profile)
	var beer_score: Dictionary = StrategyScorerClass.score_macro(observation, beer_macro, profile)
	if float(beer_score.get("score", 0.0)) <= float(soda_score.get("score", 0.0)):
		return Result.failure("expected beer route to beat soda route for pending beer marketing with fridge: beer=%s soda=%s" % [str(beer_score), str(soda_score)])
	var beer_features: Dictionary = Dictionary(beer_score.get("features", {}))
	if int(beer_features.get("product_pending_marketing_demand", 0)) != 1:
		return Result.failure("expected product_pending_marketing_demand=1: %s" % str(beer_features))
	if not bool(beer_features.get("product_future_supply_storage_available", false)):
		return Result.failure("expected future storage with fridge: %s" % str(beer_features))
	if bool(beer_features.get("product_pending_marketing_supply_deferred", false)):
		return Result.failure("expected pending marketing supply not to be deferred with fridge: %s" % str(beer_features))
	if int(beer_features.get("product_supply_future_covered_units", 0)) != 1:
		return Result.failure("expected pending beer supply to cover one future unit with fridge: %s" % str(beer_features))
	if int(beer_features.get("product_effective_pending_marketing_demand", 0)) != 1:
		return Result.failure("expected effective pending demand=1 with fridge: %s" % str(beer_features))
	return Result.success()

static func _scenario_income_route_first_recruit_gets_food_supply(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["employees"] = []
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {}
	observation.employee_pool_public = _base_income_recruit_pool()
	var chosen_read := _best_recruit_candidate(observation, seed_val)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("role", "")) != "produce_food":
		return Result.failure("expected first income recruit to be food supply, got %s" % str(chosen))
	return Result.success()

static func _scenario_income_route_recruits_marketing_after_food_supply(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["employees"] = ["burger_cook"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {}
	observation.employee_pool_public = _base_income_recruit_pool()
	_set_observation_house_demand_count(observation, "house_near", "burger", 2)
	var chosen_read := _best_recruit_candidate(observation, seed_val)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("role", "")) != "marketing":
		return Result.failure("expected income route to add marketing after food supply, got %s" % str(chosen))
	return Result.success()

static func _scenario_income_route_recruits_drink_supply_for_drink_demand(seed_val: int) -> Result:
	var observation := _synthetic_drink_route_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["employees"] = ["burger_cook", "campaign_manager"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {}
	observation.employee_pool_public = _base_income_recruit_pool()
	_set_observation_house_demand_count(observation, "house_near", "soda", 2)
	var chosen_read := _best_recruit_candidate(observation, seed_val)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("role", "")) != "procure_drink":
		return Result.failure("expected income route to add drink supply for drink demand, got %s" % str(chosen))
	return Result.success()

static func _scenario_income_route_recruits_pricing_after_stable_serviceable_demand(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["cash"] = 35
	observation.own_player["employees"] = ["burger_cook", "campaign_manager", "errand_boy"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 3}
	observation.own_player["milestones"] = []
	observation.employee_pool_public = _base_income_recruit_pool()
	observation.milestone_pool_public = ["first_lower_prices"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 3)
	var chosen_read := _best_recruit_candidate(observation, seed_val)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("employee_id", "")) != "pricing_manager":
		return Result.failure("expected stable income route to add pricing_manager before generic support, got %s" % str(chosen))
	var features: Dictionary = Dictionary(chosen.get("features", {}))
	if float(features.get("recruit_price_route_value", 0.0)) <= 0.0:
		return Result.failure("expected pricing route value feature on pricing_manager recruit: %s" % str(chosen))
	if not bool(features.get("recruit_price_route_first_lower_prices_available", false)):
		return Result.failure("expected pricing route to expose first_lower_prices availability: %s" % str(chosen))
	return Result.success()

static func _scenario_income_route_structures_pricing_after_price_recruit() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["cash"] = 35
	observation.own_player["employees"] = ["burger_cook", "campaign_manager", "pricing_manager", "trainer"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 3}
	observation.own_player["milestones"] = []
	observation.own_player["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "burger_cook", "reports": []},
			{"employee_id": "campaign_manager", "reports": []},
			{},
		],
	}
	observation.milestone_pool_public = ["first_lower_prices"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 3)

	var pricing_macro := MacroAction.create(
		"structure_pricing_for_stable_income_route",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 2, "employee_id": "pricing_manager"})],
		0.0,
		["restructuring", "direct"],
		{}
	)
	var trainer_macro := MacroAction.create(
		"structure_trainer_after_price_recruit",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 2, "employee_id": "trainer"})],
		0.0,
		["restructuring", "direct"],
		{}
	)
	var submit_macro := MacroAction.create(
		"submit_without_price_manager",
		[Command.create("submit_restructuring", 0, {})],
		0.0,
		["restructuring"],
		{}
	)

	var pricing_score: Dictionary = StrategyScorerClass.score_macro(observation, pricing_macro, profile)
	var trainer_score: Dictionary = StrategyScorerClass.score_macro(observation, trainer_macro, profile)
	var submit_score: Dictionary = StrategyScorerClass.score_macro(observation, submit_macro, profile)
	if float(pricing_score.get("score", 0.0)) <= float(trainer_score.get("score", 0.0)):
		return Result.failure("expected pricing_manager structure to beat trainer after price recruit: pricing=%s trainer=%s" % [str(pricing_score), str(trainer_score)])
	if float(pricing_score.get("score", 0.0)) <= float(submit_score.get("score", 0.0)):
		return Result.failure("expected pricing_manager structure to beat submit after price recruit: pricing=%s submit=%s" % [str(pricing_score), str(submit_score)])
	var features: Dictionary = Dictionary(pricing_score.get("features", {}))
	if float(features.get("structure_price_route_value", 0.0)) <= 0.0:
		return Result.failure("expected pricing structure route value feature: %s" % str(features))
	return Result.success()

static func _scenario_income_route_executes_price_action_after_price_structure(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	observation.own_player["cash"] = 35
	observation.own_player["employees"] = ["burger_cook", "campaign_manager", "pricing_manager"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 3}
	observation.own_player["milestones"] = []
	observation.round_state_public = {}
	_set_observation_house_demand_count(observation, "house_near", "burger", 3)
	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_WORKING,
		DefsClass.SUB_PHASE_GET_FOOD,
		int(observation.round_number),
		seed_val,
		[]
	)
	var bot = StrategyBotClass.new()
	var decision: BotDecision = bot.choose_command(
		observation,
		context,
		["set_price", "produce_food", "skip_sub_phase"],
		Callable(),
		null
	)
	if decision == null or decision.is_failure():
		return Result.failure("expected StrategyBot price decision, got %s" % (decision.failure_reason if decision != null else "null"))
	if decision.command == null or str(decision.command.action_id) != "set_price":
		return Result.failure("expected active pricing_manager to execute mandatory set_price, got %s" % str(decision.to_debug_dict()))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if int(features.get("price_action_delta", 0)) != -1:
		return Result.failure("expected set_price delta feature on price action: %s" % str(decision.to_debug_dict()))
	if int(features.get("price_estimated_sale_units", 0)) <= 0:
		return Result.failure("expected price action to estimate sale units from serviceable demand: %s" % str(decision.to_debug_dict()))
	var top_candidates: Array = Array(Dictionary(decision.trace).get("top_candidates", []))
	if top_candidates.is_empty() or str(Dictionary(top_candidates[0]).get("action_id", "")) != "set_price":
		return Result.failure("expected set_price to lead StrategyBot top candidates: %s" % str(decision.to_debug_dict()))
	return Result.success()

static func _scenario_income_route_recruits_waitress_after_price_support(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["cash"] = 35
	observation.own_player["employees"] = ["burger_cook", "campaign_manager", "errand_boy", "pricing_manager"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 3}
	observation.own_player["milestones"] = []
	observation.employee_pool_public = {
		"management_trainee": 1,
		"recruiting_girl": 1,
		"trainer": 2,
		"waitress": 1,
	}
	observation.milestone_pool_public = ["first_waitress"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 3)
	var pre_price_observation := _synthetic_food_income_observation()
	pre_price_observation.phase = observation.phase
	pre_price_observation.sub_phase = observation.sub_phase
	pre_price_observation.own_player["cash"] = 35
	pre_price_observation.own_player["employees"] = ["burger_cook", "campaign_manager", "errand_boy"]
	pre_price_observation.own_player["reserve_employees"] = []
	pre_price_observation.own_player["inventory"] = {"burger": 3}
	pre_price_observation.own_player["milestones"] = []
	pre_price_observation.milestone_pool_public = ["first_waitress"]
	_set_observation_house_demand_count(pre_price_observation, "house_near", "burger", 3)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var pre_price_waitress_macro := MacroAction.create(
		"recruit_waitress_before_price_support",
		[Command.create("recruit", 0, {"employee_type": "waitress"})],
		0.0,
		["recruit"],
		{}
	)
	var pre_price_waitress_score: Dictionary = StrategyScorerClass.score_macro(pre_price_observation, pre_price_waitress_macro, profile)
	var pre_price_features: Dictionary = Dictionary(pre_price_waitress_score.get("features", {}))
	if float(pre_price_features.get("recruit_waitress_route_value", 0.0)) != 0.0:
		return Result.failure("expected waitress route value to stay disabled before price support: %s" % str(pre_price_features))
	var chosen_read := _best_recruit_candidate(observation, seed_val)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("employee_id", "")) != "waitress":
		return Result.failure("expected stable income route with price support to add waitress, got %s" % str(chosen))
	var features: Dictionary = Dictionary(chosen.get("features", {}))
	if float(features.get("recruit_waitress_route_value", 0.0)) <= 0.0:
		return Result.failure("expected waitress route value feature on waitress recruit: %s" % str(chosen))
	if not bool(features.get("recruit_waitress_first_waitress_available", false)):
		return Result.failure("expected waitress recruit to expose first_waitress availability: %s" % str(chosen))
	return Result.success()

static func _scenario_income_route_structures_waitress_after_support_recruit() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["cash"] = 35
	observation.own_player["employees"] = ["burger_cook", "campaign_manager", "pricing_manager", "trainer", "waitress"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 3}
	observation.own_player["milestones"] = []
	observation.own_player["company_structure"] = {
		"ceo_slots": 4,
		"structure": [
			{"employee_id": "burger_cook", "reports": []},
			{"employee_id": "campaign_manager", "reports": []},
			{"employee_id": "pricing_manager", "reports": []},
			{},
		],
	}
	observation.milestone_pool_public = ["first_waitress"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 3)
	var waitress_macro := MacroAction.create(
		"activate_waitress_for_dinner_tips",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 3, "employee_id": "waitress"})],
		0.0,
		["restructuring", "structure"],
		{}
	)
	var trainer_macro := MacroAction.create(
		"activate_trainer_without_train_route",
		[Command.create("set_company_structure_direct", 0, {"slot_index": 3, "employee_id": "trainer"})],
		0.0,
		["restructuring", "structure"],
		{}
	)
	var submit_macro := MacroAction.create(
		"submit_without_waitress",
		[Command.create("submit_restructuring", 0, {})],
		0.0,
		["restructuring", "fallback"],
		{}
	)
	var waitress_score: Dictionary = StrategyScorerClass.score_macro(observation, waitress_macro, profile)
	var trainer_score: Dictionary = StrategyScorerClass.score_macro(observation, trainer_macro, profile)
	var submit_score: Dictionary = StrategyScorerClass.score_macro(observation, submit_macro, profile)
	if float(waitress_score.get("score", 0.0)) <= float(trainer_score.get("score", 0.0)):
		return Result.failure("expected waitress structure to beat idle trainer after support recruit: waitress=%s trainer=%s" % [str(waitress_score), str(trainer_score)])
	if float(waitress_score.get("score", 0.0)) <= float(submit_score.get("score", 0.0)):
		return Result.failure("expected waitress structure to beat submit after support recruit: waitress=%s submit=%s" % [str(waitress_score), str(submit_score)])
	var features: Dictionary = Dictionary(waitress_score.get("features", {}))
	if float(features.get("structure_waitress_route_value", 0.0)) <= 0.0:
		return Result.failure("expected waitress structure route value feature: %s" % str(features))
	return Result.success()

static func _scenario_milestone_third_recruit_values_first_hire_3() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["milestones"] = []
	observation.milestone_pool_public = ["first_hire_3"]
	observation.round_state_public = {
		"recruit_used": {
			0: 2,
		},
	}
	var recruit_macro := MacroAction.create(
		"third_recruit_for_first_hire_3",
		[Command.create("recruit", 0, {"employee_type": "trainer"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var score: Dictionary = StrategyScorerClass.score_macro(observation, recruit_macro, profile)
	var features: Dictionary = Dictionary(score.get("features", {}))
	if not Array(features.get("milestone_race_ids", [])).has("first_hire_3"):
		return Result.failure("expected third recruit to expose first_hire_3 race id: %s" % str(features))
	if float(features.get("milestone_race_value", 0.0)) <= 10.0:
		return Result.failure("expected first_hire_3 gain_cards effect to be materially valued: %s" % str(features))

	var early_observation := _synthetic_food_income_observation()
	early_observation.phase = DefsClass.PHASE_WORKING
	early_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	early_observation.own_player["milestones"] = []
	early_observation.milestone_pool_public = ["first_hire_3"]
	early_observation.round_state_public = {
		"recruit_used": {
			0: 1,
		},
	}
	var early_score: Dictionary = StrategyScorerClass.score_macro(early_observation, recruit_macro, profile)
	var early_features: Dictionary = Dictionary(early_score.get("features", {}))
	if Array(early_features.get("milestone_race_ids", [])).has("first_hire_3"):
		return Result.failure("first or second recruit should not claim immediate first_hire_3 race value: %s" % str(early_features))
	return Result.success()

static func _scenario_milestone_lower_price_ignores_luxury_price() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	observation.own_player["milestones"] = []
	observation.milestone_pool_public = ["first_lower_prices"]
	var discount_macro := MacroAction.create(
		"discount_triggers_first_lower_prices",
		[Command.create("set_discount", 0, {})],
		0.0,
		["working", "price"],
		{}
	)
	var luxury_macro := MacroAction.create(
		"luxury_price_does_not_lower_prices",
		[Command.create("set_luxury_price", 0, {})],
		0.0,
		["working", "price"],
		{}
	)
	var discount_score: Dictionary = StrategyScorerClass.score_macro(observation, discount_macro, profile)
	var discount_features: Dictionary = Dictionary(discount_score.get("features", {}))
	if not Array(discount_features.get("milestone_race_ids", [])).has("first_lower_prices"):
		return Result.failure("discount should expose first_lower_prices race id: %s" % str(discount_features))
	if float(discount_features.get("milestone_race_value", 0.0)) <= 4.0:
		return Result.failure("discount should include first_lower_prices base_price_delta effect value: %s" % str(discount_features))
	var luxury_score: Dictionary = StrategyScorerClass.score_macro(observation, luxury_macro, profile)
	var luxury_features: Dictionary = Dictionary(luxury_score.get("features", {}))
	if Array(luxury_features.get("milestone_race_ids", [])).has("first_lower_prices"):
		return Result.failure("luxury price should not expose first_lower_prices race id: %s" % str(luxury_features))
	if float(luxury_features.get("milestone_race_value", 0.0)) != 0.0:
		return Result.failure("luxury price should not receive lower-price race value: %s" % str(luxury_features))
	return Result.success()

static func _scenario_dinner_preview_values_cash_reached_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.players[0]["cash"] = 10
	state.players[0]["inventory"] = {}
	state.players[0]["milestones"] = []
	state.players[1]["inventory"] = {}
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_have_20"]
	var take := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take.ok:
		return Result.failure("cash milestone preview take kitchen_trainee failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "kitchen_trainee", false)
	if not add.ok:
		return Result.failure("cash milestone preview add kitchen_trainee failed: %s" % add.error)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read

	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var burger_macro := MacroAction.create(
		"produce_burger_reaches_cash_20",
		[Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, burger_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(score.get("features", {}))
	if str(features.get("product_dinner_preview_source", "")) != "dinner_preview":
		return Result.failure("cash milestone scenario should use DinnerPreview: %s" % str(features))
	if not Array(features.get("product_dinner_preview_milestone_ids", [])).has("first_have_20"):
		return Result.failure("expected DinnerPreview to expose first_have_20 cash milestone: %s" % str(features))
	if float(features.get("product_dinner_preview_milestone_value", 0.0)) <= 0.0:
		return Result.failure("expected DinnerPreview cash milestone to add positive value: %s" % str(features))
	return Result.success()

static func _scenario_dinner_preview_values_waitress_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.players[0]["cash"] = 0
	state.players[0]["inventory"] = {}
	state.players[0]["milestones"] = []
	state.players[1]["inventory"] = {}
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_waitress"]
	for employee_id in ["kitchen_trainee", "waitress"]:
		var take := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take.ok:
			return Result.failure("waitress milestone preview take %s failed: %s" % [employee_id, take.error])
		var add := StateUpdaterClass.add_employee(state, 0, employee_id, false)
		if not add.ok:
			return Result.failure("waitress milestone preview add %s failed: %s" % [employee_id, add.error])
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read

	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var burger_macro := MacroAction.create(
		"produce_burger_with_waitress_dinner_milestone",
		[Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, burger_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(score.get("features", {}))
	if str(features.get("product_dinner_preview_source", "")) != "dinner_preview":
		return Result.failure("waitress milestone scenario should use DinnerPreview: %s" % str(features))
	if not Array(features.get("product_dinner_preview_milestone_ids", [])).has("first_waitress"):
		return Result.failure("expected DinnerPreview to expose first_waitress milestone: %s" % str(features))
	if float(features.get("product_dinner_preview_milestone_value", 0.0)) <= 0.0:
		return Result.failure("expected DinnerPreview waitress milestone to add positive value: %s" % str(features))
	return Result.success()

static func _scenario_milestone_marketing_sell_bonus_is_valued() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_MARKETING
	observation.own_player["employees"] = ["campaign_manager", "burger_cook"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 1}
	observation.own_player["milestones"] = []
	observation.milestone_pool_public = ["first_burger_marketed"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 0)
	var macro := MacroAction.create(
		"market_burger_for_sell_bonus",
		[Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager", "marketing_type": "mailbox", "board_number": 8, "product": "burger", "position": [2, 2]})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_near"]}
	)
	var score: Dictionary = StrategyScorerClass.score_macro(observation, macro, profile)
	var features: Dictionary = Dictionary(score.get("features", {}))
	var race_ids: Array = Array(features.get("milestone_race_ids", []))
	if not race_ids.has("first_burger_marketed"):
		return Result.failure("expected first_burger_marketed race id: %s" % str(features))
	if float(features.get("milestone_race_value", 0.0)) <= 5.0:
		return Result.failure("expected sell_bonus effect to raise marketing milestone value above base value: %s" % str(features))
	return Result.success()

static func _scenario_milestone_airplane_trigger_uses_marketing_board() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_MARKETING
	observation.own_player["employees"] = ["campaign_manager", "burger_cook", "zeppelin_pilot"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 1}
	observation.own_player["milestones"] = []
	observation.milestone_pool_public = ["first_airplane"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 0)
	var airplane_macro := MacroAction.create(
		"market_airplane_for_turn_order",
		[Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager", "marketing_type": "airplane", "board_number": 4, "product": "burger", "position": [2, 2]})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_near"]}
	)
	var airplane_score: Dictionary = StrategyScorerClass.score_macro(observation, airplane_macro, profile)
	var airplane_features: Dictionary = Dictionary(airplane_score.get("features", {}))
	if not Array(airplane_features.get("milestone_race_ids", [])).has("first_airplane"):
		return Result.failure("expected airplane marketing to expose first_airplane race id: %s" % str(airplane_features))
	if float(airplane_features.get("milestone_race_value", 0.0)) <= 7.0:
		return Result.failure("expected first_airplane effect to raise value above base value: %s" % str(airplane_features))

	var zeppelin_macro := MacroAction.create(
		"zeppelin_drink_route_should_not_trigger_airplane",
		[Command.create("procure_drinks", 0, {"employee_type": "zeppelin_pilot", "restaurant_id": "rest_near", "route": [[3, 2], [4, 2]], "selected_sources": [[4, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var zeppelin_score: Dictionary = StrategyScorerClass.score_macro(observation, zeppelin_macro, profile)
	var zeppelin_features: Dictionary = Dictionary(zeppelin_score.get("features", {}))
	if Array(zeppelin_features.get("milestone_race_ids", [])).has("first_airplane"):
		return Result.failure("zeppelin drink procurement must not expose first_airplane race id: %s" % str(zeppelin_features))
	return Result.success()

static func _scenario_milestone_effect_values_base_support() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var checks: Array[Dictionary] = [
		{"id": "first_waitress", "min": 8.0, "effect": "waitress_tips"},
		{"id": "first_throw_away", "min": 12.0, "effect": "gain_fridge"},
		{"id": "first_pay_20_salaries", "min": 10.0, "effect": "multi_trainer_on_one"},
		{"id": "first_radio", "min": 14.0, "effect": "extra_marketing"},
		{"id": "first_cart_operator", "min": 12.0, "effect": "distance_plus_one"},
	]
	for check in checks:
		var milestone_id := str(check.get("id", ""))
		var min_value := float(check.get("min", 0.0))
		var value := MilestoneRaceAnalyzerClass.milestone_value(milestone_id, profile)
		if value < min_value:
			return Result.failure(
				"expected %s to value %s effect at least %.1f, got %.1f" % [
					milestone_id,
					str(check.get("effect", "")),
					min_value,
					value,
				]
			)
	return Result.success()

static func _best_recruit_candidate(observation: ObservationState, seed_val: int) -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_WORKING,
		DefsClass.SUB_PHASE_RECRUIT,
		int(observation.round_number),
		seed_val,
		[]
	)
	var generated := CandidateGeneratorClass.generate(
		observation,
		context,
		["recruit", "skip_sub_phase"],
		Callable(),
		{"max_valid_per_action": 16}
	)
	if not generated.ok:
		return generated
	var candidates: Array = Array(Dictionary(generated.value).get("candidates", []))
	var best := {}
	var best_score := -INF
	var ranked: Array[Dictionary] = []
	for candidate_val in candidates:
		if not (candidate_val is MacroAction):
			continue
		var candidate: MacroAction = candidate_val
		if candidate.commands.is_empty():
			continue
		var command: Command = candidate.commands[0]
		var score_payload: Dictionary = StrategyScorerClass.score_macro(observation, candidate, profile)
		var score := float(score_payload.get("score", -INF))
		var employee_id := str(command.params.get("employee_type", ""))
		var role := _employee_role(employee_id)
		var item := {
			"macro_action_id": str(candidate.id),
			"action_id": str(command.action_id),
			"employee_id": employee_id,
			"role": role,
			"score": score,
			"features": Dictionary(score_payload.get("features", {})).duplicate(true),
		}
		ranked.append(item)
		if best.is_empty() or score > best_score or (is_equal_approx(score, best_score) and str(candidate.id) < str(best.get("macro_action_id", ""))):
			best = item
			best_score = score
	if best.is_empty():
		return Result.failure("expected recruit candidates, got %s" % str(ranked))
	best["top_candidates"] = _sorted_top_candidates(ranked, 5)
	return Result.success(best)

static func _sorted_top_candidates(candidates: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var out := candidates.duplicate(true)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ascore := float(a.get("score", 0.0))
		var bscore := float(b.get("score", 0.0))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		return str(a.get("macro_action_id", "")) < str(b.get("macro_action_id", ""))
	)
	return out.slice(0, maxi(0, limit))

static func _base_income_recruit_pool() -> Dictionary:
	return {
		"burger_cook": 2,
		"campaign_manager": 2,
		"errand_boy": 2,
		"kitchen_trainee": 4,
		"management_trainee": 2,
		"marketing_trainee": 4,
		"pricing_manager": 1,
		"recruiting_girl": 1,
		"trainer": 2,
	}

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func _synthetic_food_income_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.current_player_id = 0
	observation.round_number = 4
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	observation.rules_public = {
		"salary_cost": 5,
	}
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["burger_cook", "pizza_cook"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
		"company_structure": {
			"ceo_slots": 3,
			"structure": [{}, {}, {}],
		},
	}
	observation.map_public = {
		"grid_size": Vector2i(12, 12),
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
					{"product": "burger"},
					{"product": "burger"},
				],
			},
		},
		"restaurants": {
			"rest_near": {
				"restaurant_id": "rest_near",
				"owner": 0,
				"anchor_pos": Vector2i(3, 2),
			},
		},
	}
	return observation

static func _synthetic_drink_route_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.current_player_id = 0
	observation.round_number = 4
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	observation.rules_public = {
		"salary_cost": 5,
	}
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["truck_driver"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
		"milestones": [],
	}
	observation.map_public = {
		"grid_size": Vector2i(12, 12),
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
					{"product": "soda"},
					{"product": "soda"},
				],
			},
		},
		"restaurants": {
			"rest_near": {
				"restaurant_id": "rest_near",
				"owner": 0,
				"anchor_pos": Vector2i(3, 2),
			},
		},
		"drink_sources": [
			{"world_pos": Vector2i(4, 2), "type": "soda"},
			{"world_pos": Vector2i(8, 2), "type": "beer"},
		],
	}
	return observation

static func _set_observation_house_demand_count(observation: ObservationState, house_id: String, product_id: String, count: int) -> void:
	if observation == null or house_id.is_empty() or product_id.is_empty():
		return
	var houses: Dictionary = Dictionary(observation.map_public.get("houses", {})).duplicate(true)
	var house: Dictionary = Dictionary(houses.get(house_id, {})).duplicate(true)
	var demands: Array = []
	for _i in range(maxi(0, count)):
		demands.append({"product": product_id})
	house["demands"] = demands
	houses[house_id] = house
	observation.map_public["houses"] = houses

static func _sync_initial_checkpoint_to_current_state(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if engine.checkpoints.is_empty():
		return Result.failure("engine has no initial checkpoint")
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	var checkpoint: Dictionary = engine.checkpoints[0]
	checkpoint["state_dict"] = state.to_dict().duplicate(true)
	checkpoint["hash"] = state.compute_hash()
	engine.checkpoints[0] = checkpoint
	engine.command_history.clear()
	engine.current_command_index = -1
	return Result.success()
