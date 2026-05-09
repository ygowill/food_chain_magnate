class_name StrategyPhasePlanner
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const VERSION := "phase_planner_v2"
const DEFAULT_MAX_VALID_PER_ACTION := 12
const SETUP_RESTAURANT_MIN_VALID_PER_ACTION := 64
const INCOME_ROUTE_MIN_VALID_PER_ACTION := 16
const GROWTH_ROUTE_MIN_VALID_PER_ACTION := 24

const DEFAULT_SEARCH_BEAM_WIDTH := 4
const DEFAULT_SEARCH_MAX_DEPTH := 3
const DEFAULT_SEARCH_TOP_K_PER_NODE := 3
const DEFAULT_SEARCH_MAX_CANDIDATES := 6
const DEFAULT_SEARCH_OPPONENT_MAX_CANDIDATES := 3
const DEFAULT_SEARCH_OPPONENT_MAX_VALID_PER_ACTION := 3
const DEFAULT_SEARCH_OPPONENT_RESPONSE_HORIZON := 1

const DEFAULT_SEARCH_MCTS_ITERATIONS := 16
const DEFAULT_SEARCH_MCTS_MAX_DEPTH := 3
const DEFAULT_SEARCH_MCTS_TOP_K_PER_NODE := 4
const DEFAULT_SEARCH_MCTS_EXPLORATION := 1.25
const DEFAULT_SEARCH_MCTS_MIN_SIMULATION_BUDGET_MS := 24

const SETUP_RESTAURANT_SEARCH_BEAM_WIDTH := 6
const SETUP_RESTAURANT_SEARCH_MAX_DEPTH := 2
const SETUP_RESTAURANT_SEARCH_TOP_K_PER_NODE := 5
const SETUP_RESTAURANT_SEARCH_MAX_CANDIDATES := 10
const SETUP_RESTAURANT_SEARCH_OPPONENT_MAX_CANDIDATES := 4
const SETUP_RESTAURANT_SEARCH_OPPONENT_MAX_VALID_PER_ACTION := 4
const SETUP_RESTAURANT_SEARCH_OPPONENT_RESPONSE_HORIZON := 1
const SETUP_RESTAURANT_SEARCH_MCTS_ITERATIONS := 24
const SETUP_RESTAURANT_SEARCH_MCTS_MAX_DEPTH := 2
const SETUP_RESTAURANT_SEARCH_MCTS_TOP_K_PER_NODE := 5

const INCOME_ROUTE_SEARCH_BEAM_WIDTH := 5
const INCOME_ROUTE_SEARCH_MAX_DEPTH := 3
const INCOME_ROUTE_SEARCH_TOP_K_PER_NODE := 4
const INCOME_ROUTE_SEARCH_MAX_CANDIDATES := 8
const INCOME_ROUTE_SEARCH_OPPONENT_MAX_CANDIDATES := 3
const INCOME_ROUTE_SEARCH_OPPONENT_MAX_VALID_PER_ACTION := 3
const INCOME_ROUTE_SEARCH_OPPONENT_RESPONSE_HORIZON := 1
const INCOME_ROUTE_SEARCH_MCTS_ITERATIONS := 24
const INCOME_ROUTE_SEARCH_MCTS_MAX_DEPTH := 3
const INCOME_ROUTE_SEARCH_MCTS_TOP_K_PER_NODE := 4

const GROWTH_ROUTE_SEARCH_BEAM_WIDTH := 6
const GROWTH_ROUTE_SEARCH_MAX_DEPTH := 4
const GROWTH_ROUTE_SEARCH_TOP_K_PER_NODE := 5
const GROWTH_ROUTE_SEARCH_MAX_CANDIDATES := 10
const GROWTH_ROUTE_SEARCH_OPPONENT_MAX_CANDIDATES := 4
const GROWTH_ROUTE_SEARCH_OPPONENT_MAX_VALID_PER_ACTION := 4
const GROWTH_ROUTE_SEARCH_OPPONENT_RESPONSE_HORIZON := 1
const GROWTH_ROUTE_SEARCH_MCTS_ITERATIONS := 32
const GROWTH_ROUTE_SEARCH_MCTS_MAX_DEPTH := 4
const GROWTH_ROUTE_SEARCH_MCTS_TOP_K_PER_NODE := 5

const ORDER_OF_BUSINESS_SEARCH_BEAM_WIDTH := 4
const ORDER_OF_BUSINESS_SEARCH_MAX_DEPTH := 2
const ORDER_OF_BUSINESS_SEARCH_TOP_K_PER_NODE := 3
const ORDER_OF_BUSINESS_SEARCH_MAX_CANDIDATES := 6
const ORDER_OF_BUSINESS_SEARCH_OPPONENT_MAX_CANDIDATES := 3
const ORDER_OF_BUSINESS_SEARCH_OPPONENT_MAX_VALID_PER_ACTION := 3
const ORDER_OF_BUSINESS_SEARCH_OPPONENT_RESPONSE_HORIZON := 2
const ORDER_OF_BUSINESS_SEARCH_MCTS_ITERATIONS := 24
const ORDER_OF_BUSINESS_SEARCH_MCTS_MAX_DEPTH := 2
const ORDER_OF_BUSINESS_SEARCH_MCTS_TOP_K_PER_NODE := 4

static func plan(observation: ObservationState, context: AiDecisionContext, profile) -> Dictionary:
	var phase := str(observation.phase) if observation != null else ""
	var sub_phase := str(observation.sub_phase) if observation != null else ""
	var player_id := int(context.player_id) if context != null else -1
	var strategy_id := _strategy_id_for_phase(phase, sub_phase)
	var goal := _goal_for_strategy(strategy_id)
	var search_hints := _search_hints_for_strategy(strategy_id, profile)
	var max_valid_per_action := int(search_hints.get("max_valid_per_action", _profile_max_valid_per_action(profile)))
	return {
		"id": strategy_id,
		"goal": goal,
		"version": VERSION,
		"phase": phase,
		"sub_phase": sub_phase,
		"player_id": player_id,
		"max_valid_per_action": max_valid_per_action,
		"search_hints": search_hints,
	}

static func build_search_options(
	observation: ObservationState,
	context: AiDecisionContext,
	profile,
	base_options: Dictionary = {}
) -> Dictionary:
	var plan_result := plan(observation, context, profile)
	var options: Dictionary = {}
	if base_options != null:
		options = base_options.duplicate()
	var search_hints_val = plan_result.get("search_hints", {})
	if search_hints_val is Dictionary:
		for key in Dictionary(search_hints_val).keys():
			options[key] = search_hints_val.get(key, null)
	options["max_valid_per_action"] = maxi(1, int(plan_result.get("max_valid_per_action", _profile_max_valid_per_action(profile))))
	return options

static func _strategy_id_for_phase(phase: String, sub_phase: String) -> String:
	match phase:
		DefsClass.PHASE_SETUP:
			if sub_phase == DefsClass.SUB_PHASE_RESERVE_CARDS:
				return "setup_reserve_cards"
			return "setup_restaurant"
		DefsClass.PHASE_RESTRUCTURING:
			return "restructuring_income_capacity"
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			return "order_of_business_tempo"
		DefsClass.PHASE_WORKING:
			return _working_strategy_id(sub_phase)
		DefsClass.PHASE_DINNERTIME:
			return "dinnertime_settlement"
		DefsClass.PHASE_PAYDAY:
			return "payday_cash_safety"
		DefsClass.PHASE_MARKETING:
			return "marketing_settlement"
		DefsClass.PHASE_CLEANUP:
			return "cleanup_inventory_safety"
		DefsClass.PHASE_GAME_OVER:
			return "game_over"
	return "generic"

static func _working_strategy_id(sub_phase: String) -> String:
	match sub_phase:
		DefsClass.SUB_PHASE_RECRUIT:
			return "working_recruit_income_route"
		DefsClass.SUB_PHASE_TRAIN:
			return "working_train_capacity"
		DefsClass.SUB_PHASE_MARKETING:
			return "working_marketing_demand"
		DefsClass.SUB_PHASE_GET_FOOD:
			return "working_get_food_supply"
		DefsClass.SUB_PHASE_GET_DRINKS:
			return "working_get_drinks_supply"
		DefsClass.SUB_PHASE_PLACE_HOUSES:
			return "working_place_houses_growth"
		DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
			return "working_place_restaurants_growth"
	return "working_generic"

static func _goal_for_strategy(strategy_id: String) -> String:
	match strategy_id:
		"setup_reserve_cards", "setup_restaurant":
			return "foundation"
		"restructuring_income_capacity", "working_recruit_income_route", "working_train_capacity", "working_marketing_demand", "working_get_food_supply", "working_get_drinks_supply":
			return "income_route"
		"working_place_houses_growth", "working_place_restaurants_growth":
			return "growth_route"
		"order_of_business_tempo":
			return "tempo"
		"payday_cash_safety":
			return "cash_safety"
		"cleanup_inventory_safety":
			return "inventory_safety"
		"dinnertime_settlement", "marketing_settlement":
			return "settlement"
		"game_over":
			return "terminal"
	return "generic"

static func _search_hints_for_strategy(strategy_id: String, profile) -> Dictionary:
	var profile_max_valid_per_action := _profile_max_valid_per_action(profile)
	var search_hints := {}
	match strategy_id:
		"setup_restaurant":
			search_hints = _make_search_hints(
				maxi(profile_max_valid_per_action, SETUP_RESTAURANT_MIN_VALID_PER_ACTION),
				SETUP_RESTAURANT_SEARCH_BEAM_WIDTH,
				SETUP_RESTAURANT_SEARCH_MAX_DEPTH,
				SETUP_RESTAURANT_SEARCH_TOP_K_PER_NODE,
				SETUP_RESTAURANT_SEARCH_MAX_CANDIDATES,
				SETUP_RESTAURANT_SEARCH_OPPONENT_MAX_CANDIDATES,
				SETUP_RESTAURANT_SEARCH_OPPONENT_MAX_VALID_PER_ACTION,
				SETUP_RESTAURANT_SEARCH_OPPONENT_RESPONSE_HORIZON
			)
		"restructuring_income_capacity", "working_recruit_income_route", "working_train_capacity", "working_marketing_demand", "working_get_food_supply", "working_get_drinks_supply":
			search_hints = _make_search_hints(
				maxi(profile_max_valid_per_action, INCOME_ROUTE_MIN_VALID_PER_ACTION),
				INCOME_ROUTE_SEARCH_BEAM_WIDTH,
				INCOME_ROUTE_SEARCH_MAX_DEPTH,
				INCOME_ROUTE_SEARCH_TOP_K_PER_NODE,
				INCOME_ROUTE_SEARCH_MAX_CANDIDATES,
				INCOME_ROUTE_SEARCH_OPPONENT_MAX_CANDIDATES,
				INCOME_ROUTE_SEARCH_OPPONENT_MAX_VALID_PER_ACTION,
				INCOME_ROUTE_SEARCH_OPPONENT_RESPONSE_HORIZON
			)
		"working_place_houses_growth", "working_place_restaurants_growth":
			search_hints = _make_search_hints(
				maxi(profile_max_valid_per_action, GROWTH_ROUTE_MIN_VALID_PER_ACTION),
				GROWTH_ROUTE_SEARCH_BEAM_WIDTH,
				GROWTH_ROUTE_SEARCH_MAX_DEPTH,
				GROWTH_ROUTE_SEARCH_TOP_K_PER_NODE,
				GROWTH_ROUTE_SEARCH_MAX_CANDIDATES,
				GROWTH_ROUTE_SEARCH_OPPONENT_MAX_CANDIDATES,
				GROWTH_ROUTE_SEARCH_OPPONENT_MAX_VALID_PER_ACTION,
				GROWTH_ROUTE_SEARCH_OPPONENT_RESPONSE_HORIZON
			)
		"order_of_business_tempo":
			search_hints = _make_search_hints(
				profile_max_valid_per_action,
				ORDER_OF_BUSINESS_SEARCH_BEAM_WIDTH,
				ORDER_OF_BUSINESS_SEARCH_MAX_DEPTH,
				ORDER_OF_BUSINESS_SEARCH_TOP_K_PER_NODE,
				ORDER_OF_BUSINESS_SEARCH_MAX_CANDIDATES,
				ORDER_OF_BUSINESS_SEARCH_OPPONENT_MAX_CANDIDATES,
				ORDER_OF_BUSINESS_SEARCH_OPPONENT_MAX_VALID_PER_ACTION,
				ORDER_OF_BUSINESS_SEARCH_OPPONENT_RESPONSE_HORIZON
			)
		_:
			search_hints = _make_search_hints(
				profile_max_valid_per_action,
				DEFAULT_SEARCH_BEAM_WIDTH,
				DEFAULT_SEARCH_MAX_DEPTH,
				DEFAULT_SEARCH_TOP_K_PER_NODE,
				DEFAULT_SEARCH_MAX_CANDIDATES,
				DEFAULT_SEARCH_OPPONENT_MAX_CANDIDATES,
				DEFAULT_SEARCH_OPPONENT_MAX_VALID_PER_ACTION,
				DEFAULT_SEARCH_OPPONENT_RESPONSE_HORIZON
			)
	var mcts_hints := _mcts_hints_for_strategy(strategy_id)
	for key in mcts_hints.keys():
		search_hints[key] = mcts_hints.get(key, null)
	return search_hints

static func _mcts_hints_for_strategy(strategy_id: String) -> Dictionary:
	match strategy_id:
		"setup_restaurant":
			return _make_mcts_hints(
				SETUP_RESTAURANT_SEARCH_MCTS_ITERATIONS,
				SETUP_RESTAURANT_SEARCH_MCTS_MAX_DEPTH,
				SETUP_RESTAURANT_SEARCH_MCTS_TOP_K_PER_NODE,
				DEFAULT_SEARCH_MCTS_EXPLORATION
			)
		"restructuring_income_capacity", "working_recruit_income_route", "working_train_capacity", "working_marketing_demand", "working_get_food_supply", "working_get_drinks_supply":
			return _make_mcts_hints(
				INCOME_ROUTE_SEARCH_MCTS_ITERATIONS,
				INCOME_ROUTE_SEARCH_MCTS_MAX_DEPTH,
				INCOME_ROUTE_SEARCH_MCTS_TOP_K_PER_NODE,
				DEFAULT_SEARCH_MCTS_EXPLORATION
			)
		"working_place_houses_growth", "working_place_restaurants_growth":
			return _make_mcts_hints(
				GROWTH_ROUTE_SEARCH_MCTS_ITERATIONS,
				GROWTH_ROUTE_SEARCH_MCTS_MAX_DEPTH,
				GROWTH_ROUTE_SEARCH_MCTS_TOP_K_PER_NODE,
				DEFAULT_SEARCH_MCTS_EXPLORATION
			)
		"order_of_business_tempo":
			return _make_mcts_hints(
				ORDER_OF_BUSINESS_SEARCH_MCTS_ITERATIONS,
				ORDER_OF_BUSINESS_SEARCH_MCTS_MAX_DEPTH,
				ORDER_OF_BUSINESS_SEARCH_MCTS_TOP_K_PER_NODE,
				DEFAULT_SEARCH_MCTS_EXPLORATION
			)
	return _make_mcts_hints(
		DEFAULT_SEARCH_MCTS_ITERATIONS,
		DEFAULT_SEARCH_MCTS_MAX_DEPTH,
		DEFAULT_SEARCH_MCTS_TOP_K_PER_NODE,
		DEFAULT_SEARCH_MCTS_EXPLORATION
	)

static func _make_mcts_hints(
	iterations: int,
	max_depth: int,
	top_k_per_node: int,
	exploration: float
) -> Dictionary:
	return {
		"mcts_iterations": int(iterations),
		"mcts_max_depth": int(max_depth),
		"mcts_top_k_per_node": int(top_k_per_node),
		"mcts_exploration": float(exploration),
		"mcts_min_simulation_budget_ms": DEFAULT_SEARCH_MCTS_MIN_SIMULATION_BUDGET_MS,
	}

static func _make_search_hints(
	max_valid_per_action: int,
	beam_width: int,
	max_depth: int,
	top_k_per_node: int,
	max_candidates: int,
	opponent_max_candidates: int,
	opponent_max_valid_per_action: int,
	opponent_response_horizon: int
) -> Dictionary:
	return {
		"max_valid_per_action": int(max_valid_per_action),
		"beam_width": int(beam_width),
		"max_depth": int(max_depth),
		"top_k_per_node": int(top_k_per_node),
		"max_candidates": int(max_candidates),
		"opponent_max_candidates": int(opponent_max_candidates),
		"opponent_max_valid_per_action": int(opponent_max_valid_per_action),
		"opponent_response_horizon": int(opponent_response_horizon),
	}

static func _profile_max_valid_per_action(profile) -> int:
	if profile != null and profile.get("max_valid_per_action") != null:
		return maxi(1, int(profile.max_valid_per_action))
	return DEFAULT_MAX_VALID_PER_ACTION
