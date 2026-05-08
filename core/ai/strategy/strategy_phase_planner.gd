class_name StrategyPhasePlanner
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const VERSION := "phase_planner_v1"
const DEFAULT_MAX_VALID_PER_ACTION := 12
const SETUP_RESTAURANT_MIN_VALID_PER_ACTION := 64

static func plan(observation: ObservationState, context: AiDecisionContext, profile) -> Dictionary:
	var phase := str(observation.phase) if observation != null else ""
	var sub_phase := str(observation.sub_phase) if observation != null else ""
	var player_id := int(context.player_id) if context != null else -1
	var strategy_id := _strategy_id_for_phase(phase, sub_phase)
	var goal := _goal_for_strategy(strategy_id)
	var max_valid_per_action := _profile_max_valid_per_action(profile)
	if strategy_id == "setup_restaurant":
		max_valid_per_action = maxi(max_valid_per_action, SETUP_RESTAURANT_MIN_VALID_PER_ACTION)
	return {
		"id": strategy_id,
		"goal": goal,
		"version": VERSION,
		"phase": phase,
		"sub_phase": sub_phase,
		"player_id": player_id,
		"max_valid_per_action": max_valid_per_action,
	}

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

static func _profile_max_valid_per_action(profile) -> int:
	if profile != null and profile.get("max_valid_per_action") != null:
		return maxi(1, int(profile.max_valid_per_action))
	return DEFAULT_MAX_VALID_PER_ACTION
