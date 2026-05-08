class_name StrategyRoutePlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

static func analyze(observation: ObservationState, income_analysis: Dictionary, _profile = null) -> Dictionary:
	var cash := _cash(observation)
	var salary_cost := _salary_cost(observation)
	var total_public_demand := maxi(0, int(income_analysis.get("total_public_demand", 0)))
	var total_serviceable_demand := maxi(0, int(income_analysis.get("total_serviceable_demand", 0)))
	var total_actionable_demand := maxi(0, int(income_analysis.get("total_actionable_demand", total_serviceable_demand)))
	var total_price_recoverable_demand := maxi(0, int(income_analysis.get("total_price_recoverable_demand", 0)))
	var serviceable_inventory_units := _serviceable_inventory_units(income_analysis)
	var actionable_inventory_units := _actionable_inventory_units(income_analysis)
	var price_recoverable_inventory_units := _price_recoverable_inventory_units(income_analysis)
	var own_restaurants := _own_restaurant_count(observation)
	var owns_food_supply := _owns_role(observation, "produce_food")
	var owns_drink_supply := _owns_role(observation, "procure_drink")
	var owns_marketing := _owns_role(observation, "marketing")
	var owns_price := _owns_role(observation, "price")
	var milestones := _own_milestones(observation)
	var supply_readiness := _actionable_demand_supply_readiness(income_analysis, owns_food_supply, owns_drink_supply)
	var supply_ready_actionable_demand := int(supply_readiness.get("ready_actionable_demand", 0))
	var supply_blocked_actionable_demand := int(supply_readiness.get("blocked_actionable_demand", 0))
	var price_recoverable_readiness := _price_recoverable_demand_supply_readiness(income_analysis, owns_food_supply, owns_drink_supply)
	var price_recoverable_supply_ready_demand := int(price_recoverable_readiness.get("ready_recoverable_demand", 0))
	var price_recoverable_supply_blocked_demand := int(price_recoverable_readiness.get("blocked_recoverable_demand", 0))
	var price_route_ready_demand := supply_ready_actionable_demand + price_recoverable_supply_ready_demand
	var price_route_sale_inventory_units := actionable_inventory_units + price_recoverable_inventory_units

	var stable_income_ready := false
	if own_restaurants > 0 and owns_food_supply and owns_marketing:
		if cash >= maxi(20, salary_cost * 4):
			stable_income_ready = supply_ready_actionable_demand >= 2 and supply_blocked_actionable_demand <= 0
	var price_route_ready := own_restaurants > 0 and price_route_ready_demand > 0
	price_route_ready = price_route_ready and (price_route_sale_inventory_units > 0 or stable_income_ready or (owns_marketing and price_recoverable_supply_ready_demand > 0))

	var house_growth_ready := false
	if stable_income_ready and _has_house_growth_space(observation):
		if cash >= maxi(40, salary_cost * 8):
			house_growth_ready = supply_ready_actionable_demand >= 3

	var waitress_support_ready := owns_price or milestones.has("first_lower_prices")
	return {
		"cash": cash,
		"salary_cost": salary_cost,
		"own_restaurants": own_restaurants,
		"owns_food_supply": owns_food_supply,
		"owns_drink_supply": owns_drink_supply,
		"owns_marketing": owns_marketing,
		"owns_price": owns_price,
		"total_public_demand": total_public_demand,
		"total_serviceable_demand": total_serviceable_demand,
		"total_actionable_demand": total_actionable_demand,
		"total_price_recoverable_demand": total_price_recoverable_demand,
		"supply_ready_actionable_demand": supply_ready_actionable_demand,
		"supply_blocked_actionable_demand": supply_blocked_actionable_demand,
		"price_recoverable_supply_ready_demand": price_recoverable_supply_ready_demand,
		"price_recoverable_supply_blocked_demand": price_recoverable_supply_blocked_demand,
		"price_route_ready_demand": price_route_ready_demand,
		"serviceable_inventory_units": serviceable_inventory_units,
		"actionable_inventory_units": actionable_inventory_units,
		"price_recoverable_inventory_units": price_recoverable_inventory_units,
		"price_route_sale_inventory_units": price_route_sale_inventory_units,
		"price_route_has_sale_inventory": price_route_sale_inventory_units > 0,
		"price_route_ready": price_route_ready,
		"stable_income_ready": stable_income_ready,
		"house_growth_space": _has_house_growth_space(observation),
		"house_growth_ready": house_growth_ready,
		"waitress_support_ready": waitress_support_ready,
	}

static func stable_income_ready(observation: ObservationState, income_analysis: Dictionary, profile = null) -> bool:
	return bool(analyze(observation, income_analysis, profile).get("stable_income_ready", false))

static func price_route_ready(observation: ObservationState, income_analysis: Dictionary, profile = null) -> bool:
	return bool(analyze(observation, income_analysis, profile).get("price_route_ready", false))

static func house_growth_ready(observation: ObservationState, income_analysis: Dictionary, profile = null) -> bool:
	return bool(analyze(observation, income_analysis, profile).get("house_growth_ready", false))

static func waitress_support_ready(observation: ObservationState, income_analysis: Dictionary = {}, profile = null) -> bool:
	return bool(analyze(observation, income_analysis, profile).get("waitress_support_ready", false))

static func _salary_cost(observation: ObservationState) -> int:
	if observation == null:
		return 5
	return _read_non_negative_int(observation.rules_public.get("salary_cost", 5), 5)

static func _cash(observation: ObservationState) -> int:
	if observation == null:
		return 0
	return _read_non_negative_int(observation.own_player.get("cash", 0), 0)

static func _own_restaurant_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var restaurants_val = observation.own_player.get("restaurants", [])
	if restaurants_val is Array:
		return Array(restaurants_val).size()
	return 0

static func _owns_role(observation: ObservationState, role: String) -> bool:
	if observation == null or role.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if _employee_role(employee_id) == role:
			return true
	return false

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func _serviceable_inventory_units(income_analysis: Dictionary) -> int:
	var total := 0
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_val in products.values():
		if not (product_val is Dictionary):
			continue
		var product: Dictionary = product_val
		var serviceable := maxi(0, int(product.get("serviceable_demand", 0)))
		var inventory := maxi(0, int(product.get("inventory_units", 0)))
		total += mini(serviceable, inventory)
	return total

static func _actionable_inventory_units(income_analysis: Dictionary) -> int:
	var total := 0
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_val in products.values():
		if not (product_val is Dictionary):
			continue
		var product: Dictionary = product_val
		var serviceable := maxi(0, int(product.get("serviceable_demand", 0)))
		var actionable := maxi(0, int(product.get("actionable_demand", serviceable)))
		var inventory := maxi(0, int(product.get("inventory_units", 0)))
		total += mini(actionable, inventory)
	return total

static func _price_recoverable_inventory_units(income_analysis: Dictionary) -> int:
	var total := 0
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_val in products.values():
		if not (product_val is Dictionary):
			continue
		var product: Dictionary = product_val
		var serviceable := maxi(0, int(product.get("serviceable_demand", 0)))
		var actionable := maxi(0, int(product.get("actionable_demand", serviceable)))
		var recoverable := maxi(0, int(product.get("price_recoverable_demand", 0)))
		if recoverable <= 0:
			continue
		var inventory := maxi(0, int(product.get("inventory_units", 0)))
		var current_sale_inventory := mini(actionable, inventory)
		var lowered_price_sale_inventory := mini(actionable + recoverable, inventory)
		total += maxi(0, lowered_price_sale_inventory - current_sale_inventory)
	return total

static func _actionable_demand_supply_readiness(income_analysis: Dictionary, owns_food_supply: bool, owns_drink_supply: bool) -> Dictionary:
	var ready := 0
	var blocked := 0
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_key in products.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var product_val = products.get(product_key, {})
		if not (product_val is Dictionary):
			continue
		var product: Dictionary = product_val
		var serviceable := maxi(0, int(product.get("serviceable_demand", 0)))
		var actionable := maxi(0, int(product.get("actionable_demand", serviceable)))
		if actionable <= 0:
			continue
		var inventory := maxi(0, int(product.get("inventory_units", 0)))
		var inventory_ready := mini(actionable, inventory)
		var supply_gap := maxi(0, actionable - inventory_ready)
		ready += inventory_ready
		if supply_gap <= 0:
			continue
		if _has_supply_for_product(product_id, owns_food_supply, owns_drink_supply):
			ready += supply_gap
		else:
			blocked += supply_gap
	return {
		"ready_actionable_demand": ready,
		"blocked_actionable_demand": blocked,
	}

static func _price_recoverable_demand_supply_readiness(income_analysis: Dictionary, owns_food_supply: bool, owns_drink_supply: bool) -> Dictionary:
	var ready := 0
	var blocked := 0
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_key in products.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var product_val = products.get(product_key, {})
		if not (product_val is Dictionary):
			continue
		var product: Dictionary = product_val
		var recoverable := maxi(0, int(product.get("price_recoverable_demand", 0)))
		if recoverable <= 0:
			continue
		var serviceable := maxi(0, int(product.get("serviceable_demand", 0)))
		var actionable := maxi(0, int(product.get("actionable_demand", serviceable)))
		var inventory := maxi(0, int(product.get("inventory_units", 0)))
		var current_sale_inventory := mini(actionable, inventory)
		var lowered_price_sale_inventory := mini(actionable + recoverable, inventory)
		var inventory_ready := maxi(0, lowered_price_sale_inventory - current_sale_inventory)
		var supply_gap := maxi(0, recoverable - inventory_ready)
		ready += inventory_ready
		if supply_gap <= 0:
			continue
		if _has_supply_for_product(product_id, owns_food_supply, owns_drink_supply):
			ready += supply_gap
		else:
			blocked += supply_gap
	return {
		"ready_recoverable_demand": ready,
		"blocked_recoverable_demand": blocked,
	}

static func _has_supply_for_product(product_id: String, owns_food_supply: bool, owns_drink_supply: bool) -> bool:
	if product_id.is_empty():
		return false
	return owns_drink_supply if _is_drink_product(product_id) else owns_food_supply

static func _is_drink_product(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		var def_val = ProductRegistryClass.get_def(product_id)
		if def_val is ProductDef:
			return (def_val as ProductDef).is_drink()
	return ["beer", "soda", "lemonade", "coffee"].has(product_id)

static func _owned_employee_ids(player: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var employees_val = player.get(key, [])
		if not (employees_val is Array):
			continue
		for employee_val in Array(employees_val):
			var employee_id := str(employee_val)
			if not employee_id.is_empty() and not out.has(employee_id):
				out.append(employee_id)
	out.sort()
	return out

static func _own_milestones(observation: ObservationState) -> Array[String]:
	var out: Array[String] = []
	if observation == null:
		return out
	var milestones_val = observation.own_player.get("milestones", [])
	if not (milestones_val is Array):
		return out
	for milestone_val in Array(milestones_val):
		var milestone_id := str(milestone_val)
		if not milestone_id.is_empty() and not out.has(milestone_id):
			out.append(milestone_id)
	out.sort()
	return out

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

static func _read_non_negative_int(value, fallback: int) -> int:
	var out := fallback
	if value is int:
		out = int(value)
	elif value is float:
		out = int(value)
	elif value is String and str(value).is_valid_int():
		out = int(str(value))
	return maxi(0, out)
