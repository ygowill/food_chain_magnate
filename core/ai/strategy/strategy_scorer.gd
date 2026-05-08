class_name StrategyScorer
extends RefCounted

const MilestoneRaceAnalyzerClass = preload("res://core/ai/analysis/milestone_race_analyzer.gd")
const StrategyBoardAnalyzerClass = preload("res://core/ai/strategy/strategy_board_analyzer.gd")
const StrategyCashPlannerClass = preload("res://core/ai/strategy/strategy_cash_planner.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyMarketingPlannerClass = preload("res://core/ai/strategy/strategy_marketing_planner.gd")
const StrategyRecruitPlannerClass = preload("res://core/ai/strategy/strategy_recruit_planner.gd")
const StrategySetupPlannerClass = preload("res://core/ai/strategy/strategy_setup_planner.gd")
const StrategyStructurePlannerClass = preload("res://core/ai/strategy/strategy_structure_planner.gd")
const StrategySupportPlannerClass = preload("res://core/ai/strategy/strategy_support_planner.gd")
const StrategySupplyPlannerClass = preload("res://core/ai/strategy/strategy_supply_planner.gd")
const StrategyTrainPlannerClass = preload("res://core/ai/strategy/strategy_train_planner.gd")

static func score_macro(observation: ObservationState, macro: MacroAction, profile, options: Dictionary = {}) -> Dictionary:
	if observation == null or macro == null or profile == null or macro.commands.is_empty():
		return {"score": -INF, "features": {}}
	var command: Command = macro.commands[0]
	if command == null:
		return {"score": -INF, "features": {}}

	var action_id := str(command.action_id)
	var income_analysis_val = options.get("income_analysis", null)
	var income_analysis := Dictionary(income_analysis_val) if income_analysis_val is Dictionary else StrategyIncomeAnalyzerClass.analyze(observation, profile, options.get("source_state", null))
	var features := {
		"action_weight": profile.action_weight(action_id),
		"candidate_prior": float(macro.prior_score),
		"income_total_public_demand": int(income_analysis.get("total_public_demand", 0)),
		"income_total_actionable_demand": int(income_analysis.get("total_actionable_demand", income_analysis.get("total_serviceable_demand", 0))),
		"income_total_lost_to_competitor_demand": int(income_analysis.get("total_lost_to_competitor_demand", 0)),
		"income_total_price_recoverable_demand": int(income_analysis.get("total_price_recoverable_demand", 0)),
		"income_total_own_sourced_opponent_blocking_demand": int(income_analysis.get("total_own_sourced_opponent_blocking_demand", 0)),
		"income_total_inventory_gap": int(income_analysis.get("total_inventory_gap", 0)),
		"income_total_actionable_inventory_gap": int(income_analysis.get("total_actionable_inventory_gap", income_analysis.get("total_inventory_gap", 0))),
		"income_total_pending_marketing_demand": int(income_analysis.get("total_pending_marketing_demand", 0)),
		"income_total_pending_defensive_marketing_demand": int(income_analysis.get("total_pending_defensive_marketing_demand", 0)),
	}
	var score := float(features["action_weight"]) + float(macro.prior_score)
	var strategy_precondition_failed := false

	match action_id:
		"recruit":
			var recruit_payload := StrategyRecruitPlannerClass.evaluate_action(observation, command, profile, income_analysis)
			_merge_features(features, Dictionary(recruit_payload.get("features", {})))
			score += float(recruit_payload.get("value", 0.0))
		"train":
			var train_payload := StrategyTrainPlannerClass.evaluate_action(observation, command, profile, income_analysis)
			_merge_features(features, Dictionary(train_payload.get("features", {})))
			score += float(train_payload.get("value", 0.0))
		"set_company_structure_direct", "set_company_structure_report", "restructure_employee":
			var structure_payload := StrategyStructurePlannerClass.evaluate_action(observation, command, profile, income_analysis)
			_merge_features(features, Dictionary(structure_payload.get("features", {})))
			score += float(structure_payload.get("value", 0.0))
		"initiate_marketing":
			var affected_ids := _affected_house_ids(macro)
			var marketing_options := options.duplicate()
			if macro.debug.has("marketing_service_features"):
				marketing_options["marketing_service_features"] = Dictionary(macro.debug.get("marketing_service_features", {})).duplicate(true)
			var marketing_payload := StrategyMarketingPlannerClass.evaluate(observation, command, affected_ids, profile, income_analysis, marketing_options)
			_merge_features(features, Dictionary(marketing_payload.get("features", {})))
			score += float(marketing_payload.get("value", 0.0))
		"produce_food", "procure_drinks":
			var supply_payload := StrategySupplyPlannerClass.evaluate_action(observation, command, profile, income_analysis, options)
			_merge_features(features, Dictionary(supply_payload.get("features", {})))
			var supply_bonus := float(supply_payload.get("value", 0.0))
			features["product_supply_action_value"] = supply_bonus
			score += supply_bonus
			if StrategySupplyPlannerClass.should_defer_supply(features):
				strategy_precondition_failed = true
				features["strategy_precondition_failed"] = "supply_should_be_deferred"
		"set_price", "set_discount", "set_luxury_price":
			var price_payload := StrategySupportPlannerClass.evaluate_price_action(observation, command, income_analysis, options.get("source_state", null))
			_merge_features(features, Dictionary(price_payload.get("features", {})))
			score += float(price_payload.get("value", 0.0))
		"select_reserve_card":
			var reserve_payload := StrategySetupPlannerClass.evaluate_action(observation, command)
			_merge_features(features, Dictionary(reserve_payload.get("features", {})))
			score += float(reserve_payload.get("value", 0.0))
		"place_house":
			var house_payload := StrategyBoardAnalyzerClass.evaluate_house_action(observation, command.params)
			_merge_features(features, Dictionary(house_payload.get("features", {})))
			score += float(house_payload.get("value", 0.0))
		"place_restaurant", "move_restaurant":
			var source_analysis := {}
			var source_analysis_val = options.get("source_analysis", {})
			if source_analysis_val is Dictionary:
				source_analysis = source_analysis_val
			var placement_payload := StrategyBoardAnalyzerClass.evaluate_restaurant_action(
				observation,
				command.params,
				income_analysis,
				options.get("source_state", null),
				action_id,
				int(command.actor),
				source_analysis
			)
			_merge_features(features, Dictionary(placement_payload.get("features", {})))
			score += float(placement_payload.get("value", 0.0))
		"fire":
			var employee_id3 := str(command.params.get("employee_id", ""))
			var fire_payload := StrategyCashPlannerClass.fire_value(observation, command, profile, income_analysis, options)
			_merge_features(features, Dictionary(fire_payload.get("features", {})))
			if not features.has("fire_employee_id"):
				features["fire_employee_id"] = employee_id3
			score += float(fire_payload.get("value", 0.0))
		"choose_turn_order":
			var turn_order_payload := StrategySetupPlannerClass.evaluate_action(observation, command)
			_merge_features(features, Dictionary(turn_order_payload.get("features", {})))
			score += float(turn_order_payload.get("value", 0.0))
		"skip", "skip_sub_phase":
			var skip_penalty := -10.0 if _has_non_skip_alternative(observation, macro) else 0.0
			features["skip_penalty"] = skip_penalty
			score += skip_penalty

	var milestone_payload := MilestoneRaceAnalyzerClass.score_macro(observation, macro, profile)
	var milestone_score := float(milestone_payload.get("score", 0.0))
	features["milestone_race_value"] = milestone_score
	if strategy_precondition_failed or _should_suppress_deferred_supply_milestone(action_id, features):
		if milestone_score > 0.0:
			features["milestone_race_suppressed_deferred_supply"] = true
			if bool(features.get("product_no_demand_supply_deferred", false)):
				features["milestone_race_suppressed_no_demand_supply"] = true
			features["milestone_race_suppressed_value"] = milestone_score
		milestone_score = 0.0
		features["milestone_race_value"] = 0.0
	if milestone_score > 0.0:
		features["milestone_race_ids"] = Array(milestone_payload.get("milestone_ids", [])).duplicate()
		features["milestone_race_candidates"] = Array(milestone_payload.get("milestones", [])).duplicate(true)
		score += milestone_score
	if strategy_precondition_failed:
		score = -INF

	return {
		"score": score,
		"features": features,
	}

static func _merge_features(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		target[key] = source[key]

static func _affected_house_ids(macro: MacroAction) -> Array[String]:
	var out: Array[String] = []
	if macro == null:
		return out
	var affected_val = macro.debug.get("affected_house_ids", [])
	if affected_val is Array:
		for house_id_val in Array(affected_val):
			var house_id := str(house_id_val)
			if not house_id.is_empty() and not out.has(house_id):
				out.append(house_id)
	return out

static func _has_non_skip_alternative(_observation: ObservationState, _macro: MacroAction) -> bool:
	return true

static func _should_suppress_deferred_supply_milestone(action_id: String, features: Dictionary) -> bool:
	if action_id != "produce_food" and action_id != "procure_drinks":
		return false
	if not StrategySupplyPlannerClass.should_defer_supply(features):
		return false
	if int(features.get("product_public_demand", 0)) > 0:
		return false
	if int(features.get("product_effective_pending_marketing_demand", 0)) > 0:
		return false
	if int(features.get("product_effective_planning_inventory_gap", 0)) > 0:
		return false
	return true
