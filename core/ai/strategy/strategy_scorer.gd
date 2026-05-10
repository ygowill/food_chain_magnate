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
const StrategyPlanHintsClass = preload("res://core/ai/planning/strategic_plan_hints.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

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
	var hints_bonus := _plan_hints_bonus(observation, macro, options, features)
	if not is_equal_approx(hints_bonus, 0.0):
		features["plan_hints_bonus"] = hints_bonus
		score += hints_bonus
	var plan_id := _plan_hints_plan_id(options)
	if not plan_id.is_empty():
		features["plan_id"] = plan_id
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

static func _plan_hints_bonus(
	_observation: ObservationState,
	macro: MacroAction,
	options: Dictionary,
	features: Dictionary
) -> float:
	var hints := _plan_hints_dict(options)
	if hints.is_empty() or macro == null or macro.commands.is_empty():
		return 0.0
	var command: Command = macro.commands[0]
	if command == null:
		return 0.0
	var action_id := str(command.action_id)
	var avoid_actions := _string_array(hints.get("avoid_actions", []))
	if avoid_actions.has(action_id):
		return -24.0
	var bonus := 0.0
	var preferred_products := _string_array(hints.get("preferred_products", []))
	var preferred_employee_ids := _string_array(hints.get("preferred_employee_ids", []))
	var preferred_roles := _string_array(hints.get("preferred_employee_roles", []))
	var preferred_price_actions := _string_array(hints.get("preferred_price_actions", []))
	var preferred_actions := _string_array(hints.get("preferred_actions", []))
	var execution_sequence := _ordered_string_array(hints.get("execution_sequence", []))
	var preferred_houses := _string_array(hints.get("preferred_marketing_house_ids", []))
	var preferred_boards := _int_array(hints.get("preferred_marketing_board_numbers", []))
	var sequence_index := execution_sequence.find(action_id)
	if sequence_index >= 0:
		var sequence_bonus := maxf(0.0, 14.0 - float(sequence_index) * 2.0)
		bonus += sequence_bonus
		features["plan_hints_sequence_match"] = action_id
		features["plan_hints_sequence_index"] = sequence_index
	if preferred_actions.has(action_id):
		bonus += 8.0
		features["plan_hints_action_match"] = action_id
	var command_products := _command_products(command, features)
	for product_id in command_products:
		if preferred_products.has(product_id):
			bonus += 22.0
	var employee_id := _command_employee_id(command)
	if not employee_id.is_empty() and preferred_employee_ids.has(employee_id):
		bonus += 18.0
	var role := _command_employee_role(command, features)
	if not role.is_empty() and preferred_roles.has(role):
		bonus += 12.0
	if preferred_price_actions.has(action_id):
		bonus += 24.0
	if action_id == "initiate_marketing":
		var board_number := int(command.params.get("board_number", -1))
		if preferred_boards.has(board_number):
			bonus += 8.0
		if not preferred_houses.is_empty():
			var affected := _affected_house_ids(macro)
			for house_id in affected:
				if preferred_houses.has(house_id):
					bonus += 6.0
	if action_id == "place_house" or action_id == "add_garden" or action_id == "place_restaurant" or action_id == "move_restaurant":
		bonus += maxf(0.0, float(hints.get("growth_bias", 0.0))) * 12.0
	if int(hints.get("cash_floor", 0)) > 0 and action_id == "fire":
		bonus += 4.0
	return bonus

static func _plan_hints_dict(options: Dictionary) -> Dictionary:
	var value = options.get("plan_hints", null)
	if value != null and value.has_method("to_dict"):
		var dict_val = value.to_dict()
		if dict_val is Dictionary:
			return Dictionary(dict_val)
	if value is Dictionary:
		return Dictionary(value)
	return {}

static func _plan_hints_plan_id(options: Dictionary) -> String:
	var hints := _plan_hints_dict(options)
	return str(hints.get("plan_id", "")).strip_edges()

static func _command_products(command: Command, features: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if command == null:
		return out
	for key in ["product", "food_type", "drink_type"]:
		var value := str(command.params.get(key, "")).strip_edges()
		if not value.is_empty() and not out.has(value):
			out.append(value)
	var product_id := str(features.get("product_id", "")).strip_edges()
	if not product_id.is_empty() and not out.has(product_id):
		out.append(product_id)
	return out

static func _command_employee_id(command: Command) -> String:
	if command == null:
		return ""
	for key in ["employee_type", "employee_id", "from_employee", "to_employee"]:
		var value := str(command.params.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

static func _command_employee_role(command: Command, features: Dictionary) -> String:
	for key in ["employee_role", "recruit_role", "target_employee_role", "structure_employee_role"]:
		var value := str(features.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	if command != null:
		match str(command.action_id):
			"initiate_marketing":
				return "marketing"
			"produce_food":
				return "produce_food"
			"procure_drinks":
				return "procure_drink"
		var employee_id := _command_employee_id(command)
		if not employee_id.is_empty() and EmployeeRegistryClass.is_loaded() and EmployeeRegistryClass.has(employee_id):
			var def_val = EmployeeRegistryClass.get_def(employee_id)
			if def_val is EmployeeDef:
				return str((def_val as EmployeeDef).role)
	return ""

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out

static func _int_array(value) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for item in Array(value):
			if item is int or item is float:
				var n := int(item)
				if not out.has(n):
					out.append(n)
	out.sort()
	return out

static func _ordered_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	return out
