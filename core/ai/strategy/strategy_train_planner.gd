class_name StrategyTrainPlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DrinkRouteAnalyzerClass = preload("res://core/ai/analysis/drink_route_analyzer.gd")
const StrategyEmployeePlannerClass = preload("res://core/ai/strategy/strategy_employee_planner.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategySupplyPlannerClass = preload("res://core/ai/strategy/strategy_supply_planner.gd")

static func evaluate_action(observation: ObservationState, command: Command, profile, income_analysis: Dictionary) -> Dictionary:
	var features := {}
	if observation == null or command == null or profile == null:
		return {"value": 0.0, "features": features}
	var from_employee := str(command.params.get("from_employee", ""))
	var to_employee := str(command.params.get("to_employee", ""))
	var target_value := StrategyIncomeAnalyzerClass.employee_value(observation, to_employee, profile, income_analysis)
	var placement_route_value := StrategyEmployeePlannerClass.placement_route_value(observation, to_employee, income_analysis)
	var route_readiness_adjustment := StrategyEmployeePlannerClass.placement_route_readiness_adjustment(observation, to_employee, income_analysis)
	var capacity_upgrade_payload := capacity_upgrade_value(observation, from_employee, to_employee, profile, income_analysis)
	var capacity_upgrade_value_total := float(capacity_upgrade_payload.get("value", 0.0))
	var drink_route_upgrade_payload := drink_route_upgrade_value(observation, from_employee, to_employee, profile, income_analysis)
	var drink_route_upgrade_value_total := float(drink_route_upgrade_payload.get("value", 0.0))
	var drink_route_readiness_adjustment_value := drink_route_readiness_adjustment(to_employee, income_analysis)
	var value: float = float(target_value.get("score", 0.0)) * 1.2 + maxf(0.0, float(profile.employee_priority(to_employee)) - float(profile.employee_priority(from_employee))) + placement_route_value + route_readiness_adjustment + capacity_upgrade_value_total + drink_route_upgrade_value_total + drink_route_readiness_adjustment_value
	features["train_value"] = value
	features["train_target_income_value"] = float(target_value.get("score", 0.0))
	features["train_placement_route_value"] = placement_route_value
	features["train_route_readiness_adjustment"] = route_readiness_adjustment
	features["train_drink_route_readiness_adjustment"] = drink_route_readiness_adjustment_value
	_append_drink_need_features(features, income_analysis)
	_append_capacity_upgrade_features(features, capacity_upgrade_payload)
	_append_drink_route_upgrade_features(features, drink_route_upgrade_payload)
	features["train_target_products"] = Array(target_value.get("target_products", [])).duplicate()
	return {"value": value, "features": features}

static func capacity_upgrade_value(observation: ObservationState, from_employee: String, to_employee: String, profile, income_analysis: Dictionary) -> Dictionary:
	var out := {
		"value": 0.0,
		"products": [],
		"target_units_by_product": {},
		"source_units_by_product": {},
		"delta_units_by_product": {},
		"target_action_values": {},
		"source_action_values": {},
	}
	if observation == null or from_employee.is_empty() or to_employee.is_empty() or profile == null:
		return out
	if not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(to_employee):
		return out
	var target_def_val = EmployeeRegistryClass.get_def(to_employee)
	if not (target_def_val is EmployeeDef):
		return out
	var target_def: EmployeeDef = target_def_val
	if not target_def.can_produce():
		return out
	var target_units := StrategySupplyPlannerClass.expected_food_units(to_employee)
	var source_units := StrategySupplyPlannerClass.expected_food_units(from_employee)
	var products: Array[String] = []
	for product_val in target_def.get_production_food_options():
		var product_id := str(product_val)
		if not product_id.is_empty():
			products.append(product_id)
	products.sort()
	var total := 0.0
	var valued_products: Array[String] = []
	var target_units_by_product := {}
	var source_units_by_product := {}
	var delta_units_by_product := {}
	var target_action_values := {}
	var source_action_values := {}
	for product_id in products:
		var source_can_produce := _employee_can_produce_product(from_employee, product_id)
		var product_source_units := source_units if source_can_produce else 0
		var delta_units := maxi(0, target_units - product_source_units)
		if delta_units <= 0:
			continue
		var target_features := {}
		var source_features := {}
		var target_action_value := StrategySupplyPlannerClass.product_supply_action_value(product_id, profile, income_analysis, target_features, target_units, observation)
		var source_action_value := 0.0
		if product_source_units > 0:
			source_action_value = StrategySupplyPlannerClass.product_supply_action_value(product_id, profile, income_analysis, source_features, product_source_units, observation)
		var delta_value := maxf(0.0, target_action_value - source_action_value) * 0.75
		if delta_value <= 0.0:
			continue
		total += delta_value
		valued_products.append(product_id)
		target_units_by_product[product_id] = target_units
		source_units_by_product[product_id] = product_source_units
		delta_units_by_product[product_id] = delta_units
		target_action_values[product_id] = target_action_value
		source_action_values[product_id] = source_action_value
	out["value"] = total
	out["products"] = valued_products
	out["target_units_by_product"] = target_units_by_product
	out["source_units_by_product"] = source_units_by_product
	out["delta_units_by_product"] = delta_units_by_product
	out["target_action_values"] = target_action_values
	out["source_action_values"] = source_action_values
	return out

static func drink_route_upgrade_value(observation: ObservationState, from_employee: String, to_employee: String, profile, income_analysis: Dictionary) -> Dictionary:
	var out := {
		"value": 0.0,
		"products": [],
		"target_units_by_product": {},
		"source_units_by_product": {},
		"delta_units_by_product": {},
		"target_action_values": {},
		"source_action_values": {},
		"target_route_source_count": 0,
		"target_route_distance": -1,
	}
	if observation == null or from_employee.is_empty() or to_employee.is_empty() or profile == null:
		return out
	if not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(to_employee):
		return out
	var target_def_val = EmployeeRegistryClass.get_def(to_employee)
	if not (target_def_val is EmployeeDef):
		return out
	var target_def: EmployeeDef = target_def_val
	if not target_def.can_procure() or to_employee == "errand_boy":
		return out
	var target_payload := _best_route_drink_expected_by_product(observation, to_employee, profile, income_analysis)
	var target_units_by_product: Dictionary = Dictionary(target_payload.get("units_by_product", {}))
	if target_units_by_product.is_empty():
		return out
	var source_units_by_product := _source_drink_expected_by_product(observation, from_employee, target_units_by_product, profile, income_analysis)
	var total := 0.0
	var valued_products: Array[String] = []
	var delta_units_by_product := {}
	var target_action_values := {}
	var source_action_values := {}
	for product_id in _sorted_dictionary_keys(target_units_by_product):
		var target_units := maxi(0, int(target_units_by_product.get(product_id, 0)))
		var source_units := maxi(0, int(source_units_by_product.get(product_id, 0)))
		var delta_units := maxi(0, target_units - source_units)
		if delta_units <= 0:
			continue
		var target_features := {}
		var source_features := {}
		var target_action_value := StrategySupplyPlannerClass.product_supply_action_value(product_id, profile, income_analysis, target_features, target_units, observation)
		var source_action_value := 0.0
		if source_units > 0:
			source_action_value = StrategySupplyPlannerClass.product_supply_action_value(product_id, profile, income_analysis, source_features, source_units, observation)
		var delta_value := maxf(0.0, target_action_value - source_action_value) * 0.75
		if delta_value <= 0.0:
			continue
		total += delta_value
		valued_products.append(product_id)
		delta_units_by_product[product_id] = delta_units
		target_action_values[product_id] = target_action_value
		source_action_values[product_id] = source_action_value
	out["value"] = total
	out["products"] = valued_products
	out["target_units_by_product"] = target_units_by_product
	out["source_units_by_product"] = source_units_by_product
	out["delta_units_by_product"] = delta_units_by_product
	out["target_action_values"] = target_action_values
	out["source_action_values"] = source_action_values
	out["target_route_source_count"] = int(target_payload.get("source_count", 0))
	out["target_route_distance"] = int(target_payload.get("distance", -1))
	return out

static func drink_route_readiness_adjustment(to_employee: String, income_analysis: Dictionary) -> float:
	if _employee_role(to_employee) != "procure_drink":
		return 0.0
	if bool(StrategyIncomeAnalyzerClass.drink_need(income_analysis).get("has_actionable_demand", false)):
		return 0.0
	return -120.0

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func _append_capacity_upgrade_features(features: Dictionary, payload: Dictionary) -> void:
	features["train_capacity_upgrade_value"] = float(payload.get("value", 0.0))
	features["train_capacity_upgrade_products"] = Array(payload.get("products", [])).duplicate()
	features["train_capacity_upgrade_target_units_by_product"] = Dictionary(payload.get("target_units_by_product", {})).duplicate()
	features["train_capacity_upgrade_source_units_by_product"] = Dictionary(payload.get("source_units_by_product", {})).duplicate()
	features["train_capacity_upgrade_delta_units_by_product"] = Dictionary(payload.get("delta_units_by_product", {})).duplicate()
	features["train_capacity_upgrade_target_action_values"] = Dictionary(payload.get("target_action_values", {})).duplicate()
	features["train_capacity_upgrade_source_action_values"] = Dictionary(payload.get("source_action_values", {})).duplicate()

static func _append_drink_route_upgrade_features(features: Dictionary, payload: Dictionary) -> void:
	features["train_drink_route_upgrade_value"] = float(payload.get("value", 0.0))
	features["train_drink_route_upgrade_products"] = Array(payload.get("products", [])).duplicate()
	features["train_drink_route_upgrade_target_units_by_product"] = Dictionary(payload.get("target_units_by_product", {})).duplicate()
	features["train_drink_route_upgrade_source_units_by_product"] = Dictionary(payload.get("source_units_by_product", {})).duplicate()
	features["train_drink_route_upgrade_delta_units_by_product"] = Dictionary(payload.get("delta_units_by_product", {})).duplicate()
	features["train_drink_route_upgrade_target_action_values"] = Dictionary(payload.get("target_action_values", {})).duplicate()
	features["train_drink_route_upgrade_source_action_values"] = Dictionary(payload.get("source_action_values", {})).duplicate()
	features["train_drink_route_upgrade_target_route_source_count"] = int(payload.get("target_route_source_count", 0))
	features["train_drink_route_upgrade_target_route_distance"] = int(payload.get("target_route_distance", -1))

static func _append_drink_need_features(features: Dictionary, income_analysis: Dictionary) -> void:
	var need: Dictionary = StrategyIncomeAnalyzerClass.drink_need(income_analysis)
	features["train_drink_has_actionable_demand"] = bool(need.get("has_actionable_demand", false))
	features["train_drink_actionable_inventory_gap"] = int(need.get("actionable_inventory_gap", 0))
	features["train_drink_actionable_demand"] = int(need.get("actionable_demand", 0))
	features["train_drink_serviceable_demand"] = int(need.get("serviceable_demand", 0))
	features["train_drink_pending_marketing_demand"] = int(need.get("pending_marketing_demand", 0))

static func _employee_can_produce_product(employee_id: String, product_id: String) -> bool:
	if employee_id.is_empty() or product_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	return def.can_produce() and def.get_production_food_options().has(product_id)

static func _best_route_drink_expected_by_product(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var out := {
		"units_by_product": {},
		"source_count": 0,
		"distance": -1,
	}
	if observation == null or employee_id.is_empty():
		return out
	var routes_read := DrinkRouteAnalyzerClass.generate_routes(observation, employee_id, 6)
	if not routes_read.ok:
		return out
	var routes: Array = Array(routes_read.value)
	var best_units_by_product := {}
	var best_score := -INF
	var best_source_count := 0
	var best_distance := -1
	for route_val in routes:
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
		var route_score := 0.0
		for product_id in _sorted_dictionary_keys(expected_by_product):
			var product_payload := StrategyIncomeAnalyzerClass.product_value(product_id, profile, income_analysis)
			route_score += float(expected_by_product.get(product_id, 0)) * float(product_payload.get("score", 0.0))
		if route_score <= best_score:
			continue
		best_score = route_score
		best_units_by_product = expected_by_product
		best_source_count = int(route.get("source_count", 0))
		best_distance = int(route.get("distance", -1))
	out["units_by_product"] = best_units_by_product
	out["source_count"] = best_source_count
	out["distance"] = best_distance
	return out

static func _source_drink_expected_by_product(observation: ObservationState, from_employee: String, target_units_by_product: Dictionary, profile, income_analysis: Dictionary) -> Dictionary:
	if from_employee.is_empty():
		return {}
	if from_employee == "errand_boy":
		var out := {}
		for product_id in _sorted_dictionary_keys(target_units_by_product):
			var command := Command.create("procure_drinks", int(observation.current_player_id), {
				"employee_type": "errand_boy",
				"drink_type": product_id,
			})
			out[product_id] = StrategySupplyPlannerClass.expected_drink_units(observation, command)
		return out
	var source_payload := _best_route_drink_expected_by_product(observation, from_employee, profile, income_analysis)
	return Dictionary(source_payload.get("units_by_product", {}))

static func _sorted_dictionary_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in dict.keys():
		var text := str(key)
		if not text.is_empty():
			out.append(text)
	out.sort()
	return out
