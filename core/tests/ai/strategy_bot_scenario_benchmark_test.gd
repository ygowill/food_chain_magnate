class_name StrategyBotScenarioBenchmarkTest
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
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

	var marketing_sell_bonus := _scenario_milestone_marketing_sell_bonus_is_valued()
	if not marketing_sell_bonus.ok:
		return _scenario_failure("milestone_marketing_sell_bonus_is_valued", marketing_sell_bonus)
	names.append("milestone_marketing_sell_bonus_is_valued")

	var airplane_trigger := _scenario_milestone_airplane_trigger_uses_marketing_board()
	if not airplane_trigger.ok:
		return _scenario_failure("milestone_airplane_trigger_uses_marketing_board", airplane_trigger)
	names.append("milestone_airplane_trigger_uses_marketing_board")

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
