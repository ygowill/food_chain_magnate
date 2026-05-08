class_name StrategyIncomeAnalyzer
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const MarketingPressureAnalyzerClass = preload("res://core/ai/analysis/marketing_pressure_analyzer.gd")

static func analyze(observation: ObservationState, profile, source_state = null, source_analysis: Dictionary = {}) -> Dictionary:
	var products := {}
	var total_public_demand := 0
	var total_serviceable_demand := 0
	var total_actionable_demand := 0
	var total_lost_to_competitor_demand := 0
	var total_price_recoverable_demand := 0
	var total_own_sourced_opponent_blocking_demand := 0
	var total_inventory_gap := 0
	var total_actionable_inventory_gap := 0
	var total_pending_marketing_demand := 0
	var total_pending_defensive_marketing_demand := 0
	var total_planning_inventory_gap := 0
	var total_planning_actionable_inventory_gap := 0
	var pending_marketing_payload := _pending_marketing_demand_payload(observation, source_state, source_analysis)
	var pending_marketing_demand := Dictionary(pending_marketing_payload.get("revenue", {}))
	var pending_defensive_marketing_demand := Dictionary(pending_marketing_payload.get("defensive", {}))
	var product_ids := _known_product_ids(observation, profile, pending_marketing_payload)
	var public_demands := {}
	var has_public_demand := false
	for product_id in product_ids:
		var demand := _public_demand_count_for_product(observation, product_id)
		public_demands[product_id] = demand
		if demand > 0:
			has_public_demand = true
	var demand_pressure := MarketingPressureAnalyzerClass.current_demand_pressure_by_product(source_state, observation, source_analysis) if has_public_demand else {}
	var lower_price_pressure := MarketingPressureAnalyzerClass.current_demand_pressure_by_product(source_state, observation, source_analysis, -1) if has_public_demand and source_state is GameState else {}
	for product_id in product_ids:
		var demand := int(public_demands.get(product_id, 0))
		var serviceable := _serviceable_demand_count_for_product(observation, product_id)
		var pressure_info: Dictionary = Dictionary(demand_pressure.get(product_id, {}))
		if not pressure_info.is_empty():
			serviceable = maxi(0, int(pressure_info.get("serviceable_demand", serviceable)))
		var actionable := maxi(0, int(pressure_info.get("competitive_demand", serviceable)))
		var lost_to_competitor := maxi(0, int(pressure_info.get("lost_to_competitor_demand", 0)))
		var own_sourced_demand := maxi(0, int(pressure_info.get("own_sourced_demand", 0)))
		var own_sourced_opponent_blocking := maxi(0, int(pressure_info.get("own_sourced_opponent_blocking_demand", 0)))
		var lower_price_info: Dictionary = Dictionary(lower_price_pressure.get(product_id, {}))
		var lower_price_actionable := actionable
		var price_recoverable := 0
		if not lower_price_info.is_empty():
			lower_price_actionable = maxi(0, int(lower_price_info.get("competitive_demand", actionable)))
			price_recoverable = mini(lost_to_competitor, maxi(0, lower_price_actionable - actionable))
		var inventory := _inventory_count(observation, product_id)
		var gap := maxi(0, demand - inventory)
		var actionable_gap := maxi(0, actionable - inventory)
		var pending := int(pending_marketing_demand.get(product_id, 0))
		var pending_defensive := int(pending_defensive_marketing_demand.get(product_id, 0))
		var planning_demand := demand + pending
		var planning_actionable_demand := actionable + pending
		var pending_inventory_credit := _pending_marketing_inventory_credit(observation, product_id, demand, inventory, pending)
		var actionable_pending_inventory_credit := _pending_marketing_inventory_credit(observation, product_id, actionable, inventory, pending)
		var planning_gap := gap + maxi(0, pending - pending_inventory_credit)
		var planning_actionable_gap := actionable_gap + maxi(0, pending - actionable_pending_inventory_credit)
		var can_supply := _can_supply_product(observation, product_id)
		var value := _product_value_from_parts(product_id, demand, serviceable, actionable, inventory, gap, actionable_gap, can_supply, profile, pending, planning_gap, planning_actionable_gap, pending_inventory_credit)
		products[product_id] = {
			"public_demand": demand,
			"serviceable_demand": serviceable,
			"competitive_demand": actionable,
			"actionable_demand": actionable,
			"lost_to_competitor_demand": lost_to_competitor,
			"own_sourced_demand": own_sourced_demand,
			"own_sourced_opponent_blocking_demand": own_sourced_opponent_blocking,
			"price_projected_actionable_demand": lower_price_actionable,
			"price_recoverable_demand": price_recoverable,
			"inventory_units": inventory,
			"inventory_gap": gap,
			"actionable_inventory_gap": actionable_gap,
			"pending_marketing_demand": pending,
			"pending_defensive_marketing_demand": pending_defensive,
			"pending_marketing_inventory_credit": pending_inventory_credit,
			"actionable_pending_marketing_inventory_credit": actionable_pending_inventory_credit,
			"planning_demand": planning_demand,
			"planning_actionable_demand": planning_actionable_demand,
			"planning_inventory_gap": planning_gap,
			"planning_actionable_inventory_gap": planning_actionable_gap,
			"can_supply": can_supply,
			"is_drink": _is_drink(product_id),
			"value": value,
		}
		total_public_demand += demand
		total_serviceable_demand += serviceable
		total_actionable_demand += actionable
		total_lost_to_competitor_demand += lost_to_competitor
		total_price_recoverable_demand += price_recoverable
		total_own_sourced_opponent_blocking_demand += own_sourced_opponent_blocking
		total_inventory_gap += gap
		total_actionable_inventory_gap += actionable_gap
		total_pending_marketing_demand += pending
		total_pending_defensive_marketing_demand += pending_defensive
		total_planning_inventory_gap += planning_gap
		total_planning_actionable_inventory_gap += planning_actionable_gap
	return {
		"products": products,
		"total_public_demand": total_public_demand,
		"total_serviceable_demand": total_serviceable_demand,
		"total_actionable_demand": total_actionable_demand,
		"total_lost_to_competitor_demand": total_lost_to_competitor_demand,
		"total_price_recoverable_demand": total_price_recoverable_demand,
		"total_own_sourced_opponent_blocking_demand": total_own_sourced_opponent_blocking_demand,
		"total_inventory_gap": total_inventory_gap,
		"total_actionable_inventory_gap": total_actionable_inventory_gap,
		"total_pending_marketing_demand": total_pending_marketing_demand,
		"total_pending_defensive_marketing_demand": total_pending_defensive_marketing_demand,
		"total_planning_inventory_gap": total_planning_inventory_gap,
		"total_planning_actionable_inventory_gap": total_planning_actionable_inventory_gap,
		"own_restaurants": _own_restaurant_count(observation),
		"has_food_supply": _has_supply_kind(observation, false),
		"has_drink_supply": _has_supply_kind(observation, true),
	}

static func product_value(product_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	var product_info: Dictionary = Dictionary(products.get(product_id, {}))
	var priority := _profile_product_priority(profile, product_id)
	if product_info.is_empty():
		return {
			"score": priority,
			"public_demand": 0,
			"serviceable_demand": 0,
			"competitive_demand": 0,
			"actionable_demand": 0,
			"lost_to_competitor_demand": 0,
			"own_sourced_demand": 0,
			"own_sourced_opponent_blocking_demand": 0,
			"price_projected_actionable_demand": 0,
			"price_recoverable_demand": 0,
			"inventory_units": 0,
			"inventory_gap": 0,
			"actionable_inventory_gap": 0,
			"pending_marketing_demand": 0,
			"pending_defensive_marketing_demand": 0,
			"pending_marketing_inventory_credit": 0,
			"actionable_pending_marketing_inventory_credit": 0,
			"planning_demand": 0,
			"planning_actionable_demand": 0,
			"planning_inventory_gap": 0,
			"planning_actionable_inventory_gap": 0,
			"can_supply": false,
			"is_drink": _is_drink(product_id),
		}
	return {
		"score": float(product_info.get("value", priority)),
		"public_demand": int(product_info.get("public_demand", 0)),
		"serviceable_demand": int(product_info.get("serviceable_demand", 0)),
		"competitive_demand": int(product_info.get("competitive_demand", product_info.get("serviceable_demand", 0))),
		"actionable_demand": int(product_info.get("actionable_demand", product_info.get("competitive_demand", product_info.get("serviceable_demand", 0)))),
		"lost_to_competitor_demand": int(product_info.get("lost_to_competitor_demand", 0)),
		"own_sourced_demand": int(product_info.get("own_sourced_demand", 0)),
		"own_sourced_opponent_blocking_demand": int(product_info.get("own_sourced_opponent_blocking_demand", 0)),
		"price_projected_actionable_demand": int(product_info.get("price_projected_actionable_demand", product_info.get("actionable_demand", product_info.get("competitive_demand", product_info.get("serviceable_demand", 0))))),
		"price_recoverable_demand": int(product_info.get("price_recoverable_demand", 0)),
		"inventory_units": int(product_info.get("inventory_units", 0)),
		"inventory_gap": int(product_info.get("inventory_gap", 0)),
		"actionable_inventory_gap": int(product_info.get("actionable_inventory_gap", product_info.get("inventory_gap", 0))),
		"pending_marketing_demand": int(product_info.get("pending_marketing_demand", 0)),
		"pending_defensive_marketing_demand": int(product_info.get("pending_defensive_marketing_demand", 0)),
		"pending_marketing_inventory_credit": int(product_info.get("pending_marketing_inventory_credit", 0)),
		"actionable_pending_marketing_inventory_credit": int(product_info.get("actionable_pending_marketing_inventory_credit", product_info.get("pending_marketing_inventory_credit", 0))),
		"planning_demand": int(product_info.get("planning_demand", 0)),
		"planning_actionable_demand": int(product_info.get("planning_actionable_demand", product_info.get("planning_demand", 0))),
		"planning_inventory_gap": int(product_info.get("planning_inventory_gap", 0)),
		"planning_actionable_inventory_gap": int(product_info.get("planning_actionable_inventory_gap", product_info.get("planning_inventory_gap", 0))),
		"can_supply": bool(product_info.get("can_supply", false)),
		"is_drink": bool(product_info.get("is_drink", false)),
	}

static func drink_need(income_analysis: Dictionary) -> Dictionary:
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	var product_ids: Array[String] = []
	var total_public_demand := 0
	var total_serviceable_demand := 0
	var total_pending_marketing_demand := 0
	var total_actionable_demand := 0
	var total_inventory_units := 0
	var total_actionable_inventory_gap := 0
	for product_key in products.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var info: Dictionary = Dictionary(products.get(product_key, {}))
		if not bool(info.get("is_drink", false)):
			continue
		var public_demand := maxi(0, int(info.get("public_demand", 0)))
		var serviceable_demand := maxi(0, int(info.get("serviceable_demand", 0)))
		var actionable_demand := maxi(0, int(info.get("actionable_demand", serviceable_demand)))
		var pending_marketing_demand := maxi(0, int(info.get("pending_marketing_demand", 0)))
		var inventory_units := maxi(0, int(info.get("inventory_units", 0)))
		var total_product_actionable_demand := actionable_demand + pending_marketing_demand
		var actionable_gap := maxi(0, total_product_actionable_demand - inventory_units)
		total_public_demand += public_demand
		total_serviceable_demand += serviceable_demand
		total_pending_marketing_demand += pending_marketing_demand
		total_actionable_demand += total_product_actionable_demand
		total_inventory_units += inventory_units
		total_actionable_inventory_gap += actionable_gap
		if actionable_gap > 0:
			product_ids.append(product_id)
	product_ids.sort()
	return {
		"has_actionable_demand": total_actionable_inventory_gap > 0,
		"product_ids": product_ids,
		"public_demand": total_public_demand,
		"serviceable_demand": total_serviceable_demand,
		"pending_marketing_demand": total_pending_marketing_demand,
		"actionable_demand": total_actionable_demand,
		"inventory_units": total_inventory_units,
		"actionable_inventory_gap": total_actionable_inventory_gap,
	}

static func fridge_capacity_from_observation(observation: ObservationState) -> Dictionary:
	if observation == null:
		return {
			"has_fridge": false,
			"capacity": 0,
		}
	var milestones_val = observation.own_player.get("milestones", [])
	if not (milestones_val is Array):
		return {
			"has_fridge": false,
			"capacity": 0,
		}
	return fridge_capacity_from_milestones(Array(milestones_val), "StrategyIncomeAnalyzer: ", "own_player.milestones")

static func fridge_capacity_from_milestones(milestones: Array, context_prefix: String = "StrategyIncomeAnalyzer: ", path: String = "milestones") -> Dictionary:
	var best_read := MilestoneEffectQueriesClass.max_non_negative_int_value(
		milestones,
		"gain_fridge",
		context_prefix,
		path
	)
	if not best_read.ok or not (best_read.value is Dictionary):
		return {
			"has_fridge": false,
			"capacity": 0,
		}
	var best: Dictionary = best_read.value
	return {
		"has_fridge": bool(best.get("found", false)),
		"capacity": int(best.get("value", 0)),
	}

static func can_preserve_product_for_future_demand(observation: ObservationState, product_id: String) -> bool:
	if product_id.is_empty() or not can_store_product(product_id):
		return false
	var fridge := fridge_capacity_from_observation(observation)
	return bool(fridge.get("has_fridge", false)) and int(fridge.get("capacity", 0)) > 0

static func can_store_product(product_id: String) -> bool:
	return _is_storable_food_or_drink(product_id)

static func build_fridge_keep(observation: ObservationState, capacity: int, profile = null) -> Dictionary:
	if observation == null or capacity <= 0:
		return {}
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return {}
	var inventory: Dictionary = inventory_val
	var analysis := analyze(observation, profile)
	var products: Dictionary = Dictionary(analysis.get("products", {}))
	var units: Array[Dictionary] = []
	for product_key in inventory.keys():
		var product_id := str(product_key)
		if product_id.is_empty() or not _is_storable_food_or_drink(product_id):
			continue
		var available := _inventory_count(observation, product_id)
		if available <= 0:
			continue
		var product_info: Dictionary = Dictionary(products.get(product_id, {}))
		for unit_index in range(1, available + 1):
			units.append({
				"product_id": product_id,
				"unit_index": int(unit_index),
				"value": _fridge_unit_value(product_id, int(unit_index), product_info, profile),
			})
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var value_a := float(a.get("value", 0.0))
		var value_b := float(b.get("value", 0.0))
		if not is_equal_approx(value_a, value_b):
			return value_a > value_b
		var product_a := str(a.get("product_id", ""))
		var product_b := str(b.get("product_id", ""))
		if product_a != product_b:
			return product_a < product_b
		return int(a.get("unit_index", 0)) < int(b.get("unit_index", 0))
	)
	var keep := {}
	var remaining := capacity
	for unit in units:
		if remaining <= 0:
			break
		var product_id := str(unit.get("product_id", ""))
		if product_id.is_empty():
			continue
		keep[product_id] = int(keep.get(product_id, 0)) + 1
		remaining -= 1
	return keep

static func employee_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	if employee_id.is_empty():
		return {"score": 0.0, "role": "", "target_products": []}
	if not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return {"score": _profile_employee_priority(profile, employee_id), "role": "", "target_products": []}
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return {"score": _profile_employee_priority(profile, employee_id), "role": "", "target_products": []}
	var def: EmployeeDef = def_val
	var role := str(def.role)
	var score := _profile_employee_priority(profile, employee_id)
	var target_products: Array[String] = []
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	match role:
		"produce_food":
			for product_id in def.get_production_food_options():
				var product_score := _employee_product_score(product_id, products, profile)
				if product_score > 0.0:
					target_products.append(product_id)
				score += product_score
			if not _owns_role(observation, "produce_food"):
				score += _profile_role_bonus(profile, "income_first_produce_food", 4.0)
		"procure_drink":
			for product_id in _drink_product_ids(products):
				var product_info: Dictionary = Dictionary(products.get(product_id, {}))
				if not _product_has_actionable_need(product_info):
					continue
				var product_score2 := _employee_product_score(product_id, products, profile)
				if product_score2 > 0.0:
					target_products.append(product_id)
				score += product_score2 * 0.85
			if not bool(income_analysis.get("has_drink_supply", false)) and bool(drink_need(income_analysis).get("has_actionable_demand", false)):
				score += _profile_role_bonus(profile, "income_no_drink_supply", 4.0)
		"marketing":
			var marketing_supply_value := _best_marketable_product_score(products, profile)
			score += marketing_supply_value * 0.45
			if int(income_analysis.get("own_restaurants", 0)) > 0:
				score += _profile_role_bonus(profile, "income_marketing_own_restaurant", 2.0)
			if not _owns_role(observation, "marketing"):
				score += _profile_role_bonus(profile, "income_first_marketing", 3.0)
		"new_shop":
			if int(income_analysis.get("own_restaurants", 0)) <= 0:
				score += _profile_role_bonus(profile, "income_first_new_shop", 10.0)
			elif int(income_analysis.get("total_public_demand", 0)) > int(income_analysis.get("total_serviceable_demand", 0)):
				score += _profile_role_bonus(profile, "income_unserviceable_new_shop", 4.0)
		"recruit_train":
			if _has_trainable_reserve_employee(observation):
				score += _profile_role_bonus(profile, "income_recruit_train_trainable", 4.0)
		"price":
			var price_relevant_demand := int(income_analysis.get("total_actionable_demand", income_analysis.get("total_serviceable_demand", 0))) + int(income_analysis.get("total_price_recoverable_demand", 0))
			if price_relevant_demand > 0:
				score += _profile_role_bonus(profile, "income_price_serviceable", 2.0)
	return {
		"score": score,
		"role": role,
		"target_products": target_products,
	}

static func _product_value_from_parts(product_id: String, demand: int, serviceable: int, actionable: int, inventory: int, _gap: int, actionable_gap: int, can_supply: bool, profile, pending: int, _planning_gap: int, planning_actionable_gap: int, pending_inventory_credit: int) -> float:
	var value := _profile_product_priority(profile, product_id)
	var future_gap := maxi(0, planning_actionable_gap - actionable_gap)
	var public_only := maxi(0, demand - actionable)
	value += float(public_only)
	value += float(serviceable) * 1.5
	value += float(actionable) * 5.5
	value += float(actionable_gap) * 5.0
	value += float(future_gap) * 4.0
	value += float(pending) * 2.0
	if inventory > 0:
		value += float(mini(inventory, demand + pending_inventory_credit)) * 2.0
	if can_supply:
		value += 2.0
	return value

static func _product_has_actionable_need(product_info: Dictionary) -> bool:
	var serviceable_demand := maxi(0, int(product_info.get("serviceable_demand", 0)))
	var actionable_demand := maxi(0, int(product_info.get("actionable_demand", serviceable_demand)))
	var pending_marketing_demand := maxi(0, int(product_info.get("pending_marketing_demand", 0)))
	var inventory_units := maxi(0, int(product_info.get("inventory_units", 0)))
	return actionable_demand + pending_marketing_demand > inventory_units

static func _fridge_unit_value(product_id: String, unit_index: int, product_info: Dictionary, profile) -> float:
	var value := _profile_product_priority(profile, product_id) * 0.25
	var public_demand := int(product_info.get("public_demand", 0))
	var serviceable_demand := int(product_info.get("serviceable_demand", 0))
	var pending_marketing_demand := int(product_info.get("pending_marketing_demand", 0))
	var can_supply := bool(product_info.get("can_supply", false))
	if unit_index <= serviceable_demand:
		value += 100.0
	elif unit_index <= public_demand:
		value += 45.0
	elif unit_index <= public_demand + pending_marketing_demand:
		value += 30.0
	elif unit_index <= public_demand + 2 and (public_demand > 0 or can_supply):
		value += 8.0
	elif can_supply:
		value += 2.0
	if not can_supply and unit_index <= public_demand:
		value += 5.0
	return value

static func _employee_product_score(product_id: String, products: Dictionary, profile) -> float:
	var info: Dictionary = Dictionary(products.get(product_id, {}))
	var priority := _profile_product_priority(profile, product_id)
	if info.is_empty():
		return priority * 0.4
	var demand := int(info.get("public_demand", 0))
	var serviceable := int(info.get("serviceable_demand", 0))
	var actionable := int(info.get("actionable_demand", serviceable))
	var gap := int(info.get("inventory_gap", 0))
	var actionable_gap := int(info.get("actionable_inventory_gap", gap))
	var pending := int(info.get("pending_marketing_demand", 0))
	var planning_gap := int(info.get("planning_inventory_gap", gap))
	var planning_actionable_gap := int(info.get("planning_actionable_inventory_gap", planning_gap))
	var future_gap := maxi(0, planning_actionable_gap - actionable_gap)
	var value := priority * 0.5
	value += float(actionable_gap) * 5.0
	value += float(future_gap) * 4.0
	value += float(actionable) * 3.0
	value += float(maxi(0, serviceable - actionable)) * 0.5
	value += float(maxi(0, demand - serviceable)) * 0.25
	value += float(pending) * 2.0
	return value

static func _best_marketable_product_score(products: Dictionary, profile) -> float:
	var best := 0.0
	for product_id_val in products.keys():
		var product_id := str(product_id_val)
		var info: Dictionary = Dictionary(products.get(product_id, {}))
		var value := _profile_product_priority(profile, product_id)
		value += float(info.get("inventory_units", 0)) * 1.5
		if bool(info.get("can_supply", false)):
			value += 2.0
		best = maxf(best, value)
	return best

static func _known_product_ids(observation: ObservationState, profile, pending_marketing_payload: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if ProductRegistryClass.is_loaded():
		for product_id in ProductRegistryClass.get_all_ids():
			_append_unique(out, product_id)
	if profile != null and profile.product_priorities is Dictionary:
		for product_id_val in Dictionary(profile.product_priorities).keys():
			_append_unique(out, str(product_id_val))
	if observation != null:
		var inventory_val = observation.own_player.get("inventory", {})
		if inventory_val is Dictionary:
			for product_id_val2 in Dictionary(inventory_val).keys():
				_append_unique(out, str(product_id_val2))
		var pending_payload := pending_marketing_payload
		if pending_payload.is_empty():
			pending_payload = _pending_marketing_demand_payload(observation)
		for bucket_name in ["revenue", "defensive", "lost"]:
			var bucket_val = pending_payload.get(bucket_name, {})
			if not (bucket_val is Dictionary):
				continue
			for product_id_val3 in Dictionary(bucket_val).keys():
				_append_unique(out, str(product_id_val3))
		var houses_val = observation.map_public.get("houses", {})
		if houses_val is Dictionary:
			for house_val in Dictionary(houses_val).values():
				if not (house_val is Dictionary):
					continue
				var demands_val = Dictionary(house_val).get("demands", [])
				if not (demands_val is Array):
					continue
				for demand_val in Array(demands_val):
					if demand_val is Dictionary:
						_append_unique(out, str(Dictionary(demand_val).get("product", "")))
	out.sort()
	return out

static func _pending_marketing_demand_by_product(observation: ObservationState, source_state = null, source_analysis: Dictionary = {}) -> Dictionary:
	return Dictionary(_pending_marketing_demand_payload(observation, source_state, source_analysis).get("revenue", {}))

static func _pending_marketing_demand_payload(observation: ObservationState, source_state = null, source_analysis: Dictionary = {}) -> Dictionary:
	var out := {
		"revenue": {},
		"defensive": {},
		"lost": {},
	}
	if observation == null:
		return out
	var viewer_id := int(observation.viewer_player_id)
	if viewer_id < 0:
		return out
	var instances := _pending_marketing_instances(observation, source_state)
	for inst in instances:
		if int(inst.get("owner", -1)) != viewer_id:
			continue
		if int(inst.get("remaining_duration", 1)) <= 0:
			continue
		var amount := 1
		if inst.has("demand_amount"):
			amount = maxi(0, int(inst.get("demand_amount", 0)))
		if amount <= 0:
			continue
		var products := _marketing_instance_products(inst)
		if products.is_empty():
			continue
		if not (source_state is GameState):
			for fallback_product_id in products:
				_add_product_units(out["revenue"], fallback_product_id, amount)
			continue
		var affected_ids := _affected_marketing_house_ids(source_state, inst)
		if affected_ids.is_empty():
			for unknown_product_id in products:
				_add_product_units(out["revenue"], unknown_product_id, amount)
			continue
		for product_id in products:
			var pressure := MarketingPressureAnalyzerClass.analyze_candidate(observation, affected_ids, product_id, source_state, source_analysis)
			var self_capture := maxi(0, int(pressure.get("self_capture_houses", pressure.get("competitive_houses", 0))))
			var opponent_pressure := maxi(0, int(pressure.get("opponent_pressure_houses", pressure.get("opponent_capacity_gap_houses", 0))))
			var lost_to_competitor := maxi(0, int(pressure.get("lost_to_competitor_houses", 0)))
			if self_capture > 0:
				_add_product_units(out["revenue"], product_id, self_capture * amount)
			if lost_to_competitor > 0:
				_add_product_units(out["lost"], product_id, lost_to_competitor * amount)
			var defensive_units := maxi(0, opponent_pressure - self_capture)
			if defensive_units > 0:
				_add_product_units(out["defensive"], product_id, defensive_units * amount)
	return out

static func _pending_marketing_instances(observation: ObservationState, source_state = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if source_state is GameState:
		var state: GameState = source_state
		if state.marketing_instances is Array:
			for inst_val in Array(state.marketing_instances):
				if inst_val is Dictionary:
					out.append(Dictionary(inst_val))
			return out
	var instances_val = observation.marketing_instances_public if observation != null else []
	if not (instances_val is Array):
		return out
	for inst_val in Array(instances_val):
		if inst_val is Dictionary:
			out.append(Dictionary(inst_val))
	return out

static func _affected_marketing_house_ids(source_state: GameState, inst: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if source_state == null:
		return out
	var affected_read := MarketingRangeCalculatorClass.new().get_affected_house_ids(source_state, inst)
	if not affected_read.ok:
		return out
	var affected_val = affected_read.value
	if not (affected_val is Array):
		return out
	for house_id_val in Array(affected_val):
		var house_id := str(house_id_val)
		if not house_id.is_empty() and not out.has(house_id):
			out.append(house_id)
	out.sort()
	return out

static func _add_product_units(target, product_id: String, amount: int) -> void:
	if not (target is Dictionary) or product_id.is_empty() or amount <= 0:
		return
	var dict: Dictionary = target
	dict[product_id] = int(dict.get(product_id, 0)) + amount

static func _legacy_pending_marketing_demand_by_product(observation: ObservationState) -> Dictionary:
	var out := {}
	if observation == null:
		return out
	var viewer_id := int(observation.viewer_player_id)
	if viewer_id < 0:
		return out
	var instances_val = observation.marketing_instances_public
	if not (instances_val is Array):
		return out
	for inst_val in Array(instances_val):
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("owner", -1)) != viewer_id:
			continue
		if int(inst.get("remaining_duration", 1)) <= 0:
			continue
		var amount := 1
		if inst.has("demand_amount"):
			amount = maxi(0, int(inst.get("demand_amount", 0)))
		if amount <= 0:
			continue
		for product_id in _marketing_instance_products(inst):
			out[product_id] = int(out.get(product_id, 0)) + amount
	return out

static func _pending_marketing_inventory_credit(observation: ObservationState, product_id: String, demand: int, inventory: int, pending: int) -> int:
	if pending <= 0 or inventory <= demand:
		return 0
	if not can_preserve_product_for_future_demand(observation, product_id):
		return 0
	return mini(pending, inventory - demand)

static func _marketing_instance_products(inst: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var products_val = inst.get("products", null)
	if products_val is Array:
		for product_val in Array(products_val):
			var product_id := str(product_val)
			if not product_id.is_empty():
				_append_unique(out, product_id)
	if out.is_empty():
		var fallback_product_id := str(inst.get("product", ""))
		if not fallback_product_id.is_empty():
			_append_unique(out, fallback_product_id)
	return out

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

static func _serviceable_demand_count_for_product(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return 0
	var count := 0
	for house_id_val in Dictionary(houses_val).keys():
		var house_id := str(house_id_val)
		if _min_house_distance_to_owned_restaurant(observation, house_id) < 0:
			continue
		var house_val = Dictionary(houses_val).get(house_id_val, null)
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
	var is_drink := _is_drink(product_id)
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

static func _has_supply_kind(observation: ObservationState, drink: bool) -> bool:
	if observation == null or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if drink and def.can_procure():
			return true
		if not drink and def.can_produce():
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
			if not employee_id.is_empty() and not out.has(employee_id):
				out.append(employee_id)
	return out

static func _owns_role(observation: ObservationState, role: String) -> bool:
	if observation == null or role.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	for employee_id in _owned_employee_ids(observation.own_player):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDef and str((def_val as EmployeeDef).role) == role:
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

static func _drink_product_ids(products: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for product_id_val in products.keys():
		var product_id := str(product_id_val)
		if _is_drink(product_id):
			out.append(product_id)
	out.sort()
	return out

static func _is_drink(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		return ProductRegistryClass.is_drink(product_id)
	return product_id == "beer" or product_id == "soda" or product_id == "lemonade"

static func _is_storable_food_or_drink(product_id: String) -> bool:
	if product_id.is_empty() or not ProductRegistryClass.is_loaded():
		return false
	var def_val = ProductRegistryClass.get_def(product_id)
	if not (def_val is ProductDef):
		return false
	var def: ProductDef = def_val
	if def.has_tag("no_storage"):
		return false
	return def.has_tag("food") or def.has_tag("drink")

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

static func _append_unique(out: Array[String], value: String) -> void:
	var text := str(value)
	if text.is_empty() or out.has(text):
		return
	out.append(text)

static func _profile_product_priority(profile, product_id: String) -> float:
	if profile == null:
		return 1.0
	return float(profile.product_priority(product_id))

static func _profile_employee_priority(profile, employee_id: String) -> float:
	if profile == null:
		return 1.0
	return float(profile.employee_priority(employee_id))

static func _profile_role_bonus(profile, key: String, fallback: float) -> float:
	if profile == null:
		return fallback
	return float(profile.role_bonus(key, fallback))
