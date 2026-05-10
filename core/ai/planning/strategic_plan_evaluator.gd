class_name StrategicPlanEvaluator
extends RefCounted

const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const EvaluatorClass = preload("res://core/ai/evaluation/evaluator.gd")

static func evaluate_rollout(
	plan,
	rollout: Dictionary,
	profile = null
) -> Result:
	if plan == null or not plan.has_method("is_valid"):
		return Result.failure("StrategicPlanEvaluator.evaluate_rollout: plan is null")
	var engine: GameEngine = rollout.get("engine", null)
	if engine == null:
		return Result.failure("StrategicPlanEvaluator.evaluate_rollout: rollout engine is null")
	var obs_read := ObservationAdapterClass.observe_for_player(engine, plan.owner_player_id)
	if not obs_read.ok:
		return obs_read
	var final_observation: ObservationState = obs_read.value
	var eval_read := EvaluatorClass.score_observation(final_observation, plan.owner_player_id)
	if not eval_read.ok:
		return eval_read
	var before_cash := int(rollout.get("cash_before", 0))
	var after_cash := _own_cash(final_observation)
	var cash_delta := after_cash - before_cash
	var income := StrategyIncomeAnalyzerClass.analyze(final_observation, profile, engine.get_state())
	var eval_payload: Dictionary = Dictionary(eval_read.value)
	var eval_features: Dictionary = Dictionary(eval_payload.get("features", {})).duplicate(true)
	var route_progress_bonus := _route_progress_bonus(plan, final_observation, income, rollout)
	var route_completion_bonus := _route_completion_bonus(plan, final_observation, income, rollout)
	var route_action_count := _route_action_count(plan, rollout)
	var route_stalled := _route_is_stalled(plan, rollout, route_action_count, route_progress_bonus, route_completion_bonus)
	var route_stall_penalty := _route_stall_penalty(route_stalled)
	var breakdown := {
		"cash_delta": cash_delta,
		"cash_after": after_cash,
		"cash_min_after_first_positive": int(rollout.get("cash_min_after_first_positive", after_cash)),
		"cash_max_seen": int(rollout.get("cash_max_seen", after_cash)),
		"milestone_value": _milestone_value(final_observation),
		"sold_units": int(rollout.get("demand_sold", 0)),
		"unsold_demand_penalty": -float(income.get("total_actionable_inventory_gap", 0)) * 6.0,
		"inventory_overstock_penalty": -float(_inventory_units(final_observation)) * 0.8,
		"salary_shortfall_penalty": -float(_salary_shortfall(final_observation)) * 10.0,
		"employee_capability_delta": float(eval_features.get("employee_capability_value", 0.0)),
		"route_progress_bonus": route_progress_bonus,
		"route_completion_bonus": route_completion_bonus,
		"route_stall_penalty": route_stall_penalty,
		"opponent_denial_value": float(income.get("total_own_sourced_opponent_blocking_demand", 0)) * 4.0,
		"search_cost_penalty": -float(rollout.get("search_time_ms", 0)) * 0.01,
	}
	var telemetry := {
		"milestones_gained": Array(rollout.get("milestones_gained", [])).duplicate(true),
		"demand_created": int(rollout.get("demand_created", 0)),
		"demand_sold": int(rollout.get("demand_sold", 0)),
		"lost_to_competitor": int(rollout.get("lost_to_competitor", 0)),
		"salary_due_estimate": int(rollout.get("salary_due_estimate", 0)),
		"route_action_count": route_action_count,
		"route_stalled": route_stalled,
	}
	var score := float(eval_payload.get("score", 0.0))
	for key in breakdown.keys():
		if key == "search_cost_penalty":
			continue
		score += float(breakdown.get(key, 0.0))
	return Result.success({
		"score": score,
		"breakdown": breakdown,
		"telemetry": telemetry,
		"features": eval_features,
	})

static func _route_completion_bonus(
	plan,
	observation: ObservationState,
	income_analysis: Dictionary,
	rollout: Dictionary = {}
) -> float:
	if plan == null or observation == null:
		return 0.0
	var bonus := 0.0
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	for product_id in plan.target_products:
		var info: Dictionary = Dictionary(products.get(product_id, {}))
		if int(info.get("inventory_units", 0)) > 0:
			bonus += 4.0
		if int(info.get("actionable_inventory_gap", 0)) <= 0 and int(info.get("actionable_demand", 0)) > 0:
			bonus += 8.0
	match str(plan.route_type):
		"price_recovery":
			if _owner_executed_any(rollout, plan.owner_player_id, ["set_price", "set_discount", "set_luxury_price"]):
				bonus += 10.0
			if _own_milestones(observation).has("first_lower_prices"):
				bonus += 8.0
		"supply_capacity":
			if _owner_executed_any(rollout, plan.owner_player_id, ["train", "produce_food", "procure_drinks"]):
				bonus += 10.0
			if _own_milestones(observation).has("first_train"):
				bonus += 8.0
		"marketing_income", "product_switch_attack":
			if _owner_executed_any(rollout, plan.owner_player_id, ["initiate_marketing"]):
				bonus += 10.0
			elif _own_marketing_count(observation) > 0:
				bonus += 2.0
		"growth":
			if _owner_executed_any(rollout, plan.owner_player_id, ["place_house", "add_garden", "place_restaurant", "move_restaurant"]):
				bonus += 12.0
			elif _owner_executed_any(rollout, plan.owner_player_id, ["recruit", "train"]):
				bonus += _growth_staff_progress_bonus(rollout, plan.owner_player_id)
	return bonus

static func _route_progress_bonus(
	plan,
	observation: ObservationState,
	income_analysis: Dictionary,
	rollout: Dictionary = {}
) -> float:
	if plan == null or not plan.has_method("is_valid"):
		return 0.0
	var bonus := _sequence_progress_bonus(plan, rollout)
	var gained_milestones := _string_array(rollout.get("milestones_gained", []))
	match str(plan.route_type):
		"marketing_income", "product_switch_attack":
			bonus += float(rollout.get("demand_created", 0)) * 1.0
			bonus += float(rollout.get("demand_sold", 0)) * 1.5
			bonus -= float(rollout.get("lost_to_competitor", 0)) * 1.0
		"price_recovery":
			if gained_milestones.has("first_lower_prices"):
				bonus += 8.0
			bonus += 1.0 if float(rollout.get("cash_min_after_first_positive", 0)) > 0 else 0.0
		"supply_capacity":
			if gained_milestones.has("first_train"):
				bonus += 8.0
			bonus += 1.0 if float(rollout.get("salary_due_estimate", 0)) <= 0 else 0.0
		"growth":
			if _owner_executed_any(rollout, plan.owner_player_id, ["place_house", "add_garden", "place_restaurant", "move_restaurant"]):
				bonus += 8.0
	return bonus

static func _sequence_progress_bonus(plan, rollout: Dictionary = {}) -> float:
	if plan == null or not plan.has_method("is_valid"):
		return 0.0
	var sequence := _string_array(plan.execution_sequence if plan.get("execution_sequence") != null else [])
	if sequence.is_empty():
		return 0.0
	var commands_val = rollout.get("commands_executed", [])
	if not (commands_val is Array):
		return 0.0
	var progress_index := 0
	var bonus := 0.0
	for item_val in Array(commands_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("actor", -1)) != plan.owner_player_id:
			continue
		var action_id := str(item.get("action_id", ""))
		if action_id.is_empty():
			continue
		for seq_index in range(progress_index, sequence.size()):
			if action_id != sequence[seq_index]:
				continue
			bonus += maxf(0.0, 6.0 - float(seq_index) * 0.8)
			progress_index = seq_index + 1
			break
	if progress_index > 0:
		bonus += float(progress_index) * 1.2
	if progress_index >= sequence.size():
		bonus += 6.0
	return bonus

static func _route_action_count(plan, rollout: Dictionary = {}) -> int:
	if plan == null or not plan.has_method("is_valid"):
		return 0
	var command_actions := _route_action_ids(plan)
	if command_actions.is_empty():
		return 0
	var commands_val = rollout.get("commands_executed", [])
	if not (commands_val is Array):
		return 0
	var count := 0
	for item_val in Array(commands_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("actor", -1)) != plan.owner_player_id:
			continue
		var action_id := str(item.get("action_id", "")).strip_edges()
		if action_id.is_empty() or not command_actions.has(action_id):
			continue
		count += 1
	return count

static func _route_action_ids(plan) -> Array[String]:
	if plan == null or not plan.has_method("is_valid"):
		return []
	var sequence := _string_array(plan.execution_sequence if plan.get("execution_sequence") != null else [])
	if not sequence.is_empty():
		return sequence
	match str(plan.route_type):
		"marketing_income", "product_switch_attack":
			return ["recruit", "train", "initiate_marketing", "produce_food", "procure_drinks"]
		"price_recovery":
			return ["recruit", "train", "set_price", "set_discount", "set_luxury_price", "produce_food", "procure_drinks"]
		"supply_capacity":
			return ["recruit", "train", "produce_food", "procure_drinks"]
		"growth":
			return ["recruit", "train", "place_house", "add_garden", "place_restaurant", "move_restaurant"]
	return []

static func _route_is_stalled(
	plan,
	rollout: Dictionary,
	route_action_count: int,
	route_progress_bonus: float,
	route_completion_bonus: float
) -> bool:
	if plan == null or not plan.has_method("is_valid"):
		return false
	if route_action_count > 0:
		return false
	if route_progress_bonus > 0.0 or route_completion_bonus > 0.0:
		return false
	if int(rollout.get("demand_created", 0)) > 0 or int(rollout.get("demand_sold", 0)) > 0:
		return false
	return true

static func _route_stall_penalty(route_stalled: bool) -> float:
	return -140.0 if route_stalled else 0.0

static func _owner_executed_any(rollout: Dictionary, owner_player_id: int, action_ids: Array[String]) -> bool:
	if owner_player_id < 0:
		return false
	var commands_val = rollout.get("commands_executed", [])
	if not (commands_val is Array):
		return false
	for item_val in Array(commands_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("actor", -1)) != owner_player_id:
			continue
		if action_ids.has(str(item.get("action_id", ""))):
			return true
	return false

static func _growth_staff_progress_bonus(rollout: Dictionary, owner_player_id: int) -> float:
	var commands_val = rollout.get("commands_executed", [])
	if not (commands_val is Array):
		return 0.0
	for item_val in Array(commands_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("actor", -1)) != owner_player_id:
			continue
		var params: Dictionary = Dictionary(item.get("params", {}))
		if str(params.get("employee_type", "")) == "new_business_developer" or str(params.get("to_employee", "")) == "new_business_developer":
			return 4.0
	return 0.0

static func _own_cash(observation: ObservationState) -> int:
	if observation == null:
		return 0
	return int(observation.own_player.get("cash", 0))

static func _inventory_units(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	var total := 0
	for amount in Dictionary(inventory_val).values():
		total += maxi(0, int(amount))
	return total

static func _salary_shortfall(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var cash := int(observation.own_player.get("cash", 0))
	var salary_cost := int(observation.rules_public.get("salary_cost", 5))
	var paid_employees := 0
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var employees_val = observation.own_player.get(key, [])
		if employees_val is Array:
			for employee_id in Array(employees_val):
				if str(employee_id) != "ceo":
					paid_employees += 1
	return maxi(0, paid_employees * salary_cost - cash)

static func _milestone_value(observation: ObservationState) -> float:
	return float(_own_milestones(observation).size()) * 6.0

static func _own_milestones(observation: ObservationState) -> Array[String]:
	var out: Array[String] = []
	if observation == null:
		return out
	var milestones_val = observation.own_player.get("milestones", [])
	if milestones_val is Array:
		for item in Array(milestones_val):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out

static func _own_marketing_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var count := 0
	for item in observation.marketing_instances_public:
		if item is Dictionary and int(Dictionary(item).get("owner", -1)) == observation.viewer_player_id:
			count += 1
	return count

static func _own_restaurant_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var restaurants_val = observation.own_player.get("restaurants", [])
	return Array(restaurants_val).size() if restaurants_val is Array else 0

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	return out
