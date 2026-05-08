class_name StrategySupportPlanner
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const MilestoneRaceAnalyzerClass = preload("res://core/ai/analysis/milestone_race_analyzer.gd")
const MarketingPressureAnalyzerClass = preload("res://core/ai/analysis/marketing_pressure_analyzer.gd")
const StrategyRecoveryPlannerClass = preload("res://core/ai/strategy/strategy_recovery_planner.gd")
const StrategyRoutePlannerClass = preload("res://core/ai/strategy/strategy_route_planner.gd")

static func price_employee_route_value(observation: ObservationState, employee_id: String, income_analysis: Dictionary) -> Dictionary:
	var serviceable_demand := maxi(0, int(income_analysis.get("total_serviceable_demand", 0)))
	var actionable_demand := maxi(0, int(income_analysis.get("total_actionable_demand", serviceable_demand)))
	var recoverable_demand := maxi(0, int(income_analysis.get("total_price_recoverable_demand", 0)))
	var price_relevant_demand := actionable_demand + recoverable_demand
	var route_plan: Dictionary = StrategyRoutePlannerClass.analyze(observation, income_analysis)
	var inventory_units := maxi(0, int(route_plan.get("price_route_sale_inventory_units", route_plan.get("actionable_inventory_units", route_plan.get("serviceable_inventory_units", 0)))))
	var stable_income_ready := bool(route_plan.get("stable_income_ready", false))
	var supply_ready_units := maxi(0, int(route_plan.get("price_route_ready_demand", route_plan.get("supply_ready_actionable_demand", actionable_demand))))
	var estimated_sale_units := inventory_units
	if estimated_sale_units <= 0 and stable_income_ready:
		estimated_sale_units = supply_ready_units
	var first_lower_prices_available := observation != null and _sorted_unique_strings(observation.milestone_pool_public).has("first_lower_prices")
	var out := {
		"value": 0.0,
		"serviceable_demand": serviceable_demand,
		"actionable_demand": actionable_demand,
		"recoverable_demand": recoverable_demand,
		"price_relevant_demand": price_relevant_demand,
		"supply_ready_actionable_demand": supply_ready_units,
		"inventory_units": inventory_units,
		"estimated_sale_units": estimated_sale_units,
		"first_lower_prices_available": first_lower_prices_available,
		"stable_income_ready": stable_income_ready,
		"has_sale_inventory": inventory_units > 0,
	}
	if employee_id.is_empty() or _employee_role(employee_id) != "price":
		return out
	if not bool(route_plan.get("price_route_ready", false)):
		return out
	if price_relevant_demand <= 0:
		return out

	var value := 4.0 + float(actionable_demand) * 1.1 + float(recoverable_demand) * 1.3 + float(estimated_sale_units) * 1.4
	if first_lower_prices_available:
		value += 9.0
	if employee_id == "pricing_manager":
		value += 3.0
	out["value"] = value
	return out

static func waitress_route_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var tips := 3
	var first_waitress_available := false
	if observation != null:
		tips = _read_non_negative_int(observation.rules_public.get("waitress_tips", 3), 3)
		first_waitress_available = _sorted_unique_strings(observation.milestone_pool_public).has("first_waitress") and not _own_milestones(observation).has("first_waitress")
	var out := {
		"value": 0.0,
		"tips": tips,
		"first_waitress_available": first_waitress_available,
		"first_waitress_value": 0.0,
	}
	if employee_id != "waitress":
		return out
	if not StrategyRoutePlannerClass.stable_income_ready(observation, income_analysis):
		return out
	if not StrategyRoutePlannerClass.waitress_support_ready(observation, income_analysis):
		return out

	var first_waitress_value := 0.0
	if first_waitress_available:
		first_waitress_value = MilestoneRaceAnalyzerClass.milestone_value("first_waitress", profile)
	out["first_waitress_value"] = first_waitress_value
	out["value"] = 8.0 + float(tips) * 2.0 + first_waitress_value * 0.4
	return out

static func price_action_value(observation: ObservationState, command: Command, income_analysis: Dictionary, source_state = null) -> Dictionary:
	var action_id := str(command.action_id) if command != null else ""
	var player_id := int(command.actor) if command != null else -1
	var delta := _price_action_delta(action_id)
	var price_payload := _current_unit_price_payload(observation, source_state, player_id)
	var current_unit_price := int(price_payload.get("unit_price", 10))
	var projected_unit_price := current_unit_price + delta
	var demand_payload := _projected_price_action_demand_payload(observation, income_analysis, source_state, delta)
	var serviceable_units := int(demand_payload.get("serviceable_demand", 0))
	var actionable_units := int(demand_payload.get("actionable_demand", 0))
	var recoverable_units := maxi(0, int(income_analysis.get("total_price_recoverable_demand", 0)))
	var price_relevant_units := maxi(0, int(income_analysis.get("total_actionable_demand", serviceable_units))) + recoverable_units
	var inventory_units := int(demand_payload.get("inventory_units", 0))
	var estimated_sale_units := int(demand_payload.get("estimated_sale_units", 0))
	var revenue_delta := delta * estimated_sale_units
	var competition_delta := -delta * actionable_units
	var value := float(revenue_delta) * 0.35 + float(competition_delta) * 0.65
	if actionable_units <= 0:
		value -= float(absi(delta)) * 0.5
	var payload := {
		"value": value,
		"source": str(price_payload.get("source", "observation")),
		"current_unit_price": current_unit_price,
		"action_delta": delta,
		"projected_unit_price": projected_unit_price,
		"round_modifier_total": int(price_payload.get("round_modifier_total", 0)),
		"serviceable_demand": serviceable_units,
		"actionable_demand": actionable_units,
		"recoverable_demand": recoverable_units,
		"price_relevant_demand": price_relevant_units,
		"inventory_units": inventory_units,
		"estimated_sale_units": estimated_sale_units,
		"revenue_delta_estimate": revenue_delta,
		"competition_delta_estimate": competition_delta,
	}
	var recovery_payload := StrategyRecoveryPlannerClass.price_response_value(payload, income_analysis)
	var recovery_value := float(recovery_payload.get("value", 0.0))
	payload["value"] = value + recovery_value
	payload["recovery_value"] = recovery_value
	payload["recovery_needed"] = bool(recovery_payload.get("needs_recovery", false))
	payload["recovery_modes"] = Array(recovery_payload.get("modes", [])).duplicate()
	return {
		"value": float(payload.get("value", 0.0)),
		"source": str(payload.get("source", "observation")),
		"current_unit_price": int(payload.get("current_unit_price", 10)),
		"action_delta": int(payload.get("action_delta", 0)),
		"projected_unit_price": int(payload.get("projected_unit_price", 10)),
		"round_modifier_total": int(payload.get("round_modifier_total", 0)),
		"serviceable_demand": int(payload.get("serviceable_demand", 0)),
		"actionable_demand": int(payload.get("actionable_demand", 0)),
		"recoverable_demand": int(payload.get("recoverable_demand", 0)),
		"price_relevant_demand": int(payload.get("price_relevant_demand", 0)),
		"inventory_units": int(payload.get("inventory_units", 0)),
		"estimated_sale_units": int(payload.get("estimated_sale_units", 0)),
		"revenue_delta_estimate": int(payload.get("revenue_delta_estimate", 0)),
		"competition_delta_estimate": int(payload.get("competition_delta_estimate", 0)),
		"recovery_value": recovery_value,
		"recovery_needed": bool(payload.get("recovery_needed", false)),
		"recovery_modes": Array(payload.get("recovery_modes", [])).duplicate(),
	}

static func evaluate_price_action(observation: ObservationState, command: Command, income_analysis: Dictionary, source_state = null) -> Dictionary:
	var features := {}
	var price_payload := price_action_value(observation, command, income_analysis, source_state)
	_append_price_action_features(features, price_payload)
	return {
		"value": float(price_payload.get("value", 0.0)),
		"features": features,
	}

static func _projected_price_action_demand_payload(observation: ObservationState, income_analysis: Dictionary, source_state, own_price_delta: int) -> Dictionary:
	var serviceable_units := maxi(0, int(income_analysis.get("total_serviceable_demand", 0)))
	var actionable_units := maxi(0, int(income_analysis.get("total_actionable_demand", serviceable_units)))
	var inventory_units := _total_inventory_units(observation)
	var estimated_sale_units := actionable_units if inventory_units <= 0 else mini(actionable_units, inventory_units)
	if not (source_state is GameState) or observation == null or own_price_delta == 0:
		return {
			"serviceable_demand": serviceable_units,
			"actionable_demand": actionable_units,
			"inventory_units": inventory_units,
			"estimated_sale_units": estimated_sale_units,
		}

	var projected_pressure := MarketingPressureAnalyzerClass.current_demand_pressure_by_product(source_state, observation, {}, own_price_delta)
	if projected_pressure.is_empty():
		return {
			"serviceable_demand": serviceable_units,
			"actionable_demand": actionable_units,
			"inventory_units": inventory_units,
			"estimated_sale_units": estimated_sale_units,
		}

	var projected_serviceable := 0
	var projected_actionable := 0
	var projected_inventory := 0
	var projected_estimated_sale_units := 0
	for product_key in projected_pressure.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var product: Dictionary = Dictionary(projected_pressure.get(product_key, {}))
		var product_serviceable := maxi(0, int(product.get("serviceable_demand", 0)))
		var product_actionable := maxi(0, int(product.get("competitive_demand", product_serviceable)))
		var product_inventory := _inventory_count(observation, product_id)
		projected_serviceable += product_serviceable
		projected_actionable += product_actionable
		projected_inventory += product_inventory
		projected_estimated_sale_units += mini(product_actionable, product_inventory)
	if projected_inventory <= 0:
		projected_estimated_sale_units = projected_actionable
	return {
		"serviceable_demand": projected_serviceable,
		"actionable_demand": projected_actionable,
		"inventory_units": projected_inventory,
		"estimated_sale_units": projected_estimated_sale_units,
	}

static func _current_unit_price_payload(observation: ObservationState, source_state, player_id: int) -> Dictionary:
	if source_state is GameState:
		var pipeline_read := PricingPipelineClass.calculate_unit_price(source_state, player_id)
		if pipeline_read.ok:
			return {
				"unit_price": int(pipeline_read.value),
				"source": "pricing_pipeline",
				"round_modifier_total": _price_modifier_total_from_round_state(source_state.round_state, player_id),
			}
	return {
		"unit_price": _fallback_current_unit_price(observation, player_id),
		"source": "observation",
		"round_modifier_total": _price_modifier_total_from_round_state(observation.round_state_public if observation != null else {}, player_id),
	}

static func _fallback_current_unit_price(observation: ObservationState, player_id: int) -> int:
	if observation == null:
		return 10
	var unit_price := _read_non_negative_int(observation.rules_public.get("base_unit_price", 10), 10)
	unit_price += _base_price_delta(observation)
	unit_price += _price_modifier_total_from_round_state(observation.round_state_public, player_id)
	return unit_price

static func _price_action_delta(action_id: String) -> int:
	match action_id:
		"set_price":
			return -1
		"set_discount":
			return -3
		"set_luxury_price":
			return 10
	return 0

static func _price_modifier_total_from_round_state(round_state: Dictionary, player_id: int) -> int:
	var modifiers_val = round_state.get("price_modifiers", {})
	if not (modifiers_val is Dictionary):
		return 0
	var price_modifiers: Dictionary = modifiers_val
	var player_modifiers_val = price_modifiers.get(player_id, price_modifiers.get(str(player_id), {}))
	if not (player_modifiers_val is Dictionary):
		return 0
	var total := 0
	for delta_val in Dictionary(player_modifiers_val).values():
		total += _read_int(delta_val, 0)
	return total

static func _base_price_delta(observation: ObservationState) -> int:
	var delta_read := MilestoneEffectQueriesClass.sum_int_values(
		_own_milestones(observation),
		"base_price_delta",
		"StrategySupportPlanner: ",
		"own_player.milestones"
	)
	if not delta_read.ok:
		return 0
	return int(delta_read.value)

static func _employee_role(employee_id: String) -> String:
	if employee_id.is_empty() or not EmployeeRegistryClass.is_loaded() or not EmployeeRegistryClass.has(employee_id):
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		return str((def_val as EmployeeDef).role)
	return ""

static func _append_price_action_features(features: Dictionary, price_payload: Dictionary) -> void:
	features["price_source"] = str(price_payload.get("source", "observation"))
	features["price_current_unit_price"] = int(price_payload.get("current_unit_price", 0))
	features["price_action_delta"] = int(price_payload.get("action_delta", 0))
	features["price_projected_unit_price"] = int(price_payload.get("projected_unit_price", 0))
	features["price_round_modifier_total"] = int(price_payload.get("round_modifier_total", 0))
	features["price_serviceable_demand"] = int(price_payload.get("serviceable_demand", 0))
	features["price_actionable_demand"] = int(price_payload.get("actionable_demand", price_payload.get("serviceable_demand", 0)))
	features["price_recoverable_demand"] = int(price_payload.get("recoverable_demand", 0))
	features["price_relevant_demand"] = int(price_payload.get("price_relevant_demand", price_payload.get("actionable_demand", price_payload.get("serviceable_demand", 0))))
	features["price_inventory_units"] = int(price_payload.get("inventory_units", 0))
	features["price_estimated_sale_units"] = int(price_payload.get("estimated_sale_units", 0))
	features["price_revenue_delta_estimate"] = int(price_payload.get("revenue_delta_estimate", 0))
	features["price_competition_delta_estimate"] = int(price_payload.get("competition_delta_estimate", 0))
	features["price_action_value"] = float(price_payload.get("value", 0.0))
	features["price_recovery_value"] = float(price_payload.get("recovery_value", 0.0))
	features["price_recovery_needed"] = bool(price_payload.get("recovery_needed", false))
	features["price_recovery_modes"] = Array(price_payload.get("recovery_modes", [])).duplicate()

static func _total_inventory_units(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	var total := 0
	for amount_val in Dictionary(inventory_val).values():
		total += maxi(0, _read_int(amount_val, 0))
	return total

static func _inventory_count(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	return maxi(0, _read_int(Dictionary(inventory_val).get(product_id, 0), 0))

static func _own_milestones(observation: ObservationState) -> Array[String]:
	if observation == null:
		return []
	return _sorted_unique_strings(observation.own_player.get("milestones", []))

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

static func _read_int(value, fallback: int) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String and str(value).is_valid_int():
		return int(str(value))
	return fallback
