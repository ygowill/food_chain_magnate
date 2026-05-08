class_name StrategyStructurePlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const DrinkRouteAnalyzerClass = preload("res://core/ai/analysis/drink_route_analyzer.gd")
const StrategyEmployeePlannerClass = preload("res://core/ai/strategy/strategy_employee_planner.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyRecoveryPlannerClass = preload("res://core/ai/strategy/strategy_recovery_planner.gd")
const StrategySupportPlannerClass = preload("res://core/ai/strategy/strategy_support_planner.gd")
const StrategySupplyPlannerClass = preload("res://core/ai/strategy/strategy_supply_planner.gd")

static func evaluate_action(observation: ObservationState, command: Command, profile, income_analysis: Dictionary) -> Dictionary:
	var features := {}
	if observation == null or command == null or profile == null:
		return {"value": 0.0, "features": features}
	var action_id := str(command.action_id)
	var employee_id := str(command.params.get("employee_id", ""))
	var employee_payload := StrategyEmployeePlannerClass.strategy_value(observation, employee_id, profile, income_analysis)
	var employee_value := float(employee_payload.get("value", 0.0))
	var route_readiness_adjustment := StrategyEmployeePlannerClass.placement_route_readiness_adjustment(observation, employee_id, income_analysis)
	var drink_route_readiness_adjustment_value := _drink_route_readiness_adjustment(employee_id, income_analysis)
	var price_route_payload := StrategySupportPlannerClass.price_employee_route_value(observation, employee_id, income_analysis)
	var price_route_value := float(price_route_payload.get("value", 0.0))
	var waitress_route_payload := StrategySupportPlannerClass.waitress_route_value(observation, employee_id, profile, income_analysis)
	var waitress_route_value := float(waitress_route_payload.get("value", 0.0))
	var activation_payload := activation_value(observation, employee_id, profile, income_analysis) if action_id != "restructure_employee" else {}
	var activation_value_total := float(activation_payload.get("value", 0.0))
	features["structure_employee_value"] = employee_value
	features["structure_activation_value"] = activation_value_total
	features["structure_activation_products"] = Array(activation_payload.get("products", [])).duplicate()
	features["structure_marketing_supply_products"] = Array(activation_payload.get("marketing_supply_products", [])).duplicate()
	features["structure_marketing_activation_value"] = float(activation_payload.get("marketing_activation_value", 0.0))
	features["structure_marketing_activation_products"] = Array(activation_payload.get("marketing_activation_products", [])).duplicate()
	features["structure_marketing_activation_reasons"] = Array(activation_payload.get("marketing_activation_reasons", [])).duplicate()
	features["structure_drink_activation_value"] = float(activation_payload.get("drink_value", 0.0))
	features["structure_drink_activation_products"] = Array(activation_payload.get("drink_products", [])).duplicate()
	features["structure_drink_activation_units_by_product"] = Dictionary(activation_payload.get("drink_units_by_product", {})).duplicate()
	features["structure_drink_activation_action_values"] = Dictionary(activation_payload.get("drink_action_values", {})).duplicate()
	features["structure_drink_activation_route_source_count"] = int(activation_payload.get("drink_route_source_count", 0))
	features["structure_drink_activation_route_distance"] = int(activation_payload.get("drink_route_distance", -1))
	features["structure_placement_route_value"] = float(employee_payload.get("placement_route_value", 0.0))
	features["structure_route_readiness_adjustment"] = route_readiness_adjustment
	features["structure_drink_route_readiness_adjustment"] = drink_route_readiness_adjustment_value
	_append_drink_need_features(features, income_analysis)
	_append_price_employee_route_features(features, price_route_payload)
	_append_waitress_route_features(features, waitress_route_payload)
	_append_employee_income_features(features, employee_payload)
	return {
		"value": employee_value + activation_value_total + route_readiness_adjustment + drink_route_readiness_adjustment_value + price_route_value + waitress_route_value,
		"features": features,
	}

static func activation_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var out := {
		"value": 0.0,
		"food_value": 0.0,
		"drink_value": 0.0,
		"products": [],
		"marketing_supply_products": [],
		"marketing_activation_value": 0.0,
		"marketing_activation_products": [],
		"marketing_activation_reasons": [],
		"drink_products": [],
		"drink_units_by_product": {},
		"drink_action_values": {},
		"drink_route_source_count": 0,
		"drink_route_distance": -1,
	}
	if observation == null or employee_id.is_empty() or profile == null:
		return out
	var role := _employee_role(employee_id)
	if role == "procure_drink":
		return _drink_activation_value(observation, employee_id, profile, income_analysis, out)
	if role == "marketing":
		return _marketing_activation_value(observation, employee_id, profile, income_analysis, out)
	if role != "produce_food":
		return out
	var products: Array[String] = _employee_food_products(employee_id)
	var total := 0.0
	var activation_products: Array[String] = []
	var marketing_supply_products: Array[String] = []
	for product_id in products:
		var product_payload := StrategyIncomeAnalyzerClass.product_value(product_id, profile, income_analysis)
		var current_gap := int(product_payload.get("inventory_gap", 0))
		var planning_gap := int(product_payload.get("planning_inventory_gap", current_gap))
		var future_gap := maxi(0, planning_gap - current_gap)
		var product_switch_gap := maxi(0, int(product_payload.get("own_sourced_opponent_blocking_demand", 0)) - int(product_payload.get("inventory_units", 0)))
		var product_value := float(current_gap) * 8.0 + float(future_gap) * 6.0
		product_value += float(product_switch_gap) * 7.0
		if _marketing_pipeline_needs_active_supply(observation, product_id):
			product_value += 16.0 + float(profile.product_priority(product_id)) * 0.8
			marketing_supply_products.append(product_id)
		if product_value <= 0.0:
			continue
		total += product_value
		activation_products.append(product_id)
	out["value"] = total
	out["food_value"] = total
	out["products"] = activation_products
	out["marketing_supply_products"] = marketing_supply_products
	return out

static func _drink_activation_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary, out: Dictionary) -> Dictionary:
	if observation == null or employee_id.is_empty() or profile == null:
		return out
	if not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return out
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return out
	var def: EmployeeDef = def_val
	if not def.can_procure():
		return out
	var payload := _errand_drink_activation_value(observation, employee_id, profile, income_analysis) if employee_id == "errand_boy" else _route_drink_activation_value(observation, employee_id, profile, income_analysis)
	var drink_value := float(payload.get("value", 0.0))
	out["value"] = drink_value
	out["drink_value"] = drink_value
	out["products"] = Array(payload.get("products", [])).duplicate()
	out["drink_products"] = Array(payload.get("products", [])).duplicate()
	out["marketing_supply_products"] = Array(payload.get("marketing_supply_products", [])).duplicate()
	out["drink_units_by_product"] = Dictionary(payload.get("units_by_product", {})).duplicate()
	out["drink_action_values"] = Dictionary(payload.get("action_values", {})).duplicate()
	out["drink_route_source_count"] = int(payload.get("route_source_count", 0))
	out["drink_route_distance"] = int(payload.get("route_distance", -1))
	return out

static func _marketing_activation_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary, out: Dictionary) -> Dictionary:
	if observation == null or employee_id.is_empty() or profile == null:
		return out
	if _own_restaurant_count(observation) <= 0:
		return out
	if _has_active_marketing_employee(observation):
		return out
	var products := _marketable_active_supply_products(observation, income_analysis)
	if products.is_empty():
		return out
	var best_priority := 0.0
	for product_id in products:
		best_priority = maxf(best_priority, float(profile.product_priority(product_id)))
	var value := 14.0 + best_priority * 1.2 + float(maxi(0, products.size() - 1)) * 2.0
	var reasons: Array[String] = ["active_supply_route"]
	var recovery := StrategyRecoveryPlannerClass.analyze(income_analysis)
	var recovery_modes := Array(recovery.get("modes", [])).duplicate()
	var recovery_pressure := int(recovery.get("lost_to_competitor_demand", 0)) + int(recovery.get("own_sourced_opponent_blocking_demand", 0))
	if recovery_modes.has("customer_switch"):
		value += 8.0 + float(maxi(0, int(recovery.get("lost_to_competitor_demand", 0)))) * 4.0
		reasons.append("recovery_customer_switch")
	if recovery_modes.has("product_switch"):
		value += 8.0 + float(maxi(0, int(recovery.get("own_sourced_opponent_blocking_demand", 0)))) * 4.0
		reasons.append("recovery_product_switch")
	if recovery_pressure > 0:
		value += float(products.size()) * 2.0
	if int(income_analysis.get("total_pending_marketing_demand", 0)) <= 0:
		value += 5.0
		reasons.append("no_pending_marketing")
	if int(income_analysis.get("total_public_demand", 0)) <= 0:
		value += 5.0
		reasons.append("no_public_demand")
	elif _player_cash(observation) <= 0:
		value += 3.0
		reasons.append("cash_starved")
	if employee_id == "campaign_manager":
		value += 3.0
		reasons.append("campaign_manager")
	out["value"] = value
	out["marketing_activation_value"] = value
	out["marketing_activation_products"] = products
	out["marketing_activation_reasons"] = reasons
	return out

static func _errand_drink_activation_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var best := _empty_drink_activation_payload()
	for product_id in _drink_product_ids(income_analysis):
		var command := Command.create("procure_drinks", int(observation.current_player_id), {
			"employee_type": employee_id,
			"drink_type": product_id,
		})
		var units := StrategySupplyPlannerClass.expected_drink_units(observation, command)
		var product_features := {}
		var action_value := StrategySupplyPlannerClass.product_supply_action_value(product_id, profile, income_analysis, product_features, units, observation)
		if not _drink_activation_product_is_relevant(product_features):
			continue
		var product_value := maxf(0.0, action_value)
		if product_value <= 0.0:
			continue
		best["value"] = float(best.get("value", 0.0)) + product_value
		_append_unique_string(best["products"], product_id)
		best["units_by_product"][product_id] = units
		best["action_values"][product_id] = product_value
	return best

static func _route_drink_activation_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var best := _empty_drink_activation_payload()
	var routes_read := DrinkRouteAnalyzerClass.generate_routes(observation, employee_id, 6)
	if not routes_read.ok:
		return best
	var best_score := -INF
	for route_val in Array(routes_read.value):
		if not (route_val is Dictionary):
			continue
		var route: Dictionary = route_val
		var params_val = route.get("params", null)
		if not (params_val is Dictionary):
			continue
		var command := Command.create("procure_drinks", int(observation.current_player_id), Dictionary(params_val).duplicate(true))
		var expected_by_product := StrategySupplyPlannerClass.expected_route_drinks_by_product(observation, command)
		if expected_by_product.is_empty():
			continue
		var route_payload := _route_drink_activation_payload_from_expected(observation, expected_by_product, profile, income_analysis)
		var route_score := float(route_payload.get("value", 0.0))
		if route_score <= best_score:
			continue
		best_score = route_score
		best = route_payload
		best["route_source_count"] = int(route.get("source_count", 0))
		best["route_distance"] = int(route.get("distance", -1))
	return best

static func _route_drink_activation_payload_from_expected(observation: ObservationState, expected_by_product: Dictionary, profile, income_analysis: Dictionary) -> Dictionary:
	var out := _empty_drink_activation_payload()
	for product_id in _sorted_dictionary_keys(expected_by_product):
		var units := maxi(1, int(expected_by_product.get(product_id, 0)))
		var product_features := {}
		var action_value := StrategySupplyPlannerClass.product_supply_action_value(product_id, profile, income_analysis, product_features, units, observation)
		if not _drink_activation_product_is_relevant(product_features):
			continue
		var product_value := maxf(0.0, action_value)
		if product_value <= 0.0:
			continue
		out["value"] = float(out.get("value", 0.0)) + product_value
		_append_unique_string(out["products"], product_id)
		out["units_by_product"][product_id] = units
		out["action_values"][product_id] = product_value
	return out

static func _empty_drink_activation_payload() -> Dictionary:
	return {
		"value": 0.0,
		"products": [],
		"marketing_supply_products": [],
		"units_by_product": {},
		"action_values": {},
		"route_source_count": 0,
		"route_distance": -1,
	}

static func _drink_activation_product_is_relevant(product_features: Dictionary) -> bool:
	if int(product_features.get("product_serviceable_demand", 0)) > 0 and int(product_features.get("product_supply_covered_units", 0)) > 0:
		return true
	if int(product_features.get("product_effective_pending_marketing_demand", 0)) > 0 and int(product_features.get("product_supply_future_covered_units", 0)) > 0:
		return true
	if str(product_features.get("product_supply_relevance", "")) == "product_switch_gap" and int(product_features.get("product_supply_relevant_units", 0)) > 0:
		return true
	return false

static func _drink_product_ids(income_analysis: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_key in products.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var product_payload: Dictionary = Dictionary(products.get(product_key, {}))
		var is_drink := bool(product_payload.get("is_drink", false))
		if not is_drink and ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
			is_drink = ProductRegistryClass.is_drink(product_id)
		if is_drink and not out.has(product_id):
			out.append(product_id)
	out.sort()
	return out

static func _append_unique_string(target, text: String) -> void:
	if not (target is Array) or text.is_empty():
		return
	var arr: Array = target
	if not arr.has(text):
		arr.append(text)

static func _sorted_dictionary_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in dict.keys():
		var text := str(key)
		if not text.is_empty():
			out.append(text)
	out.sort()
	return out

static func _employee_food_products(employee_id: String) -> Array[String]:
	var out: Array[String] = []
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return out
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return out
	var def: EmployeeDef = def_val
	for product_val in def.get_production_food_options():
		var product_id := str(product_val)
		if not product_id.is_empty() and not out.has(product_id):
			out.append(product_id)
	out.sort()
	return out

static func _marketing_pipeline_needs_active_supply(observation: ObservationState, product_id: String) -> bool:
	if observation == null or product_id.is_empty():
		return false
	if _own_restaurant_count(observation) <= 0:
		return false
	if not _has_owned_marketing_employee(observation):
		return false
	if not _is_marketable_product(product_id):
		return false
	if _can_actively_supply_product(observation, product_id):
		return false
	return _inventory_count(observation, product_id) <= 0

static func _marketable_active_supply_products(observation: ObservationState, income_analysis: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if observation == null:
		return out
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_id in _sorted_dictionary_keys(products):
		if not _is_marketable_product(product_id):
			continue
		if _inventory_count(observation, product_id) <= 0 and not _can_actively_supply_product(observation, product_id):
			continue
		out.append(product_id)
	return out

static func _has_active_marketing_employee(observation: ObservationState) -> bool:
	if observation == null:
		return false
	for employee_id in _active_employee_ids(observation.own_player):
		if _employee_role(employee_id) == "marketing":
			return true
	return false

static func _has_owned_marketing_employee(observation: ObservationState) -> bool:
	if observation == null:
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if _employee_role(employee_id) == "marketing":
			return true
	return false

static func _is_marketable_product(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if not ProductRegistryClass.is_loaded() or not ProductRegistryClass.has(product_id):
		return true
	var def_val = ProductRegistryClass.get_def(product_id)
	if not (def_val is ProductDef):
		return true
	var def: ProductDef = def_val
	return not def.has_tag("no_marketing")

static func _append_price_employee_route_features(features: Dictionary, payload: Dictionary) -> void:
	features["structure_price_route_value"] = float(payload.get("value", 0.0))
	features["structure_price_route_serviceable_demand"] = int(payload.get("serviceable_demand", 0))
	features["structure_price_route_actionable_demand"] = int(payload.get("actionable_demand", 0))
	features["structure_price_route_recoverable_demand"] = int(payload.get("recoverable_demand", 0))
	features["structure_price_route_relevant_demand"] = int(payload.get("price_relevant_demand", payload.get("actionable_demand", 0)))
	features["structure_price_route_inventory_units"] = int(payload.get("inventory_units", 0))
	features["structure_price_route_estimated_sale_units"] = int(payload.get("estimated_sale_units", 0))
	features["structure_price_route_first_lower_prices_available"] = bool(payload.get("first_lower_prices_available", false))

static func _append_waitress_route_features(features: Dictionary, payload: Dictionary) -> void:
	features["structure_waitress_route_value"] = float(payload.get("value", 0.0))
	features["structure_waitress_tips"] = int(payload.get("tips", 0))
	features["structure_waitress_first_waitress_available"] = bool(payload.get("first_waitress_available", false))
	features["structure_waitress_first_waitress_value"] = float(payload.get("first_waitress_value", 0.0))

static func _append_employee_income_features(features: Dictionary, employee_payload: Dictionary) -> void:
	features["structure_income_employee_value"] = float(employee_payload.get("income_value", 0.0))
	features["structure_income_employee_role"] = str(employee_payload.get("role", ""))
	features["structure_target_products"] = Array(employee_payload.get("target_products", [])).duplicate()

static func _drink_route_readiness_adjustment(employee_id: String, income_analysis: Dictionary) -> float:
	if _employee_role(employee_id) != "procure_drink":
		return 0.0
	if bool(StrategyIncomeAnalyzerClass.drink_need(income_analysis).get("has_actionable_demand", false)):
		return 0.0
	return -120.0

static func _append_drink_need_features(features: Dictionary, income_analysis: Dictionary) -> void:
	var need: Dictionary = StrategyIncomeAnalyzerClass.drink_need(income_analysis)
	features["structure_drink_has_actionable_demand"] = bool(need.get("has_actionable_demand", false))
	features["structure_drink_actionable_inventory_gap"] = int(need.get("actionable_inventory_gap", 0))
	features["structure_drink_actionable_demand"] = int(need.get("actionable_demand", 0))
	features["structure_drink_serviceable_demand"] = int(need.get("serviceable_demand", 0))
	features["structure_drink_pending_marketing_demand"] = int(need.get("pending_marketing_demand", 0))

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

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

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

static func _inventory_count(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	return maxi(0, int(Dictionary(inventory_val).get(product_id, 0)))

static func _player_cash(observation: ObservationState) -> int:
	if observation == null:
		return 0
	return int(observation.own_player.get("cash", 0))

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out
