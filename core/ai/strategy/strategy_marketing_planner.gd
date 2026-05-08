class_name StrategyMarketingPlanner
extends RefCounted

const MarketingPressureAnalyzerClass = preload("res://core/ai/analysis/marketing_pressure_analyzer.gd")
const MarketingPreviewClass = preload("res://core/ai/analysis/marketing_preview.gd")
const MilestoneRaceAnalyzerClass = preload("res://core/ai/analysis/milestone_race_analyzer.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyRecoveryPlannerClass = preload("res://core/ai/strategy/strategy_recovery_planner.gd")

static func evaluate(observation: ObservationState, command: Command, affected_house_ids: Array[String], profile, income_analysis: Dictionary, options: Dictionary = {}) -> Dictionary:
	var features := {}
	if observation == null or command == null or profile == null:
		return {
			"value": 0.0,
			"features": features,
		}
	var product_id := str(command.params.get("product", ""))
	var affected_count := affected_house_ids.size()
	var pipeline_value := _product_pipeline_value(product_id, profile, income_analysis, features)
	var pressure_val = options.get("marketing_service_features", null)
	var pressure := Dictionary(pressure_val).duplicate(true) if pressure_val is Dictionary else service_features(observation, affected_house_ids, product_id, options.get("source_state", null))
	var marketing_value := value_from_features(affected_count, pipeline_value, pressure)
	var recovery_payload := StrategyRecoveryPlannerClass.marketing_response_value(pressure, income_analysis)
	var recovery_value := float(recovery_payload.get("value", 0.0))
	marketing_value += recovery_value
	features["affected_houses"] = affected_count
	features["affected_house_ids"] = affected_house_ids.duplicate()
	features["product_pipeline_value"] = pipeline_value
	features["marketing_serviceable_houses"] = int(pressure.get("serviceable_houses", 0))
	features["marketing_competitive_houses"] = int(pressure.get("competitive_houses", pressure.get("serviceable_houses", 0)))
	features["marketing_contested_houses"] = int(pressure.get("contested_houses", 0))
	features["marketing_restaurant_dominated_houses"] = int(pressure.get("restaurant_dominated_houses", 0))
	features["marketing_restaurant_dominated_house_ids"] = Array(pressure.get("restaurant_dominated_house_ids", [])).duplicate()
	features["marketing_lost_to_competitor_houses"] = int(pressure.get("lost_to_competitor_houses", 0))
	features["marketing_self_capture_houses"] = int(pressure.get("self_capture_houses", 0))
	features["marketing_self_supply_blocked_houses"] = int(pressure.get("self_supply_blocked_houses", 0))
	features["marketing_opponent_pressure_houses"] = int(pressure.get("opponent_pressure_houses", 0))
	features["marketing_strategic_houses"] = int(pressure.get("strategic_houses", 0))
	features["marketing_strategic_house_ids"] = Array(pressure.get("strategic_house_ids", [])).duplicate()
	features["marketing_pressure_mode"] = str(pressure.get("pressure_mode", "none"))
	features["marketing_opponent_capacity_gap_houses"] = int(pressure.get("opponent_capacity_gap_houses", 0))
	features["marketing_opponent_capacity_gap_prevented_sales"] = int(pressure.get("opponent_capacity_gap_prevented_sales", 0))
	features["marketing_opponent_capacity_gap_owner_ids"] = Array(pressure.get("opponent_capacity_gap_owner_ids", [])).duplicate()
	features["marketing_opponent_capacity_gap_products"] = Array(pressure.get("opponent_capacity_gap_products", [])).duplicate()
	features["marketing_opponent_capacity_gap_value"] = float(pressure.get("opponent_capacity_gap_value", 0.0))
	features["marketing_closest_distance"] = int(pressure.get("closest_distance", -1))
	features["marketing_closest_competitor_distance"] = int(pressure.get("closest_competitor_distance", -1))
	features["marketing_inventory_units"] = int(pressure.get("inventory_units", 0))
	features["marketing_can_supply_product"] = bool(pressure.get("can_supply_product", false))
	features["marketing_can_future_supply_product"] = bool(pressure.get("can_future_supply_product", false))
	features["marketing_supply_readiness_penalty"] = float(pressure.get("supply_readiness_penalty", 0.0))
	features["marketing_competitive_sales_penalty"] = float(pressure.get("competitive_sales_penalty", 0.0))
	features["marketing_own_restaurants"] = int(pressure.get("own_restaurants", 0))
	features["marketing_distance_source"] = str(pressure.get("distance_source", "anchor"))
	features["marketing_recovery_needed"] = bool(recovery_payload.get("needs_recovery", false))
	features["marketing_recovery_lost_to_competitor_demand"] = int(recovery_payload.get("lost_to_competitor_demand", 0))
	features["marketing_recovery_price_recoverable_demand"] = int(recovery_payload.get("price_recoverable_demand", 0))
	features["marketing_recovery_modes"] = Array(recovery_payload.get("modes", [])).duplicate()
	features["marketing_recovery_value"] = recovery_value
	features["marketing_value"] = marketing_value
	marketing_value += _preview_value(observation, command, profile, options, features)
	return {
		"value": marketing_value,
		"features": features,
	}

static func service_features(observation: ObservationState, affected_house_ids: Array[String], product_id: String, source_state = null) -> Dictionary:
	return MarketingPressureAnalyzerClass.analyze_candidate(observation, affected_house_ids, product_id, source_state)

static func opponent_capacity_gap_product_prior(source_state: GameState, observation: ObservationState, product_id: String) -> int:
	return MarketingPressureAnalyzerClass.product_pressure_prior(source_state, observation, product_id)

static func value_from_features(affected_count: int, pipeline_value: float, pressure: Dictionary) -> float:
	if affected_count <= 0:
		return -500.0
	var serviceable := int(pressure.get("serviceable_houses", 0))
	var competitive := int(pressure.get("competitive_houses", serviceable))
	var self_capture := int(pressure.get("self_capture_houses", competitive))
	var self_supply_blocked := int(pressure.get("self_supply_blocked_houses", 0))
	var lost_to_competitor := int(pressure.get("lost_to_competitor_houses", 0))
	var opponent_pressure := int(pressure.get("opponent_pressure_houses", pressure.get("opponent_capacity_gap_houses", 0)))
	var opponent_prevented_sales := int(pressure.get("opponent_capacity_gap_prevented_sales", 0))
	var inventory_units := int(pressure.get("inventory_units", 0))
	var closest_distance := int(pressure.get("closest_distance", -1))
	var own_restaurants := int(pressure.get("own_restaurants", 0))
	var can_supply_product := bool(pressure.get("can_supply_product", false))
	var can_future_supply_product := bool(pressure.get("can_future_supply_product", can_supply_product))
	var value := float(affected_count) * 10.0 + pipeline_value
	value += float(serviceable) * 7.0
	value += float(self_capture) * 8.0
	value -= float(lost_to_competitor) * 24.0
	if opponent_pressure > 0:
		var opponent_pressure_value := float(opponent_pressure) * 24.0 + float(opponent_prevented_sales) * 12.0
		pressure["opponent_capacity_gap_value"] = opponent_pressure_value
		value += opponent_pressure_value
	value += float(mini(inventory_units, affected_count)) * 4.0
	if closest_distance >= 0:
		value += maxf(0.0, 8.0 - float(closest_distance) * 0.5)
	if serviceable > 0 and self_capture <= 0 and opponent_pressure <= 0:
		var competitive_penalty := -170.0
		pressure["competitive_sales_penalty"] = competitive_penalty
		value += competitive_penalty
	if own_restaurants <= 0 and self_capture > 0:
		value -= 16.0
	if self_supply_blocked > 0 and opponent_pressure <= 0:
		var blocked_penalty := -6.0 if can_future_supply_product else -140.0
		pressure["supply_readiness_penalty"] = blocked_penalty
		value += blocked_penalty
	elif self_capture > 0 and not can_supply_product and inventory_units <= 0:
		var readiness_penalty := -6.0 if can_future_supply_product else -140.0
		pressure["supply_readiness_penalty"] = readiness_penalty
		value += readiness_penalty
	return value

static func _product_pipeline_value(product_id: String, profile, income_analysis: Dictionary, features: Dictionary) -> float:
	if product_id.is_empty():
		return 0.0
	var product_payload := StrategyIncomeAnalyzerClass.product_value(product_id, profile, income_analysis)
	features["product_public_demand"] = int(product_payload.get("public_demand", 0))
	features["product_serviceable_demand"] = int(product_payload.get("serviceable_demand", 0))
	features["product_inventory_units"] = int(product_payload.get("inventory_units", 0))
	features["product_inventory_gap"] = int(product_payload.get("inventory_gap", 0))
	features["product_can_supply"] = bool(product_payload.get("can_supply", false))
	return float(product_payload.get("score", 0.0))

static func _preview_value(observation: ObservationState, command: Command, profile, options: Dictionary, features: Dictionary) -> float:
	if observation == null or command == null:
		return 0.0
	if str(command.action_id) != "initiate_marketing":
		return 0.0
	var engine_val = options.get("source_engine", null)
	if not (engine_val is GameEngine):
		return 0.0
	if int(features.get("affected_houses", 0)) <= 0 and int(features.get("marketing_serviceable_houses", 0)) <= 0:
		return 0.0
	var preview_read := MarketingPreviewClass.preview_after_commands(engine_val, [command], {"max_steps": 32})
	if not preview_read.ok:
		features["marketing_preview_error"] = preview_read.error
		return 0.0
	var payload: Dictionary = Dictionary(preview_read.value)
	var actor := int(command.actor)
	var board_number := int(command.params.get("board_number", 0))
	var product_id := str(command.params.get("product", ""))
	var demands_added := _preview_demands_added(payload, actor, board_number, product_id)
	features["marketing_preview_source"] = "marketing_preview"
	features["marketing_preview_demands_added"] = demands_added
	var processed_val = payload.get("processed", [])
	var expired_val = payload.get("expired", [])
	features["marketing_preview_processed_count"] = Array(processed_val).size() if processed_val is Array else 0
	features["marketing_preview_expired_count"] = Array(expired_val).size() if expired_val is Array else 0
	var milestone_value := _preview_milestone_features(observation, payload, actor, profile, features)
	var value := 0.0
	if demands_added <= 0:
		var penalty := -220.0
		features["marketing_preview_no_demand_penalty"] = penalty
		return penalty
	if demands_added > int(features.get("affected_houses", 0)):
		value += float(demands_added - int(features.get("affected_houses", 0))) * 8.0
	if milestone_value > 0.0:
		features["marketing_preview_milestone_value"] = milestone_value
	return value

static func _preview_demands_added(payload: Dictionary, player_id: int, board_number: int, product_id: String) -> int:
	var processed_val = payload.get("processed", [])
	if not (processed_val is Array):
		return 0
	var total := 0
	for item_val in Array(processed_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("owner", -1)) != player_id:
			continue
		if board_number > 0 and int(item.get("board_number", 0)) != board_number:
			continue
		if not product_id.is_empty() and str(item.get("product", "")) != product_id:
			continue
		total += int(item.get("demands_added", 0))
	return total

static func _preview_milestone_features(observation: ObservationState, payload: Dictionary, player_id: int, profile, features: Dictionary) -> float:
	if observation == null or player_id < 0:
		return 0.0
	var state_val = payload.get("state", null)
	if not (state_val is GameState):
		return 0.0
	var preview_state: GameState = state_val
	var before_ids := _own_milestones(observation)
	var after_ids := _player_milestones_from_state(preview_state, player_id)
	var public_ids := _sorted_unique_strings(observation.milestone_pool_public)
	var gained: Array[String] = []
	var value := 0.0
	for milestone_id in after_ids:
		if before_ids.has(milestone_id) or not public_ids.has(milestone_id):
			continue
		gained.append(milestone_id)
		value += MilestoneRaceAnalyzerClass.milestone_value(milestone_id, profile)
	if gained.is_empty():
		return 0.0
	features["marketing_preview_milestone_ids"] = gained.duplicate()
	return value

static func _player_milestones_from_state(state: GameState, player_id: int) -> Array[String]:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return []
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return []
	return _sorted_unique_strings(Dictionary(player_val).get("milestones", []))

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

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out
