class_name StrategyEmployeePlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyRoutePlannerClass = preload("res://core/ai/strategy/strategy_route_planner.gd")

static func strategy_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	if employee_id.is_empty() or profile == null:
		return {
			"value": 0.0,
			"income_value": 0.0,
			"role": "",
			"target_products": [],
			"placement_route_value": 0.0,
		}
	var income_value := StrategyIncomeAnalyzerClass.employee_value(observation, employee_id, profile, income_analysis)
	var role := _employee_role(employee_id)
	var value: float = float(income_value.get("score", profile.employee_priority(employee_id)))
	if role == "produce_food" and not _owns_role(observation, "produce_food"):
		value += _profile_role_bonus(profile, "strategy_first_produce_food", 8.0)
	elif role == "marketing" and not _owns_role(observation, "marketing"):
		value += _profile_role_bonus(profile, "strategy_first_marketing", 7.0)
	elif role == "procure_drink" and not _owns_role(observation, "procure_drink") and bool(StrategyIncomeAnalyzerClass.drink_need(income_analysis).get("has_actionable_demand", false)):
		value += _profile_role_bonus(profile, "strategy_first_procure_drink", 6.0)
	elif role == "recruit_train" and _has_trainable_reserve_employee(observation):
		value += _profile_role_bonus(profile, "strategy_recruit_train_trainable", 5.0)
	elif role == "new_shop" and _own_restaurant_count(observation) <= 1:
		value += _profile_role_bonus(profile, "strategy_early_new_shop", 3.0)
	var placement_value := placement_route_value(observation, employee_id, income_analysis)
	value += placement_value
	return {
		"value": value,
		"income_value": float(income_value.get("score", 0.0)),
		"role": role,
		"target_products": Array(income_value.get("target_products", [])).duplicate(),
		"placement_route_value": placement_value,
	}

static func placement_route_value(observation: ObservationState, employee_id: String, income_analysis: Dictionary) -> float:
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

static func placement_route_readiness_adjustment(observation: ObservationState, employee_id: String, income_analysis: Dictionary) -> float:
	if not _employee_is_placement_employee(employee_id):
		return 0.0
	if not _has_house_growth_space(observation):
		return -115.0
	if _house_route_economy_ready(observation, income_analysis):
		return 0.0
	return -115.0

static func _house_route_economy_ready(observation: ObservationState, income_analysis: Dictionary) -> bool:
	return StrategyRoutePlannerClass.house_growth_ready(observation, income_analysis)

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

static func _owns_any_employee(observation: ObservationState, employee_ids: Array[String]) -> bool:
	if observation == null or employee_ids.is_empty():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if employee_ids.has(employee_id):
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

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out

static func _read_non_negative_int(value, fallback: int) -> int:
	if value is int:
		return maxi(0, int(value))
	if value is float:
		return maxi(0, int(value))
	if value is String and str(value).is_valid_int():
		return maxi(0, int(str(value)))
	return fallback

static func _profile_role_bonus(profile, key: String, fallback: float) -> float:
	if profile != null and profile.has_method("role_bonus"):
		return float(profile.role_bonus(key, fallback))
	return fallback
