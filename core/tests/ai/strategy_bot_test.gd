class_name StrategyBotTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyBoardAnalyzerClass = preload("res://core/ai/strategy/strategy_board_analyzer.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyCashPlannerClass = preload("res://core/ai/strategy/strategy_cash_planner.gd")
const StrategyDinnerPlannerClass = preload("res://core/ai/strategy/strategy_dinner_planner.gd")
const StrategyEmployeePlannerClass = preload("res://core/ai/strategy/strategy_employee_planner.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyMarketingPlannerClass = preload("res://core/ai/strategy/strategy_marketing_planner.gd")
const MarketingPressureAnalyzerClass = preload("res://core/ai/analysis/marketing_pressure_analyzer.gd")
const StrategyPhasePlannerClass = preload("res://core/ai/strategy/strategy_phase_planner.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyRecoveryPlannerClass = preload("res://core/ai/strategy/strategy_recovery_planner.gd")
const StrategyRecruitPlannerClass = preload("res://core/ai/strategy/strategy_recruit_planner.gd")
const StrategyRoutePlannerClass = preload("res://core/ai/strategy/strategy_route_planner.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const StrategySetupPlannerClass = preload("res://core/ai/strategy/strategy_setup_planner.gd")
const StrategyStructurePlannerClass = preload("res://core/ai/strategy/strategy_structure_planner.gd")
const StrategySupplyPlannerClass = preload("res://core/ai/strategy/strategy_supply_planner.gd")
const StrategySupportPlannerClass = preload("res://core/ai/strategy/strategy_support_planner.gd")
const StrategyTrainPlannerClass = preload("res://core/ai/strategy/strategy_train_planner.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const MarketingCampaignsTestClass = preload("res://core/tests/marketing_campaigns_test.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var first := _run_to_round_or_game_over(seed_val, 3)
	if not first.ok:
		return first
	var second := _run_to_round_or_game_over(seed_val, 3)
	if not second.ok:
		return second
	var first_actions: Array = first.value.get("actions", [])
	var second_actions: Array = second.value.get("actions", [])
	if str(first_actions) != str(second_actions):
		return Result.failure("StrategyBot should be deterministic for same seed")
	if not bool(first.value.get("saw_strategy_trace", false)):
		return Result.failure("StrategyBot should emit strategy trace metadata")
	var profile_load := _test_strategy_profile_loads_data_config()
	if not profile_load.ok:
		return profile_load
	var phase_planner := _test_phase_planner_classifies_strategy_context(seed_val)
	if not phase_planner.ok:
		return phase_planner
	var route_planner := _test_route_planner_classifies_income_readiness()
	if not route_planner.ok:
		return route_planner
	var recovery_planner := _test_recovery_planner_classifies_structural_responses()
	if not recovery_planner.ok:
		return recovery_planner
	var recruit_planner := _test_recruit_planner_classifies_desired_counts()
	if not recruit_planner.ok:
		return recruit_planner
	var marketing_upgrade_recruit := _test_recruit_planner_values_marketing_upgrade_recovery()
	if not marketing_upgrade_recruit.ok:
		return marketing_upgrade_recruit
	var train_planner := _test_train_planner_values_supply_upgrades()
	if not train_planner.ok:
		return train_planner
	var marketing_planner := _test_marketing_planner_values_supply_readiness()
	if not marketing_planner.ok:
		return marketing_planner
	var structure_planner := _test_structure_planner_values_marketing_supply_activation()
	if not structure_planner.ok:
		return structure_planner
	var structure_marketing_activation := _test_structure_score_activates_marketing_for_ready_supply()
	if not structure_marketing_activation.ok:
		return structure_marketing_activation
	var support_planner := _test_support_planner_values_price_and_waitress_routes()
	if not support_planner.ok:
		return support_planner
	var cash_planner := _test_cash_planner_values_no_demand_and_payday_fire()
	if not cash_planner.ok:
		return cash_planner
	var dinner_planner := _test_dinner_planner_values_food_preview(seed_val)
	if not dinner_planner.ok:
		return dinner_planner
	var dinner_drink_planner := _test_dinner_planner_values_drink_preview(seed_val)
	if not dinner_drink_planner.ok:
		return dinner_drink_planner
	var reserve_card_score := _test_reserve_card_score_prefers_strategy_capacity(seed_val)
	if not reserve_card_score.ok:
		return reserve_card_score
	var setup_turn_order := _test_setup_planner_values_turn_order()
	if not setup_turn_order.ok:
		return setup_turn_order
	var filter_case := _test_marketing_filter_discards_no_house_candidate()
	if not filter_case.ok:
		return filter_case
	var opening_pressure_filter := _test_marketing_filter_delays_opponent_pressure_until_income_started()
	if not opening_pressure_filter.ok:
		return opening_pressure_filter
	var marketing_score := _test_marketing_score_prefers_affected_serviceable_houses(seed_val)
	if not marketing_score.ok:
		return marketing_score
	var marketing_generation := _test_marketing_generation_prioritizes_ready_product(seed_val)
	if not marketing_generation.ok:
		return marketing_generation
	var marketing_generation_competition := _test_marketing_generation_discards_competitor_captured_candidates(seed_val)
	if not marketing_generation_competition.ok:
		return marketing_generation_competition
	var active_supply := _test_marketing_score_uses_active_supply_for_unstocked_product(seed_val)
	if not active_supply.ok:
		return active_supply
	var road_graph_marketing := _test_marketing_score_uses_source_road_graph(seed_val)
	if not road_graph_marketing.ok:
		return road_graph_marketing
	var competitor_marketing := _test_marketing_score_penalizes_competitor_sale_route(seed_val)
	if not competitor_marketing.ok:
		return competitor_marketing
	var future_route_marketing := _test_marketing_score_penalizes_restaurant_dominated_future_route(seed_val)
	if not future_route_marketing.ok:
		return future_route_marketing
	var opponent_gap_marketing := _test_marketing_score_values_opponent_capacity_gap(seed_val)
	if not opponent_gap_marketing.ok:
		return opponent_gap_marketing
	var marketing_preview := _test_marketing_score_uses_marketing_preview_for_capped_demand(seed_val)
	if not marketing_preview.ok:
		return marketing_preview
	var income_gap := _test_income_analyzer_detects_serviceable_inventory_gap(seed_val)
	if not income_gap.ok:
		return income_gap
	var competitive_income_gap := _test_income_analyzer_detects_competitive_inventory_gap(seed_val)
	if not competitive_income_gap.ok:
		return competitive_income_gap
	var recoverable_price_gap := _test_income_analyzer_detects_price_recoverable_demand(seed_val)
	if not recoverable_price_gap.ok:
		return recoverable_price_gap
	var unreachable_income_gap := _test_income_analyzer_uses_road_graph_for_unreachable_demand()
	if not unreachable_income_gap.ok:
		return unreachable_income_gap
	var pending_marketing_demand := _test_income_analyzer_counts_pending_marketing_demand(seed_val)
	if not pending_marketing_demand.ok:
		return pending_marketing_demand
	var recruit_roster := _test_recruit_score_penalizes_roster_saturation(seed_val)
	if not recruit_roster.ok:
		return recruit_roster
	var advanced_support_recruit := _test_recruit_score_delays_advanced_support_until_income_ready(seed_val)
	if not advanced_support_recruit.ok:
		return advanced_support_recruit
	var house_route_recruit := _test_recruit_score_values_house_placement_route(seed_val)
	if not house_route_recruit.ok:
		return house_route_recruit
	var house_route_train := _test_train_score_values_house_placement_route(seed_val)
	if not house_route_train.ok:
		return house_route_train
	var house_route_structure := _test_structure_score_values_reserve_new_business_developer(seed_val)
	if not house_route_structure.ok:
		return house_route_structure
	var marketing_supply_structure := _test_structure_score_keeps_food_supply_for_marketing_pipeline(seed_val)
	if not marketing_supply_structure.ok:
		return marketing_supply_structure
	var trainable_supply_generation := _test_candidate_generation_keeps_trainable_food_supply_available(seed_val)
	if not trainable_supply_generation.ok:
		return trainable_supply_generation
	var fridge_keep := _test_fridge_keep_prioritizes_serviceable_demand(seed_val)
	if not fridge_keep.ok:
		return fridge_keep
	var product_gap_score := _test_strategy_scoring_targets_current_product_gap(seed_val)
	if not product_gap_score.ok:
		return product_gap_score
	var product_amount_score := _test_strategy_scoring_values_supply_amount(seed_val)
	if not product_amount_score.ok:
		return product_amount_score
	var route_drinks_score := _test_strategy_scoring_values_route_drink_products(seed_val)
	if not route_drinks_score.ok:
		return route_drinks_score
	var pending_marketing_supply := _test_strategy_scoring_values_pending_marketing_supply(seed_val)
	if not pending_marketing_supply.ok:
		return pending_marketing_supply
	var product_overstock := _test_strategy_scoring_penalizes_product_overstock(seed_val)
	if not product_overstock.ok:
		return product_overstock
	var no_demand_food := _test_strategy_scoring_skips_no_demand_food_when_cash_unsafe(seed_val)
	if not no_demand_food.ok:
		return no_demand_food
	var no_demand_drinks := _test_strategy_scoring_skips_no_demand_drinks_when_cash_unsafe(seed_val)
	if not no_demand_drinks.ok:
		return no_demand_drinks
	var dinner_preview_food := _test_strategy_scoring_uses_dinner_preview_for_food_income(seed_val)
	if not dinner_preview_food.ok:
		return dinner_preview_food
	var dinner_preview_drink := _test_strategy_scoring_uses_dinner_preview_for_drink_income(seed_val)
	if not dinner_preview_drink.ok:
		return dinner_preview_drink
	var pricing_pipeline := _test_strategy_scoring_uses_pricing_pipeline_for_price_actions(seed_val)
	if not pricing_pipeline.ok:
		return pricing_pipeline
	var milestone_race := _test_strategy_scoring_values_key_milestone_race(seed_val)
	if not milestone_race.ok:
		return milestone_race
	var restaurant_placement := _test_restaurant_placement_prefers_near_public_demand(seed_val)
	if not restaurant_placement.ok:
		return restaurant_placement
	var restaurant_road_graph := _test_restaurant_placement_uses_source_road_graph(seed_val)
	if not restaurant_road_graph.ok:
		return restaurant_road_graph
	var restaurant_competition := _test_restaurant_placement_penalizes_competitor_dominated_houses(seed_val)
	if not restaurant_competition.ok:
		return restaurant_competition
	var restaurant_opening_contested := _test_initial_restaurant_placement_penalizes_contested_opening_lane()
	if not restaurant_opening_contested.ok:
		return restaurant_opening_contested
	var restaurant_opening_robustness := _test_initial_restaurant_placement_values_opening_robustness(seed_val)
	if not restaurant_opening_robustness.ok:
		return restaurant_opening_robustness
	var restaurant_opening_dominance := _test_initial_restaurant_placement_prefers_broader_opening_route()
	if not restaurant_opening_dominance.ok:
		return restaurant_opening_dominance
	var second_player_opening_route := _test_strategy_bot_opens_second_player_marketing_route()
	if not second_player_opening_route.ok:
		return second_player_opening_route
	var house_placement := _test_house_placement_prefers_near_owned_restaurant(seed_val)
	if not house_placement.ok:
		return house_placement
	var payday_fire := _test_payday_fire_prefers_low_income_employee(seed_val)
	if not payday_fire.ok:
		return payday_fire
	var payday_preview_fire := _test_payday_fire_uses_payday_preview_for_unresolved_shortfall(seed_val)
	if not payday_preview_fire.ok:
		return payday_preview_fire
	var payday_preview_other_player := _test_payday_fire_ignores_other_player_preview_shortfall(seed_val)
	if not payday_preview_other_player.ok:
		return payday_preview_other_player
	return Result.success({
		"steps": int(first.value.get("steps", 0)),
		"round": int(first.value.get("round", 0)),
		"phase": str(first.value.get("phase", "")),
	})

static func _run_to_round_or_game_over(seed_val: int, min_round: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)

	var controller := BotControllerClass.new()
	var bots := {
		0: StrategyBotClass.new(),
		1: StrategyBotClass.new(),
	}
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		return state != null and (int(state.round_number) >= min_round or str(state.phase) == DefsClass.PHASE_GAME_OVER)
	var run_result := controller.run_until(engine, bots, stop_condition, 720, 80)
	if not run_result.ok:
		return run_result

	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after StrategyBot run")
	if int(state.round_number) < min_round and str(state.phase) != DefsClass.PHASE_GAME_OVER:
		return Result.failure("expected StrategyBot to reach round %d or GameOver, got round=%d %s/%s" % [min_round, int(state.round_number), str(state.phase), str(state.sub_phase)])

	return Result.success({
		"steps": controller.last_trace.size(),
		"round": int(state.round_number),
		"phase": str(state.phase),
		"actions": _action_summary(controller.last_trace),
		"saw_strategy_trace": _saw_strategy_trace(controller.last_trace),
	})

static func _action_summary(trace: Array[Dictionary]) -> Array:
	var actions := []
	for item in trace:
		actions.append({
			"player_id": int(item.get("player_id", -1)),
			"action_id": str(item.get("action_id", "")),
			"params": Dictionary(item.get("params", {})).duplicate(true),
			"macro_action_id": str(item.get("macro_action_id", "")),
			"phase_before": str(item.get("phase_before", "")),
			"sub_phase_before": str(item.get("sub_phase_before", "")),
		})
	return actions

static func _saw_strategy_trace(trace: Array[Dictionary]) -> bool:
	for item in trace:
		var decision_trace: Dictionary = Dictionary(item.get("decision_trace", {}))
		if str(decision_trace.get("bot", "")) == "StrategyBot" and not str(decision_trace.get("strategy_profile", "")).is_empty():
			return true
	return false

static func _test_strategy_profile_loads_data_config() -> Result:
	var loaded = StrategyProfileClass.new()
	var load_read := loaded.load_from_file(StrategyProfileClass.DEFAULT_BASE_REVENUE_PATH)
	if not load_read.ok:
		return Result.failure("StrategyProfile should load default JSON config: %s" % load_read.error)
	if str(loaded.id) != "base_revenue_v1":
		return Result.failure("StrategyProfile loaded wrong id: %s" % loaded.id)
	if int(loaded.max_valid_per_action) != 12:
		return Result.failure("StrategyProfile loaded wrong max_valid_per_action: %d" % int(loaded.max_valid_per_action))
	if not bool(loaded.strict_marketing_must_affect_houses):
		return Result.failure("StrategyProfile loaded wrong strict marketing flag")
	if not is_equal_approx(float(loaded.action_weight("fire")), 25.0):
		return Result.failure("StrategyProfile loaded wrong fire action weight: %s" % str(loaded.action_weights))
	if not is_equal_approx(float(loaded.product_priority("burger")), 5.0):
		return Result.failure("StrategyProfile loaded wrong burger priority: %s" % str(loaded.product_priorities))
	if not is_equal_approx(float(loaded.milestone_priority("first_errand_boy")), 7.0):
		return Result.failure("StrategyProfile loaded wrong milestone priority: %s" % str(loaded.milestone_priorities))
	if not is_equal_approx(float(loaded.milestone_effect_weight("drinks_per_source_delta")), 1.0):
		return Result.failure("StrategyProfile loaded wrong milestone effect weight: %s" % str(loaded.milestone_effect_weights))
	if not is_equal_approx(float(loaded.role_bonus("strategy_first_procure_drink")), 6.0):
		return Result.failure("StrategyProfile loaded wrong role bonus: %s" % str(loaded.role_bonuses))
	var configured = StrategyProfileClass.new()
	configured.configure_base_revenue()
	if not is_equal_approx(float(configured.action_weight("choose_fridge_keep")), 120.0):
		return Result.failure("StrategyProfile.configure_base_revenue should use data config when available")
	var growth_path := StrategyProfileClass.resolve_profile_path("base_revenue_growth_v1")
	if growth_path != "res://data/bots/base_revenue_growth_v1.json":
		return Result.failure("StrategyProfile should resolve profile ids to data/bots JSON: %s" % growth_path)
	var growth = StrategyProfileClass.new()
	var growth_read := growth.configure("base_revenue_growth_v1")
	if not growth_read.ok:
		return Result.failure("StrategyProfile should load growth profile id: %s" % growth_read.error)
	if str(growth.id) != "base_revenue_growth_v1":
		return Result.failure("StrategyProfile loaded wrong growth id: %s" % growth.id)
	if int(growth.max_valid_per_action) != 16:
		return Result.failure("StrategyProfile loaded wrong growth max_valid_per_action: %d" % int(growth.max_valid_per_action))
	if not is_equal_approx(float(growth.action_weight("place_restaurant")), 82.0):
		return Result.failure("StrategyProfile loaded wrong growth place_restaurant weight: %s" % str(growth.action_weights))
	if not is_equal_approx(float(growth.milestone_priority("first_billboard")), 9.0):
		return Result.failure("StrategyProfile loaded wrong growth milestone priority: %s" % str(growth.milestone_priorities))
	var growth_json_read := _read_json_dict(growth_path)
	if not growth_json_read.ok:
		return growth_json_read
	var growth_json_role_bonuses: Dictionary = Dictionary(Dictionary(growth_json_read.value).get("role_bonuses", {}))
	if not growth_json_role_bonuses.has("income_no_drink_supply"):
		return Result.failure("StrategyProfile growth JSON should include income_no_drink_supply role bonus")
	if not is_equal_approx(float(growth.role_bonus("income_no_drink_supply")), float(growth_json_role_bonuses.get("income_no_drink_supply", 0.0))):
		return Result.failure("StrategyProfile loaded wrong growth role bonus: %s" % str(growth.role_bonuses))
	var bot = StrategyBotClass.new()
	var bot_read := bot.configure_profile("base_revenue_growth_v1")
	if not bot_read.ok:
		return Result.failure("StrategyBot should configure named profile: %s" % bot_read.error)
	if str(bot.profile.id) != "base_revenue_growth_v1":
		return Result.failure("StrategyBot configured wrong profile: %s" % str(bot.profile.id))
	return Result.success()

static func _read_json_dict(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("test JSON should be readable: %s" % path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return Result.failure("test JSON should parse as Dictionary: %s" % path)
	return Result.success(Dictionary(parsed))

static func _test_phase_planner_classifies_strategy_context(seed_val: int) -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var train_observation := _synthetic_income_observation()
	train_observation.phase = DefsClass.PHASE_WORKING
	train_observation.sub_phase = DefsClass.SUB_PHASE_TRAIN
	var train_context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_WORKING,
		DefsClass.SUB_PHASE_TRAIN,
		1,
		seed_val,
		[]
	)
	var train_plan: Dictionary = StrategyPhasePlannerClass.plan(train_observation, train_context, profile)
	if str(train_plan.get("id", "")) != "working_train_capacity":
		return Result.failure("StrategyPhasePlanner should classify Working/Train: %s" % str(train_plan))
	if str(train_plan.get("goal", "")) != "income_route":
		return Result.failure("StrategyPhasePlanner should mark Working/Train as income route: %s" % str(train_plan))
	if int(train_plan.get("max_valid_per_action", 0)) != 16:
		return Result.failure("StrategyPhasePlanner should expand Working/Train candidate budget to sixteen: %s" % str(train_plan))
	var train_search_hints: Dictionary = Dictionary(train_plan.get("search_hints", {}))
	if int(train_search_hints.get("beam_width", 0)) != 5:
		return Result.failure("Working/Train should widen beam search: %s" % str(train_search_hints))
	if int(train_search_hints.get("max_depth", 0)) != 3:
		return Result.failure("Working/Train should keep a depth-3 horizon: %s" % str(train_search_hints))
	if int(train_search_hints.get("top_k_per_node", 0)) != 4:
		return Result.failure("Working/Train should broaden per-node candidates: %s" % str(train_search_hints))
	if int(train_search_hints.get("max_candidates", 0)) != 8:
		return Result.failure("Working/Train should broaden OSLA candidates: %s" % str(train_search_hints))
	if int(train_search_hints.get("opponent_max_candidates", 0)) != 3:
		return Result.failure("Working/Train should keep opponent response breadth at three: %s" % str(train_search_hints))
	var train_search_options := StrategyPhasePlannerClass.build_search_options(train_observation, train_context, profile)
	if int(train_search_options.get("max_valid_per_action", 0)) != 16:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge train candidate budget sixteen: %s" % str(train_search_options))
	if int(train_search_options.get("beam_width", 0)) != 5:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge train beam width: %s" % str(train_search_options))

	var oob_observation := _synthetic_order_of_business_observation()
	var oob_context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_ORDER_OF_BUSINESS,
		"",
		1,
		seed_val,
		[]
	)
	var oob_plan: Dictionary = StrategyPhasePlannerClass.plan(oob_observation, oob_context, profile)
	if str(oob_plan.get("id", "")) != "order_of_business_tempo":
		return Result.failure("StrategyPhasePlanner should classify OrderOfBusiness tempo: %s" % str(oob_plan))
	if str(oob_plan.get("goal", "")) != "tempo":
		return Result.failure("StrategyPhasePlanner should mark OrderOfBusiness as tempo: %s" % str(oob_plan))
	var oob_search_hints: Dictionary = Dictionary(oob_plan.get("search_hints", {}))
	if int(oob_search_hints.get("opponent_response_horizon", 0)) != 2:
		return Result.failure("OrderOfBusiness should use a two-step opponent response horizon: %s" % str(oob_search_hints))
	var oob_search_options := StrategyPhasePlannerClass.build_search_options(oob_observation, oob_context, profile)
	if int(oob_search_options.get("opponent_response_horizon", 0)) != 2:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge OrderOfBusiness response horizon: %s" % str(oob_search_options))

	var reserve_observation := _synthetic_reserve_card_observation()
	var reserve_context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_SETUP,
		DefsClass.SUB_PHASE_RESERVE_CARDS,
		1,
		seed_val,
		[]
	)
	var reserve_plan: Dictionary = StrategyPhasePlannerClass.plan(reserve_observation, reserve_context, profile)
	if str(reserve_plan.get("id", "")) != "setup_reserve_cards":
		return Result.failure("StrategyPhasePlanner should classify Setup/ReserveCards: %s" % str(reserve_plan))
	if str(reserve_plan.get("goal", "")) != "foundation":
		return Result.failure("StrategyPhasePlanner should mark reserve cards as foundation: %s" % str(reserve_plan))

	var setup_restaurant_observation := _synthetic_reserve_card_observation()
	setup_restaurant_observation.sub_phase = ""
	var setup_restaurant_context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_SETUP,
		"",
		1,
		seed_val,
		[]
	)
	var setup_restaurant_plan: Dictionary = StrategyPhasePlannerClass.plan(setup_restaurant_observation, setup_restaurant_context, profile)
	if str(setup_restaurant_plan.get("id", "")) != "setup_restaurant":
		return Result.failure("StrategyPhasePlanner should classify Setup restaurant placement: %s" % str(setup_restaurant_plan))
	if int(setup_restaurant_plan.get("max_valid_per_action", 0)) < 64:
		return Result.failure("Setup restaurant placement should broaden candidate coverage: %s" % str(setup_restaurant_plan))
	var setup_restaurant_search_hints: Dictionary = Dictionary(setup_restaurant_plan.get("search_hints", {}))
	if int(setup_restaurant_search_hints.get("max_valid_per_action", 0)) < 64:
		return Result.failure("Setup restaurant placement should widen search candidate coverage: %s" % str(setup_restaurant_search_hints))
	if int(setup_restaurant_search_hints.get("beam_width", 0)) != 6:
		return Result.failure("Setup restaurant placement should widen beam search: %s" % str(setup_restaurant_search_hints))
	if int(setup_restaurant_search_hints.get("max_depth", 0)) != 2:
		return Result.failure("Setup restaurant placement should stay shallow: %s" % str(setup_restaurant_search_hints))
	if int(setup_restaurant_search_hints.get("max_candidates", 0)) != 10:
		return Result.failure("Setup restaurant placement should broaden OSLA candidates: %s" % str(setup_restaurant_search_hints))
	var setup_restaurant_search_options := StrategyPhasePlannerClass.build_search_options(setup_restaurant_observation, setup_restaurant_context, profile)
	if int(setup_restaurant_search_options.get("max_valid_per_action", 0)) < 64:
		return Result.failure("StrategyPhasePlanner.build_search_options should preserve setup restaurant candidate coverage: %s" % str(setup_restaurant_search_options))
	if int(setup_restaurant_search_options.get("beam_width", 0)) != 6:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge setup restaurant beam width: %s" % str(setup_restaurant_search_options))

	var growth_observation := _synthetic_house_growth_observation()
	growth_observation.phase = DefsClass.PHASE_WORKING
	growth_observation.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	var growth_context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_WORKING,
		DefsClass.SUB_PHASE_PLACE_HOUSES,
		1,
		seed_val,
		[]
	)
	var growth_plan: Dictionary = StrategyPhasePlannerClass.plan(growth_observation, growth_context, profile)
	if str(growth_plan.get("id", "")) != "working_place_houses_growth":
		return Result.failure("StrategyPhasePlanner should classify Working/PlaceHouses growth: %s" % str(growth_plan))
	var growth_search_hints: Dictionary = Dictionary(growth_plan.get("search_hints", {}))
	if int(growth_search_hints.get("beam_width", 0)) != 6:
		return Result.failure("Working/PlaceHouses should widen beam search: %s" % str(growth_search_hints))
	if int(growth_search_hints.get("max_depth", 0)) != 4:
		return Result.failure("Working/PlaceHouses should deepen the search horizon: %s" % str(growth_search_hints))
	if int(growth_search_hints.get("top_k_per_node", 0)) != 5:
		return Result.failure("Working/PlaceHouses should broaden per-node candidates: %s" % str(growth_search_hints))
	if int(growth_search_hints.get("max_candidates", 0)) != 10:
		return Result.failure("Working/PlaceHouses should broaden OSLA candidates: %s" % str(growth_search_hints))
	if int(growth_search_hints.get("opponent_max_candidates", 0)) != 4:
		return Result.failure("Working/PlaceHouses should widen opponent response breadth: %s" % str(growth_search_hints))
	if int(growth_search_hints.get("opponent_max_valid_per_action", 0)) != 4:
		return Result.failure("Working/PlaceHouses should widen opponent valid-action coverage: %s" % str(growth_search_hints))
	if int(growth_search_hints.get("max_valid_per_action", 0)) != 24:
		return Result.failure("Working/PlaceHouses should widen candidate coverage to twenty-four: %s" % str(growth_search_hints))
	var growth_search_options := StrategyPhasePlannerClass.build_search_options(growth_observation, growth_context, profile)
	if int(growth_search_options.get("max_valid_per_action", 0)) != 24:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge growth candidate coverage: %s" % str(growth_search_options))
	if int(growth_search_options.get("max_depth", 0)) != 4:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge the deeper growth horizon: %s" % str(growth_search_options))
	if int(growth_search_options.get("beam_width", 0)) != 6:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge growth beam width: %s" % str(growth_search_options))
	if int(growth_search_options.get("opponent_max_candidates", 0)) != 4:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge growth opponent breadth: %s" % str(growth_search_options))
	if int(growth_search_options.get("opponent_max_valid_per_action", 0)) != 4:
		return Result.failure("StrategyPhasePlanner.build_search_options should merge growth opponent valid-action coverage: %s" % str(growth_search_options))

	var payday_observation := _synthetic_payday_observation()
	var payday_context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_PAYDAY,
		"",
		1,
		seed_val,
		[]
	)
	var payday_plan: Dictionary = StrategyPhasePlannerClass.plan(payday_observation, payday_context, profile)
	if str(payday_plan.get("id", "")) != "payday_cash_safety":
		return Result.failure("StrategyPhasePlanner should classify Payday: %s" % str(payday_plan))
	if str(payday_plan.get("goal", "")) != "cash_safety":
		return Result.failure("StrategyPhasePlanner should mark Payday as cash safety: %s" % str(payday_plan))
	return Result.success()

static func _test_route_planner_classifies_income_readiness() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var missing_marketing := _synthetic_income_observation()
	var missing_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(missing_marketing, profile)
	var missing_plan: Dictionary = StrategyRoutePlannerClass.analyze(missing_marketing, missing_analysis, profile)
	if bool(missing_plan.get("stable_income_ready", true)):
		return Result.failure("StrategyRoutePlanner should require marketing for stable income: %s" % str(missing_plan))

	var price_opportunity := _synthetic_income_observation()
	price_opportunity.own_player["employees"] = ["burger_cook", "campaign_manager"]
	price_opportunity.own_player["cash"] = 0
	_set_observation_house_demand_count(price_opportunity, "house_near", "burger", 1)
	var price_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(price_opportunity, profile)
	var price_plan: Dictionary = StrategyRoutePlannerClass.analyze(price_opportunity, price_analysis, profile)
	if bool(price_plan.get("stable_income_ready", true)):
		return Result.failure("StrategyRoutePlanner should keep one-demand low-cash route below stable income: %s" % str(price_plan))
	if bool(price_plan.get("price_route_ready", false)):
		return Result.failure("StrategyRoutePlanner should not treat unsupported low-cash demand as price-ready before sale inventory: %s" % str(price_plan))
	price_opportunity.own_player["inventory"] = {"burger": 1}
	price_analysis = StrategyIncomeAnalyzerClass.analyze(price_opportunity, profile)
	price_plan = StrategyRoutePlannerClass.analyze(price_opportunity, price_analysis, profile)
	if not bool(price_plan.get("price_route_ready", false)):
		return Result.failure("StrategyRoutePlanner should detect price route once sale inventory exists: %s" % str(price_plan))
	if int(price_plan.get("serviceable_inventory_units", 0)) != 1:
		return Result.failure("StrategyRoutePlanner should expose serviceable sale inventory for price route: %s" % str(price_plan))

	var stable := _synthetic_income_observation()
	stable.own_player["employees"] = ["burger_cook", "campaign_manager"]
	stable.own_player["cash"] = 25
	var stable_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(stable, profile)
	var stable_plan: Dictionary = StrategyRoutePlannerClass.analyze(stable, stable_analysis, profile)
	if not bool(stable_plan.get("stable_income_ready", false)):
		return Result.failure("StrategyRoutePlanner should detect stable income route: %s" % str(stable_plan))
	if bool(stable_plan.get("house_growth_ready", true)):
		return Result.failure("StrategyRoutePlanner should delay house growth before cash/demand threshold: %s" % str(stable_plan))

	var unsupported_drink := _synthetic_income_observation()
	unsupported_drink.own_player["employees"] = ["burger_cook", "campaign_manager"]
	unsupported_drink.own_player["cash"] = 25
	_set_observation_house_demand_count(unsupported_drink, "house_near", "beer", 2)
	var unsupported_drink_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(unsupported_drink, profile)
	var unsupported_drink_plan: Dictionary = StrategyRoutePlannerClass.analyze(unsupported_drink, unsupported_drink_analysis, profile)
	if bool(unsupported_drink_plan.get("stable_income_ready", false)):
		return Result.failure("StrategyRoutePlanner should not call drink-only demand stable without drink supply: %s" % str(unsupported_drink_plan))
	if bool(unsupported_drink_plan.get("price_route_ready", false)):
		return Result.failure("StrategyRoutePlanner should not call unsupported drink demand price-ready: %s" % str(unsupported_drink_plan))
	if int(unsupported_drink_plan.get("supply_blocked_actionable_demand", 0)) <= 0:
		return Result.failure("StrategyRoutePlanner should expose blocked actionable drink demand: %s" % str(unsupported_drink_plan))

	var growth := _synthetic_house_growth_observation()
	growth.own_player["employees"] = ["burger_cook", "campaign_manager"]
	growth.own_player["cash"] = 45
	_set_observation_house_demand_count(growth, "house_near", "burger", 5)
	var growth_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(growth, profile)
	var growth_plan: Dictionary = StrategyRoutePlannerClass.analyze(growth, growth_analysis, profile)
	if not bool(growth_plan.get("house_growth_ready", false)):
		return Result.failure("StrategyRoutePlanner should detect growth-ready income route: %s" % str(growth_plan))

	var waitress_ready := _synthetic_income_observation()
	waitress_ready.own_player["employees"] = ["burger_cook", "campaign_manager", "pricing_manager"]
	var waitress_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(waitress_ready, profile)
	var waitress_plan: Dictionary = StrategyRoutePlannerClass.analyze(waitress_ready, waitress_analysis, profile)
	if not bool(waitress_plan.get("waitress_support_ready", false)):
		return Result.failure("StrategyRoutePlanner should detect waitress support from price role: %s" % str(waitress_plan))
	return Result.success()

static func _test_recruit_planner_classifies_desired_counts() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var food_missing := _synthetic_income_observation()
	food_missing.own_player["employees"] = ["campaign_manager"]
	var food_missing_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(food_missing, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(food_missing, "kitchen_trainee", food_missing_analysis, profile) != 1:
		return Result.failure("StrategyRecruitPlanner should want first kitchen trainee when food supply is missing")

	var food_owned := _synthetic_income_observation()
	food_owned.own_player["employees"] = ["burger_cook", "campaign_manager"]
	var food_owned_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(food_owned, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(food_owned, "kitchen_trainee", food_owned_analysis, profile) != 0:
		return Result.failure("StrategyRecruitPlanner should stop kitchen trainee when modest food gap is already covered")

	var high_food_demand := _synthetic_income_observation()
	high_food_demand.own_player["employees"] = ["burger_cook", "campaign_manager"]
	_set_observation_house_demand_count(high_food_demand, "house_near", "burger", 6)
	var high_food_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(high_food_demand, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(high_food_demand, "kitchen_trainee", high_food_analysis, profile) != 2:
		return Result.failure("StrategyRecruitPlanner should raise food recruit target when food demand is large")

	var marketing_missing := _synthetic_income_observation()
	marketing_missing.own_player["employees"] = ["burger_cook"]
	var marketing_missing_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(marketing_missing, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(marketing_missing, "marketing_trainee", marketing_missing_analysis, profile) != 1:
		return Result.failure("StrategyRecruitPlanner should want marketing trainee after restaurant exists")
	marketing_missing.own_player["employees"] = ["burger_cook", "campaign_manager"]
	var marketing_owned_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(marketing_missing, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(marketing_missing, "marketing_trainee", marketing_owned_analysis, profile) != 0:
		return Result.failure("StrategyRecruitPlanner should stop marketing trainee once campaign manager exists")
	var marketing_busy_recovery := _synthetic_income_observation()
	marketing_busy_recovery.own_player["cash"] = 40
	marketing_busy_recovery.own_player["employees"] = ["burger_cook"]
	marketing_busy_recovery.own_player["reserve_employees"] = []
	marketing_busy_recovery.own_player["busy_marketers"] = ["marketing_trainee"]
	var marketing_busy_recovery_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(marketing_busy_recovery, profile)
	marketing_busy_recovery_analysis["total_lost_to_competitor_demand"] = 2
	var marketing_capacity_plan: Dictionary = StrategyRecoveryPlannerClass.marketing_capacity_plan(marketing_busy_recovery, marketing_busy_recovery_analysis)
	if int(marketing_capacity_plan.get("desired_count", 0)) != 2:
		return Result.failure("StrategyRecoveryPlanner should request second marketing capacity when the only marketer is busy during recovery: %s" % str(marketing_capacity_plan))
	if StrategyRecruitPlannerClass.desired_recruit_count(marketing_busy_recovery, "marketing_trainee", marketing_busy_recovery_analysis, profile) != 2:
		return Result.failure("StrategyRecruitPlanner should allow second marketing trainee for recovery routes")
	var marketing_busy_roster: Dictionary = StrategyRecruitPlannerClass.roster_adjustment(marketing_busy_recovery, "marketing_trainee", marketing_busy_recovery_analysis, profile)
	if bool(marketing_busy_roster.get("saturated", true)):
		return Result.failure("StrategyRecruitPlanner should not treat one busy marketing trainee as saturated when recovery needs another: %s" % str(marketing_busy_roster))

	var no_drink_demand := _synthetic_drink_route_observation()
	no_drink_demand.own_player["employees"] = ["burger_cook", "campaign_manager"]
	_set_observation_house_demand_count(no_drink_demand, "house_near", "soda", 0)
	var no_drink_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(no_drink_demand, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(no_drink_demand, "errand_boy", no_drink_analysis, profile) != 0:
		return Result.failure("StrategyRecruitPlanner should not want errand_boy when there is no actionable drink demand")
	var no_drink_errand_macro := MacroAction.create(
		"recruit_errand_without_drink_demand",
		[Command.create("recruit", 0, {"employee_type": "errand_boy"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var no_drink_skip_macro := MacroAction.create(
		"skip_no_drink_recruit",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var no_drink_errand_score: Dictionary = StrategyScorerClass.score_macro(no_drink_demand, no_drink_errand_macro, profile)
	var no_drink_skip_score: Dictionary = StrategyScorerClass.score_macro(no_drink_demand, no_drink_skip_macro, profile)
	if float(no_drink_errand_score.get("score", 0.0)) >= float(no_drink_skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer skipping over errand_boy without actionable drink demand: errand=%s skip=%s" % [str(no_drink_errand_score), str(no_drink_skip_score)])
	var no_drink_features: Dictionary = Dictionary(no_drink_errand_score.get("features", {}))
	if int(no_drink_features.get("recruit_desired_count", -1)) != 0 or bool(no_drink_features.get("recruit_drink_has_actionable_demand", true)):
		return Result.failure("no-demand errand recruit should expose zero desired drink route: %s" % str(no_drink_features))
	var drink_demand := _synthetic_drink_route_observation()
	drink_demand.own_player["employees"] = ["burger_cook", "campaign_manager"]
	_set_observation_house_demand_count(drink_demand, "house_near", "soda", 2)
	var drink_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(drink_demand, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(drink_demand, "errand_boy", drink_analysis, profile) != 1:
		return Result.failure("StrategyRecruitPlanner should want errand_boy when drink demand exists")
	var low_runway_drink := _synthetic_drink_route_observation()
	low_runway_drink.own_player["employees"] = ["burger_cook", "pizza_cook"]
	low_runway_drink.own_player["cash"] = 10
	var low_runway_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(low_runway_drink, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(low_runway_drink, "truck_driver", low_runway_analysis, profile) != 0:
		return Result.failure("StrategyRecruitPlanner should delay paid drink recruit when current Payday runway is exhausted")
	var low_runway_truck_macro := MacroAction.create(
		"recruit_truck_driver_without_salary_runway",
		[Command.create("recruit", 0, {"employee_type": "truck_driver"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var low_runway_skip_macro := MacroAction.create(
		"skip_low_runway_recruit",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var low_runway_truck_score: Dictionary = StrategyScorerClass.score_macro(low_runway_drink, low_runway_truck_macro, profile)
	var low_runway_skip_score: Dictionary = StrategyScorerClass.score_macro(low_runway_drink, low_runway_skip_macro, profile)
	if float(low_runway_truck_score.get("score", 0.0)) >= float(low_runway_skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer skipping over paid recruit without salary runway: truck=%s skip=%s" % [str(low_runway_truck_score), str(low_runway_skip_score)])

	var price_opportunity := _synthetic_income_observation()
	price_opportunity.own_player["employees"] = ["burger_cook", "campaign_manager"]
	price_opportunity.own_player["cash"] = 0
	_set_observation_house_demand_count(price_opportunity, "house_near", "burger", 1)
	var price_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(price_opportunity, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(price_opportunity, "pricing_manager", price_analysis, profile) != 0:
		return Result.failure("StrategyRecruitPlanner should delay pricing support before sale inventory or stable income")
	price_opportunity.own_player["inventory"] = {"burger": 1}
	price_analysis = StrategyIncomeAnalyzerClass.analyze(price_opportunity, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(price_opportunity, "pricing_manager", price_analysis, profile) != 1:
		return Result.failure("StrategyRecruitPlanner should want pricing support for sale-ready price opportunity")
	if StrategyRecruitPlannerClass.desired_recruit_count(price_opportunity, "waitress", price_analysis, profile) != 0:
		return Result.failure("StrategyRecruitPlanner should still delay waitress before stable price-supported income")

	var covered_training := _synthetic_income_observation()
	covered_training.own_player["employees"] = ["burger_cook", "kitchen_trainee"]
	_set_observation_house_demand_count(covered_training, "house_near", "burger", 2)
	var covered_training_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(covered_training, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(covered_training, "trainer", covered_training_analysis, profile) != 0:
		return Result.failure("StrategyRecruitPlanner should delay trainer when owned food capacity already covers demand")

	var capacity_training := _synthetic_income_observation()
	capacity_training.own_player["employees"] = ["kitchen_trainee"]
	_set_observation_house_demand_count(capacity_training, "house_near", "burger", 4)
	var capacity_training_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(capacity_training, profile)
	if StrategyRecruitPlannerClass.desired_recruit_count(capacity_training, "trainer", capacity_training_analysis, profile) != 1:
		return Result.failure("StrategyRecruitPlanner should want trainer when training closes a real food capacity gap")

	var duplicate_trainer := _synthetic_income_observation()
	duplicate_trainer.own_player["employees"] = ["burger_cook", "trainer"]
	_set_observation_house_demand_count(duplicate_trainer, "house_near", "burger", 6)
	var duplicate_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(duplicate_trainer, profile)
	var duplicate_payload: Dictionary = StrategyRecruitPlannerClass.roster_adjustment(duplicate_trainer, "trainer", duplicate_analysis, profile)
	if not bool(duplicate_payload.get("saturated", false)):
		return Result.failure("StrategyRecruitPlanner should mark duplicate trainer saturated: %s" % str(duplicate_payload))
	if int(duplicate_payload.get("desired_count", -1)) != 1:
		return Result.failure("StrategyRecruitPlanner should keep trainer desired count at one: %s" % str(duplicate_payload))
	if float(duplicate_payload.get("adjustment", 0.0)) >= 0.0:
		return Result.failure("StrategyRecruitPlanner should penalize duplicate trainer: %s" % str(duplicate_payload))
	var duplicate_command := Command.create("recruit", 0, {"employee_type": "trainer"})
	var duplicate_action_payload: Dictionary = StrategyRecruitPlannerClass.evaluate_action(duplicate_trainer, duplicate_command, profile, duplicate_analysis)
	var duplicate_action_features: Dictionary = Dictionary(duplicate_action_payload.get("features", {}))
	if not bool(duplicate_action_features.get("recruit_roster_saturated", false)):
		return Result.failure("StrategyRecruitPlanner action should expose duplicate trainer saturation: %s" % str(duplicate_action_payload))
	if float(duplicate_action_features.get("recruit_roster_adjustment", 0.0)) >= 0.0:
		return Result.failure("StrategyRecruitPlanner action should expose duplicate trainer penalty: %s" % str(duplicate_action_payload))
	return Result.success()

static func _test_recruit_planner_values_marketing_upgrade_recovery() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["cash"] = 20
	observation.own_player["employees"] = ["kitchen_trainee", "marketing_trainee"]
	observation.own_player["reserve_employees"] = []
	observation.own_player["busy_marketers"] = []
	observation.employee_pool_public = {
		"trainer": 1,
		"campaign_manager": 1,
	}
	var income_analysis := {
		"total_public_demand": 1,
		"total_serviceable_demand": 0,
		"total_actionable_demand": 0,
		"total_lost_to_competitor_demand": 1,
		"total_price_recoverable_demand": 0,
		"total_inventory_gap": 0,
		"total_actionable_inventory_gap": 0,
		"products": {},
	}
	if not StrategyRecruitPlannerClass.marketing_upgrade_recovery_need(observation, income_analysis):
		return Result.failure("StrategyRecruitPlanner should detect marketing-upgrade recovery need when competitor captures current demand")
	if StrategyRecruitPlannerClass.desired_recruit_count(observation, "trainer", income_analysis, profile) != 1:
		return Result.failure("StrategyRecruitPlanner should want trainer when upgrading marketing can reopen a lost route")
	var roster_payload: Dictionary = StrategyRecruitPlannerClass.roster_adjustment(observation, "trainer", income_analysis, profile)
	if bool(roster_payload.get("saturated", true)):
		return Result.failure("StrategyRecruitPlanner should not saturate trainer when marketing upgrade recovery needs one: %s" % str(roster_payload))
	var trainer_macro := MacroAction.create(
		"recruit_trainer_for_marketing_upgrade_recovery",
		[Command.create("recruit", 0, {"employee_type": "trainer"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_marketing_upgrade_recovery",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var trainer_score: Dictionary = StrategyScorerClass.score_macro(observation, trainer_macro, profile, {"income_analysis": income_analysis})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile, {"income_analysis": income_analysis})
	if float(trainer_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer trainer over skip for marketing-upgrade recovery: trainer=%s skip=%s" % [str(trainer_score), str(skip_score)])
	var features: Dictionary = Dictionary(trainer_score.get("features", {}))
	if not bool(features.get("recruit_marketing_upgrade_needed", false)):
		return Result.failure("trainer recovery score should expose marketing upgrade need: %s" % str(features))
	if float(features.get("recruit_marketing_upgrade_value", 0.0)) <= 0.0:
		return Result.failure("trainer recovery score should expose positive marketing upgrade value: %s" % str(features))
	if str(features.get("recruit_marketing_upgrade_source_employee", "")) != "marketing_trainee":
		return Result.failure("trainer recovery score should expose marketing trainee as upgrade source: %s" % str(features))
	if str(features.get("recruit_marketing_upgrade_target_employee", "")) != "campaign_manager":
		return Result.failure("trainer recovery score should expose campaign manager as upgrade target: %s" % str(features))
	observation.own_player["employees"] = ["kitchen_trainee", "marketing_trainee", "campaign_manager"]
	if StrategyRecruitPlannerClass.marketing_upgrade_recovery_need(observation, income_analysis):
		return Result.failure("StrategyRecruitPlanner should stop marketing-upgrade recovery once advanced marketing is owned")
	return Result.success()

static func _test_recovery_planner_classifies_structural_responses() -> Result:
	var blocked_income := {
		"total_public_demand": 2,
		"total_serviceable_demand": 2,
		"total_actionable_demand": 0,
		"total_lost_to_competitor_demand": 1,
		"total_price_recoverable_demand": 1,
		"total_own_sourced_opponent_blocking_demand": 1,
		"products": {
			"pizza": {
				"lost_to_competitor_demand": 0,
				"price_recoverable_demand": 0,
				"own_sourced_opponent_blocking_demand": 1,
			},
		},
	}
	var recovery: Dictionary = StrategyRecoveryPlannerClass.analyze(blocked_income)
	var recovery_modes: Array = Array(recovery.get("modes", []))
	if not recovery_modes.has("customer_switch") or not recovery_modes.has("price_recovery") or not recovery_modes.has("product_switch"):
		return Result.failure("Recovery planner should expose customer, price, and product-switch modes: %s" % str(recovery))

	var customer_payload: Dictionary = StrategyRecoveryPlannerClass.marketing_response_value({
		"self_capture_houses": 1,
		"opponent_pressure_houses": 0,
		"can_future_supply_product": true,
	}, blocked_income)
	var customer_modes: Array = Array(customer_payload.get("modes", []))
	if float(customer_payload.get("value", 0.0)) <= 0.0 or not customer_modes.has("customer_switch"):
		return Result.failure("Recovery planner should value switching to an own-winnable customer route: %s" % str(customer_payload))

	var product_switch_payload: Dictionary = StrategyRecoveryPlannerClass.marketing_response_value({
		"self_capture_houses": 0,
		"opponent_pressure_houses": 1,
		"opponent_capacity_gap_prevented_sales": 1,
		"can_future_supply_product": true,
	}, blocked_income)
	var product_switch_modes: Array = Array(product_switch_payload.get("modes", []))
	if float(product_switch_payload.get("value", 0.0)) <= 0.0 or not product_switch_modes.has("product_switch"):
		return Result.failure("Recovery planner should value marketing a product that blocks opponent capacity: %s" % str(product_switch_payload))

	var price_payload: Dictionary = StrategyRecoveryPlannerClass.price_response_value({
		"action_delta": -1,
		"actionable_demand": 1,
		"recoverable_demand": 1,
		"estimated_sale_units": 1,
	}, blocked_income)
	var price_modes: Array = Array(price_payload.get("modes", []))
	if float(price_payload.get("value", 0.0)) <= 0.0 or not price_modes.has("price_recovery"):
		return Result.failure("Recovery planner should value a lower-price recovery action: %s" % str(price_payload))
	return Result.success()

static func _test_train_planner_values_supply_upgrades() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var food_observation := _synthetic_income_observation()
	_set_observation_house_demand_count(food_observation, "house_near", "burger", 6)
	var food_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(food_observation, profile)
	var food_payload: Dictionary = StrategyTrainPlannerClass.capacity_upgrade_value(food_observation, "burger_cook", "burger_chef", profile, food_analysis)
	if float(food_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategyTrainPlanner should value burger_cook -> burger_chef when burger demand exceeds cook capacity: %s" % str(food_payload))
	if int(Dictionary(food_payload.get("delta_units_by_product", {})).get("burger", 0)) <= 0:
		return Result.failure("StrategyTrainPlanner should expose burger delta units: %s" % str(food_payload))
	var food_train_command := Command.create("train", 0, {
		"from_employee": "burger_cook",
		"to_employee": "burger_chef",
	})
	var food_action_payload: Dictionary = StrategyTrainPlannerClass.evaluate_action(food_observation, food_train_command, profile, food_analysis)
	var food_action_features: Dictionary = Dictionary(food_action_payload.get("features", {}))
	if float(food_action_payload.get("value", 0.0)) <= float(food_payload.get("value", 0.0)):
		return Result.failure("StrategyTrainPlanner action value should include capacity upgrade and target value: %s" % str(food_action_payload))
	if int(Dictionary(food_action_features.get("train_capacity_upgrade_delta_units_by_product", {})).get("burger", 0)) <= 0:
		return Result.failure("StrategyTrainPlanner action features should expose capacity upgrade delta units: %s" % str(food_action_features))
	var no_upgrade: Dictionary = StrategyTrainPlannerClass.capacity_upgrade_value(food_observation, "burger_chef", "burger_cook", profile, food_analysis)
	if not is_equal_approx(float(no_upgrade.get("value", 0.0)), 0.0):
		return Result.failure("StrategyTrainPlanner should not value lower-capacity food training as upgrade: %s" % str(no_upgrade))

	var drink_observation := _synthetic_drink_route_observation()
	var route_command := Command.create("procure_drinks", 0, {
		"employee_type": "truck_driver",
		"restaurant_id": "rest_near",
		"route": [[3, 2], [4, 2]],
		"selected_sources": [[4, 2]],
	})
	var expected_by_product: Dictionary = StrategySupplyPlannerClass.expected_route_drinks_by_product(drink_observation, route_command)
	if int(expected_by_product.get("soda", 0)) != 2:
		return Result.failure("StrategySupplyPlanner should infer route drink product/units from selected sources: %s" % str(expected_by_product))
	var drink_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(drink_observation, profile)
	var drink_train_command := Command.create("train", 0, {
		"from_employee": "errand_boy",
		"to_employee": "cart_operator",
	})
	var drink_train_payload: Dictionary = StrategyTrainPlannerClass.evaluate_action(drink_observation, drink_train_command, profile, drink_analysis)
	var drink_train_features: Dictionary = Dictionary(drink_train_payload.get("features", {}))
	if not is_equal_approx(float(drink_train_features.get("train_drink_route_readiness_adjustment", -1.0)), 0.0):
		return Result.failure("StrategyTrainPlanner should allow drink route training when drink demand is actionable: %s" % str(drink_train_features))
	var no_drink_observation := _synthetic_drink_route_observation()
	_set_observation_house_demand_count(no_drink_observation, "house_near", "soda", 0)
	var no_drink_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(no_drink_observation, profile)
	var no_drink_train_payload: Dictionary = StrategyTrainPlannerClass.evaluate_action(no_drink_observation, drink_train_command, profile, no_drink_analysis)
	var no_drink_train_features: Dictionary = Dictionary(no_drink_train_payload.get("features", {}))
	if float(no_drink_train_features.get("train_drink_route_readiness_adjustment", 0.0)) > -100.0:
		return Result.failure("StrategyTrainPlanner should penalize drink route training without actionable drink demand: %s" % str(no_drink_train_features))
	if StrategySupplyPlannerClass.expected_food_units("burger_chef") != 8:
		return Result.failure("StrategySupplyPlanner should expose burger_chef production amount")
	return Result.success()

static func _test_marketing_planner_values_supply_readiness() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var command := Command.create("initiate_marketing", 0, {"product": "burger"})
	var affected_ids: Array[String] = ["house_near"]

	var no_supply := _synthetic_marketing_observation()
	no_supply.own_player["employees"] = ["campaign_manager"]
	no_supply.own_player["reserve_employees"] = []
	no_supply.own_player["inventory"] = {}
	var no_supply_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(no_supply, profile)
	var no_supply_payload: Dictionary = StrategyMarketingPlannerClass.evaluate(no_supply, command, affected_ids, profile, no_supply_analysis)
	var no_supply_features: Dictionary = Dictionary(no_supply_payload.get("features", {}))
	if bool(no_supply_features.get("marketing_can_supply_product", true)):
		return Result.failure("StrategyMarketingPlanner should not count missing active supply as ready: %s" % str(no_supply_features))
	if bool(no_supply_features.get("marketing_can_future_supply_product", true)):
		return Result.failure("StrategyMarketingPlanner should not count missing future supply as ready: %s" % str(no_supply_features))
	if int(no_supply_features.get("marketing_self_supply_blocked_houses", 0)) <= 0:
		return Result.failure("StrategyMarketingPlanner should classify unsupplied self marketing as supply-blocked: %s" % str(no_supply_features))
	if float(no_supply_features.get("marketing_supply_readiness_penalty", 0.0)) > -100.0:
		return Result.failure("StrategyMarketingPlanner should strongly penalize marketing that cannot be supplied: %s" % str(no_supply_features))

	var future_supply := _synthetic_marketing_observation()
	future_supply.own_player["employees"] = ["campaign_manager"]
	future_supply.own_player["reserve_employees"] = ["burger_cook"]
	future_supply.own_player["inventory"] = {}
	var future_supply_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(future_supply, profile)
	var future_supply_payload: Dictionary = StrategyMarketingPlannerClass.evaluate(future_supply, command, affected_ids, profile, future_supply_analysis)
	var future_supply_features: Dictionary = Dictionary(future_supply_payload.get("features", {}))
	if bool(future_supply_features.get("marketing_can_supply_product", true)):
		return Result.failure("StrategyMarketingPlanner should not count reserve supply as same-turn active supply: %s" % str(future_supply_features))
	if not bool(future_supply_features.get("marketing_can_future_supply_product", false)):
		return Result.failure("StrategyMarketingPlanner should count reserve cook as next-round supply: %s" % str(future_supply_features))
	if float(future_supply_payload.get("value", 0.0)) <= float(no_supply_payload.get("value", 0.0)):
		return Result.failure("StrategyMarketingPlanner should prefer next-round supply over no supply: future=%s none=%s" % [str(future_supply_payload), str(no_supply_payload)])

	var active_supply := _synthetic_marketing_observation()
	active_supply.own_player["employees"] = ["campaign_manager", "burger_cook"]
	active_supply.own_player["inventory"] = {}
	var active_supply_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(active_supply, profile)
	var active_supply_payload: Dictionary = StrategyMarketingPlannerClass.evaluate(active_supply, command, affected_ids, profile, active_supply_analysis)
	var active_supply_features: Dictionary = Dictionary(active_supply_payload.get("features", {}))
	if not bool(active_supply_features.get("marketing_can_supply_product", false)):
		return Result.failure("StrategyMarketingPlanner should count active cook as same-turn supply: %s" % str(active_supply_features))
	if float(active_supply_payload.get("value", 0.0)) <= float(future_supply_payload.get("value", 0.0)):
		return Result.failure("StrategyMarketingPlanner should prefer active supply over future-only supply: active=%s future=%s" % [str(active_supply_payload), str(future_supply_payload)])
	return Result.success()

static func _test_structure_planner_values_marketing_supply_activation() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var marketing_supply := _synthetic_income_observation()
	marketing_supply.phase = DefsClass.PHASE_RESTRUCTURING
	marketing_supply.sub_phase = ""
	marketing_supply.own_player["employees"] = ["campaign_manager"]
	marketing_supply.own_player["reserve_employees"] = ["kitchen_trainee"]
	marketing_supply.own_player["inventory"] = {}
	_set_observation_house_demand_count(marketing_supply, "house_near", "burger", 0)
	var marketing_supply_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(marketing_supply, profile)
	var marketing_supply_payload: Dictionary = StrategyStructurePlannerClass.activation_value(marketing_supply, "kitchen_trainee", profile, marketing_supply_analysis)
	if float(marketing_supply_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategyStructurePlanner should value active food supply for owned marketing pipeline: %s" % str(marketing_supply_payload))
	if not Array(marketing_supply_payload.get("marketing_supply_products", [])).has("burger"):
		return Result.failure("StrategyStructurePlanner should expose burger as marketing supply product: %s" % str(marketing_supply_payload))
	var marketing_supply_command := Command.create("set_company_structure_direct", 0, {"employee_id": "kitchen_trainee"})
	var marketing_supply_action_payload: Dictionary = StrategyStructurePlannerClass.evaluate_action(marketing_supply, marketing_supply_command, profile, marketing_supply_analysis)
	var marketing_supply_action_features: Dictionary = Dictionary(marketing_supply_action_payload.get("features", {}))
	if float(marketing_supply_action_features.get("structure_activation_value", 0.0)) <= 0.0:
		return Result.failure("StrategyStructurePlanner action should expose activation value: %s" % str(marketing_supply_action_payload))
	if not Array(marketing_supply_action_features.get("structure_marketing_supply_products", [])).has("burger"):
		return Result.failure("StrategyStructurePlanner action should expose marketing supply product: %s" % str(marketing_supply_action_payload))

	var active_supply := _synthetic_income_observation()
	active_supply.phase = DefsClass.PHASE_RESTRUCTURING
	active_supply.sub_phase = ""
	active_supply.own_player["employees"] = ["campaign_manager", "burger_cook"]
	active_supply.own_player["reserve_employees"] = ["kitchen_trainee"]
	active_supply.own_player["inventory"] = {}
	_set_observation_house_demand_count(active_supply, "house_near", "burger", 0)
	var active_supply_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(active_supply, profile)
	var active_supply_payload: Dictionary = StrategyStructurePlannerClass.activation_value(active_supply, "kitchen_trainee", profile, active_supply_analysis)
	if Array(active_supply_payload.get("marketing_supply_products", [])).has("burger"):
		return Result.failure("StrategyStructurePlanner should not mark marketing supply when active cook already covers burger: %s" % str(active_supply_payload))

	var current_gap := _synthetic_income_observation()
	current_gap.phase = DefsClass.PHASE_RESTRUCTURING
	current_gap.sub_phase = ""
	current_gap.own_player["employees"] = []
	current_gap.own_player["reserve_employees"] = ["kitchen_trainee"]
	current_gap.own_player["inventory"] = {}
	_set_observation_house_demand_count(current_gap, "house_near", "burger", 2)
	var current_gap_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(current_gap, profile)
	var current_gap_payload: Dictionary = StrategyStructurePlannerClass.activation_value(current_gap, "kitchen_trainee", profile, current_gap_analysis)
	if float(current_gap_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategyStructurePlanner should value active food supply for current inventory gap: %s" % str(current_gap_payload))
	if not Array(current_gap_payload.get("products", [])).has("burger"):
		return Result.failure("StrategyStructurePlanner should expose burger as activated product: %s" % str(current_gap_payload))
	return Result.success()

static func _test_structure_score_activates_marketing_for_ready_supply() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var ready := _synthetic_income_observation()
	ready.phase = DefsClass.PHASE_RESTRUCTURING
	ready.sub_phase = ""
	ready.own_player["cash"] = 0
	ready.own_player["employees"] = ["kitchen_trainee"]
	ready.own_player["reserve_employees"] = ["campaign_manager", "pricing_manager"]
	ready.own_player["inventory"] = {}
	_set_observation_house_demand_count(ready, "house_near", "burger", 0)
	var ready_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(ready, profile)
	var campaign_activation: Dictionary = StrategyStructurePlannerClass.activation_value(ready, "campaign_manager", profile, ready_analysis)
	if float(campaign_activation.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategyStructurePlanner should value activating marketing with active supply route: %s" % str(campaign_activation))
	if not Array(campaign_activation.get("marketing_activation_products", [])).has("burger"):
		return Result.failure("StrategyStructurePlanner should expose burger as marketing activation product: %s" % str(campaign_activation))
	var recovery_ready := _synthetic_income_observation()
	recovery_ready.phase = DefsClass.PHASE_RESTRUCTURING
	recovery_ready.sub_phase = ""
	recovery_ready.own_player["employees"] = ["burger_cook"]
	recovery_ready.own_player["reserve_employees"] = ["marketing_trainee"]
	recovery_ready.own_player["inventory"] = {"burger": 1}
	var recovery_ready_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(recovery_ready, profile)
	recovery_ready_analysis["total_lost_to_competitor_demand"] = 2
	var recovery_activation: Dictionary = StrategyStructurePlannerClass.activation_value(recovery_ready, "marketing_trainee", profile, recovery_ready_analysis)
	if not Array(recovery_activation.get("marketing_activation_reasons", [])).has("recovery_customer_switch"):
		return Result.failure("StrategyStructurePlanner should expose customer-switch recovery as a marketing activation reason: %s" % str(recovery_activation))
	var campaign_command := Command.create("set_company_structure_direct", 0, {"employee_id": "campaign_manager"})
	var pricing_command := Command.create("set_company_structure_direct", 0, {"employee_id": "pricing_manager"})
	var campaign_payload: Dictionary = StrategyStructurePlannerClass.evaluate_action(ready, campaign_command, profile, ready_analysis)
	var pricing_payload: Dictionary = StrategyStructurePlannerClass.evaluate_action(ready, pricing_command, profile, ready_analysis)
	if float(campaign_payload.get("value", 0.0)) <= float(pricing_payload.get("value", 0.0)):
		return Result.failure("StrategyStructurePlanner should activate marketing before pricing when no demand route exists: campaign=%s pricing=%s" % [str(campaign_payload), str(pricing_payload)])
	var campaign_features: Dictionary = Dictionary(campaign_payload.get("features", {}))
	if float(campaign_features.get("structure_marketing_activation_value", 0.0)) <= 0.0:
		return Result.failure("StrategyStructurePlanner action should expose marketing activation value: %s" % str(campaign_payload))

	var no_supply := _synthetic_income_observation()
	no_supply.phase = DefsClass.PHASE_RESTRUCTURING
	no_supply.sub_phase = ""
	no_supply.own_player["employees"] = []
	no_supply.own_player["reserve_employees"] = ["campaign_manager"]
	no_supply.own_player["inventory"] = {}
	_set_observation_house_demand_count(no_supply, "house_near", "burger", 0)
	var no_supply_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(no_supply, profile)
	var no_supply_activation: Dictionary = StrategyStructurePlannerClass.activation_value(no_supply, "campaign_manager", profile, no_supply_analysis)
	if float(no_supply_activation.get("value", 0.0)) > 0.0:
		return Result.failure("StrategyStructurePlanner should not value marketing activation without active supply or inventory: %s" % str(no_supply_activation))

	var active_marketing := _synthetic_income_observation()
	active_marketing.phase = DefsClass.PHASE_RESTRUCTURING
	active_marketing.sub_phase = ""
	active_marketing.own_player["employees"] = ["kitchen_trainee", "campaign_manager"]
	active_marketing.own_player["reserve_employees"] = ["marketing_trainee"]
	active_marketing.own_player["inventory"] = {}
	_set_observation_house_demand_count(active_marketing, "house_near", "burger", 0)
	var active_marketing_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(active_marketing, profile)
	var duplicate_activation: Dictionary = StrategyStructurePlannerClass.activation_value(active_marketing, "marketing_trainee", profile, active_marketing_analysis)
	if float(duplicate_activation.get("value", 0.0)) > 0.0:
		return Result.failure("StrategyStructurePlanner should not add marketing activation when marketing is already active: %s" % str(duplicate_activation))
	return Result.success()

static func _test_support_planner_values_price_and_waitress_routes() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var no_demand := _synthetic_income_observation()
	no_demand.milestone_pool_public = ["first_lower_prices", "first_waitress"]
	_set_observation_house_demand_count(no_demand, "house_near", "burger", 0)
	var missing_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(no_demand, profile)
	var missing_price_payload: Dictionary = StrategySupportPlannerClass.price_employee_route_value(no_demand, "pricing_manager", missing_analysis)
	if not is_equal_approx(float(missing_price_payload.get("value", 0.0)), 0.0):
		return Result.failure("StrategySupportPlanner should delay price support until serviceable demand exists: %s" % str(missing_price_payload))

	var unsupported_drink := _synthetic_income_observation()
	unsupported_drink.own_player["employees"] = ["burger_cook", "campaign_manager"]
	unsupported_drink.own_player["cash"] = 25
	unsupported_drink.milestone_pool_public = ["first_lower_prices", "first_waitress"]
	_set_observation_house_demand_count(unsupported_drink, "house_near", "beer", 2)
	var unsupported_drink_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(unsupported_drink, profile)
	var unsupported_drink_price_payload: Dictionary = StrategySupportPlannerClass.price_employee_route_value(unsupported_drink, "pricing_manager", unsupported_drink_analysis)
	if not is_equal_approx(float(unsupported_drink_price_payload.get("value", 0.0)), 0.0):
		return Result.failure("StrategySupportPlanner should not value pricing support for unsupported drink-only demand: %s" % str(unsupported_drink_price_payload))

	var price_opportunity := _synthetic_income_observation()
	price_opportunity.own_player["employees"] = ["burger_cook", "campaign_manager"]
	price_opportunity.own_player["cash"] = 0
	price_opportunity.own_player["inventory"] = {"burger": 1}
	price_opportunity.milestone_pool_public = ["first_lower_prices", "first_waitress"]
	_set_observation_house_demand_count(price_opportunity, "house_near", "burger", 1)
	var opportunity_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(price_opportunity, profile)
	var opportunity_price_payload: Dictionary = StrategySupportPlannerClass.price_employee_route_value(price_opportunity, "pricing_manager", opportunity_analysis)
	if float(opportunity_price_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategySupportPlanner should value one serviceable price opportunity: %s" % str(opportunity_price_payload))

	var stable := _synthetic_income_observation()
	stable.own_player["employees"] = ["burger_cook", "campaign_manager"]
	stable.own_player["cash"] = 25
	stable.own_player["inventory"] = {"burger": 1}
	stable.milestone_pool_public = ["first_lower_prices", "first_waitress"]
	var stable_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(stable, profile)
	var price_payload: Dictionary = StrategySupportPlannerClass.price_employee_route_value(stable, "pricing_manager", stable_analysis)
	if float(price_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategySupportPlanner should value pricing manager once stable income route is ready: %s" % str(price_payload))
	if int(price_payload.get("serviceable_demand", 0)) < 2:
		return Result.failure("StrategySupportPlanner price route should expose serviceable demand: %s" % str(price_payload))
	if int(price_payload.get("estimated_sale_units", 0)) != 1:
		return Result.failure("StrategySupportPlanner price route should cap estimated sale units by inventory: %s" % str(price_payload))
	if not bool(price_payload.get("first_lower_prices_available", false)):
		return Result.failure("StrategySupportPlanner price route should expose first_lower_prices availability: %s" % str(price_payload))

	var unsupported_waitress_payload: Dictionary = StrategySupportPlannerClass.waitress_route_value(stable, "waitress", profile, stable_analysis)
	if not is_equal_approx(float(unsupported_waitress_payload.get("value", 0.0)), 0.0):
		return Result.failure("StrategySupportPlanner should delay waitress until price support is ready: %s" % str(unsupported_waitress_payload))

	var waitress_ready := _synthetic_income_observation()
	waitress_ready.rules_public = {"waitress_tips": 4}
	waitress_ready.own_player["employees"] = ["burger_cook", "campaign_manager", "pricing_manager"]
	waitress_ready.own_player["cash"] = 25
	waitress_ready.own_player["inventory"] = {"burger": 2}
	waitress_ready.own_player["milestones"] = []
	waitress_ready.milestone_pool_public = ["first_waitress"]
	var waitress_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(waitress_ready, profile)
	var waitress_payload: Dictionary = StrategySupportPlannerClass.waitress_route_value(waitress_ready, "waitress", profile, waitress_analysis)
	if float(waitress_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategySupportPlanner should value waitress after stable income and price support are ready: %s" % str(waitress_payload))
	if int(waitress_payload.get("tips", 0)) != 4:
		return Result.failure("StrategySupportPlanner waitress route should read current waitress tips: %s" % str(waitress_payload))
	if not bool(waitress_payload.get("first_waitress_available", false)):
		return Result.failure("StrategySupportPlanner waitress route should expose first_waitress availability: %s" % str(waitress_payload))
	if float(waitress_payload.get("first_waitress_value", 0.0)) <= 0.0:
		return Result.failure("StrategySupportPlanner waitress route should expose first_waitress milestone value: %s" % str(waitress_payload))

	var price_command := Command.create("set_price", 0, {})
	var price_action_observation := _synthetic_income_observation()
	price_action_observation.rules_public = {"base_unit_price": 10}
	price_action_observation.own_player["inventory"] = {"burger": 1}
	price_action_observation.round_state_public = {
		"price_modifiers": {
			0: {"existing_discount": -2},
		},
	}
	var action_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(price_action_observation, profile)
	var action_payload: Dictionary = StrategySupportPlannerClass.price_action_value(price_action_observation, price_command, action_analysis)
	if str(action_payload.get("source", "")) != "observation":
		return Result.failure("StrategySupportPlanner fallback price action should mark observation source: %s" % str(action_payload))
	if int(action_payload.get("current_unit_price", 0)) != 8:
		return Result.failure("StrategySupportPlanner fallback price action should include round price modifiers: %s" % str(action_payload))
	if int(action_payload.get("action_delta", 0)) != -1:
		return Result.failure("StrategySupportPlanner set_price should expose -1 action delta: %s" % str(action_payload))
	if int(action_payload.get("estimated_sale_units", 0)) != 1:
		return Result.failure("StrategySupportPlanner price action should cap estimated sales by inventory: %s" % str(action_payload))
	var action_eval_payload: Dictionary = StrategySupportPlannerClass.evaluate_price_action(price_action_observation, price_command, action_analysis)
	var action_eval_features: Dictionary = Dictionary(action_eval_payload.get("features", {}))
	if str(action_eval_features.get("price_source", "")) != "observation":
		return Result.failure("StrategySupportPlanner price action eval should expose observation source: %s" % str(action_eval_payload))
	if int(action_eval_features.get("price_current_unit_price", 0)) != 8:
		return Result.failure("StrategySupportPlanner price action eval should expose current unit price: %s" % str(action_eval_payload))
	if int(action_eval_features.get("price_action_delta", 0)) != -1:
		return Result.failure("StrategySupportPlanner price action eval should expose action delta: %s" % str(action_eval_payload))
	return Result.success()

static func _test_cash_planner_values_no_demand_and_payday_fire() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var no_demand := _synthetic_income_observation()
	no_demand.rules_public = {"salary_cost": 5}
	no_demand.own_player["cash"] = 0
	no_demand.own_player["inventory"] = {}
	_set_observation_house_demand_count(no_demand, "house_near", "burger", 0)
	var food_command := Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "burger"})
	var no_demand_features := {
		"product_public_demand": 0,
		"product_serviceable_demand": 0,
		"product_inventory_gap": 0,
		"product_inventory_units": 0,
	}
	var no_demand_payload: Dictionary = StrategyCashPlannerClass.no_demand_food_cash_safety_value(no_demand, food_command, no_demand_features)
	if float(no_demand_payload.get("value", 0.0)) >= 0.0:
		return Result.failure("StrategyCashPlanner should penalize no-demand food production when cash cannot cover salary: %s" % str(no_demand_payload))
	var no_demand_payload_features: Dictionary = Dictionary(no_demand_payload.get("features", {}))
	if float(no_demand_payload_features.get("product_no_demand_cash_safety_penalty", 0.0)) >= 0.0:
		return Result.failure("StrategyCashPlanner should expose no-demand cash safety penalty feature: %s" % str(no_demand_payload))

	var safe_cash := _synthetic_income_observation()
	safe_cash.rules_public = {"salary_cost": 5}
	safe_cash.own_player["cash"] = 5
	_set_observation_house_demand_count(safe_cash, "house_near", "burger", 0)
	var safe_payload: Dictionary = StrategyCashPlannerClass.no_demand_food_cash_safety_value(safe_cash, food_command, no_demand_features)
	if not is_equal_approx(float(safe_payload.get("value", 0.0)), 0.0):
		return Result.failure("StrategyCashPlanner should not penalize no-demand food when cash covers salary: %s" % str(safe_payload))

	var payday := _synthetic_payday_observation()
	var payday_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(payday, profile)
	var cfo_payload: Dictionary = StrategyCashPlannerClass.fire_value(
		payday,
		Command.create("fire", 0, {"employee_id": "cfo", "location": "active"}),
		profile,
		payday_analysis
	)
	var burger_payload: Dictionary = StrategyCashPlannerClass.fire_value(
		payday,
		Command.create("fire", 0, {"employee_id": "burger_cook", "location": "active"}),
		profile,
		payday_analysis
	)
	if float(cfo_payload.get("value", 0.0)) <= float(burger_payload.get("value", 0.0)):
		return Result.failure("StrategyCashPlanner should prefer firing lower income value employee under payday shortfall: cfo=%s burger=%s" % [str(cfo_payload), str(burger_payload)])
	var fire_features: Dictionary = Dictionary(cfo_payload.get("features", {}))
	if int(fire_features.get("fire_payday_shortfall", 0)) <= 0:
		return Result.failure("StrategyCashPlanner fire payload should expose payday shortfall: %s" % str(cfo_payload))
	if int(fire_features.get("fire_effective_salary_relief", 0)) <= 0:
		return Result.failure("StrategyCashPlanner fire payload should expose effective salary relief: %s" % str(cfo_payload))
	if float(fire_features.get("fire_value", 0.0)) <= 0.0:
		return Result.failure("StrategyCashPlanner fire payload should expose base fire value: %s" % str(cfo_payload))
	return Result.success()

static func _test_dinner_planner_values_food_preview(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "burger"}])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.players[0]["cash"] = 0
	state.players[0]["inventory"] = {}
	state.players[1]["inventory"] = {"burger": 1}
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_burger_produced"]
	var take := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take.ok:
		return Result.failure("dinner planner test take kitchen_trainee failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "kitchen_trainee", false)
	if not add.ok:
		return Result.failure("dinner planner test add kitchen_trainee failed: %s" % add.error)
	RoadGraphCacheClass.invalidate_road_graph(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var command := Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "burger"})
	var preview_features := {
		"product_public_demand": 1,
	}
	var no_source_payload: Dictionary = StrategyDinnerPlannerClass.supply_preview_value(observation_read.value, command, profile, preview_features)
	if not is_equal_approx(float(no_source_payload.get("value", 0.0)), 0.0):
		return Result.failure("StrategyDinnerPlanner should skip preview without source_engine: %s" % str(no_source_payload))
	if not Dictionary(no_source_payload.get("features", {})).is_empty():
		return Result.failure("StrategyDinnerPlanner should not emit preview features without source_engine: %s" % str(no_source_payload))

	var preview_payload: Dictionary = StrategyDinnerPlannerClass.supply_preview_value(observation_read.value, command, profile, preview_features, {"source_engine": engine})
	var features: Dictionary = Dictionary(preview_payload.get("features", {}))
	if str(features.get("product_dinner_preview_source", "")) != "dinner_preview":
		return Result.failure("StrategyDinnerPlanner should use DinnerPreview when source_engine is available: %s" % str(preview_payload))
	if int(features.get("product_dinner_preview_income", -1)) != 0:
		return Result.failure("StrategyDinnerPlanner should expose zero contested preview income: %s" % str(preview_payload))
	if float(features.get("product_dinner_preview_no_income_penalty", 0.0)) >= 0.0:
		return Result.failure("StrategyDinnerPlanner should expose zero-income cash safety penalty: %s" % str(preview_payload))
	if float(preview_payload.get("value", 0.0)) >= 0.0:
		return Result.failure("StrategyDinnerPlanner should penalize contested zero-income production while cash is unsafe: %s" % str(preview_payload))
	return Result.success()

static func _test_dinner_planner_values_drink_preview(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "beer"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.current_player_index = 0
	state.players[0]["cash"] = 0
	state.players[0]["inventory"] = {}
	state.players[1]["inventory"] = {}
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_errand_boy"]
	var take := StateUpdaterClass.take_from_pool(state, "errand_boy", 1)
	if not take.ok:
		return Result.failure("dinner planner drink test take errand_boy failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "errand_boy", false)
	if not add.ok:
		return Result.failure("dinner planner drink test add errand_boy failed: %s" % add.error)
	RoadGraphCacheClass.invalidate_road_graph(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var command := Command.create("procure_drinks", 0, {"employee_type": "errand_boy", "drink_type": "beer"})
	var preview_features := {
		"product_public_demand": 1,
	}
	var preview_payload: Dictionary = StrategyDinnerPlannerClass.supply_preview_value(observation_read.value, command, profile, preview_features, {"source_engine": engine})
	var features: Dictionary = Dictionary(preview_payload.get("features", {}))
	if str(features.get("product_dinner_preview_source", "")) != "dinner_preview":
		return Result.failure("StrategyDinnerPlanner should use DinnerPreview for procure_drinks when source_engine is available: %s" % str(preview_payload))
	if int(features.get("product_dinner_preview_income", -1)) != 0:
		return Result.failure("incomplete house order drink procurement should preview zero income: %s" % str(preview_payload))
	if float(features.get("product_dinner_preview_no_income_penalty", 0.0)) >= 0.0:
		return Result.failure("unsafe zero-income drink procurement should expose DinnerPreview penalty: %s" % str(preview_payload))
	if Array(features.get("product_dinner_preview_milestone_ids", [])).has("first_errand_boy"):
		return Result.failure("DinnerPreview should not double count immediate procure_drinks milestone: %s" % str(preview_payload))
	if float(preview_payload.get("value", 0.0)) >= 0.0:
		return Result.failure("StrategyDinnerPlanner should penalize incomplete-order drink procurement while cash is unsafe: %s" % str(preview_payload))
	return Result.success()

static func _test_reserve_card_score_prefers_strategy_capacity(seed_val: int) -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_reserve_card_observation()
	var low_payload: Dictionary = StrategySetupPlannerClass.reserve_card_value(observation, {"selected_index": 0})
	var high_payload: Dictionary = StrategySetupPlannerClass.reserve_card_value(observation, {"selected_index": 2})
	if float(high_payload.get("value", 0.0)) <= float(low_payload.get("value", 0.0)):
		return Result.failure("StrategySetupPlanner should prefer reserve card with stronger CEO capacity: high=%s low=%s" % [str(high_payload), str(low_payload)])
	if int(high_payload.get("ceo_slots", 0)) != 4:
		return Result.failure("StrategySetupPlanner should expose reserve card CEO slots: %s" % str(high_payload))
	if int(high_payload.get("cash", 0)) != 150:
		return Result.failure("StrategySetupPlanner should expose reserve card cash: %s" % str(high_payload))
	var high_action_payload: Dictionary = StrategySetupPlannerClass.evaluate_action(observation, Command.create("select_reserve_card", 0, {"selected_index": 2}))
	var high_action_features: Dictionary = Dictionary(high_action_payload.get("features", {}))
	if int(high_action_features.get("reserve_card_ceo_slots", 0)) != 4:
		return Result.failure("StrategySetupPlanner reserve action should expose CEO slots: %s" % str(high_action_payload))
	if int(high_action_features.get("reserve_card_cash", 0)) != 150:
		return Result.failure("StrategySetupPlanner reserve action should expose cash: %s" % str(high_action_payload))
	var invalid_payload: Dictionary = StrategySetupPlannerClass.reserve_card_value(observation, {"selected_index": 99})
	if bool(invalid_payload.get("valid", true)):
		return Result.failure("StrategySetupPlanner should mark out-of-range reserve card invalid: %s" % str(invalid_payload))
	if float(invalid_payload.get("value", 0.0)) >= 0.0:
		return Result.failure("StrategySetupPlanner should penalize invalid reserve card selection: %s" % str(invalid_payload))
	var low_macro := MacroAction.create(
		"reserve_card_0",
		[Command.create("select_reserve_card", 0, {"selected_index": 0})],
		0.0,
		["setup", "reserve"],
		{}
	)
	var high_macro := MacroAction.create(
		"reserve_card_2",
		[Command.create("select_reserve_card", 0, {"selected_index": 2})],
		0.0,
		["setup", "reserve"],
		{}
	)
	var low_score: Dictionary = StrategyScorerClass.score_macro(observation, low_macro, profile)
	var high_score: Dictionary = StrategyScorerClass.score_macro(observation, high_macro, profile)
	if float(high_score.get("score", 0.0)) <= float(low_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer reserve card with stronger CEO capacity: high=%s low=%s" % [str(high_score), str(low_score)])
	var features: Dictionary = Dictionary(high_score.get("features", {}))
	if int(features.get("reserve_card_ceo_slots", 0)) != 4:
		return Result.failure("reserve card score should expose ceo slot capacity: %s" % str(features))
	if int(features.get("reserve_card_cash", 0)) != 150:
		return Result.failure("reserve card score should expose reserve cash: %s" % str(features))
	if float(features.get("reserve_card_value", 0.0)) <= 0.0:
		return Result.failure("reserve card score should expose positive value: %s" % str(features))
	var bot = StrategyBotClass.new()
	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_SETUP,
		DefsClass.SUB_PHASE_RESERVE_CARDS,
		1,
		seed_val,
		[]
	)
	var decision := bot.choose_command(observation, context, ["select_reserve_card"], Callable(), null)
	if decision == null or decision.is_failure():
		return Result.failure("StrategyBot should choose a reserve card: %s" % (decision.failure_reason if decision != null else "null decision"))
	if int(decision.command.params.get("selected_index", -1)) != 2:
		return Result.failure("StrategyBot should choose the highest strategic reserve card, got decision=%s trace=%s" % [str(decision.command.to_dict()), str(decision.trace)])
	if str(decision.trace.get("phase_strategy", "")) != "setup_reserve_cards":
		return Result.failure("StrategyBot trace should expose phase strategy: %s" % str(decision.trace))
	if str(decision.explanation.get("phase_strategy_goal", "")) != "foundation":
		return Result.failure("StrategyBot explanation should expose phase strategy goal: %s" % str(decision.explanation))
	return Result.success()

static func _test_setup_planner_values_turn_order() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_reserve_card_observation()
	var early_payload: Dictionary = StrategySetupPlannerClass.turn_order_value({"position": 0})
	var later_payload: Dictionary = StrategySetupPlannerClass.turn_order_value({"position": 1})
	if float(early_payload.get("value", 0.0)) <= float(later_payload.get("value", 0.0)):
		return Result.failure("StrategySetupPlanner should prefer earlier turn order: early=%s later=%s" % [str(early_payload), str(later_payload)])
	if int(later_payload.get("position", -1)) != 1:
		return Result.failure("StrategySetupPlanner should expose turn order position: %s" % str(later_payload))
	var later_action_payload: Dictionary = StrategySetupPlannerClass.evaluate_action(observation, Command.create("choose_turn_order", 0, {"position": 1}))
	var later_action_features: Dictionary = Dictionary(later_action_payload.get("features", {}))
	if int(later_action_features.get("turn_order_position", -1)) != 1:
		return Result.failure("StrategySetupPlanner turn order action should expose selected position: %s" % str(later_action_payload))
	if float(later_action_features.get("turn_order_value", 0.0)) <= 0.0:
		return Result.failure("StrategySetupPlanner turn order action should expose positive value: %s" % str(later_action_payload))
	var early_macro := MacroAction.create(
		"turn_order_0",
		[Command.create("choose_turn_order", 0, {"position": 0})],
		0.0,
		["setup", "turn_order"],
		{}
	)
	var later_macro := MacroAction.create(
		"turn_order_1",
		[Command.create("choose_turn_order", 0, {"position": 1})],
		0.0,
		["setup", "turn_order"],
		{}
	)
	var early_score: Dictionary = StrategyScorerClass.score_macro(observation, early_macro, profile)
	var later_score: Dictionary = StrategyScorerClass.score_macro(observation, later_macro, profile)
	if float(early_score.get("score", 0.0)) <= float(later_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer earlier turn order: early=%s later=%s" % [str(early_score), str(later_score)])
	var features: Dictionary = Dictionary(later_score.get("features", {}))
	if int(features.get("turn_order_position", -1)) != 1:
		return Result.failure("turn order score should expose selected position: %s" % str(features))
	if float(features.get("turn_order_value", 0.0)) <= 0.0:
		return Result.failure("turn order score should expose positive value: %s" % str(features))
	return Result.success()

static func _test_marketing_filter_discards_no_house_candidate() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_marketing_observation()
	var bad_macro := MacroAction.create(
		"marketing_no_house",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": []}
	)
	var no_supply_macro := MacroAction.create(
		"marketing_no_supply",
		[Command.create("initiate_marketing", 0, {"product": "beer"})],
		0.0,
		["working", "marketing"],
		{
			"affected_house_ids": ["house_near"],
			"marketing_service_features": {
				"serviceable_houses": 1,
				"inventory_units": 0,
				"can_supply_product": false,
				"can_future_supply_product": false,
			},
		}
	)
	var future_supply_macro := MacroAction.create(
		"marketing_future_supply",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{
			"affected_house_ids": ["house_near"],
			"marketing_service_features": {
				"serviceable_houses": 1,
				"inventory_units": 0,
				"can_supply_product": false,
				"can_future_supply_product": true,
			},
		}
	)
	var skip_macro := MacroAction.create(
		"skip_sub_phase",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var filtered: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, [bad_macro, no_supply_macro, future_supply_macro, skip_macro], profile)
	var kept_val = filtered.get("candidates", [])
	if not (kept_val is Array):
		return Result.failure("StrategyCandidateFilter should return candidate Array")
	var kept: Array = kept_val
	if kept.size() != 2:
		return Result.failure("StrategyCandidateFilter should keep future-supply marketing and fallback candidate, got %d" % kept.size())
	if not kept.has(future_supply_macro):
		return Result.failure("StrategyCandidateFilter should keep future-supply marketing")
	if not kept.has(skip_macro):
		return Result.failure("StrategyCandidateFilter should keep fallback candidate")
	var stats: Dictionary = Dictionary(filtered.get("stats", {}))
	if int(stats.get("discarded_marketing_no_affected_houses", 0)) != 1:
		return Result.failure("StrategyCandidateFilter should count no-house marketing discard: %s" % str(stats))
	if int(stats.get("discarded_marketing_no_supply", 0)) != 1:
		return Result.failure("StrategyCandidateFilter should count no-supply marketing discard: %s" % str(stats))
	return Result.success()

static func _test_marketing_filter_delays_opponent_pressure_until_income_started() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var opening_observation := _synthetic_marketing_observation()
	opening_observation.own_player["cash"] = 0
	opening_observation.own_player["milestones"] = []
	opening_observation.own_player["inventory"] = {}
	var pressure_macro := MacroAction.create(
		"marketing_opening_opponent_pressure",
		[Command.create("initiate_marketing", 0, {"product": "beer"})],
		0.0,
		["working", "marketing"],
		{
			"affected_house_ids": ["house_near"],
			"marketing_service_features": {
				"serviceable_houses": 0,
				"competitive_houses": 0,
				"self_capture_houses": 0,
				"opponent_pressure_houses": 1,
				"opponent_capacity_gap_houses": 1,
				"opponent_capacity_gap_prevented_sales": 1,
				"strategic_houses": 1,
				"inventory_units": 0,
				"can_supply_product": false,
				"can_future_supply_product": false,
			},
		}
	)
	var skip_macro := MacroAction.create(
		"skip_sub_phase",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var opening_filtered: Dictionary = StrategyCandidateFilterClass.filter_candidates(opening_observation, [pressure_macro, skip_macro], profile)
	var opening_kept: Array = Array(opening_filtered.get("candidates", []))
	if opening_kept.has(pressure_macro) or not opening_kept.has(skip_macro):
		return Result.failure("StrategyCandidateFilter should delay pure opponent-pressure marketing before own income: %s" % str(opening_filtered))
	var opening_stats: Dictionary = Dictionary(opening_filtered.get("stats", {}))
	if int(opening_stats.get("discarded_marketing_opening_opponent_pressure", 0)) != 1:
		return Result.failure("StrategyCandidateFilter should count opening opponent-pressure discard: %s" % str(opening_stats))

	var income_observation := _synthetic_marketing_observation()
	income_observation.own_player["cash"] = 20
	income_observation.own_player["milestones"] = ["first_have_20"]
	income_observation.own_player["inventory"] = {}
	var income_filtered: Dictionary = StrategyCandidateFilterClass.filter_candidates(income_observation, [pressure_macro, skip_macro], profile)
	var income_kept: Array = Array(income_filtered.get("candidates", []))
	if not income_kept.has(pressure_macro) or not income_kept.has(skip_macro):
		return Result.failure("StrategyCandidateFilter should allow opponent-pressure marketing after own income starts: %s" % str(income_filtered))
	return Result.success()

static func _test_marketing_score_prefers_affected_serviceable_houses(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_marketing_observation()
	var serviceable_macro := MacroAction.create(
		"marketing_serviceable",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_near"]}
	)
	var no_house_macro := MacroAction.create(
		"marketing_no_house",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": []}
	)
	var good_score: Dictionary = StrategyScorerClass.score_macro(observation, serviceable_macro, profile)
	var bad_score: Dictionary = StrategyScorerClass.score_macro(observation, no_house_macro, profile)
	if float(good_score.get("score", 0.0)) <= float(bad_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer marketing that affects serviceable houses: good=%s bad=%s" % [str(good_score), str(bad_score)])
	var features: Dictionary = Dictionary(good_score.get("features", {}))
	if int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return Result.failure("StrategyScorer should expose marketing_serviceable_houses: %s" % str(features))
	if int(features.get("marketing_inventory_units", 0)) <= 0:
		return Result.failure("StrategyScorer should expose marketing inventory support: %s" % str(features))
	return Result.success()

static func _test_marketing_generation_prioritizes_ready_product(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var observation := _synthetic_marketing_observation()
	observation.own_player["reserve_employees"] = ["errand_boy"]
	var houses: Dictionary = Dictionary(observation.map_public.get("houses", {}))
	var house_near: Dictionary = Dictionary(houses.get("house_near", {}))
	house_near["demands"] = [{"product": "burger"}]
	houses["house_near"] = house_near
	observation.map_public["houses"] = houses
	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_WORKING,
		DefsClass.SUB_PHASE_MARKETING,
		1,
		seed_val,
		[]
	)
	var generated := CandidateGeneratorClass.generate(
		observation,
		context,
		["initiate_marketing"],
		Callable(),
		{"max_valid_per_action": 4}
	)
	if not generated.ok:
		return generated
	var payload: Dictionary = Dictionary(generated.value)
	var candidates_val = payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.failure("CandidateGenerator should return candidates Array")
	var candidates: Array = candidates_val
	if candidates.is_empty():
		return Result.failure("CandidateGenerator should generate marketing candidates")
	var first_macro = candidates[0]
	if not (first_macro is MacroAction):
		return Result.failure("CandidateGenerator returned non-MacroAction candidate")
	var first_action: MacroAction = first_macro
	if first_action.commands.is_empty():
		return Result.failure("CandidateGenerator returned empty marketing macro")
	var first_command: Command = first_action.commands[0]
	var first_product := str(first_command.params.get("product", ""))
	if first_product != "burger":
		return Result.failure("marketing generation should prioritize stocked/demanded burger before reserve-only drinks, got product=%s macro=%s" % [first_product, first_action.id])
	return Result.success()

static func _test_marketing_generation_discards_competitor_captured_candidates(seed_val: int) -> Result:
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
	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_WORKING,
		DefsClass.SUB_PHASE_MARKETING,
		int(state.round_number),
		seed_val,
		[]
	)
	var generated := CandidateGeneratorClass.generate(
		observation,
		context,
		["initiate_marketing"],
		Callable(),
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

static func _test_marketing_score_uses_active_supply_for_unstocked_product(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var reserve_observation := _synthetic_marketing_observation()
	reserve_observation.own_player["inventory"] = {}
	reserve_observation.own_player["reserve_employees"] = ["errand_boy"]
	var active_observation := _synthetic_marketing_observation()
	active_observation.own_player["inventory"] = {}
	active_observation.own_player["employees"] = ["campaign_manager", "errand_boy"]
	var beer_macro := MacroAction.create(
		"marketing_beer",
		[Command.create("initiate_marketing", 0, {"product": "beer"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_near"]}
	)
	var reserve_score: Dictionary = StrategyScorerClass.score_macro(reserve_observation, beer_macro, profile)
	var active_score: Dictionary = StrategyScorerClass.score_macro(active_observation, beer_macro, profile)
	var reserve_features: Dictionary = Dictionary(reserve_score.get("features", {}))
	var active_features: Dictionary = Dictionary(active_score.get("features", {}))
	if bool(reserve_features.get("marketing_can_supply_product", true)):
		return Result.failure("reserve employees should not count as immediate marketing supply: %s" % str(reserve_features))
	if not bool(active_features.get("marketing_can_supply_product", false)):
		return Result.failure("active employees should count as immediate marketing supply: %s" % str(active_features))
	if float(active_score.get("score", 0.0)) <= float(reserve_score.get("score", 0.0)):
		return Result.failure("active supply should score higher than reserve-only supply: active=%s reserve=%s" % [str(active_score), str(reserve_score)])
	return Result.success()

static func _test_marketing_score_uses_source_road_graph(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	var drive_setup := _apply_drive_through_source_case(state)
	if not drive_setup.ok:
		return drive_setup
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var macro := MacroAction.create(
		"marketing_drive_through_road_graph",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_left"]}
	)
	var score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, macro, profile, {"source_state": state})
	var features: Dictionary = Dictionary(score.get("features", {}))
	if str(features.get("marketing_distance_source", "")) != "road_graph":
		return Result.failure("StrategyScorer should use source road graph when available: %s" % str(features))
	if int(features.get("marketing_serviceable_houses", 0)) != 1:
		return Result.failure("StrategyScorer should find drive-through road-graph serviceable house: %s" % str(features))
	if int(features.get("marketing_closest_distance", -1)) < 0:
		return Result.failure("StrategyScorer should expose road-graph marketing distance: %s" % str(features))
	return Result.success()

static func _test_marketing_score_penalizes_competitor_sale_route(seed_val: int) -> Result:
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
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var own_route_macro := MacroAction.create(
		"marketing_own_route",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_left"]}
	)
	var competitor_route_macro := MacroAction.create(
		"marketing_competitor_route",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_right"]}
	)
	var skip_macro := MacroAction.create(
		"skip_competitor_route_marketing",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var own_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, own_route_macro, profile, {"source_state": state})
	var competitor_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, competitor_route_macro, profile, {"source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_state": state})
	var own_features: Dictionary = Dictionary(own_score.get("features", {}))
	var competitor_features: Dictionary = Dictionary(competitor_score.get("features", {}))
	if int(own_features.get("marketing_competitive_houses", 0)) != 1:
		return Result.failure("own-side marketing should be competitively serviceable: %s" % str(own_features))
	if int(competitor_features.get("marketing_lost_to_competitor_houses", 0)) != 1:
		return Result.failure("competitor-side marketing should expose lost sale route: %s" % str(competitor_features))
	if float(competitor_features.get("marketing_competitive_sales_penalty", 0.0)) > -100.0:
		return Result.failure("competitor-side marketing should carry a strong competitive penalty: %s" % str(competitor_features))
	if float(competitor_score.get("score", 0.0)) >= float(own_score.get("score", 0.0)):
		return Result.failure("marketing should prefer self-captured demand over competitor-captured demand: own=%s competitor=%s" % [str(own_score), str(competitor_score)])
	if float(competitor_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("marketing that is likely captured by a competitor should lose to skip: competitor=%s skip=%s" % [str(competitor_score), str(skip_score)])
	return Result.success()

static func _test_marketing_score_penalizes_restaurant_dominated_future_route(seed_val: int) -> Result:
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
	state.players[1]["employees"] = []
	state.players[0]["inventory"] = {"burger": 1}
	state.players[1]["inventory"] = {}
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var dominated_route_macro := MacroAction.create(
		"marketing_restaurant_dominated_route",
		[Command.create("initiate_marketing", 0, {"product": "burger"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_right"]}
	)
	var skip_macro := MacroAction.create(
		"skip_restaurant_dominated_marketing",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var dominated_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, dominated_route_macro, profile, {"source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_state": state})
	var features: Dictionary = Dictionary(dominated_score.get("features", {}))
	if int(features.get("marketing_restaurant_dominated_houses", 0)) != 1:
		return Result.failure("restaurant-dominated marketing should expose route domination even before competitor supply exists: %s" % str(features))
	if int(features.get("marketing_lost_to_competitor_houses", -1)) != 0:
		return Result.failure("restaurant-dominated future route should be separate from current competitor supply capture: %s" % str(features))
	if int(features.get("marketing_self_capture_houses", -1)) != 0:
		return Result.failure("restaurant-dominated future route should not count as self-captured demand: %s" % str(features))
	if float(dominated_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("restaurant-dominated marketing should lose to skip: dominated=%s skip=%s" % [str(dominated_score), str(skip_score)])
	return Result.success()

static func _test_marketing_score_values_opponent_capacity_gap(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
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
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var disruptive_macro := MacroAction.create(
		"marketing_opponent_gap_pizza",
		[Command.create("initiate_marketing", 0, {"product": "pizza"})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_right"]}
	)
	var skip_macro := MacroAction.create(
		"skip_opponent_gap_marketing",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var disruptive_score: Dictionary = StrategyScorerClass.score_macro(observation, disruptive_macro, profile, {"source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile, {"source_state": state})
	var features: Dictionary = Dictionary(disruptive_score.get("features", {}))
	if int(features.get("marketing_opponent_capacity_gap_houses", 0)) != 1:
		return Result.failure("disruptive marketing should expose one opponent capacity gap house: %s" % str(features))
	if int(features.get("marketing_opponent_capacity_gap_prevented_sales", 0)) != 1:
		return Result.failure("disruptive marketing should expose prevented opponent sale: %s" % str(features))
	if not Array(features.get("marketing_opponent_capacity_gap_products", [])).has("pizza"):
		return Result.failure("disruptive marketing should expose pizza as the gap product: %s" % str(features))
	if int(features.get("marketing_self_capture_houses", -1)) != 0:
		return Result.failure("disruptive marketing should not be classified as self-captured demand without supply: %s" % str(features))
	if int(features.get("marketing_opponent_pressure_houses", 0)) != 1:
		return Result.failure("disruptive marketing should be classified as opponent pressure: %s" % str(features))
	if int(features.get("marketing_strategic_houses", 0)) != 1:
		return Result.failure("disruptive marketing should expose one strategic house through pressure analysis: %s" % str(features))
	if str(features.get("marketing_pressure_mode", "")) != "opponent_pressure":
		return Result.failure("disruptive marketing should use opponent_pressure mode: %s" % str(features))
	if not Array(features.get("marketing_recovery_modes", [])).has("opponent_capacity_attack"):
		return Result.failure("disruptive marketing should expose opponent capacity attack recovery mode: %s" % str(features))
	if not Array(features.get("marketing_recovery_modes", [])).has("product_switch"):
		return Result.failure("disruptive marketing should expose product-switch recovery mode: %s" % str(features))
	if features.has("marketing_supply_readiness_penalty") and float(features.get("marketing_supply_readiness_penalty", 0.0)) < 0.0:
		return Result.failure("opponent-gap marketing should not be penalized as a self-supply route: %s" % str(features))
	if float(disruptive_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should value opponent-gap marketing over skipping: disruptive=%s skip=%s" % [str(disruptive_score), str(skip_score)])

	var context := AiDecisionContext.create(
		0,
		DefsClass.PHASE_WORKING,
		DefsClass.SUB_PHASE_MARKETING,
		int(state.round_number),
		seed_val,
		[]
	)
	var generated := CandidateGeneratorClass.generate(
		observation,
		context,
		["initiate_marketing"],
		Callable(),
		{"max_valid_per_action": 500, "source_state": state}
	)
	if not generated.ok:
		return generated
	var payload: Dictionary = Dictionary(generated.value)
	var candidates_val = payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.failure("CandidateGenerator should return candidates Array")
	var found_gap_candidate := false
	var gap_command: Command = null
	for candidate_val in Array(candidates_val):
		if not (candidate_val is MacroAction):
			continue
		var candidate: MacroAction = candidate_val
		if candidate.commands.is_empty():
			continue
		var command: Command = candidate.commands[0]
		var product_id := str(command.params.get("product", ""))
		var affected := _sorted_unique_strings(candidate.debug.get("affected_house_ids", []))
		if not affected.has("house_right"):
			continue
		var service_features: Dictionary = Dictionary(candidate.debug.get("marketing_service_features", {}))
		var gap_products := _sorted_unique_strings(service_features.get("opponent_capacity_gap_products", []))
		var pressure_mode := str(service_features.get("pressure_mode", ""))
		if int(service_features.get("opponent_pressure_houses", 0)) > 0 and pressure_mode == "opponent_pressure" and gap_products.has(product_id):
			found_gap_candidate = true
			gap_command = command
			break
	if not found_gap_candidate:
		return Result.failure("CandidateGenerator should keep opponent-gap marketing candidates: %s" % str(payload.get("discarded_reasons", [])))
	if gap_command == null:
		return Result.failure("Opponent-gap marketing test did not retain the candidate command")
	var gap_product := str(gap_command.params.get("product", ""))
	if gap_product.is_empty():
		return Result.failure("Opponent-gap marketing candidate should include product: %s" % str(gap_command.params))
	var executed := engine.execute_command(gap_command)
	if not executed.ok:
		return Result.failure("Opponent-gap marketing candidate should execute: %s" % executed.error)
	var after_observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not after_observation_read.ok:
		return after_observation_read
	var after_income: Dictionary = StrategyIncomeAnalyzerClass.analyze(after_observation_read.value, profile, engine.get_state())
	var products: Dictionary = Dictionary(after_income.get("products", {}))
	var gap_product_info: Dictionary = Dictionary(products.get(gap_product, {}))
	if int(gap_product_info.get("pending_marketing_demand", 0)) != 0:
		return Result.failure("opponent-pressure-only marketing should not become own pending supply demand: %s" % str(gap_product_info))
	if int(gap_product_info.get("pending_defensive_marketing_demand", 0)) != 1:
		return Result.failure("opponent-pressure-only marketing should be tracked as defensive pending demand: product=%s command=%s instances=%s" % [str(gap_product_info), str(gap_command.params), str(engine.get_state().marketing_instances)])
	if int(after_income.get("total_pending_marketing_demand", 0)) != 0:
		return Result.failure("defensive marketing should not drive own pending demand totals: %s" % str(after_income))
	if int(after_income.get("total_pending_defensive_marketing_demand", 0)) != 1:
		return Result.failure("defensive marketing should expose defensive pending demand totals: %s" % str(after_income))

	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [
		{"product": "burger", "from_player": 1, "board_number": 1, "type": "billboard"},
		{"product": "pizza", "from_player": 0, "board_number": 2, "type": "billboard"},
	])
	state.marketing_instances.clear()
	var full_order_observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not full_order_observation_read.ok:
		return full_order_observation_read
	var full_order_income: Dictionary = StrategyIncomeAnalyzerClass.analyze(full_order_observation_read.value, profile, state)
	var full_order_products: Dictionary = Dictionary(full_order_income.get("products", {}))
	var burger: Dictionary = Dictionary(full_order_products.get("burger", {}))
	var pizza2: Dictionary = Dictionary(full_order_products.get("pizza", {}))
	if int(burger.get("lost_to_competitor_demand", 0)) != 0:
		return Result.failure("full-order pressure should not mark burger as lost when own-sourced pizza blocks opponent full order: %s" % str(full_order_income))
	if int(pizza2.get("own_sourced_opponent_blocking_demand", 0)) != 1:
		return Result.failure("full-order pressure should expose own-sourced product-switch blocking demand: %s" % str(full_order_income))
	if int(full_order_income.get("total_price_recoverable_demand", 0)) != 0:
		return Result.failure("full-order pressure should not call blocked opponent orders price recoverable: %s" % str(full_order_income))
	if int(full_order_income.get("total_own_sourced_opponent_blocking_demand", 0)) != 1:
		return Result.failure("full-order pressure should aggregate own-sourced opponent blocking demand: %s" % str(full_order_income))
	var product_switch_income := {
		"products": {
			"pizza": {
				"public_demand": 1,
				"serviceable_demand": 1,
				"actionable_demand": 0,
				"own_sourced_opponent_blocking_demand": 1,
				"price_recoverable_demand": 0,
				"price_projected_actionable_demand": 0,
				"inventory_units": 0,
				"inventory_gap": 1,
				"actionable_inventory_gap": 0,
				"pending_marketing_demand": 0,
				"planning_demand": 1,
				"planning_actionable_demand": 0,
				"planning_inventory_gap": 1,
				"planning_actionable_inventory_gap": 0,
				"can_supply": true,
				"is_drink": false,
			},
		},
		"total_own_sourced_opponent_blocking_demand": 1,
	}
	var product_switch_features := {}
	var product_switch_value := StrategySupplyPlannerClass.product_supply_action_value("pizza", profile, product_switch_income, product_switch_features, 1, full_order_observation_read.value)
	if product_switch_value <= 0.0 or str(product_switch_features.get("product_supply_relevance", "")) != "product_switch_gap":
		return Result.failure("product-switch pressure should make matching supply relevant without price-recovery patching: value=%s features=%s" % [str(product_switch_value), str(product_switch_features)])
	return Result.success()

static func _test_marketing_score_uses_marketing_preview_for_capped_demand(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	MarketingCampaignsTestClass._force_turn_order(state, 2)
	var actor := state.get_current_player_id()
	var map_result := MarketingCampaignsTestClass._build_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[actor]["restaurants"] = ["rest_0"]
	state.players[actor]["cash"] = 100
	state.players[actor]["inventory"]["burger"] = 1
	var take := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take.ok:
		return Result.failure("take marketing_trainee failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "marketing_trainee", false)
	if not add.ok:
		return Result.failure("add marketing_trainee failed: %s" % add.error)
	var houses: Dictionary = state.map.get("houses", {})
	var left: Dictionary = houses.get("house_left", {})
	var full_demands: Array = []
	var demand_cap := int(state.get_rule_int("demand_cap_normal"))
	for i in range(demand_cap):
		full_demands.append({"product": "pizza", "from_player": -1, "board_number": 0, "type": "seed_%d" % i})
	left["demands"] = full_demands
	houses["house_left"] = left
	state.map["houses"] = houses
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.round_state["sub_phase_passed"] = {
		0: false,
		1: false,
	}
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, actor)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var marketing_macro := MacroAction.create(
		"marketing_capped_house",
		[Command.create("initiate_marketing", actor, {
			"employee_type": "marketing_trainee",
			"board_number": 11,
			"product": "burger",
			"duration": 1,
			"position": [0, 2],
		})],
		0.0,
		["working", "marketing"],
		{"affected_house_ids": ["house_left"]}
	)
	var skip_macro := MacroAction.create(
		"skip_marketing_capped_house",
		[Command.create("skip_sub_phase", actor, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var marketing_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, marketing_macro, profile, {"source_engine": engine, "source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(marketing_score.get("features", {}))
	if str(features.get("marketing_preview_source", "")) != "marketing_preview":
		return Result.failure("marketing scoring should use MarketingPreview when source_engine is available: %s" % str(features))
	if int(features.get("marketing_preview_demands_added", -1)) != 0:
		return Result.failure("capped house should preview zero added demand: %s" % str(features))
	if float(features.get("marketing_preview_no_demand_penalty", 0.0)) >= 0.0:
		return Result.failure("zero-demand marketing should expose preview penalty: %s" % str(features))
	if float(marketing_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer skipping zero-demand marketing: marketing=%s skip=%s" % [str(marketing_score), str(skip_score)])
	return Result.success()

static func _test_income_analyzer_detects_serviceable_inventory_gap(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(_synthetic_income_observation(), profile)
	var products: Dictionary = Dictionary(analysis.get("products", {}))
	var burger: Dictionary = Dictionary(products.get("burger", {}))
	if int(burger.get("public_demand", 0)) != 2:
		return Result.failure("income analyzer should count burger demand: %s" % str(burger))
	if int(burger.get("serviceable_demand", 0)) != 2:
		return Result.failure("income analyzer should count serviceable burger demand: %s" % str(burger))
	if int(burger.get("inventory_gap", 0)) != 2:
		return Result.failure("income analyzer should expose burger inventory gap: %s" % str(burger))
	return Result.success()

static func _test_income_analyzer_detects_competitive_inventory_gap(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	state.players[0]["employees"] = ["burger_cook"]
	state.players[1]["employees"] = ["burger_cook"]
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "burger"}])
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(observation_read.value, profile, state)
	var products: Dictionary = Dictionary(analysis.get("products", {}))
	var burger: Dictionary = Dictionary(products.get("burger", {}))
	if int(burger.get("public_demand", 0)) != 2:
		return Result.failure("competitive income analyzer should keep public burger demand: %s" % str(burger))
	if int(burger.get("serviceable_demand", 0)) != 2:
		return Result.failure("competitive income analyzer should count both road-reachable burger demands: %s" % str(burger))
	if int(burger.get("actionable_demand", -1)) != 1:
		return Result.failure("competitive income analyzer should only count own-winnable burger demand as actionable: %s" % str(burger))
	if int(burger.get("lost_to_competitor_demand", -1)) != 1:
		return Result.failure("competitive income analyzer should expose competitor-captured burger demand: %s" % str(burger))
	if int(burger.get("actionable_inventory_gap", -1)) != 1:
		return Result.failure("competitive income analyzer should base actionable gap on own-winnable demand: %s" % str(burger))
	return Result.success()

static func _test_income_analyzer_detects_price_recoverable_demand(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	state.players[0]["employees"] = ["burger_cook", "campaign_manager"]
	state.players[1]["employees"] = ["burger_cook"]
	state.players[0]["cash"] = 35
	state.players[0]["inventory"] = {"burger": 1}
	state.players[1]["inventory"] = {"burger": 1}
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "burger"}])
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(observation_read.value, profile, state)
	var products: Dictionary = Dictionary(analysis.get("products", {}))
	var burger: Dictionary = Dictionary(products.get("burger", {}))
	if int(burger.get("actionable_demand", -1)) != 0:
		return Result.failure("price recovery setup should start with no currently winnable burger demand: %s" % str(burger))
	if int(burger.get("lost_to_competitor_demand", -1)) != 1:
		return Result.failure("price recovery setup should expose lost competitor demand: %s" % str(burger))
	if int(burger.get("price_recoverable_demand", -1)) != 1:
		return Result.failure("income analyzer should expose demand recoverable by lower price: %s" % str(burger))
	if int(analysis.get("total_price_recoverable_demand", -1)) != 1:
		return Result.failure("income analyzer should total price recoverable demand: %s" % str(analysis))
	var route_plan: Dictionary = StrategyRoutePlannerClass.analyze(observation_read.value, analysis, profile)
	if not bool(route_plan.get("price_route_ready", false)):
		return Result.failure("route planner should treat lower-price recovery as price route ready: %s" % str(route_plan))
	if int(route_plan.get("price_recoverable_inventory_units", -1)) != 1:
		return Result.failure("route planner should expose recoverable sale inventory: %s" % str(route_plan))
	var price_payload: Dictionary = StrategySupportPlannerClass.price_employee_route_value(observation_read.value, "pricing_manager", analysis)
	if float(price_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("price support should value recoverable lost demand: %s" % str(price_payload))
	if int(price_payload.get("recoverable_demand", -1)) != 1:
		return Result.failure("price support should expose recoverable demand: %s" % str(price_payload))
	state.players[0]["inventory"] = {}
	var no_inventory_observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not no_inventory_observation_read.ok:
		return no_inventory_observation_read
	var no_inventory_analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(no_inventory_observation_read.value, profile, state)
	var supply_features := {}
	var supply_value := StrategySupplyPlannerClass.product_supply_action_value("burger", profile, no_inventory_analysis, supply_features, 1, no_inventory_observation_read.value)
	if supply_value <= 0.0:
		return Result.failure("supply planner should value production for price-recoverable lost demand: %s" % str(supply_features))
	if str(supply_features.get("product_supply_relevance", "")) != "price_recovery_gap":
		return Result.failure("supply planner should classify recoverable production as price_recovery_gap: %s" % str(supply_features))
	state.players[0]["inventory"] = {"burger": 1}
	observation_read.value.phase = DefsClass.PHASE_WORKING
	observation_read.value.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	var pricing_macro := MacroAction.create(
		"recruit_pricing_for_recoverable_demand",
		[Command.create("recruit", 0, {"employee_type": "pricing_manager"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_recoverable_price_route",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var pricing_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, pricing_macro, profile, {"source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_state": state})
	if float(pricing_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("pricing manager recruit should beat skip for recoverable lost demand: pricing=%s skip=%s" % [str(pricing_score), str(skip_score)])
	var pricing_features: Dictionary = Dictionary(pricing_score.get("features", {}))
	if int(pricing_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("recoverable price route should desire one pricing manager: %s" % str(pricing_features))
	if int(pricing_features.get("recruit_price_route_recoverable_demand", -1)) != 1:
		return Result.failure("recoverable price route should expose recruit recoverable demand: %s" % str(pricing_features))
	return Result.success()

static func _test_income_analyzer_uses_road_graph_for_unreachable_demand() -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 330010)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	for _i in range(2):
		var reserve_state := engine.get_state()
		if reserve_state == null:
			return Result.failure("road graph unreachable demand test state is null during reserve")
		var reserve_player := reserve_state.get_current_player_id()
		var reserve := engine.execute_command(Command.create("select_reserve_card", reserve_player, {"selected_index": 2}))
		if not reserve.ok:
			return Result.failure("road graph unreachable demand test reserve failed: %s" % reserve.error)
	var place0 := engine.execute_command(Command.create("place_restaurant", 0, {"position": [6, 5], "rotation": 180}))
	if not place0.ok:
		return Result.failure("road graph unreachable demand test place p0 failed: %s" % place0.error)
	var setup_skip := engine.execute_command(Command.create("skip", 0, {}))
	if not setup_skip.ok:
		return Result.failure("road graph unreachable demand test setup skip failed: %s" % setup_skip.error)
	var place1 := engine.execute_command(Command.create("place_restaurant", 1, {"position": [10, 3], "rotation": 0}))
	if not place1.ok:
		return Result.failure("road graph unreachable demand test place p1 failed: %s" % place1.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("road graph unreachable demand test state is null")
	var houses_val = state.map.get("houses", {})
	if not (houses_val is Dictionary) or not Dictionary(houses_val).has("7"):
		return Result.failure("road graph unreachable demand test requires seed 330010 house 7")
	DinnertimeSettlementTestClass._set_house_demands(state, "7", [{"product": "burger"}])
	state.players[0]["inventory"] = {"burger": 1}
	state.players[1]["inventory"] = {}
	var take := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take.ok:
		return Result.failure("road graph unreachable demand test take kitchen_trainee failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 1, "kitchen_trainee", false)
	if not add.ok:
		return Result.failure("road graph unreachable demand test add kitchen_trainee failed: %s" % add.error)
	RoadGraphCacheClass.invalidate_road_graph(state)
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 1)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var pressure: Dictionary = MarketingPressureAnalyzerClass.current_demand_pressure_by_product(state, observation)
	var burger_pressure: Dictionary = Dictionary(pressure.get("burger", {}))
	if int(burger_pressure.get("unserviceable_demand", 0)) != 1:
		return Result.failure("road pressure should expose unreachable burger demand instead of omitting the product: %s" % str(pressure))
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(observation, profile, state)
	var products: Dictionary = Dictionary(analysis.get("products", {}))
	var burger: Dictionary = Dictionary(products.get("burger", {}))
	if int(burger.get("public_demand", 0)) != 1:
		return Result.failure("unreachable demand test should keep public burger demand: %s" % str(burger))
	if int(burger.get("serviceable_demand", -1)) != 0:
		return Result.failure("income analyzer should not count road-unreachable burger demand as serviceable: %s" % str(burger))
	if int(burger.get("actionable_demand", -1)) != 0:
		return Result.failure("income analyzer should not count road-unreachable burger demand as actionable: %s" % str(burger))
	if int(burger.get("actionable_inventory_gap", -1)) != 0:
		return Result.failure("income analyzer should not create actionable gap for road-unreachable demand: %s" % str(burger))
	return Result.success()

static func _test_income_analyzer_counts_pending_marketing_demand(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	_set_observation_house_demand_count(observation, "house_near", "burger", 0)
	observation.marketing_instances_public = [
		{"owner": 0, "product": "beer", "remaining_duration": 2},
		{"owner": 1, "product": "soda", "remaining_duration": 2},
		{"owner": 0, "product": "soda", "remaining_duration": 0},
		{"owner": 0, "product": "soda", "remaining_duration": 2, "demand_amount": 0},
	]
	var analysis: Dictionary = StrategyIncomeAnalyzerClass.analyze(observation, profile)
	if int(analysis.get("total_pending_marketing_demand", 0)) != 1:
		return Result.failure("income analyzer should count own pending marketing demand only: %s" % str(analysis))
	var products: Dictionary = Dictionary(analysis.get("products", {}))
	var beer: Dictionary = Dictionary(products.get("beer", {}))
	if int(beer.get("pending_marketing_demand", 0)) != 1:
		return Result.failure("beer should expose pending_marketing_demand from own campaign: %s" % str(beer))
	if int(beer.get("planning_inventory_gap", 0)) != 1:
		return Result.failure("beer should expose planning_inventory_gap from pending campaign: %s" % str(beer))
	var soda: Dictionary = Dictionary(products.get("soda", {}))
	if int(soda.get("pending_marketing_demand", 0)) != 0:
		return Result.failure("opponent pending marketing should not count as own pending demand: %s" % str(soda))
	return Result.success()

static func _test_recruit_score_penalizes_roster_saturation(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var useful_observation := _synthetic_income_observation()
	useful_observation.phase = DefsClass.PHASE_WORKING
	useful_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	_set_observation_house_demand_count(useful_observation, "house_near", "burger", 6)
	var saturated_observation := _synthetic_income_observation()
	saturated_observation.phase = DefsClass.PHASE_WORKING
	saturated_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	saturated_observation.own_player["employees"] = ["burger_cook", "pizza_cook", "trainer"]
	_set_observation_house_demand_count(saturated_observation, "house_near", "burger", 6)
	var trainer_macro := MacroAction.create(
		"recruit_trainer",
		[Command.create("recruit", 0, {"employee_type": "trainer"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_recruit",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var useful_score: Dictionary = StrategyScorerClass.score_macro(useful_observation, trainer_macro, profile)
	var duplicate_score: Dictionary = StrategyScorerClass.score_macro(saturated_observation, trainer_macro, profile)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(saturated_observation, skip_macro, profile)
	if float(useful_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should still value first trainer when training closes a capacity gap: trainer=%s skip=%s" % [str(useful_score), str(skip_score)])
	if float(duplicate_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer skipping over duplicate saturated trainer: trainer=%s skip=%s" % [str(duplicate_score), str(skip_score)])
	var features: Dictionary = Dictionary(duplicate_score.get("features", {}))
	if not bool(features.get("recruit_roster_saturated", false)):
		return Result.failure("duplicate trainer should expose recruit_roster_saturated: %s" % str(features))
	if int(features.get("recruit_owned_count", 0)) != 1:
		return Result.failure("duplicate trainer should expose owned count: %s" % str(features))
	if int(features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("duplicate trainer should expose desired count: %s" % str(features))
	if float(features.get("recruit_roster_adjustment", 0.0)) >= 0.0:
		return Result.failure("duplicate trainer should carry negative roster adjustment: %s" % str(features))
	var saturated_train_route_observation := _synthetic_income_observation()
	saturated_train_route_observation.phase = DefsClass.PHASE_WORKING
	saturated_train_route_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	saturated_train_route_observation.own_player["employees"] = ["kitchen_trainee", "marketing_trainee", "trainer"]
	saturated_train_route_observation.own_player["reserve_employees"] = ["errand_boy"]
	var duplicate_train_route_score: Dictionary = StrategyScorerClass.score_macro(saturated_train_route_observation, trainer_macro, profile)
	var train_route_skip: Dictionary = StrategyScorerClass.score_macro(saturated_train_route_observation, skip_macro, profile)
	if float(duplicate_train_route_score.get("score", 0.0)) >= float(train_route_skip.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip duplicate trainer even when trainable reserve exists: trainer=%s skip=%s" % [str(duplicate_train_route_score), str(train_route_skip)])
	var train_route_features: Dictionary = Dictionary(duplicate_train_route_score.get("features", {}))
	if not bool(train_route_features.get("recruit_roster_saturated", false)):
		return Result.failure("duplicate trainer with trainable reserve should expose recruit_roster_saturated: %s" % str(train_route_features))
	var completed_route_observation := _synthetic_income_observation()
	completed_route_observation.phase = DefsClass.PHASE_WORKING
	completed_route_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	completed_route_observation.own_player["employees"] = ["new_business_developer"]
	var management_macro := MacroAction.create(
		"recruit_management_after_target",
		[Command.create("recruit", 0, {"employee_type": "management_trainee"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var management_score: Dictionary = StrategyScorerClass.score_macro(completed_route_observation, management_macro, profile)
	var management_skip: Dictionary = StrategyScorerClass.score_macro(completed_route_observation, skip_macro, profile)
	if float(management_score.get("score", 0.0)) >= float(management_skip.get("score", 0.0)):
		return Result.failure("StrategyScorer should avoid recruiting management trainee after route target exists: management=%s skip=%s" % [str(management_score), str(management_skip)])
	var management_features: Dictionary = Dictionary(management_score.get("features", {}))
	if int(management_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("completed management route should expose zero desired count: %s" % str(management_features))
	if not bool(management_features.get("recruit_roster_saturated", false)):
		return Result.failure("completed management route should be saturated: %s" % str(management_features))
	return Result.success()

static func _test_recruit_score_delays_advanced_support_until_income_ready(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player["employees"] = ["burger_cook"]
	_set_observation_house_demand_count(observation, "house_near", "burger", 0)
	var pricing_macro := MacroAction.create(
		"recruit_pricing_before_stable_income",
		[Command.create("recruit", 0, {"employee_type": "pricing_manager"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var recruiter_macro := MacroAction.create(
		"recruit_recruiting_girl_before_stable_income",
		[Command.create("recruit", 0, {"employee_type": "recruiting_girl"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var waitress_macro := MacroAction.create(
		"recruit_waitress_before_price_support",
		[Command.create("recruit", 0, {"employee_type": "waitress"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_recruit",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var early_pricing_score: Dictionary = StrategyScorerClass.score_macro(observation, pricing_macro, profile)
	var early_recruiter_score: Dictionary = StrategyScorerClass.score_macro(observation, recruiter_macro, profile)
	var early_waitress_score: Dictionary = StrategyScorerClass.score_macro(observation, waitress_macro, profile)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile)
	if float(early_pricing_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip pricing manager before serviceable price opportunity: pricing=%s skip=%s" % [str(early_pricing_score), str(skip_score)])
	if float(early_recruiter_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip recruiting girl before stable income route: recruiting_girl=%s skip=%s" % [str(early_recruiter_score), str(skip_score)])
	if float(early_waitress_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip waitress before stable income and price support: waitress=%s skip=%s" % [str(early_waitress_score), str(skip_score)])
	var early_pricing_features: Dictionary = Dictionary(early_pricing_score.get("features", {}))
	if int(early_pricing_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("early pricing manager should expose zero desired count: %s" % str(early_pricing_features))
	var early_recruiter_features: Dictionary = Dictionary(early_recruiter_score.get("features", {}))
	if int(early_recruiter_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("early recruiting girl should expose zero desired count: %s" % str(early_recruiter_features))
	var early_waitress_features: Dictionary = Dictionary(early_waitress_score.get("features", {}))
	if int(early_waitress_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("early waitress should expose zero desired count: %s" % str(early_waitress_features))

	var price_opportunity_observation := _synthetic_income_observation()
	price_opportunity_observation.phase = DefsClass.PHASE_WORKING
	price_opportunity_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	price_opportunity_observation.own_player["cash"] = 0
	price_opportunity_observation.own_player["employees"] = ["burger_cook", "campaign_manager"]
	price_opportunity_observation.own_player["inventory"] = {"burger": 1}
	_set_observation_house_demand_count(price_opportunity_observation, "house_near", "burger", 1)
	var price_opportunity_score: Dictionary = StrategyScorerClass.score_macro(price_opportunity_observation, pricing_macro, profile)
	var price_opportunity_skip: Dictionary = StrategyScorerClass.score_macro(price_opportunity_observation, skip_macro, profile)
	if float(price_opportunity_score.get("score", 0.0)) <= float(price_opportunity_skip.get("score", 0.0)):
		return Result.failure("StrategyScorer should value pricing manager for one serviceable opportunity: pricing=%s skip=%s" % [str(price_opportunity_score), str(price_opportunity_skip)])
	var price_opportunity_features: Dictionary = Dictionary(price_opportunity_score.get("features", {}))
	if int(price_opportunity_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("price opportunity pricing manager should expose desired count 1: %s" % str(price_opportunity_features))
	if float(price_opportunity_features.get("recruit_price_route_value", 0.0)) <= 0.0:
		return Result.failure("price opportunity pricing manager should expose route value: %s" % str(price_opportunity_features))

	var ready_observation := _synthetic_income_observation()
	ready_observation.phase = DefsClass.PHASE_WORKING
	ready_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	ready_observation.own_player["cash"] = 25
	ready_observation.own_player["employees"] = ["burger_cook", "marketing_trainee"]
	ready_observation.own_player["inventory"] = {"burger": 2}
	var ready_pricing_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, pricing_macro, profile)
	var ready_recruiter_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, recruiter_macro, profile)
	var ready_waitress_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, waitress_macro, profile)
	var ready_pricing_features: Dictionary = Dictionary(ready_pricing_score.get("features", {}))
	if int(ready_pricing_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("stable income pricing manager should expose desired count 1: %s" % str(ready_pricing_features))
	var ready_recruiter_features: Dictionary = Dictionary(ready_recruiter_score.get("features", {}))
	if int(ready_recruiter_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("stable income recruiting girl should expose desired count 1: %s" % str(ready_recruiter_features))
	var ready_waitress_features: Dictionary = Dictionary(ready_waitress_score.get("features", {}))
	if int(ready_waitress_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("stable income waitress should stay at desired count 0 before price support: %s" % str(ready_waitress_features))
	if float(ready_waitress_features.get("recruit_waitress_route_value", 0.0)) != 0.0:
		return Result.failure("stable income waitress route value should stay disabled before price support: %s" % str(ready_waitress_features))

	var price_supported_observation := _synthetic_income_observation()
	price_supported_observation.phase = DefsClass.PHASE_WORKING
	price_supported_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	price_supported_observation.own_player["cash"] = 25
	price_supported_observation.own_player["employees"] = ["burger_cook", "marketing_trainee", "pricing_manager"]
	price_supported_observation.own_player["inventory"] = {"burger": 2}
	price_supported_observation.milestone_pool_public = ["first_waitress"]
	var price_supported_waitress_score: Dictionary = StrategyScorerClass.score_macro(price_supported_observation, waitress_macro, profile)
	var price_supported_waitress_features: Dictionary = Dictionary(price_supported_waitress_score.get("features", {}))
	if int(price_supported_waitress_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("price-supported waitress should expose desired count 1: %s" % str(price_supported_waitress_features))
	if float(price_supported_waitress_features.get("recruit_waitress_route_value", 0.0)) <= 0.0:
		return Result.failure("price-supported waitress should expose route value: %s" % str(price_supported_waitress_features))
	return Result.success()

static func _test_recruit_score_values_house_placement_route(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_house_growth_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	var early_income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile)
	var early_management_payload: Dictionary = StrategyEmployeePlannerClass.strategy_value(observation, "management_trainee", profile, early_income_analysis)
	if not is_equal_approx(float(early_management_payload.get("placement_route_value", -1.0)), 0.0):
		return Result.failure("StrategyEmployeePlanner should keep early management trainee house route value at zero: %s" % str(early_management_payload))
	var management_macro := MacroAction.create(
		"recruit_management_for_houses",
		[Command.create("recruit", 0, {"employee_type": "management_trainee"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var kitchen_macro := MacroAction.create(
		"recruit_kitchen",
		[Command.create("recruit", 0, {"employee_type": "kitchen_trainee"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var management_score: Dictionary = StrategyScorerClass.score_macro(observation, management_macro, profile)
	var kitchen_score: Dictionary = StrategyScorerClass.score_macro(observation, kitchen_macro, profile)
	if float(management_score.get("score", 0.0)) >= float(kitchen_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should not push house route over core income before surplus economy: management=%s kitchen=%s" % [str(management_score), str(kitchen_score)])
	var features: Dictionary = Dictionary(management_score.get("features", {}))
	if not is_equal_approx(float(features.get("recruit_placement_route_value", -1.0)), 0.0):
		return Result.failure("early management trainee should not expose recruit_placement_route_value: %s" % str(features))
	if int(features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("early management trainee should expose zero desired count: %s" % str(features))
	var ready_observation := _synthetic_house_growth_observation()
	ready_observation.own_player["cash"] = 50
	ready_observation.own_player["employees"] = ["burger_cook", "marketing_trainee"]
	ready_observation.own_player["inventory"] = {"burger": 5}
	_set_observation_house_demand_count(ready_observation, "house_near", "burger", 5)
	var ready_income_analysis := StrategyIncomeAnalyzerClass.analyze(ready_observation, profile)
	var ready_management_payload: Dictionary = StrategyEmployeePlannerClass.strategy_value(ready_observation, "management_trainee", profile, ready_income_analysis)
	if float(ready_management_payload.get("placement_route_value", 0.0)) <= 0.0:
		return Result.failure("StrategyEmployeePlanner should expose positive late management trainee house route value: %s" % str(ready_management_payload))
	var ready_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, management_macro, profile)
	var ready_features: Dictionary = Dictionary(ready_score.get("features", {}))
	if float(ready_features.get("recruit_placement_route_value", 0.0)) <= 0.0:
		return Result.failure("late management trainee should expose positive recruit_placement_route_value: %s" % str(ready_features))
	if int(ready_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("late management trainee should expose desired count 1: %s" % str(ready_features))
	var pre_demand := _synthetic_house_growth_observation()
	pre_demand.own_player["cash"] = 0
	var houses: Dictionary = Dictionary(pre_demand.map_public.get("houses", {})).duplicate(true)
	var house_near: Dictionary = Dictionary(houses.get("house_near", {})).duplicate(true)
	house_near["demands"] = []
	houses["house_near"] = house_near
	pre_demand.map_public["houses"] = houses
	var marketing_macro := MacroAction.create(
		"recruit_marketing_before_salary_route",
		[Command.create("recruit", 0, {"employee_type": "marketing_trainee"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var pre_demand_management_score: Dictionary = StrategyScorerClass.score_macro(pre_demand, management_macro, profile)
	var pre_demand_marketing_score: Dictionary = StrategyScorerClass.score_macro(pre_demand, marketing_macro, profile)
	if float(pre_demand_management_score.get("score", 0.0)) >= float(pre_demand_marketing_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should build marketing demand before early salaried house route: management=%s marketing=%s" % [str(pre_demand_management_score), str(pre_demand_marketing_score)])
	var no_growth := _synthetic_house_growth_observation()
	no_growth.map_public["house_number_supply_remaining"] = []
	no_growth.map_public["garden_supply_remaining"] = 0
	var no_growth_score: Dictionary = StrategyScorerClass.score_macro(no_growth, management_macro, profile)
	var no_growth_features: Dictionary = Dictionary(no_growth_score.get("features", {}))
	if not is_equal_approx(float(no_growth_features.get("recruit_placement_route_value", -1.0)), 0.0):
		return Result.failure("management trainee should not expose house route value without house/garden growth space: %s" % str(no_growth_features))
	return Result.success()

static func _test_train_score_values_house_placement_route(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_house_growth_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_TRAIN
	observation.own_player["employees"] = ["trainer"]
	observation.own_player["reserve_employees"] = ["management_trainee"]
	var early_income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile)
	var early_nbd_readiness := StrategyEmployeePlannerClass.placement_route_readiness_adjustment(observation, "new_business_developer", early_income_analysis)
	if early_nbd_readiness >= 0.0:
		return Result.failure("StrategyEmployeePlanner should penalize early NBD route readiness: %s" % str(early_nbd_readiness))
	var nbd_macro := MacroAction.create(
		"train_management_to_new_business",
		[Command.create("train", 0, {"from_employee": "management_trainee", "to_employee": "new_business_developer"})],
		0.0,
		["working", "train"],
		{}
	)
	var jvp_macro := MacroAction.create(
		"train_management_to_jvp",
		[Command.create("train", 0, {"from_employee": "management_trainee", "to_employee": "junior_vice_president"})],
		0.0,
		["working", "train"],
		{}
	)
	var nbd_score: Dictionary = StrategyScorerClass.score_macro(observation, nbd_macro, profile)
	var nbd_features: Dictionary = Dictionary(nbd_score.get("features", {}))
	if not is_equal_approx(float(nbd_features.get("train_placement_route_value", -1.0)), 0.0):
		return Result.failure("early NBD training should not expose train_placement_route_value: %s" % str(nbd_features))
	if float(nbd_features.get("train_route_readiness_adjustment", 0.0)) >= 0.0:
		return Result.failure("early NBD training should carry negative route readiness adjustment: %s" % str(nbd_features))
	var ready_observation := _synthetic_house_growth_observation()
	ready_observation.phase = DefsClass.PHASE_WORKING
	ready_observation.sub_phase = DefsClass.SUB_PHASE_TRAIN
	ready_observation.own_player["cash"] = 50
	ready_observation.own_player["employees"] = ["trainer", "burger_cook", "marketing_trainee"]
	ready_observation.own_player["reserve_employees"] = ["management_trainee"]
	ready_observation.own_player["inventory"] = {"burger": 5}
	_set_observation_house_demand_count(ready_observation, "house_near", "burger", 5)
	var ready_income_analysis := StrategyIncomeAnalyzerClass.analyze(ready_observation, profile)
	var ready_nbd_route_value := StrategyEmployeePlannerClass.placement_route_value(ready_observation, "new_business_developer", ready_income_analysis)
	if ready_nbd_route_value <= 0.0:
		return Result.failure("StrategyEmployeePlanner should expose positive ready NBD route value: %s" % str(ready_nbd_route_value))
	var ready_nbd_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, nbd_macro, profile)
	var jvp_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, jvp_macro, profile)
	if float(ready_nbd_score.get("score", 0.0)) <= float(jvp_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer NBD training only after surplus economy is ready: nbd=%s jvp=%s" % [str(ready_nbd_score), str(jvp_score)])
	var ready_nbd_features: Dictionary = Dictionary(ready_nbd_score.get("features", {}))
	if float(ready_nbd_features.get("train_placement_route_value", 0.0)) <= 0.0:
		return Result.failure("late NBD training should expose positive train_placement_route_value: %s" % str(ready_nbd_features))
	var jvp_features: Dictionary = Dictionary(jvp_score.get("features", {}))
	if not is_equal_approx(float(jvp_features.get("train_placement_route_value", -1.0)), 0.0):
		return Result.failure("non-placement training should not expose placement route value: %s" % str(jvp_features))
	return Result.success()

static func _test_structure_score_values_reserve_new_business_developer(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_house_growth_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["cash"] = 20
	observation.own_player["employees"] = ["trainer", "kitchen_trainee", "marketing_trainee"]
	observation.own_player["reserve_employees"] = ["new_business_developer"]
	var nbd_macro := MacroAction.create(
		"structure_new_business_developer",
		[Command.create("set_company_structure_direct", 0, {"employee_id": "new_business_developer"})],
		0.0,
		["restructuring"],
		{}
	)
	var kitchen_macro := MacroAction.create(
		"structure_kitchen_trainee",
		[Command.create("set_company_structure_direct", 0, {"employee_id": "kitchen_trainee"})],
		0.0,
		["restructuring"],
		{}
	)
	var nbd_score: Dictionary = StrategyScorerClass.score_macro(observation, nbd_macro, profile)
	var kitchen_score: Dictionary = StrategyScorerClass.score_macro(observation, kitchen_macro, profile)
	if float(nbd_score.get("score", 0.0)) >= float(kitchen_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should not activate reserve NBD before house growth is ready: nbd=%s kitchen=%s" % [str(nbd_score), str(kitchen_score)])
	var early_features: Dictionary = Dictionary(nbd_score.get("features", {}))
	if float(early_features.get("structure_route_readiness_adjustment", 0.0)) >= 0.0:
		return Result.failure("early reserve NBD structure should carry negative route readiness adjustment: %s" % str(early_features))

	var ready_observation := _synthetic_house_growth_observation()
	ready_observation.phase = DefsClass.PHASE_RESTRUCTURING
	ready_observation.sub_phase = ""
	ready_observation.own_player["cash"] = 50
	ready_observation.own_player["employees"] = ["trainer", "kitchen_trainee", "marketing_trainee"]
	ready_observation.own_player["reserve_employees"] = ["new_business_developer"]
	ready_observation.own_player["inventory"] = {"burger": 5}
	_set_observation_house_demand_count(ready_observation, "house_near", "burger", 5)
	var ready_nbd_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, nbd_macro, profile)
	var ready_kitchen_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, kitchen_macro, profile)
	if float(ready_nbd_score.get("score", 0.0)) <= float(ready_kitchen_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should activate reserve NBD when house growth is ready: nbd=%s kitchen=%s" % [str(ready_nbd_score), str(ready_kitchen_score)])
	var features: Dictionary = Dictionary(ready_nbd_score.get("features", {}))
	if float(features.get("structure_placement_route_value", 0.0)) <= 0.0:
		return Result.failure("reserve NBD structure should expose positive structure_placement_route_value: %s" % str(features))
	if not is_equal_approx(float(features.get("structure_route_readiness_adjustment", -1.0)), 0.0):
		return Result.failure("ready reserve NBD structure should not carry route readiness penalty: %s" % str(features))
	return Result.success()

static func _test_structure_score_keeps_food_supply_for_marketing_pipeline(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["cash"] = 20
	observation.own_player["employees"] = ["campaign_manager"]
	observation.own_player["reserve_employees"] = ["kitchen_trainee", "errand_boy"]
	observation.own_player["inventory"] = {}
	_set_observation_house_demand_count(observation, "house_near", "burger", 0)
	var kitchen_macro := MacroAction.create(
		"structure_kitchen_for_marketing",
		[Command.create("set_company_structure_direct", 0, {"employee_id": "kitchen_trainee"})],
		0.0,
		["restructuring"],
		{}
	)
	var errand_macro := MacroAction.create(
		"structure_errand_without_food",
		[Command.create("set_company_structure_direct", 0, {"employee_id": "errand_boy"})],
		0.0,
		["restructuring"],
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
		return Result.failure("StrategyScorer should keep food supply active for owned marketing pipeline: kitchen=%s errand=%s" % [str(kitchen_score), str(errand_score)])
	var errand_features: Dictionary = Dictionary(errand_score.get("features", {}))
	if float(errand_features.get("structure_drink_route_readiness_adjustment", 0.0)) > -100.0:
		return Result.failure("StrategyScorer should penalize activating drink supply without actionable drink demand: %s" % str(errand_features))
	if float(kitchen_score.get("score", 0.0)) <= float(submit_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should not submit restructuring before activating food supply for marketing: kitchen=%s submit=%s" % [str(kitchen_score), str(submit_score)])
	var features: Dictionary = Dictionary(kitchen_score.get("features", {}))
	if float(features.get("structure_activation_value", 0.0)) <= 0.0:
		return Result.failure("food supply structure should expose structure_activation_value: %s" % str(features))
	var marketing_products: Array = Array(features.get("structure_marketing_supply_products", []))
	if not marketing_products.has("burger"):
		return Result.failure("food supply structure should expose burger marketing supply product: %s" % str(features))
	return Result.success()

static func _test_candidate_generation_keeps_trainable_food_supply_available(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var observation := _synthetic_income_observation()
	observation.phase = DefsClass.PHASE_RESTRUCTURING
	observation.sub_phase = ""
	observation.own_player["employees"] = ["trainer", "campaign_manager"]
	observation.own_player["reserve_employees"] = ["burger_cook", "errand_boy"]
	observation.own_player["inventory"] = {}
	observation.own_player["company_structure"] = {
		"ceo_slots": 3,
		"structure": [{}, {}, {}],
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
	return Result.failure("CandidateGenerator should not hide trainable burger cook when current food demand needs active supply: %s" % str(candidate_ids))

static func _test_fridge_keep_prioritizes_serviceable_demand(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var observation := _synthetic_fridge_observation()
	var keep: Dictionary = StrategyIncomeAnalyzerClass.build_fridge_keep(observation, 3)
	if int(keep.get("burger", 0)) != 2:
		return Result.failure("fridge keep should preserve all serviceable burger demand before excess inventory: %s" % str(keep))
	if int(keep.get("soda", 0)) != 1:
		return Result.failure("fridge keep should use remaining capacity deterministically after serviceable demand: %s" % str(keep))
	return Result.success()

static func _test_strategy_scoring_targets_current_product_gap(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	var burger_macro := MacroAction.create(
		"produce_burger_gap",
		[Command.create("produce_food", 0, {"employee_type": "burger_cook", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var pizza_macro := MacroAction.create(
		"produce_pizza_no_gap",
		[Command.create("produce_food", 0, {"employee_type": "pizza_cook", "food_type": "pizza"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var burger_score: Dictionary = StrategyScorerClass.score_macro(observation, burger_macro, profile)
	var pizza_score: Dictionary = StrategyScorerClass.score_macro(observation, pizza_macro, profile)
	if float(burger_score.get("score", 0.0)) <= float(pizza_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer product with serviceable demand gap: burger=%s pizza=%s" % [str(burger_score), str(pizza_score)])
	var features: Dictionary = Dictionary(burger_score.get("features", {}))
	if int(features.get("product_inventory_gap", 0)) != 2:
		return Result.failure("StrategyScorer should expose product_inventory_gap: %s" % str(features))
	if int(features.get("product_serviceable_demand", 0)) != 2:
		return Result.failure("StrategyScorer should expose product_serviceable_demand: %s" % str(features))
	return Result.success()

static func _test_strategy_scoring_values_supply_amount(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	var houses: Dictionary = Dictionary(observation.map_public.get("houses", {}))
	var house_near: Dictionary = Dictionary(houses.get("house_near", {}))
	house_near["demands"] = [
		{"product": "burger"},
		{"product": "burger"},
		{"product": "burger"},
		{"product": "burger"},
		{"product": "burger"},
		{"product": "burger"},
	]
	houses["house_near"] = house_near
	observation.map_public["houses"] = houses
	var cook_macro := MacroAction.create(
		"produce_burger_cook",
		[Command.create("produce_food", 0, {"employee_type": "burger_cook", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var chef_macro := MacroAction.create(
		"produce_burger_chef",
		[Command.create("produce_food", 0, {"employee_type": "burger_chef", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile)
	var chef_payload: Dictionary = StrategySupplyPlannerClass.evaluate_action(
		observation,
		Command.create("produce_food", 0, {"employee_type": "burger_chef", "food_type": "burger"}),
		profile,
		income_analysis
	)
	var chef_payload_features: Dictionary = Dictionary(chef_payload.get("features", {}))
	if int(chef_payload_features.get("product_supply_expected_units", 0)) != 8:
		return Result.failure("StrategySupplyPlanner evaluate_action should expose expected production amount 8: %s" % str(chef_payload))
	if int(chef_payload_features.get("product_supply_covered_units", 0)) != 6:
		return Result.failure("StrategySupplyPlanner evaluate_action should cap covered units by current gap: %s" % str(chef_payload))
	if float(chef_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategySupplyPlanner evaluate_action should value large covered food gap: %s" % str(chef_payload))
	var cook_score: Dictionary = StrategyScorerClass.score_macro(observation, cook_macro, profile)
	var chef_score: Dictionary = StrategyScorerClass.score_macro(observation, chef_macro, profile)
	if float(chef_score.get("score", 0.0)) <= float(cook_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should value higher production amount when inventory gap is large: chef=%s cook=%s" % [str(chef_score), str(cook_score)])
	var chef_features: Dictionary = Dictionary(chef_score.get("features", {}))
	if int(chef_features.get("product_supply_expected_units", 0)) != 8:
		return Result.failure("burger_chef should expose expected production amount 8: %s" % str(chef_features))
	if int(chef_features.get("product_supply_covered_units", 0)) != 6:
		return Result.failure("burger_chef should cap covered units by current gap: %s" % str(chef_features))
	return Result.success()

static func _test_strategy_scoring_values_route_drink_products(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_drink_route_observation()
	var soda_macro := MacroAction.create(
		"procure_route_soda",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [4, 2]], "selected_sources": [[4, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var beer_macro := MacroAction.create(
		"procure_route_beer",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [8, 2]], "selected_sources": [[8, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var soda_score: Dictionary = StrategyScorerClass.score_macro(observation, soda_macro, profile)
	var beer_score: Dictionary = StrategyScorerClass.score_macro(observation, beer_macro, profile)
	if float(soda_score.get("score", 0.0)) <= float(beer_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer route drinks matching current demand: soda=%s beer=%s" % [str(soda_score), str(beer_score)])
	var features: Dictionary = Dictionary(soda_score.get("features", {}))
	var expected_by_product: Dictionary = Dictionary(features.get("drink_route_expected_units_by_product", {}))
	if int(expected_by_product.get("soda", 0)) != 2:
		return Result.failure("route drink scoring should infer soda units from selected source: %s" % str(features))
	if str(features.get("product_supply_primary_product", "")) != "soda":
		return Result.failure("route drink scoring should expose primary product: %s" % str(features))
	if int(features.get("product_supply_covered_units", 0)) != 2:
		return Result.failure("route drink scoring should count covered drink demand: %s" % str(features))
	return Result.success()

static func _test_strategy_scoring_values_pending_marketing_supply(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
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
		return Result.failure("pending marketing supply should expose product_pending_marketing_demand: %s" % str(beer_features))
	if int(beer_features.get("product_planning_inventory_gap", 0)) != 1:
		return Result.failure("pending marketing supply should expose product_planning_inventory_gap: %s" % str(beer_features))
	if not bool(beer_features.get("product_pending_marketing_supply_deferred", false)):
		return Result.failure("pending marketing supply should be deferred without fridge: %s" % str(beer_features))
	if int(beer_features.get("product_supply_future_covered_units", 0)) != 0:
		return Result.failure("pending marketing supply should not count future covered units without fridge: %s" % str(beer_features))
	if int(beer_features.get("product_effective_pending_marketing_demand", -1)) != 0:
		return Result.failure("pending marketing supply should have effective pending demand 0 without fridge: %s" % str(beer_features))

	var fridge_observation := _synthetic_drink_route_observation()
	_set_observation_house_demand_count(fridge_observation, "house_near", "soda", 0)
	fridge_observation.own_player["milestones"] = ["first_throw_away"]
	fridge_observation.marketing_instances_public = [
		{"owner": 0, "product": "beer", "remaining_duration": 2},
	]
	var soda_macro := MacroAction.create(
		"procure_route_soda_without_pending",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [4, 2]], "selected_sources": [[4, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var fridge_beer_score: Dictionary = StrategyScorerClass.score_macro(fridge_observation, beer_macro, profile)
	var soda_score: Dictionary = StrategyScorerClass.score_macro(fridge_observation, soda_macro, profile)
	if float(fridge_beer_score.get("score", 0.0)) <= float(soda_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should procure drinks matching pending own marketing when fridge can preserve it: beer=%s soda=%s" % [str(fridge_beer_score), str(soda_score)])
	var fridge_beer_features: Dictionary = Dictionary(fridge_beer_score.get("features", {}))
	if int(fridge_beer_features.get("product_supply_future_covered_units", 0)) != 1:
		return Result.failure("pending marketing supply should count future covered units with fridge: %s" % str(fridge_beer_features))
	if int(fridge_beer_features.get("product_effective_pending_marketing_demand", 0)) != 1:
		return Result.failure("pending marketing supply should have effective pending demand 1 with fridge: %s" % str(fridge_beer_features))
	return Result.success()

static func _test_strategy_scoring_penalizes_product_overstock(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	observation.own_player["inventory"] = {"burger": 4}
	var burger_macro := MacroAction.create(
		"produce_burger_overstock",
		[Command.create("produce_food", 0, {"employee_type": "burger_cook", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_get_food",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var burger_score: Dictionary = StrategyScorerClass.score_macro(observation, burger_macro, profile)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile)
	if float(burger_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer skipping over overstock production: burger=%s skip=%s" % [str(burger_score), str(skip_score)])
	var features: Dictionary = Dictionary(burger_score.get("features", {}))
	if int(features.get("product_inventory_gap", -1)) != 0:
		return Result.failure("overstock production should expose zero product_inventory_gap: %s" % str(features))
	if not bool(features.get("product_overstock_penalty", false)):
		return Result.failure("overstock production should expose product_overstock_penalty: %s" % str(features))
	return Result.success()

static func _test_strategy_scoring_skips_no_demand_food_when_cash_unsafe(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var base_profile = StrategyProfileClass.new()
	base_profile.configure_base_revenue()
	var base_check := _assert_strategy_scoring_skips_no_demand_food_when_cash_unsafe_for_profile(base_profile, "base_revenue_v1")
	if not base_check.ok:
		return base_check
	var growth_profile = StrategyProfileClass.new()
	var growth_config := growth_profile.configure("base_revenue_growth_v1")
	if not growth_config.ok:
		return Result.failure("configure base_revenue_growth_v1 failed: %s" % growth_config.error)
	return _assert_strategy_scoring_skips_no_demand_food_when_cash_unsafe_for_profile(growth_profile, "base_revenue_growth_v1")

static func _assert_strategy_scoring_skips_no_demand_food_when_cash_unsafe_for_profile(profile, profile_label: String) -> Result:
	var observation := _synthetic_income_observation()
	observation.rules_public = {"salary_cost": 5}
	observation.own_player["cash"] = 0
	observation.own_player["employees"] = ["kitchen_trainee"]
	observation.own_player["inventory"] = {}
	observation.milestone_pool_public = ["first_burger_produced"]
	var houses: Dictionary = Dictionary(observation.map_public.get("houses", {})).duplicate(true)
	var house_near: Dictionary = Dictionary(houses.get("house_near", {})).duplicate(true)
	house_near["demands"] = []
	houses["house_near"] = house_near
	observation.map_public["houses"] = houses
	var burger_macro := MacroAction.create(
		"produce_no_demand_burger",
		[Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_get_food",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var burger_score: Dictionary = StrategyScorerClass.score_macro(observation, burger_macro, profile)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile)
	if float(burger_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip no-demand food production when cash cannot keep the milestone cook for %s: burger=%s skip=%s" % [profile_label, str(burger_score), str(skip_score)])
	var features: Dictionary = Dictionary(burger_score.get("features", {}))
	if float(features.get("product_no_demand_cash_safety_penalty", 0.0)) >= 0.0:
		return Result.failure("no-demand unsafe food production should expose cash safety penalty for %s: %s" % [profile_label, str(features)])
	if not bool(features.get("milestone_race_suppressed_no_demand_supply", false)):
		return Result.failure("no-demand unsafe food production should suppress supply milestone race for %s: %s" % [profile_label, str(features)])
	if not is_equal_approx(float(features.get("milestone_race_value", -1.0)), 0.0):
		return Result.failure("no-demand unsafe food production should not score supply milestone race for %s: %s" % [profile_label, str(features)])
	if str(features.get("strategy_precondition_failed", "")) != "supply_should_be_deferred":
		return Result.failure("no-demand unsafe food production should fail the supply relevance precondition for %s: %s" % [profile_label, str(features)])
	var filtered: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, [burger_macro, skip_macro], profile)
	var kept_val = filtered.get("candidates", [])
	if not (kept_val is Array):
		return Result.failure("StrategyCandidateFilter should return Array for no-demand supply test")
	var kept: Array = kept_val
	if kept.has(burger_macro) or not kept.has(skip_macro):
		return Result.failure("StrategyCandidateFilter should discard no-demand food supply and keep skip for %s: %s" % [profile_label, str(filtered)])
	var stats: Dictionary = Dictionary(filtered.get("stats", {}))
	if int(stats.get("discarded_supply_deferred", 0)) != 1:
		return Result.failure("StrategyCandidateFilter should count deferred supply discard for %s: %s" % [profile_label, str(stats)])

	var safe_observation := _synthetic_income_observation()
	safe_observation.rules_public = {"salary_cost": 5}
	safe_observation.own_player["cash"] = 20
	safe_observation.own_player["employees"] = ["kitchen_trainee"]
	safe_observation.own_player["inventory"] = {}
	safe_observation.milestone_pool_public = ["first_pizza_produced"]
	var safe_houses: Dictionary = Dictionary(safe_observation.map_public.get("houses", {})).duplicate(true)
	var safe_house_near: Dictionary = Dictionary(safe_houses.get("house_near", {})).duplicate(true)
	safe_house_near["demands"] = []
	safe_houses["house_near"] = safe_house_near
	safe_observation.map_public["houses"] = safe_houses
	var pizza_macro := MacroAction.create(
		"produce_no_demand_pizza_for_milestone",
		[Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "pizza"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var pizza_score: Dictionary = StrategyScorerClass.score_macro(safe_observation, pizza_macro, profile)
	var safe_skip_score: Dictionary = StrategyScorerClass.score_macro(safe_observation, skip_macro, profile)
	if float(pizza_score.get("score", 0.0)) >= float(safe_skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip no-demand milestone food production even when current cash is safe for %s: pizza=%s skip=%s" % [profile_label, str(pizza_score), str(safe_skip_score)])
	var pizza_features: Dictionary = Dictionary(pizza_score.get("features", {}))
	if not bool(pizza_features.get("product_no_demand_supply_deferred", false)):
		return Result.failure("safe no-demand milestone food production should expose deferred supply for %s: %s" % [profile_label, str(pizza_features)])
	if not bool(pizza_features.get("milestone_race_suppressed_no_demand_supply", false)):
		return Result.failure("safe no-demand milestone food production should suppress supply milestone race for %s: %s" % [profile_label, str(pizza_features)])
	if str(pizza_features.get("strategy_precondition_failed", "")) != "supply_should_be_deferred":
		return Result.failure("safe no-demand milestone food production should fail the supply relevance precondition for %s: %s" % [profile_label, str(pizza_features)])
	return Result.success()

static func _test_strategy_scoring_skips_no_demand_drinks_when_cash_unsafe(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	var profile_config := profile.configure("base_revenue_growth_v1")
	if not profile_config.ok:
		return Result.failure("configure base_revenue_growth_v1 failed: %s" % profile_config.error)
	var observation := _synthetic_drink_route_observation()
	observation.rules_public = {"salary_cost": 5}
	observation.own_player["cash"] = 0
	observation.own_player["employees"] = ["truck_driver"]
	observation.own_player["inventory"] = {}
	observation.milestone_pool_public = ["first_errand_boy"]
	_set_observation_house_demand_count(observation, "house_near", "soda", 0)
	var beer_macro := MacroAction.create(
		"procure_no_demand_beer",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [8, 2]], "selected_sources": [[8, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_get_drinks",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var beer_score: Dictionary = StrategyScorerClass.score_macro(observation, beer_macro, profile)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile)
	if float(beer_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip no-demand drink procurement when cash cannot cover salary: beer=%s skip=%s" % [str(beer_score), str(skip_score)])
	var features: Dictionary = Dictionary(beer_score.get("features", {}))
	if float(features.get("product_no_demand_cash_safety_penalty", 0.0)) >= 0.0:
		return Result.failure("no-demand unsafe drink procurement should expose cash safety penalty: %s" % str(features))
	if str(features.get("strategy_precondition_failed", "")) != "supply_should_be_deferred":
		return Result.failure("no-demand unsafe drink procurement should fail the supply relevance precondition: %s" % str(features))
	return Result.success()

static func _test_strategy_scoring_uses_dinner_preview_for_food_income(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "burger"}])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.players[0]["cash"] = 0
	state.players[0]["inventory"] = {}
	state.players[1]["inventory"] = {"burger": 1}
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_burger_produced"]
	var take := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take.ok:
		return Result.failure("dinner preview food test take kitchen_trainee failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "kitchen_trainee", false)
	if not add.ok:
		return Result.failure("dinner preview food test add kitchen_trainee failed: %s" % add.error)
	RoadGraphCacheClass.invalidate_road_graph(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var burger_macro := MacroAction.create(
		"produce_contested_burger",
		[Command.create("produce_food", 0, {"employee_type": "kitchen_trainee", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_get_food",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var burger_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, burger_macro, profile, {"source_engine": engine, "source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(burger_score.get("features", {}))
	if str(features.get("product_dinner_preview_source", "")) != "dinner_preview":
		return Result.failure("food scoring should use DinnerPreview when source_engine is available: score=%s features=%s" % [str(burger_score), str(features)])
	if int(features.get("product_public_demand", 0)) <= 0:
		return Result.failure("dinner preview food test should retain public burger demand: %s" % str(features))
	if int(features.get("product_dinner_preview_income", -1)) != 0:
		return Result.failure("contested production should preview zero income for player 0: %s" % str(features))
	if float(features.get("product_dinner_preview_no_income_penalty", 0.0)) >= 0.0:
		return Result.failure("zero-income unsafe production should expose DinnerPreview penalty: %s" % str(features))
	if float(burger_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer skipping contested zero-income food while cash is unsafe: burger=%s skip=%s" % [str(burger_score), str(skip_score)])
	return Result.success()

static func _test_strategy_scoring_uses_dinner_preview_for_drink_income(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "beer"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
	state.current_player_index = 0
	state.players[0]["cash"] = 0
	state.players[0]["inventory"] = {}
	state.players[1]["inventory"] = {}
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_errand_boy"]
	var take := StateUpdaterClass.take_from_pool(state, "errand_boy", 1)
	if not take.ok:
		return Result.failure("dinner preview drink test take errand_boy failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "errand_boy", false)
	if not add.ok:
		return Result.failure("dinner preview drink test add errand_boy failed: %s" % add.error)
	RoadGraphCacheClass.invalidate_road_graph(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var beer_macro := MacroAction.create(
		"procure_incomplete_order_beer",
		[Command.create("procure_drinks", 0, {"employee_type": "errand_boy", "drink_type": "beer"})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_get_drinks",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var beer_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, beer_macro, profile, {"source_engine": engine, "source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(beer_score.get("features", {}))
	if str(features.get("product_dinner_preview_source", "")) != "dinner_preview":
		return Result.failure("drink scoring should use DinnerPreview when source_engine is available: score=%s features=%s" % [str(beer_score), str(features)])
	if int(features.get("product_public_demand", 0)) <= 0:
		return Result.failure("dinner preview drink test should retain public beer demand: %s" % str(features))
	if int(features.get("product_dinner_preview_income", -1)) != 0:
		return Result.failure("incomplete-order drink procurement should preview zero income for player 0: %s" % str(features))
	if float(features.get("product_dinner_preview_no_income_penalty", 0.0)) >= 0.0:
		return Result.failure("zero-income unsafe drink procurement should expose DinnerPreview penalty: %s" % str(features))
	if float(beer_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer skipping incomplete-order drink procurement while cash is unsafe: beer=%s skip=%s" % [str(beer_score), str(skip_score)])
	return Result.success()

static func _sync_initial_checkpoint_to_current_state(engine: GameEngine) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("cannot sync checkpoint: engine/state is null")
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("cannot sync checkpoint: checkpoint[0] missing")
	var state := engine.get_state()
	var checkpoint: Dictionary = engine.checkpoints[0]
	checkpoint["state_dict"] = state.to_dict().duplicate(true)
	checkpoint["hash"] = state.compute_hash()
	engine.checkpoints[0] = checkpoint
	engine.command_history.clear()
	engine.current_command_index = -1
	var total_cash_read := InvariantsClass.compute_total_cash(state)
	if not total_cash_read.ok:
		return total_cash_read
	engine.set_initial_total_cash_for_invariants(int(total_cash_read.value))
	var employee_totals_read := InvariantsClass.compute_employee_base_totals_for_invariants(state)
	if not employee_totals_read.ok:
		return employee_totals_read
	engine.set_initial_employee_totals_for_invariants(employee_totals_read.value)
	return Result.success()

static func _test_strategy_scoring_uses_pricing_pipeline_for_price_actions(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	state.round_state["price_modifiers"] = {
		0: {"existing_discount": -2},
	}
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	observation.own_player["inventory"] = {"burger": 2}
	var discount_macro := MacroAction.create(
		"set_discount_with_existing_modifier",
		[Command.create("set_discount", 0, {})],
		0.0,
		["working", "price"],
		{}
	)
	var score: Dictionary = StrategyScorerClass.score_macro(observation, discount_macro, profile, {"source_state": state})
	var features: Dictionary = Dictionary(score.get("features", {}))
	if str(features.get("price_source", "")) != "pricing_pipeline":
		return Result.failure("price action scoring should use PricingPipeline when source_state is available: %s" % str(features))
	if int(features.get("price_current_unit_price", 0)) != 8:
		return Result.failure("price action scoring should include existing round_state.price_modifiers via PricingPipeline: %s" % str(features))
	if int(features.get("price_action_delta", 0)) != -3:
		return Result.failure("set_discount should expose -3 price delta: %s" % str(features))
	if int(features.get("price_projected_unit_price", 0)) != 5:
		return Result.failure("set_discount should project unit price after action delta: %s" % str(features))
	if int(features.get("price_round_modifier_total", 0)) != -2:
		return Result.failure("price action scoring should expose current round modifier total: %s" % str(features))
	if int(features.get("price_estimated_sale_units", 0)) != 2:
		return Result.failure("price action scoring should estimate sale units from serviceable stocked demand: %s" % str(features))
	return Result.success()

static func _test_strategy_scoring_values_key_milestone_race(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_TRAIN
	observation.milestone_pool_public = ["first_train", "first_burger_produced"]
	observation.own_player["milestones"] = []
	var train_macro := MacroAction.create(
		"train_management_to_trainer",
		[Command.create("train", 0, {"from_employee": "management_trainee", "to_employee": "trainer"})],
		0.0,
		["working", "train"],
		{}
	)
	var train_score: Dictionary = StrategyScorerClass.score_macro(observation, train_macro, profile)
	var train_features: Dictionary = Dictionary(train_score.get("features", {}))
	if float(train_features.get("milestone_race_value", 0.0)) <= 0.0:
		return Result.failure("train score should value first_train race: %s" % str(train_score))
	if not Array(train_features.get("milestone_race_ids", [])).has("first_train"):
		return Result.failure("train score should expose first_train race id: %s" % str(train_features))
	var tuned_profile = StrategyProfileClass.new()
	tuned_profile.configure_base_revenue()
	tuned_profile.milestone_priorities["first_train"] = 1.0
	tuned_profile.milestone_effect_weights["gain_card"] = 0.0
	var tuned_score: Dictionary = StrategyScorerClass.score_macro(observation, train_macro, tuned_profile)
	var tuned_features: Dictionary = Dictionary(tuned_score.get("features", {}))
	if float(tuned_features.get("milestone_race_value", 0.0)) >= float(train_features.get("milestone_race_value", 0.0)):
		return Result.failure("milestone race value should respond to profile weights: base=%s tuned=%s" % [str(train_features), str(tuned_features)])
	var claimed_observation := _synthetic_income_observation()
	claimed_observation.phase = DefsClass.PHASE_WORKING
	claimed_observation.sub_phase = DefsClass.SUB_PHASE_TRAIN
	claimed_observation.milestone_pool_public = ["first_train"]
	claimed_observation.own_player["milestones"] = ["first_train"]
	var claimed_score: Dictionary = StrategyScorerClass.score_macro(claimed_observation, train_macro, profile)
	var claimed_features: Dictionary = Dictionary(claimed_score.get("features", {}))
	if float(claimed_features.get("milestone_race_value", 0.0)) != 0.0:
		return Result.failure("owned milestone should not score race value: %s" % str(claimed_score))
	var burger_macro := MacroAction.create(
		"produce_burger",
		[Command.create("produce_food", 0, {"employee_type": "burger_cook", "food_type": "burger"})],
		0.0,
		["working", "get_food"],
		{}
	)
	var burger_score: Dictionary = StrategyScorerClass.score_macro(observation, burger_macro, profile)
	var burger_features: Dictionary = Dictionary(burger_score.get("features", {}))
	if not Array(burger_features.get("milestone_race_ids", [])).has("first_burger_produced"):
		return Result.failure("burger production should expose first_burger_produced race id: %s" % str(burger_features))
	return Result.success()

static func _test_restaurant_placement_prefers_near_public_demand(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_restaurant_observation()
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile)
	var near_payload: Dictionary = StrategyBoardAnalyzerClass.restaurant_action_value(
		observation,
		{"position": [3, 2], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		0
	)
	var far_payload: Dictionary = StrategyBoardAnalyzerClass.restaurant_action_value(
		observation,
		{"position": [11, 11], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		0
	)
	if float(near_payload.get("restaurant_value", 0.0)) <= float(far_payload.get("restaurant_value", 0.0)):
		return Result.failure("StrategyBoardAnalyzer should prefer restaurant placement near public demand: near=%s far=%s" % [str(near_payload), str(far_payload)])
	if float(near_payload.get("restaurant_base_value", 0.0)) <= 0.0:
		return Result.failure("StrategyBoardAnalyzer should expose restaurant base value: %s" % str(near_payload))
	var near_action_payload: Dictionary = StrategyBoardAnalyzerClass.evaluate_restaurant_action(
		observation,
		{"position": [3, 2], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		0
	)
	var near_action_features: Dictionary = Dictionary(near_action_payload.get("features", {}))
	if float(near_action_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategyBoardAnalyzer restaurant action should expose positive value: %s" % str(near_action_payload))
	if float(near_action_features.get("restaurant_base_value", 0.0)) <= 0.0:
		return Result.failure("StrategyBoardAnalyzer restaurant action should expose base value: %s" % str(near_action_payload))
	var near_macro := MacroAction.create(
		"place_restaurant_near_demand",
		[Command.create("place_restaurant", 0, {"position": [3, 2], "rotation": 0})],
		0.0,
		["setup", "restaurant"],
		{}
	)
	var far_macro := MacroAction.create(
		"place_restaurant_far_demand",
		[Command.create("place_restaurant", 0, {"position": [11, 11], "rotation": 0})],
		0.0,
		["setup", "restaurant"],
		{}
	)
	var near_score: Dictionary = StrategyScorerClass.score_macro(observation, near_macro, profile)
	var far_score: Dictionary = StrategyScorerClass.score_macro(observation, far_macro, profile)
	if float(near_score.get("score", 0.0)) <= float(far_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer restaurant placement near public demand: near=%s far=%s" % [str(near_score), str(far_score)])
	var features: Dictionary = Dictionary(near_score.get("features", {}))
	if float(features.get("restaurant_base_value", 0.0)) <= 0.0:
		return Result.failure("restaurant placement features should expose base value: %s" % str(features))
	if int(features.get("restaurant_nearby_demand", 0)) <= 0:
		return Result.failure("restaurant placement features should expose nearby demand: %s" % str(features))
	if int(features.get("restaurant_nearest_house_distance", -1)) > 2:
		return Result.failure("restaurant placement features should expose near house distance: %s" % str(features))
	return Result.success()

static func _test_restaurant_placement_uses_source_road_graph(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	RoadGraphCacheClass.invalidate_road_graph(state)
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var place_macro := MacroAction.create(
		"place_restaurant_road_graph",
		[Command.create("place_restaurant", 0, {"position": [3, 3], "rotation": 0})],
		0.0,
		["working", "restaurant"],
		{}
	)
	var place_score: Dictionary = StrategyScorerClass.score_macro(observation, place_macro, profile, {"source_state": state})
	var place_features: Dictionary = Dictionary(place_score.get("features", {}))
	if str(place_features.get("restaurant_distance_source", "")) != "road_graph":
		return Result.failure("StrategyScorer should use source road graph for place_restaurant: %s" % str(place_features))
	if int(place_features.get("restaurant_nearby_demand", 0)) <= 0:
		return Result.failure("road graph restaurant placement should expose nearby demand: %s" % str(place_features))
	if int(place_features.get("restaurant_nearest_house_distance", -1)) < 0:
		return Result.failure("road graph restaurant placement should expose nearest distance: %s" % str(place_features))

	var move_macro := MacroAction.create(
		"move_restaurant_road_graph",
		[Command.create("move_restaurant", 0, {"restaurant_id": "rest_0", "position": [3, 3], "rotation": 0})],
		0.0,
		["working", "move_restaurant"],
		{}
	)
	var move_score: Dictionary = StrategyScorerClass.score_macro(observation, move_macro, profile, {"source_state": state})
	var move_features: Dictionary = Dictionary(move_score.get("features", {}))
	if str(move_features.get("restaurant_distance_source", "")) != "road_graph":
		return Result.failure("StrategyScorer should use source road graph for move_restaurant: %s" % str(move_features))
	if int(move_features.get("restaurant_nearby_demand", 0)) <= 0:
		return Result.failure("road graph restaurant move should expose nearby demand: %s" % str(move_features))
	return Result.success()

static func _test_restaurant_placement_penalizes_competitor_dominated_houses(_seed_val: int) -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := ObservationState.new()
	observation.viewer_player_id = 1
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_SETUP
	observation.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	observation.own_player = {
		"id": 1,
		"cash": 20,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"inventory": {},
	}
	observation.map_public = {
		"grid_size": Vector2i(12, 12),
		"houses": {
			"dominated_1": {
				"house_number": 1,
				"anchor_pos": Vector2i(5, 5),
				"demands": [{"product": "burger"}],
			},
			"dominated_2": {
				"house_number": 2,
				"anchor_pos": Vector2i(5, 6),
				"demands": [{"product": "burger"}],
			},
			"competitive_1": {
				"house_number": 3,
				"anchor_pos": Vector2i(10, 5),
				"demands": [{"product": "burger"}],
			},
		},
		"restaurants": {
			"opponent_restaurant": {
				"restaurant_id": "opponent_restaurant",
				"owner": 0,
				"anchor_pos": Vector2i(5, 4),
			},
		},
	}
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile)
	var dominated_payload: Dictionary = StrategyBoardAnalyzerClass.restaurant_action_value(
		observation,
		{"position": [5, 9], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		1
	)
	var competitive_payload: Dictionary = StrategyBoardAnalyzerClass.restaurant_action_value(
		observation,
		{"position": [10, 6], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		1
	)
	if float(dominated_payload.get("restaurant_value", 0.0)) >= float(competitive_payload.get("restaurant_value", 0.0)):
		return Result.failure("restaurant placement should prefer fewer competitive houses over more opponent-dominated houses: dominated=%s competitive=%s" % [str(dominated_payload), str(competitive_payload)])
	var dominated_action: Dictionary = StrategyBoardAnalyzerClass.evaluate_restaurant_action(
		observation,
		{"position": [5, 9], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		1
	)
	var dominated_features: Dictionary = Dictionary(dominated_action.get("features", {}))
	if int(dominated_features.get("restaurant_competitor_dominated_houses", 0)) < 2:
		return Result.failure("dominated restaurant placement should expose dominated houses: %s" % str(dominated_features))
	if int(dominated_features.get("restaurant_nearby_demand", -1)) != 0:
		return Result.failure("dominated restaurant placement should not count opponent-won demand as nearby demand: %s" % str(dominated_features))
	if float(dominated_features.get("restaurant_competition_penalty", 0.0)) >= 0.0:
		return Result.failure("dominated restaurant placement should expose negative competition penalty: %s" % str(dominated_features))
	var competitive_action: Dictionary = StrategyBoardAnalyzerClass.evaluate_restaurant_action(
		observation,
		{"position": [10, 6], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		1
	)
	var competitive_features: Dictionary = Dictionary(competitive_action.get("features", {}))
	if int(competitive_features.get("restaurant_competitive_houses", 0)) <= 0:
		return Result.failure("competitive restaurant placement should expose competitive houses: %s" % str(competitive_features))
	return Result.success()

static func _test_initial_restaurant_placement_penalizes_contested_opening_lane() -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := ObservationState.new()
	observation.viewer_player_id = 1
	observation.round_number = 0
	observation.phase = DefsClass.PHASE_SETUP
	observation.sub_phase = ""
	observation.own_player = {
		"id": 1,
		"cash": 0,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"inventory": {},
	}
	observation.map_public = {
		"grid_size": Vector2i(16, 16),
		"houses": {
			"contested_opening_house": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [],
			},
			"independent_opening_house": {
				"house_number": 2,
				"anchor_pos": Vector2i(12, 12),
				"demands": [],
			},
		},
		"restaurants": {
			"opponent_restaurant": {
				"restaurant_id": "opponent_restaurant",
				"owner": 0,
				"anchor_pos": Vector2i(2, 1),
			},
		},
	}
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile)
	var contested_payload: Dictionary = StrategyBoardAnalyzerClass.restaurant_action_value(
		observation,
		{"position": [2, 3], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		1
	)
	var independent_payload: Dictionary = StrategyBoardAnalyzerClass.restaurant_action_value(
		observation,
		{"position": [12, 11], "rotation": 0},
		income_analysis,
		null,
		"place_restaurant",
		1
	)
	if float(independent_payload.get("restaurant_value", 0.0)) <= float(contested_payload.get("restaurant_value", 0.0)):
		return Result.failure("initial restaurant should prefer independent opening lane over contested tie: independent=%s contested=%s" % [str(independent_payload), str(contested_payload)])
	if float(contested_payload.get("opening_competition_safety_penalty", 0.0)) >= 0.0:
		return Result.failure("contested opening should expose safety penalty: %s" % str(contested_payload))
	return Result.success()

static func _test_initial_restaurant_placement_values_opening_robustness(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	RoadGraphCacheClass.invalidate_road_graph(state)
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

	var edge_macro := MacroAction.create(
		"initial_restaurant_edge",
		[Command.create("place_restaurant", 0, {"position": [0, 3], "rotation": 0})],
		0.0,
		["setup", "restaurant"],
		{}
	)
	var near_edge_macro := MacroAction.create(
		"initial_restaurant_near_edge_cluster",
		[Command.create("place_restaurant", 0, {"position": [4, 1], "rotation": 180})],
		0.0,
		["setup", "restaurant"],
		{}
	)
	var robust_macro := MacroAction.create(
		"initial_restaurant_robust",
		[Command.create("place_restaurant", 0, {"position": [6, 8], "rotation": 90})],
		0.0,
		["setup", "restaurant"],
		{}
	)
	var edge_score: Dictionary = StrategyScorerClass.score_macro(observation, edge_macro, profile, {"source_state": state})
	var near_edge_score: Dictionary = StrategyScorerClass.score_macro(observation, near_edge_macro, profile, {"source_state": state})
	var robust_score: Dictionary = StrategyScorerClass.score_macro(observation, robust_macro, profile, {"source_state": state})
	if float(robust_score.get("score", 0.0)) <= float(edge_score.get("score", 0.0)):
		return Result.failure("initial restaurant should prefer robust marketing-capable opening over edge cluster: robust=%s edge=%s" % [str(robust_score), str(edge_score)])
	if float(robust_score.get("score", 0.0)) <= float(near_edge_score.get("score", 0.0)):
		return Result.failure("initial restaurant should prefer robust marketing-capable opening over near-edge cluster: robust=%s near_edge=%s" % [str(robust_score), str(near_edge_score)])
	var robust_features: Dictionary = Dictionary(robust_score.get("features", {}))
	var edge_features: Dictionary = Dictionary(edge_score.get("features", {}))
	if float(robust_features.get("restaurant_opening_robustness_value", 0.0)) <= float(edge_features.get("restaurant_opening_robustness_value", 0.0)):
		return Result.failure("opening robustness should favor central candidate: robust=%s edge=%s" % [str(robust_features), str(edge_features)])
	if int(edge_features.get("restaurant_opening_edge_distance", -1)) != 0:
		return Result.failure("edge candidate should expose edge distance 0: %s" % str(edge_features))
	if int(robust_features.get("restaurant_opening_marketing_route_board_count", 0)) <= 1:
		return Result.failure("robust opening should expose multiple independent opening billboard boards: %s" % str(robust_features))
	if int(robust_features.get("restaurant_opening_marketing_route_options", 0)) < int(robust_features.get("restaurant_opening_marketing_route_board_count", 0)):
		return Result.failure("opening marketing route options should include board-level alternatives: %s" % str(robust_features))
	return Result.success()

static func _test_initial_restaurant_placement_prefers_broader_opening_route() -> Result:
	var observation := ObservationState.new()
	observation.phase = DefsClass.PHASE_SETUP
	observation.sub_phase = ""
	observation.own_player = {
		"id": 0,
		"cash": 0,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"inventory": {},
	}
	var singleton_entry := {
		"macro_action_id": "initial_restaurant_singleton",
		"action_id": "place_restaurant",
		"params": {"position": [1, 1], "rotation": 0},
		"score": 84.0,
		"features": {
			"restaurant_competitive_houses": 1,
			"restaurant_contested_houses": 0,
			"restaurant_competitor_dominated_houses": 0,
			"restaurant_opening_marketing_route_houses": 1,
			"restaurant_opening_marketing_route_board_count": 1,
			"restaurant_opening_marketing_route_options": 1,
		},
	}
	var broader_entry := {
		"macro_action_id": "initial_restaurant_broader",
		"action_id": "place_restaurant",
		"params": {"position": [2, 2], "rotation": 0},
		"score": 80.0,
		"features": {
			"restaurant_competitive_houses": 2,
			"restaurant_contested_houses": 0,
			"restaurant_competitor_dominated_houses": 0,
			"restaurant_opening_marketing_route_houses": 3,
			"restaurant_opening_marketing_route_board_count": 2,
			"restaurant_opening_marketing_route_options": 4,
		},
	}
	var filtered := StrategyBotClass._filter_unsafe_opening_restaurant_entries(observation, [singleton_entry, broader_entry])
	var kept: Array = Array(filtered.get("ranked", []))
	if kept.size() != 1:
		return Result.failure("opening route filter should keep only the broader candidate: %s" % str(filtered))
	var kept_entry: Dictionary = Dictionary(kept[0])
	if str(kept_entry.get("macro_action_id", "")) != "initial_restaurant_broader":
		return Result.failure("opening route filter should discard the singleton opening when a broader route exists: %s" % str(filtered))
	var discarded_reasons: Array = Array(filtered.get("discarded_reasons", []))
	if discarded_reasons.is_empty() or str(discarded_reasons[0]).find("broader marketing route") < 0:
		return Result.failure("opening route filter should explain the dominance discard: %s" % str(filtered))
	return Result.success()

static func _test_strategy_bot_opens_second_player_marketing_route() -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 331009)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var controller := BotControllerClass.new()
	var bots := {
		0: StrategyBotClass.new(),
		1: StrategyBotClass.new(),
	}
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		if state == null:
			return false
		if str(state.phase) == DefsClass.PHASE_GAME_OVER:
			return true
		var p0_cash_running := int(Dictionary(state.players[0]).get("cash", 0))
		var p1_cash_running := int(Dictionary(state.players[1]).get("cash", 0))
		return (p0_cash_running > 0 and p1_cash_running > 0) or int(state.round_number) >= 6
	var run_result := controller.run_until(engine, bots, stop_condition, 720, 80)
	if not run_result.ok:
		return run_result
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after opening route regression")
	var p0_cash := int(Dictionary(state.players[0]).get("cash", 0))
	var p1_cash := int(Dictionary(state.players[1]).get("cash", 0))
	if p0_cash <= 0 or p1_cash <= 0:
		return Result.failure("opening route regression should get both players positive cash by round 6, cash=[%d,%d] trace=%s" % [p0_cash, p1_cash, str(_action_summary(controller.last_trace))])
	var saw_p1_marketing := false
	var saw_p1_production := false
	for item in controller.last_trace:
		if int(item.get("player_id", -1)) != 1:
			continue
		var action_id := str(item.get("action_id", ""))
		if action_id == "initiate_marketing":
			saw_p1_marketing = true
		elif action_id == "produce_food":
			saw_p1_production = true
	if not saw_p1_marketing:
		return Result.failure("opening route regression should let second player initiate marketing: %s" % str(_action_summary(controller.last_trace)))
	if not saw_p1_production:
		return Result.failure("opening route regression should let second player produce after marketing: %s" % str(_action_summary(controller.last_trace)))
	return Result.success()

static func _test_house_placement_prefers_near_owned_restaurant(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	var near_house_payload: Dictionary = StrategyBoardAnalyzerClass.evaluate_house_action(observation, {"position": [4, 3], "rotation": 0, "house_number": 2})
	var near_house_features: Dictionary = Dictionary(near_house_payload.get("features", {}))
	if int(near_house_features.get("house_nearest_restaurant_distance", -1)) > 2:
		return Result.failure("StrategyBoardAnalyzer house action should expose close restaurant distance: %s" % str(near_house_payload))
	if float(near_house_payload.get("value", 0.0)) <= 0.0:
		return Result.failure("StrategyBoardAnalyzer house action should expose positive value: %s" % str(near_house_payload))
	var near_macro := MacroAction.create(
		"place_house_near_restaurant",
		[Command.create("place_house", 0, {"position": [4, 3], "rotation": 0, "house_number": 2})],
		0.0,
		["working", "place_house"],
		{}
	)
	var far_macro := MacroAction.create(
		"place_house_far_restaurant",
		[Command.create("place_house", 0, {"position": [10, 10], "rotation": 0, "house_number": 2})],
		0.0,
		["working", "place_house"],
		{}
	)
	var near_score: Dictionary = StrategyScorerClass.score_macro(observation, near_macro, profile)
	var far_score: Dictionary = StrategyScorerClass.score_macro(observation, far_macro, profile)
	if float(near_score.get("score", 0.0)) <= float(far_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer placing houses near owned restaurants: near=%s far=%s" % [str(near_score), str(far_score)])
	var features: Dictionary = Dictionary(near_score.get("features", {}))
	if int(features.get("house_nearest_restaurant_distance", -1)) > 2:
		return Result.failure("near house placement should expose close restaurant distance: %s" % str(features))
	if float(features.get("house_placement_value", 0.0)) <= 0.0:
		return Result.failure("near house placement should expose positive house_placement_value: %s" % str(features))
	return Result.success()

static func _test_payday_fire_prefers_low_income_employee(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_payday_observation()
	var cfo_macro := MacroAction.create(
		"fire_cfo",
		[Command.create("fire", 0, {"employee_id": "cfo", "location": "active"})],
		0.0,
		["payday", "fire"],
		{}
	)
	var burger_macro := MacroAction.create(
		"fire_burger_cook",
		[Command.create("fire", 0, {"employee_id": "burger_cook", "location": "active"})],
		0.0,
		["payday", "fire"],
		{}
	)
	var cfo_score: Dictionary = StrategyScorerClass.score_macro(observation, cfo_macro, profile)
	var burger_score: Dictionary = StrategyScorerClass.score_macro(observation, burger_macro, profile)
	if float(cfo_score.get("score", 0.0)) <= float(burger_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should prefer firing lower income value employee under payday shortfall: cfo=%s burger=%s" % [str(cfo_score), str(burger_score)])
	var features: Dictionary = Dictionary(cfo_score.get("features", {}))
	if int(features.get("fire_payday_shortfall", 0)) <= 0:
		return Result.failure("fire features should expose payday shortfall: %s" % str(features))
	if int(features.get("fire_effective_salary_relief", 0)) <= 0:
		return Result.failure("fire features should expose effective salary relief: %s" % str(features))
	return Result.success()

static func _test_payday_fire_uses_payday_preview_for_unresolved_shortfall(seed_val: int) -> Result:
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
	var set_cash := StateUpdaterClass.set_player_cash(state, 0, 5)
	if not set_cash.ok:
		return Result.failure("payday preview fire test set cash failed: %s" % set_cash.error)
	for employee_id in ["burger_cook", "pizza_cook", "cfo"]:
		var take := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take.ok:
			return Result.failure("payday preview fire test take %s failed: %s" % [employee_id, take.error])
		var add := StateUpdaterClass.add_employee(state, 0, employee_id, false)
		if not add.ok:
			return Result.failure("payday preview fire test add %s failed: %s" % [employee_id, add.error])
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var fire_macro := MacroAction.create(
		"fire_one_employee_still_short",
		[Command.create("fire", 0, {"employee_id": "cfo", "location": "active"})],
		0.0,
		["payday", "fire"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_payday_shortfall",
		[Command.create("skip", 0, {})],
		0.0,
		["payday", "fallback"],
		{}
	)
	var fire_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, fire_macro, profile, {"source_engine": engine, "source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(fire_score.get("features", {}))
	if str(features.get("fire_payday_preview_source", "")) != "payday_preview":
		return Result.failure("fire scoring should use PaydayPreview when source_engine is available: %s" % str(features))
	if str(features.get("fire_payday_preview_error", "")).is_empty():
		return Result.failure("unresolved fire shortfall should expose PaydayPreview error: %s" % str(features))
	if not bool(features.get("fire_payday_preview_actor_shortfall_reduced", false)):
		return Result.failure("unresolved fire shortfall should mark actor shortfall reduced: %s" % str(features))
	if features.has("fire_payday_preview_failure_penalty"):
		return Result.failure("partial salary relief should not be penalized because more fires can follow: %s" % str(features))
	if float(fire_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should keep firing when one fire reduces unresolved Payday shortfall: fire=%s skip=%s" % [str(fire_score), str(skip_score)])
	return Result.success()

static func _test_payday_fire_ignores_other_player_preview_shortfall(seed_val: int) -> Result:
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
	for player_id in [0, 1]:
		var set_cash := StateUpdaterClass.set_player_cash(state, player_id, 0)
		if not set_cash.ok:
			return Result.failure("two-player payday preview test set cash failed for player %d: %s" % [player_id, set_cash.error])
		state.players[player_id]["employees"] = []
		state.players[player_id]["reserve_employees"] = []
		state.players[player_id]["busy_marketers"] = []
		state.players[player_id]["employees_staff_ids"] = []
		state.players[player_id]["reserve_staff_ids"] = []
		state.players[player_id]["busy_staff_ids"] = []
		state.players[player_id]["staff_registry"] = {}
	var player0_employee := "burger_cook"
	var player1_employee := "pizza_cook"
	for item in [
		{"player_id": 0, "employee_id": player0_employee},
		{"player_id": 1, "employee_id": player1_employee},
	]:
		var player_id := int(item.get("player_id", -1))
		var employee_id := str(item.get("employee_id", ""))
		var take := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take.ok:
			return Result.failure("two-player payday preview test take %s failed: %s" % [employee_id, take.error])
		var add := StateUpdaterClass.add_employee(state, player_id, employee_id, false)
		if not add.ok:
			return Result.failure("two-player payday preview test add %s failed: %s" % [employee_id, add.error])
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
	if not observation_read.ok:
		return observation_read
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var fire_macro := MacroAction.create(
		"fire_actor_shortfall_resolved_other_player_pending",
		[Command.create("fire", 0, {"employee_id": player0_employee, "location": "active"})],
		0.0,
		["payday", "fire"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_actor_shortfall",
		[Command.create("skip", 0, {})],
		0.0,
		["payday", "fallback"],
		{}
	)
	var fire_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, fire_macro, profile, {"source_engine": engine, "source_state": state})
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation_read.value, skip_macro, profile, {"source_engine": engine, "source_state": state})
	var features: Dictionary = Dictionary(fire_score.get("features", {}))
	if str(features.get("fire_payday_preview_source", "")) != "payday_preview":
		return Result.failure("two-player payday fire should use PaydayPreview: %s" % str(features))
	if str(features.get("fire_payday_preview_error", "")).is_empty():
		return Result.failure("two-player payday fire should expose other-player preview error: %s" % str(features))
	if not bool(features.get("fire_payday_preview_actor_shortfall_resolved", false)):
		return Result.failure("two-player payday fire should mark actor shortfall resolved: %s" % str(features))
	if features.has("fire_payday_preview_failure_penalty"):
		return Result.failure("two-player payday fire should not penalize other player's pending shortfall: %s" % str(features))
	if float(fire_score.get("score", 0.0)) <= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should fire when actor shortfall is resolved even if another player still owes: fire=%s skip=%s" % [str(fire_score), str(skip_score)])
	return Result.success()

static func _synthetic_marketing_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_MARKETING
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["campaign_manager"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {"burger": 1},
	}
	observation.map_public = {
		"grid_size": Vector2i(12, 12),
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [],
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

static func _sorted_unique_strings(value) -> Array[String]:
	var seen := {}
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if text.is_empty():
				continue
			seen[text] = true
	var out: Array[String] = []
	for key in seen.keys():
		out.append(str(key))
	out.sort()
	return out

static func _synthetic_order_of_business_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_ORDER_OF_BUSINESS
	observation.sub_phase = ""
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"inventory": {},
	}
	return observation

static func _synthetic_reserve_card_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_SETUP
	observation.sub_phase = DefsClass.SUB_PHASE_RESERVE_CARDS
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"inventory": {},
		"reserve_cards": [
			{"type": 5, "cash": 50, "ceo_slots": 2},
			{"type": 10, "cash": 100, "ceo_slots": 3},
			{"type": 20, "cash": 150, "ceo_slots": 4},
		],
		"reserve_card_selected": -1,
	}
	return observation

static func _apply_drive_through_source_case(state: GameState) -> Result:
	if state == null:
		return Result.failure("drive-through source case missing state")
	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("drive-through source case take local_manager failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "local_manager", false)
	if not add.ok:
		return Result.failure("drive-through source case add local_manager failed: %s" % add.error)
	var restaurants: Dictionary = state.map.get("restaurants", {})
	var rest_0: Dictionary = restaurants.get("rest_0", {})
	if rest_0.is_empty():
		return Result.failure("drive-through source case missing rest_0")
	rest_0["entrance_pos"] = Vector2i(1, 4)
	restaurants["rest_0"] = rest_0
	state.map["restaurants"] = restaurants
	RoadGraphCacheClass.invalidate_road_graph(state)
	return Result.success()

static func _synthetic_income_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["burger_cook", "pizza_cook"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
	}
	observation.map_public = {
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

static func _synthetic_house_growth_observation() -> ObservationState:
	var observation := _synthetic_income_observation()
	observation.map_public["house_number_supply_remaining"] = [2, 3, 4, 5]
	observation.map_public["garden_supply_remaining"] = 2
	var houses: Dictionary = Dictionary(observation.map_public.get("houses", {})).duplicate(true)
	var house_near: Dictionary = Dictionary(houses.get("house_near", {})).duplicate(true)
	house_near["has_garden"] = false
	houses["house_near"] = house_near
	observation.map_public["houses"] = houses
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

static func _synthetic_drink_route_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_DRINKS
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

static func _synthetic_payday_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_PAYDAY
	observation.sub_phase = ""
	observation.rules_public = {
		"salary_cost": 5,
	}
	observation.own_player = {
		"id": 0,
		"cash": 0,
		"employees": ["burger_cook", "cfo"],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
		"milestones": [],
	}
	observation.map_public = {
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
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

static func _synthetic_fridge_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_CLEANUP
	observation.sub_phase = ""
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {
			"burger": 2,
			"soda": 8,
		},
	}
	observation.map_public = {
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

static func _synthetic_restaurant_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_SETUP
	observation.sub_phase = ""
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"inventory": {},
	}
	observation.map_public = {
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
					{"product": "burger"},
				],
			},
			"house_far": {
				"house_number": 2,
				"anchor_pos": Vector2i(9, 9),
				"demands": [],
			},
		},
		"restaurants": {},
	}
	return observation
