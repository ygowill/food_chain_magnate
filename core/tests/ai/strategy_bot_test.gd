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
	var recruit_roster := _test_recruit_score_penalizes_roster_saturation(seed_val)
	if not recruit_roster.ok:
		return recruit_roster
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
	var product_overstock := _test_strategy_scoring_penalizes_product_overstock(seed_val)
	if not product_overstock.ok:
		return product_overstock
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
