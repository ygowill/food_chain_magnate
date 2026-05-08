class_name StrategyRecruitPlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const StrategyCashPlannerClass = preload("res://core/ai/strategy/strategy_cash_planner.gd")
const StrategyEmployeePlannerClass = preload("res://core/ai/strategy/strategy_employee_planner.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyRecoveryPlannerClass = preload("res://core/ai/strategy/strategy_recovery_planner.gd")
const StrategyRoutePlannerClass = preload("res://core/ai/strategy/strategy_route_planner.gd")
const StrategySupportPlannerClass = preload("res://core/ai/strategy/strategy_support_planner.gd")
const StrategySupplyPlannerClass = preload("res://core/ai/strategy/strategy_supply_planner.gd")

static func evaluate_action(observation: ObservationState, command: Command, profile, income_analysis: Dictionary) -> Dictionary:
	var features := {}
	if observation == null or command == null or profile == null:
		return {"value": 0.0, "features": features}
	var employee_id := str(command.params.get("employee_type", ""))
	var employee_payload := StrategyEmployeePlannerClass.strategy_value(observation, employee_id, profile, income_analysis)
	var employee_value := float(employee_payload.get("value", 0.0))
	var placement_route_value := float(employee_payload.get("placement_route_value", 0.0))
	var price_route_payload := StrategySupportPlannerClass.price_employee_route_value(observation, employee_id, income_analysis)
	var price_route_value := float(price_route_payload.get("value", 0.0))
	var waitress_route_payload := StrategySupportPlannerClass.waitress_route_value(observation, employee_id, profile, income_analysis)
	var waitress_route_value := float(waitress_route_payload.get("value", 0.0))
	var marketing_upgrade_payload := marketing_upgrade_route_value(observation, employee_id, income_analysis)
	var marketing_upgrade_value := float(marketing_upgrade_payload.get("value", 0.0))
	var roster_payload := roster_adjustment(observation, employee_id, income_analysis)
	var roster_adjustment_value := float(roster_payload.get("adjustment", 0.0))
	var marketing_capacity_payload := StrategyRecoveryPlannerClass.marketing_capacity_plan(observation, income_analysis)
	features["employee_value"] = employee_value
	features["recruit_placement_route_value"] = placement_route_value
	_append_marketing_capacity_features(features, marketing_capacity_payload)
	_append_price_employee_route_features(features, price_route_payload)
	_append_waitress_route_features(features, waitress_route_payload)
	_append_marketing_upgrade_route_features(features, marketing_upgrade_payload)
	features["recruit_owned_count"] = int(roster_payload.get("owned_count", 0))
	features["recruit_desired_count"] = int(roster_payload.get("desired_count", 0))
	features["recruit_roster_saturated"] = bool(roster_payload.get("saturated", false))
	features["recruit_roster_adjustment"] = roster_adjustment_value
	_append_employee_income_features(features, employee_payload)
	var role := str(employee_payload.get("role", ""))
	if role == "procure_drink":
		_append_drink_need_features(features, income_analysis)
	return {
		"value": employee_value + roster_adjustment_value + price_route_value + waitress_route_value + marketing_upgrade_value,
		"features": features,
	}

static func marketing_upgrade_route_value(observation: ObservationState, employee_id: String, income_analysis: Dictionary) -> Dictionary:
	var need := marketing_upgrade_recovery_need(observation, income_analysis)
	var lost_demand := maxi(0, int(income_analysis.get("total_lost_to_competitor_demand", 0)))
	var out := {
		"value": 0.0,
		"needed": need,
		"lost_to_competitor_demand": lost_demand,
		"source_employee": "marketing_trainee" if need else "",
		"target_employee": "campaign_manager" if need else "",
	}
	if not need:
		return out
	if employee_id.is_empty() or _employee_train_capacity(employee_id) <= 0:
		return out
	out["value"] = 10.0 + float(lost_demand) * 4.0
	return out

static func roster_adjustment(observation: ObservationState, employee_id: String, income_analysis: Dictionary, profile = null) -> Dictionary:
	var owned_count := _count_owned_employee(observation.own_player if observation != null else {}, employee_id)
	var desired_count := desired_recruit_count(observation, employee_id, income_analysis, profile)
	var saturated := owned_count >= desired_count
	var adjustment := 0.0
	if saturated:
		adjustment -= 145.0 + float(maxi(0, owned_count - desired_count)) * 35.0
	return {
		"owned_count": owned_count,
		"desired_count": desired_count,
		"saturated": saturated,
		"adjustment": adjustment,
	}

static func desired_recruit_count(observation: ObservationState, employee_id: String, income_analysis: Dictionary, profile = null) -> int:
	if observation == null or employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return 0
	if not _paid_recruit_has_salary_runway(observation, employee_id):
		return 0
	var route_plan: Dictionary = StrategyRoutePlannerClass.analyze(observation, income_analysis, profile)
	var role := _employee_role(employee_id)
	match employee_id:
		"kitchen_trainee":
			var food_actionable_demand := _food_actionable_demand(income_analysis)
			var food_actionable_inventory_gap := _food_actionable_inventory_gap(income_analysis)
			if bool(route_plan.get("owns_food_supply", false)) and food_actionable_demand < 5 and food_actionable_inventory_gap < 4:
				return 0
			return 2 if food_actionable_demand >= 5 or food_actionable_inventory_gap >= 4 else 1
		"marketing_trainee":
			if _owns_any_employee(observation, ["campaign_manager", "brand_manager", "brand_director"]):
				return 0
			var marketing_capacity_plan: Dictionary = StrategyRecoveryPlannerClass.marketing_capacity_plan(observation, income_analysis)
			return int(marketing_capacity_plan.get("desired_count", 0))
		"errand_boy":
			return 1 if _has_actionable_drink_need(income_analysis) else 0
		"trainer":
			if _has_actionable_training_need(observation, income_analysis):
				return 1
			if marketing_upgrade_recovery_need(observation, income_analysis):
				return 1
			return 1 if bool(route_plan.get("stable_income_ready", false)) and _has_trainable_owned_employee(observation) else 0
		"management_trainee":
			if _owns_any_employee(observation, ["management_trainee", "new_business_developer", "junior_vice_president", "luxury_manager"]):
				return 0
			if not bool(route_plan.get("house_growth_space", false)):
				return 0
			return 1 if bool(route_plan.get("house_growth_ready", false)) else 0
		"waitress":
			if not bool(route_plan.get("stable_income_ready", false)):
				return 0
			return 1 if bool(route_plan.get("waitress_support_ready", false)) else 0
		"recruiting_girl":
			return 1 if bool(route_plan.get("stable_income_ready", false)) else 0
	if role == "new_shop":
		var unserviceable := int(income_analysis.get("total_public_demand", 0)) - int(income_analysis.get("total_serviceable_demand", 0))
		return 1 if unserviceable > 0 or int(route_plan.get("own_restaurants", 0)) <= 1 else 0
	if role == "produce_food":
		var role_food_actionable_demand := _food_actionable_demand(income_analysis)
		var role_food_actionable_inventory_gap := _food_actionable_inventory_gap(income_analysis)
		if bool(route_plan.get("owns_food_supply", false)) and role_food_actionable_demand < 6 and role_food_actionable_inventory_gap < 4:
			return 0
		return 2 if role_food_actionable_demand >= 6 or role_food_actionable_inventory_gap >= 4 else 1
	if role == "price":
		var price_relevant_demand := int(income_analysis.get("total_actionable_demand", income_analysis.get("total_serviceable_demand", 0))) + int(income_analysis.get("total_price_recoverable_demand", 0))
		if price_relevant_demand <= 0:
			return 0
		return 1 if bool(route_plan.get("price_route_ready", false)) else 0
	if role == "procure_drink":
		return 1 if _has_actionable_drink_need(income_analysis) else 0
	if role == "marketing" or role == "recruit_train":
		return 1
	return 1

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func marketing_upgrade_recovery_need(observation: ObservationState, income_analysis: Dictionary) -> bool:
	if observation == null:
		return false
	if _own_restaurant_count(observation) <= 0:
		return false
	if maxi(0, int(income_analysis.get("total_lost_to_competitor_demand", 0))) <= 0:
		return false
	if _owns_any_employee(observation, ["campaign_manager", "brand_manager", "brand_director"]):
		return false
	if not _owns_any_employee(observation, ["marketing_trainee"]):
		return false
	if int(observation.employee_pool_public.get("campaign_manager", 0)) <= 0:
		return false
	return true

static func _employee_train_capacity(employee_id: String) -> int:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return 0
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return 0
	var def: EmployeeDef = def_val
	return maxi(0, int(def.train_capacity))

static func _paid_recruit_has_salary_runway(observation: ObservationState, employee_id: String) -> bool:
	if observation == null or employee_id.is_empty():
		return false
	if not EmployeeRulesClass.requires_salary(employee_id, observation.own_player):
		return true
	var payday := StrategyCashPlannerClass.payday_cash_snapshot(observation)
	var due := maxi(0, int(payday.get("due", 0)))
	if due <= 0:
		return true
	var cash := maxi(0, int(payday.get("cash", 0)))
	var salary_cost := maxi(0, int(payday.get("salary_cost", 0)))
	if salary_cost <= 0:
		return true
	return cash >= due + salary_cost

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

static func _has_actionable_training_need(observation: ObservationState, income_analysis: Dictionary) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	if _own_cash(observation) <= 0:
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if employee_id.is_empty() or not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		for target_val in def.train_to:
			var target_id := str(target_val)
			if _training_target_closes_capacity_gap(observation, employee_id, target_id, income_analysis):
				return true
	return false

static func _own_cash(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var value = observation.own_player.get("cash", 0)
	if value is int:
		return maxi(0, int(value))
	if value is float:
		return maxi(0, int(value))
	if value is String and str(value).is_valid_int():
		return maxi(0, int(str(value)))
	return 0

static func _own_restaurant_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var restaurants_val = observation.own_player.get("restaurants", [])
	if restaurants_val is Array:
		return Array(restaurants_val).size()
	return 0

static func _training_target_closes_capacity_gap(observation: ObservationState, source_employee_id: String, target_employee_id: String, income_analysis: Dictionary) -> bool:
	if source_employee_id.is_empty() or target_employee_id.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	if not EmployeeRegistryClass.has(source_employee_id) or not EmployeeRegistryClass.has(target_employee_id):
		return false
	var target_def_val = EmployeeRegistryClass.get_def(target_employee_id)
	if not (target_def_val is EmployeeDef):
		return false
	var target_def: EmployeeDef = target_def_val
	if not target_def.can_produce():
		return false
	var source_units := StrategySupplyPlannerClass.expected_food_units(source_employee_id)
	var target_units := StrategySupplyPlannerClass.expected_food_units(target_employee_id)
	if target_units <= source_units:
		return false
	for product_val in target_def.get_production_food_options():
		var product_id := str(product_val)
		if product_id.is_empty():
			continue
		var current_capacity := _owned_food_capacity_for_product(observation, product_id)
		var product_info: Dictionary = Dictionary(Dictionary(income_analysis.get("products", {})).get(product_id, {}))
		var current_gap := maxi(0, int(product_info.get("inventory_gap", 0)))
		var actionable_gap := maxi(0, int(product_info.get("actionable_inventory_gap", current_gap)))
		var planning_gap := maxi(actionable_gap, int(product_info.get("planning_actionable_inventory_gap", product_info.get("planning_inventory_gap", actionable_gap))))
		if planning_gap > current_capacity:
			return true
	return false

static func _owned_food_capacity_for_product(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty() or not EmployeeRegistryClass.is_loaded():
		return 0
	var total := 0
	for employee_id in _owned_employee_ids(observation.own_player):
		if not _employee_can_produce_product(employee_id, product_id):
			continue
		total += StrategySupplyPlannerClass.expected_food_units(employee_id)
	return total

static func _employee_can_produce_product(employee_id: String, product_id: String) -> bool:
	if employee_id.is_empty() or product_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	return def.can_produce() and def.get_production_food_options().has(product_id)

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

static func _food_public_demand(income_analysis: Dictionary) -> int:
	var total := 0
	for product_id in _income_analysis_product_ids(income_analysis):
		if _is_food_product(product_id):
			var info: Dictionary = Dictionary(Dictionary(income_analysis.get("products", {})).get(product_id, {}))
			total += int(info.get("public_demand", 0))
	return total

static func _food_inventory_gap(income_analysis: Dictionary) -> int:
	var total := 0
	for product_id in _income_analysis_product_ids(income_analysis):
		if _is_food_product(product_id):
			var info: Dictionary = Dictionary(Dictionary(income_analysis.get("products", {})).get(product_id, {}))
			total += int(info.get("inventory_gap", 0))
	return total

static func _food_actionable_demand(income_analysis: Dictionary) -> int:
	var total := 0
	for product_id in _income_analysis_product_ids(income_analysis):
		if _is_food_product(product_id):
			var info: Dictionary = Dictionary(Dictionary(income_analysis.get("products", {})).get(product_id, {}))
			total += int(info.get("actionable_demand", info.get("serviceable_demand", 0)))
	return total

static func _food_actionable_inventory_gap(income_analysis: Dictionary) -> int:
	var total := 0
	for product_id in _income_analysis_product_ids(income_analysis):
		if _is_food_product(product_id):
			var info: Dictionary = Dictionary(Dictionary(income_analysis.get("products", {})).get(product_id, {}))
			total += int(info.get("actionable_inventory_gap", info.get("inventory_gap", 0)))
	return total

static func _has_actionable_drink_need(income_analysis: Dictionary) -> bool:
	return bool(StrategyIncomeAnalyzerClass.drink_need(income_analysis).get("has_actionable_demand", false))

static func _income_analysis_product_ids(income_analysis: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_id_val in products.keys():
		var product_id := str(product_id_val)
		if not product_id.is_empty():
			out.append(product_id)
	out.sort()
	return out

static func _is_food_product(product_id: String) -> bool:
	if product_id.is_empty() or not ProductRegistryClass.is_loaded() or not ProductRegistryClass.has(product_id):
		return false
	var def_val = ProductRegistryClass.get_def(product_id)
	if def_val is ProductDef:
		var def: ProductDef = def_val
		return def.has_tag("food") and not def.is_drink()
	return false

static func _append_price_employee_route_features(features: Dictionary, payload: Dictionary) -> void:
	features["recruit_price_route_value"] = float(payload.get("value", 0.0))
	features["recruit_price_route_serviceable_demand"] = int(payload.get("serviceable_demand", 0))
	features["recruit_price_route_actionable_demand"] = int(payload.get("actionable_demand", 0))
	features["recruit_price_route_recoverable_demand"] = int(payload.get("recoverable_demand", 0))
	features["recruit_price_route_relevant_demand"] = int(payload.get("price_relevant_demand", payload.get("actionable_demand", 0)))
	features["recruit_price_route_inventory_units"] = int(payload.get("inventory_units", 0))
	features["recruit_price_route_estimated_sale_units"] = int(payload.get("estimated_sale_units", 0))
	features["recruit_price_route_first_lower_prices_available"] = bool(payload.get("first_lower_prices_available", false))
	features["recruit_price_route_stable_income_ready"] = bool(payload.get("stable_income_ready", false))
	features["recruit_price_route_has_sale_inventory"] = bool(payload.get("has_sale_inventory", false))

static func _append_marketing_capacity_features(features: Dictionary, payload: Dictionary) -> void:
	features["recruit_marketing_capacity_desired_count"] = int(payload.get("desired_count", 0))
	features["recruit_marketing_capacity_base_desired_count"] = int(payload.get("base_desired_count", 0))
	features["recruit_marketing_capacity_needs_extra"] = bool(payload.get("needs_extra_capacity", false))
	features["recruit_marketing_capacity_owned_count"] = int(payload.get("owned_marketing_count", 0))
	features["recruit_marketing_capacity_available_count"] = int(payload.get("available_marketing_count", 0))
	features["recruit_marketing_capacity_busy_count"] = int(payload.get("busy_marketing_count", 0))
	features["recruit_marketing_capacity_modes"] = Array(payload.get("modes", [])).duplicate()
	features["recruit_marketing_capacity_reasons"] = Array(payload.get("reasons", [])).duplicate()

static func _append_waitress_route_features(features: Dictionary, payload: Dictionary) -> void:
	features["recruit_waitress_route_value"] = float(payload.get("value", 0.0))
	features["recruit_waitress_tips"] = int(payload.get("tips", 0))
	features["recruit_waitress_first_waitress_available"] = bool(payload.get("first_waitress_available", false))
	features["recruit_waitress_first_waitress_value"] = float(payload.get("first_waitress_value", 0.0))

static func _append_marketing_upgrade_route_features(features: Dictionary, payload: Dictionary) -> void:
	features["recruit_marketing_upgrade_value"] = float(payload.get("value", 0.0))
	features["recruit_marketing_upgrade_needed"] = bool(payload.get("needed", false))
	features["recruit_marketing_upgrade_lost_to_competitor_demand"] = int(payload.get("lost_to_competitor_demand", 0))
	features["recruit_marketing_upgrade_source_employee"] = str(payload.get("source_employee", ""))
	features["recruit_marketing_upgrade_target_employee"] = str(payload.get("target_employee", ""))

static func _append_employee_income_features(features: Dictionary, employee_payload: Dictionary) -> void:
	features["recruit_income_employee_value"] = float(employee_payload.get("income_value", 0.0))
	features["recruit_income_employee_role"] = str(employee_payload.get("role", ""))
	features["recruit_target_products"] = Array(employee_payload.get("target_products", [])).duplicate()

static func _append_drink_need_features(features: Dictionary, income_analysis: Dictionary) -> void:
	var need: Dictionary = StrategyIncomeAnalyzerClass.drink_need(income_analysis)
	features["recruit_drink_has_actionable_demand"] = bool(need.get("has_actionable_demand", false))
	features["recruit_drink_actionable_inventory_gap"] = int(need.get("actionable_inventory_gap", 0))
	features["recruit_drink_actionable_demand"] = int(need.get("actionable_demand", 0))
	features["recruit_drink_serviceable_demand"] = int(need.get("serviceable_demand", 0))
	features["recruit_drink_pending_marketing_demand"] = int(need.get("pending_marketing_demand", 0))
