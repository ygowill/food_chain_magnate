class_name StrategyRecoveryPlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

static func analyze(income_analysis: Dictionary) -> Dictionary:
	var products := {}
	var lost_total := maxi(0, int(income_analysis.get("total_lost_to_competitor_demand", 0)))
	var price_recoverable_total := maxi(0, int(income_analysis.get("total_price_recoverable_demand", 0)))
	var product_switch_total := maxi(0, int(income_analysis.get("total_own_sourced_opponent_blocking_demand", 0)))
	var modes: Array[String] = []
	if lost_total > 0:
		modes.append("customer_switch")
	if price_recoverable_total > 0:
		modes.append("price_recovery")
	if product_switch_total > 0:
		modes.append("product_switch")
	var products_val = income_analysis.get("products", {})
	if products_val is Dictionary:
		for product_key in Dictionary(products_val).keys():
			var product_id := str(product_key)
			if product_id.is_empty():
				continue
			var product: Dictionary = Dictionary(Dictionary(products_val).get(product_key, {}))
			var lost := maxi(0, int(product.get("lost_to_competitor_demand", 0)))
			var recoverable := maxi(0, int(product.get("price_recoverable_demand", 0)))
			var product_switch := maxi(0, int(product.get("own_sourced_opponent_blocking_demand", 0)))
			if lost <= 0 and recoverable <= 0 and product_switch <= 0:
				continue
			products[product_id] = {
				"lost_to_competitor_demand": lost,
				"price_recoverable_demand": recoverable,
				"own_sourced_opponent_blocking_demand": product_switch,
			}
	return {
		"needs_recovery": lost_total > 0 or price_recoverable_total > 0 or product_switch_total > 0,
		"lost_to_competitor_demand": lost_total,
		"price_recoverable_demand": price_recoverable_total,
		"own_sourced_opponent_blocking_demand": product_switch_total,
		"modes": modes,
		"products": products,
	}

static func marketing_capacity_plan(observation: ObservationState, income_analysis: Dictionary) -> Dictionary:
	var recovery := analyze(income_analysis)
	var base_desired := 1 if _own_restaurant_count(observation) > 0 else 0
	var owned_marketing := _owned_marketing_count(observation)
	var available_marketing := _available_marketing_count(observation)
	var busy_marketing := _busy_marketing_count(observation)
	var modes := Array(recovery.get("modes", [])).duplicate()
	var needs_recovery_capacity := bool(recovery.get("needs_recovery", false)) and base_desired > 0
	var desired := base_desired
	var reasons: Array[String] = []
	if needs_recovery_capacity and owned_marketing > 0 and available_marketing <= 0:
		desired = 2
		reasons.append("owned_marketing_busy")
	if modes.has("customer_switch"):
		reasons.append("customer_switch")
	if modes.has("product_switch"):
		reasons.append("product_switch")
	if modes.has("price_recovery"):
		reasons.append("price_recovery")
	return {
		"desired_count": desired,
		"base_desired_count": base_desired,
		"needs_extra_capacity": desired > base_desired,
		"owned_marketing_count": owned_marketing,
		"available_marketing_count": available_marketing,
		"busy_marketing_count": busy_marketing,
		"modes": modes,
		"reasons": reasons,
	}

static func marketing_response_value(pressure: Dictionary, income_analysis: Dictionary) -> Dictionary:
	var recovery := analyze(income_analysis)
	var lost_total := int(recovery.get("lost_to_competitor_demand", 0))
	var price_recoverable_total := int(recovery.get("price_recoverable_demand", 0))
	var product_switch_total := int(recovery.get("own_sourced_opponent_blocking_demand", 0))
	var public_total := maxi(0, int(income_analysis.get("total_public_demand", 0)))
	var actionable_total := maxi(0, int(income_analysis.get("total_actionable_demand", 0)))
	var stalled_public_demand := maxi(0, public_total - actionable_total)
	var self_capture := maxi(0, int(pressure.get("self_capture_houses", pressure.get("competitive_houses", 0))))
	var opponent_pressure := maxi(0, int(pressure.get("opponent_pressure_houses", pressure.get("opponent_capacity_gap_houses", 0))))
	var opponent_prevented_sales := maxi(0, int(pressure.get("opponent_capacity_gap_prevented_sales", 0)))
	var needs_customer_route := lost_total > 0 or (public_total > 0 and actionable_total <= 0)
	var needs_product_switch := product_switch_total > 0 or opponent_pressure > 0
	var value := 0.0
	var modes: Array[String] = []
	if needs_customer_route and self_capture > 0:
		var customer_pressure := maxi(lost_total, stalled_public_demand)
		value += float(mini(customer_pressure, self_capture)) * 16.0 + float(self_capture) * 4.0
		modes.append("alternate_customer")
		modes.append("customer_switch")
	if needs_product_switch and opponent_pressure > 0:
		value += float(opponent_pressure) * 10.0 + float(opponent_prevented_sales) * 8.0 + float(product_switch_total) * 4.0
		modes.append("opponent_capacity_attack")
		modes.append("product_switch")
	if price_recoverable_total > 0:
		modes.append("price_recovery")
	return {
		"value": value,
		"needs_recovery": bool(recovery.get("needs_recovery", false)) or needs_customer_route or needs_product_switch,
		"lost_to_competitor_demand": lost_total,
		"price_recoverable_demand": price_recoverable_total,
		"own_sourced_opponent_blocking_demand": product_switch_total,
		"stalled_public_demand": stalled_public_demand,
		"modes": modes,
	}

static func price_response_value(price_payload: Dictionary, income_analysis: Dictionary) -> Dictionary:
	var recovery := analyze(income_analysis)
	var recoverable_total := maxi(0, int(recovery.get("price_recoverable_demand", 0)))
	var action_delta := int(price_payload.get("action_delta", 0))
	var projected_actionable := maxi(0, int(price_payload.get("actionable_demand", 0)))
	var estimated_sale_units := maxi(0, int(price_payload.get("estimated_sale_units", 0)))
	var value := 0.0
	var modes: Array[String] = []
	if action_delta < 0 and recoverable_total > 0 and projected_actionable > 0:
		var recoverable_units := maxi(0, int(price_payload.get("recoverable_demand", recoverable_total)))
		value = float(recoverable_units) * 8.0 + float(estimated_sale_units) * 2.0
		modes.append("price_recovery")
	return {
		"value": value,
		"needs_recovery": recoverable_total > 0,
		"price_recoverable_demand": recoverable_total,
		"modes": modes,
	}

static func _own_restaurant_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var restaurants_val = observation.own_player.get("restaurants", [])
	if restaurants_val is Array:
		return Array(restaurants_val).size()
	return 0

static func _owned_marketing_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var total := 0
	for employee_id in _owned_employee_ids(observation.own_player):
		if _employee_role(employee_id) == "marketing":
			total += 1
	return total

static func _available_marketing_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var total := 0
	for employee_id in _active_employee_ids(observation.own_player):
		if _employee_role(employee_id) == "marketing":
			total += 1
	for employee_id in _reserve_employee_ids(observation.own_player):
		if _employee_role(employee_id) == "marketing":
			total += 1
	return total

static func _busy_marketing_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var total := 0
	for employee_id in _busy_employee_ids(observation.own_player):
		if _employee_role(employee_id) == "marketing":
			total += 1
	return total

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func _active_employee_ids(player: Dictionary) -> Array[String]:
	return _sorted_unique_strings(player.get("employees", []))

static func _reserve_employee_ids(player: Dictionary) -> Array[String]:
	return _sorted_unique_strings(player.get("reserve_employees", []))

static func _busy_employee_ids(player: Dictionary) -> Array[String]:
	return _sorted_unique_strings(player.get("busy_marketers", []))

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

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out
