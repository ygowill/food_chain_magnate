class_name StrategyScorer
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

static func score_macro(observation: ObservationState, macro: MacroAction, profile) -> Dictionary:
	if observation == null or macro == null or profile == null or macro.commands.is_empty():
		return {"score": -INF, "features": {}}
	var command: Command = macro.commands[0]
	if command == null:
		return {"score": -INF, "features": {}}

	var action_id := str(command.action_id)
	var features := {
		"action_weight": profile.action_weight(action_id),
		"candidate_prior": float(macro.prior_score),
	}
	var score := float(features["action_weight"]) + float(macro.prior_score)

	match action_id:
		"recruit":
			var employee_id := str(command.params.get("employee_type", ""))
			var bonus := _employee_strategy_value(observation, employee_id, profile)
			features["employee_value"] = bonus
			score += bonus
		"train":
			var from_employee := str(command.params.get("from_employee", ""))
			var to_employee := str(command.params.get("to_employee", ""))
			var train_bonus: float = float(profile.employee_priority(to_employee)) * 2.0 + maxf(0.0, float(profile.employee_priority(to_employee)) - float(profile.employee_priority(from_employee)))
			features["train_value"] = train_bonus
			score += train_bonus
		"set_company_structure_direct", "set_company_structure_report", "restructure_employee":
			var employee_id2 := str(command.params.get("employee_id", ""))
			var structure_bonus := _employee_strategy_value(observation, employee_id2, profile)
			features["structure_employee_value"] = structure_bonus
			score += structure_bonus
		"initiate_marketing":
			var product_id := str(command.params.get("product", ""))
			var affected_count := _affected_house_count(macro)
			var marketing_bonus := float(affected_count) * 12.0 + _product_pipeline_value(observation, product_id, profile)
			features["affected_houses"] = affected_count
			features["product_pipeline_value"] = marketing_bonus
			score += marketing_bonus
		"produce_food", "procure_drinks":
			var product_id2 := str(command.params.get("food_type", command.params.get("drink_type", "")))
			var pipeline_bonus := _product_pipeline_value(observation, product_id2, profile)
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

static func _employee_strategy_value(observation: ObservationState, employee_id: String, profile) -> float:
	if employee_id.is_empty():
		return 0.0
	var value: float = float(profile.employee_priority(employee_id))
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

static func _product_pipeline_value(observation: ObservationState, product_id: String, profile) -> float:
	if product_id.is_empty():
		return 0.0
	var demand := _public_demand_count_for_product(observation, product_id)
	var inventory := _inventory_count(observation, product_id)
	var value: float = float(profile.product_priority(product_id))
	value += float(demand) * 4.0
	if demand > 0 and inventory < demand:
		value += float(demand - inventory) * 3.0
	elif inventory <= 0:
		value += 1.0
	if _can_supply_product(observation, product_id):
		value += 2.0
	return value

static func _affected_house_count(macro: MacroAction) -> int:
	if macro == null:
		return 0
	var affected_val = macro.debug.get("affected_house_ids", [])
	if affected_val is Array:
		return Array(affected_val).size()
	return 0

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
