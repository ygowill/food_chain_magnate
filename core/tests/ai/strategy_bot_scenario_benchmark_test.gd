class_name StrategyBotScenarioBenchmarkTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const MilestoneRaceAnalyzerClass = preload("res://core/ai/analysis/milestone_race_analyzer.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var registry_read := _load_registries(seed_val)
	if not registry_read.ok:
		return registry_read

	var names: Array[String] = []
	var initial_opening := _scenario_initial_restaurant_opening_prefers_competitive_position(seed_val)
	if not initial_opening.ok:
		return _scenario_failure("initial_restaurant_opening_prefers_competitive_position", initial_opening)
	names.append("initial_restaurant_opening_prefers_competitive_position")

	var second_opening := _scenario_second_restaurant_opening_avoids_competitor_dominated_cluster(seed_val)
	if not second_opening.ok:
		return _scenario_failure("second_restaurant_opening_avoids_competitor_dominated_cluster", second_opening)
	names.append("second_restaurant_opening_avoids_competitor_dominated_cluster")

	var second_opening_serviceable := _scenario_second_restaurant_opening_avoids_competitor_dominated_cluster(330028)
	if not second_opening_serviceable.ok:
		return _scenario_failure("second_restaurant_opening_requires_serviceable_route", second_opening_serviceable)
	names.append("second_restaurant_opening_requires_serviceable_route")

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

	var early_income_route := _scenario_early_income_route_trains_markets_structures_produces_and_sells(seed_val)
	if not early_income_route.ok:
		return _scenario_failure("early_income_route_trains_markets_structures_produces_and_sells", early_income_route)
	names.append("early_income_route_trains_markets_structures_produces_and_sells")

	var marketing_upgrade_route := _scenario_blocked_billboard_route_trains_campaign_manager_markets_and_sells(seed_val)
	if not marketing_upgrade_route.ok:
		return _scenario_failure("blocked_billboard_route_trains_campaign_manager_markets_and_sells", marketing_upgrade_route)
	names.append("blocked_billboard_route_trains_campaign_manager_markets_and_sells")

	var marketing_candidate_diversity := _scenario_marketing_generation_preserves_mailbox_candidates_under_cap(seed_val)
	if not marketing_candidate_diversity.ok:
		return _scenario_failure("marketing_generation_preserves_mailbox_candidates_under_cap", marketing_candidate_diversity)
	names.append("marketing_generation_preserves_mailbox_candidates_under_cap")

	var marketing_competition_filter := _scenario_marketing_generation_discards_competitor_captured_candidates(seed_val)
	if not marketing_competition_filter.ok:
		return _scenario_failure("marketing_generation_discards_competitor_captured_candidates", marketing_competition_filter)
	names.append("marketing_generation_discards_competitor_captured_candidates")

	var recovery_customer_switch := _scenario_recovery_customer_switch_values_alternate_house(seed_val)
	if not recovery_customer_switch.ok:
		return _scenario_failure("recovery_customer_switch_values_alternate_house", recovery_customer_switch)
	names.append("recovery_customer_switch_values_alternate_house")

	var recovery_price_action := _scenario_recovery_price_action_recovers_lost_demand(seed_val)
	if not recovery_price_action.ok:
		return _scenario_failure("recovery_price_action_recovers_lost_demand", recovery_price_action)
	names.append("recovery_price_action_recovers_lost_demand")

	var recovery_product_switch := _scenario_recovery_product_switch_marketing_targets_opponent_capacity_gap(seed_val)
	if not recovery_product_switch.ok:
		return _scenario_failure("recovery_product_switch_marketing_targets_opponent_capacity_gap", recovery_product_switch)
	names.append("recovery_product_switch_marketing_targets_opponent_capacity_gap")

	var billboard_marketing_route := _scenario_billboard_marketing_claims_first_billboard_and_sells(seed_val)
	if not billboard_marketing_route.ok:
		return _scenario_failure("billboard_marketing_claims_first_billboard_and_sells", billboard_marketing_route)
	names.append("billboard_marketing_claims_first_billboard_and_sells")

	var radio_marketing_route := _scenario_radio_marketing_claims_first_radio_and_sells(seed_val)
	if not radio_marketing_route.ok:
		return _scenario_failure("radio_marketing_claims_first_radio_and_sells", radio_marketing_route)
	names.append("radio_marketing_claims_first_radio_and_sells")

	var airplane_marketing_route := _scenario_airplane_marketing_claims_first_airplane_and_sells(seed_val)
	if not airplane_marketing_route.ok:
		return _scenario_failure("airplane_marketing_claims_first_airplane_and_sells", airplane_marketing_route)
	names.append("airplane_marketing_claims_first_airplane_and_sells")

	var drink_marketing_route := _scenario_drink_marketing_claims_first_drink_marketed_and_sells(seed_val)
	if not drink_marketing_route.ok:
		return _scenario_failure("drink_marketing_claims_first_drink_marketed_and_sells", drink_marketing_route)
	names.append("drink_marketing_claims_first_drink_marketed_and_sells")

	var pizza_marketing_route := _scenario_pizza_marketing_claims_first_pizza_marketed_and_sells(seed_val)
	if not pizza_marketing_route.ok:
		return _scenario_failure("pizza_marketing_claims_first_pizza_marketed_and_sells", pizza_marketing_route)
	names.append("pizza_marketing_claims_first_pizza_marketed_and_sells")

	var training_food_supply := _scenario_income_route_trains_food_supply_for_serviceable_demand(seed_val)
	if not training_food_supply.ok:
		return _scenario_failure("income_route_trains_food_supply_for_serviceable_demand", training_food_supply)
	names.append("income_route_trains_food_supply_for_serviceable_demand")

	var first_train_salary_delta := _scenario_first_train_salary_delta_reduces_payday_due(seed_val)
	if not first_train_salary_delta.ok:
		return _scenario_failure("first_train_salary_delta_reduces_payday_due", first_train_salary_delta)
	names.append("first_train_salary_delta_reduces_payday_due")

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

	var cleanup_fridge_keep := _scenario_cleanup_fridge_keep_prioritizes_pending_marketing(seed_val)
	if not cleanup_fridge_keep.ok:
		return _scenario_failure("cleanup_fridge_keep_prioritizes_pending_marketing", cleanup_fridge_keep)
	names.append("cleanup_fridge_keep_prioritizes_pending_marketing")

	var first_errand_boy := _scenario_first_errand_boy_counts_two_drinks(seed_val)
	if not first_errand_boy.ok:
		return _scenario_failure("first_errand_boy_counts_two_drinks", first_errand_boy)
	names.append("first_errand_boy_counts_two_drinks")

	var burger_produced_route := _scenario_burger_demand_claims_first_burger_produced_and_sells(seed_val)
	if not burger_produced_route.ok:
		return _scenario_failure("burger_demand_claims_first_burger_produced_and_sells", burger_produced_route)
	names.append("burger_demand_claims_first_burger_produced_and_sells")

	var pizza_produced_route := _scenario_pizza_demand_claims_first_pizza_produced_and_sells(seed_val)
	if not pizza_produced_route.ok:
		return _scenario_failure("pizza_demand_claims_first_pizza_produced_and_sells", pizza_produced_route)
	names.append("pizza_demand_claims_first_pizza_produced_and_sells")

	var route_drink_sale := _scenario_route_drink_demand_produces_and_sells(seed_val)
	if not route_drink_sale.ok:
		return _scenario_failure("route_drink_demand_produces_and_sells", route_drink_sale)
	names.append("route_drink_demand_produces_and_sells")

	var drink_structure := _scenario_income_route_structures_drink_supply_for_serviceable_demand(seed_val)
	if not drink_structure.ok:
		return _scenario_failure("income_route_structures_drink_supply_for_serviceable_demand", drink_structure)
	names.append("income_route_structures_drink_supply_for_serviceable_demand")

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

	var pricing_opportunity_recruit := _scenario_income_route_recruits_pricing_for_serviceable_price_opportunity(seed_val)
	if not pricing_opportunity_recruit.ok:
		return _scenario_failure("income_route_recruits_pricing_for_serviceable_price_opportunity", pricing_opportunity_recruit)
	names.append("income_route_recruits_pricing_for_serviceable_price_opportunity")

	var pricing_structure := _scenario_income_route_structures_pricing_after_price_recruit()
	if not pricing_structure.ok:
		return _scenario_failure("income_route_structures_pricing_after_price_recruit", pricing_structure)
	names.append("income_route_structures_pricing_after_price_recruit")

	var pricing_action := _scenario_income_route_executes_price_action_after_price_structure(seed_val)
	if not pricing_action.ok:
		return _scenario_failure("income_route_executes_price_action_after_price_structure", pricing_action)
	names.append("income_route_executes_price_action_after_price_structure")

	var pricing_action_milestone := _scenario_income_route_price_action_claims_lower_price_milestone(seed_val)
	if not pricing_action_milestone.ok:
		return _scenario_failure("income_route_price_action_claims_lower_price_milestone", pricing_action_milestone)
	names.append("income_route_price_action_claims_lower_price_milestone")

	var pricing_contested_sale := _scenario_income_route_price_action_wins_contested_sale(seed_val)
	if not pricing_contested_sale.ok:
		return _scenario_failure("income_route_price_action_wins_contested_sale", pricing_contested_sale)
	names.append("income_route_price_action_wins_contested_sale")

	var waitress_recruit := _scenario_income_route_recruits_waitress_after_price_support(seed_val)
	if not waitress_recruit.ok:
		return _scenario_failure("income_route_recruits_waitress_after_price_support", waitress_recruit)
	names.append("income_route_recruits_waitress_after_price_support")

	var waitress_structure := _scenario_income_route_structures_waitress_after_support_recruit()
	if not waitress_structure.ok:
		return _scenario_failure("income_route_structures_waitress_after_support_recruit", waitress_structure)
	names.append("income_route_structures_waitress_after_support_recruit")

	var waitress_active_route := _scenario_waitress_active_route_claims_first_waitress_and_tips(seed_val)
	if not waitress_active_route.ok:
		return _scenario_failure("waitress_active_route_claims_first_waitress_and_tips", waitress_active_route)
	names.append("waitress_active_route_claims_first_waitress_and_tips")

	var payday_fire := _scenario_payday_fire_resolves_shortfall_with_low_income_employee(seed_val)
	if not payday_fire.ok:
		return _scenario_failure("payday_fire_resolves_shortfall_with_low_income_employee", payday_fire)
	names.append("payday_fire_resolves_shortfall_with_low_income_employee")

	var payday_salary_milestone := _scenario_payday_keeps_staff_to_claim_first_pay_20_salaries(seed_val)
	if not payday_salary_milestone.ok:
		return _scenario_failure("payday_keeps_staff_to_claim_first_pay_20_salaries", payday_salary_milestone)
	names.append("payday_keeps_staff_to_claim_first_pay_20_salaries")

	var third_recruit_route := _scenario_third_recruit_claims_first_hire_3_with_real_recruit_action(seed_val)
	if not third_recruit_route.ok:
		return _scenario_failure("third_recruit_claims_first_hire_3_with_real_recruit_action", third_recruit_route)
	names.append("third_recruit_claims_first_hire_3_with_real_recruit_action")

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

	var cash_100_milestone := _scenario_dinner_preview_values_cash_100_milestone(seed_val)
	if not cash_100_milestone.ok:
		return _scenario_failure("dinner_preview_values_cash_100_milestone", cash_100_milestone)
	names.append("dinner_preview_values_cash_100_milestone")

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

static func _scenario_initial_restaurant_opening_prefers_competitive_position(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var bot0 = StrategyBotClass.new()
	var bot1 = StrategyBotClass.new()
	for bot in [bot0, bot1]:
		var configure_read: Result = bot.configure_profile("base_revenue_growth_v1")
		if not configure_read.ok:
			return configure_read
	var controller := BotControllerClass.new()
	var stop_condition := func(test_engine: GameEngine) -> bool:
		return _player_restaurant_count(test_engine.get_state(), 0) > 0
	var run_read := controller.run_until(
		engine,
		{0: bot0, 1: bot1},
		stop_condition,
		12,
		80
	)
	if not run_read.ok:
		return Result.failure("opening route run failed: %s" % run_read.error)
	var opening_trace := {}
	for trace_val in controller.last_trace:
		if not (trace_val is Dictionary):
			continue
		var trace: Dictionary = trace_val
		if int(trace.get("player_id", -1)) == 0 and str(trace.get("action_id", "")) == "place_restaurant":
			opening_trace = trace
			break
	if opening_trace.is_empty():
		return Result.failure("expected player 0 initial place_restaurant trace, got %s" % str(controller.last_trace))
	var params: Dictionary = Dictionary(opening_trace.get("params", {}))
	var pos := _read_position_array(params.get("position", []))
	if pos.is_empty():
		return Result.failure("expected player 0 opening to expose a placement position, trace=%s" % str(opening_trace))
	var explanation: Dictionary = Dictionary(opening_trace.get("explanation", {}))
	var features: Dictionary = Dictionary(explanation.get("features", {}))
	if features.is_empty():
		var decision_trace: Dictionary = Dictionary(opening_trace.get("decision_trace", {}))
		var top_candidates: Array = Array(decision_trace.get("top_candidates", []))
		if not top_candidates.is_empty() and top_candidates[0] is Dictionary:
			features = Dictionary(Dictionary(top_candidates[0]).get("features", {}))
	if float(features.get("restaurant_opening_robustness_value", 0.0)) <= 0.0:
		return Result.failure("opening trace should expose positive robustness value: trace=%s" % str(opening_trace))
	if int(features.get("restaurant_competitive_houses", 0)) <= 0:
		return Result.failure("expected player 0 to choose a competitive opening, pos=%s features=%s trace=%s" % [str(pos), str(features), str(opening_trace)])
	if int(features.get("restaurant_competitor_dominated_houses", 0)) > 0:
		return Result.failure("expected player 0 opening to avoid opponent-dominated houses, pos=%s features=%s trace=%s" % [str(pos), str(features), str(opening_trace)])
	return Result.success()

static func _scenario_second_restaurant_opening_avoids_competitor_dominated_cluster(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var bot0 = StrategyBotClass.new()
	var bot1 = StrategyBotClass.new()
	for bot in [bot0, bot1]:
		var configure_read: Result = bot.configure_profile("base_revenue_growth_v1")
		if not configure_read.ok:
			return configure_read
	var controller := BotControllerClass.new()
	var stop_condition := func(test_engine: GameEngine) -> bool:
		return _player_restaurant_count(test_engine.get_state(), 1) > 0
	var run_read := controller.run_until(
		engine,
		{0: bot0, 1: bot1},
		stop_condition,
		24,
		80
	)
	if not run_read.ok:
		return Result.failure("second opening route run failed: %s" % run_read.error)
	var opening_trace := {}
	for trace_val in controller.last_trace:
		if not (trace_val is Dictionary):
			continue
		var trace: Dictionary = trace_val
		if int(trace.get("player_id", -1)) == 1 and str(trace.get("action_id", "")) == "place_restaurant":
			opening_trace = trace
			break
	if opening_trace.is_empty():
		return Result.failure("expected player 1 initial place_restaurant trace, got %s" % str(controller.last_trace))
	var params: Dictionary = Dictionary(opening_trace.get("params", {}))
	var pos := _read_position_array(params.get("position", []))
	if pos == [4, 3]:
		return Result.failure("expected player 1 to avoid known opponent-dominated opening [4, 3], trace=%s" % str(opening_trace))
	var explanation: Dictionary = Dictionary(opening_trace.get("explanation", {}))
	var features: Dictionary = Dictionary(explanation.get("features", {}))
	var dominated_houses := int(features.get("restaurant_competitor_dominated_houses", 0))
	var servable_houses := int(features.get("restaurant_competitive_houses", 0)) + int(features.get("restaurant_contested_houses", 0))
	if int(features.get("restaurant_closest_competitor_distance", -1)) < 0:
		return Result.failure("second opening trace should expose competitor distance features: trace=%s" % str(opening_trace))
	if servable_houses <= 0:
		return Result.failure("expected player 1 opening to keep at least one serviceable route, pos=%s features=%s trace=%s" % [str(pos), str(features), str(opening_trace)])
	if dominated_houses > servable_houses:
		return Result.failure("expected player 1 opening to avoid more dominated than servable houses: pos=%s features=%s trace=%s" % [str(pos), str(features), str(opening_trace)])
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

static func _scenario_early_income_route_trains_markets_structures_produces_and_sells(seed_val: int) -> Result:
	var engine_read := _build_early_income_full_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()

	var train_controller := BotControllerClass.new()
	var train_step := train_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not train_step.ok:
		return Result.failure("early route training step failed: %s" % train_step.error)
	var train_trace: Dictionary = train_step.value
	if str(train_trace.get("action_id", "")) != "train":
		return Result.failure("expected early route to train food supply before marketing, got %s" % str(train_trace))
	var train_params: Dictionary = Dictionary(train_trace.get("params", {}))
	if str(train_params.get("from_employee", "")) != "kitchen_trainee" or str(train_params.get("to_employee", "")) != "burger_cook":
		return Result.failure("expected early route training kitchen_trainee -> burger_cook, got %s" % str(train_trace))
	var state := engine.get_state()
	var reserve: Array = Array(Dictionary(state.players[0]).get("reserve_employees", []))
	if not reserve.has("burger_cook"):
		return Result.failure("early route should leave trained burger_cook in reserve, reserve=%s" % str(reserve))

	var prepare_marketing := _prepare_current_round_marketing(engine)
	if not prepare_marketing.ok:
		return prepare_marketing
	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("early route marketing step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected early route to market burger after training, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	if str(marketing_params.get("product", "")) != "burger":
		return Result.failure("expected early route marketing product burger, got %s" % str(marketing_trace))
	var marketing_features: Dictionary = Dictionary(Dictionary(marketing_trace.get("explanation", {})).get("features", {}))
	if not Array(marketing_features.get("milestone_race_ids", [])).has("first_burger_marketed"):
		return Result.failure("early route should value first_burger_marketed race, features=%s trace=%s" % [str(marketing_features), str(marketing_trace)])
	if not Array(marketing_features.get("marketing_preview_milestone_ids", [])).has("first_burger_marketed"):
		return Result.failure("early route should preview first_burger_marketed from real Marketing settlement, features=%s trace=%s" % [str(marketing_features), str(marketing_trace)])
	state = engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if milestones.has("first_burger_marketed"):
		return Result.failure("first_burger_marketed should wait for DemandMarked at Marketing settlement, milestones=%s trace=%s" % [str(milestones), str(marketing_trace)])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("early route marketing action should not create same-round burger demand")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	if _state_product_demand_count(state, "burger") != 1:
		return Result.failure("early route Marketing settlement should create one burger demand for next round")
	milestones = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_burger_marketed"):
		return Result.failure("Marketing settlement should claim first_burger_marketed, milestones=%s" % str(milestones))

	var prepare_next_round := _prepare_next_round_restructuring(engine)
	if not prepare_next_round.ok:
		return prepare_next_round
	var structure_controller := BotControllerClass.new()
	var structure_step := structure_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not structure_step.ok:
		return Result.failure("early route next-round restructuring step failed: %s" % structure_step.error)
	var structure_trace: Dictionary = structure_step.value
	if str(structure_trace.get("action_id", "")) != "set_company_structure_direct":
		return Result.failure("expected early route to activate trained burger_cook, got %s" % str(structure_trace))
	var structure_params: Dictionary = Dictionary(structure_trace.get("params", {}))
	if str(structure_params.get("employee_id", "")) != "burger_cook":
		return Result.failure("expected early route structure employee burger_cook, got %s" % str(structure_trace))

	var prepare_get_food := _prepare_next_round_get_food(engine)
	if not prepare_get_food.ok:
		return prepare_get_food
	var produce_controller := BotControllerClass.new()
	var produce_step := produce_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("early route production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected early route to produce burger for settled demand, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("food_type", "")) != "burger":
		return Result.failure("expected early route production food burger, got %s" % str(produce_trace))

	state = engine.get_state()
	var cash_before_dinner := int(state.players[0].get("cash", 0))
	var burger_breakdown_read := _route_house_sale_breakdown(state, 0, {"burger": 1})
	if not burger_breakdown_read.ok:
		return burger_breakdown_read
	var burger_breakdown: Dictionary = burger_breakdown_read.value
	if int(burger_breakdown.get("bonus", 0)) != 5:
		return Result.failure("early route first_burger_marketed bonus should be 5, breakdown=%s" % str(burger_breakdown))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	var cash_delta := int(state.players[0].get("cash", 0)) - cash_before_dinner
	if cash_delta != int(burger_breakdown.get("revenue", 0)):
		return Result.failure("early route should sell produced burger with first_burger_marketed bonus, cash_delta=%d breakdown=%s" % [cash_delta, str(burger_breakdown)])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("early route Dinnertime should clear marketed burger demand")
	return Result.success()

static func _scenario_blocked_billboard_route_trains_campaign_manager_markets_and_sells(seed_val: int) -> Result:
	var engine_read := _build_blocked_billboard_training_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()

	var train_controller := BotControllerClass.new()
	var train_step := train_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not train_step.ok:
		return Result.failure("blocked billboard route training step failed: %s" % train_step.error)
	var train_trace: Dictionary = train_step.value
	if str(train_trace.get("action_id", "")) != "train":
		return Result.failure("expected blocked billboard route to train campaign_manager, got %s" % str(train_trace))
	var train_params: Dictionary = Dictionary(train_trace.get("params", {}))
	if str(train_params.get("from_employee", "")) != "marketing_trainee" or str(train_params.get("to_employee", "")) != "campaign_manager":
		return Result.failure("expected marketing_trainee -> campaign_manager training route, got %s" % str(train_trace))

	var prepare_marketing_round := _prepare_next_round_restructuring(engine)
	if not prepare_marketing_round.ok:
		return prepare_marketing_round
	var seed_structure := _seed_current_structure(engine, ["trainer", "burger_cook"])
	if not seed_structure.ok:
		return seed_structure
	var structure_read := _run_restructuring_until_direct_staff_active(engine, bot, ["campaign_manager"], 3)
	if not structure_read.ok:
		return structure_read

	var prepare_marketing := _prepare_current_round_marketing(engine)
	if not prepare_marketing.ok:
		return prepare_marketing
	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("blocked billboard route marketing step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected blocked billboard route to initiate campaign_manager marketing, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	if str(marketing_params.get("employee_type", "")) != "campaign_manager":
		return Result.failure("expected blocked billboard route to use campaign_manager, got %s" % str(marketing_trace))
	var board_number := int(marketing_params.get("board_number", 0))
	if board_number < 7 or board_number > 10:
		return Result.failure("expected campaign_manager to use mailbox when billboards are occupied, got %s" % str(marketing_trace))
	if str(marketing_params.get("product", "")) != "burger":
		return Result.failure("expected campaign_manager mailbox route to market burger for active supply, got %s" % str(marketing_trace))
	var state := engine.get_state()
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("campaign_manager marketing action should not create same-round burger demand before Marketing settlement")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	if _state_product_demand_count(state, "burger") <= 0:
		return Result.failure("campaign_manager mailbox route should create burger demand at Marketing settlement")

	var prepare_get_food := _prepare_next_round_get_food(engine)
	if not prepare_get_food.ok:
		return prepare_get_food
	var produce_controller := BotControllerClass.new()
	var produce_step := produce_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("blocked billboard route production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected blocked billboard route to produce burger for settled demand, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("food_type", "")) != "burger":
		return Result.failure("expected blocked billboard route production food burger, got %s" % str(produce_trace))

	state = engine.get_state()
	var cash_before_dinner := int(state.players[0].get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(state.players[0].get("cash", 0)) <= cash_before_dinner:
		return Result.failure("blocked billboard route should sell produced burger at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(state.players[0].get("cash", 0))])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("blocked billboard route Dinnertime should clear marketed burger demand")
	return Result.success()

static func _scenario_marketing_generation_preserves_mailbox_candidates_under_cap(seed_val: int) -> Result:
	var engine_read := _build_marketing_next_round_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var context_read := AiDecisionContext.from_observation(observation, 777, [])
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value
	var legal_ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not legal_ids_read.ok:
		return legal_ids_read
	var legal_action_ids: Array[String] = legal_ids_read.value
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	var gen_read := CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_fn, {
		"source_state": engine.get_state(),
		"max_valid_per_action": 12,
	})
	if not gen_read.ok:
		return gen_read
	var payload: Dictionary = Dictionary(gen_read.value)
	var candidates: Array = Array(payload.get("candidates", []))
	var marketing_count := 0
	var has_billboard := false
	var has_mailbox := false
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			continue
		var command: Command = macro.commands[0]
		if str(command.action_id) != "initiate_marketing":
			continue
		marketing_count += 1
		var board_number := int(command.params.get("board_number", 0))
		if board_number >= 11 and board_number <= 16:
			has_billboard = true
		if board_number >= 7 and board_number <= 10:
			has_mailbox = true
	if marketing_count > 12:
		return Result.failure("marketing candidate generation should respect cap=12, got %d" % marketing_count)
	if not has_billboard:
		return Result.failure("marketing candidate generation should still include billboard candidates")
	if not has_mailbox:
		return Result.failure("marketing candidate generation should preserve mailbox candidates under cap; candidates=%s discarded=%s" % [str(_marketing_candidate_ids(candidates)), str(payload.get("discarded_reasons", []))])
	return Result.success()

static func _scenario_marketing_generation_discards_competitor_captured_candidates(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.players[0]["employees"] = ["campaign_manager", "burger_cook"]
	state.players[1]["employees"] = ["burger_cook"]
	state.players[0]["inventory"] = {"burger": 1}
	state.players[1]["inventory"] = {"burger": 1}
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var context_read := AiDecisionContext.from_observation(observation, seed_val, [])
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	var generated := CandidateGeneratorClass.generate(
		observation,
		context,
		["initiate_marketing"],
		validate_fn,
		{"max_valid_per_action": 500, "source_state": state}
	)
	if not generated.ok:
		return generated
	var payload: Dictionary = Dictionary(generated.value)
	var candidates_val = payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.failure("CandidateGenerator should return candidates Array")
	var saw_own_side := false
	for candidate_val in Array(candidates_val):
		if not (candidate_val is MacroAction):
			continue
		var candidate: MacroAction = candidate_val
		var affected := _sorted_unique_strings(candidate.debug.get("affected_house_ids", []))
		if affected.has("house_left"):
			saw_own_side = true
		var service_features: Dictionary = Dictionary(candidate.debug.get("marketing_service_features", {}))
		var serviceable := int(service_features.get("serviceable_houses", 0))
		var competitive := int(service_features.get("competitive_houses", serviceable))
		var lost_to_competitor := int(service_features.get("lost_to_competitor_houses", 0))
		if competitive <= 0 and lost_to_competitor > 0:
			return Result.failure("CandidateGenerator should discard marketing that only creates competitor-captured demand: %s" % str(candidate.to_debug_dict()))
	if not saw_own_side:
		return Result.failure("CandidateGenerator should keep at least one own-side marketing candidate")
	var discarded := _sorted_unique_strings(payload.get("discarded_reasons", []))
	var saw_competition_discard := false
	for reason in discarded:
		if reason.find("captured by competitor") >= 0:
			saw_competition_discard = true
			break
	if not saw_competition_discard:
		return Result.failure("CandidateGenerator should report discarded competitor-captured marketing candidates")
	return Result.success()

static func _scenario_recovery_customer_switch_values_alternate_house(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "burger"}])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.players[0]["employees"] = ["campaign_manager", "burger_cook"]
	state.players[1]["employees"] = ["burger_cook"]
	state.players[0]["inventory"] = {"burger": 1}
	state.players[1]["inventory"] = {"burger": 2}
	_reset_round_state_for_ai_step(state)
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var alternate_house_macro := MacroAction.create(
		"recovery_customer_switch_alternate_house",
		[Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager", "marketing_type": "billboard", "board_number": 11, "product": "burger", "position": [0, 2]})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_left"]}
	)
	var captured_house_macro := MacroAction.create(
		"recovery_customer_switch_captured_house",
		[Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager", "marketing_type": "billboard", "board_number": 12, "product": "burger", "position": [8, 2]})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_right"]}
	)
	var skip_macro := MacroAction.create(
		"skip_customer_switch_recovery",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var score_options := {"source_state": state}
	var alternate_score: Dictionary = StrategyScorerClass.score_macro(observation, alternate_house_macro, profile, score_options)
	var captured_score: Dictionary = StrategyScorerClass.score_macro(observation, captured_house_macro, profile, score_options)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile, score_options)
	var features: Dictionary = Dictionary(alternate_score.get("features", {}))
	if int(features.get("marketing_self_capture_houses", 0)) <= 0:
		return Result.failure("alternate house marketing should expose self-captured house: %s" % str(features))
	if int(features.get("marketing_recovery_lost_to_competitor_demand", 0)) <= 0:
		return Result.failure("alternate house recovery should see lost competitor demand elsewhere: %s" % str(features))
	if not Array(features.get("marketing_recovery_modes", [])).has("customer_switch"):
		return Result.failure("alternate house recovery should expose customer_switch mode: %s" % str(features))
	if float(features.get("marketing_recovery_value", 0.0)) <= 0.0:
		return Result.failure("alternate house recovery should have positive recovery value: %s" % str(features))
	if float(alternate_score.get("score", 0.0)) <= float(captured_score.get("score", 0.0)):
		return Result.failure("customer switch should prefer alternate own-serviceable house over captured house: alternate=%s captured=%s" % [str(alternate_score), str(captured_score)])
	if float(alternate_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("customer switch should beat skip when an alternate house is serviceable: alternate=%s skip=%s" % [str(alternate_score), str(skip_score)])
	return Result.success()

static func _scenario_recovery_price_action_recovers_lost_demand(seed_val: int) -> Result:
	var engine_read := _build_income_route_contested_price_action_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("price recovery action step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "set_price":
		return Result.failure("expected price recovery to execute set_price, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if int(features.get("income_total_price_recoverable_demand", 0)) <= 0:
		return Result.failure("price recovery should expose income_total_price_recoverable_demand: %s" % str(features))
	if not bool(features.get("price_recovery_needed", false)):
		return Result.failure("price recovery should mark recovery_needed: %s" % str(features))
	if not Array(features.get("price_recovery_modes", [])).has("price_recovery"):
		return Result.failure("price recovery should expose price_recovery mode: %s" % str(features))
	if float(features.get("price_recovery_value", 0.0)) <= 0.0:
		return Result.failure("price recovery should add positive recovery value: %s" % str(features))
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after price recovery action")
	var cash_before := int(Dictionary(state.players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("cash", 0)) <= cash_before:
		return Result.failure("price recovery action should convert recovered demand into sale, before=%d after=%d" % [cash_before, int(Dictionary(state.players[0]).get("cash", 0))])
	return Result.success()

static func _scenario_recovery_product_switch_marketing_targets_opponent_capacity_gap(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "burger"}])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.players[0]["employees"] = ["campaign_manager"]
	state.players[1]["employees"] = ["burger_cook"]
	state.players[0]["inventory"] = {}
	state.players[1]["inventory"] = {}
	_reset_round_state_for_ai_step(state)
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var disruptive_macro := MacroAction.create(
		"recovery_product_switch_marketing_pizza",
		[Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager", "marketing_type": "billboard", "board_number": 11, "product": "pizza", "position": [8, 2]})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_right"]}
	)
	var skip_macro := MacroAction.create(
		"skip_product_switch_recovery",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var score_options := {"source_state": state}
	var disruptive_score: Dictionary = StrategyScorerClass.score_macro(observation, disruptive_macro, profile, score_options)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile, score_options)
	var features: Dictionary = Dictionary(disruptive_score.get("features", {}))
	if int(features.get("marketing_opponent_capacity_gap_houses", 0)) != 1:
		return Result.failure("product switch should expose one opponent capacity gap house: %s" % str(features))
	if int(features.get("marketing_opponent_capacity_gap_prevented_sales", 0)) != 1:
		return Result.failure("product switch should expose one prevented opponent sale: %s" % str(features))
	if not Array(features.get("marketing_opponent_capacity_gap_products", [])).has("pizza"):
		return Result.failure("product switch should expose pizza as gap product: %s" % str(features))
	if str(features.get("marketing_pressure_mode", "")) != "opponent_pressure":
		return Result.failure("product switch should be opponent_pressure marketing: %s" % str(features))
	if not Array(features.get("marketing_recovery_modes", [])).has("product_switch"):
		return Result.failure("product switch should expose product_switch recovery mode: %s" % str(features))
	if float(features.get("marketing_recovery_value", 0.0)) <= 0.0:
		return Result.failure("product switch should add positive recovery value: %s" % str(features))
	if float(disruptive_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("product switch opponent-gap marketing should beat skip: disruptive=%s skip=%s" % [str(disruptive_score), str(skip_score)])
	return Result.success()

static func _scenario_billboard_marketing_claims_first_billboard_and_sells(seed_val: int) -> Result:
	var engine_read := _build_billboard_marketing_milestone_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var state := engine.get_state()
	var paid_before := EmployeeRulesClass.count_paid_employees(Dictionary(state.players[0]))
	if paid_before != 2:
		return Result.failure("billboard route setup should have two paid employees before first_billboard, got %d" % paid_before)

	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("billboard marketing route step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected StrategyBot to initiate billboard marketing, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	var board_number := int(marketing_params.get("board_number", 0))
	if board_number < 11 or board_number > 16:
		return Result.failure("expected first_billboard route to use a billboard board, got %s" % str(marketing_trace))
	if str(marketing_params.get("employee_type", "")) != "campaign_manager":
		return Result.failure("expected first_billboard route to use campaign_manager, got %s" % str(marketing_trace))
	if str(marketing_params.get("product", "")) != "burger":
		return Result.failure("expected first_billboard route to market burger, got %s" % str(marketing_trace))
	var features: Dictionary = Dictionary(Dictionary(marketing_trace.get("explanation", {})).get("features", {}))
	if int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return Result.failure("billboard marketing route should expose own-serviceable affected houses, features=%s trace=%s" % [str(features), str(marketing_trace)])
	if not Array(features.get("milestone_race_ids", [])).has("first_billboard"):
		return Result.failure("billboard marketing route should value first_billboard, features=%s trace=%s" % [str(features), str(marketing_trace)])

	state = engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_billboard"):
		return Result.failure("billboard marketing action should claim first_billboard immediately, milestones=%s trace=%s" % [str(milestones), str(marketing_trace)])
	var paid_after := EmployeeRulesClass.count_paid_employees(Dictionary(state.players[0]))
	if paid_after != 1:
		return Result.failure("first_billboard should make marketing employees salary-free, paid before=%d after=%d player=%s" % [paid_before, paid_after, str(state.players[0])])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("billboard marketing action should not create same-round burger demand before Marketing settlement")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	var demand_count := _state_product_demand_count(state, "burger")
	if demand_count != 1:
		return Result.failure("first_billboard route should create one burger demand at Marketing settlement, got %d" % demand_count)

	var prepare_get_food := _prepare_next_round_get_food(engine)
	if not prepare_get_food.ok:
		return prepare_get_food
	var produce_controller := BotControllerClass.new()
	var produce_step := produce_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("billboard route production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected billboard route to produce burger for settled demand, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("food_type", "")) != "burger":
		return Result.failure("expected billboard route production food burger, got %s" % str(produce_trace))

	state = engine.get_state()
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("cash", 0)) <= cash_before_dinner:
		return Result.failure("billboard route should sell produced burger at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(Dictionary(state.players[0]).get("cash", 0))])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("billboard route Dinnertime should clear marketed burger demand")
	var permanent_marketing := _assert_first_billboard_followup_marketing_is_permanent(engine, seed_val)
	if not permanent_marketing.ok:
		return permanent_marketing
	return Result.success()

static func _assert_first_billboard_followup_marketing_is_permanent(engine: GameEngine, seed_val: int) -> Result:
	var state := engine.get_state()
	if state == null:
		return Result.failure("first_billboard permanent check state is null")
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var take_trainee := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("first_billboard permanent check take marketing_trainee failed: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", false)
	if not add_trainee.ok:
		return Result.failure("first_billboard permanent check add marketing_trainee failed: %s" % add_trainee.error)

	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var context_read := AiDecisionContext.from_observation(observation, seed_val + 101, [])
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value
	var legal_ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not legal_ids_read.ok:
		return legal_ids_read
	var legal_action_ids: Array[String] = legal_ids_read.value
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	var gen_read := CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_fn, {
		"source_state": state,
		"max_valid_per_action": 80,
	})
	if not gen_read.ok:
		return gen_read
	var payload: Dictionary = Dictionary(gen_read.value)
	var followup_command: Command = null
	for macro_val in Array(payload.get("candidates", [])):
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			continue
		var command: Command = macro.commands[0]
		if str(command.action_id) != "initiate_marketing":
			continue
		if str(command.params.get("employee_type", "")) != "marketing_trainee":
			continue
		var params: Dictionary = command.params.duplicate(true)
		params["product"] = "pizza"
		followup_command = Command.create("initiate_marketing", 0, params)
		break
	if followup_command == null:
		return Result.failure("first_billboard permanent check should find a follow-up marketing_trainee candidate, payload=%s" % str(payload))

	var exec := engine.execute_command(followup_command)
	if not exec.ok:
		return Result.failure("first_billboard permanent check follow-up marketing failed: %s command=%s" % [exec.error, str(followup_command.to_dict())])
	state = engine.get_state()
	if state == null:
		return Result.failure("first_billboard permanent check state is null after follow-up marketing")
	var followup_board_number := int(followup_command.params.get("board_number", 0))
	var found_instance := false
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			return Result.failure("first_billboard permanent check marketing_instances element should be Dictionary")
		var inst: Dictionary = inst_val
		if int(inst.get("board_number", 0)) != followup_board_number:
			continue
		found_instance = true
		if int(inst.get("remaining_duration", 0)) != -1:
			return Result.failure("first_billboard follow-up marketing should be permanent, instance=%s" % str(inst))
	if not found_instance:
		return Result.failure("first_billboard permanent check missing follow-up board #%d in marketing_instances" % followup_board_number)
	var placements_val = state.map.get("marketing_placements", {})
	if not (placements_val is Dictionary):
		return Result.failure("first_billboard permanent check marketing_placements should be Dictionary")
	var placements: Dictionary = placements_val
	var placement_key := str(followup_board_number)
	if not placements.has(placement_key) or not (placements[placement_key] is Dictionary):
		return Result.failure("first_billboard permanent check missing placement #%d" % followup_board_number)
	var placement: Dictionary = placements[placement_key]
	if int(placement.get("remaining_duration", 0)) != -1:
		return Result.failure("first_billboard follow-up placement should be permanent, placement=%s" % str(placement))
	return Result.success()

static func _scenario_radio_marketing_claims_first_radio_and_sells(seed_val: int) -> Result:
	var engine_read := _build_radio_marketing_milestone_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()

	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("radio marketing route step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected StrategyBot to initiate radio marketing, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	var board_number := int(marketing_params.get("board_number", 0))
	if board_number < 1 or board_number > 3:
		return Result.failure("expected first_radio route to use a radio board, got %s" % str(marketing_trace))
	if str(marketing_params.get("employee_type", "")) != "brand_director":
		return Result.failure("expected first_radio route to use brand_director, got %s" % str(marketing_trace))
	if str(marketing_params.get("product", "")) != "burger":
		return Result.failure("expected first_radio route to market burger, got %s" % str(marketing_trace))
	var features: Dictionary = Dictionary(Dictionary(marketing_trace.get("explanation", {})).get("features", {}))
	if int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return Result.failure("radio marketing route should expose own-serviceable affected houses, features=%s trace=%s" % [str(features), str(marketing_trace)])
	if not Array(features.get("milestone_race_ids", [])).has("first_radio"):
		return Result.failure("radio marketing route should value first_radio, features=%s trace=%s" % [str(features), str(marketing_trace)])

	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_radio"):
		return Result.failure("radio marketing action should claim first_radio immediately, milestones=%s trace=%s" % [str(milestones), str(marketing_trace)])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("radio marketing action should not create same-round burger demand before Marketing settlement")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	var demand_count := _state_product_demand_count(state, "burger")
	if demand_count != 2:
		return Result.failure("first_radio extra_marketing should create 2 burger demands at Marketing settlement, got %d" % demand_count)

	var prepare_get_food := _prepare_next_round_get_food(engine)
	if not prepare_get_food.ok:
		return prepare_get_food
	var produce_controller := BotControllerClass.new()
	var produce_step := produce_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("radio route production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected radio route to produce burger for settled demand, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("food_type", "")) != "burger":
		return Result.failure("expected radio route production food burger, got %s" % str(produce_trace))

	state = engine.get_state()
	var cash_before_dinner := int(state.players[0].get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(state.players[0].get("cash", 0)) <= cash_before_dinner:
		return Result.failure("radio route should sell produced burger at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(state.players[0].get("cash", 0))])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("radio route Dinnertime should clear marketed burger demand")
	return Result.success()

static func _scenario_airplane_marketing_claims_first_airplane_and_sells(seed_val: int) -> Result:
	var engine_read := _build_airplane_marketing_milestone_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()

	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("airplane marketing route step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected StrategyBot to initiate airplane marketing, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	var board_number := int(marketing_params.get("board_number", 0))
	if board_number < 4 or board_number > 6:
		return Result.failure("expected first_airplane route to use an airplane board, got %s" % str(marketing_trace))
	if str(marketing_params.get("employee_type", "")) != "brand_manager":
		return Result.failure("expected first_airplane route to use brand_manager, got %s" % str(marketing_trace))
	if str(marketing_params.get("product", "")) != "burger":
		return Result.failure("expected first_airplane route to market burger, got %s" % str(marketing_trace))
	var pos_val = marketing_params.get("position", [])
	var pos := Vector2i(-1, -1)
	if pos_val is Vector2i:
		pos = pos_val
	elif pos_val is Array and Array(pos_val).size() >= 2:
		pos = Vector2i(int(Array(pos_val)[0]), int(Array(pos_val)[1]))
	var axis := str(marketing_params.get("axis", "")).strip_edges()
	if axis == "row" and pos.x != 0 and pos.x != 7:
		return Result.failure("airplane row candidate should attach to left/right edge, params=%s trace=%s" % [str(marketing_params), str(marketing_trace)])
	if axis == "col" and pos.y != 0 and pos.y != 5:
		return Result.failure("airplane col candidate should attach to top/bottom edge, params=%s trace=%s" % [str(marketing_params), str(marketing_trace)])
	var features: Dictionary = Dictionary(Dictionary(marketing_trace.get("explanation", {})).get("features", {}))
	if int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return Result.failure("airplane marketing route should expose own-serviceable affected houses, features=%s trace=%s" % [str(features), str(marketing_trace)])
	if not Array(features.get("milestone_race_ids", [])).has("first_airplane"):
		return Result.failure("airplane marketing route should value first_airplane, features=%s trace=%s" % [str(features), str(marketing_trace)])

	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_airplane"):
		return Result.failure("airplane marketing action should claim first_airplane immediately, milestones=%s trace=%s" % [str(milestones), str(marketing_trace)])
	var airplane_player: Dictionary = Dictionary(state.players[0]).duplicate(true)
	var no_airplane_player: Dictionary = airplane_player.duplicate(true)
	var no_airplane_milestones: Array = Array(no_airplane_player.get("milestones", [])).duplicate()
	no_airplane_milestones.erase("first_airplane")
	no_airplane_player["milestones"] = no_airplane_milestones
	var slots_with_airplane := WorkingFlowClass.compute_order_of_business_empty_slots(state, airplane_player)
	if not slots_with_airplane.ok:
		return slots_with_airplane
	var slots_without_airplane := WorkingFlowClass.compute_order_of_business_empty_slots(state, no_airplane_player)
	if not slots_without_airplane.ok:
		return slots_without_airplane
	if int(slots_with_airplane.value) != int(slots_without_airplane.value) + 2:
		return Result.failure("first_airplane should add 2 OrderOfBusiness empty slots, without=%d with=%d milestones=%s" % [int(slots_without_airplane.value), int(slots_with_airplane.value), str(milestones)])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("airplane marketing action should not create same-round burger demand before Marketing settlement")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	var demand_count := _state_product_demand_count(state, "burger")
	if demand_count != 1:
		return Result.failure("airplane marketing should create one burger demand at Marketing settlement, got %d" % demand_count)

	var prepare_get_food := _prepare_next_round_get_food(engine)
	if not prepare_get_food.ok:
		return prepare_get_food
	var produce_controller := BotControllerClass.new()
	var produce_step := produce_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("airplane route production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected airplane route to produce burger for settled demand, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("food_type", "")) != "burger":
		return Result.failure("expected airplane route production food burger, got %s" % str(produce_trace))

	state = engine.get_state()
	var cash_before_dinner := int(state.players[0].get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(state.players[0].get("cash", 0)) <= cash_before_dinner:
		return Result.failure("airplane route should sell produced burger at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(state.players[0].get("cash", 0))])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("airplane route Dinnertime should clear marketed burger demand")
	return Result.success()

static func _scenario_drink_marketing_claims_first_drink_marketed_and_sells(seed_val: int) -> Result:
	var engine_read := _build_drink_marketing_milestone_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()

	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("drink marketing route step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected StrategyBot to initiate drink marketing, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	if str(marketing_params.get("employee_type", "")) != "campaign_manager":
		return Result.failure("expected drink marketing route to use campaign_manager, got %s" % str(marketing_trace))
	if str(marketing_params.get("product", "")) != "soda":
		return Result.failure("expected drink marketing route to market soda, got %s" % str(marketing_trace))
	var features: Dictionary = Dictionary(Dictionary(marketing_trace.get("explanation", {})).get("features", {}))
	if int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return Result.failure("drink marketing route should expose own-serviceable affected houses, features=%s trace=%s" % [str(features), str(marketing_trace)])
	if not Array(features.get("milestone_race_ids", [])).has("first_drink_marketed"):
		return Result.failure("drink marketing route should value first_drink_marketed race, features=%s trace=%s" % [str(features), str(marketing_trace)])
	if not Array(features.get("marketing_preview_milestone_ids", [])).has("first_drink_marketed"):
		return Result.failure("drink marketing route should preview first_drink_marketed from real Marketing settlement, features=%s trace=%s" % [str(features), str(marketing_trace)])

	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if milestones.has("first_drink_marketed"):
		return Result.failure("first_drink_marketed should wait for DemandMarked at Marketing settlement, milestones=%s trace=%s" % [str(milestones), str(marketing_trace)])
	if _state_product_demand_count(state, "soda") != 1:
		return Result.failure("drink marketing action should not create same-round soda demand before Marketing settlement")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	if _state_product_demand_count(state, "soda") != 2:
		return Result.failure("drink marketing should add one soda demand at Marketing settlement")
	milestones = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_drink_marketed"):
		return Result.failure("Marketing settlement should claim first_drink_marketed, milestones=%s" % str(milestones))

	var prepare_get_drinks := _prepare_current_round_get_drinks(engine)
	if not prepare_get_drinks.ok:
		return prepare_get_drinks
	var drink_controller := BotControllerClass.new()
	var drink_step := drink_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not drink_step.ok:
		return Result.failure("drink marketing route procurement step failed: %s" % drink_step.error)
	var drink_trace: Dictionary = drink_step.value
	if str(drink_trace.get("action_id", "")) != "procure_drinks":
		return Result.failure("expected drink marketing route to procure soda, got %s" % str(drink_trace))
	var drink_params: Dictionary = Dictionary(drink_trace.get("params", {}))
	if str(drink_params.get("employee_type", "")) != "truck_driver":
		return Result.failure("expected drink marketing route to use truck_driver, got %s" % str(drink_trace))
	if not Array(drink_params.get("selected_sources", [])).has([7, 2]):
		return Result.failure("expected drink marketing route to select soda source [7, 2], got %s" % str(drink_trace))

	state = engine.get_state()
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var drink_breakdown_read := _route_house_sale_breakdown(state, 0, {"soda": 2})
	if not drink_breakdown_read.ok:
		return drink_breakdown_read
	var drink_breakdown: Dictionary = drink_breakdown_read.value
	if int(drink_breakdown.get("bonus", 0)) != 10:
		return Result.failure("drink route first_drink_marketed bonus should be 10 for two soda, breakdown=%s" % str(drink_breakdown))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	var cash_delta := int(Dictionary(state.players[0]).get("cash", 0)) - cash_before_dinner
	if cash_delta != int(drink_breakdown.get("revenue", 0)):
		return Result.failure("drink marketing route should sell soda with first_drink_marketed bonus, cash_delta=%d breakdown=%s" % [cash_delta, str(drink_breakdown)])
	if _state_product_demand_count(state, "soda") != 0:
		return Result.failure("drink marketing route Dinnertime should clear soda demand")
	return Result.success()

static func _scenario_pizza_marketing_claims_first_pizza_marketed_and_sells(seed_val: int) -> Result:
	var engine_read := _build_pizza_marketing_milestone_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()

	var marketing_controller := BotControllerClass.new()
	var marketing_step := marketing_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not marketing_step.ok:
		return Result.failure("pizza marketing route step failed: %s" % marketing_step.error)
	var marketing_trace: Dictionary = marketing_step.value
	if str(marketing_trace.get("action_id", "")) != "initiate_marketing":
		return Result.failure("expected StrategyBot to initiate pizza marketing, got %s" % str(marketing_trace))
	var marketing_params: Dictionary = Dictionary(marketing_trace.get("params", {}))
	if str(marketing_params.get("employee_type", "")) != "campaign_manager":
		return Result.failure("expected pizza marketing route to use campaign_manager, got %s" % str(marketing_trace))
	if str(marketing_params.get("product", "")) != "pizza":
		return Result.failure("expected pizza marketing route to market pizza, got %s" % str(marketing_trace))
	var features: Dictionary = Dictionary(Dictionary(marketing_trace.get("explanation", {})).get("features", {}))
	if int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return Result.failure("pizza marketing route should expose own-serviceable affected houses, features=%s trace=%s" % [str(features), str(marketing_trace)])
	if not Array(features.get("milestone_race_ids", [])).has("first_pizza_marketed"):
		return Result.failure("pizza marketing route should value first_pizza_marketed race, features=%s trace=%s" % [str(features), str(marketing_trace)])
	if not Array(features.get("marketing_preview_milestone_ids", [])).has("first_pizza_marketed"):
		return Result.failure("pizza marketing route should preview first_pizza_marketed from real Marketing settlement, features=%s trace=%s" % [str(features), str(marketing_trace)])

	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if milestones.has("first_pizza_marketed"):
		return Result.failure("first_pizza_marketed should wait for DemandMarked at Marketing settlement, milestones=%s trace=%s" % [str(milestones), str(marketing_trace)])
	if _state_product_demand_count(state, "pizza") != 0:
		return Result.failure("pizza marketing action should not create same-round pizza demand before Marketing settlement")

	var settled := _advance_direct_payday_to_marketing(engine)
	if not settled.ok:
		return settled
	state = engine.get_state()
	if _state_product_demand_count(state, "pizza") != 1:
		return Result.failure("pizza marketing should add one pizza demand at Marketing settlement")
	milestones = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_pizza_marketed"):
		return Result.failure("Marketing settlement should claim first_pizza_marketed, milestones=%s" % str(milestones))

	var prepare_next_round := _prepare_next_round_restructuring(engine)
	if not prepare_next_round.ok:
		return prepare_next_round
	var structure_controller := BotControllerClass.new()
	var structure_step := structure_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not structure_step.ok:
		return Result.failure("pizza marketing route restructuring step failed: %s" % structure_step.error)
	var structure_trace: Dictionary = structure_step.value
	if str(structure_trace.get("action_id", "")) != "set_company_structure_direct":
		return Result.failure("expected pizza marketing route to activate pizza_cook, got %s" % str(structure_trace))
	var structure_params: Dictionary = Dictionary(structure_trace.get("params", {}))
	if str(structure_params.get("employee_id", "")) != "pizza_cook":
		return Result.failure("expected pizza marketing route structure employee pizza_cook, got %s" % str(structure_trace))

	var prepare_get_food := _prepare_next_round_get_food(engine)
	if not prepare_get_food.ok:
		return prepare_get_food
	var produce_controller := BotControllerClass.new()
	var produce_step := produce_controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("pizza marketing route production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected pizza marketing route to produce pizza, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("employee_type", "")) != "pizza_cook" or str(produce_params.get("food_type", "")) != "pizza":
		return Result.failure("expected pizza_cook to produce pizza, got %s" % str(produce_trace))

	state = engine.get_state()
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var pizza_breakdown_read := _route_house_sale_breakdown(state, 0, {"pizza": 1})
	if not pizza_breakdown_read.ok:
		return pizza_breakdown_read
	var pizza_breakdown: Dictionary = pizza_breakdown_read.value
	if int(pizza_breakdown.get("bonus", 0)) != 5:
		return Result.failure("pizza route first_pizza_marketed bonus should be 5, breakdown=%s" % str(pizza_breakdown))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	var cash_delta := int(Dictionary(state.players[0]).get("cash", 0)) - cash_before_dinner
	if cash_delta != int(pizza_breakdown.get("revenue", 0)):
		return Result.failure("pizza marketing route should sell pizza with first_pizza_marketed bonus, cash_delta=%d breakdown=%s" % [cash_delta, str(pizza_breakdown)])
	if _state_product_demand_count(state, "pizza") != 0:
		return Result.failure("pizza marketing route Dinnertime should clear pizza demand")
	return Result.success()

static func _route_house_sale_breakdown(state: GameState, player_id: int, required: Dictionary) -> Result:
	if state == null:
		return Result.failure("route house sale breakdown state is null")
	if not (state.map is Dictionary):
		return Result.failure("route house sale breakdown state.map should be Dictionary")
	var houses_val = state.map.get("houses", {})
	if not (houses_val is Dictionary):
		return Result.failure("route house sale breakdown map.houses should be Dictionary")
	var houses: Dictionary = houses_val
	if not houses.has("house_route") or not (houses["house_route"] is Dictionary):
		return Result.failure("route house sale breakdown missing house_route")
	var house: Dictionary = Dictionary(houses["house_route"])
	return PricingPipelineClass.calculate_sale_breakdown(state, player_id, house, required)

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

static func _build_billboard_marketing_milestone_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
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
		return Result.failure("seed billboard route cash failed: %s" % seed_cash.error)
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for active_employee_id in ["campaign_manager", "burger_cook"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "campaign_manager", "reports": []},
			{"employee_id": "burger_cook", "reports": []},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.milestone_pool = ["first_billboard"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_pizza_marketing_milestone_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
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
		return Result.failure("seed pizza marketing route cash failed: %s" % seed_cash.error)
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for employee_id in ["campaign_manager", "pizza_cook"]:
		var take := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take.ok:
			return Result.failure("take %s failed: %s" % [employee_id, take.error])
		var add := StateUpdaterClass.add_employee(state, 0, employee_id, employee_id == "pizza_cook")
		if not add.ok:
			return Result.failure("add %s failed: %s" % [employee_id, add.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "campaign_manager", "reports": []},
			{},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.milestone_pool = ["first_pizza_marketed"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_radio_marketing_milestone_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
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
		return Result.failure("seed radio route cash failed: %s" % seed_cash.error)
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for active_employee_id in ["brand_director", "burger_cook"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "brand_director", "reports": []},
			{"employee_id": "burger_cook", "reports": []},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.milestone_pool = ["first_radio"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_airplane_marketing_milestone_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
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
		return Result.failure("seed airplane route cash failed: %s" % seed_cash.error)
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for active_employee_id in ["brand_manager", "burger_cook"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "brand_manager", "reports": []},
			{"employee_id": "burger_cook", "reports": []},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.milestone_pool = ["first_airplane"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_drink_marketing_milestone_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	_force_route_turn_order(state, 2)
	var map_result := _build_route_marketing_sale_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	var house: Dictionary = Dictionary(Dictionary(state.map.get("houses", {})).get("house_route", {})).duplicate(true)
	house["demands"] = [
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
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 50)
	if not seed_cash.ok:
		return Result.failure("seed drink marketing route cash failed: %s" % seed_cash.error)
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for active_employee_id in ["campaign_manager", "truck_driver"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "campaign_manager", "reports": []},
			{"employee_id": "truck_driver", "reports": []},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.milestone_pool = ["first_drink_marketed"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_early_income_full_route_engine(seed_val: int) -> Result:
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
		return Result.failure("seed early route cash failed: %s" % seed_cash.error)
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for active_employee_id in ["trainer", "campaign_manager"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	var take_trainee := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("take kitchen_trainee failed: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "kitchen_trainee", true)
	if not add_trainee.ok:
		return Result.failure("add kitchen_trainee failed: %s" % add_trainee.error)
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
	state.milestone_pool = ["first_train", "first_burger_marketed"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_blocked_billboard_training_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
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
		return Result.failure("seed blocked billboard route cash failed: %s" % seed_cash.error)
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for active_employee_id in ["trainer", "burger_cook"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	for reserve_employee_id in ["marketing_trainee"]:
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
			{"employee_id": "burger_cook", "reports": []},
			{},
		],
	}
	var occupy := _occupy_base_billboards_for_player(state, 1)
	if not occupy.ok:
		return occupy
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	state.current_player_index = 0
	state.milestone_pool = ["first_train"]
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

static func _scenario_first_train_salary_delta_reduces_payday_due(seed_val: int) -> Result:
	var engine_read := _build_training_income_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("first_train salary scenario train step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "train":
		return Result.failure("expected first_train salary scenario to train, got %s" % str(trace))
	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_train"):
		return Result.failure("first_train salary scenario should claim first_train before Payday, milestones=%s trace=%s" % [str(milestones), str(trace)])
	var cash_before := int(Dictionary(state.players[0]).get("cash", 0))
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	state.current_player_index = 0
	var advance := engine.phase_manager.advance_phase(state)
	if not advance.ok:
		return Result.failure("first_train salary scenario Payday advance failed: %s" % advance.error)
	state = engine.get_state()
	var report: Dictionary = Dictionary(state.round_state.get("payday", {}))
	var details: Array = Array(report.get("details", []))
	if details.is_empty():
		return Result.failure("first_train salary scenario should record Payday details, report=%s" % str(report))
	var player0: Dictionary = Dictionary(details[0])
	if int(player0.get("base_due", -1)) <= 0:
		return Result.failure("first_train salary scenario should have positive base salary before milestone delta, details=%s" % str(player0))
	if int(player0.get("milestone_delta", 0)) != -15:
		return Result.failure("first_train salary scenario should apply -15 salary_total_delta, details=%s" % str(player0))
	if int(player0.get("due", -1)) != 0:
		return Result.failure("first_train salary scenario should reduce due to 0, details=%s" % str(player0))
	if int(Dictionary(state.players[0]).get("cash", 0)) != cash_before:
		return Result.failure("first_train salary scenario should not spend cash after due reaches 0, before=%d after=%d report=%s" % [cash_before, int(Dictionary(state.players[0]).get("cash", 0)), str(report)])
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

static func _scenario_burger_demand_claims_first_burger_produced_and_sells(seed_val: int) -> Result:
	var engine_read := _build_burger_production_milestone_sale_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("burger production milestone route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected StrategyBot to produce food for burger demand, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("employee_type", "")) != "kitchen_trainee" or str(params.get("food_type", "")) != "burger":
		return Result.failure("expected kitchen_trainee to produce burger for first_burger_produced, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if not Array(features.get("milestone_race_ids", [])).has("first_burger_produced"):
		return Result.failure("burger production should expose first_burger_produced race id, features=%s trace=%s" % [str(features), str(trace)])
	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_burger_produced"):
		return Result.failure("burger production should claim first_burger_produced, milestones=%s trace=%s" % [str(milestones), str(trace)])
	var reserve: Array = Array(Dictionary(state.players[0]).get("reserve_employees", []))
	if not reserve.has("burger_cook"):
		return Result.failure("first_burger_produced should grant burger_cook to reserve, reserve=%s" % str(reserve))
	var inventory: Dictionary = Dictionary(Dictionary(state.players[0]).get("inventory", {}))
	if int(inventory.get("burger", 0)) <= 0:
		return Result.failure("burger production should add burger inventory, inventory=%s" % str(inventory))
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("cash", 0)) <= cash_before_dinner:
		return Result.failure("burger production route should sell at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(Dictionary(state.players[0]).get("cash", 0))])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("burger production route Dinnertime should clear burger demand")
	return Result.success()

static func _build_burger_production_milestone_sale_engine(seed_val: int) -> Result:
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
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	state.players[0]["cash"] = 0
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	var take_trainee := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("take kitchen_trainee failed: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "kitchen_trainee", false)
	if not add_trainee.ok:
		return Result.failure("add kitchen_trainee failed: %s" % add_trainee.error)
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "kitchen_trainee", "reports": []},
			{},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.milestone_pool = ["first_burger_produced"]
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _scenario_pizza_demand_claims_first_pizza_produced_and_sells(seed_val: int) -> Result:
	var engine_read := _build_pizza_production_milestone_sale_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("pizza production milestone route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected StrategyBot to produce food for pizza demand, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("employee_type", "")) != "kitchen_trainee" or str(params.get("food_type", "")) != "pizza":
		return Result.failure("expected kitchen_trainee to produce pizza for first_pizza_produced, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if not Array(features.get("milestone_race_ids", [])).has("first_pizza_produced"):
		return Result.failure("pizza production should expose first_pizza_produced race id, features=%s trace=%s" % [str(features), str(trace)])
	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_pizza_produced"):
		return Result.failure("pizza production should claim first_pizza_produced, milestones=%s trace=%s" % [str(milestones), str(trace)])
	var reserve: Array = Array(Dictionary(state.players[0]).get("reserve_employees", []))
	if not reserve.has("pizza_cook"):
		return Result.failure("first_pizza_produced should grant pizza_cook to reserve, reserve=%s" % str(reserve))
	var inventory: Dictionary = Dictionary(Dictionary(state.players[0]).get("inventory", {}))
	if int(inventory.get("pizza", 0)) <= 0:
		return Result.failure("pizza production should add pizza inventory, inventory=%s" % str(inventory))
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("cash", 0)) <= cash_before_dinner:
		return Result.failure("pizza production route should sell at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(Dictionary(state.players[0]).get("cash", 0))])
	if _state_product_demand_count(state, "pizza") != 0:
		return Result.failure("pizza production route Dinnertime should clear pizza demand")
	return Result.success()

static func _build_pizza_production_milestone_sale_engine(seed_val: int) -> Result:
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
		{"product": "pizza"},
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	state.players[0]["cash"] = 0
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	var take_trainee := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take_trainee.ok:
		return Result.failure("take kitchen_trainee failed: %s" % take_trainee.error)
	var add_trainee := StateUpdaterClass.add_employee(state, 0, "kitchen_trainee", false)
	if not add_trainee.ok:
		return Result.failure("add kitchen_trainee failed: %s" % add_trainee.error)
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "kitchen_trainee", "reports": []},
			{},
			{},
		],
	}
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.milestone_pool = ["first_pizza_produced"]
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

static func _scenario_income_route_structures_drink_supply_for_serviceable_demand(seed_val: int) -> Result:
	var engine_read := _build_structure_drink_supply_route_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var structure_read := _run_restructuring_until_direct_staff_active(engine, bot, ["cart_operator"], 3)
	if not structure_read.ok:
		return structure_read
	var traces: Array = Array(Dictionary(structure_read.value).get("traces", []))
	var saw_cart_activation := false
	for trace_val in traces:
		if not (trace_val is Dictionary):
			continue
		var trace: Dictionary = trace_val
		if str(trace.get("action_id", "")) != "set_company_structure_direct":
			continue
		var params: Dictionary = Dictionary(trace.get("params", {}))
		if str(params.get("employee_id", "")) != "cart_operator":
			continue
		var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
		if float(features.get("structure_drink_activation_value", 0.0)) <= 0.0:
			return Result.failure("cart_operator structure should expose drink activation value: %s" % str(trace))
		if not Array(features.get("structure_drink_activation_products", [])).has("soda"):
			return Result.failure("cart_operator structure should expose soda activation product: %s" % str(trace))
		saw_cart_activation = true
	if not saw_cart_activation:
		return Result.failure("expected restructuring traces to activate cart_operator: %s" % str(traces))

	var prepare_get_drinks := _prepare_current_round_get_drinks(engine)
	if not prepare_get_drinks.ok:
		return prepare_get_drinks
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("structured drink supply step failed: %s" % step.error)
	var drink_trace: Dictionary = step.value
	if str(drink_trace.get("action_id", "")) != "procure_drinks":
		return Result.failure("expected structured drink supply to procure soda, got %s" % str(drink_trace))
	var drink_params: Dictionary = Dictionary(drink_trace.get("params", {}))
	if str(drink_params.get("employee_type", "")) != "cart_operator":
		return Result.failure("expected structured drink supply to use cart_operator, got %s" % str(drink_trace))
	if not Array(drink_params.get("selected_sources", [])).has([7, 2]):
		return Result.failure("expected structured drink supply to select soda source [7, 2], got %s" % str(drink_trace))
	var state := engine.get_state()
	var inventory: Dictionary = Dictionary(Dictionary(state.players[0]).get("inventory", {}))
	if int(inventory.get("soda", 0)) < 2:
		return Result.failure("structured drink supply should procure soda, inventory=%s" % str(inventory))
	var cash_before_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("cash", 0)) <= cash_before_dinner:
		return Result.failure("structured drink supply should sell at Dinnertime, cash before=%d after=%d" % [cash_before_dinner, int(Dictionary(state.players[0]).get("cash", 0))])
	if _state_product_demand_count(state, "soda") != 0:
		return Result.failure("structured drink supply Dinnertime should clear soda demand")
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

static func _build_structure_drink_supply_route_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
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
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 35)
	if not seed_cash.ok:
		return Result.failure("seed structure drink route cash failed: %s" % seed_cash.error)
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
	for reserve_employee_id in ["trainer", "pricing_manager", "kitchen_trainee", "cart_operator"]:
		var take_reserve := StateUpdaterClass.take_from_pool(state, reserve_employee_id, 1)
		if not take_reserve.ok:
			return Result.failure("take %s failed: %s" % [reserve_employee_id, take_reserve.error])
		var add_reserve := StateUpdaterClass.add_employee(state, 0, reserve_employee_id, true)
		if not add_reserve.ok:
			return Result.failure("add %s failed: %s" % [reserve_employee_id, add_reserve.error])
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.sub_phase = ""
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

static func _prepare_current_round_marketing(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	return _sync_initial_checkpoint_to_current_state(engine)

static func _prepare_current_round_get_drinks(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
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

static func _seed_current_structure(engine: GameEngine, direct_employee_ids: Array[String]) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	var structure: Array = []
	for employee_id in direct_employee_ids:
		if str(employee_id).is_empty():
			continue
		structure.append({"employee_id": str(employee_id), "reports": []})
	while structure.size() < 3:
		structure.append({})
	var player: Dictionary = state.players[0]
	player["company_structure"] = {
		"ceo_slots": 3,
		"structure": structure,
	}
	state.players[0] = player
	return _sync_initial_checkpoint_to_current_state(engine)

static func _run_restructuring_until_direct_staff_active(engine: GameEngine, bot, required_employee_ids: Array[String], max_steps: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if bot == null:
		return Result.failure("bot is null")
	var controller := BotControllerClass.new()
	var traces: Array = []
	for _i in range(maxi(1, max_steps)):
		var state := engine.get_state()
		var missing := _missing_active_employee_ids(state, 0, required_employee_ids)
		if missing.is_empty():
			return Result.success({"traces": traces})
		var step := controller.step(engine, 0, bot, TimeBudget.start(80))
		if not step.ok:
			return Result.failure("restructuring activation step failed: %s traces=%s" % [step.error, str(traces)])
		var trace: Dictionary = step.value
		traces.append(trace)
		var action_id := str(trace.get("action_id", ""))
		if action_id == "submit_restructuring":
			var state_after := engine.get_state()
			var still_missing := _missing_active_employee_ids(state_after, 0, required_employee_ids)
			if not still_missing.is_empty():
				return Result.failure("submitted restructuring before activating required employees %s, traces=%s" % [str(still_missing), str(traces)])
		elif action_id != "set_company_structure_direct" and action_id != "set_company_structure_report":
			return Result.failure("expected restructuring activation action, got %s traces=%s" % [str(trace), str(traces)])
	var final_state := engine.get_state()
	var final_missing := _missing_active_employee_ids(final_state, 0, required_employee_ids)
	if not final_missing.is_empty():
		return Result.failure("failed to activate required employees %s after %d steps, traces=%s" % [str(final_missing), max_steps, str(traces)])
	return Result.success({"traces": traces})

static func _missing_active_employee_ids(state: GameState, player_id: int, required_employee_ids: Array[String]) -> Array[String]:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return required_employee_ids.duplicate()
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return required_employee_ids.duplicate()
	var active_val = Dictionary(player_val).get("employees", [])
	var active: Array = active_val if (active_val is Array) else []
	var missing: Array[String] = []
	for required_id in required_employee_ids:
		var have := 0
		for employee_val in active:
			if str(employee_val) == required_id:
				have += 1
		if have < 1:
			missing.append(required_id)
	return missing

static func _occupy_base_billboards_for_player(state: GameState, owner: int) -> Result:
	if state == null:
		return Result.failure("state is null")
	var placements_val = state.map.get("marketing_placements", null)
	if not (placements_val is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	var placements: Dictionary = placements_val
	var billboard_specs := {
		11: Vector2i(3, 2),
		13: Vector2i(3, 1),
		14: Vector2i(2, 1),
	}
	for board_number in [11, 13, 14]:
		var footprint: Vector2i = billboard_specs[board_number]
		var inst := {
			"board_number": board_number,
			"type": "billboard",
			"owner": owner,
			"employee_type": "marketing_trainee",
			"product": "pizza",
			"world_pos": Vector2i(1, 0),
			"rotation": 0,
			"footprint_size": footprint,
			"remaining_duration": 9,
			"axis": "",
			"tile_index": -1,
			"created_round": state.round_number,
		}
		state.marketing_instances.append(inst.duplicate(true))
		placements[str(board_number)] = {
			"board_number": board_number,
			"type": "billboard",
			"owner": owner,
			"product": "pizza",
			"world_pos": Vector2i(1, 0),
			"rotation": 0,
			"footprint_size": footprint,
			"remaining_duration": 9,
			"axis": "",
			"tile_index": -1,
		}
	state.map["marketing_placements"] = placements
	return Result.success()

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

static func _round_state_player_count(round_state: Dictionary, counter_key: String, player_id: int) -> int:
	if counter_key.is_empty():
		return 0
	var all_val = round_state.get(counter_key, null)
	if not (all_val is Dictionary):
		return 0
	var all_counts: Dictionary = all_val
	if all_counts.has(player_id):
		return int(all_counts.get(player_id, 0))
	var string_key := str(player_id)
	if all_counts.has(string_key):
		return int(all_counts.get(string_key, 0))
	return 0

static func _set_player_cash_by_transfer(state: GameState, player_id: int, target_cash: int) -> Result:
	if state == null:
		return Result.failure("set cash by transfer failed: state is null")
	if target_cash < 0:
		return Result.failure("set cash by transfer failed: target_cash must be >= 0, got %d" % target_cash)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("set cash by transfer failed: invalid player_id=%d" % player_id)
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("set cash by transfer failed: player[%d] is not Dictionary" % player_id)
	var current_cash := int(Dictionary(player_val).get("cash", 0))
	var delta := target_cash - current_cash
	if delta > 0:
		return StateUpdaterClass.player_receive_from_bank(state, player_id, delta)
	if delta < 0:
		return StateUpdaterClass.player_pay_to_bank(state, player_id, -delta)
	return Result.success()

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

static func _scenario_cleanup_fridge_keep_prioritizes_pending_marketing(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var claim := StateUpdaterClass.claim_milestone(state, 0, "first_throw_away")
	if not claim.ok:
		return Result.failure("claim first_throw_away failed: %s" % claim.error)
	state.players[0]["inventory"] = {
		"beer": 12,
		"soda": 12,
	}
	state.marketing_instances = [
		{
			"owner": 0,
			"product": "soda",
			"demand_amount": 3,
			"remaining_duration": 2,
		},
	]
	state.round_state["cleanup"] = {
		"fridge_choice_pending": true,
		"pending_choice_kind": "fridge",
	}
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [
			{"kind": "fridge_keep", "player_id": 0},
		],
	}
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync

	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("cleanup fridge keep step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "choose_fridge_keep":
		return Result.failure("expected StrategyBot to choose fridge keep, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	var keep: Dictionary = Dictionary(params.get("keep", {}))
	if int(keep.get("soda", 0)) < 3:
		return Result.failure("fridge keep should preserve pending soda marketing inventory before excess beer: keep=%s trace=%s" % [str(keep), str(trace)])
	var state_after := engine.get_state()
	if state_after == null:
		return Result.failure("engine state is null after cleanup fridge keep")
	var inventory_after: Dictionary = Dictionary(state_after.players[0].get("inventory", {}))
	if int(inventory_after.get("soda", 0)) < 3:
		return Result.failure("executed fridge keep should preserve pending soda marketing inventory: inventory=%s keep=%s" % [str(inventory_after), str(keep)])
	if int(inventory_after.get("beer", 0)) + int(inventory_after.get("soda", 0)) != 10:
		return Result.failure("executed fridge keep should leave exactly fridge capacity 10: inventory=%s keep=%s" % [str(inventory_after), str(keep)])
	var cleanup: Dictionary = Dictionary(state_after.round_state.get("cleanup", {}))
	if not cleanup.is_empty() and bool(cleanup.get("fridge_choice_pending", false)):
		return Result.failure("executed fridge keep should clear cleanup fridge pending: %s" % str(cleanup))
	var pending_val = state_after.round_state.get("pending_phase_actions", {})
	if pending_val is Dictionary:
		var cleanup_pending_val = Dictionary(pending_val).get(DefsClass.PHASE_CLEANUP, [])
		if cleanup_pending_val is Array:
			for pending_item in Array(cleanup_pending_val):
				if pending_item is Dictionary and str(Dictionary(pending_item).get("kind", "")) == "fridge_keep":
					return Result.failure("executed fridge keep should remove fridge pending task: %s" % str(cleanup_pending_val))
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
	observation.employee_pool_public = _full_base_recruit_pool()
	observation.milestone_pool_public = ["first_lower_prices"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 3)
	var chosen_read := _best_recruit_candidate(observation, seed_val, 12)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("employee_id", "")) != "pricing_manager":
		return Result.failure("expected stable income route to keep and add pricing_manager under default recruit candidate budget, got %s" % str(chosen))
	var features: Dictionary = Dictionary(chosen.get("features", {}))
	if float(features.get("recruit_price_route_value", 0.0)) <= 0.0:
		return Result.failure("expected pricing route value feature on pricing_manager recruit: %s" % str(chosen))
	if not bool(features.get("recruit_price_route_first_lower_prices_available", false)):
		return Result.failure("expected pricing route to expose first_lower_prices availability: %s" % str(chosen))
	return Result.success()

static func _scenario_income_route_recruits_pricing_for_serviceable_price_opportunity(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["cash"] = 0
	observation.own_player["employees"] = ["burger_cook", "campaign_manager", "trainer", "errand_boy"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 1}
	observation.own_player["milestones"] = []
	observation.employee_pool_public = _full_base_recruit_pool()
	observation.milestone_pool_public = ["first_lower_prices"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 1)
	var chosen_read := _best_recruit_candidate(observation, seed_val, 12)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("employee_id", "")) != "pricing_manager":
		return Result.failure("expected one serviceable price opportunity to recruit pricing_manager, got %s" % str(chosen))
	var features: Dictionary = Dictionary(chosen.get("features", {}))
	if int(features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("expected pricing_manager desired count for price opportunity: %s" % str(chosen))
	if float(features.get("recruit_price_route_value", 0.0)) <= 0.0:
		return Result.failure("expected pricing route value for one serviceable opportunity: %s" % str(chosen))
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

static func _scenario_income_route_price_action_claims_lower_price_milestone(seed_val: int) -> Result:
	var engine_read := _build_income_route_price_action_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("price action milestone route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "set_price":
		return Result.failure("expected StrategyBot engine route to execute set_price, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if str(features.get("price_source", "")) != "pricing_pipeline":
		return Result.failure("expected engine price route to use PricingPipeline source, features=%s trace=%s" % [str(features), str(trace)])
	if int(features.get("price_estimated_sale_units", 0)) <= 0:
		return Result.failure("expected engine price route to estimate sale units, features=%s trace=%s" % [str(features), str(trace)])

	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after set_price")
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_lower_prices"):
		return Result.failure("engine set_price route should claim first_lower_prices, milestones=%s trace=%s" % [str(milestones), str(trace)])
	var price_modifiers_val = state.round_state.get("price_modifiers", {})
	if not (price_modifiers_val is Dictionary):
		return Result.failure("engine set_price route should write price_modifiers, round_state=%s" % str(state.round_state))
	var player_modifiers_val = Dictionary(price_modifiers_val).get(0, Dictionary(price_modifiers_val).get("0", {}))
	if not (player_modifiers_val is Dictionary):
		return Result.failure("engine set_price route missing player price modifier, price_modifiers=%s" % str(price_modifiers_val))
	if int(Dictionary(player_modifiers_val).get("pricing_manager", 0)) != -1:
		return Result.failure("engine set_price route should write pricing_manager -1 modifier, player_modifiers=%s" % str(player_modifiers_val))
	var current_price_read := PricingPipelineClass.calculate_unit_price(state, 0)
	if not current_price_read.ok:
		return current_price_read
	var expected_current_price := int(state.get_rule_int("base_unit_price")) - 2
	if int(current_price_read.value) != expected_current_price:
		return Result.failure("first_lower_prices current round price should combine permanent base delta and set_price modifier, got=%d expected=%d state=%s" % [int(current_price_read.value), expected_current_price, str(state.round_state)])
	var saved_price_modifiers: Dictionary = Dictionary(price_modifiers_val).duplicate(true)
	state.round_state["price_modifiers"] = {}
	var permanent_price_read := PricingPipelineClass.calculate_unit_price(state, 0)
	state.round_state["price_modifiers"] = saved_price_modifiers
	if not permanent_price_read.ok:
		return permanent_price_read
	var expected_permanent_price := int(state.get_rule_int("base_unit_price")) - 1
	if int(permanent_price_read.value) != expected_permanent_price:
		return Result.failure("first_lower_prices should leave permanent base price delta after round modifiers clear, got=%d expected=%d milestones=%s" % [int(permanent_price_read.value), expected_permanent_price, str(milestones)])
	return Result.success()

static func _scenario_income_route_price_action_wins_contested_sale(seed_val: int) -> Result:
	var engine_read := _build_income_route_contested_price_action_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("contested price action step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "set_price":
		return Result.failure("expected StrategyBot to set price before contested sale, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if str(features.get("price_source", "")) != "pricing_pipeline":
		return Result.failure("expected contested price action to use PricingPipeline, features=%s trace=%s" % [str(features), str(trace)])
	if int(features.get("price_estimated_sale_units", 0)) <= 0:
		return Result.failure("expected contested price action to estimate sale units, features=%s trace=%s" % [str(features), str(trace)])

	var state := engine.get_state()
	var cash_before := int(Dictionary(state.players[0]).get("cash", 0))
	var adv := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not adv.ok:
		return adv
	state = engine.get_state()
	var cash_after := int(Dictionary(state.players[0]).get("cash", 0))
	if cash_after <= cash_before:
		return Result.failure("lower price should win contested sale and increase cash, before=%d after=%d" % [cash_before, cash_after])
	if int(Dictionary(state.players[1]).get("cash", 0)) != 0:
		return Result.failure("opponent should not win contested sale after lower price, player1=%s" % str(state.players[1]))
	if int(Dictionary(Dictionary(state.players[0]).get("inventory", {})).get("burger", 0)) != 0:
		return Result.failure("winning contested sale should consume player 0 burger inventory, player0=%s" % str(state.players[0]))
	if int(Dictionary(Dictionary(state.players[1]).get("inventory", {})).get("burger", 0)) != 1:
		return Result.failure("opponent inventory should remain after losing contested sale, player1=%s" % str(state.players[1]))
	var house_right: Dictionary = Dictionary(Dictionary(state.map.get("houses", {})).get("house_right", {}))
	if Array(house_right.get("demands", [])).size() != 0:
		return Result.failure("contested sale should clear house_right demand, house_right=%s" % str(house_right))
	return Result.success()

static func _build_income_route_price_action_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
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
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 35)
	if not seed_cash.ok:
		return Result.failure("seed price action route cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 3,
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
	state.players[0]["milestones"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
	}
	for active_employee_id in ["burger_cook", "campaign_manager", "pricing_manager"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "burger_cook", "reports": []},
			{"employee_id": "campaign_manager", "reports": []},
			{"employee_id": "pricing_manager", "reports": []},
		],
	}
	state.milestone_pool = ["first_lower_prices"]
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_income_route_contested_price_action_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "burger"}])
	var seed_cash := StateUpdaterClass.player_receive_from_bank(state, 0, 35)
	if not seed_cash.ok:
		return Result.failure("seed contested price action route cash failed: %s" % seed_cash.error)
	state.players[0]["inventory"] = {
		"burger": 1,
		"pizza": 0,
		"soda": 0,
		"lemonade": 0,
		"beer": 0,
	}
	state.players[1]["inventory"] = {
		"burger": 1,
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
	state.players[1]["employees"] = ["ceo"]
	state.players[1]["reserve_employees"] = []
	state.players[1]["busy_marketers"] = []
	state.players[1]["employees_staff_ids"] = []
	state.players[1]["reserve_staff_ids"] = []
	state.players[1]["busy_staff_ids"] = []
	state.players[1]["staff_registry"] = {}
	state.players[1]["milestones"] = []
	for active_employee_id in ["burger_cook", "campaign_manager", "pricing_manager"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "burger_cook", "reports": []},
			{"employee_id": "campaign_manager", "reports": []},
			{"employee_id": "pricing_manager", "reports": []},
		],
	}
	state.milestone_pool = ["first_lower_prices"]
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _scenario_income_route_recruits_waitress_after_price_support(seed_val: int) -> Result:
	var observation := _synthetic_food_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["cash"] = 35
	observation.own_player["employees"] = ["burger_cook", "campaign_manager", "errand_boy", "pricing_manager"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["inventory"] = {"burger": 3}
	observation.own_player["milestones"] = []
	observation.employee_pool_public = _full_base_recruit_pool()
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
	pre_price_observation.employee_pool_public = _full_base_recruit_pool()
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
	if int(pre_price_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("expected waitress desired count to stay zero before price support: %s" % str(pre_price_features))
	var pre_price_chosen_read := _best_recruit_candidate(pre_price_observation, seed_val, 12)
	if not pre_price_chosen_read.ok:
		return pre_price_chosen_read
	var pre_price_chosen: Dictionary = pre_price_chosen_read.value
	if str(pre_price_chosen.get("employee_id", "")) == "waitress":
		return Result.failure("expected stable income route without price support to delay waitress recruit, got %s" % str(pre_price_chosen))
	var chosen_read := _best_recruit_candidate(observation, seed_val, 12)
	if not chosen_read.ok:
		return chosen_read
	var chosen: Dictionary = chosen_read.value
	if str(chosen.get("employee_id", "")) != "waitress":
		return Result.failure("expected stable income route with price support to keep and add waitress under default recruit candidate budget, got %s" % str(chosen))
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

static func _scenario_waitress_active_route_claims_first_waitress_and_tips(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	_force_route_turn_order(state, 2)
	var map_result := _build_route_marketing_sale_map(0)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	var house: Dictionary = Dictionary(Dictionary(state.map.get("houses", {})).get("house_route", {})).duplicate(true)
	house["demands"] = [
		{"product": "burger"},
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	state.players[0]["cash"] = 0
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
	state.players[0]["milestones"] = []
	for active_employee_id in ["kitchen_trainee", "waitress"]:
		var take_active := StateUpdaterClass.take_from_pool(state, active_employee_id, 1)
		if not take_active.ok:
			return Result.failure("take %s failed: %s" % [active_employee_id, take_active.error])
		var add_active := StateUpdaterClass.add_employee(state, 0, active_employee_id, false)
		if not add_active.ok:
			return Result.failure("add %s failed: %s" % [active_employee_id, add_active.error])
	state.players[0]["company_structure"] = {
		"ceo_slots": 3,
		"structure": [
			{"employee_id": "kitchen_trainee", "reports": []},
			{"employee_id": "waitress", "reports": []},
			{},
		],
	}
	state.milestone_pool = ["first_waitress"]
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	_reset_round_state_for_ai_step(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync

	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var produce_step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not produce_step.ok:
		return Result.failure("waitress active route production step failed: %s" % produce_step.error)
	var produce_trace: Dictionary = produce_step.value
	if str(produce_trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected waitress active route to produce burger before dinner, got %s" % str(produce_trace))
	var produce_params: Dictionary = Dictionary(produce_trace.get("params", {}))
	if str(produce_params.get("food_type", "")) != "burger":
		return Result.failure("expected waitress active route production food burger, got %s" % str(produce_trace))
	state = engine.get_state()
	if int(Dictionary(state.players[0]).get("inventory", {}).get("burger", 0)) <= 0:
		return Result.failure("waitress active route should leave burger inventory before Dinnertime")
	if Array(Dictionary(state.players[0]).get("milestones", [])).has("first_waitress"):
		return Result.failure("first_waitress should not be claimed before Dinnertime waitress use")

	var cash_before_dinner := int(state.players[0].get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	var cash_after_dinner := int(state.players[0].get("cash", 0))
	if not Array(Dictionary(state.players[0]).get("milestones", [])).has("first_waitress"):
		return Result.failure("Dinnertime waitress use should claim first_waitress, milestones=%s" % str(Dictionary(state.players[0]).get("milestones", [])))
	if cash_after_dinner - cash_before_dinner < 15:
		return Result.failure("waitress active route should sell burger and collect first_waitress tips, cash before=%d after=%d" % [cash_before_dinner, cash_after_dinner])
	if _state_product_demand_count(state, "burger") != 0:
		return Result.failure("waitress active route Dinnertime should clear burger demand")
	return Result.success()

static func _scenario_payday_fire_resolves_shortfall_with_low_income_employee(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.rules["salary_cost"] = 5
	var current_cash := int(state.players[0].get("cash", 0))
	if current_cash > 5:
		var pay_down := StateUpdaterClass.player_pay_to_bank(state, 0, current_cash - 5)
		if not pay_down.ok:
			return Result.failure("payday fire scenario reduce cash failed: %s" % pay_down.error)
	elif current_cash < 5:
		var top_up := StateUpdaterClass.player_receive_from_bank(state, 0, 5 - current_cash)
		if not top_up.ok:
			return Result.failure("payday fire scenario top up cash failed: %s" % top_up.error)
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["inventory"] = {}
	state.players[0]["milestones"] = []
	for employee_id in ["burger_cook", "cfo"]:
		var take := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take.ok:
			return Result.failure("payday fire scenario take %s failed: %s" % [employee_id, take.error])
		var add := StateUpdaterClass.add_employee(state, 0, employee_id, false)
		if not add.ok:
			return Result.failure("payday fire scenario add %s failed: %s" % [employee_id, add.error])
	var cfo_pool_before := int(state.employee_pool.get("cfo", 0))
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync

	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("payday fire step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "fire":
		return Result.failure("expected StrategyBot to fire during Payday shortfall, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("employee_id", "")) != "cfo":
		return Result.failure("expected StrategyBot to fire low-income cfo before burger_cook, got %s" % str(trace))
	var state_after_fire := engine.get_state()
	if state_after_fire == null:
		return Result.failure("engine state is null after payday fire")
	var employees_after: Array = Array(state_after_fire.players[0].get("employees", []))
	if employees_after.has("cfo"):
		return Result.failure("payday fire should remove cfo from active employees: %s" % str(employees_after))
	if not employees_after.has("burger_cook"):
		return Result.failure("payday fire should preserve income employee burger_cook: %s" % str(employees_after))
	var cfo_pool_after := int(state_after_fire.employee_pool.get("cfo", 0))
	if cfo_pool_after != cfo_pool_before + 1:
		return Result.failure("payday fire should return cfo to pool: before=%d after=%d" % [cfo_pool_before, cfo_pool_after])
	var settle := engine.phase_manager.advance_phase(state_after_fire)
	if not settle.ok:
		return Result.failure("Payday should settle after firing cfo: %s" % settle.error)
	var report: Dictionary = Dictionary(engine.get_state().round_state.get("payday", {}))
	var unpaid: Array = Array(report.get("unpaid", []))
	if unpaid.size() <= 0 or int(unpaid[0]) != 0:
		return Result.failure("Payday should have no unpaid salary after firing cfo: %s" % str(report))
	return Result.success()

static func _scenario_payday_keeps_staff_to_claim_first_pay_20_salaries(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_pay_20_salaries"]
	var current_cash := int(state.players[0].get("cash", 0))
	if current_cash > 20:
		var pay_down := StateUpdaterClass.player_pay_to_bank(state, 0, current_cash - 20)
		if not pay_down.ok:
			return Result.failure("payday salary milestone reduce cash failed: %s" % pay_down.error)
	elif current_cash < 20:
		var top_up := StateUpdaterClass.player_receive_from_bank(state, 0, 20 - current_cash)
		if not top_up.ok:
			return Result.failure("payday salary milestone top up cash failed: %s" % top_up.error)
	state.players[0]["employees"] = []
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["employees_staff_ids"] = []
	state.players[0]["reserve_staff_ids"] = []
	state.players[0]["busy_staff_ids"] = []
	state.players[0]["staff_registry"] = {}
	state.players[0]["inventory"] = {}
	state.players[0]["milestones"] = []
	var add_ceo := StateUpdaterClass.add_employee(state, 0, "ceo", false)
	if not add_ceo.ok:
		return Result.failure("payday salary milestone add ceo failed: %s" % add_ceo.error)
	if not Array(state.players[1].get("employees", [])).has("ceo"):
		var add_other_ceo := StateUpdaterClass.add_employee(state, 1, "ceo", false)
		if not add_other_ceo.ok:
			return Result.failure("payday salary milestone add player1 ceo failed: %s" % add_other_ceo.error)
	for _i in range(4):
		var take := StateUpdaterClass.take_from_pool(state, "burger_cook", 1)
		if not take.ok:
			return Result.failure("payday salary milestone take burger_cook failed: %s" % take.error)
		var add := StateUpdaterClass.add_employee(state, 0, "burger_cook", false)
		if not add.ok:
			return Result.failure("payday salary milestone add burger_cook failed: %s" % add.error)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync

	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("payday salary milestone step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) == "fire":
		return Result.failure("expected StrategyBot not to fire when cash covers $20 salary milestone, got %s" % str(trace))
	var finish_controller := BotControllerClass.new()
	var other_bot = StrategyBotClass.new()
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var test_state := test_engine.get_state()
		return test_state != null and str(test_state.phase) != DefsClass.PHASE_PAYDAY
	var finish := finish_controller.run_until(engine, {0: bot, 1: other_bot}, stop_condition, 8, 80)
	if not finish.ok:
		return Result.failure("payday salary milestone finish failed: %s" % finish.error)
	for trace_val in finish_controller.last_trace:
		if trace_val is Dictionary and str(Dictionary(trace_val).get("action_id", "")) == "fire":
			return Result.failure("expected Payday salary milestone finish not to fire, trace=%s" % str(finish_controller.last_trace))
	var state_after := engine.get_state()
	if state_after == null:
		return Result.failure("engine state is null after payday salary milestone step")
	var milestones: Array = Array(state_after.players[0].get("milestones", []))
	if not milestones.has("first_pay_20_salaries"):
		return Result.failure("Payday step should claim first_pay_20_salaries, action=%s milestones=%s" % [str(trace), str(milestones)])
	if not bool(state_after.players[0].get("multi_trainer_on_one", false)):
		return Result.failure("first_pay_20_salaries should enable multi_trainer_on_one, player=%s" % str(state_after.players[0]))
	if int(state_after.players[0].get("cash", -1)) != 0:
		return Result.failure("Payday salary milestone should spend exactly $20 salary, player=%s" % str(state_after.players[0]))
	return Result.success()

static func _scenario_third_recruit_claims_first_hire_3_with_real_recruit_action(seed_val: int) -> Result:
	var engine_read := _build_first_hire_3_real_recruit_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("third recruit route step failed: %s" % step.error)
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "recruit":
		return Result.failure("expected StrategyBot to execute third recruit, got %s" % str(trace))
	var params: Dictionary = Dictionary(trace.get("params", {}))
	var recruited_id := str(params.get("employee_type", "")).strip_edges()
	if _employee_role(recruited_id) != "produce_food":
		return Result.failure("expected third recruit route to fill food supply before claiming first_hire_3, got %s" % str(trace))
	var features: Dictionary = Dictionary(Dictionary(trace.get("explanation", {})).get("features", {}))
	if not Array(features.get("milestone_race_ids", [])).has("first_hire_3"):
		return Result.failure("third recruit route should expose first_hire_3 race id, features=%s trace=%s" % [str(features), str(trace)])
	if float(features.get("milestone_race_value", 0.0)) <= 10.0:
		return Result.failure("third recruit route should materially value first_hire_3 gain_cards effect, features=%s trace=%s" % [str(features), str(trace)])
	var state := engine.get_state()
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has("first_hire_3"):
		return Result.failure("third real recruit should claim first_hire_3, milestones=%s trace=%s" % [str(milestones), str(trace)])
	if _round_state_player_count(state.round_state, "recruit_used", 0) != 3:
		return Result.failure("third real recruit should advance recruit_used to 3, round_state=%s" % str(state.round_state))
	var reserve: Array = Array(Dictionary(state.players[0]).get("reserve_employees", []))
	if not reserve.has(recruited_id):
		return Result.failure("third real recruit should add recruited employee to reserve, recruited=%s reserve=%s" % [recruited_id, str(reserve)])
	var trainee_count := 0
	for emp in reserve:
		if emp is String and str(emp) == "management_trainee":
			trainee_count += 1
	if trainee_count < 2:
		return Result.failure("first_hire_3 should grant two management_trainee cards, reserve=%s" % str(reserve))
	return Result.success()

static func _build_first_hire_3_real_recruit_engine(seed_val: int) -> Result:
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
	]
	var houses: Dictionary = Dictionary(state.map.get("houses", {})).duplicate(true)
	houses["house_route"] = house
	state.map["houses"] = houses
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
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
	state.players[0]["milestones"] = []
	var take_hr := StateUpdaterClass.take_from_pool(state, "hr_director", 1)
	if not take_hr.ok:
		return Result.failure("take hr_director failed: %s" % take_hr.error)
	var add_hr := StateUpdaterClass.add_employee(state, 0, "hr_director", false)
	if not add_hr.ok:
		return Result.failure("add hr_director failed: %s" % add_hr.error)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	state.current_player_index = 0
	state.milestone_pool = ["first_hire_3"]
	_reset_round_state_for_ai_step(state)
	var setup_sync := _sync_initial_checkpoint_to_current_state(engine)
	if not setup_sync.ok:
		return setup_sync
	var first := engine.execute_command(Command.create("recruit", 0, {"employee_type": "recruiting_girl"}))
	if not first.ok:
		return Result.failure("setup first recruit failed: %s" % first.error)
	var second := engine.execute_command(Command.create("recruit", 0, {"employee_type": "trainer"}))
	if not second.ok:
		return Result.failure("setup second recruit failed: %s" % second.error)
	state = engine.get_state()
	if _round_state_player_count(state.round_state, "recruit_used", 0) != 2:
		return Result.failure("setup should leave recruit_used at 2, round_state=%s" % str(state.round_state))
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if milestones.has("first_hire_3"):
		return Result.failure("first_hire_3 should not be claimed before the third recruit, milestones=%s" % str(milestones))
	var final_sync := _sync_initial_checkpoint_to_current_state(engine)
	if not final_sync.ok:
		return final_sync
	return Result.success(engine)

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
	return _scenario_dinner_preview_values_cash_threshold_milestone(seed_val, "first_have_20", 10, 0.0)

static func _scenario_dinner_preview_values_cash_100_milestone(seed_val: int) -> Result:
	return _scenario_dinner_preview_values_cash_threshold_milestone(seed_val, "first_have_100", 90, 15.0)

static func _scenario_dinner_preview_values_cash_threshold_milestone(seed_val: int, milestone_id: String, starting_cash: int, minimum_value: float) -> Result:
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
	for pid in range(state.players.size()):
		state.players[pid]["reserve_cards"] = [{"type": 10, "cash": 20, "ceo_slots": 4}]
		state.players[pid]["reserve_card_selected"] = 0
		state.players[pid]["reserve_card_revealed"] = false
	var cash_set := _set_player_cash_by_transfer(state, 0, starting_cash)
	if not cash_set.ok:
		return cash_set
	state.players[0]["inventory"] = {}
	state.players[0]["milestones"] = []
	state.players[1]["inventory"] = {}
	state.rules["salary_cost"] = 5
	state.milestone_pool = [milestone_id]
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
		"produce_burger_reaches_%s" % milestone_id,
		[Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, burger_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(score.get("features", {}))
	if str(features.get("product_dinner_preview_source", "")) != "dinner_preview":
		return Result.failure("cash milestone scenario should use DinnerPreview: %s" % str(features))
	if not Array(features.get("product_dinner_preview_milestone_ids", [])).has(milestone_id):
		return Result.failure("expected DinnerPreview to expose %s cash milestone: %s" % [milestone_id, str(features)])
	if float(features.get("product_dinner_preview_milestone_value", 0.0)) <= minimum_value:
		return Result.failure("expected DinnerPreview %s cash milestone to add material value above %.1f: %s" % [milestone_id, minimum_value, str(features)])
	var bot = StrategyBotClass.new()
	var controller := BotControllerClass.new()
	var step := controller.step(engine, 0, bot, TimeBudget.start(80))
	if not step.ok:
		return Result.failure("%s cash milestone production step failed: %s" % [milestone_id, step.error])
	var trace: Dictionary = step.value
	if str(trace.get("action_id", "")) != "produce_food":
		return Result.failure("expected StrategyBot to produce burger for %s cash milestone, got %s" % [milestone_id, str(trace)])
	var params: Dictionary = Dictionary(trace.get("params", {}))
	if str(params.get("employee_type", "")) != "kitchen_trainee" or str(params.get("food_type", "")) != "burger":
		return Result.failure("expected kitchen_trainee burger production for %s cash milestone, got %s" % [milestone_id, str(trace)])
	var cash_before_dinner := int(Dictionary(engine.get_state().players[0]).get("cash", 0))
	var dinner := DinnertimeSettlementTestClass._advance_to_dinnertime(engine)
	if not dinner.ok:
		return dinner
	state = engine.get_state()
	var cash_after_dinner := int(Dictionary(state.players[0]).get("cash", 0))
	if cash_after_dinner <= cash_before_dinner:
		return Result.failure("expected Dinnertime sale to increase cash for %s, before=%d after=%d" % [milestone_id, cash_before_dinner, cash_after_dinner])
	var milestones: Array = Array(Dictionary(state.players[0]).get("milestones", []))
	if not milestones.has(milestone_id):
		return Result.failure("real Dinnertime sale should claim %s, milestones=%s" % [milestone_id, str(milestones)])
	if milestone_id == "first_have_20" and not bool(Dictionary(state.players[0]).get("can_peek_all_reserve_cards", false)):
		return Result.failure("first_have_20 should enable reserve card peek, player=%s" % str(state.players[0]))
	if milestone_id == "first_have_100":
		var player0: Dictionary = Dictionary(state.players[0])
		if not Array(player0.get("banned_employee_ids", [])).has("cfo"):
			return Result.failure("first_have_100 should ban cfo, player=%s" % str(player0))
		var cfo_start_round_val = player0.get("ceo_cfo_ability_start_round", null)
		if not (cfo_start_round_val is int):
			return Result.failure("first_have_100 should set ceo_cfo_ability_start_round, player=%s" % str(player0))
		var expected_start_round := int(state.round_number) + 1
		if int(cfo_start_round_val) != expected_start_round:
			return Result.failure("first_have_100 should make CEO/CFO income bonus start next round, got=%d expected=%d player=%s" % [int(cfo_start_round_val), expected_start_round, str(player0)])
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
		{"id": "first_billboard", "min": 20.0, "effect": "marketing_no_salary/marketing_permanent"},
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

static func _best_recruit_candidate(observation: ObservationState, seed_val: int, max_valid_per_action: int = 16) -> Result:
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
		{"max_valid_per_action": max_valid_per_action}
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

static func _full_base_recruit_pool() -> Dictionary:
	var out := {}
	if EmployeeRegistryClass.is_loaded():
		for employee_id in EmployeeRegistryClass.get_all_ids():
			var id := str(employee_id)
			if id.is_empty() or id == "ceo":
				continue
			out[id] = 1
		return out
	return _base_income_recruit_pool()

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

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out

static func _player_restaurant_count(state: GameState, player_id: int) -> int:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return 0
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return 0
	var restaurants_val = Dictionary(player_val).get("restaurants", [])
	if restaurants_val is Array:
		return Array(restaurants_val).size()
	return 0

static func _read_position_array(value) -> Array[int]:
	if value is Vector2i:
		var v2i: Vector2i = value
		return [v2i.x, v2i.y]
	if value is Vector2:
		var v2: Vector2 = value
		return [int(v2.x), int(v2.y)]
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return [int(arr[0]), int(arr[1])]
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y"):
			return [int(dict.get("x", 0)), int(dict.get("y", 0))]
	return []

static func _marketing_candidate_ids(candidates: Array) -> Array[String]:
	var out: Array[String] = []
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			continue
		var command: Command = macro.commands[0]
		if str(command.action_id) != "initiate_marketing":
			continue
		out.append("%s#%d" % [str(macro.id), int(command.params.get("board_number", 0))])
	return out

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
