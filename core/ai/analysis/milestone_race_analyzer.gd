class_name MilestoneRaceAnalyzer
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

static func score_macro(observation: ObservationState, macro: MacroAction, profile) -> Dictionary:
	if observation == null or macro == null or macro.commands.is_empty():
		return _empty_payload()
	var command: Command = macro.commands[0]
	if command == null:
		return _empty_payload()
	var candidate_ids := _candidate_milestone_ids(observation, str(command.action_id), command.params, int(command.actor))
	if candidate_ids.is_empty():
		return _empty_payload()

	var available_ids := _available_milestones(observation)
	var own_ids := _own_milestones(observation)
	var scored: Array[Dictionary] = []
	var scored_ids: Array[String] = []
	var total := 0.0
	for milestone_id in candidate_ids:
		if own_ids.has(milestone_id) or not available_ids.has(milestone_id):
			continue
		var value := _milestone_value(milestone_id, profile)
		if value <= 0.0:
			continue
		scored_ids.append(milestone_id)
		scored.append({
			"id": milestone_id,
			"value": value,
		})
		total += value
	return {
		"score": total,
		"milestone_ids": scored_ids,
		"milestones": scored,
	}

static func _candidate_milestone_ids(observation: ObservationState, action_id: String, params: Dictionary, actor_id: int) -> Array[String]:
	var out: Array[String] = []
	match action_id:
		"recruit":
			if _recruit_would_trigger_first_hire_3(observation, actor_id):
				out.append("first_hire_3")
		"train":
			out.append("first_train")
		"produce_food":
			var product_id := str(params.get("food_type", params.get("product", ""))).strip_edges()
			if product_id == "burger":
				out.append("first_burger_produced")
			elif product_id == "pizza":
				out.append("first_pizza_produced")
		"procure_drinks":
			var employee_id := str(params.get("employee_type", "")).strip_edges()
			if employee_id == "errand_boy":
				out.append("first_errand_boy")
			elif employee_id == "cart_operator":
				out.append("first_cart_operator")
		"initiate_marketing":
			var product_id2 := str(params.get("product", "")).strip_edges()
			var marketing_type := str(params.get("marketing_type", "")).strip_edges()
			var board_number := int(params.get("board_number", -1))
			if product_id2 == "burger":
				out.append("first_burger_marketed")
			elif product_id2 == "pizza":
				out.append("first_pizza_marketed")
			elif ["beer", "soda", "lemonade"].has(product_id2):
				out.append("first_drink_marketed")
			if board_number >= 11 and board_number <= 16:
				out.append("first_billboard")
			elif board_number >= 1 and board_number <= 3:
				out.append("first_radio")
			elif marketing_type == "airplane" or (board_number >= 4 and board_number <= 6):
				out.append("first_airplane")
		"set_price", "set_discount":
			out.append("first_lower_prices")
	return out

static func milestone_value(milestone_id: String, profile) -> float:
	return _milestone_value(milestone_id, profile)

static func _recruit_would_trigger_first_hire_3(observation: ObservationState, actor_id: int) -> bool:
	if observation == null:
		return false
	var player_id := actor_id
	if player_id < 0:
		player_id = int(observation.current_player_id)
	if player_id < 0:
		player_id = int(observation.viewer_player_id)
	if player_id < 0:
		return false
	return _round_state_player_count(observation.round_state_public, "recruit_used", player_id) == 2

static func _round_state_player_count(round_state: Dictionary, counter_key: String, player_id: int) -> int:
	if not (round_state is Dictionary):
		return 0
	var all_val = round_state.get(counter_key, null)
	if not (all_val is Dictionary):
		return 0
	var all_counts: Dictionary = all_val
	if all_counts.has(player_id):
		return int(all_counts.get(player_id, 0))
	var string_key := str(player_id)
	if all_counts.has(string_key):
		return int(all_counts.get(string_key, 0))
	return 0

static func _milestone_value(milestone_id: String, profile) -> float:
	if milestone_id.is_empty():
		return 0.0
	var value := _base_milestone_value(milestone_id)
	if MilestoneRegistryClass.is_loaded() and MilestoneRegistryClass.has(milestone_id):
		var def_val = MilestoneRegistryClass.get_def(milestone_id)
		if def_val is MilestoneDef:
			value += _effects_value((def_val as MilestoneDef).effects, profile)
	return maxf(0.0, value)

static func _base_milestone_value(milestone_id: String) -> float:
	match milestone_id:
		"first_train":
			return 10.0
		"first_burger_produced", "first_pizza_produced":
			return 8.0
		"first_errand_boy", "first_cart_operator", "first_airplane":
			return 7.0
		"first_billboard", "first_radio":
			return 9.0
		"first_burger_marketed", "first_pizza_marketed", "first_drink_marketed":
			return 5.0
		"first_lower_prices":
			return 4.0
	return 3.0

static func _effects_value(effects: Array, profile) -> float:
	var total := 0.0
	for effect_val in effects:
		if not (effect_val is Dictionary):
			continue
		var effect: Dictionary = effect_val
		var effect_type := str(effect.get("type", "")).strip_edges()
		match effect_type:
			"salary_total_delta":
				total += maxf(0.0, -float(effect.get("value", 0))) * 0.9
			"gain_card":
				total += 6.0 + _employee_priority(profile, str(effect.get("value", ""))) * 0.8
			"gain_cards":
				var cards_val = effect.get("value", [])
				if cards_val is Array:
					for card_val in Array(cards_val):
						total += 5.0 + _employee_priority(profile, str(card_val)) * 0.6
			"procure_plus_one":
				total += 14.0
			"drinks_per_source_delta":
				total += maxf(10.0, _non_negative_float(effect.get("value", 1), 1.0) * 10.0)
			"distance_plus_one":
				total += 6.0 + float(maxi(1, _array_size(effect.get("targets", [])))) * 4.0
			"marketing_no_salary", "marketing_permanent":
				total += 10.0
			"extra_marketing":
				total += 12.0 + _non_negative_float(effect.get("value", 0), 0.0) * 4.0
			"gain_fridge":
				total += 12.0 + _non_negative_float(effect.get("value", 0), 0.0) * 0.8
			"sell_bonus":
				total += maxf(0.0, float(effect.get("value", 0)))
			"waitress_tips":
				total += maxf(6.0, _non_negative_float(effect.get("value", 0), 0.0) * 2.0)
			"turnorder_empty_slots":
				total += maxf(0.0, float(effect.get("value", 0))) * 4.0
			"multi_trainer_on_one":
				total += 12.0
			"peek_reserve_cards":
				total += 6.0
			"ceo_get_cfo":
				total += 16.0
			"ban_card":
				total += 4.0
			"base_price_delta":
				total += maxf(0.0, -float(effect.get("value", 0))) * 2.0
	return total

static func _non_negative_float(value, fallback: float = 0.0) -> float:
	if value is int or value is float:
		return maxf(0.0, float(value))
	return fallback

static func _array_size(value) -> int:
	if value is Array:
		return Array(value).size()
	return 0

static func _employee_priority(profile, employee_id: String) -> float:
	if profile != null and profile.has_method("employee_priority"):
		return float(profile.employee_priority(employee_id))
	return 1.0

static func _available_milestones(observation: ObservationState) -> Array[String]:
	var out: Array[String] = []
	if observation == null:
		return out
	for item in observation.milestone_pool_public:
		var milestone_id := str(item).strip_edges()
		if not milestone_id.is_empty() and not out.has(milestone_id):
			out.append(milestone_id)
	return out

static func _own_milestones(observation: ObservationState) -> Array[String]:
	var out: Array[String] = []
	if observation == null:
		return out
	var milestones_val = observation.own_player.get("milestones", [])
	if not (milestones_val is Array):
		return out
	for item in Array(milestones_val):
		var milestone_id := str(item).strip_edges()
		if not milestone_id.is_empty() and not out.has(milestone_id):
			out.append(milestone_id)
	return out

static func _empty_payload() -> Dictionary:
	return {
		"score": 0.0,
		"milestone_ids": [],
		"milestones": [],
	}
