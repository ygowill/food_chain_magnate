class_name StrategyBoardAnalyzer
extends RefCounted

const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const MapContextBuilderClass = preload("res://core/map/map_context_builder.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const NodeKeysClass = preload("res://core/map/road_graph/node_keys.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const RestaurantPlacementClass = preload("res://core/map/placement_validator/restaurant_placement.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StructureDistanceClass = preload("res://core/map/map_runtime/structure_distance.gd")

const IDEAL_SERVICE_DISTANCE := 4
const MAX_HEURISTIC_DISTANCE := 8
const OPENING_CENTER_WEIGHT := 0.55
const OPENING_EDGE_PENALTY := -1.5
const OPENING_NEAR_EDGE_PENALTY := -1.0
const RESTAURANT_CONTESTED_HOUSE_VALUE_FACTOR := 0.5
const RESTAURANT_DOMINATED_HOUSE_VALUE_FACTOR := 0.15
const RESTAURANT_CONTESTED_HOUSE_PENALTY_FACTOR := 0.25
const RESTAURANT_DOMINATED_HOUSE_PENALTY_FACTOR := 0.9
const EXPANSION_PRESSURED_DISTANCE_MARGIN := 2
const EXPANSION_PRESSURED_VALUE_FACTOR := 0.85
const EXPANSION_CONTESTED_VALUE_FACTOR := 0.45
const EXPANSION_DOMINATED_VALUE_FACTOR := 0.1
const HOUSE_PRESSURED_MIN_PENALTY := 6.0
const HOUSE_CONTESTED_MIN_PENALTY := 18.0
const HOUSE_DOMINATED_MIN_PENALTY := 42.0
const HOUSE_OPPONENT_ONLY_MIN_PENALTY := 52.0
const GARDEN_PRESSURED_MIN_PENALTY := 8.0
const GARDEN_CONTESTED_MIN_PENALTY := 18.0
const GARDEN_DOMINATED_MIN_PENALTY := 42.0
const GARDEN_OPPONENT_ONLY_MIN_PENALTY := 52.0
const OPENING_CONTESTED_HOUSE_SAFETY_PENALTY := -12.0
const OPENING_DOMINATED_HOUSE_SAFETY_PENALTY := -18.0
const OPENING_LOW_INDEPENDENT_ROUTE_PENALTY := -10.0
const OPENING_NO_INDEPENDENT_ROUTE_PENALTY := -24.0
const OPENING_MARKETING_ROUTE_VALUE := 6.0
const OPENING_SINGLE_MARKETING_ROUTE_PENALTY := -8.0
const OPENING_NO_MARKETING_ROUTE_PENALTY := -28.0

static func restaurant_action_value(
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary,
	source_state = null,
	action_id: String = "",
	actor_id: int = -1,
	source_analysis: Dictionary = {}
) -> Dictionary:
	var payload := restaurant_placement_value(
		observation,
		params,
		income_analysis,
		source_state,
		action_id,
		actor_id,
		source_analysis
	)
	var base_value := _restaurant_action_base_value(action_id, observation)
	payload["restaurant_base_value"] = base_value
	payload["restaurant_value"] = base_value + float(payload.get("placement_value", 0.0))
	return payload

static func evaluate_restaurant_action(
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary,
	source_state = null,
	action_id: String = "",
	actor_id: int = -1,
	source_analysis: Dictionary = {}
) -> Dictionary:
	var placement_payload := restaurant_action_value(
		observation,
		params,
		income_analysis,
		source_state,
		action_id,
		actor_id,
		source_analysis
	)
	var features := {}
	_append_restaurant_features(features, placement_payload)
	return {
		"value": float(placement_payload.get("restaurant_value", 0.0)),
		"features": features,
	}

static func evaluate_house_action(
	observation: ObservationState,
	params: Dictionary,
	source_state = null,
	actor_id: int = -1
) -> Dictionary:
	var house_payload := house_placement_value(observation, params, source_state, actor_id)
	var features := {}
	_append_house_features(features, house_payload)
	return {
		"value": float(house_payload.get("value", 0.0)),
		"features": features,
	}

static func evaluate_garden_action(
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary = {},
	source_state = null,
	actor_id: int = -1
) -> Dictionary:
	var garden_payload := garden_value(observation, params, income_analysis, source_state, actor_id)
	var features := {}
	_append_garden_features(features, garden_payload)
	return {
		"value": float(garden_payload.get("value", 0.0)),
		"features": features,
	}

static func house_placement_value(
	observation: ObservationState,
	params: Dictionary,
	source_state = null,
	actor_id: int = -1
) -> Dictionary:
	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	var restaurant_distance := _nearest_distance_to_owned_restaurant_anchor(observation, anchor)
	var competitor_distance := _nearest_distance_to_competitor_restaurant_anchor(observation, anchor)
	var existing_house_distance := _nearest_distance_to_house_anchor(observation, anchor)
	var value := 0.0
	if restaurant_distance >= 0:
		value += maxf(0.0, 10.0 - float(restaurant_distance)) * 4.0
		if restaurant_distance <= 4:
			value += 12.0
		elif restaurant_distance > 8:
			value -= 10.0
	else:
		value -= 12.0
	if existing_house_distance >= 0:
		value += maxf(0.0, 6.0 - float(existing_house_distance)) * 2.0
	var player_id := actor_id
	if player_id < 0 and observation != null:
		player_id = int(observation.viewer_player_id)
	var price_payload := _current_unit_price_payload(observation, source_state, player_id)
	var unit_price := maxi(1, int(price_payload.get("unit_price", 10)))
	var raw_value := value
	var capture_payload := _expansion_capture_risk(restaurant_distance, competitor_distance, unit_price, 1, "place_house")
	if value > 0.0:
		value *= float(capture_payload.get("value_factor", 1.0))
	value += float(capture_payload.get("opponent_subsidy_penalty", 0.0))
	return {
		"value": value,
		"raw_value": raw_value,
		"anchor": [anchor.x, anchor.y],
		"nearest_restaurant_distance": restaurant_distance,
		"nearest_competitor_restaurant_distance": competitor_distance,
		"nearest_existing_house_distance": existing_house_distance,
		"capture_state": str(capture_payload.get("capture_state", "self_capture")),
		"capture_value_factor": float(capture_payload.get("value_factor", 1.0)),
		"opponent_capture_risk": float(capture_payload.get("opponent_capture_risk", 0.0)),
		"opponent_subsidy_penalty": float(capture_payload.get("opponent_subsidy_penalty", 0.0)),
		"competition_adjustment": value - raw_value,
	}

static func garden_value(
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary = {},
	source_state = null,
	actor_id: int = -1
) -> Dictionary:
	var house_id := str(params.get("house_id", "")).strip_edges()
	var out := _empty_garden_payload(house_id)
	if observation == null or house_id.is_empty():
		return out
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return out
	var houses: Dictionary = houses_val
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		return out
	var house: Dictionary = house_val
	out["has_garden"] = bool(house.get("has_garden", false))
	if bool(out.get("has_garden", false)):
		return out

	var demand_count := _house_demand_count(house)
	var estimated_sale_units := _estimate_house_sale_units(house, income_analysis)
	var normal_cap := _read_positive_int(observation.rules_public.get("demand_cap_normal", 3), 3)
	var garden_cap := _read_positive_int(observation.rules_public.get("demand_cap_with_garden", 5), 5)
	if garden_cap < normal_cap:
		garden_cap = normal_cap
	var capped_sale_units := mini(estimated_sale_units, normal_cap)
	var cap_gain := maxi(0, garden_cap - normal_cap)
	var cap_unlock_units := mini(cap_gain, maxi(0, demand_count - normal_cap))
	var player_id := actor_id
	if player_id < 0:
		player_id = int(observation.viewer_player_id)
	var price_payload := _current_unit_price_payload(observation, source_state, player_id)
	var unit_price := maxi(0, int(price_payload.get("unit_price", 10)))
	var revenue_delta := unit_price * capped_sale_units
	var cap_value := float(cap_unlock_units * unit_price) * 0.35
	if cap_unlock_units <= 0 and demand_count >= normal_cap and cap_gain > 0:
		cap_value += float(cap_gain * unit_price) * 0.12
	var service_distance := _min_house_distance_to_owned_restaurant(observation, house_id)
	var competitor_distance := _min_house_distance_to_competitor_restaurant(observation, house_id)
	var service_value := 0.0
	if service_distance < 0:
		service_value = -12.0
	elif service_distance <= IDEAL_SERVICE_DISTANCE:
		service_value = 6.0 + float(IDEAL_SERVICE_DISTANCE - service_distance) * 1.5
	else:
		service_value = -minf(10.0, float(service_distance - IDEAL_SERVICE_DISTANCE) * 1.5)
	var no_demand_penalty := -6.0 if demand_count <= 0 else 0.0
	var raw_value := float(revenue_delta) * 0.45 + cap_value + float(demand_count) * 1.2 + service_value + no_demand_penalty
	var at_risk_units := maxi(1 if demand_count > 0 else 0, capped_sale_units + cap_unlock_units)
	var capture_payload := _expansion_capture_risk(service_distance, competitor_distance, unit_price, at_risk_units, "add_garden")
	var value := raw_value
	if value > 0.0:
		value *= float(capture_payload.get("value_factor", 1.0))
	value += float(capture_payload.get("opponent_subsidy_penalty", 0.0))

	out["value"] = value
	out["raw_value"] = raw_value
	out["demand_count"] = demand_count
	out["estimated_sale_units"] = capped_sale_units
	out["raw_estimated_sale_units"] = estimated_sale_units
	out["unit_price"] = unit_price
	out["unit_price_source"] = str(price_payload.get("source", "observation"))
	out["revenue_delta_estimate"] = revenue_delta
	out["demand_cap_normal"] = normal_cap
	out["demand_cap_with_garden"] = garden_cap
	out["cap_unlock_units"] = cap_unlock_units
	out["cap_value"] = cap_value
	out["service_distance"] = service_distance
	out["service_value"] = service_value
	out["competitor_service_distance"] = competitor_distance
	out["capture_state"] = str(capture_payload.get("capture_state", "self_capture"))
	out["capture_value_factor"] = float(capture_payload.get("value_factor", 1.0))
	out["opponent_capture_risk"] = float(capture_payload.get("opponent_capture_risk", 0.0))
	out["opponent_subsidy_penalty"] = float(capture_payload.get("opponent_subsidy_penalty", 0.0))
	out["competition_adjustment"] = value - raw_value
	return out

static func restaurant_placement_value(
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary,
	source_state = null,
	action_id: String = "",
	actor_id: int = -1,
	source_analysis: Dictionary = {}
) -> Dictionary:
	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	if source_state is GameState and _should_use_source_restaurant_analysis(observation, action_id):
		var road_payload := _restaurant_placement_value_from_source(
			source_state,
			observation,
			params,
			income_analysis,
			action_id,
			actor_id
		)
		if not road_payload.is_empty():
			return road_payload
	elif source_state is GameState and _should_use_fast_setup_restaurant_analysis(observation, action_id):
		var setup_payload := _restaurant_placement_value_from_setup_source(
			source_state,
			observation,
			params,
			income_analysis,
			actor_id,
			source_analysis
		)
		if not setup_payload.is_empty():
			return setup_payload
	var houses_val = observation.map_public.get("houses", {}) if observation != null else {}
	if not (houses_val is Dictionary):
		return _empty_restaurant_payload(anchor)
	var grid_size := _read_grid_size(observation.map_public if observation != null else {})
	var houses: Dictionary = houses_val
	var nearest_distance := 2147483647
	var nearby_houses := 0
	var nearby_servable_houses := 0
	var nearby_servable_house_ids: Array[String] = []
	var nearby_demand := 0
	var total_demand := 0
	var unserviceable_demand_covered := 0
	var competitive_houses := 0
	var contested_houses := 0
	var competitor_dominated_houses := 0
	var closest_competitor_distance := 2147483647
	var competition_penalty := 0.0
	var house_value := 0.0
	for house_id_val in houses.keys():
		var house_id := str(house_id_val)
		var house_val = houses.get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var house_anchor := _read_vector2i(house.get("anchor_pos", Vector2i.ZERO))
		var distance := absi(anchor.x - house_anchor.x) + absi(anchor.y - house_anchor.y)
		nearest_distance = mini(nearest_distance, distance)
		var demand_count := _house_demand_count(house)
		total_demand += demand_count
		var house_base := maxf(0.0, float(MAX_HEURISTIC_DISTANCE - distance))
		var competitor_distance := _nearest_distance_to_competitor_restaurant_anchor(observation, house_anchor)
		if competitor_distance >= 0:
			closest_competitor_distance = mini(closest_competitor_distance, competitor_distance)
		var competition_payload := _restaurant_house_competition(distance, competitor_distance, house_base)
		var value_factor := float(competition_payload.get("value_factor", 1.0))
		var house_competition_penalty := float(competition_payload.get("penalty", 0.0))
		var competition_state := str(competition_payload.get("state", "competitive"))
		competition_penalty += house_competition_penalty
		if house_base > 0.0:
			match competition_state:
				"dominated":
					competitor_dominated_houses += 1
				"contested":
					contested_houses += 1
				_:
					competitive_houses += 1
		if distance <= IDEAL_SERVICE_DISTANCE:
			nearby_houses += 1
			if competition_state != "dominated":
				nearby_servable_houses += 1
				nearby_servable_house_ids.append(house_id)
				nearby_demand += demand_count
		house_value += house_base * 0.75 * value_factor
		house_value += house_competition_penalty
		if demand_count > 0 and competition_state != "dominated":
			house_value += house_base * value_factor * float(demand_count) * 2.0
			if observation != null and _min_house_distance_to_owned_restaurant(observation, house_id) < 0:
				unserviceable_demand_covered += demand_count
				house_value += house_base * value_factor * float(demand_count) * 1.25
	var own_restaurants := int(income_analysis.get("own_restaurants", 0))
	if own_restaurants <= 0 and nearby_servable_houses > 0:
		house_value += 10.0
	if total_demand > 0 and nearby_demand <= 0:
		house_value -= 8.0
	var opening_competition_safety_penalty := _opening_competition_safety_penalty(own_restaurants, competitive_houses, contested_houses, competitor_dominated_houses)
	house_value += opening_competition_safety_penalty
	var marketing_launch_payload := _opening_marketing_launch_payload(source_state, houses, nearby_servable_house_ids, own_restaurants)
	house_value += float(marketing_launch_payload.get("value", 0.0))
	var robustness_payload := _opening_robustness_payload(anchor, grid_size, own_restaurants)
	house_value += float(robustness_payload.get("value", 0.0))
	var nearest := nearest_distance if nearest_distance < 2147483647 else -1
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": nearest,
		"nearby_houses": nearby_houses,
		"nearby_demand": nearby_demand,
		"total_public_demand": total_demand,
		"unserviceable_demand_covered": unserviceable_demand_covered,
		"competitive_houses": competitive_houses,
		"contested_houses": contested_houses,
		"competitor_dominated_houses": competitor_dominated_houses,
		"closest_competitor_distance": closest_competitor_distance if closest_competitor_distance < 2147483647 else -1,
		"competition_penalty": competition_penalty,
		"opening_competition_safety_penalty": opening_competition_safety_penalty,
		"opening_marketing_route_houses": int(marketing_launch_payload.get("route_houses", 0)),
		"opening_marketing_blocked_houses": int(marketing_launch_payload.get("blocked_houses", 0)),
		"opening_marketing_route_board_count": int(marketing_launch_payload.get("route_board_count", 0)),
		"opening_marketing_route_options": int(marketing_launch_payload.get("route_options", 0)),
		"opening_marketing_route_board_ids": Array(marketing_launch_payload.get("route_board_ids", [])).duplicate(),
		"opening_marketing_route_value": float(marketing_launch_payload.get("value", 0.0)),
		"placement_value": house_value,
		"distance_source": "anchor",
		"opening_robustness_value": float(robustness_payload.get("value", 0.0)),
		"opening_center_distance": float(robustness_payload.get("center_distance", -1.0)),
		"opening_edge_distance": int(robustness_payload.get("edge_distance", -1)),
	}

static func _restaurant_action_base_value(action_id: String, observation: ObservationState) -> float:
	if action_id == "place_restaurant":
		return 10.0 if _own_restaurant_count(observation) <= 0 else 2.0
	if action_id == "move_restaurant":
		return 1.0
	return 0.0

static func _should_use_source_restaurant_analysis(observation: ObservationState, action_id: String) -> bool:
	if observation != null and str(observation.phase) == DefsClass.PHASE_SETUP and action_id == "place_restaurant":
		return false
	return true

static func _should_use_fast_setup_restaurant_analysis(observation: ObservationState, action_id: String) -> bool:
	return observation != null and str(observation.phase) == DefsClass.PHASE_SETUP and action_id == "place_restaurant"

static func _append_restaurant_features(features: Dictionary, placement_payload: Dictionary) -> void:
	features["restaurant_value"] = float(placement_payload.get("restaurant_value", 0.0))
	features["restaurant_base_value"] = float(placement_payload.get("restaurant_base_value", 0.0))
	features["restaurant_candidate_anchor"] = Array(placement_payload.get("candidate_anchor", [])).duplicate()
	features["restaurant_nearest_house_distance"] = int(placement_payload.get("nearest_house_distance", -1))
	features["restaurant_nearby_houses"] = int(placement_payload.get("nearby_houses", 0))
	features["restaurant_nearby_demand"] = int(placement_payload.get("nearby_demand", 0))
	features["restaurant_total_public_demand"] = int(placement_payload.get("total_public_demand", 0))
	features["restaurant_unserviceable_demand_covered"] = int(placement_payload.get("unserviceable_demand_covered", 0))
	features["restaurant_competitive_houses"] = int(placement_payload.get("competitive_houses", 0))
	features["restaurant_contested_houses"] = int(placement_payload.get("contested_houses", 0))
	features["restaurant_competitor_dominated_houses"] = int(placement_payload.get("competitor_dominated_houses", 0))
	features["restaurant_closest_competitor_distance"] = int(placement_payload.get("closest_competitor_distance", -1))
	features["restaurant_competition_penalty"] = float(placement_payload.get("competition_penalty", 0.0))
	features["restaurant_opening_competition_safety_penalty"] = float(placement_payload.get("opening_competition_safety_penalty", 0.0))
	features["restaurant_opening_marketing_route_houses"] = int(placement_payload.get("opening_marketing_route_houses", 0))
	features["restaurant_opening_marketing_blocked_houses"] = int(placement_payload.get("opening_marketing_blocked_houses", 0))
	features["restaurant_opening_marketing_route_board_count"] = int(placement_payload.get("opening_marketing_route_board_count", 0))
	features["restaurant_opening_marketing_route_options"] = int(placement_payload.get("opening_marketing_route_options", 0))
	features["restaurant_opening_marketing_route_board_ids"] = Array(placement_payload.get("opening_marketing_route_board_ids", [])).duplicate()
	features["restaurant_opening_marketing_route_value"] = float(placement_payload.get("opening_marketing_route_value", 0.0))
	features["restaurant_placement_value"] = float(placement_payload.get("placement_value", 0.0))
	features["restaurant_distance_source"] = str(placement_payload.get("distance_source", "anchor"))
	features["restaurant_opening_robustness_value"] = float(placement_payload.get("opening_robustness_value", 0.0))
	features["restaurant_opening_center_distance"] = float(placement_payload.get("opening_center_distance", -1.0))
	features["restaurant_opening_edge_distance"] = int(placement_payload.get("opening_edge_distance", -1))

static func _append_house_features(features: Dictionary, house_payload: Dictionary) -> void:
	features["house_candidate_anchor"] = Array(house_payload.get("anchor", [])).duplicate()
	features["house_nearest_restaurant_distance"] = int(house_payload.get("nearest_restaurant_distance", -1))
	features["house_nearest_competitor_restaurant_distance"] = int(house_payload.get("nearest_competitor_restaurant_distance", -1))
	features["house_nearest_existing_house_distance"] = int(house_payload.get("nearest_existing_house_distance", -1))
	features["house_raw_placement_value"] = float(house_payload.get("raw_value", house_payload.get("value", 0.0)))
	features["house_capture_state"] = str(house_payload.get("capture_state", "self_capture"))
	features["house_capture_value_factor"] = float(house_payload.get("capture_value_factor", 1.0))
	features["house_opponent_capture_risk"] = float(house_payload.get("opponent_capture_risk", 0.0))
	features["house_opponent_subsidy_penalty"] = float(house_payload.get("opponent_subsidy_penalty", 0.0))
	features["house_competition_adjustment"] = float(house_payload.get("competition_adjustment", 0.0))
	features["house_placement_value"] = float(house_payload.get("value", 0.0))

static func _append_garden_features(features: Dictionary, garden_payload: Dictionary) -> void:
	features["garden_house_id"] = str(garden_payload.get("house_id", ""))
	features["garden_has_garden"] = bool(garden_payload.get("has_garden", false))
	features["garden_house_demand_count"] = int(garden_payload.get("demand_count", 0))
	features["garden_estimated_sale_units"] = int(garden_payload.get("estimated_sale_units", 0))
	features["garden_raw_estimated_sale_units"] = int(garden_payload.get("raw_estimated_sale_units", 0))
	features["garden_unit_price"] = int(garden_payload.get("unit_price", 0))
	features["garden_unit_price_source"] = str(garden_payload.get("unit_price_source", "observation"))
	features["garden_revenue_delta_estimate"] = int(garden_payload.get("revenue_delta_estimate", 0))
	features["garden_demand_cap_normal"] = int(garden_payload.get("demand_cap_normal", 0))
	features["garden_demand_cap_with_garden"] = int(garden_payload.get("demand_cap_with_garden", 0))
	features["garden_cap_unlock_units"] = int(garden_payload.get("cap_unlock_units", 0))
	features["garden_cap_value"] = float(garden_payload.get("cap_value", 0.0))
	features["garden_nearest_restaurant_distance"] = int(garden_payload.get("service_distance", -1))
	features["garden_service_value"] = float(garden_payload.get("service_value", 0.0))
	features["garden_nearest_competitor_restaurant_distance"] = int(garden_payload.get("competitor_service_distance", -1))
	features["garden_raw_value"] = float(garden_payload.get("raw_value", garden_payload.get("value", 0.0)))
	features["garden_capture_state"] = str(garden_payload.get("capture_state", "self_capture"))
	features["garden_capture_value_factor"] = float(garden_payload.get("capture_value_factor", 1.0))
	features["garden_opponent_capture_risk"] = float(garden_payload.get("opponent_capture_risk", 0.0))
	features["garden_opponent_subsidy_penalty"] = float(garden_payload.get("opponent_subsidy_penalty", 0.0))
	features["garden_competition_adjustment"] = float(garden_payload.get("competition_adjustment", 0.0))
	features["garden_value"] = float(garden_payload.get("value", 0.0))

static func _own_restaurant_count(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var restaurants_val = observation.own_player.get("restaurants", [])
	if restaurants_val is Array:
		return Array(restaurants_val).size()
	return 0

static func _restaurant_placement_value_from_source(
	source_state: GameState,
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary,
	action_id: String,
	actor_id: int
) -> Dictionary:
	var player_id := actor_id
	if player_id < 0 and observation != null:
		player_id = int(observation.viewer_player_id)
	if player_id < 0:
		return {}

	var state := source_state.duplicate_state()
	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	var rotation := int(params.get("rotation", 0))
	var map_ctx_read := MapContextBuilderClass.build_context_result(state, "StrategyBoardAnalyzer.restaurant_placement_value")
	if not map_ctx_read.ok:
		return {}
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := PieceDefClass.create_default_registry()
	var restaurant_id := ""
	var existing_owned_ids := _owned_restaurant_ids(observation, source_state, player_id)

	if action_id == "move_restaurant":
		restaurant_id = str(params.get("restaurant_id", "")).strip_edges()
		if restaurant_id.is_empty():
			return {}
		existing_owned_ids.erase(restaurant_id)
		var move_read := _apply_hypothetical_move(state, map_ctx, piece_registry, player_id, restaurant_id, anchor, rotation)
		if not move_read.ok:
			return {}
	else:
		restaurant_id = _candidate_restaurant_id(state)
		var place_read := _apply_hypothetical_place(state, map_ctx, piece_registry, player_id, restaurant_id, anchor, rotation)
		if not place_read.ok:
			return {}

	RoadGraphCacheClass.invalidate_road_graph(state)
	var analysis_read := BoardAnalyzerClass.analyze_state(state)
	if not analysis_read.ok:
		return {}
	var analysis: Dictionary = analysis_read.value
	if not bool(analysis.get("road_graph_available", false)):
		return {}
	return _restaurant_payload_from_analysis(
		state,
		anchor,
		observation,
		income_analysis,
		analysis,
		restaurant_id,
		existing_owned_ids,
		_competitor_restaurant_ids(state, player_id, restaurant_id)
	)

static func _restaurant_placement_value_from_setup_source(
	source_state: GameState,
	observation: ObservationState,
	params: Dictionary,
	income_analysis: Dictionary,
	actor_id: int,
	source_analysis: Dictionary
) -> Dictionary:
	var player_id := actor_id
	if player_id < 0 and observation != null:
		player_id = int(observation.viewer_player_id)
	if player_id < 0:
		return {}

	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	var rotation := int(params.get("rotation", 0))
	var map_ctx_read := MapContextBuilderClass.build_context_result(source_state, "StrategyBoardAnalyzer.setup_restaurant_placement_value")
	if not map_ctx_read.ok:
		return {}
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := PieceDefClass.create_default_registry()
	var validate_read := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx,
		anchor,
		rotation,
		piece_registry,
		player_id,
		true,
		{}
	)
	if not validate_read.ok:
		return {}
	var payload_read := _read_placement_payload(validate_read.value)
	if not payload_read.ok:
		return {}
	var payload: Dictionary = payload_read.value
	var entrance_pos: Vector2i = payload["entrance_pos"]
	var distance_context := _setup_distance_context(source_state, map_ctx, source_analysis)
	if distance_context.is_empty():
		return {}

	var candidate_restaurant_id := _candidate_restaurant_id(source_state)
	var candidate_distances_read := _build_candidate_house_distances_from_context(source_state, distance_context, [entrance_pos])
	if not candidate_distances_read.ok:
		return {}
	var candidate_distances: Dictionary = candidate_distances_read.value
	var analysis := Dictionary(distance_context.get("analysis", {})).duplicate(true)
	var distances := Dictionary(analysis.get("restaurant_house_distances", {})).duplicate(true)
	distances[candidate_restaurant_id] = candidate_distances
	analysis["restaurant_house_distances"] = distances
	analysis["road_graph_available"] = true
	return _restaurant_payload_from_analysis(
		source_state,
		anchor,
		observation,
		income_analysis,
		analysis,
		candidate_restaurant_id,
		_owned_restaurant_ids(observation, source_state, player_id),
		_competitor_restaurant_ids(source_state, player_id, "")
	)

static func _apply_hypothetical_place(
	state: GameState,
	map_ctx: Dictionary,
	piece_registry: Dictionary,
	player_id: int,
	restaurant_id: String,
	anchor: Vector2i,
	rotation: int
) -> Result:
	var is_initial := str(state.phase) == DefsClass.PHASE_SETUP
	var validate_read := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx,
		anchor,
		rotation,
		piece_registry,
		player_id,
		is_initial,
		{}
	)
	if not validate_read.ok:
		return validate_read
	var payload_read := _read_placement_payload(validate_read.value)
	if not payload_read.ok:
		return payload_read
	var payload: Dictionary = payload_read.value
	var footprint_cells: Array[Vector2i] = payload["footprint_cells"]
	var entrance_pos: Vector2i = payload["entrance_pos"]
	_write_restaurant_cells(state, restaurant_id, player_id, anchor, rotation, footprint_cells)

	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: state.map.restaurants is not Dictionary")
	var restaurants: Dictionary = restaurants_val
	restaurants[restaurant_id] = {
		"restaurant_id": restaurant_id,
		"owner": player_id,
		"anchor_pos": anchor,
		"entrance_pos": entrance_pos,
		"cells": footprint_cells,
		"rotation": rotation,
	}
	state.map["restaurants"] = restaurants
	_add_player_restaurant_id(state, player_id, restaurant_id)
	return Result.success()

static func _apply_hypothetical_move(
	state: GameState,
	map_ctx: Dictionary,
	piece_registry: Dictionary,
	player_id: int,
	restaurant_id: String,
	anchor: Vector2i,
	rotation: int
) -> Result:
	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: state.map.restaurants is not Dictionary")
	var restaurants: Dictionary = restaurants_val
	var rest_val = restaurants.get(restaurant_id, null)
	if not (rest_val is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: restaurant not found: %s" % restaurant_id)
	var rest: Dictionary = rest_val
	if int(rest.get("owner", -1)) != player_id:
		return Result.failure("StrategyBoardAnalyzer: restaurant owner mismatch: %s" % restaurant_id)
	var old_cells := _read_vector2i_array(rest.get("cells", []))
	if old_cells.is_empty():
		return Result.failure("StrategyBoardAnalyzer: restaurant cells missing: %s" % restaurant_id)

	var validate_read := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx,
		anchor,
		rotation,
		piece_registry,
		player_id,
		false,
		{"ignore_structure_cells": old_cells}
	)
	if not validate_read.ok:
		return validate_read
	var payload_read := _read_placement_payload(validate_read.value)
	if not payload_read.ok:
		return payload_read
	var payload: Dictionary = payload_read.value
	var new_cells: Array[Vector2i] = payload["footprint_cells"]
	var entrance_pos: Vector2i = payload["entrance_pos"]

	_clear_structure_cells(state, old_cells)
	_write_restaurant_cells(state, restaurant_id, player_id, anchor, rotation, new_cells)
	rest["anchor_pos"] = anchor
	rest["entrance_pos"] = entrance_pos
	rest["cells"] = new_cells
	rest["rotation"] = rotation
	restaurants[restaurant_id] = rest
	state.map["restaurants"] = restaurants
	return Result.success()

static func _read_placement_payload(value) -> Result:
	if not (value is Dictionary):
		return Result.failure("StrategyBoardAnalyzer: placement payload is not Dictionary")
	var payload: Dictionary = value
	var footprint_cells := _read_vector2i_array(payload.get("footprint_cells", []))
	if footprint_cells.is_empty():
		return Result.failure("StrategyBoardAnalyzer: placement footprint_cells is empty")
	var entrance_val = payload.get("entrance_pos", null)
	if not (entrance_val is Vector2i):
		return Result.failure("StrategyBoardAnalyzer: placement entrance_pos missing")
	return Result.success({
		"footprint_cells": footprint_cells,
		"entrance_pos": entrance_val,
	})

static func _source_analysis_or_basic(source_analysis: Dictionary, houses: Dictionary, grid_size: Vector2i) -> Dictionary:
	if not source_analysis.is_empty():
		return source_analysis.duplicate(true)
	return {
		"grid_size": grid_size,
		"houses": houses.duplicate(true),
		"restaurant_house_distances": {},
	}

static func _setup_distance_context(source_state: GameState, map_ctx: Dictionary, source_analysis: Dictionary) -> Dictionary:
	var cache_key := "_setup_restaurant_distance_context"
	var cached_val = source_analysis.get(cache_key, null)
	if cached_val is Dictionary:
		return cached_val
	var grid_size: Vector2i = map_ctx.get("grid_size", Vector2i.ZERO)
	var houses: Dictionary = Dictionary(map_ctx.get("houses", {}))
	var road_graph = RoadGraphCacheClass.get_road_graph(source_state)
	if road_graph == null:
		return {}
	var house_infos := {}
	for house_id in _sorted_string_keys(houses):
		var house_val = houses.get(house_id, null)
		if not (house_val is Dictionary):
			return {}
		var house_cells_read := _read_house_cells(Dictionary(house_val), house_id)
		if not house_cells_read.ok:
			return {}
		var house_cells: Array[Vector2i] = house_cells_read.value
		var house_roads := StructureDistanceClass.get_structure_adjacent_roads(source_state, grid_size, house_cells)
		if house_roads.is_empty():
			continue
		house_infos[house_id] = {
			"roads": house_roads,
			"entry_cost_by_road": _build_structure_to_road_boundary_cost(house_cells, house_roads),
		}
	var context := {
		"analysis": _source_analysis_or_basic(source_analysis, houses, grid_size),
		"grid_size": grid_size,
		"house_infos": house_infos,
		"road_graph": road_graph,
		"road_distance_cache": {},
	}
	source_analysis[cache_key] = context
	return context

static func _build_candidate_house_distances_from_context(
	state: GameState,
	distance_context: Dictionary,
	entrance_points: Array[Vector2i]
) -> Result:
	var per_house := {}
	var road_graph = distance_context.get("road_graph", null)
	if road_graph == null:
		return Result.success(per_house)
	var grid_size := _read_grid_size_from_value(distance_context.get("grid_size", Vector2i.ZERO))
	var house_infos: Dictionary = Dictionary(distance_context.get("house_infos", {}))
	var rest_roads := StructureDistanceClass.get_structure_adjacent_roads(state, grid_size, entrance_points)
	if rest_roads.is_empty():
		return Result.success(per_house)
	var rest_entry_cost_by_road := _build_structure_to_road_boundary_cost(entrance_points, rest_roads)
	var road_distance_cache_val = distance_context.get("road_distance_cache", null)
	var road_distance_cache: Dictionary
	if road_distance_cache_val is Dictionary:
		road_distance_cache = road_distance_cache_val
	else:
		road_distance_cache = {}
		distance_context["road_distance_cache"] = road_distance_cache
	for house_id in _sorted_string_keys(house_infos):
		var info_val = house_infos.get(house_id, null)
		if not (info_val is Dictionary):
			continue
		var info: Dictionary = info_val
		var house_roads: Array = Array(info.get("roads", []))
		if house_roads.is_empty():
			continue
		var house_entry_cost_by_road: Dictionary = Dictionary(info.get("entry_cost_by_road", {}))
		var best_distance := INF
		var best_steps := INF
		for start_road in rest_roads:
			var distance_by_pos := _cached_road_distances_from_position(road_graph, start_road, road_distance_cache)
			for target_road in house_roads:
				var path_val = distance_by_pos.get(target_road, null)
				if not (path_val is Dictionary):
					continue
				var path_payload: Dictionary = path_val
				if not path_payload.has("distance"):
					continue
				if not path_payload.has("steps"):
					continue
				var distance := int(path_payload.get("distance", 0))
				distance += int(rest_entry_cost_by_road.get(start_road, 0))
				distance += int(house_entry_cost_by_road.get(target_road, 0))
				var steps := int(path_payload.get("steps", 0))
				if distance < best_distance or (distance == best_distance and steps < best_steps):
					best_distance = distance
					best_steps = steps
		if best_distance < INF:
			per_house[house_id] = {
				"distance": int(best_distance),
				"steps": int(best_steps),
				"path": [],
			}
	return Result.success(per_house)

static func _cached_road_distances_from_position(road_graph, start_pos: Vector2i, cache: Dictionary) -> Dictionary:
	var cached_val = cache.get(start_pos, null)
	if cached_val is Dictionary:
		return cached_val
	var distances := _road_distances_from_position(road_graph, start_pos)
	cache[start_pos] = distances
	return distances

static func _road_distances_from_position(road_graph, start_pos: Vector2i) -> Dictionary:
	var start_nodes := _road_nodes_at_pos(road_graph, start_pos)
	if start_nodes.is_empty():
		return {}
	var dist := {}
	var best_by_pos := {}
	var pq := []
	for start_node in start_nodes:
		dist[start_node] = {"crossings": 0, "steps": 0}
		pq.append({"node": start_node, "crossings": 0, "steps": 0})
	while not pq.is_empty():
		pq.sort_custom(func(a, b):
			if int(a.crossings) != int(b.crossings):
				return int(a.crossings) < int(b.crossings)
			return int(a.steps) < int(b.steps)
		)
		var current: Dictionary = pq.pop_front()
		var current_node := str(current.get("node", ""))
		var current_crossings := int(current.get("crossings", 0))
		var current_steps := int(current.get("steps", 0))
		var current_best: Dictionary = Dictionary(dist.get(current_node, {"crossings": INF, "steps": INF}))
		if current_crossings > int(current_best.get("crossings", INF)):
			continue
		if current_crossings == int(current_best.get("crossings", INF)) and current_steps > int(current_best.get("steps", INF)):
			continue
		var parsed := NodeKeysClass.parse_node_key(current_node)
		if not parsed.is_empty():
			var pos: Vector2i = parsed.get("pos", Vector2i.ZERO)
			var pos_best_val = best_by_pos.get(pos, null)
			if not (pos_best_val is Dictionary) or _road_distance_is_better(current_crossings, current_steps, Dictionary(pos_best_val)):
				best_by_pos[pos] = {"distance": current_crossings, "steps": current_steps}
		var edges_val = road_graph._edges.get(current_node, [])
		if not (edges_val is Array):
			continue
		var edges: Array = edges_val
		for edge_val in edges:
			if not (edge_val is Dictionary):
				continue
			var edge: Dictionary = edge_val
			var neighbor := str(edge.get("to", ""))
			if neighbor == "":
				continue
			var new_steps := current_steps + int(edge.get("weight", 1))
			var new_crossings := current_crossings
			if bool(edge.get("crosses_boundary", false)):
				new_crossings += 1
			var neighbor_best_val = dist.get(neighbor, null)
			if not (neighbor_best_val is Dictionary) or _road_distance_is_better(new_crossings, new_steps, Dictionary(neighbor_best_val)):
				dist[neighbor] = {"crossings": new_crossings, "steps": new_steps}
				pq.append({"node": neighbor, "crossings": new_crossings, "steps": new_steps})
	return best_by_pos

static func _road_nodes_at_pos(road_graph, pos: Vector2i) -> Array[String]:
	var nodes: Array[String] = []
	var seg_idx := 0
	while true:
		var key := NodeKeysClass.make_node_key(pos, seg_idx)
		if road_graph._nodes.has(key):
			nodes.append(key)
			seg_idx += 1
		else:
			break
	return nodes

static func _road_distance_is_better(crossings: int, steps: int, current_best: Dictionary) -> bool:
	var best_crossings := int(current_best.get("crossings", current_best.get("distance", INF)))
	var best_steps := int(current_best.get("steps", INF))
	return crossings < best_crossings or (crossings == best_crossings and steps < best_steps)

static func _read_house_cells(house: Dictionary, house_id: String) -> Result:
	if not house.has("cells") or not (house["cells"] is Array):
		return Result.failure("StrategyBoardAnalyzer: houses[%s].cells is not Array" % house_id)
	var out: Array[Vector2i] = []
	var cells_any: Array = house["cells"]
	for i in range(cells_any.size()):
		var cell_val = cells_any[i]
		if not (cell_val is Vector2i):
			return Result.failure("StrategyBoardAnalyzer: houses[%s].cells[%d] is not Vector2i" % [house_id, i])
		out.append(cell_val)
	return Result.success(out)

static func _build_structure_to_road_boundary_cost(
	structure_cells: Array[Vector2i],
	road_cells: Array[Vector2i]
) -> Dictionary:
	var out := {}
	for road_cell in road_cells:
		var best := INF
		for structure_cell in structure_cells:
			if structure_cell == road_cell:
				best = 0
				break
			if not MapUtilsClass.are_adjacent(structure_cell, road_cell):
				continue
			best = min(best, 1 if MapUtilsClass.crosses_tile_boundary(structure_cell, road_cell) else 0)
		if best == INF:
			best = 0
		out[road_cell] = int(best)
	return out

static func _sorted_string_keys(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in dict.keys():
		out.append(str(key))
	out.sort()
	return out

static func _restaurant_payload_from_analysis(
	state: GameState,
	anchor: Vector2i,
	observation: ObservationState,
	income_analysis: Dictionary,
	analysis: Dictionary,
	candidate_restaurant_id: String,
	existing_owned_ids: Array[String],
	competitor_ids: Array[String]
) -> Dictionary:
	var houses_val = analysis.get("houses", {})
	if not (houses_val is Dictionary):
		return {}
	var grid_size := _read_grid_size_from_value(analysis.get("grid_size", Vector2i.ZERO))
	var houses: Dictionary = houses_val
	var distances_val = analysis.get("restaurant_house_distances", {})
	if not (distances_val is Dictionary):
		return {}
	var distances: Dictionary = distances_val
	if not distances.has(candidate_restaurant_id):
		return {}
	var candidate_distances_val = distances.get(candidate_restaurant_id, {})
	if not (candidate_distances_val is Dictionary):
		return {}
	var candidate_distances: Dictionary = candidate_distances_val

	var nearest_distance := 2147483647
	var nearby_houses := 0
	var nearby_servable_houses := 0
	var nearby_servable_house_ids: Array[String] = []
	var nearby_demand := 0
	var total_demand := 0
	var unserviceable_demand_covered := 0
	var competitive_houses := 0
	var contested_houses := 0
	var competitor_dominated_houses := 0
	var closest_competitor_distance := 2147483647
	var competition_penalty := 0.0
	var house_value := 0.0
	for house_id_val in houses.keys():
		var house_id := str(house_id_val)
		var house_val = houses.get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var demand_count := _house_demand_count(house)
		total_demand += demand_count
		var distance := _distance_for_house(candidate_distances, house_id)
		if distance < 0:
			continue
		nearest_distance = mini(nearest_distance, distance)
		var house_base := maxf(0.0, float(MAX_HEURISTIC_DISTANCE - distance))
		var competitor_distance := _nearest_competitor_road_distance(distances, competitor_ids, house_id)
		if competitor_distance >= 0:
			closest_competitor_distance = mini(closest_competitor_distance, competitor_distance)
		var competition_payload := _restaurant_house_competition(distance, competitor_distance, house_base)
		var value_factor := float(competition_payload.get("value_factor", 1.0))
		var house_competition_penalty := float(competition_payload.get("penalty", 0.0))
		var competition_state := str(competition_payload.get("state", "competitive"))
		competition_penalty += house_competition_penalty
		if house_base > 0.0:
			match competition_state:
				"dominated":
					competitor_dominated_houses += 1
				"contested":
					contested_houses += 1
				_:
					competitive_houses += 1
		if distance <= IDEAL_SERVICE_DISTANCE:
			nearby_houses += 1
			if competition_state != "dominated":
				nearby_servable_houses += 1
				nearby_servable_house_ids.append(house_id)
				nearby_demand += demand_count
		house_value += house_base * 0.75 * value_factor
		house_value += house_competition_penalty
		if demand_count > 0 and competition_state != "dominated":
			house_value += house_base * value_factor * float(demand_count) * 2.0
			if not _house_has_owned_road_distance(distances, existing_owned_ids, house_id):
				unserviceable_demand_covered += demand_count
				house_value += house_base * value_factor * float(demand_count) * 1.25
	var own_restaurants := int(income_analysis.get("own_restaurants", 0))
	if own_restaurants <= 0 and nearby_servable_houses > 0:
		house_value += 10.0
	if total_demand > 0 and nearby_demand <= 0:
		house_value -= 8.0
	var opening_competition_safety_penalty := _opening_competition_safety_penalty(own_restaurants, competitive_houses, contested_houses, competitor_dominated_houses)
	house_value += opening_competition_safety_penalty
	var marketing_launch_payload := _opening_marketing_launch_payload(state, houses, nearby_servable_house_ids, own_restaurants)
	house_value += float(marketing_launch_payload.get("value", 0.0))
	var robustness_payload := _opening_robustness_payload(anchor, grid_size, own_restaurants)
	house_value += float(robustness_payload.get("value", 0.0))
	var nearest := nearest_distance if nearest_distance < 2147483647 else -1
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": nearest,
		"nearby_houses": nearby_houses,
		"nearby_demand": nearby_demand,
		"total_public_demand": total_demand,
		"unserviceable_demand_covered": unserviceable_demand_covered,
		"competitive_houses": competitive_houses,
		"contested_houses": contested_houses,
		"competitor_dominated_houses": competitor_dominated_houses,
		"closest_competitor_distance": closest_competitor_distance if closest_competitor_distance < 2147483647 else -1,
		"competition_penalty": competition_penalty,
		"opening_competition_safety_penalty": opening_competition_safety_penalty,
		"opening_marketing_route_houses": int(marketing_launch_payload.get("route_houses", 0)),
		"opening_marketing_blocked_houses": int(marketing_launch_payload.get("blocked_houses", 0)),
		"opening_marketing_route_board_count": int(marketing_launch_payload.get("route_board_count", 0)),
		"opening_marketing_route_options": int(marketing_launch_payload.get("route_options", 0)),
		"opening_marketing_route_board_ids": Array(marketing_launch_payload.get("route_board_ids", [])).duplicate(),
		"opening_marketing_route_value": float(marketing_launch_payload.get("value", 0.0)),
		"placement_value": house_value,
		"distance_source": "road_graph",
		"opening_robustness_value": float(robustness_payload.get("value", 0.0)),
		"opening_center_distance": float(robustness_payload.get("center_distance", -1.0)),
		"opening_edge_distance": int(robustness_payload.get("edge_distance", -1)),
	}

static func _opening_marketing_launch_payload(
	state: GameState,
	houses: Dictionary,
	serviceable_house_ids: Array[String],
	own_restaurants: int
) -> Dictionary:
	var out := {
		"route_houses": 0,
		"blocked_houses": 0,
		"route_board_count": 0,
		"route_options": 0,
		"route_board_ids": [],
		"value": 0.0,
	}
	if state == null or own_restaurants > 0 or serviceable_house_ids.is_empty():
		return out
	if not MarketingRegistryClass.is_loaded():
		return out
	var billboard_defs := _opening_billboard_defs(state)
	if billboard_defs.is_empty():
		return out

	var route_houses := 0
	var blocked_houses := 0
	var route_options := 0
	var route_board_ids: Array[int] = []
	for house_id in serviceable_house_ids:
		var house_val = _house_value_by_string_id(houses, house_id)
		if not (house_val is Dictionary):
			continue
		var board_ids := _launchable_opening_billboard_ids_for_house(state, Dictionary(house_val), billboard_defs)
		if not board_ids.is_empty():
			route_houses += 1
			route_options += board_ids.size()
			for board_id in board_ids:
				if not route_board_ids.has(board_id):
					route_board_ids.append(board_id)
		else:
			blocked_houses += 1

	var value := float(route_houses) * OPENING_MARKETING_ROUTE_VALUE
	route_board_ids.sort()
	value += float(route_options) * 1.5 + float(route_board_ids.size()) * 3.0
	if route_houses <= 0 and blocked_houses > 0:
		value += OPENING_NO_MARKETING_ROUTE_PENALTY
	elif route_board_ids.size() <= 1:
		value += OPENING_SINGLE_MARKETING_ROUTE_PENALTY
	out["route_houses"] = route_houses
	out["blocked_houses"] = blocked_houses
	out["route_board_count"] = route_board_ids.size()
	out["route_options"] = route_options
	out["route_board_ids"] = route_board_ids.duplicate()
	out["value"] = value
	return out

static func _house_value_by_string_id(houses: Dictionary, house_id: String):
	if houses.has(house_id):
		return houses.get(house_id, null)
	for key in houses.keys():
		if str(key) == house_id:
			return houses.get(key, null)
	return null

static func _opening_billboard_defs(state: GameState) -> Array[MarketingDef]:
	var out: Array[MarketingDef] = []
	if state == null or not MarketingRegistryClass.is_loaded():
		return out
	var player_count := state.players.size()
	for board_number in MarketingRegistryClass.get_all_board_numbers():
		var def_val = MarketingRegistryClass.get_def(int(board_number))
		if not (def_val is MarketingDef):
			continue
		var board_def: MarketingDef = def_val
		if str(board_def.type) != "billboard":
			continue
		if board_def.has_method("is_available_for_player_count") and not board_def.is_available_for_player_count(player_count):
			continue
		out.append(board_def)
	return out

static func _launchable_opening_billboard_ids_for_house(
	state: GameState,
	house: Dictionary,
	billboard_defs: Array[MarketingDef]
) -> Array[int]:
	var out: Array[int] = []
	var house_cells := _opening_house_cells(house)
	if house_cells.is_empty():
		return out
	for board_def in billboard_defs:
		for rotation in [0, 90, 180, 270]:
			var size_read := MarketingRulesClass.get_rotated_footprint_size(Vector2i(board_def.footprint_size), int(rotation))
			if not size_read.ok:
				continue
			var size: Vector2i = size_read.value
			for house_cell in house_cells:
				for dy in range(size.y):
					for dx in range(size.x):
						for dir in MapUtilsClass.DIRECTIONS:
							var footprint_cell := MapUtilsClass.get_neighbor_pos(house_cell, dir)
							var anchor := footprint_cell - Vector2i(dx, dy)
							var footprint_cells := MarketingRulesClass.build_footprint_cells(anchor, size)
							if not _is_valid_opening_marketing_footprint(state, footprint_cells):
								continue
							if _billboard_footprint_affects_house_cells(footprint_cells, house_cells):
								var board_number := int(board_def.board_number)
								if not out.has(board_number):
									out.append(board_number)
	out.sort()
	return out

static func _opening_house_cells(house: Dictionary) -> Array[Vector2i]:
	var cells := _read_vector2i_array(house.get("cells", []))
	if not cells.is_empty():
		return cells
	return [_read_vector2i(house.get("anchor_pos", Vector2i.ZERO))]

static func _is_valid_opening_marketing_footprint(state: GameState, footprint_cells: Array[Vector2i]) -> bool:
	if state == null or footprint_cells.is_empty():
		return false
	var footprint_set := {}
	for cell_pos in footprint_cells:
		if not CoordsClass.is_world_pos_in_grid(state, cell_pos):
			return false
		var cell := CellsClass.get_cell(state, cell_pos)
		if cell.is_empty():
			return false
		var structure_val = cell.get("structure", null)
		if structure_val is Dictionary and not Dictionary(structure_val).is_empty():
			return false
		var drink_source_val = cell.get("drink_source", null)
		if drink_source_val != null and (not (drink_source_val is Dictionary) or not Dictionary(drink_source_val).is_empty()):
			return false
		if bool(cell.get("blocked", false)):
			return false
		var road_segments_val = cell.get("road_segments", [])
		if road_segments_val is Array and not Array(road_segments_val).is_empty():
			return false
		footprint_set[cell_pos] = true
	if _opening_marketing_overlaps_existing(state, footprint_set):
		return false
	var has_adjacent_road := false
	for cell_pos2 in footprint_cells:
		for dir in MapUtilsClass.DIRECTIONS:
			var neighbor := MapUtilsClass.get_neighbor_pos(cell_pos2, dir)
			if footprint_set.has(neighbor):
				continue
			if not CoordsClass.is_world_pos_in_grid(state, neighbor):
				continue
			if CellsClass.has_road_at(state, neighbor):
				has_adjacent_road = true
				break
		if has_adjacent_road:
			break
	return has_adjacent_road

static func _opening_marketing_overlaps_existing(state: GameState, footprint_set: Dictionary) -> bool:
	if state == null or footprint_set.is_empty() or not (state.map is Dictionary):
		return false
	var placements_val = state.map.get("marketing_placements", {})
	if not (placements_val is Dictionary):
		return false
	var placements: Dictionary = placements_val
	for placement_val in placements.values():
		if not (placement_val is Dictionary):
			continue
		var placement: Dictionary = placement_val
		if str(placement.get("type", "")) == "airplane":
			continue
		for cell_pos in _marketing_placement_footprint_cells(placement):
			if footprint_set.has(cell_pos):
				return true
	return false

static func _marketing_placement_footprint_cells(placement: Dictionary) -> Array[Vector2i]:
	var board_number := int(placement.get("board_number", -1))
	var footprint_size := _read_vector2i(placement.get("footprint_size", Vector2i.ZERO))
	if footprint_size.x <= 0 or footprint_size.y <= 0:
		if board_number > 0 and MarketingRegistryClass.is_loaded():
			var def_val = MarketingRegistryClass.get_def(board_number)
			if def_val is MarketingDef:
				footprint_size = Vector2i((def_val as MarketingDef).footprint_size)
	if footprint_size.x <= 0 or footprint_size.y <= 0:
		return []
	var rotation := int(placement.get("rotation", 0))
	var size_read := MarketingRulesClass.get_rotated_footprint_size(footprint_size, rotation)
	if not size_read.ok:
		return []
	var world_pos := _read_vector2i(placement.get("world_pos", placement.get("position", Vector2i.ZERO)))
	return MarketingRulesClass.build_footprint_cells(world_pos, size_read.value)

static func _billboard_footprint_affects_house_cells(
	footprint_cells: Array[Vector2i],
	house_cells: Array[Vector2i]
) -> bool:
	if footprint_cells.is_empty() or house_cells.is_empty():
		return false
	var house_set := {}
	for house_cell in house_cells:
		house_set[house_cell] = true
	for cell_pos in footprint_cells:
		for dir in MapUtilsClass.DIRECTIONS:
			var neighbor := MapUtilsClass.get_neighbor_pos(cell_pos, dir)
			if house_set.has(neighbor):
				return true
	return false

static func _opening_robustness_payload(anchor: Vector2i, grid_size: Vector2i, own_restaurants: int) -> Dictionary:
	if own_restaurants > 0 or grid_size.x <= 1 or grid_size.y <= 1:
		return {
			"value": 0.0,
			"center_distance": -1.0,
			"edge_distance": -1,
		}
	var center := Vector2(float(grid_size.x - 1) * 0.5, float(grid_size.y - 1) * 0.5)
	var center_distance := absf(float(anchor.x) - center.x) + absf(float(anchor.y) - center.y)
	var max_center_distance := center.x + center.y
	var center_value := maxf(0.0, max_center_distance - center_distance) * OPENING_CENTER_WEIGHT
	var edge_distance := mini(mini(anchor.x, anchor.y), mini(grid_size.x - 1 - anchor.x, grid_size.y - 1 - anchor.y))
	var edge_penalty := 0.0
	if edge_distance <= 0:
		edge_penalty = OPENING_EDGE_PENALTY
	elif edge_distance == 1:
		edge_penalty = OPENING_NEAR_EDGE_PENALTY
	return {
		"value": center_value + edge_penalty,
		"center_distance": center_distance,
		"edge_distance": edge_distance,
	}

static func _distance_for_house(per_restaurant_distances: Dictionary, house_id: String) -> int:
	var info_val = per_restaurant_distances.get(house_id, null)
	if not (info_val is Dictionary):
		return -1
	var info: Dictionary = info_val
	if not info.has("distance"):
		return -1
	return int(info.get("distance", -1))

static func _restaurant_house_competition(distance: int, competitor_distance: int, house_base: float) -> Dictionary:
	if competitor_distance < 0:
		return {
			"state": "competitive",
			"value_factor": 1.0,
			"penalty": 0.0,
		}
	if competitor_distance < distance:
		return {
			"state": "dominated",
			"value_factor": RESTAURANT_DOMINATED_HOUSE_VALUE_FACTOR,
			"penalty": -house_base * RESTAURANT_DOMINATED_HOUSE_PENALTY_FACTOR,
		}
	if competitor_distance == distance:
		return {
			"state": "contested",
			"value_factor": RESTAURANT_CONTESTED_HOUSE_VALUE_FACTOR,
			"penalty": -house_base * RESTAURANT_CONTESTED_HOUSE_PENALTY_FACTOR,
		}
	return {
		"state": "competitive",
		"value_factor": 1.0,
		"penalty": 0.0,
	}

static func _expansion_capture_risk(own_distance: int, competitor_distance: int, unit_price: int, at_risk_units: int, action_id: String) -> Dictionary:
	var safe_units := maxi(1, at_risk_units)
	var revenue_basis := float(maxi(1, unit_price) * safe_units)
	var is_garden := action_id == "add_garden"
	var pressured_floor := GARDEN_PRESSURED_MIN_PENALTY if is_garden else HOUSE_PRESSURED_MIN_PENALTY
	var contested_floor := GARDEN_CONTESTED_MIN_PENALTY if is_garden else HOUSE_CONTESTED_MIN_PENALTY
	var dominated_floor := GARDEN_DOMINATED_MIN_PENALTY if is_garden else HOUSE_DOMINATED_MIN_PENALTY
	var opponent_only_floor := GARDEN_OPPONENT_ONLY_MIN_PENALTY if is_garden else HOUSE_OPPONENT_ONLY_MIN_PENALTY
	var out := {
		"capture_state": "self_capture",
		"value_factor": 1.0,
		"opponent_capture_risk": 0.0,
		"opponent_subsidy_penalty": 0.0,
	}
	if own_distance < 0:
		if competitor_distance >= 0:
			out["capture_state"] = "opponent_only"
			out["value_factor"] = 0.0
			out["opponent_capture_risk"] = revenue_basis
			out["opponent_subsidy_penalty"] = -maxf(opponent_only_floor, revenue_basis * 0.9)
		else:
			out["capture_state"] = "unserviceable"
		return out
	if competitor_distance < 0:
		return out
	if competitor_distance < own_distance:
		var distance_gap := maxi(1, own_distance - competitor_distance)
		out["capture_state"] = "opponent_dominated"
		out["value_factor"] = EXPANSION_DOMINATED_VALUE_FACTOR
		out["opponent_capture_risk"] = revenue_basis
		out["opponent_subsidy_penalty"] = -maxf(dominated_floor, revenue_basis * (0.75 + minf(0.25, float(distance_gap) * 0.05)))
	elif competitor_distance == own_distance:
		out["capture_state"] = "contested"
		out["value_factor"] = EXPANSION_CONTESTED_VALUE_FACTOR
		out["opponent_capture_risk"] = revenue_basis * 0.5
		out["opponent_subsidy_penalty"] = -maxf(contested_floor, revenue_basis * 0.35)
	elif competitor_distance <= own_distance + EXPANSION_PRESSURED_DISTANCE_MARGIN:
		out["capture_state"] = "pressured"
		out["value_factor"] = EXPANSION_PRESSURED_VALUE_FACTOR
		out["opponent_capture_risk"] = revenue_basis * 0.25
		out["opponent_subsidy_penalty"] = -maxf(pressured_floor, revenue_basis * 0.12)
	return out

static func _opening_competition_safety_penalty(own_restaurants: int, competitive_houses: int, contested_houses: int, competitor_dominated_houses: int) -> float:
	if own_restaurants > 0:
		return 0.0
	var penalty := float(contested_houses) * OPENING_CONTESTED_HOUSE_SAFETY_PENALTY
	penalty += float(competitor_dominated_houses) * OPENING_DOMINATED_HOUSE_SAFETY_PENALTY
	if competitive_houses <= 0 and (contested_houses > 0 or competitor_dominated_houses > 0):
		penalty += OPENING_NO_INDEPENDENT_ROUTE_PENALTY
	elif competitive_houses == 1 and (contested_houses > 0 or competitor_dominated_houses > 0):
		penalty += OPENING_LOW_INDEPENDENT_ROUTE_PENALTY
	return penalty

static func _nearest_competitor_road_distance(
	distances: Dictionary,
	competitor_ids: Array[String],
	house_id: String
) -> int:
	var best := 2147483647
	for restaurant_id in competitor_ids:
		var per_rest_val = distances.get(restaurant_id, null)
		if not (per_rest_val is Dictionary):
			continue
		var distance := _distance_for_house(per_rest_val, house_id)
		if distance >= 0:
			best = mini(best, distance)
	return best if best < 2147483647 else -1

static func _house_has_owned_road_distance(
	distances: Dictionary,
	owned_restaurant_ids: Array[String],
	house_id: String
) -> bool:
	for restaurant_id in owned_restaurant_ids:
		var per_rest_val = distances.get(restaurant_id, null)
		if not (per_rest_val is Dictionary):
			continue
		if _distance_for_house(per_rest_val, house_id) >= 0:
			return true
	return false

static func _empty_restaurant_payload(anchor: Vector2i) -> Dictionary:
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": -1,
		"nearby_houses": 0,
		"nearby_demand": 0,
		"total_public_demand": 0,
		"unserviceable_demand_covered": 0,
		"competitive_houses": 0,
		"contested_houses": 0,
		"competitor_dominated_houses": 0,
		"closest_competitor_distance": -1,
		"competition_penalty": 0.0,
		"opening_competition_safety_penalty": 0.0,
		"opening_marketing_route_houses": 0,
		"opening_marketing_blocked_houses": 0,
		"opening_marketing_route_value": 0.0,
		"placement_value": 0.0,
		"distance_source": "anchor",
		"opening_robustness_value": 0.0,
		"opening_center_distance": -1.0,
		"opening_edge_distance": -1,
	}

static func _empty_garden_payload(house_id: String) -> Dictionary:
	return {
		"house_id": house_id,
		"has_garden": false,
		"demand_count": 0,
		"estimated_sale_units": 0,
		"raw_estimated_sale_units": 0,
		"unit_price": 0,
		"unit_price_source": "observation",
		"revenue_delta_estimate": 0,
		"demand_cap_normal": 0,
		"demand_cap_with_garden": 0,
		"cap_unlock_units": 0,
		"cap_value": 0.0,
		"service_distance": -1,
		"service_value": 0.0,
		"competitor_service_distance": -1,
		"raw_value": 0.0,
		"capture_state": "self_capture",
		"capture_value_factor": 1.0,
		"opponent_capture_risk": 0.0,
		"opponent_subsidy_penalty": 0.0,
		"competition_adjustment": 0.0,
		"value": 0.0,
	}

static func _house_demand_count(house: Dictionary) -> int:
	var demands_val = house.get("demands", [])
	if demands_val is Array:
		return Array(demands_val).size()
	return 0

static func _house_demand_product_counts(house: Dictionary) -> Dictionary:
	var out := {}
	var demands_val = house.get("demands", [])
	if not (demands_val is Array):
		return out
	for demand_val in Array(demands_val):
		var product_id := _demand_product_id(demand_val)
		if product_id.is_empty():
			continue
		out[product_id] = int(out.get(product_id, 0)) + 1
	return out

static func _demand_product_id(value) -> String:
	if value is Dictionary:
		var demand: Dictionary = value
		var product_id := str(demand.get("product", demand.get("product_id", ""))).strip_edges()
		return product_id
	return str(value).strip_edges()

static func _estimate_house_sale_units(house: Dictionary, income_analysis: Dictionary) -> int:
	var demand_count := _house_demand_count(house)
	if demand_count <= 0:
		return 0
	var product_counts := _house_demand_product_counts(house)
	if product_counts.is_empty():
		return demand_count if int(income_analysis.get("total_actionable_demand", 0)) > 0 else 0
	var products: Dictionary = Dictionary(income_analysis.get("products", {}))
	var estimated := 0
	for product_id in _sorted_string_keys(product_counts):
		var needed := int(product_counts.get(product_id, 0))
		if needed <= 0:
			continue
		var product: Dictionary = Dictionary(products.get(product_id, {}))
		if product.is_empty():
			continue
		var actionable := maxi(0, int(product.get("actionable_demand", product.get("serviceable_demand", 0))))
		var inventory := maxi(0, int(product.get("inventory_units", 0)))
		var can_supply := bool(product.get("can_supply", false))
		var ready_units := inventory
		if can_supply:
			ready_units = maxi(ready_units, actionable)
		if ready_units > 0:
			estimated += needed
	return mini(demand_count, estimated)

static func _current_unit_price_payload(observation: ObservationState, source_state, player_id: int) -> Dictionary:
	if source_state is GameState and player_id >= 0:
		var pipeline_read := PricingPipelineClass.calculate_unit_price(source_state, player_id)
		if pipeline_read.ok:
			return {
				"unit_price": int(pipeline_read.value),
				"source": "pricing_pipeline",
			}
	return {
		"unit_price": _fallback_current_unit_price(observation, player_id),
		"source": "observation",
	}

static func _fallback_current_unit_price(observation: ObservationState, player_id: int) -> int:
	if observation == null:
		return 10
	var unit_price := _read_positive_int(observation.rules_public.get("base_unit_price", 10), 10)
	unit_price += _base_price_delta(observation)
	unit_price += _price_modifier_total_from_round_state(observation.round_state_public, player_id)
	return maxi(0, unit_price)

static func _base_price_delta(observation: ObservationState) -> int:
	if observation == null:
		return 0
	var milestones := _sorted_unique_strings(observation.own_player.get("milestones", []))
	var delta_read := MilestoneEffectQueriesClass.sum_int_values(
		milestones,
		"base_price_delta",
		"StrategyBoardAnalyzer: ",
		"milestones"
	)
	if delta_read.ok:
		return int(delta_read.value)
	return 0

static func _price_modifier_total_from_round_state(round_state: Dictionary, player_id: int) -> int:
	if player_id < 0:
		return 0
	var modifiers_val = round_state.get("price_modifiers", {})
	if not (modifiers_val is Dictionary):
		return 0
	var price_modifiers: Dictionary = modifiers_val
	var player_modifiers_val = price_modifiers.get(player_id, price_modifiers.get(str(player_id), {}))
	if not (player_modifiers_val is Dictionary):
		return 0
	var total := 0
	for value in Dictionary(player_modifiers_val).values():
		if value is int:
			total += int(value)
	return total

static func _read_positive_int(value, fallback: int) -> int:
	var out := fallback
	if value is int:
		out = int(value)
	elif value is float:
		out = int(value)
	elif value is String and str(value).is_valid_int():
		out = int(str(value))
	return maxi(0, out)

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

static func _min_house_distance_to_competitor_restaurant(observation: ObservationState, house_id: String) -> int:
	if observation == null or house_id.is_empty():
		return -1
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return -1
	var house_val = Dictionary(houses_val).get(house_id, null)
	if not (house_val is Dictionary):
		return -1
	var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
	return _nearest_distance_to_competitor_restaurant_anchor(observation, house_anchor)

static func _nearest_distance_to_owned_restaurant_anchor(observation: ObservationState, pos: Vector2i) -> int:
	if observation == null:
		return -1
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var restaurants: Dictionary = restaurants_val
	var best := 2147483647
	for restaurant_id in _sorted_unique_strings(observation.own_player.get("restaurants", [])):
		var rest_val = restaurants.get(restaurant_id, null)
		if not (rest_val is Dictionary):
			continue
		var rest_anchor := _read_vector2i(Dictionary(rest_val).get("anchor_pos", Vector2i.ZERO))
		best = mini(best, absi(pos.x - rest_anchor.x) + absi(pos.y - rest_anchor.y))
	return best if best < 2147483647 else -1

static func _nearest_distance_to_house_anchor(observation: ObservationState, pos: Vector2i) -> int:
	if observation == null:
		return -1
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return -1
	var best := 2147483647
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
		best = mini(best, absi(pos.x - house_anchor.x) + absi(pos.y - house_anchor.y))
	return best if best < 2147483647 else -1

static func _nearest_distance_to_competitor_restaurant_anchor(observation: ObservationState, pos: Vector2i) -> int:
	if observation == null:
		return -1
	var restaurants_val = observation.map_public.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var restaurants: Dictionary = restaurants_val
	var own_ids := _sorted_unique_strings(observation.own_player.get("restaurants", []))
	var player_id := int(observation.viewer_player_id)
	var best := 2147483647
	for restaurant_id_val in restaurants.keys():
		var restaurant_id := str(restaurant_id_val)
		if own_ids.has(restaurant_id):
			continue
		var rest_val = restaurants.get(restaurant_id_val, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var owner := int(rest.get("owner", -1))
		if owner < 0 or owner == player_id:
			continue
		var rest_anchor := _read_vector2i(rest.get("anchor_pos", Vector2i.ZERO))
		best = mini(best, absi(pos.x - rest_anchor.x) + absi(pos.y - rest_anchor.y))
	return best if best < 2147483647 else -1

static func _owned_restaurant_ids(observation: ObservationState, state: GameState, player_id: int) -> Array[String]:
	if observation != null:
		return _sorted_unique_strings(observation.own_player.get("restaurants", []))
	if state != null and player_id >= 0 and player_id < state.players.size():
		var player_val = state.players[player_id]
		if player_val is Dictionary:
			return _sorted_unique_strings(Dictionary(player_val).get("restaurants", []))
	return []

static func _competitor_restaurant_ids(state: GameState, player_id: int, excluded_id: String = "") -> Array[String]:
	var out: Array[String] = []
	if state == null or not (state.map is Dictionary):
		return out
	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return out
	var restaurants: Dictionary = restaurants_val
	for restaurant_id_val in restaurants.keys():
		var restaurant_id := str(restaurant_id_val)
		if not excluded_id.is_empty() and restaurant_id == excluded_id:
			continue
		var rest_val = restaurants.get(restaurant_id_val, null)
		if not (rest_val is Dictionary):
			continue
		var owner := int(Dictionary(rest_val).get("owner", -1))
		if owner >= 0 and owner != player_id:
			out.append(restaurant_id)
	out.sort()
	return out

static func _candidate_restaurant_id(state: GameState) -> String:
	var restaurants_val = state.map.get("restaurants", {}) if state != null else {}
	var restaurants: Dictionary = restaurants_val if restaurants_val is Dictionary else {}
	var base_id := "__strategy_candidate_restaurant__"
	var candidate_id := base_id
	var index := 1
	while restaurants.has(candidate_id):
		candidate_id = "%s_%d" % [base_id, index]
		index += 1
	return candidate_id

static func _add_player_restaurant_id(state: GameState, player_id: int, restaurant_id: String) -> void:
	if state == null or restaurant_id.is_empty():
		return
	if player_id < 0 or player_id >= state.players.size():
		return
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return
	var player: Dictionary = player_val
	var restaurants: Array = []
	var restaurants_val = player.get("restaurants", [])
	if restaurants_val is Array:
		restaurants = Array(restaurants_val).duplicate()
	if not restaurants.has(restaurant_id):
		restaurants.append(restaurant_id)
	player["restaurants"] = restaurants
	state.players[player_id] = player

static func _write_restaurant_cells(
	state: GameState,
	restaurant_id: String,
	player_id: int,
	anchor: Vector2i,
	rotation: int,
	footprint_cells: Array[Vector2i]
) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var cells_val = state.map.get("cells", [])
	if not (cells_val is Array):
		return
	var cells: Array = cells_val
	for cell_pos in footprint_cells:
		var idx := CoordsClass.world_to_index(state, cell_pos)
		if idx.y < 0 or idx.y >= cells.size():
			continue
		var row_val = cells[idx.y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		if idx.x < 0 or idx.x >= row.size():
			continue
		var cell_val = row[idx.x]
		if not (cell_val is Dictionary):
			continue
		var cell: Dictionary = cell_val
		cell["structure"] = {
			"piece_id": "restaurant",
			"owner": player_id,
			"anchor_cell": cell_pos == anchor,
			"parent_anchor": anchor,
			"rotation": rotation,
			"restaurant_id": restaurant_id,
			"dynamic": true,
		}
		row[idx.x] = cell
		cells[idx.y] = row
	state.map["cells"] = cells

static func _clear_structure_cells(state: GameState, footprint_cells: Array[Vector2i]) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var cells_val = state.map.get("cells", [])
	if not (cells_val is Array):
		return
	var cells: Array = cells_val
	for cell_pos in footprint_cells:
		var idx := CoordsClass.world_to_index(state, cell_pos)
		if idx.y < 0 or idx.y >= cells.size():
			continue
		var row_val = cells[idx.y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		if idx.x < 0 or idx.x >= row.size():
			continue
		var cell_val = row[idx.x]
		if not (cell_val is Dictionary):
			continue
		var cell: Dictionary = cell_val
		cell["structure"] = {}
		row[idx.x] = cell
		cells[idx.y] = row
	state.map["cells"] = cells

static func _read_vector2i_array(value) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not (value is Array):
		return out
	for item in Array(value):
		if item is Vector2i:
			out.append(Vector2i(item))
		elif item is Vector2:
			var v2: Vector2 = item
			out.append(Vector2i(int(v2.x), int(v2.y)))
		elif item is Array:
			var arr: Array = item
			if arr.size() >= 2:
				out.append(Vector2i(int(arr[0]), int(arr[1])))
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

static func _read_grid_size(map_public: Dictionary) -> Vector2i:
	return _read_grid_size_from_value(map_public.get("grid_size", Vector2i.ZERO))

static func _read_grid_size_from_value(value) -> Vector2i:
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
