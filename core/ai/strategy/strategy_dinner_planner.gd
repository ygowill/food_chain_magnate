class_name StrategyDinnerPlanner
extends RefCounted

const DinnerPreviewClass = preload("res://core/ai/analysis/dinner_preview.gd")
const MilestoneRaceAnalyzerClass = preload("res://core/ai/analysis/milestone_race_analyzer.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")

static func supply_preview_value(observation: ObservationState, command: Command, profile, supply_features: Dictionary, options: Dictionary = {}) -> Dictionary:
	if observation == null or command == null:
		return _empty_value()
	var action_id := str(command.action_id)
	if action_id != "produce_food" and action_id != "procure_drinks":
		return _empty_value()
	if int(supply_features.get("product_public_demand", 0)) <= 0:
		return _empty_value()
	var engine_val = options.get("source_engine", null)
	if not (engine_val is GameEngine):
		return _empty_value()
	if not _supply_preview_needed(observation, command, supply_features, options):
		return {
			"value": 0.0,
			"features": {
				"product_dinner_preview_skipped": "stable_supply",
			},
		}
	var preview_read := DinnerPreviewClass.preview_after_commands(engine_val, [command], {"max_steps": 24})
	if not preview_read.ok:
		return {
			"value": 0.0,
			"features": {
				"product_dinner_preview_error": preview_read.error,
			},
		}
	var payload: Dictionary = Dictionary(preview_read.value)
	var actor := int(command.actor)
	var total_income := _read_indexed_int(payload.get("total_income", []), actor, 0)
	var income_sales := _read_indexed_int(payload.get("income_sales", []), actor, 0)
	var features := {
		"product_dinner_preview_income": total_income,
		"product_dinner_preview_sales_income": income_sales,
		"product_dinner_preview_source": "dinner_preview",
	}
	var value := float(total_income) * 0.35
	value += _dinner_preview_milestone_value(observation, command, payload, actor, profile, features)
	if total_income <= 0 and int(supply_features.get("product_public_demand", 0)) > 0 and _cash_below_salary_cost(observation):
		var penalty := -155.0
		features["product_dinner_preview_no_income_penalty"] = penalty
		value += penalty
	return {
		"value": value,
		"features": features,
	}

static func _dinner_preview_milestone_value(observation: ObservationState, command: Command, payload: Dictionary, player_id: int, profile, features: Dictionary) -> float:
	if observation == null or player_id < 0:
		return 0.0
	var state_val = payload.get("state", null)
	if not (state_val is GameState):
		return 0.0
	var preview_state: GameState = state_val
	var before_ids := _own_milestones(observation)
	var after_ids := _player_milestones_from_state(preview_state, player_id)
	var public_ids := _sorted_unique_strings(observation.milestone_pool_public)
	var immediate_ids := _immediate_milestone_ids_for_command(command)
	var gained: Array[String] = []
	var value := 0.0
	for milestone_id in after_ids:
		if before_ids.has(milestone_id) or not public_ids.has(milestone_id):
			continue
		if immediate_ids.has(milestone_id):
			continue
		gained.append(milestone_id)
		value += MilestoneRaceAnalyzerClass.milestone_value(milestone_id, profile)
	if gained.is_empty():
		return 0.0
	features["product_dinner_preview_milestone_ids"] = gained.duplicate()
	features["product_dinner_preview_milestone_value"] = value
	return value

static func _supply_preview_needed(observation: ObservationState, command: Command, supply_features: Dictionary, options: Dictionary) -> bool:
	if _cash_below_salary_cost(observation):
		return true
	if int(supply_features.get("product_public_demand", 0)) > 0 and int(supply_features.get("product_actionable_demand", 0)) <= 0:
		return true
	if _can_gain_cash_threshold_milestone(observation, command, supply_features, options):
		return true
	return _can_gain_sale_milestone(observation, command)

static func _can_gain_cash_threshold_milestone(observation: ObservationState, command: Command, supply_features: Dictionary, options: Dictionary) -> bool:
	if observation == null or command == null:
		return false
	var own_milestones := _own_milestones(observation)
	var public_ids := _sorted_unique_strings(observation.milestone_pool_public)
	var threshold := -1
	for milestone_id in ["first_have_20", "first_have_100"]:
		if own_milestones.has(milestone_id) or not public_ids.has(milestone_id):
			continue
		threshold = _cash_threshold_for_milestone(milestone_id)
		break
	if threshold <= 0:
		return false
	var cash := _read_non_negative_int(observation.own_player.get("cash", 0), 0)
	if cash >= threshold:
		return false
	var expected_units := _estimated_current_supply_units(supply_features)
	if expected_units <= 0:
		return false
	var unit_price := _estimated_unit_price(command, observation, options)
	return cash + expected_units * unit_price >= threshold

static func _cash_threshold_for_milestone(milestone_id: String) -> int:
	match milestone_id:
		"first_have_20":
			return 20
		"first_have_100":
			return 100
		_:
			return -1

static func _estimated_current_supply_units(supply_features: Dictionary) -> int:
	var units := int(supply_features.get("product_supply_current_covered_units", 0))
	if units <= 0:
		units = int(supply_features.get("product_supply_covered_units", 0))
	if units <= 0:
		units = int(supply_features.get("product_supply_relevant_units", 0))
	return maxi(0, units)

static func _estimated_unit_price(command: Command, observation: ObservationState, options: Dictionary) -> int:
	var source_state = options.get("source_state", null)
	if source_state is GameState and command != null:
		var price_read := PricingPipelineClass.calculate_unit_price(source_state, int(command.actor))
		if price_read.ok:
			return maxi(0, int(price_read.value))
	return _read_non_negative_int(observation.rules_public.get("base_unit_price", 10), 10)

static func _can_gain_sale_milestone(observation: ObservationState, command: Command) -> bool:
	if observation == null or command == null:
		return false
	var product_id := str(command.params.get("food_type", command.params.get("drink_type", command.params.get("product", "")))).strip_edges()
	if product_id.is_empty():
		return false
	var milestone_id := "first_%s_sold" % product_id
	if _own_milestones(observation).has(milestone_id):
		return false
	return _sorted_unique_strings(observation.milestone_pool_public).has(milestone_id)

static func _immediate_milestone_ids_for_command(command: Command) -> Array[String]:
	var out: Array[String] = []
	if command == null:
		return out
	match str(command.action_id):
		"produce_food":
			var product_id := str(command.params.get("food_type", command.params.get("product", ""))).strip_edges()
			if product_id == "burger":
				out.append("first_burger_produced")
			elif product_id == "pizza":
				out.append("first_pizza_produced")
		"procure_drinks":
			var employee_id := str(command.params.get("employee_type", "")).strip_edges()
			if employee_id == "errand_boy":
				out.append("first_errand_boy")
			elif employee_id == "cart_operator":
				out.append("first_cart_operator")
	return out

static func _player_milestones_from_state(state: GameState, player_id: int) -> Array[String]:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return []
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return []
	return _sorted_unique_strings(Dictionary(player_val).get("milestones", []))

static func _cash_below_salary_cost(observation: ObservationState) -> bool:
	if observation == null:
		return false
	var salary_cost := _read_non_negative_int(observation.rules_public.get("salary_cost", 5), 5)
	if salary_cost <= 0:
		return false
	var cash := _read_non_negative_int(observation.own_player.get("cash", 0), 0)
	return cash < salary_cost

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
