class_name StrategyScorer
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const DinnerPreviewClass = preload("res://core/ai/analysis/dinner_preview.gd")
const MilestoneRaceAnalyzerClass = preload("res://core/ai/analysis/milestone_race_analyzer.gd")
const StrategyBoardAnalyzerClass = preload("res://core/ai/strategy/strategy_board_analyzer.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")

static func score_macro(observation: ObservationState, macro: MacroAction, profile, options: Dictionary = {}) -> Dictionary:
	if observation == null or macro == null or profile == null or macro.commands.is_empty():
		return {"score": -INF, "features": {}}
	var command: Command = macro.commands[0]
	if command == null:
		return {"score": -INF, "features": {}}

	var action_id := str(command.action_id)
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile)
	var features := {
		"action_weight": profile.action_weight(action_id),
		"candidate_prior": float(macro.prior_score),
		"income_total_public_demand": int(income_analysis.get("total_public_demand", 0)),
		"income_total_inventory_gap": int(income_analysis.get("total_inventory_gap", 0)),
	}
	var score := float(features["action_weight"]) + float(macro.prior_score)

	match action_id:
		"recruit":
			var employee_id := str(command.params.get("employee_type", ""))
			var bonus := _employee_strategy_value(observation, employee_id, profile, income_analysis)
			var placement_route_value := _placement_route_value(observation, employee_id, income_analysis)
			var roster_payload := _recruit_roster_adjustment(observation, employee_id, income_analysis)
			var roster_adjustment := float(roster_payload.get("adjustment", 0.0))
			features["employee_value"] = bonus
			features["recruit_placement_route_value"] = placement_route_value
			features["recruit_owned_count"] = int(roster_payload.get("owned_count", 0))
			features["recruit_desired_count"] = int(roster_payload.get("desired_count", 0))
			features["recruit_roster_saturated"] = bool(roster_payload.get("saturated", false))
			features["recruit_roster_adjustment"] = roster_adjustment
			_append_employee_income_features(features, observation, employee_id, income_analysis, profile, "recruit")
			score += bonus + roster_adjustment
		"train":
			var from_employee := str(command.params.get("from_employee", ""))
			var to_employee := str(command.params.get("to_employee", ""))
			var target_value := StrategyIncomeAnalyzerClass.employee_value(observation, to_employee, profile, income_analysis)
			var train_placement_route_value := _placement_route_value(observation, to_employee, income_analysis)
			var train_bonus: float = float(target_value.get("score", 0.0)) * 1.2 + maxf(0.0, float(profile.employee_priority(to_employee)) - float(profile.employee_priority(from_employee))) + train_placement_route_value
			features["train_value"] = train_bonus
			features["train_target_income_value"] = float(target_value.get("score", 0.0))
			features["train_placement_route_value"] = train_placement_route_value
			features["train_target_products"] = Array(target_value.get("target_products", [])).duplicate()
			score += train_bonus
		"set_company_structure_direct", "set_company_structure_report", "restructure_employee":
			var employee_id2 := str(command.params.get("employee_id", ""))
			var structure_bonus := _employee_strategy_value(observation, employee_id2, profile, income_analysis)
			features["structure_employee_value"] = structure_bonus
			features["structure_placement_route_value"] = _placement_route_value(observation, employee_id2, income_analysis)
			_append_employee_income_features(features, observation, employee_id2, income_analysis, profile, "structure")
			score += structure_bonus
		"initiate_marketing":
			var product_id := str(command.params.get("product", ""))
			var affected_ids := _affected_house_ids(macro)
			var affected_count := affected_ids.size()
			var pipeline_value := _product_pipeline_value(product_id, profile, income_analysis, features)
			var service_features := _marketing_service_features(observation, affected_ids, product_id, options.get("source_state", null))
			var marketing_bonus := _marketing_value_from_features(affected_count, pipeline_value, service_features)
			features["affected_houses"] = affected_count
			features["affected_house_ids"] = affected_ids.duplicate()
			features["product_pipeline_value"] = pipeline_value
			features["marketing_serviceable_houses"] = int(service_features.get("serviceable_houses", 0))
			features["marketing_closest_distance"] = int(service_features.get("closest_distance", -1))
			features["marketing_inventory_units"] = int(service_features.get("inventory_units", 0))
			features["marketing_can_supply_product"] = bool(service_features.get("can_supply_product", false))
			features["marketing_own_restaurants"] = int(service_features.get("own_restaurants", 0))
			features["marketing_distance_source"] = str(service_features.get("distance_source", "anchor"))
			features["marketing_value"] = marketing_bonus
			score += marketing_bonus
		"produce_food", "procure_drinks":
			var supply_bonus := _supply_action_value(observation, command, profile, income_analysis, features, options)
			features["product_supply_action_value"] = supply_bonus
			score += supply_bonus
		"set_price", "set_discount", "set_luxury_price":
			var price_payload := _price_action_value(observation, command, income_analysis, options.get("source_state", null))
			_append_price_features(features, price_payload)
			score += float(price_payload.get("value", 0.0))
		"select_reserve_card":
			var reserve_payload := _reserve_card_value(observation, command.params)
			_append_reserve_card_features(features, reserve_payload)
			score += float(reserve_payload.get("value", 0.0))
		"place_house":
			var house_payload := _house_placement_value(observation, command.params)
			_append_house_placement_features(features, house_payload)
			score += float(house_payload.get("value", 0.0))
		"place_restaurant", "move_restaurant":
			var placement_payload := StrategyBoardAnalyzerClass.restaurant_placement_value(
				observation,
				command.params,
				income_analysis,
				options.get("source_state", null),
				action_id,
				int(command.actor)
			)
			var restaurant_bonus := _restaurant_action_base_value(action_id, observation) + float(placement_payload.get("placement_value", 0.0))
			features["restaurant_value"] = restaurant_bonus
			_append_restaurant_placement_features(features, placement_payload)
			score += restaurant_bonus
		"fire":
			var employee_id3 := str(command.params.get("employee_id", ""))
			var fire_payload := _fire_value(observation, employee_id3, profile, income_analysis)
			features["fire_employee_id"] = employee_id3
			features["fire_location"] = str(command.params.get("location", ""))
			features["fire_payday_cash"] = int(fire_payload.get("cash", 0))
			features["fire_payday_due"] = int(fire_payload.get("due", 0))
			features["fire_payday_shortfall"] = int(fire_payload.get("shortfall", 0))
			features["fire_effective_salary_relief"] = int(fire_payload.get("effective_salary_relief", 0))
			features["fire_employee_income_value"] = float(fire_payload.get("employee_income_value", 0.0))
			features["fire_value"] = float(fire_payload.get("value", 0.0))
			score += float(fire_payload.get("value", 0.0))
		"choose_turn_order":
			var position := int(command.params.get("position", 0))
			var turn_bonus := maxf(0.0, 8.0 - float(position) * 2.0)
			features["turn_order_value"] = turn_bonus
			score += turn_bonus
		"skip", "skip_sub_phase":
			var skip_penalty := -10.0 if _has_non_skip_alternative(observation, macro) else 0.0
			features["skip_penalty"] = skip_penalty
			score += skip_penalty

	var milestone_payload := MilestoneRaceAnalyzerClass.score_macro(observation, macro, profile)
	var milestone_score := float(milestone_payload.get("score", 0.0))
	features["milestone_race_value"] = milestone_score
	if milestone_score > 0.0:
		features["milestone_race_ids"] = Array(milestone_payload.get("milestone_ids", [])).duplicate()
		features["milestone_race_candidates"] = Array(milestone_payload.get("milestones", [])).duplicate(true)
		score += milestone_score

	return {
		"score": score,
		"features": features,
	}

static func _employee_strategy_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> float:
	if employee_id.is_empty():
		return 0.0
	var income_value := StrategyIncomeAnalyzerClass.employee_value(observation, employee_id, profile, income_analysis)
	var value: float = float(income_value.get("score", profile.employee_priority(employee_id)))
	var role := _employee_role(employee_id)
	if role == "produce_food" and not _owns_role(observation, "produce_food"):
		value += 8.0
	elif role == "marketing" and not _owns_role(observation, "marketing"):
		value += 7.0
	elif role == "procure_drink" and not _owns_role(observation, "procure_drink"):
		value += 6.0
	elif role == "recruit_train" and _has_trainable_reserve_employee(observation):
		value += 5.0
	elif role == "new_shop" and _own_restaurant_count(observation) <= 1:
		value += 3.0
	value += _placement_route_value(observation, employee_id, income_analysis)
	return value

static func _placement_route_value(observation: ObservationState, employee_id: String, income_analysis: Dictionary) -> float:
	if observation == null or employee_id.is_empty():
		return 0.0
	if not _has_house_growth_space(observation):
		return 0.0
	if _has_owned_placement_employee(observation):
		if employee_id != "new_business_developer" or _has_active_placement_employee(observation):
			return 0.0
	var pressure := _house_growth_pressure(observation, income_analysis)
	var economy_ready := _house_route_economy_ready(observation, income_analysis)
	match employee_id:
		"new_business_developer":
			if not economy_ready:
				return 0.0
			return 18.0 + pressure * 0.5
		"management_trainee":
			if _owns_any_employee(observation, ["management_trainee", "new_business_developer"]):
				return 0.0
			if not economy_ready:
				return 0.0
			return 7.0 + pressure * 0.2
		"trainer":
			if _owns_any_employee(observation, ["trainer", "new_business_developer"]):
				return 0.0
			if _owns_any_employee(observation, ["management_trainee"]):
				if not economy_ready:
					return 0.0
				return 5.0 + pressure * 0.15
	return 0.0

static func _house_route_economy_ready(observation: ObservationState, income_analysis: Dictionary) -> bool:
	if observation == null:
		return false
	var salary_cost := _read_non_negative_int(observation.rules_public.get("salary_cost", 5), 5)
	var cash := _read_non_negative_int(observation.own_player.get("cash", 0), 0)
	var required_cash := maxi(10, salary_cost * 3)
	if cash < required_cash:
		return false
	if not _owns_role(observation, "produce_food"):
		return false
	if not _owns_role(observation, "marketing"):
		return false
	return int(income_analysis.get("total_public_demand", 0)) >= 2 or int(income_analysis.get("total_serviceable_demand", 0)) >= 2

static func _house_growth_pressure(observation: ObservationState, income_analysis: Dictionary) -> float:
	if observation == null:
		return 0.0
	var pressure := float(mini(_remaining_house_number_count(observation), 4)) * 2.0
	if _has_garden_growth_space(observation):
		pressure += 2.0
	if _own_restaurant_count(observation) > 0:
		pressure += 4.0
	var public_demand := int(income_analysis.get("total_public_demand", 0))
	if public_demand >= 8:
		pressure += 4.0
	elif public_demand >= 4:
		pressure += 2.0
	return pressure

static func _has_house_growth_space(observation: ObservationState) -> bool:
	return _remaining_house_number_count(observation) > 0 or _has_garden_growth_space(observation)

static func _remaining_house_number_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var remaining_val = observation.map_public.get("house_number_supply_remaining", [])
	if not (remaining_val is Array):
		return 0
	return Array(remaining_val).size()

static func _has_garden_growth_space(observation: ObservationState) -> bool:
	if observation == null:
		return false
	if _read_non_negative_int(observation.map_public.get("garden_supply_remaining", 0), 0) <= 0:
		return false
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return false
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		if not bool(Dictionary(house_val).get("has_garden", true)):
			return true
	return false

static func _has_owned_placement_employee(observation: ObservationState) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if _employee_is_placement_employee(employee_id):
			return true
	return false

static func _has_active_placement_employee(observation: ObservationState) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _active_employee_ids(observation.own_player):
		if _employee_is_placement_employee(employee_id):
			return true
	return false

static func _employee_is_placement_employee(employee_id: String) -> bool:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	return def.has_tag("place_house_or_garden") or def.has_usage_tag("use:place_house") or def.has_usage_tag("use:add_garden")

static func _recruit_roster_adjustment(observation: ObservationState, employee_id: String, income_analysis: Dictionary) -> Dictionary:
	var owned_count := _count_owned_employee(observation.own_player if observation != null else {}, employee_id)
	var desired_count := _desired_recruit_count(observation, employee_id, income_analysis)
	var saturated := owned_count >= desired_count
	var adjustment := 0.0
	if saturated:
		adjustment -= 115.0 + float(maxi(0, owned_count - desired_count)) * 25.0
	return {
		"owned_count": owned_count,
		"desired_count": desired_count,
		"saturated": saturated,
		"adjustment": adjustment,
	}

static func _desired_recruit_count(observation: ObservationState, employee_id: String, income_analysis: Dictionary) -> int:
	if observation == null or employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return 0
	var role := _employee_role(employee_id)
	match employee_id:
		"kitchen_trainee":
			var public_demand := int(income_analysis.get("total_public_demand", 0))
			var inventory_gap := int(income_analysis.get("total_inventory_gap", 0))
			return 2 if public_demand >= 5 or inventory_gap >= 4 else 1
		"marketing_trainee":
			if _owns_any_employee(observation, ["campaign_manager", "brand_manager", "brand_director"]):
				return 0
			return 1 if int(income_analysis.get("own_restaurants", 0)) > 0 else 0
		"errand_boy":
			return 1
		"trainer":
			return 1 if _has_trainable_owned_employee(observation) else 0
		"management_trainee":
			if _owns_any_employee(observation, ["management_trainee", "new_business_developer", "junior_vice_president", "luxury_manager"]):
				return 0
			return 1
		"recruiting_girl":
			return 1
	if role == "new_shop":
		var unserviceable := int(income_analysis.get("total_public_demand", 0)) - int(income_analysis.get("total_serviceable_demand", 0))
		return 1 if unserviceable > 0 or _own_restaurant_count(observation) <= 1 else 0
	if role == "produce_food":
		return 2 if int(income_analysis.get("total_public_demand", 0)) >= 6 else 1
	if role == "marketing" or role == "procure_drink" or role == "recruit_train" or role == "price":
		return 1
	return 1

static func _product_pipeline_value(product_id: String, profile, income_analysis: Dictionary, features: Dictionary) -> float:
	if product_id.is_empty():
		return 0.0
	var product_payload := StrategyIncomeAnalyzerClass.product_value(product_id, profile, income_analysis)
	features["product_public_demand"] = int(product_payload.get("public_demand", 0))
	features["product_serviceable_demand"] = int(product_payload.get("serviceable_demand", 0))
	features["product_inventory_units"] = int(product_payload.get("inventory_units", 0))
	features["product_inventory_gap"] = int(product_payload.get("inventory_gap", 0))
	features["product_can_supply"] = bool(product_payload.get("can_supply", false))
	return float(product_payload.get("score", 0.0))

static func _supply_action_value(observation: ObservationState, command: Command, profile, income_analysis: Dictionary, features: Dictionary, options: Dictionary = {}) -> float:
	if command == null:
		return 0.0
	var action_id := str(command.action_id)
	var product_id := str(command.params.get("food_type", command.params.get("drink_type", "")))
	if action_id == "procure_drinks" and product_id.is_empty():
		return _route_drink_supply_action_value(observation, command, profile, income_analysis, features)
	var expected_units := _expected_supply_units(observation, command)
	var supply_bonus := _product_supply_action_value(product_id, profile, income_analysis, features, expected_units)
	features["product_supply_expected_units"] = expected_units
	var no_demand_penalty := _no_demand_food_cash_safety_penalty(observation, command, features)
	if not is_equal_approx(no_demand_penalty, 0.0):
		features["product_no_demand_cash_safety_penalty"] = no_demand_penalty
	var preview_value := _dinner_preview_supply_value(observation, command, options, features)
	return supply_bonus + no_demand_penalty + preview_value

static func _route_drink_supply_action_value(observation: ObservationState, command: Command, profile, income_analysis: Dictionary, features: Dictionary) -> float:
	var expected_by_product := _expected_route_drinks_by_product(observation, command)
	features["drink_route_expected_units_by_product"] = expected_by_product.duplicate(true)
	if expected_by_product.is_empty():
		features["drink_route_missing_source_types"] = true
		return 0.0
	var product_ids := _sorted_dictionary_keys(expected_by_product)
	var product_values := {}
	var total_value := 0.0
	var total_expected_units := 0
	var total_covered_units := 0
	var total_excess_units := 0
	var total_buffer_units := 0
	var best_product := ""
	var best_product_value := -INF
	var best_features := {}
	for product_id in product_ids:
		var expected_units := maxi(1, int(expected_by_product.get(product_id, 0)))
		var product_features := {}
		var product_value := _product_supply_action_value(product_id, profile, income_analysis, product_features, expected_units)
		product_values[product_id] = product_value
		total_value += product_value
		total_expected_units += expected_units
		total_covered_units += int(product_features.get("product_supply_covered_units", 0))
		total_excess_units += int(product_features.get("product_supply_excess_units", 0))
		total_buffer_units += int(product_features.get("product_supply_buffer_units", 0))
		if best_product.is_empty() or product_value > best_product_value:
			best_product = product_id
			best_product_value = product_value
			best_features = product_features
	features["drink_route_product_values"] = product_values
	features["product_supply_products"] = product_ids.duplicate()
	features["product_supply_expected_units"] = total_expected_units
	features["product_supply_covered_units"] = total_covered_units
	features["product_supply_excess_units"] = total_excess_units
	if total_buffer_units > 0:
		features["product_supply_buffer_units"] = total_buffer_units
	if not best_product.is_empty():
		features["product_supply_primary_product"] = best_product
		for key in ["product_public_demand", "product_serviceable_demand", "product_inventory_units", "product_inventory_gap", "product_can_supply"]:
			if best_features.has(key):
				features[key] = best_features[key]
		if bool(best_features.get("product_overstock_penalty", false)):
			features["product_overstock_penalty"] = true
	return total_value

static func _product_supply_action_value(product_id: String, profile, income_analysis: Dictionary, features: Dictionary, expected_units: int = 1) -> float:
	if product_id.is_empty():
		return 0.0
	var product_payload := StrategyIncomeAnalyzerClass.product_value(product_id, profile, income_analysis)
	var public_demand := int(product_payload.get("public_demand", 0))
	var serviceable_demand := int(product_payload.get("serviceable_demand", 0))
	var inventory_units := int(product_payload.get("inventory_units", 0))
	var inventory_gap := int(product_payload.get("inventory_gap", 0))
	var can_supply := bool(product_payload.get("can_supply", false))
	var supply_units := maxi(1, expected_units)
	features["product_public_demand"] = public_demand
	features["product_serviceable_demand"] = serviceable_demand
	features["product_inventory_units"] = inventory_units
	features["product_inventory_gap"] = inventory_gap
	features["product_can_supply"] = can_supply
	if inventory_gap > 0:
		var covered_units := mini(inventory_gap, supply_units)
		var excess_units := maxi(0, supply_units - inventory_gap)
		features["product_supply_covered_units"] = covered_units
		features["product_supply_excess_units"] = excess_units
		return float(covered_units) * 14.0 + float(serviceable_demand) * 3.0 + float(public_demand) + float(profile.product_priority(product_id)) * 0.5 - float(excess_units) * 3.0
	if public_demand <= 0 and inventory_units <= 0:
		return float(profile.product_priority(product_id)) * 0.6
	var desired_buffer := public_demand + 1
	if public_demand > 0 and inventory_units < desired_buffer:
		var buffer_units := mini(supply_units, maxi(0, desired_buffer - inventory_units))
		features["product_supply_buffer_units"] = buffer_units
		return 4.0 + float(buffer_units) * 2.0 + float(profile.product_priority(product_id)) * 0.25
	features["product_overstock_penalty"] = true
	return -100.0 - float(maxi(0, inventory_units + supply_units - desired_buffer)) * 8.0

static func _no_demand_food_cash_safety_penalty(observation: ObservationState, command: Command, features: Dictionary) -> float:
	if observation == null or command == null:
		return 0.0
	if str(command.action_id) != "produce_food":
		return 0.0
	if int(features.get("product_public_demand", 0)) > 0:
		return 0.0
	if int(features.get("product_serviceable_demand", 0)) > 0:
		return 0.0
	if int(features.get("product_inventory_gap", 0)) > 0:
		return 0.0
	if int(features.get("product_inventory_units", 0)) > 0:
		return 0.0
	var salary_cost := _read_non_negative_int(observation.rules_public.get("salary_cost", 5), 5)
	if salary_cost <= 0:
		return 0.0
	var cash := _read_non_negative_int(observation.own_player.get("cash", 0), 0)
	if cash >= salary_cost:
		return 0.0
	return -125.0

static func _dinner_preview_supply_value(observation: ObservationState, command: Command, options: Dictionary, features: Dictionary) -> float:
	if observation == null or command == null:
		return 0.0
	if str(command.action_id) != "produce_food":
		return 0.0
	if int(features.get("product_public_demand", 0)) <= 0:
		return 0.0
	var engine_val = options.get("source_engine", null)
	if not (engine_val is GameEngine):
		return 0.0
	var preview_read := DinnerPreviewClass.preview_after_commands(engine_val, [command], {"max_steps": 24})
	if not preview_read.ok:
		features["product_dinner_preview_error"] = preview_read.error
		return 0.0
	var payload: Dictionary = Dictionary(preview_read.value)
	var actor := int(command.actor)
	var total_income := _read_indexed_int(payload.get("total_income", []), actor, 0)
	var income_sales := _read_indexed_int(payload.get("income_sales", []), actor, 0)
	features["product_dinner_preview_income"] = total_income
	features["product_dinner_preview_sales_income"] = income_sales
	features["product_dinner_preview_source"] = "dinner_preview"
	var value := float(total_income) * 0.35
	if total_income <= 0 and int(features.get("product_public_demand", 0)) > 0 and _cash_below_salary_cost(observation):
		var penalty := -155.0
		features["product_dinner_preview_no_income_penalty"] = penalty
		value += penalty
	return value

static func _cash_below_salary_cost(observation: ObservationState) -> bool:
	if observation == null:
		return false
	var salary_cost := _read_non_negative_int(observation.rules_public.get("salary_cost", 5), 5)
	if salary_cost <= 0:
		return false
	var cash := _read_non_negative_int(observation.own_player.get("cash", 0), 0)
	return cash < salary_cost

static func _read_indexed_int(value, index: int, fallback: int) -> int:
	if index < 0:
		return fallback
	if value is Array:
		var arr: Array = value
		if index < arr.size():
			return _read_int(arr[index], fallback)
	return fallback

static func _expected_supply_units(observation: ObservationState, command: Command) -> int:
	if command == null:
		return 1
	var action_id := str(command.action_id)
	if action_id == "produce_food":
		return _expected_food_units(str(command.params.get("employee_type", "")))
	if action_id == "procure_drinks":
		return _expected_drink_units(observation, command)
	return 1

static func _expected_food_units(employee_id: String) -> int:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return 1
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return 1
	var def: EmployeeDef = def_val
	return maxi(1, int(def.produces_amount)) if not str(def.produces_food_type).is_empty() else 1

static func _expected_drink_units(observation: ObservationState, command: Command) -> int:
	var employee_id := str(command.params.get("employee_type", ""))
	if employee_id == "errand_boy":
		return 2 if _own_milestones(observation).has("first_errand_boy") else 1
	var selected_val = command.params.get("selected_sources", [])
	if selected_val is Array:
		return maxi(1, Array(selected_val).size() * _route_drinks_per_source(observation, command))
	return 1

static func _expected_route_drinks_by_product(observation: ObservationState, command: Command) -> Dictionary:
	var type_counts := _selected_drink_source_type_counts(observation, command)
	if type_counts.is_empty():
		return {}
	var per_source := _route_drinks_per_source(observation, command)
	var out := {}
	for product_id in _sorted_dictionary_keys(type_counts):
		out[product_id] = maxi(1, int(type_counts.get(product_id, 0))) * per_source
	return out

static func _selected_drink_source_type_counts(observation: ObservationState, command: Command) -> Dictionary:
	if observation == null or command == null:
		return {}
	var selected_val = command.params.get("selected_sources", [])
	if not (selected_val is Array):
		return {}
	var lookup := _drink_source_types_by_position(observation.map_public)
	if lookup.is_empty():
		return {}
	var counts := {}
	for selected_pos_val in Array(selected_val):
		var pos := _read_vector2i(selected_pos_val)
		var product_id := str(lookup.get(_vector_key(pos), ""))
		if product_id.is_empty():
			continue
		counts[product_id] = int(counts.get(product_id, 0)) + 1
	return counts

static func _drink_source_types_by_position(map_public: Dictionary) -> Dictionary:
	var out := {}
	var sources_val = map_public.get("drink_sources", [])
	if not (sources_val is Array):
		return out
	for source_val in Array(sources_val):
		if not (source_val is Dictionary):
			continue
		var source: Dictionary = source_val
		var product_id := str(source.get("type", "")).strip_edges()
		if product_id.is_empty():
			continue
		var pos := _read_vector2i(source.get("world_pos", Vector2i.ZERO))
		out[_vector_key(pos)] = product_id
	return out

static func _route_drinks_per_source(observation: ObservationState, command: Command) -> int:
	var employee_id := str(command.params.get("employee_type", "")) if command != null else ""
	return maxi(1, 2 + _procure_plus_one_bonus(observation) + _drinks_per_source_delta(observation, employee_id))

static func _procure_plus_one_bonus(observation: ObservationState) -> int:
	var bonus_read := MilestoneEffectQueriesClass.sum_positive_int_values(
		_own_milestones(observation),
		"procure_plus_one",
		"StrategyScorer: ",
		"own_player.milestones"
	)
	if not bonus_read.ok:
		return 0
	return int(bonus_read.value)

static func _drinks_per_source_delta(observation: ObservationState, employee_id: String) -> int:
	if employee_id.is_empty():
		return 0
	var entries_read := MilestoneEffectQueriesClass.collect_effect_entries(
		_own_milestones(observation),
		"drinks_per_source_delta",
		"StrategyScorer: ",
		"own_player.milestones"
	)
	if not entries_read.ok:
		return 0
	var total := 0
	for entry_val in Array(entries_read.value):
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var eff_val = entry.get("effect", null)
		if not (eff_val is Dictionary):
			continue
		var eff: Dictionary = eff_val
		var targets_val = eff.get("targets", [])
		if not (targets_val is Array):
			continue
		if not Array(targets_val).has(employee_id):
			continue
		total += _read_int(eff.get("value", 0), 0)
	return total

static func _price_action_value(observation: ObservationState, command: Command, income_analysis: Dictionary, source_state = null) -> Dictionary:
	var action_id := str(command.action_id) if command != null else ""
	var player_id := int(command.actor) if command != null else -1
	var delta := _price_action_delta(action_id)
	var price_payload := _current_unit_price_payload(observation, source_state, player_id)
	var current_unit_price := int(price_payload.get("unit_price", 10))
	var projected_unit_price := current_unit_price + delta
	var serviceable_units := maxi(0, int(income_analysis.get("total_serviceable_demand", 0)))
	var inventory_units := _total_inventory_units(observation)
	var estimated_sale_units := serviceable_units if inventory_units <= 0 else mini(serviceable_units, inventory_units)
	var revenue_delta := delta * estimated_sale_units
	var competition_delta := -delta * serviceable_units
	var value := float(revenue_delta) * 0.35 + float(competition_delta) * 0.65
	if serviceable_units <= 0:
		value -= float(absi(delta)) * 0.5
	return {
		"value": value,
		"source": str(price_payload.get("source", "observation")),
		"current_unit_price": current_unit_price,
		"action_delta": delta,
		"projected_unit_price": projected_unit_price,
		"round_modifier_total": int(price_payload.get("round_modifier_total", 0)),
		"serviceable_demand": serviceable_units,
		"inventory_units": inventory_units,
		"estimated_sale_units": estimated_sale_units,
		"revenue_delta_estimate": revenue_delta,
		"competition_delta_estimate": competition_delta,
	}

static func _append_price_features(features: Dictionary, price_payload: Dictionary) -> void:
	features["price_source"] = str(price_payload.get("source", "observation"))
	features["price_current_unit_price"] = int(price_payload.get("current_unit_price", 0))
	features["price_action_delta"] = int(price_payload.get("action_delta", 0))
	features["price_projected_unit_price"] = int(price_payload.get("projected_unit_price", 0))
	features["price_round_modifier_total"] = int(price_payload.get("round_modifier_total", 0))
	features["price_serviceable_demand"] = int(price_payload.get("serviceable_demand", 0))
	features["price_inventory_units"] = int(price_payload.get("inventory_units", 0))
	features["price_estimated_sale_units"] = int(price_payload.get("estimated_sale_units", 0))
	features["price_revenue_delta_estimate"] = int(price_payload.get("revenue_delta_estimate", 0))
	features["price_competition_delta_estimate"] = int(price_payload.get("competition_delta_estimate", 0))
	features["price_action_value"] = float(price_payload.get("value", 0.0))

static func _reserve_card_value(observation: ObservationState, params: Dictionary) -> Dictionary:
	var selected_index := _read_int(params.get("selected_index", -1), -1)
	var cards_val = observation.own_player.get("reserve_cards", []) if observation != null else []
	if not (cards_val is Array):
		return {
			"value": -100.0,
			"selected_index": selected_index,
			"valid": false,
		}
	var cards: Array = cards_val
	if selected_index < 0 or selected_index >= cards.size():
		return {
			"value": -100.0,
			"selected_index": selected_index,
			"valid": false,
		}
	var card_val = cards[selected_index]
	if not (card_val is Dictionary):
		return {
			"value": -100.0,
			"selected_index": selected_index,
			"valid": false,
		}
	var card: Dictionary = card_val
	var cash := _read_non_negative_int(card.get("cash", 0), 0)
	var ceo_slots := _read_non_negative_int(card.get("ceo_slots", 0), 0)
	var card_type := _read_non_negative_int(card.get("type", 0), 0)
	var value := float(ceo_slots) * 8.0 + float(cash) * 0.05
	if ceo_slots <= 0:
		value -= 50.0
	return {
		"value": value,
		"selected_index": selected_index,
		"valid": true,
		"type": card_type,
		"cash": cash,
		"ceo_slots": ceo_slots,
	}

static func _append_reserve_card_features(features: Dictionary, reserve_payload: Dictionary) -> void:
	features["reserve_card_value"] = float(reserve_payload.get("value", 0.0))
	features["reserve_card_selected_index"] = int(reserve_payload.get("selected_index", -1))
	features["reserve_card_valid"] = bool(reserve_payload.get("valid", false))
	features["reserve_card_type"] = int(reserve_payload.get("type", 0))
	features["reserve_card_cash"] = int(reserve_payload.get("cash", 0))
	features["reserve_card_ceo_slots"] = int(reserve_payload.get("ceo_slots", 0))

static func _current_unit_price_payload(observation: ObservationState, source_state, player_id: int) -> Dictionary:
	if source_state is GameState:
		var pipeline_read := PricingPipelineClass.calculate_unit_price(source_state, player_id)
		if pipeline_read.ok:
			return {
				"unit_price": int(pipeline_read.value),
				"source": "pricing_pipeline",
				"round_modifier_total": _price_modifier_total_from_round_state(source_state.round_state, player_id),
			}
	return {
		"unit_price": _fallback_current_unit_price(observation, player_id),
		"source": "observation",
		"round_modifier_total": _price_modifier_total_from_round_state(observation.round_state_public if observation != null else {}, player_id),
	}

static func _fallback_current_unit_price(observation: ObservationState, player_id: int) -> int:
	if observation == null:
		return 10
	var unit_price := _read_non_negative_int(observation.rules_public.get("base_unit_price", 10), 10)
	unit_price += _base_price_delta(observation)
	unit_price += _price_modifier_total_from_round_state(observation.round_state_public, player_id)
	return unit_price

static func _price_action_delta(action_id: String) -> int:
	match action_id:
		"set_price":
			return -1
		"set_discount":
			return -3
		"set_luxury_price":
			return 10
	return 0

static func _append_employee_income_features(features: Dictionary, observation: ObservationState, employee_id: String, income_analysis: Dictionary, profile, prefix: String) -> void:
	var payload := StrategyIncomeAnalyzerClass.employee_value(observation, employee_id, profile, income_analysis)
	features["%s_income_employee_value" % prefix] = float(payload.get("score", 0.0))
	features["%s_income_employee_role" % prefix] = str(payload.get("role", ""))
	features["%s_target_products" % prefix] = Array(payload.get("target_products", [])).duplicate()

static func _restaurant_action_base_value(action_id: String, observation: ObservationState) -> float:
	if action_id == "place_restaurant":
		return 10.0 if _own_restaurant_count(observation) <= 0 else 2.0
	if action_id == "move_restaurant":
		return 1.0
	return 0.0

static func _append_restaurant_placement_features(features: Dictionary, placement_payload: Dictionary) -> void:
	features["restaurant_candidate_anchor"] = Array(placement_payload.get("candidate_anchor", [])).duplicate()
	features["restaurant_nearest_house_distance"] = int(placement_payload.get("nearest_house_distance", -1))
	features["restaurant_nearby_houses"] = int(placement_payload.get("nearby_houses", 0))
	features["restaurant_nearby_demand"] = int(placement_payload.get("nearby_demand", 0))
	features["restaurant_total_public_demand"] = int(placement_payload.get("total_public_demand", 0))
	features["restaurant_unserviceable_demand_covered"] = int(placement_payload.get("unserviceable_demand_covered", 0))
	features["restaurant_placement_value"] = float(placement_payload.get("placement_value", 0.0))
	features["restaurant_distance_source"] = str(placement_payload.get("distance_source", "anchor"))

static func _house_placement_value(observation: ObservationState, params: Dictionary) -> Dictionary:
	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	var restaurant_distance := _nearest_distance_to_owned_restaurant_anchor(observation, anchor)
	var existing_house_distance := _nearest_distance_to_house_anchor(observation, anchor)
	var value := 0.0
	if restaurant_distance >= 0:
		value += maxf(0.0, 10.0 - float(restaurant_distance)) * 4.0
		if restaurant_distance <= 4:
			value += 12.0
		elif restaurant_distance > 8:
			value -= 10.0
	else:
		value -= 12.0
	if existing_house_distance >= 0:
		value += maxf(0.0, 6.0 - float(existing_house_distance)) * 2.0
	return {
		"value": value,
		"anchor": [anchor.x, anchor.y],
		"nearest_restaurant_distance": restaurant_distance,
		"nearest_existing_house_distance": existing_house_distance,
	}

static func _append_house_placement_features(features: Dictionary, house_payload: Dictionary) -> void:
	features["house_candidate_anchor"] = Array(house_payload.get("anchor", [])).duplicate()
	features["house_nearest_restaurant_distance"] = int(house_payload.get("nearest_restaurant_distance", -1))
	features["house_nearest_existing_house_distance"] = int(house_payload.get("nearest_existing_house_distance", -1))
	features["house_placement_value"] = float(house_payload.get("value", 0.0))

static func _fire_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var payday := _payday_cash_snapshot(observation)
	var employee_payload := StrategyIncomeAnalyzerClass.employee_value(observation, employee_id, profile, income_analysis)
	var employee_income_value := float(employee_payload.get("score", profile.employee_priority(employee_id)))
	var shortfall := int(payday.get("shortfall", 0))
	var effective_relief := _effective_fire_salary_relief(observation, employee_id, payday)
	var value := 0.0
	if shortfall > 0:
		value += 90.0
		value += float(effective_relief) * 8.0
	else:
		value -= 90.0
	value -= employee_income_value * 2.0
	return {
		"value": value,
		"cash": int(payday.get("cash", 0)),
		"due": int(payday.get("due", 0)),
		"shortfall": shortfall,
		"effective_salary_relief": effective_relief,
		"employee_income_value": employee_income_value,
	}

static func _payday_cash_snapshot(observation: ObservationState) -> Dictionary:
	if observation == null:
		return {
			"cash": 0,
			"due": 0,
			"shortfall": 0,
			"paid_employee_count": 0,
			"salary_cost": 0,
			"milestone_delta": 0,
		}
	var player := observation.own_player
	var paid_count := EmployeeRulesClass.count_paid_employees(player)
	var salary_cost := _read_non_negative_int(player.get("salary_cost_override", observation.rules_public.get("salary_cost", 5)), 5)
	var milestone_delta := _salary_total_delta(player)
	var due := maxi(0, paid_count * salary_cost + milestone_delta)
	var cash := _read_non_negative_int(player.get("cash", 0), 0)
	return {
		"cash": cash,
		"due": due,
		"shortfall": maxi(0, due - cash),
		"paid_employee_count": paid_count,
		"salary_cost": salary_cost,
		"milestone_delta": milestone_delta,
	}

static func _effective_fire_salary_relief(observation: ObservationState, employee_id: String, payday: Dictionary) -> int:
	if observation == null or employee_id.is_empty():
		return 0
	if not EmployeeRulesClass.requires_salary(employee_id, observation.own_player):
		return 0
	var cash := int(payday.get("cash", 0))
	var before_shortfall := int(payday.get("shortfall", 0))
	var paid_count := maxi(0, int(payday.get("paid_employee_count", 0)) - 1)
	var salary_cost := int(payday.get("salary_cost", 0))
	var milestone_delta := int(payday.get("milestone_delta", 0))
	var after_due := maxi(0, paid_count * salary_cost + milestone_delta)
	var after_shortfall := maxi(0, after_due - cash)
	return maxi(0, before_shortfall - after_shortfall)

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

static func _marketing_service_features(observation: ObservationState, affected_house_ids: Array[String], product_id: String, source_state = null) -> Dictionary:
	if source_state is GameState:
		var road_payload := _marketing_service_features_from_source(source_state, observation, affected_house_ids, product_id)
		if not road_payload.is_empty():
			return road_payload
	var serviceable := 0
	var closest_distance := 2147483647
	var total_distance := 0
	for house_id in affected_house_ids:
		var distance := _min_house_distance_to_owned_restaurant(observation, house_id)
		if distance < 0:
			continue
		serviceable += 1
		closest_distance = mini(closest_distance, distance)
		total_distance += distance
	var average_distance := -1.0
	if serviceable > 0:
		average_distance = float(total_distance) / float(serviceable)
	return {
		"serviceable_houses": serviceable,
		"closest_distance": closest_distance if serviceable > 0 else -1,
		"average_distance": average_distance,
		"inventory_units": _inventory_count(observation, product_id),
		"can_supply_product": _can_actively_supply_product(observation, product_id),
		"own_restaurants": _own_restaurant_count(observation),
		"distance_source": "anchor",
	}

static func _marketing_service_features_from_source(source_state: GameState, observation: ObservationState, affected_house_ids: Array[String], product_id: String) -> Dictionary:
	var analysis_read := BoardAnalyzerClass.analyze_state(source_state)
	if not analysis_read.ok:
		return {}
	var analysis: Dictionary = analysis_read.value
	if not bool(analysis.get("road_graph_available", false)):
		return {}
	var distances: Dictionary = Dictionary(analysis.get("restaurant_house_distances", {}))
	var own_restaurant_ids := _sorted_unique_strings(observation.own_player.get("restaurants", [])) if observation != null else []
	var serviceable := 0
	var closest_distance := 2147483647
	var total_distance := 0
	for house_id in affected_house_ids:
		var best_for_house := 2147483647
		for restaurant_id in own_restaurant_ids:
			var per_rest: Dictionary = Dictionary(distances.get(restaurant_id, {}))
			var info: Dictionary = Dictionary(per_rest.get(house_id, {}))
			if not info.has("distance"):
				continue
			best_for_house = mini(best_for_house, int(info.get("distance", 2147483647)))
		if best_for_house >= 2147483647:
			continue
		serviceable += 1
		closest_distance = mini(closest_distance, best_for_house)
		total_distance += best_for_house
	var average_distance := -1.0
	if serviceable > 0:
		average_distance = float(total_distance) / float(serviceable)
	return {
		"serviceable_houses": serviceable,
		"closest_distance": closest_distance if serviceable > 0 else -1,
		"average_distance": average_distance,
		"inventory_units": _inventory_count(observation, product_id),
		"can_supply_product": _can_actively_supply_product(observation, product_id),
		"own_restaurants": _own_restaurant_count(observation),
		"distance_source": "road_graph",
	}

static func _marketing_value_from_features(affected_count: int, pipeline_value: float, service_features: Dictionary) -> float:
	if affected_count <= 0:
		return -500.0
	var serviceable := int(service_features.get("serviceable_houses", 0))
	var inventory_units := int(service_features.get("inventory_units", 0))
	var closest_distance := int(service_features.get("closest_distance", -1))
	var own_restaurants := int(service_features.get("own_restaurants", 0))
	var can_supply_product := bool(service_features.get("can_supply_product", false))
	var value := float(affected_count) * 10.0 + pipeline_value
	value += float(serviceable) * 7.0
	value += float(mini(inventory_units, affected_count)) * 4.0
	if closest_distance >= 0:
		value += maxf(0.0, 8.0 - float(closest_distance) * 0.5)
	if own_restaurants <= 0:
		value -= 16.0
	if not can_supply_product and inventory_units <= 0:
		value -= 12.0
	return value

static func _has_non_skip_alternative(_observation: ObservationState, _macro: MacroAction) -> bool:
	return true

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func _owns_role(observation: ObservationState, role: String) -> bool:
	if observation == null or role.is_empty():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if _employee_role(employee_id) == role:
			return true
	return false

static func _has_trainable_reserve_employee(observation: ObservationState) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	var reserve_val = observation.own_player.get("reserve_employees", [])
	if not (reserve_val is Array):
		return false
	for employee_val in Array(reserve_val):
		var employee_id := str(employee_val)
		if employee_id.is_empty() or not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and not (def_val as EmployeeDef).train_to.is_empty():
			return true
	return false

static func _has_trainable_owned_employee(observation: ObservationState) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if employee_id.is_empty() or not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and not (def_val as EmployeeDef).train_to.is_empty():
			return true
	return false

static func _count_owned_employee(player: Dictionary, target_employee_id: String) -> int:
	if target_employee_id.is_empty():
		return 0
	var count := 0
	for employee_id in _owned_employee_ids(player):
		if employee_id == target_employee_id:
			count += 1
	return count

static func _owns_any_employee(observation: ObservationState, employee_ids: Array[String]) -> bool:
	if observation == null or employee_ids.is_empty():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if employee_ids.has(employee_id):
			return true
	return false

static func _public_demand_count_for_product(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return 0
	var count := 0
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		var demands_val = Dictionary(house_val).get("demands", [])
		if not (demands_val is Array):
			continue
		for demand_val in Array(demands_val):
			if demand_val is Dictionary and str(Dictionary(demand_val).get("product", "")) == product_id:
				count += 1
	return count

static func _inventory_count(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	return maxi(0, int(Dictionary(inventory_val).get(product_id, 0)))

static func _total_inventory_units(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	var total := 0
	for amount_val in Dictionary(inventory_val).values():
		total += maxi(0, _read_int(amount_val, 0))
	return total

static func _price_modifier_total_from_round_state(round_state: Dictionary, player_id: int) -> int:
	var modifiers_val = round_state.get("price_modifiers", {})
	if not (modifiers_val is Dictionary):
		return 0
	var price_modifiers: Dictionary = modifiers_val
	var player_modifiers_val = price_modifiers.get(player_id, price_modifiers.get(str(player_id), {}))
	if not (player_modifiers_val is Dictionary):
		return 0
	var total := 0
	for delta_val in Dictionary(player_modifiers_val).values():
		total += _read_int(delta_val, 0)
	return total

static func _can_supply_product(observation: ObservationState, product_id: String) -> bool:
	if observation == null or product_id.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	var is_drink := false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		is_drink = ProductRegistryClass.is_drink(product_id)
	for employee_id in _owned_employee_ids(observation.own_player):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if def.can_produce() and def.get_production_food_options().has(product_id):
			return true
		if is_drink and (def.can_procure() or employee_id == "errand_boy"):
			return true
	return false

static func _can_actively_supply_product(observation: ObservationState, product_id: String) -> bool:
	if observation == null or product_id.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	var is_drink := false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		is_drink = ProductRegistryClass.is_drink(product_id)
	for employee_id in _active_employee_ids(observation.own_player):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if def.can_produce() and def.get_production_food_options().has(product_id):
			return true
		if is_drink and (def.can_procure() or employee_id == "errand_boy"):
			return true
	return false

static func _active_employee_ids(player: Dictionary) -> Array[String]:
	return _sorted_unique_strings(player.get("employees", []))

static func _owned_employee_ids(player: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var employees_val = player.get(key, [])
		if not (employees_val is Array):
			continue
		for employee_val in Array(employees_val):
			var employee_id := str(employee_val)
			if not employee_id.is_empty():
				out.append(employee_id)
	return out

static func _own_restaurant_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var restaurants_val = observation.own_player.get("restaurants", [])
	if restaurants_val is Array:
		return Array(restaurants_val).size()
	return 0

static func _own_milestones(observation: ObservationState) -> Array[String]:
	if observation == null:
		return []
	return _sorted_unique_strings(observation.own_player.get("milestones", []))

static func _nearest_distance_to_owned_restaurant_anchor(observation: ObservationState, pos: Vector2i) -> int:
	if observation == null:
		return -1
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var restaurants: Dictionary = restaurants_val
	var best := 2147483647
	for restaurant_id in _sorted_unique_strings(observation.own_player.get("restaurants", [])):
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		var rest_anchor := _read_vector2i(Dictionary(rest_val).get("anchor_pos", Vector2i.ZERO))
		best = mini(best, absi(pos.x - rest_anchor.x) + absi(pos.y - rest_anchor.y))
	return best if best < 2147483647 else -1

static func _nearest_distance_to_house_anchor(observation: ObservationState, pos: Vector2i) -> int:
	if observation == null:
		return -1
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return -1
	var best := 2147483647
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
		best = mini(best, absi(pos.x - house_anchor.x) + absi(pos.y - house_anchor.y))
	return best if best < 2147483647 else -1

static func _min_house_distance_to_owned_restaurant(observation: ObservationState, house_id: String) -> int:
	if observation == null or house_id.is_empty():
		return -1
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return -1
	var houses: Dictionary = houses_val
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		return -1
	var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var restaurants: Dictionary = restaurants_val
	var own_ids := _sorted_unique_strings(observation.own_player.get("restaurants", []))
	var best := 2147483647
	for restaurant_id in own_ids:
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var rest_anchor := _read_vector2i(rest.get("anchor_pos", Vector2i.ZERO))
		var distance := absi(house_anchor.x - rest_anchor.x) + absi(house_anchor.y - rest_anchor.y)
		best = mini(best, distance)
	return best if best < 2147483647 else -1

static func _read_vector2i(value) -> Vector2i:
	if value is Vector2i:
		return Vector2i(value)
	if value is Vector2:
		var v2: Vector2 = value
		return Vector2i(int(v2.x), int(v2.y))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y"):
			return Vector2i(int(dict.get("x", 0)), int(dict.get("y", 0)))
	return Vector2i.ZERO

static func _vector_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

static func _sorted_dictionary_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in dict.keys():
		var text := str(key)
		if not text.is_empty():
			out.append(text)
	out.sort()
	return out

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out

static func _salary_total_delta(player: Dictionary) -> int:
	var milestones_val = player.get("milestones", [])
	if not (milestones_val is Array):
		return 0
	var delta_read := MilestoneEffectQueriesClass.sum_int_values(
		Array(milestones_val),
		"salary_total_delta",
		"StrategyScorer: ",
		"own_player.milestones"
	)
	if not delta_read.ok:
		return 0
	return int(delta_read.value)

static func _base_price_delta(observation: ObservationState) -> int:
	var delta_read := MilestoneEffectQueriesClass.sum_int_values(
		_own_milestones(observation),
		"base_price_delta",
		"StrategyScorer: ",
		"own_player.milestones"
	)
	if not delta_read.ok:
		return 0
	return int(delta_read.value)

static func _read_non_negative_int(value, fallback: int) -> int:
	if value is int:
		return maxi(0, int(value))
	if value is float:
		return maxi(0, int(value))
	if value is String and str(value).is_valid_int():
		return maxi(0, int(str(value)))
	return fallback

static func _read_int(value, fallback: int) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String and str(value).is_valid_int():
		return int(str(value))
	return fallback
