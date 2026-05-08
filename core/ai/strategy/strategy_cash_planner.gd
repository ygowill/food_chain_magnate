class_name StrategyCashPlanner
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const PaydayPreviewClass = preload("res://core/ai/analysis/payday_preview.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")

static func payday_cash_snapshot(observation: ObservationState) -> Dictionary:
	return _payday_cash_snapshot(observation)

static func no_demand_food_cash_safety_value(observation: ObservationState, command: Command, supply_features: Dictionary) -> Dictionary:
	if command == null or str(command.action_id) != "produce_food":
		return _empty_value()
	return no_demand_supply_cash_safety_value(observation, command, supply_features)

static func no_demand_supply_cash_safety_value(observation: ObservationState, command: Command, supply_features: Dictionary) -> Dictionary:
	if observation == null or command == null:
		return _empty_value()
	var action_id := str(command.action_id)
	if action_id != "produce_food" and action_id != "procure_drinks":
		return _empty_value()
	if int(supply_features.get("product_public_demand", 0)) > 0:
		return _empty_value()
	if int(supply_features.get("product_serviceable_demand", 0)) > 0:
		return _empty_value()
	if int(supply_features.get("product_inventory_gap", 0)) > 0:
		return _empty_value()
	if int(supply_features.get("product_effective_pending_marketing_demand", 0)) > 0:
		return _empty_value()
	if int(supply_features.get("product_effective_planning_inventory_gap", 0)) > 0:
		return _empty_value()
	if int(supply_features.get("product_inventory_units", 0)) > 0:
		return _empty_value()
	var salary_cost := _read_non_negative_int(observation.rules_public.get("salary_cost", 5), 5)
	if salary_cost <= 0:
		return _empty_value()
	var cash := _read_non_negative_int(observation.own_player.get("cash", 0), 0)
	if cash >= salary_cost:
		return _empty_value()
	var penalty := -180.0
	return {
		"value": penalty,
		"features": {
			"product_no_demand_cash_safety_penalty": penalty,
		},
	}

static func fire_value(observation: ObservationState, command: Command, profile, income_analysis: Dictionary, options: Dictionary = {}) -> Dictionary:
	if observation == null or command == null:
		return _empty_value()
	if str(command.action_id) != "fire":
		return _empty_value()
	var employee_id := str(command.params.get("employee_id", ""))
	var base_payload := _fire_base_value(observation, employee_id, profile, income_analysis)
	var features := {
		"fire_employee_id": employee_id,
		"fire_location": str(command.params.get("location", "")),
		"fire_payday_cash": int(base_payload.get("cash", 0)),
		"fire_payday_due": int(base_payload.get("due", 0)),
		"fire_payday_shortfall": int(base_payload.get("shortfall", 0)),
		"fire_effective_salary_relief": int(base_payload.get("effective_salary_relief", 0)),
		"fire_employee_income_value": float(base_payload.get("employee_income_value", 0.0)),
		"fire_value": float(base_payload.get("value", 0.0)),
	}
	var preview_payload := _fire_payday_preview_value(observation, command, base_payload, options)
	_merge_features(features, Dictionary(preview_payload.get("features", {})))
	return {
		"value": float(base_payload.get("value", 0.0)) + float(preview_payload.get("value", 0.0)),
		"features": features,
	}

static func _fire_base_value(observation: ObservationState, employee_id: String, profile, income_analysis: Dictionary) -> Dictionary:
	var payday := _payday_cash_snapshot(observation)
	var employee_payload := StrategyIncomeAnalyzerClass.employee_value(observation, employee_id, profile, income_analysis)
	var fallback_priority := float(profile.employee_priority(employee_id)) if profile != null else 0.0
	var employee_income_value := float(employee_payload.get("score", fallback_priority))
	var shortfall := int(payday.get("shortfall", 0))
	var effective_relief := _effective_fire_salary_relief(observation, employee_id, payday)
	var value := 0.0
	if shortfall > 0:
		value += 90.0
		value += float(effective_relief) * 8.0
	else:
		value -= 90.0
	value -= employee_income_value * 2.0
	return {
		"value": value,
		"cash": int(payday.get("cash", 0)),
		"due": int(payday.get("due", 0)),
		"shortfall": shortfall,
		"effective_salary_relief": effective_relief,
		"employee_income_value": employee_income_value,
	}

static func _fire_payday_preview_value(observation: ObservationState, command: Command, base_payload: Dictionary, options: Dictionary) -> Dictionary:
	if observation == null or command == null:
		return _empty_value()
	var engine_val = options.get("source_engine", null)
	if not (engine_val is GameEngine):
		return _empty_value()
	var features := {
		"fire_payday_preview_source": "payday_preview",
	}
	var preview_read := PaydayPreviewClass.preview_after_commands(engine_val, [command], {"max_steps": 12})
	if not preview_read.ok:
		features["fire_payday_preview_error"] = preview_read.error
		if _payday_preview_error_is_salary_shortfall(preview_read.error):
			if _fire_base_resolves_actor_shortfall(base_payload):
				features["fire_payday_preview_actor_shortfall_resolved"] = true
				features["fire_payday_preview_other_player_shortfall_pending"] = true
				return {
					"value": 0.0,
					"features": features,
				}
			if int(base_payload.get("effective_salary_relief", 0)) > 0:
				features["fire_payday_preview_actor_shortfall_reduced"] = true
				return {
					"value": 0.0,
					"features": features,
				}
			var failure_penalty := -240.0
			features["fire_payday_preview_failure_penalty"] = failure_penalty
			return {
				"value": failure_penalty,
				"features": features,
			}
		return {
			"value": 0.0,
			"features": features,
		}
	var payload: Dictionary = Dictionary(preview_read.value)
	var actor := int(command.actor)
	var due := _read_indexed_int(payload.get("due", []), actor, 0)
	var paid := _read_indexed_int(payload.get("paid", []), actor, 0)
	var unpaid := _read_indexed_int(payload.get("unpaid", []), actor, 0)
	var cash_after := _payday_preview_cash_after(payload, actor, _read_non_negative_int(observation.own_player.get("cash", 0), 0))
	features["fire_payday_preview_due"] = due
	features["fire_payday_preview_paid"] = paid
	features["fire_payday_preview_unpaid"] = unpaid
	features["fire_payday_preview_cash_after"] = cash_after
	if unpaid > 0:
		if int(base_payload.get("effective_salary_relief", 0)) > 0:
			features["fire_payday_preview_actor_shortfall_reduced"] = true
			return {
				"value": 0.0,
				"features": features,
			}
		var unpaid_penalty := -240.0 - float(unpaid) * 10.0
		features["fire_payday_preview_unpaid_penalty"] = unpaid_penalty
		return {
			"value": unpaid_penalty,
			"features": features,
		}
	return {
		"value": 0.0,
		"features": features,
	}

static func _fire_base_resolves_actor_shortfall(base_payload: Dictionary) -> bool:
	var shortfall := int(base_payload.get("shortfall", 0))
	if shortfall <= 0:
		return true
	return int(base_payload.get("effective_salary_relief", 0)) >= shortfall

static func _payday_cash_snapshot(observation: ObservationState) -> Dictionary:
	if observation == null:
		return {
			"cash": 0,
			"due": 0,
			"shortfall": 0,
			"paid_employee_count": 0,
			"salary_cost": 0,
			"milestone_delta": 0,
		}
	var player := observation.own_player
	var paid_count := EmployeeRulesClass.count_paid_employees(player)
	var salary_cost := _read_non_negative_int(player.get("salary_cost_override", observation.rules_public.get("salary_cost", 5)), 5)
	var milestone_delta := _salary_total_delta(player)
	var due := maxi(0, paid_count * salary_cost + milestone_delta)
	var cash := _read_non_negative_int(player.get("cash", 0), 0)
	return {
		"cash": cash,
		"due": due,
		"shortfall": maxi(0, due - cash),
		"paid_employee_count": paid_count,
		"salary_cost": salary_cost,
		"milestone_delta": milestone_delta,
	}

static func _effective_fire_salary_relief(observation: ObservationState, employee_id: String, payday: Dictionary) -> int:
	if observation == null or employee_id.is_empty():
		return 0
	if not EmployeeRulesClass.requires_salary(employee_id, observation.own_player):
		return 0
	var cash := int(payday.get("cash", 0))
	var before_shortfall := int(payday.get("shortfall", 0))
	var paid_count := maxi(0, int(payday.get("paid_employee_count", 0)) - 1)
	var salary_cost := int(payday.get("salary_cost", 0))
	var milestone_delta := int(payday.get("milestone_delta", 0))
	var after_due := maxi(0, paid_count * salary_cost + milestone_delta)
	var after_shortfall := maxi(0, after_due - cash)
	return maxi(0, before_shortfall - after_shortfall)

static func _payday_preview_error_is_salary_shortfall(error: String) -> bool:
	var text := str(error)
	return text.contains("薪水不足") or text.contains("仍欠") or text.contains("unpaid")

static func _payday_preview_cash_after(payload: Dictionary, player_id: int, fallback: int) -> int:
	var details_val = payload.get("details", [])
	if not (details_val is Array):
		return fallback
	for item_val in Array(details_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("player_id", -1)) != player_id:
			continue
		return _read_int(item.get("cash_after", fallback), fallback)
	return fallback

static func _salary_total_delta(player: Dictionary) -> int:
	var milestones_val = player.get("milestones", [])
	if not (milestones_val is Array):
		return 0
	var delta_read := MilestoneEffectQueriesClass.sum_int_values(
		Array(milestones_val),
		"salary_total_delta",
		"StrategyCashPlanner: ",
		"own_player.milestones"
	)
	if not delta_read.ok:
		return 0
	return int(delta_read.value)

static func _merge_features(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		target[key] = source[key]

static func _empty_value() -> Dictionary:
	return {
		"value": 0.0,
		"features": {},
	}

static func _read_indexed_int(value, index: int, fallback: int) -> int:
	if index < 0:
		return fallback
	if value is Array:
		var arr: Array = value
		if index < arr.size():
			return _read_int(arr[index], fallback)
	return fallback

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
