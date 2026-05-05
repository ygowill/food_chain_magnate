class_name StrategyScorer
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")

static func score_macro(observation: ObservationState, macro: MacroAction, profile) -> Dictionary:
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
			features["employee_value"] = bonus
			_append_employee_income_features(features, observation, employee_id, income_analysis, profile, "recruit")
			score += bonus
		"train":
			var from_employee := str(command.params.get("from_employee", ""))
			var to_employee := str(command.params.get("to_employee", ""))
			var target_value := StrategyIncomeAnalyzerClass.employee_value(observation, to_employee, profile, income_analysis)
			var train_bonus: float = float(target_value.get("score", 0.0)) * 1.2 + maxf(0.0, float(profile.employee_priority(to_employee)) - float(profile.employee_priority(from_employee)))
			features["train_value"] = train_bonus
			features["train_target_income_value"] = float(target_value.get("score", 0.0))
			features["train_target_products"] = Array(target_value.get("target_products", [])).duplicate()
			score += train_bonus
		"set_company_structure_direct", "set_company_structure_report", "restructure_employee":
			var employee_id2 := str(command.params.get("employee_id", ""))
			var structure_bonus := _employee_strategy_value(observation, employee_id2, profile, income_analysis)
			features["structure_employee_value"] = structure_bonus
			_append_employee_income_features(features, observation, employee_id2, income_analysis, profile, "structure")
			score += structure_bonus
		"initiate_marketing":
			var product_id := str(command.params.get("product", ""))
			var affected_ids := _affected_house_ids(macro)
			var affected_count := affected_ids.size()
			var pipeline_value := _product_pipeline_value(product_id, profile, income_analysis, features)
			var service_features := _marketing_service_features(observation, affected_ids, product_id)
			var marketing_bonus := _marketing_value_from_features(affected_count, pipeline_value, service_features)
			features["affected_houses"] = affected_count
			features["affected_house_ids"] = affected_ids.duplicate()
			features["product_pipeline_value"] = pipeline_value
			features["marketing_serviceable_houses"] = int(service_features.get("serviceable_houses", 0))
			features["marketing_closest_distance"] = int(service_features.get("closest_distance", -1))
			features["marketing_inventory_units"] = int(service_features.get("inventory_units", 0))
			features["marketing_can_supply_product"] = bool(service_features.get("can_supply_product", false))
			features["marketing_own_restaurants"] = int(service_features.get("own_restaurants", 0))
			features["marketing_value"] = marketing_bonus
			score += marketing_bonus
		"produce_food", "procure_drinks":
			var product_id2 := str(command.params.get("food_type", command.params.get("drink_type", "")))
			var pipeline_bonus := _product_pipeline_value(product_id2, profile, income_analysis, features)
			features["product_pipeline_value"] = pipeline_bonus
			score += pipeline_bonus
		"place_restaurant":
			var restaurant_bonus := 12.0 if _own_restaurant_count(observation) <= 0 else 4.0
			features["restaurant_value"] = restaurant_bonus
			score += restaurant_bonus
		"choose_turn_order":
			var position := int(command.params.get("position", 0))
			var turn_bonus := maxf(0.0, 8.0 - float(position) * 2.0)
			features["turn_order_value"] = turn_bonus
			score += turn_bonus
		"skip", "skip_sub_phase":
			var skip_penalty := -10.0 if _has_non_skip_alternative(observation, macro) else 0.0
			features["skip_penalty"] = skip_penalty
			score += skip_penalty

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
	return value

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

static func _append_employee_income_features(features: Dictionary, observation: ObservationState, employee_id: String, income_analysis: Dictionary, profile, prefix: String) -> void:
	var payload := StrategyIncomeAnalyzerClass.employee_value(observation, employee_id, profile, income_analysis)
	features["%s_income_employee_value" % prefix] = float(payload.get("score", 0.0))
	features["%s_income_employee_role" % prefix] = str(payload.get("role", ""))
	features["%s_target_products" % prefix] = Array(payload.get("target_products", [])).duplicate()

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

static func _marketing_service_features(observation: ObservationState, affected_house_ids: Array[String], product_id: String) -> Dictionary:
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
		"can_supply_product": _can_supply_product(observation, product_id),
		"own_restaurants": _own_restaurant_count(observation),
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

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out
