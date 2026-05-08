class_name StrategySupplyPlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const StrategyCashPlannerClass = preload("res://core/ai/strategy/strategy_cash_planner.gd")
const StrategyDinnerPlannerClass = preload("res://core/ai/strategy/strategy_dinner_planner.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")

static func evaluate_action(observation: ObservationState, command: Command, profile, income_analysis: Dictionary, options: Dictionary = {}) -> Dictionary:
	if command == null:
		return {
			"value": 0.0,
			"features": {},
		}
	var features := {}
	var action_id := str(command.action_id)
	var product_id := str(command.params.get("food_type", command.params.get("drink_type", "")))
	if action_id == "procure_drinks" and product_id.is_empty():
		var route_value := route_drink_supply_action_value(observation, command, profile, income_analysis, features)
		var route_no_demand_payload := StrategyCashPlannerClass.no_demand_supply_cash_safety_value(observation, command, features)
		route_value += float(route_no_demand_payload.get("value", 0.0))
		_merge_features(features, Dictionary(route_no_demand_payload.get("features", {})))
		return {
			"value": route_value,
			"features": features,
		}
	var expected_units := expected_supply_units(observation, command)
	var supply_value := product_supply_action_value(product_id, profile, income_analysis, features, expected_units, observation)
	features["product_supply_expected_units"] = expected_units
	var no_demand_payload := StrategyCashPlannerClass.no_demand_supply_cash_safety_value(observation, command, features)
	supply_value += float(no_demand_payload.get("value", 0.0))
	_merge_features(features, Dictionary(no_demand_payload.get("features", {})))
	var preview_payload := StrategyDinnerPlannerClass.supply_preview_value(observation, command, profile, features, options)
	supply_value += float(preview_payload.get("value", 0.0))
	_merge_features(features, Dictionary(preview_payload.get("features", {})))
	return {
		"value": supply_value,
		"features": features,
	}

static func product_supply_action_value(product_id: String, profile, income_analysis: Dictionary, features: Dictionary, expected_units: int = 1, observation: ObservationState = null) -> float:
	if product_id.is_empty():
		return 0.0
	var product_payload := StrategyIncomeAnalyzerClass.product_value(product_id, profile, income_analysis)
	var public_demand := int(product_payload.get("public_demand", 0))
	var serviceable_demand := int(product_payload.get("serviceable_demand", 0))
	var actionable_demand := int(product_payload.get("actionable_demand", serviceable_demand))
	var lost_to_competitor_demand := int(product_payload.get("lost_to_competitor_demand", 0))
	var own_sourced_opponent_blocking_demand := int(product_payload.get("own_sourced_opponent_blocking_demand", 0))
	var price_recoverable_demand := int(product_payload.get("price_recoverable_demand", 0))
	var price_projected_actionable_demand := int(product_payload.get("price_projected_actionable_demand", actionable_demand + price_recoverable_demand))
	var inventory_units := int(product_payload.get("inventory_units", 0))
	var inventory_gap := int(product_payload.get("inventory_gap", 0))
	var actionable_inventory_gap := int(product_payload.get("actionable_inventory_gap", inventory_gap))
	var pending_marketing_demand := int(product_payload.get("pending_marketing_demand", 0))
	var planning_demand := int(product_payload.get("planning_demand", public_demand))
	var planning_actionable_demand := int(product_payload.get("planning_actionable_demand", actionable_demand))
	var planning_inventory_gap := int(product_payload.get("planning_inventory_gap", inventory_gap))
	var planning_actionable_inventory_gap := int(product_payload.get("planning_actionable_inventory_gap", planning_inventory_gap))
	var can_supply := bool(product_payload.get("can_supply", false))
	var can_preserve_future_inventory := StrategyIncomeAnalyzerClass.can_preserve_product_for_future_demand(observation, product_id)
	var effective_pending_marketing_demand := pending_marketing_demand if can_preserve_future_inventory else 0
	var effective_planning_demand := planning_actionable_demand if can_preserve_future_inventory else actionable_demand
	var effective_planning_inventory_gap := planning_actionable_inventory_gap
	if pending_marketing_demand > 0 and not can_preserve_future_inventory:
		effective_planning_inventory_gap = actionable_inventory_gap
	var price_recoverable_inventory_gap := maxi(0, price_projected_actionable_demand - inventory_units)
	var recovery_supply_gap := maxi(0, price_recoverable_inventory_gap - actionable_inventory_gap)
	var product_switch_supply_gap := maxi(0, own_sourced_opponent_blocking_demand - inventory_units)
	var supply_units := maxi(1, expected_units)
	features["product_public_demand"] = public_demand
	features["product_serviceable_demand"] = serviceable_demand
	features["product_actionable_demand"] = actionable_demand
	features["product_lost_to_competitor_demand"] = lost_to_competitor_demand
	features["product_own_sourced_opponent_blocking_demand"] = own_sourced_opponent_blocking_demand
	features["product_price_recoverable_demand"] = price_recoverable_demand
	features["product_price_projected_actionable_demand"] = price_projected_actionable_demand
	features["product_inventory_units"] = inventory_units
	features["product_inventory_gap"] = inventory_gap
	features["product_actionable_inventory_gap"] = actionable_inventory_gap
	features["product_pending_marketing_demand"] = pending_marketing_demand
	features["product_planning_demand"] = planning_demand
	features["product_planning_actionable_demand"] = planning_actionable_demand
	features["product_planning_inventory_gap"] = planning_inventory_gap
	features["product_planning_actionable_inventory_gap"] = planning_actionable_inventory_gap
	features["product_effective_pending_marketing_demand"] = effective_pending_marketing_demand
	features["product_effective_planning_demand"] = effective_planning_demand
	features["product_effective_planning_inventory_gap"] = effective_planning_inventory_gap
	features["product_recovery_supply_gap"] = recovery_supply_gap
	features["product_switch_supply_gap"] = product_switch_supply_gap
	features["product_future_supply_storage_available"] = can_preserve_future_inventory
	if pending_marketing_demand > 0 and not can_preserve_future_inventory:
		features["product_pending_marketing_supply_deferred"] = true
	features["product_can_supply"] = can_supply
	if effective_planning_inventory_gap > 0:
		var covered_units := mini(effective_planning_inventory_gap, supply_units)
		var current_covered_units := mini(actionable_inventory_gap, covered_units)
		var future_covered_units := maxi(0, covered_units - current_covered_units)
		var excess_units := maxi(0, supply_units - effective_planning_inventory_gap)
		features["product_supply_relevance"] = "covers_gap"
		features["product_supply_should_defer"] = false
		features["product_supply_relevant_units"] = covered_units
		features["product_supply_covered_units"] = covered_units
		features["product_supply_current_covered_units"] = current_covered_units
		features["product_supply_future_covered_units"] = future_covered_units
		features["product_supply_excess_units"] = excess_units
		return float(current_covered_units) * 14.0 + float(future_covered_units) * 9.0 + float(actionable_demand) * 3.0 + float(maxi(0, serviceable_demand - actionable_demand)) * 0.5 + float(effective_pending_marketing_demand) * 1.5 + float(profile.product_priority(product_id)) * 0.5 - float(excess_units) * 3.0
	if recovery_supply_gap > 0:
		var recovery_units := mini(recovery_supply_gap, supply_units)
		var recovery_excess := maxi(0, supply_units - recovery_supply_gap)
		features["product_supply_relevance"] = "price_recovery_gap"
		features["product_supply_should_defer"] = false
		features["product_supply_relevant_units"] = recovery_units
		features["product_supply_recovery_units"] = recovery_units
		features["product_supply_excess_units"] = recovery_excess
		return float(recovery_units) * 11.0 + float(price_recoverable_demand) * 3.0 + float(profile.product_priority(product_id)) * 0.5 - float(recovery_excess) * 3.0
	if product_switch_supply_gap > 0:
		var switch_units := mini(product_switch_supply_gap, supply_units)
		var switch_excess := maxi(0, supply_units - product_switch_supply_gap)
		features["product_supply_relevance"] = "product_switch_gap"
		features["product_supply_should_defer"] = false
		features["product_supply_relevant_units"] = switch_units
		features["product_supply_switch_units"] = switch_units
		features["product_supply_excess_units"] = switch_excess
		return float(switch_units) * 11.0 + float(own_sourced_opponent_blocking_demand) * 3.0 + float(profile.product_priority(product_id)) * 0.5 - float(switch_excess) * 3.0
	if public_demand <= 0 and inventory_units <= 0:
		features["product_supply_relevance"] = "no_current_or_planned_demand"
		features["product_supply_should_defer"] = true
		features["product_supply_defer_reason"] = "no_current_or_planned_demand"
		features["product_supply_relevant_units"] = 0
		features["product_no_demand_supply_deferred"] = true
		features["product_supply_excess_units"] = supply_units
		features["product_overstock_penalty"] = true
		return 0.0
	var desired_buffer := maxi(actionable_demand + 1, effective_planning_demand)
	if actionable_demand > 0 and inventory_units < desired_buffer:
		var buffer_units := mini(supply_units, maxi(0, desired_buffer - inventory_units))
		features["product_supply_relevance"] = "buffer"
		features["product_supply_should_defer"] = false
		features["product_supply_relevant_units"] = buffer_units
		features["product_supply_buffer_units"] = buffer_units
		return 4.0 + float(buffer_units) * 2.0 + float(profile.product_priority(product_id)) * 0.25
	features["product_supply_relevance"] = "inventory_satisfied"
	features["product_supply_should_defer"] = true
	features["product_supply_defer_reason"] = "inventory_satisfies_demand"
	features["product_supply_relevant_units"] = 0
	features["product_overstock_penalty"] = true
	features["product_supply_excess_units"] = maxi(0, inventory_units + supply_units - desired_buffer)
	return 0.0

static func route_drink_supply_action_value(observation: ObservationState, command: Command, profile, income_analysis: Dictionary, features: Dictionary) -> float:
	var expected_by_product := expected_route_drinks_by_product(observation, command)
	features["drink_route_expected_units_by_product"] = expected_by_product.duplicate(true)
	if expected_by_product.is_empty():
		features["drink_route_missing_source_types"] = true
		return 0.0
	var product_ids := _sorted_dictionary_keys(expected_by_product)
	var product_values := {}
	var total_value := 0.0
	var total_expected_units := 0
	var total_covered_units := 0
	var total_excess_units := 0
	var total_buffer_units := 0
	var total_relevant_units := 0
	var all_products_deferred := true
	var defer_reasons: Array[String] = []
	var best_product := ""
	var best_product_value := -INF
	var best_features := {}
	for product_id in product_ids:
		var expected_units := maxi(1, int(expected_by_product.get(product_id, 0)))
		var product_features := {}
		var product_value := product_supply_action_value(product_id, profile, income_analysis, product_features, expected_units, observation)
		product_values[product_id] = product_value
		total_value += product_value
		total_expected_units += expected_units
		total_covered_units += int(product_features.get("product_supply_covered_units", 0))
		total_excess_units += int(product_features.get("product_supply_excess_units", 0))
		total_buffer_units += int(product_features.get("product_supply_buffer_units", 0))
		total_relevant_units += int(product_features.get("product_supply_relevant_units", 0))
		if not bool(product_features.get("product_supply_should_defer", false)):
			all_products_deferred = false
		var defer_reason := str(product_features.get("product_supply_defer_reason", ""))
		if not defer_reason.is_empty() and not defer_reasons.has(defer_reason):
			defer_reasons.append(defer_reason)
		if best_product.is_empty() or product_value > best_product_value:
			best_product = product_id
			best_product_value = product_value
			best_features = product_features
	features["drink_route_product_values"] = product_values
	features["product_supply_products"] = product_ids.duplicate()
	features["product_supply_expected_units"] = total_expected_units
	features["product_supply_covered_units"] = total_covered_units
	features["product_supply_excess_units"] = total_excess_units
	features["product_supply_relevant_units"] = total_relevant_units
	features["product_supply_should_defer"] = all_products_deferred
	if all_products_deferred:
		features["product_supply_defer_reason"] = "route_has_no_relevant_products" if defer_reasons.is_empty() else ",".join(defer_reasons)
	if total_buffer_units > 0:
		features["product_supply_buffer_units"] = total_buffer_units
	if not best_product.is_empty():
		features["product_supply_primary_product"] = best_product
		for key in [
			"product_public_demand",
			"product_serviceable_demand",
			"product_actionable_demand",
			"product_lost_to_competitor_demand",
			"product_own_sourced_opponent_blocking_demand",
			"product_inventory_units",
			"product_inventory_gap",
			"product_actionable_inventory_gap",
			"product_pending_marketing_demand",
			"product_planning_demand",
			"product_planning_actionable_demand",
			"product_planning_inventory_gap",
			"product_planning_actionable_inventory_gap",
			"product_effective_pending_marketing_demand",
			"product_effective_planning_demand",
			"product_effective_planning_inventory_gap",
			"product_future_supply_storage_available",
			"product_switch_supply_gap",
			"product_pending_marketing_supply_deferred",
			"product_supply_current_covered_units",
			"product_supply_future_covered_units",
			"product_can_supply",
			"product_supply_relevance",
			"product_no_demand_supply_deferred",
		]:
			if best_features.has(key):
				features[key] = best_features[key]
		if bool(best_features.get("product_overstock_penalty", false)):
			features["product_overstock_penalty"] = true
	return total_value

static func should_defer_supply(features: Dictionary) -> bool:
	return bool(features.get("product_supply_should_defer", false))

static func _merge_features(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		target[key] = source[key]

static func expected_supply_units(observation: ObservationState, command: Command) -> int:
	if command == null:
		return 1
	var action_id := str(command.action_id)
	if action_id == "produce_food":
		return expected_food_units(str(command.params.get("employee_type", "")))
	if action_id == "procure_drinks":
		return expected_drink_units(observation, command)
	return 1

static func expected_food_units(employee_id: String) -> int:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return 1
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if not (def_val is EmployeeDef):
		return 1
	var def: EmployeeDef = def_val
	return maxi(1, int(def.produces_amount)) if not str(def.produces_food_type).is_empty() else 1

static func expected_drink_units(observation: ObservationState, command: Command) -> int:
	var employee_id := str(command.params.get("employee_type", ""))
	if employee_id == "errand_boy":
		if _own_milestones(observation).has("first_errand_boy"):
			return 2
		if observation != null and observation.milestone_pool_public.has("first_errand_boy"):
			return 2
		return 1
	var selected_val = command.params.get("selected_sources", [])
	if selected_val is Array:
		return maxi(1, Array(selected_val).size() * _route_drinks_per_source(observation, command))
	return 1

static func expected_route_drinks_by_product(observation: ObservationState, command: Command) -> Dictionary:
	var type_counts := _selected_drink_source_type_counts(observation, command)
	if type_counts.is_empty():
		return {}
	var per_source := _route_drinks_per_source(observation, command)
	var out := {}
	for product_id in _sorted_dictionary_keys(type_counts):
		out[product_id] = maxi(1, int(type_counts.get(product_id, 0))) * per_source
	return out

static func _selected_drink_source_type_counts(observation: ObservationState, command: Command) -> Dictionary:
	if observation == null or command == null:
		return {}
	var selected_val = command.params.get("selected_sources", [])
	if not (selected_val is Array):
		return {}
	var lookup := _drink_source_types_by_position(observation.map_public)
	if lookup.is_empty():
		return {}
	var counts := {}
	for selected_pos_val in Array(selected_val):
		var pos := _read_vector2i(selected_pos_val)
		var product_id := str(lookup.get(_vector_key(pos), ""))
		if product_id.is_empty():
			continue
		counts[product_id] = int(counts.get(product_id, 0)) + 1
	return counts

static func _drink_source_types_by_position(map_public: Dictionary) -> Dictionary:
	var out := {}
	var sources_val = map_public.get("drink_sources", [])
	if not (sources_val is Array):
		return out
	for source_val in Array(sources_val):
		if not (source_val is Dictionary):
			continue
		var source: Dictionary = source_val
		var product_id := str(source.get("type", "")).strip_edges()
		if product_id.is_empty():
			continue
		var pos := _read_vector2i(source.get("world_pos", Vector2i.ZERO))
		out[_vector_key(pos)] = product_id
	return out

static func _route_drinks_per_source(observation: ObservationState, command: Command) -> int:
	var employee_id := str(command.params.get("employee_type", "")) if command != null else ""
	return maxi(1, 2 + _procure_plus_one_bonus(observation) + _drinks_per_source_delta(observation, employee_id))

static func _procure_plus_one_bonus(observation: ObservationState) -> int:
	var bonus_read := MilestoneEffectQueriesClass.sum_positive_int_values(
		_own_milestones(observation),
		"procure_plus_one",
		"StrategySupplyPlanner: ",
		"own_player.milestones"
	)
	if not bonus_read.ok:
		return 0
	return int(bonus_read.value)

static func _drinks_per_source_delta(observation: ObservationState, employee_id: String) -> int:
	if employee_id.is_empty():
		return 0
	var entries_read := MilestoneEffectQueriesClass.collect_effect_entries(
		_own_milestones(observation),
		"drinks_per_source_delta",
		"StrategySupplyPlanner: ",
		"own_player.milestones"
	)
	if not entries_read.ok:
		return 0
	var total := 0
	for entry_val in Array(entries_read.value):
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var eff_val = entry.get("effect", null)
		if not (eff_val is Dictionary):
			continue
		var eff: Dictionary = eff_val
		var targets_val = eff.get("targets", [])
		if not (targets_val is Array):
			continue
		if not Array(targets_val).has(employee_id):
			continue
		total += _read_int(eff.get("value", 0), 0)
	return total

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

static func _vector_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

static func _sorted_dictionary_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in dict.keys():
		var text := str(key)
		if not text.is_empty():
			out.append(text)
	out.sort()
	return out

static func _read_int(value, fallback: int) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String and str(value).is_valid_int():
		return int(str(value))
	return fallback
