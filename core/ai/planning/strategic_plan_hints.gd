class_name StrategyPlanHints
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")

var preferred_products: Array[String] = []
var preferred_employee_roles: Array[String] = []
var preferred_employee_ids: Array[String] = []
var preferred_marketing_house_ids: Array[String] = []
var preferred_marketing_board_numbers: Array[int] = []
var preferred_price_actions: Array[String] = []
var growth_bias: float = 0.0
var cash_floor: int = 0
var avoid_actions: Array[String] = []
var preferred_actions: Array[String] = []
var execution_sequence: Array[String] = []
var plan_id: String = ""
var next_action_ids: Array[String] = []
var next_target_products: Array[String] = []
var next_target_employees: Array[String] = []
var directive_phase: String = ""
var route_target_products: Array[String] = []
var route_target_employees: Array[String] = []
var route_preferred_actions: Array[String] = []

static func create(
	p_plan_id: String = "",
	p_preferred_products = [],
	p_preferred_employee_roles = [],
	p_preferred_employee_ids = [],
	p_preferred_marketing_house_ids = [],
	p_preferred_marketing_board_numbers = [],
	p_preferred_price_actions = [],
	p_growth_bias: float = 0.0,
	p_cash_floor: int = 0,
	p_avoid_actions = [],
	p_preferred_actions = [],
	p_execution_sequence = [],
	p_next_action_ids = [],
	p_next_target_products = [],
	p_next_target_employees = [],
	p_directive_phase: String = "",
	p_route_target_products = [],
	p_route_target_employees = [],
	p_route_preferred_actions = []
):
	var script := load("res://core/ai/planning/strategic_plan_hints.gd")
	var hints = script.new()
	hints.plan_id = str(p_plan_id).strip_edges()
	hints.preferred_products = _string_array(p_preferred_products)
	hints.preferred_employee_roles = _string_array(p_preferred_employee_roles)
	hints.preferred_employee_ids = _string_array(p_preferred_employee_ids)
	hints.preferred_marketing_house_ids = _string_array(p_preferred_marketing_house_ids)
	hints.preferred_marketing_board_numbers = _int_array(p_preferred_marketing_board_numbers)
	hints.preferred_price_actions = _string_array(p_preferred_price_actions)
	hints.growth_bias = float(p_growth_bias)
	hints.cash_floor = maxi(0, int(p_cash_floor))
	hints.avoid_actions = _string_array(p_avoid_actions)
	hints.preferred_actions = _string_array(p_preferred_actions)
	hints.execution_sequence = _ordered_string_array(p_execution_sequence)
	hints.next_action_ids = _ordered_string_array(p_next_action_ids)
	hints.next_target_products = _string_array(p_next_target_products)
	hints.next_target_employees = _string_array(p_next_target_employees)
	hints.directive_phase = str(p_directive_phase).strip_edges()
	hints.route_target_products = _string_array(p_route_target_products)
	hints.route_target_employees = _string_array(p_route_target_employees)
	hints.route_preferred_actions = _ordered_string_array(p_route_preferred_actions)
	return hints

static func from_plan(plan):
	if plan == null:
		return load("res://core/ai/planning/strategic_plan_hints.gd").create()
	var target_products := _string_array(plan.target_products)
	var include_food := _target_products_include_food(target_products)
	var include_drink := _target_products_include_drink(target_products)
	var roles: Array[String] = []
	var employees: Array[String] = []
	var price_actions: Array[String] = []
	var actions: Array[String] = []
	var growth := 0.0
	var avoid: Array[String] = []
	var sequence := _ordered_string_array(plan.execution_sequence if plan.get("execution_sequence") != null else [])
	actions.append_array(sequence)
	match str(plan.route_type):
		"marketing_income", "product_switch_attack":
			roles.append("marketing")
			if include_food:
				roles.append("produce_food")
			if include_drink:
				roles.append("procure_drink")
			employees.append_array(plan.target_employees)
			actions.append("initiate_marketing")
			if include_food:
				actions.append("produce_food")
			if include_drink:
				actions.append("procure_drinks")
			actions.append("recruit")
			actions.append("train")
			avoid.append("fire")
		"supply_capacity":
			if include_food:
				roles.append("produce_food")
			if include_drink:
				roles.append("procure_drink")
			roles.append("recruit_train")
			employees.append_array(plan.target_employees)
			actions.append("recruit")
			actions.append("train")
			if include_food:
				actions.append("produce_food")
			if include_drink:
				actions.append("procure_drinks")
		"price_recovery":
			roles.append("price")
			employees.append("pricing_manager")
			price_actions.append("set_price")
			price_actions.append("set_discount")
			price_actions.append("set_luxury_price")
			actions.append("set_price")
			actions.append("set_discount")
			actions.append("set_luxury_price")
			if include_food:
				roles.append("produce_food")
				actions.append("produce_food")
			if include_drink:
				roles.append("procure_drink")
				actions.append("procure_drinks")
			actions.append("recruit")
			actions.append("train")
		"growth":
			roles.append("new_shop")
			employees.append("new_business_developer")
			growth = 1.0
			actions.append("place_house")
			actions.append("add_garden")
			actions.append("place_restaurant")
			actions.append("move_restaurant")
			actions.append("recruit")
			actions.append("train")
	var cash_floor := int(plan.constraints.get("cash_floor", 0))
	return load("res://core/ai/planning/strategic_plan_hints.gd").create(
		plan.id,
		plan.target_products,
		roles,
		employees,
		plan.target_houses,
		_int_array(plan.constraints.get("preferred_marketing_board_numbers", [])),
		price_actions,
		growth,
		cash_floor,
		avoid,
		actions,
		sequence,
		[],
		[],
		[],
		"",
		plan.target_products,
		plan.target_employees,
		actions
	)

static func from_plan_for_decision(plan, observation: ObservationState = null, legal_action_ids: Array[String] = []):
	if plan == null:
		return load("res://core/ai/planning/strategic_plan_hints.gd").create()
	var route_hints = from_plan(plan)
	var legal_ids := _string_array(legal_action_ids)
	if legal_ids.is_empty():
		return route_hints
	var next_actions := _next_actions_for_legal(route_hints.execution_sequence, route_hints.preferred_actions, legal_ids)
	if next_actions.is_empty():
		return load("res://core/ai/planning/strategic_plan_hints.gd").create(
			plan.id,
			[],
			[],
			[],
			[],
			[],
			[],
			0.0,
			int(route_hints.cash_floor),
			route_hints.avoid_actions,
			[],
			[],
			[],
			[],
			[],
			_directive_phase(observation),
			plan.target_products,
			plan.target_employees,
			route_hints.preferred_actions
		)
	var next_roles := _next_roles_for_actions(next_actions, route_hints.preferred_employee_roles)
	var next_products := _next_products_for_actions(next_actions, plan.target_products)
	var next_employees := _next_employees_for_actions(next_actions, plan.target_employees, next_roles)
	var next_houses: Array[String] = []
	var next_boards: Array[int] = []
	if next_actions.has("initiate_marketing"):
		next_houses = route_hints.preferred_marketing_house_ids.duplicate()
		next_boards = route_hints.preferred_marketing_board_numbers.duplicate()
	var next_price_actions := _next_price_actions_for_actions(next_actions, route_hints.preferred_price_actions)
	var next_growth: float = route_hints.growth_bias if _has_growth_action(next_actions) else 0.0
	return load("res://core/ai/planning/strategic_plan_hints.gd").create(
		plan.id,
		next_products,
		next_roles,
		next_employees,
		next_houses,
		next_boards,
		next_price_actions,
		next_growth,
		int(route_hints.cash_floor),
		route_hints.avoid_actions,
		next_actions,
		next_actions,
		next_actions,
		next_products,
		next_employees,
		_directive_phase(observation),
		plan.target_products,
		plan.target_employees,
		route_hints.preferred_actions
	)

static func from_dict(data: Dictionary):
	return load("res://core/ai/planning/strategic_plan_hints.gd").create(
		str(data.get("plan_id", "")),
		_string_array(data.get("preferred_products", [])),
		_string_array(data.get("preferred_employee_roles", [])),
		_string_array(data.get("preferred_employee_ids", [])),
		_string_array(data.get("preferred_marketing_house_ids", [])),
		_int_array(data.get("preferred_marketing_board_numbers", [])),
		_string_array(data.get("preferred_price_actions", [])),
		float(data.get("growth_bias", 0.0)),
		int(data.get("cash_floor", 0)),
		_string_array(data.get("avoid_actions", [])),
		_string_array(data.get("preferred_actions", [])),
		_ordered_string_array(data.get("execution_sequence", [])),
		_ordered_string_array(data.get("next_action_ids", [])),
		_string_array(data.get("next_target_products", [])),
		_string_array(data.get("next_target_employees", [])),
		str(data.get("directive_phase", "")),
		_string_array(data.get("route_target_products", [])),
		_string_array(data.get("route_target_employees", [])),
		_ordered_string_array(data.get("route_preferred_actions", []))
	)

func duplicate_hints():
	return get_script().from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"preferred_products": preferred_products.duplicate(),
		"preferred_employee_roles": preferred_employee_roles.duplicate(),
		"preferred_employee_ids": preferred_employee_ids.duplicate(),
		"preferred_marketing_house_ids": preferred_marketing_house_ids.duplicate(),
		"preferred_marketing_board_numbers": preferred_marketing_board_numbers.duplicate(),
		"preferred_price_actions": preferred_price_actions.duplicate(),
		"growth_bias": growth_bias,
		"cash_floor": cash_floor,
		"avoid_actions": avoid_actions.duplicate(),
		"preferred_actions": preferred_actions.duplicate(),
		"execution_sequence": execution_sequence.duplicate(),
		"plan_id": plan_id,
		"next_action_ids": next_action_ids.duplicate(),
		"next_target_products": next_target_products.duplicate(),
		"next_target_employees": next_target_employees.duplicate(),
		"directive_phase": directive_phase,
		"route_target_products": route_target_products.duplicate(),
		"route_target_employees": route_target_employees.duplicate(),
		"route_preferred_actions": route_preferred_actions.duplicate(),
	}

func is_empty() -> bool:
	return plan_id.is_empty() \
		and preferred_products.is_empty() \
		and preferred_employee_roles.is_empty() \
		and preferred_employee_ids.is_empty() \
		and preferred_marketing_house_ids.is_empty() \
		and preferred_marketing_board_numbers.is_empty() \
		and preferred_price_actions.is_empty() \
		and is_equal_approx(growth_bias, 0.0) \
		and cash_floor <= 0 \
		and avoid_actions.is_empty() \
		and preferred_actions.is_empty() \
		and execution_sequence.is_empty() \
		and next_action_ids.is_empty() \
		and next_target_products.is_empty() \
		and next_target_employees.is_empty() \
		and directive_phase.is_empty()

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out

static func _int_array(value) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for item in Array(value):
			if item is int or item is float:
				var n := int(item)
				if not out.has(n):
					out.append(n)
	out.sort()
	return out

static func _ordered_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	return out

static func _next_actions_for_legal(sequence: Array[String], preferred_actions: Array[String], legal_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for action_id in sequence:
		if legal_ids.has(action_id):
			out.append(action_id)
			return out
	for action_id in preferred_actions:
		if legal_ids.has(action_id):
			out.append(action_id)
			return out
	return out

static func _next_products_for_actions(action_ids: Array[String], target_products: Array[String]) -> Array[String]:
	for action_id in action_ids:
		if action_id == "initiate_marketing" or action_id == "produce_food" or action_id == "procure_drinks" or action_id == "set_price" or action_id == "set_discount" or action_id == "set_luxury_price":
			return target_products.duplicate()
	return []

static func _next_employees_for_actions(
	action_ids: Array[String],
	target_employees: Array[String],
	preferred_roles: Array[String]
) -> Array[String]:
	for action_id in action_ids:
		if action_id == "recruit" or action_id == "train" or action_id == "restructure_employee" or action_id == "set_company_structure_direct" or action_id == "initiate_marketing":
			return _employees_matching_roles(target_employees, preferred_roles)
		if action_id == "produce_food" or action_id == "procure_drinks" or action_id == "set_price" or action_id == "set_discount" or action_id == "set_luxury_price" or action_id == "place_house" or action_id == "add_garden" or action_id == "place_restaurant" or action_id == "move_restaurant":
			return _employees_matching_roles(target_employees, preferred_roles)
	return []

static func _employees_matching_roles(employee_ids: Array[String], preferred_roles: Array[String]) -> Array[String]:
	if preferred_roles.is_empty():
		return employee_ids.duplicate()
	var out: Array[String] = []
	for employee_id in employee_ids:
		var role := _employee_role(employee_id)
		if role.is_empty() or preferred_roles.has(role):
			out.append(employee_id)
	return _string_array(out)

static func _employee_role(employee_id: String) -> String:
	var id := str(employee_id).strip_edges()
	if id.is_empty():
		return ""
	if EmployeeRegistryClass.is_loaded() and EmployeeRegistryClass.has(id):
		var def_val = EmployeeRegistryClass.get_def(id)
		if def_val is EmployeeDefClass:
			return str((def_val as EmployeeDefClass).role)
	if id.find("campaign") >= 0 or id.find("marketing") >= 0 or id.find("brand") >= 0:
		return "marketing"
	if id.find("cook") >= 0 or id.find("chef") >= 0 or id.find("kitchen") >= 0:
		return "produce_food"
	if id.find("errand") >= 0 or id.find("cart") >= 0 or id.find("truck") >= 0 or id.find("zeppelin") >= 0:
		return "procure_drink"
	if id.find("price") >= 0 or id.find("pricing") >= 0 or id.find("discount") >= 0:
		return "price"
	if id.find("new_business") >= 0 or id.find("developer") >= 0 or id.find("regional") >= 0:
		return "new_shop"
	return ""

static func _next_roles_for_actions(action_ids: Array[String], preferred_roles: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for action_id in action_ids:
		match action_id:
			"initiate_marketing":
				if preferred_roles.has("marketing"):
					out.append("marketing")
			"produce_food":
				if preferred_roles.has("produce_food"):
					out.append("produce_food")
			"procure_drinks":
				if preferred_roles.has("procure_drink"):
					out.append("procure_drink")
			"set_price", "set_discount", "set_luxury_price":
				if preferred_roles.has("price"):
					out.append("price")
			"place_house", "add_garden", "place_restaurant", "move_restaurant":
				if preferred_roles.has("new_shop"):
					out.append("new_shop")
			_:
				for role in preferred_roles:
					if not out.has(role):
						out.append(role)
	return out

static func _next_price_actions_for_actions(action_ids: Array[String], preferred_price_actions: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for action_id in action_ids:
		if preferred_price_actions.has(action_id):
			out.append(action_id)
	return out

static func _has_growth_action(action_ids: Array[String]) -> bool:
	for action_id in action_ids:
		if action_id == "place_house" or action_id == "add_garden" or action_id == "place_restaurant" or action_id == "move_restaurant":
			return true
	return false

static func _directive_phase(observation: ObservationState) -> String:
	if observation == null:
		return ""
	var phase := str(observation.phase).strip_edges()
	var sub_phase := str(observation.sub_phase).strip_edges()
	if sub_phase.is_empty():
		return phase
	return "%s/%s" % [phase, sub_phase]

static func _target_products_include_food(product_ids: Array[String]) -> bool:
	for product_id in product_ids:
		if not _is_drink(product_id):
			return true
	return false

static func _target_products_include_drink(product_ids: Array[String]) -> bool:
	for product_id in product_ids:
		if _is_drink(product_id):
			return true
	return false

static func _is_drink(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		return ProductRegistryClass.is_drink(product_id)
	return product_id == "beer" or product_id == "soda" or product_id == "lemonade"
