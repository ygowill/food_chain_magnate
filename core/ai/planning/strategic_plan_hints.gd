class_name StrategyPlanHints
extends RefCounted

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

static func create(
	p_plan_id: String = "",
	p_preferred_products: Array[String] = [],
	p_preferred_employee_roles: Array[String] = [],
	p_preferred_employee_ids: Array[String] = [],
	p_preferred_marketing_house_ids: Array[String] = [],
	p_preferred_marketing_board_numbers: Array[int] = [],
	p_preferred_price_actions: Array[String] = [],
	p_growth_bias: float = 0.0,
	p_cash_floor: int = 0,
	p_avoid_actions: Array[String] = [],
	p_preferred_actions: Array[String] = [],
	p_execution_sequence: Array[String] = []
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
	return hints

static func from_plan(plan):
	if plan == null:
		return load("res://core/ai/planning/strategic_plan_hints.gd").create()
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
			roles.append("produce_food")
			roles.append("procure_drink")
			employees.append_array(plan.target_employees)
			actions.append("initiate_marketing")
			actions.append("produce_food")
			actions.append("procure_drinks")
			actions.append("recruit")
			actions.append("train")
			avoid.append("fire")
		"supply_capacity":
			roles.append("produce_food")
			roles.append("procure_drink")
			roles.append("recruit_train")
			employees.append_array(plan.target_employees)
			actions.append("recruit")
			actions.append("train")
			actions.append("produce_food")
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
		sequence
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
		_ordered_string_array(data.get("execution_sequence", []))
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
		and execution_sequence.is_empty()

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
