class_name StrategyScorer
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
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
			var product_id2 := str(command.params.get("food_type", command.params.get("drink_type", "")))
			var supply_bonus := _product_supply_action_value(product_id2, profile, income_analysis, features)
			features["product_supply_action_value"] = supply_bonus
			score += supply_bonus
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

static func _product_supply_action_value(product_id: String, profile, income_analysis: Dictionary, features: Dictionary) -> float:
	if product_id.is_empty():
		return 0.0
	var product_payload := StrategyIncomeAnalyzerClass.product_value(product_id, profile, income_analysis)
	var public_demand := int(product_payload.get("public_demand", 0))
	var serviceable_demand := int(product_payload.get("serviceable_demand", 0))
	var inventory_units := int(product_payload.get("inventory_units", 0))
	var inventory_gap := int(product_payload.get("inventory_gap", 0))
	var can_supply := bool(product_payload.get("can_supply", false))
	features["product_public_demand"] = public_demand
	features["product_serviceable_demand"] = serviceable_demand
	features["product_inventory_units"] = inventory_units
	features["product_inventory_gap"] = inventory_gap
	features["product_can_supply"] = can_supply
	if inventory_gap > 0:
		return float(inventory_gap) * 12.0 + float(serviceable_demand) * 3.0 + float(public_demand) + float(profile.product_priority(product_id)) * 0.5
	if public_demand <= 0 and inventory_units <= 0:
		return float(profile.product_priority(product_id)) * 0.6
	var desired_buffer := public_demand + 1
	if public_demand > 0 and inventory_units < desired_buffer:
		return 4.0 + float(profile.product_priority(product_id)) * 0.25
	features["product_overstock_penalty"] = true
	return -100.0 - float(maxi(0, inventory_units - desired_buffer)) * 8.0

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

static func _read_non_negative_int(value, fallback: int) -> int:
	if value is int:
		return maxi(0, int(value))
	if value is float:
		return maxi(0, int(value))
	if value is String and str(value).is_valid_int():
		return maxi(0, int(str(value)))
	return fallback
