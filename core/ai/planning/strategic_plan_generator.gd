class_name StrategicPlanGenerator
extends RefCounted

const StrategicPlanClass = preload("res://core/ai/planning/strategic_plan.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyRecoveryPlannerClass = preload("res://core/ai/strategy/strategy_recovery_planner.gd")
const StrategyRoutePlannerClass = preload("res://core/ai/strategy/strategy_route_planner.gd")
const MarketingPressureAnalyzerClass = preload("res://core/ai/analysis/marketing_pressure_analyzer.gd")
const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

const DEFAULT_MAX_PLANS := 6
const DEFAULT_HORIZON_ROUNDS := 2
const DEFAULT_HORIZON_DECISIONS := 16

static func generate(
	observation: ObservationState,
	profile = null,
	options: Dictionary = {}
) -> Result:
	if observation == null:
		return Result.failure("StrategicPlanGenerator.generate: observation is null")
	var max_plans := maxi(0, int(options.get("max_plans", DEFAULT_MAX_PLANS)))
	if max_plans <= 0:
		return Result.success([])
	var source_state = options.get("source_state", null)
	var source_analysis := _source_analysis(source_state, options)
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile, source_state, source_analysis)
	var plans: Array = []
	_append_marketing_income_plans(plans, observation, profile, income_analysis, options)
	_append_price_recovery_plans(plans, observation, profile, income_analysis, options)
	_append_supply_capacity_plans(plans, observation, profile, income_analysis, options)
	_append_product_switch_attack_plans(plans, observation, profile, income_analysis, source_state, source_analysis, options)
	_append_growth_plan(plans, observation, profile, income_analysis, options)
	_sort_plans(plans)
	var deduped := _dedupe_plans(plans)
	return Result.success(deduped.slice(0, mini(max_plans, deduped.size())))

static func _append_marketing_income_plans(
	plans: Array,
	observation: ObservationState,
	profile,
	income_analysis: Dictionary,
	options: Dictionary
) -> void:
	if _own_restaurant_count(observation) <= 0:
		return
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_key in products.keys():
		var product_id := str(product_key)
		if product_id.is_empty() or not _is_marketable_product(product_id):
			continue
		var product: Dictionary = Dictionary(products.get(product_key, {}))
		var inventory := int(product.get("inventory_units", 0))
		var actionable := int(product.get("actionable_demand", product.get("competitive_demand", product.get("serviceable_demand", 0))))
		var pending := int(product.get("pending_marketing_demand", 0))
		var planning_gap := int(product.get("planning_actionable_inventory_gap", product.get("planning_inventory_gap", 0)))
		var can_supply := bool(product.get("can_supply", false))
		if actionable <= 0 and pending <= 0 and inventory <= 0 and not can_supply:
			continue
		var target_houses := _houses_with_product_demand(observation, product_id, true)
		var prior := float(actionable) * 12.0 + float(pending) * 5.0 + float(mini(inventory, maxi(1, actionable))) * 3.0 + _profile_product_priority(profile, product_id)
		if can_supply:
			prior += 5.0
		if planning_gap > 0:
			prior += float(planning_gap) * 4.0
		var target_employees := _target_employees_for_product(product_id, true)
		plans.append(_make_plan(
			"marketing_income_%s" % product_id,
			observation,
			"marketing_income",
			prior,
			[product_id],
			target_houses,
			target_employees,
			{"cash_floor": _cash_floor(observation, options)},
			["marketing", "income"]
		))

static func _append_price_recovery_plans(
	plans: Array,
	observation: ObservationState,
	profile,
	income_analysis: Dictionary,
	options: Dictionary
) -> void:
	var recovery := StrategyRecoveryPlannerClass.analyze(income_analysis)
	if int(recovery.get("price_recoverable_demand", 0)) <= 0:
		return
	var products: Dictionary = Dictionary(recovery.get("products", {}))
	for product_key in products.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var product: Dictionary = Dictionary(products.get(product_key, {}))
		var recoverable := int(product.get("price_recoverable_demand", 0))
		if recoverable <= 0:
			continue
		var prior := float(recoverable) * 18.0 + _profile_product_priority(profile, product_id)
		var target_houses := _houses_with_product_demand(observation, product_id, true)
		plans.append(_make_plan(
			"price_recovery_%s" % product_id,
			observation,
			"price_recovery",
			prior,
			[product_id],
			target_houses,
			["pricing_manager"],
			{"cash_floor": _cash_floor(observation, options)},
			["price", "recovery"]
		))

static func _append_supply_capacity_plans(
	plans: Array,
	observation: ObservationState,
	profile,
	income_analysis: Dictionary,
	options: Dictionary
) -> void:
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_key in products.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var product: Dictionary = Dictionary(products.get(product_key, {}))
		var planning_gap := int(product.get("planning_actionable_inventory_gap", product.get("planning_inventory_gap", 0)))
		var actionable_gap := int(product.get("actionable_inventory_gap", product.get("inventory_gap", 0)))
		var can_supply := bool(product.get("can_supply", false))
		if planning_gap <= 0 and actionable_gap <= 0:
			continue
		if can_supply and actionable_gap <= 1 and planning_gap <= 1:
			continue
		var target_employees := _target_employees_for_product(product_id, false)
		if target_employees.is_empty():
			continue
		var prior := float(maxi(planning_gap, actionable_gap)) * 14.0 + _profile_product_priority(profile, product_id)
		if _has_train_provider(observation):
			prior += 5.0
		if _has_trainable_for_targets(observation, target_employees):
			prior += 4.0
		var target_houses := _houses_with_product_demand(observation, product_id, true)
		plans.append(_make_plan(
			"train_supply_%s" % product_id,
			observation,
			"supply_capacity",
			prior,
			[product_id],
			target_houses,
			target_employees,
			{"cash_floor": _cash_floor(observation, options)},
			["supply", "training"]
		))

static func _append_product_switch_attack_plans(
	plans: Array,
	observation: ObservationState,
	profile,
	income_analysis: Dictionary,
	source_state,
	source_analysis: Dictionary,
	options: Dictionary
) -> void:
	if not (source_state is GameState):
		return
	var products := _known_product_ids(observation, profile, income_analysis)
	for product_id in products:
		if product_id.is_empty() or not _is_marketable_product(product_id):
			continue
		var pressure := MarketingPressureAnalyzerClass.product_pressure_prior(source_state, observation, product_id, source_analysis)
		if pressure <= 0:
			continue
		var product: Dictionary = Dictionary(Dictionary(income_analysis.get("products", {})).get(product_id, {}))
		var can_supply := bool(product.get("can_supply", false)) or int(product.get("inventory_units", 0)) > 0
		if not can_supply:
			continue
		var prior := float(pressure) * 16.0 + _profile_product_priority(profile, product_id)
		plans.append(_make_plan(
			"product_switch_attack_%s" % product_id,
			observation,
			"product_switch_attack",
			prior,
			[product_id],
			[],
			_target_employees_for_product(product_id, true),
			{"cash_floor": _cash_floor(observation, options)},
			["marketing", "attack"]
		))

static func _append_growth_plan(
	plans: Array,
	observation: ObservationState,
	profile,
	income_analysis: Dictionary,
	options: Dictionary
) -> void:
	if not _owns_employee(observation, "new_business_developer") and int(observation.employee_pool_public.get("new_business_developer", 0)) <= 0:
		return
	var own_restaurants := _own_restaurant_count(observation)
	if own_restaurants <= 0:
		return
	var public_demand := int(income_analysis.get("total_public_demand", 0))
	var serviceable := int(income_analysis.get("total_serviceable_demand", 0))
	var unserviceable := maxi(0, public_demand - serviceable)
	var house_supply := _remaining_house_supply(observation)
	var route_plan := StrategyRoutePlannerClass.analyze(observation, income_analysis, profile)
	if not _growth_route_is_grounded(observation, route_plan, unserviceable, house_supply):
		return
	var prior := float(unserviceable) * 10.0 + float(house_supply) * 2.0 + _profile_employee_priority(profile, "new_business_developer")
	plans.append(_make_plan(
		"opening_growth_restaurant",
		observation,
		"growth",
		prior,
		[],
		[],
		["new_business_developer"],
		{"cash_floor": _cash_floor(observation, options)},
		["growth"]
	))

static func _make_plan(
	plan_id: String,
	observation: ObservationState,
	route_type: String,
	prior_score: float,
	target_products: Array[String],
	target_houses: Array[String],
	target_employees: Array[String],
	constraints: Dictionary,
	tags: Array[String]
):
	var horizon := _route_horizon(route_type)
	var execution_sequence := _route_execution_sequence(route_type, observation, target_products)
	return StrategicPlanClass.create(
		plan_id,
		int(observation.viewer_player_id),
		route_type,
		prior_score,
		target_products,
		target_houses,
		target_employees,
		constraints,
		tags,
		int(horizon.get("rounds", DEFAULT_HORIZON_ROUNDS)),
		int(horizon.get("decisions", DEFAULT_HORIZON_DECISIONS)),
		execution_sequence
	)

static func _route_horizon(route_type: String) -> Dictionary:
	match str(route_type):
		"price_recovery":
			return {"rounds": 1, "decisions": 12}
		"supply_capacity":
			return {"rounds": 2, "decisions": 18}
		"growth":
			return {"rounds": 3, "decisions": 24}
	return {"rounds": DEFAULT_HORIZON_ROUNDS, "decisions": DEFAULT_HORIZON_DECISIONS}

static func _route_execution_sequence(route_type: String, observation: ObservationState, target_products: Array[String]) -> Array[String]:
	var sequence: Array[String] = []
	match str(route_type):
		"marketing_income", "product_switch_attack":
			if not _owns_role(observation, "marketing"):
				sequence.append("recruit")
				sequence.append("train")
			sequence.append("initiate_marketing")
			if _target_products_include_food(target_products):
				sequence.append("produce_food")
			if _target_products_include_drink(target_products):
				sequence.append("procure_drinks")
		"price_recovery":
			if not _owns_role(observation, "price"):
				sequence.append("recruit")
				sequence.append("train")
			sequence.append("set_price")
			sequence.append("set_discount")
			sequence.append("set_luxury_price")
			if _target_products_include_food(target_products):
				sequence.append("produce_food")
			if _target_products_include_drink(target_products):
				sequence.append("procure_drinks")
		"supply_capacity":
			if _has_train_provider(observation) or _has_trainable_for_targets(observation, _target_employees_for_products(target_products)):
				sequence.append("train")
			else:
				sequence.append("recruit")
				sequence.append("train")
			if _target_products_include_food(target_products):
				sequence.append("produce_food")
			if _target_products_include_drink(target_products):
				sequence.append("procure_drinks")
		"growth":
			if not _owns_role(observation, "new_shop"):
				sequence.append("recruit")
				sequence.append("train")
			sequence.append("place_house")
			sequence.append("add_garden")
			sequence.append("place_restaurant")
			sequence.append("move_restaurant")
	return _ordered_unique_strings(sequence)

static func _sort_plans(plans: Array) -> void:
	plans.sort_custom(func(a, b) -> bool:
		if not is_equal_approx(a.prior_score, b.prior_score):
			return a.prior_score > b.prior_score
		return a.id < b.id
	)

static func _dedupe_plans(plans: Array) -> Array:
	var out: Array = []
	var seen := {}
	for plan in plans:
		if plan == null or not plan.is_valid():
			continue
		if seen.has(plan.id):
			continue
		seen[plan.id] = true
		out.append(plan)
	return out

static func _source_analysis(source_state, options: Dictionary) -> Dictionary:
	var provided = options.get("source_analysis", {})
	if provided is Dictionary and not Dictionary(provided).is_empty():
		return Dictionary(provided)
	if not (source_state is GameState):
		return {}
	var read := BoardAnalyzerClass.analyze_state(source_state)
	if not read.ok or not (read.value is Dictionary):
		return {}
	return Dictionary(read.value)

static func _cash_floor(observation: ObservationState, options: Dictionary) -> int:
	if options.has("cash_floor"):
		return maxi(0, int(options.get("cash_floor", 0)))
	var cash := int(observation.own_player.get("cash", 0)) if observation != null else 0
	return mini(10, maxi(0, cash))

static func _known_product_ids(observation: ObservationState, profile, income_analysis: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var products_val = income_analysis.get("products", {})
	if products_val is Dictionary:
		for product_key in Dictionary(products_val).keys():
			_append_unique(out, str(product_key))
	if profile != null and profile.product_priorities is Dictionary:
		for key in Dictionary(profile.product_priorities).keys():
			_append_unique(out, str(key))
	if observation != null:
		var inventory_val = observation.own_player.get("inventory", {})
		if inventory_val is Dictionary:
			for key2 in Dictionary(inventory_val).keys():
				_append_unique(out, str(key2))
	out.sort()
	return out

static func _target_employees_for_product(product_id: String, include_marketing: bool) -> Array[String]:
	var out: Array[String] = []
	if include_marketing:
		out.append("campaign_manager")
	if product_id == "burger":
		out.append("burger_cook")
		out.append("burger_chef")
		out.append("kitchen_trainee")
	elif product_id == "pizza":
		out.append("pizza_cook")
		out.append("pizza_chef")
		out.append("kitchen_trainee")
	elif _is_drink(product_id):
		out.append("errand_boy")
		out.append("cart_operator")
		out.append("truck_driver")
		out.append("zeppelin_pilot")
	return _sorted_unique_strings(out)

static func _target_employees_for_products(product_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for product_id in product_ids:
		for employee_id in _target_employees_for_product(product_id, true):
			_append_unique(out, employee_id)
	return out

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

static func _houses_with_product_demand(observation: ObservationState, product_id: String, serviceable_only: bool) -> Array[String]:
	var out: Array[String] = []
	if observation == null or product_id.is_empty():
		return out
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return out
	for house_id_val in Dictionary(houses_val).keys():
		var house_id := str(house_id_val)
		var house_val = Dictionary(houses_val).get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		if serviceable_only and _min_house_distance_to_owned_restaurant(observation, house_id) < 0:
			continue
		var demands_val = Dictionary(house_val).get("demands", [])
		if not (demands_val is Array):
			continue
		for demand_val in Array(demands_val):
			if demand_val is Dictionary and str(Dictionary(demand_val).get("product", "")) == product_id:
				_append_unique(out, house_id)
	out.sort()
	return out

static func _own_restaurant_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var restaurants_val = observation.own_player.get("restaurants", [])
	return Array(restaurants_val).size() if restaurants_val is Array else 0

static func _owns_role(observation: ObservationState, role: String) -> bool:
	if observation == null or role.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation):
		if employee_id.is_empty() or not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and str((def_val as EmployeeDef).role) == role:
			return true
	return false

static func _owns_employee(observation: ObservationState, employee_id: String) -> bool:
	if observation == null or employee_id.is_empty():
		return false
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var employees_val = observation.own_player.get(key, [])
		if employees_val is Array and Array(employees_val).has(employee_id):
			return true
	return false

static func _has_train_provider(observation: ObservationState) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and int((def_val as EmployeeDef).train_capacity) > 0:
			return true
	return false

static func _has_trainable_for_targets(observation: ObservationState, target_employees: Array[String]) -> bool:
	if observation == null or target_employees.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		for target in (def_val as EmployeeDef).train_to:
			if target_employees.has(str(target)):
				return true
	return false

static func _owned_employee_ids(observation: ObservationState) -> Array[String]:
	var out: Array[String] = []
	if observation == null:
		return out
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var employees_val = observation.own_player.get(key, [])
		if not (employees_val is Array):
			continue
		for employee_val in Array(employees_val):
			_append_unique(out, str(employee_val))
	out.sort()
	return out

static func _remaining_house_supply(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var value = observation.map_public.get("house_number_supply_remaining", [])
	if not (value is Array):
		return 0
	return Array(value).size()

static func _growth_route_is_grounded(
	observation: ObservationState,
	route_plan: Dictionary,
	unserviceable_demand: int,
	house_supply: int
) -> bool:
	if observation == null:
		return false
	var stable_income_ready := bool(route_plan.get("stable_income_ready", false))
	var house_growth_ready := bool(route_plan.get("house_growth_ready", false))
	if house_growth_ready:
		return true
	if not stable_income_ready:
		return false
	return unserviceable_demand > 0 and house_supply > 0

static func _is_marketable_product(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if not ProductRegistryClass.is_loaded() or not ProductRegistryClass.has(product_id):
		return true
	var def_val = ProductRegistryClass.get_def(product_id)
	if not (def_val is ProductDef):
		return true
	return not (def_val as ProductDef).has_tag("no_marketing")

static func _is_drink(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		return ProductRegistryClass.is_drink(product_id)
	return product_id == "beer" or product_id == "soda" or product_id == "lemonade"

static func _profile_product_priority(profile, product_id: String) -> float:
	if profile == null:
		return 1.0
	return float(profile.product_priority(product_id))

static func _profile_employee_priority(profile, employee_id: String) -> float:
	if profile == null:
		return 1.0
	return float(profile.employee_priority(employee_id))

static func _min_house_distance_to_owned_restaurant(observation: ObservationState, house_id: String) -> int:
	if observation == null or house_id.is_empty():
		return -1
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return -1
	var house_val = Dictionary(houses_val).get(house_id, null)
	if not (house_val is Dictionary):
		return -1
	var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var best := 2147483647
	for restaurant_id in _sorted_unique_strings(observation.own_player.get("restaurants", [])):
		var rest_val = Dictionary(restaurants_val).get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		var rest_anchor := _read_vector2i(Dictionary(rest_val).get("anchor_pos", Vector2i.ZERO))
		best = mini(best, absi(house_anchor.x - rest_anchor.x) + absi(house_anchor.y - rest_anchor.y))
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
		return Vector2i(int(dict.get("x", 0)), int(dict.get("y", 0)))
	return Vector2i.ZERO

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			_append_unique(out, str(item))
	out.sort()
	return out

static func _ordered_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			_append_unique(out, str(item))
	return out

static func _append_unique(out: Array[String], value: String) -> void:
	var text := str(value).strip_edges()
	if text.is_empty() or out.has(text):
		return
	out.append(text)
