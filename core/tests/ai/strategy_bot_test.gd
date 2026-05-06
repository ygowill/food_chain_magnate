class_name StrategyBotTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
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
	var reserve_card_score := _test_reserve_card_score_prefers_strategy_capacity(seed_val)
	if not reserve_card_score.ok:
		return reserve_card_score
	var filter_case := _test_marketing_filter_discards_no_house_candidate()
	if not filter_case.ok:
		return filter_case
	var marketing_score := _test_marketing_score_prefers_affected_serviceable_houses(seed_val)
	if not marketing_score.ok:
		return marketing_score
	var marketing_generation := _test_marketing_generation_prioritizes_ready_product(seed_val)
	if not marketing_generation.ok:
		return marketing_generation
	var active_supply := _test_marketing_score_uses_active_supply_for_unstocked_product(seed_val)
	if not active_supply.ok:
		return active_supply
	var road_graph_marketing := _test_marketing_score_uses_source_road_graph(seed_val)
	if not road_graph_marketing.ok:
		return road_graph_marketing
	var income_gap := _test_income_analyzer_detects_serviceable_inventory_gap(seed_val)
	if not income_gap.ok:
		return income_gap
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
	var dinner_preview_food := _test_strategy_scoring_uses_dinner_preview_for_food_income(seed_val)
	if not dinner_preview_food.ok:
		return dinner_preview_food
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
	var house_placement := _test_house_placement_prefers_near_owned_restaurant(seed_val)
	if not house_placement.ok:
		return house_placement
	var payday_fire := _test_payday_fire_prefers_low_income_employee(seed_val)
	if not payday_fire.ok:
		return payday_fire
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
	var bot = StrategyBotClass.new()
	var bot_read := bot.configure_profile("base_revenue_growth_v1")
	if not bot_read.ok:
		return Result.failure("StrategyBot should configure named profile: %s" % bot_read.error)
	if str(bot.profile.id) != "base_revenue_growth_v1":
		return Result.failure("StrategyBot configured wrong profile: %s" % str(bot.profile.id))
	return Result.success()

static func _test_reserve_card_score_prefers_strategy_capacity(seed_val: int) -> Result:
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_reserve_card_observation()
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
	var skip_macro := MacroAction.create(
		"skip_sub_phase",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var filtered: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, [bad_macro, skip_macro], profile)
	var kept_val = filtered.get("candidates", [])
	if not (kept_val is Array):
		return Result.failure("StrategyCandidateFilter should return candidate Array")
	var kept: Array = kept_val
	if kept.size() != 1:
		return Result.failure("StrategyCandidateFilter should keep only fallback candidate, got %d" % kept.size())
	if kept[0] != skip_macro:
		return Result.failure("StrategyCandidateFilter kept wrong candidate")
	var stats: Dictionary = Dictionary(filtered.get("stats", {}))
	if int(stats.get("discarded_marketing_no_affected_houses", 0)) != 1:
		return Result.failure("StrategyCandidateFilter should count no-house marketing discard: %s" % str(stats))
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
	var saturated_observation := _synthetic_income_observation()
	saturated_observation.phase = DefsClass.PHASE_WORKING
	saturated_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	saturated_observation.own_player["employees"] = ["burger_cook", "pizza_cook", "trainer"]
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
		return Result.failure("StrategyScorer should still value first trainer when trainable staff exist: trainer=%s skip=%s" % [str(useful_score), str(skip_score)])
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
	var skip_macro := MacroAction.create(
		"skip_recruit",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var early_pricing_score: Dictionary = StrategyScorerClass.score_macro(observation, pricing_macro, profile)
	var early_recruiter_score: Dictionary = StrategyScorerClass.score_macro(observation, recruiter_macro, profile)
	var skip_score: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile)
	if float(early_pricing_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip pricing manager before stable income route: pricing=%s skip=%s" % [str(early_pricing_score), str(skip_score)])
	if float(early_recruiter_score.get("score", 0.0)) >= float(skip_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should skip recruiting girl before stable income route: recruiting_girl=%s skip=%s" % [str(early_recruiter_score), str(skip_score)])
	var early_pricing_features: Dictionary = Dictionary(early_pricing_score.get("features", {}))
	if int(early_pricing_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("early pricing manager should expose zero desired count: %s" % str(early_pricing_features))
	var early_recruiter_features: Dictionary = Dictionary(early_recruiter_score.get("features", {}))
	if int(early_recruiter_features.get("recruit_desired_count", -1)) != 0:
		return Result.failure("early recruiting girl should expose zero desired count: %s" % str(early_recruiter_features))

	var ready_observation := _synthetic_income_observation()
	ready_observation.phase = DefsClass.PHASE_WORKING
	ready_observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	ready_observation.own_player["cash"] = 25
	ready_observation.own_player["employees"] = ["burger_cook", "marketing_trainee"]
	ready_observation.own_player["inventory"] = {"burger": 2}
	var ready_pricing_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, pricing_macro, profile)
	var ready_recruiter_score: Dictionary = StrategyScorerClass.score_macro(ready_observation, recruiter_macro, profile)
	var ready_pricing_features: Dictionary = Dictionary(ready_pricing_score.get("features", {}))
	if int(ready_pricing_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("stable income pricing manager should expose desired count 1: %s" % str(ready_pricing_features))
	var ready_recruiter_features: Dictionary = Dictionary(ready_recruiter_score.get("features", {}))
	if int(ready_recruiter_features.get("recruit_desired_count", 0)) != 1:
		return Result.failure("stable income recruiting girl should expose desired count 1: %s" % str(ready_recruiter_features))
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
		"procure_route_beer_for_pending",
		[Command.create("procure_drinks", 0, {"employee_type": "truck_driver", "restaurant_id": "rest_near", "route": [[3, 2], [8, 2]], "selected_sources": [[8, 2]]})],
		0.0,
		["working", "procure_drinks"],
		{}
	)
	var soda_score: Dictionary = StrategyScorerClass.score_macro(observation, soda_macro, profile)
	var beer_score: Dictionary = StrategyScorerClass.score_macro(observation, beer_macro, profile)
	if float(beer_score.get("score", 0.0)) <= float(soda_score.get("score", 0.0)):
		return Result.failure("StrategyScorer should procure drinks matching pending own marketing: beer=%s soda=%s" % [str(beer_score), str(soda_score)])
	var beer_features: Dictionary = Dictionary(beer_score.get("features", {}))
	if int(beer_features.get("product_pending_marketing_demand", 0)) != 1:
		return Result.failure("pending marketing supply should expose product_pending_marketing_demand: %s" % str(beer_features))
	if int(beer_features.get("product_planning_inventory_gap", 0)) != 1:
		return Result.failure("pending marketing supply should expose product_planning_inventory_gap: %s" % str(beer_features))
	if int(beer_features.get("product_supply_future_covered_units", 0)) != 1:
		return Result.failure("pending marketing supply should count future covered units: %s" % str(beer_features))
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
	var profile = StrategyProfileClass.new()
	profile.configure_base_revenue()
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
		return Result.failure("StrategyScorer should skip no-demand food production when cash cannot keep the milestone cook: burger=%s skip=%s" % [str(burger_score), str(skip_score)])
	var features: Dictionary = Dictionary(burger_score.get("features", {}))
	if float(features.get("product_no_demand_cash_safety_penalty", 0.0)) >= 0.0:
		return Result.failure("no-demand unsafe food production should expose cash safety penalty: %s" % str(features))
	if float(features.get("milestone_race_value", 0.0)) <= 0.0:
		return Result.failure("test should still include the first_burger_produced race value: %s" % str(features))
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
