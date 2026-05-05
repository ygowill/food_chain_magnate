class_name Evaluator
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

static func score_observation(observation: ObservationState, player_id: int) -> Result:
	if observation == null:
		return Result.failure("Evaluator.score_observation: observation is null")
	if player_id != observation.viewer_player_id:
		return Result.failure("Evaluator.score_observation: player_id does not match observation")

	var own := observation.own_player
	var features := {
		"cash": _number(own.get("cash", 0)),
		"inventory_units": float(_sum_inventory(own.get("inventory", {}))),
		"active_employees": float(_array_size(own.get("employees", []))),
		"reserve_employees": float(_array_size(own.get("reserve_employees", []))),
		"restaurants": float(_array_size(own.get("restaurants", []))),
		"milestones": float(_array_size(own.get("milestones", []))),
		"employee_capability_value": _employee_capability_value(own),
		"salary_liability": _salary_liability(own),
		"own_marketing_instances": float(_count_owned_marketing_instances(observation.marketing_instances_public, player_id)),
		"bank_cash": _number(observation.bank_public.get("cash", 0)),
	}
	var score := 0.0
	score += float(features["cash"])
	score += float(features["inventory_units"]) * 3.0
	score += float(features["active_employees"]) * 5.0
	score += float(features["reserve_employees"]) * 2.0
	score += float(features["restaurants"]) * 8.0
	score += float(features["milestones"]) * 6.0
	score += float(features["employee_capability_value"])
	score += float(features["own_marketing_instances"]) * 8.0
	score -= float(features["salary_liability"]) * 4.0
	score += float(features["bank_cash"]) * 0.01

	return Result.success({
		"score": score,
		"features": features,
	})

static func _number(value) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0

static func _array_size(value) -> int:
	if value is Array:
		return Array(value).size()
	return 0

static func _sum_inventory(value) -> int:
	if not (value is Dictionary):
		return 0
	var total := 0
	var dict: Dictionary = value
	for key in dict.keys():
		total += maxi(0, int(dict.get(key, 0)))
	return total

static func _employee_capability_value(player: Dictionary) -> float:
	var total := 0.0
	total += _employee_list_capability_value(player.get("employees", []), 1.0)
	total += _employee_list_capability_value(player.get("reserve_employees", []), 0.7)
	total += _employee_list_capability_value(player.get("busy_marketers", []), 0.6)
	return total

static func _employee_list_capability_value(value, zone_weight: float) -> float:
	if not (value is Array):
		return 0.0
	var total := 0.0
	for item in Array(value):
		total += _employee_base_capability_value(str(item)) * zone_weight
	return total

static func _employee_base_capability_value(employee_id: String) -> float:
	if employee_id.is_empty() or employee_id == "ceo":
		return 0.0
	if not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return 1.0
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return 1.0
	var def: EmployeeDef = def_val
	var value := 1.0
	match str(def.role):
		"marketing":
			value += 7.0
		"produce_food":
			value += 7.0
		"procure_drink":
			value += 5.0
		"recruit_train":
			value += 4.0
		"price":
			value += 3.0
		"new_shop":
			value += 3.0
		"manager":
			value += 2.0
		"special":
			value += 2.0
	if def.is_entry_level():
		value += 2.0
	if not bool(def.salary):
		value += 2.0
	return value

static func _salary_liability(player: Dictionary) -> float:
	var total := 0.0
	total += _employee_list_salary_liability(player.get("employees", []))
	total += _employee_list_salary_liability(player.get("reserve_employees", []))
	total += _employee_list_salary_liability(player.get("busy_marketers", []))
	return total

static func _employee_list_salary_liability(value) -> float:
	if not (value is Array):
		return 0.0
	var total := 0.0
	for item in Array(value):
		var employee_id := str(item)
		if employee_id.is_empty() or employee_id == "ceo":
			continue
		if not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and bool((def_val as EmployeeDef).salary):
			total += 1.0
	return total

static func _count_owned_marketing_instances(value, player_id: int) -> int:
	if not (value is Array):
		return 0
	var count := 0
	for item in Array(value):
		if not (item is Dictionary):
			continue
		var dict: Dictionary = item
		if int(dict.get("owner", -1)) == player_id:
			count += 1
	return count
