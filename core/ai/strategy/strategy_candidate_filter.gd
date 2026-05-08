class_name StrategyCandidateFilter
extends RefCounted

const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategySupplyPlannerClass = preload("res://core/ai/strategy/strategy_supply_planner.gd")

static func filter_candidates(observation: ObservationState, candidates: Array, profile, options: Dictionary = {}) -> Dictionary:
	var kept: Array[MacroAction] = []
	var discarded: Array[String] = []
	var stats := {
		"input_count": candidates.size(),
		"kept_count": 0,
		"discarded_count": 0,
		"discarded_marketing_no_affected_houses": 0,
		"discarded_marketing_no_supply": 0,
		"discarded_marketing_opening_opponent_pressure": 0,
		"discarded_supply_deferred": 0,
	}
	var income_analysis := {}
	var income_analysis_val = options.get("income_analysis", null)
	if income_analysis_val is Dictionary:
		income_analysis = Dictionary(income_analysis_val)
	elif observation != null:
		income_analysis = StrategyIncomeAnalyzerClass.analyze(
			observation,
			profile,
			options.get("source_state", null),
			Dictionary(options.get("source_analysis", {}))
		)
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			discarded.append("strategy_filter: candidate is not MacroAction")
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			discarded.append("%s: strategy_filter empty command list" % macro.id)
			continue
		var command: Command = macro.commands[0]
		if command == null:
			discarded.append("%s: strategy_filter null command" % macro.id)
			continue
		var discard_reason := _discard_reason(observation, macro, command, profile, income_analysis)
		if not discard_reason.is_empty():
			discarded.append(discard_reason)
			if discard_reason.find("affects no houses") >= 0:
				stats["discarded_marketing_no_affected_houses"] = int(stats["discarded_marketing_no_affected_houses"]) + 1
			if discard_reason.find("cannot be supplied") >= 0:
				stats["discarded_marketing_no_supply"] = int(stats["discarded_marketing_no_supply"]) + 1
			if discard_reason.find("opponent-pressure marketing needs own income") >= 0:
				stats["discarded_marketing_opening_opponent_pressure"] = int(stats["discarded_marketing_opening_opponent_pressure"]) + 1
			if discard_reason.find("supply should be deferred") >= 0:
				stats["discarded_supply_deferred"] = int(stats["discarded_supply_deferred"]) + 1
			continue
		kept.append(macro)

	stats["kept_count"] = kept.size()
	stats["discarded_count"] = discarded.size()
	return {
		"candidates": kept,
		"discarded_reasons": discarded,
		"stats": stats,
	}

static func _discard_reason(_observation: ObservationState, macro: MacroAction, command: Command, profile, income_analysis: Dictionary) -> String:
	if macro == null or command == null:
		return "strategy_filter: invalid candidate"
	if str(command.action_id) == "initiate_marketing" and _strict_marketing_must_affect_houses(profile):
		if macro.debug.has("affected_house_ids"):
			var affected_val = macro.debug.get("affected_house_ids", [])
			if not (affected_val is Array):
				return "%s: strategy_filter affected_house_ids is not Array" % macro.id
			if Array(affected_val).is_empty():
				return "%s: strategy_filter affects no houses" % macro.id
		var supply_reason := _marketing_supply_discard_reason(macro)
		if not supply_reason.is_empty():
			return supply_reason
		var opening_pressure_reason := _marketing_opening_pressure_discard_reason(_observation, macro)
		if not opening_pressure_reason.is_empty():
			return opening_pressure_reason
	if _is_supply_action(str(command.action_id)):
		var supply_reason2 := _supply_discard_reason(_observation, macro, command, profile, income_analysis)
		if not supply_reason2.is_empty():
			return supply_reason2
	return ""

static func _is_supply_action(action_id: String) -> bool:
	return action_id == "produce_food" or action_id == "procure_drinks"

static func _supply_discard_reason(observation: ObservationState, macro: MacroAction, command: Command, profile, income_analysis: Dictionary) -> String:
	if observation == null or macro == null or command == null:
		return ""
	var supply_payload: Dictionary = StrategySupplyPlannerClass.evaluate_action(observation, command, profile, income_analysis)
	var features: Dictionary = Dictionary(supply_payload.get("features", {}))
	if StrategySupplyPlannerClass.should_defer_supply(features):
		var reason := str(features.get("product_supply_defer_reason", "no relevant demand"))
		return "%s: strategy_filter supply should be deferred (%s)" % [macro.id, reason]
	return ""

static func _marketing_supply_discard_reason(macro: MacroAction) -> String:
	if macro == null or not macro.debug.has("marketing_service_features"):
		return ""
	var features_val = macro.debug.get("marketing_service_features", {})
	if not (features_val is Dictionary):
		return ""
	var features: Dictionary = features_val
	var self_capture := int(features.get("self_capture_houses", features.get("competitive_houses", 0)))
	var opponent_pressure := int(features.get("opponent_pressure_houses", features.get("opponent_capacity_gap_houses", 0)))
	if self_capture <= 0 and opponent_pressure <= 0 and int(features.get("restaurant_dominated_houses", 0)) > 0:
		return "%s: strategy_filter affected houses are captured by competitor restaurant routes" % macro.id
	if self_capture <= 0 and opponent_pressure > 0:
		return ""
	var inventory_units := int(features.get("inventory_units", 0))
	var can_supply := bool(features.get("can_supply_product", false))
	var can_future_supply := bool(features.get("can_future_supply_product", can_supply))
	if inventory_units <= 0 and not can_supply and not can_future_supply:
		return "%s: strategy_filter marketing cannot be supplied" % macro.id
	return ""

static func _marketing_opening_pressure_discard_reason(observation: ObservationState, macro: MacroAction) -> String:
	if observation == null or macro == null or not macro.debug.has("marketing_service_features"):
		return ""
	if _own_income_started(observation):
		return ""
	var features_val = macro.debug.get("marketing_service_features", {})
	if not (features_val is Dictionary):
		return ""
	var features: Dictionary = features_val
	var self_capture := int(features.get("self_capture_houses", features.get("competitive_houses", 0)))
	var opponent_pressure := int(features.get("opponent_pressure_houses", features.get("opponent_capacity_gap_houses", 0)))
	if self_capture > 0 or opponent_pressure <= 0:
		return ""
	return "%s: strategy_filter opponent-pressure marketing needs own income" % macro.id

static func _own_income_started(observation: ObservationState) -> bool:
	if observation == null:
		return true
	if int(observation.own_player.get("cash", 0)) > 0:
		return true
	var milestones_val = observation.own_player.get("milestones", [])
	if milestones_val is Array:
		for milestone_val in Array(milestones_val):
			var milestone_id := str(milestone_val)
			if milestone_id == "first_have_20" or milestone_id == "first_have_100":
				return true
	return false

static func _strict_marketing_must_affect_houses(profile) -> bool:
	if profile == null:
		return true
	if profile.get("strict_marketing_must_affect_houses") != null:
		return bool(profile.strict_marketing_must_affect_houses)
	return true
