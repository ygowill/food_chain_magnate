class_name StrategyBotTest
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

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
	var income_gap := _test_income_analyzer_detects_serviceable_inventory_gap(seed_val)
	if not income_gap.ok:
		return income_gap
	var fridge_keep := _test_fridge_keep_prioritizes_serviceable_demand(seed_val)
	if not fridge_keep.ok:
		return fridge_keep
	var product_gap_score := _test_strategy_scoring_targets_current_product_gap(seed_val)
	if not product_gap_score.ok:
		return product_gap_score
	var restaurant_placement := _test_restaurant_placement_prefers_near_public_demand(seed_val)
	if not restaurant_placement.ok:
		return restaurant_placement
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
