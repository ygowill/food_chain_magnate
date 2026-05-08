class_name MarketingPressureAnalyzer
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")

static func analyze_candidate(
	observation: ObservationState,
	affected_house_ids: Array[String],
	product_id: String,
	source_state = null,
	source_analysis: Dictionary = {}
) -> Dictionary:
	if source_state is GameState:
		var road_payload := {}
		if not source_analysis.is_empty():
			road_payload = _pressure_from_analysis(source_state, observation, affected_house_ids, product_id, source_analysis)
		else:
			road_payload = _pressure_from_source(source_state, observation, affected_house_ids, product_id)
		if not road_payload.is_empty():
			return _finalize(road_payload)
	return _finalize(_pressure_from_observation(observation, affected_house_ids, product_id))

static func product_pressure_prior(source_state: GameState, observation: ObservationState, product_id: String, source_analysis: Dictionary = {}) -> int:
	if source_state == null or observation == null or product_id.is_empty():
		return 0
	var analysis: Dictionary = source_analysis
	if analysis.is_empty():
		var analysis_read := BoardAnalyzerClass.analyze_state(source_state)
		if not analysis_read.ok:
			return 0
		analysis = analysis_read.value
	if not bool(analysis.get("road_graph_available", false)):
		return 0
	var distances: Dictionary = Dictionary(analysis.get("restaurant_house_distances", {}))
	var houses: Dictionary = Dictionary(analysis.get("houses", {}))
	var player_id := int(observation.viewer_player_id)
	var total := 0
	for house_id_val in houses.keys():
		var house_id := str(house_id_val)
		var house_val = houses.get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		var gap := _opponent_capacity_gap_for_house(source_state, distances, house_id, Dictionary(house_val), product_id, player_id)
		if gap.is_empty():
			continue
		total += int(gap.get("prevented_sales", 0))
	return total

static func current_demand_pressure_by_product(source_state: GameState, observation: ObservationState, source_analysis: Dictionary = {}, own_price_delta: int = 0) -> Dictionary:
	var out := {}
	if source_state == null or observation == null:
		return out
	var analysis: Dictionary = source_analysis
	if analysis.is_empty():
		var analysis_read := BoardAnalyzerClass.analyze_state(source_state)
		if not analysis_read.ok:
			return out
		analysis = analysis_read.value
	if not bool(analysis.get("road_graph_available", false)):
		return out
	var distances: Dictionary = Dictionary(analysis.get("restaurant_house_distances", {}))
	var houses: Dictionary = Dictionary(analysis.get("houses", {}))
	var own_restaurant_ids := _sorted_unique_strings(observation.own_player.get("restaurants", []))
	var player_id := int(observation.viewer_player_id)
	for house_id_val in houses.keys():
		var house_id := str(house_id_val)
		var house_val = houses.get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var required := _required_from_house(house)
		if required.is_empty():
			continue
		var source_counts_by_product := _demand_source_counts_by_product(house, player_id)
		var own_blocking_by_product := _own_sourced_opponent_blocking_by_product(source_state, distances, house_id, house, required, source_counts_by_product, player_id)
		var best_for_house := 2147483647
		for restaurant_id in own_restaurant_ids:
			var per_rest: Dictionary = Dictionary(distances.get(restaurant_id, {}))
			var info: Dictionary = Dictionary(per_rest.get(house_id, {}))
			if not info.has("distance"):
				continue
			best_for_house = mini(best_for_house, int(info.get("distance", 2147483647)))
		var competitor := _best_planned_offer_for_required(source_state, distances, house_id, house, required, player_id, "opponent")
		var own_offer := {}
		if best_for_house < 2147483647:
			own_offer = {
				"owner": player_id,
				"distance": best_for_house,
				"score": best_for_house + _decision_unit_price_for_required(source_state, player_id, house, required) + own_price_delta,
			}
		var own_can_win_full_order := false
		if not own_offer.is_empty():
			own_can_win_full_order = competitor.is_empty() or _planned_offer_beats_or_ties(source_state, own_offer, competitor)
		for product_key in required.keys():
			var product_id := str(product_key)
			if product_id.is_empty():
				continue
			var amount := maxi(0, int(required.get(product_key, 0)))
			if amount <= 0:
				continue
			var source_counts: Dictionary = Dictionary(source_counts_by_product.get(product_id, {}))
			var own_sourced_amount := maxi(0, int(source_counts.get("own", 0)))
			var opponent_sourced_amount := maxi(0, int(source_counts.get("opponent", 0)))
			var neutral_sourced_amount := maxi(0, amount - own_sourced_amount - opponent_sourced_amount)
			var product: Dictionary = Dictionary(out.get(product_id, {}))
			if product.is_empty():
				product = {
					"public_demand": 0,
					"unserviceable_demand": 0,
					"serviceable_demand": 0,
					"competitive_demand": 0,
					"lost_to_competitor_demand": 0,
					"own_sourced_demand": 0,
					"opponent_sourced_demand": 0,
					"neutral_sourced_demand": 0,
					"own_sourced_serviceable_demand": 0,
					"own_sourced_competitive_demand": 0,
					"own_sourced_lost_to_competitor_demand": 0,
					"own_sourced_opponent_blocking_demand": 0,
				}
			product["public_demand"] = int(product.get("public_demand", 0)) + amount
			product["own_sourced_demand"] = int(product.get("own_sourced_demand", 0)) + own_sourced_amount
			product["opponent_sourced_demand"] = int(product.get("opponent_sourced_demand", 0)) + opponent_sourced_amount
			product["neutral_sourced_demand"] = int(product.get("neutral_sourced_demand", 0)) + neutral_sourced_amount
			if best_for_house >= 2147483647:
				product["unserviceable_demand"] = int(product.get("unserviceable_demand", 0)) + amount
				out[product_id] = product
				continue
			product["serviceable_demand"] = int(product.get("serviceable_demand", 0)) + amount
			product["own_sourced_serviceable_demand"] = int(product.get("own_sourced_serviceable_demand", 0)) + own_sourced_amount
			product["own_sourced_opponent_blocking_demand"] = int(product.get("own_sourced_opponent_blocking_demand", 0)) + maxi(0, int(own_blocking_by_product.get(product_id, 0)))
			if own_can_win_full_order:
				product["competitive_demand"] = int(product.get("competitive_demand", 0)) + amount
				product["own_sourced_competitive_demand"] = int(product.get("own_sourced_competitive_demand", 0)) + own_sourced_amount
			else:
				product["lost_to_competitor_demand"] = int(product.get("lost_to_competitor_demand", 0)) + amount
				product["own_sourced_lost_to_competitor_demand"] = int(product.get("own_sourced_lost_to_competitor_demand", 0)) + own_sourced_amount
			out[product_id] = product
	return out

static func discard_reason(pressure: Dictionary) -> String:
	var strategic := int(pressure.get("strategic_houses", 0))
	if strategic <= 0:
		if int(pressure.get("self_supply_blocked_houses", 0)) > 0:
			return "marketing cannot be supplied"
		if int(pressure.get("lost_to_competitor_houses", 0)) > 0:
			return "affected houses are captured by competitor restaurants"
		if int(pressure.get("restaurant_dominated_houses", 0)) > 0:
			return "affected houses are captured by competitor restaurant routes"
		if int(pressure.get("affected_houses", 0)) <= 0:
			return "affects no houses"
		return "affects no strategically useful houses"
	var self_capture := int(pressure.get("self_capture_houses", pressure.get("competitive_houses", 0)))
	var opponent_pressure := int(pressure.get("opponent_pressure_houses", pressure.get("opponent_capacity_gap_houses", 0)))
	if self_capture <= 0 and opponent_pressure <= 0:
		return "affects no strategically useful houses"
	if self_capture > 0:
		var inventory_units := int(pressure.get("inventory_units", 0))
		var can_supply := bool(pressure.get("can_supply_product", false))
		var can_future_supply := bool(pressure.get("can_future_supply_product", can_supply))
		if inventory_units <= 0 and not can_supply and not can_future_supply:
			return "marketing cannot be supplied"
	return ""

static func _pressure_from_observation(observation: ObservationState, affected_house_ids: Array[String], product_id: String) -> Dictionary:
	var serviceable := 0
	var closest_distance := 2147483647
	var total_distance := 0
	var serviceable_ids: Array[String] = []
	for house_id in affected_house_ids:
		var distance := _min_house_distance_to_owned_restaurant(observation, house_id)
		if distance < 0:
			continue
		serviceable += 1
		serviceable_ids.append(house_id)
		closest_distance = mini(closest_distance, distance)
		total_distance += distance
	var average_distance := -1.0
	if serviceable > 0:
		average_distance = float(total_distance) / float(serviceable)
	return {
		"affected_houses": affected_house_ids.size(),
		"affected_house_ids": affected_house_ids.duplicate(),
		"serviceable_houses": serviceable,
		"serviceable_house_ids": serviceable_ids.duplicate(),
		"competitive_houses": serviceable,
		"competitive_house_ids": serviceable_ids.duplicate(),
		"contested_houses": 0,
		"contested_house_ids": [],
		"restaurant_dominated_houses": 0,
		"restaurant_dominated_house_ids": [],
		"lost_to_competitor_houses": 0,
		"lost_to_competitor_house_ids": [],
		"opponent_capacity_gap_houses": 0,
		"opponent_capacity_gap_house_ids": [],
		"opponent_capacity_gap_prevented_sales": 0,
		"opponent_capacity_gap_owner_ids": [],
		"opponent_capacity_gap_products": [],
		"closest_distance": closest_distance if serviceable > 0 else -1,
		"closest_competitor_distance": -1,
		"average_distance": average_distance,
		"inventory_units": _inventory_count(observation, product_id),
		"can_supply_product": _can_actively_supply_product(observation, product_id),
		"can_future_supply_product": _can_supply_product(observation, product_id),
		"own_restaurants": _own_restaurant_count(observation),
		"distance_source": "anchor",
	}

static func _pressure_from_source(source_state: GameState, observation: ObservationState, affected_house_ids: Array[String], product_id: String) -> Dictionary:
	var analysis_read := BoardAnalyzerClass.analyze_state(source_state)
	if not analysis_read.ok:
		return {}
	var analysis: Dictionary = analysis_read.value
	return _pressure_from_analysis(source_state, observation, affected_house_ids, product_id, analysis)

static func _pressure_from_analysis(
	source_state: GameState,
	observation: ObservationState,
	affected_house_ids: Array[String],
	product_id: String,
	analysis: Dictionary
) -> Dictionary:
	if source_state == null or analysis.is_empty():
		return {}
	if not bool(analysis.get("road_graph_available", false)):
		return {}
	var distances: Dictionary = Dictionary(analysis.get("restaurant_house_distances", {}))
	var houses: Dictionary = Dictionary(analysis.get("houses", {}))
	var own_restaurant_ids := _sorted_unique_strings(observation.own_player.get("restaurants", [])) if observation != null else []
	var player_id := int(observation.viewer_player_id) if observation != null else -1
	var serviceable := 0
	var competitive := 0
	var contested := 0
	var restaurant_dominated := 0
	var lost_to_competitor := 0
	var opponent_capacity_gap_houses := 0
	var opponent_capacity_gap_prevented_sales := 0
	var opponent_capacity_gap_owner_ids: Array[String] = []
	var opponent_capacity_gap_products: Array[String] = []
	var serviceable_ids: Array[String] = []
	var competitive_ids: Array[String] = []
	var contested_ids: Array[String] = []
	var restaurant_dominated_ids: Array[String] = []
	var lost_to_competitor_ids: Array[String] = []
	var opponent_capacity_gap_ids: Array[String] = []
	var closest_distance := 2147483647
	var closest_competitor_distance := 2147483647
	var total_distance := 0
	for house_id in affected_house_ids:
		var house: Dictionary = Dictionary(houses.get(house_id, {}))
		var gap := _opponent_capacity_gap_for_house(source_state, distances, house_id, house, product_id, player_id)
		if not gap.is_empty():
			opponent_capacity_gap_houses += 1
			opponent_capacity_gap_ids.append(house_id)
			opponent_capacity_gap_prevented_sales += int(gap.get("prevented_sales", 0))
			var owner_id := str(gap.get("owner", ""))
			if not owner_id.is_empty() and not opponent_capacity_gap_owner_ids.has(owner_id):
				opponent_capacity_gap_owner_ids.append(owner_id)
			var gap_product := str(gap.get("product", ""))
			if not gap_product.is_empty() and not opponent_capacity_gap_products.has(gap_product):
				opponent_capacity_gap_products.append(gap_product)

		var best_for_house := 2147483647
		for restaurant_id in own_restaurant_ids:
			var per_rest: Dictionary = Dictionary(distances.get(restaurant_id, {}))
			var info: Dictionary = Dictionary(per_rest.get(house_id, {}))
			if not info.has("distance"):
				continue
			best_for_house = mini(best_for_house, int(info.get("distance", 2147483647)))
		if best_for_house >= 2147483647:
			continue
		serviceable += 1
		serviceable_ids.append(house_id)
		closest_distance = mini(closest_distance, best_for_house)
		total_distance += best_for_house
		var route_competitor := _best_competitor_restaurant_offer(source_state, distances, house_id, house, product_id, player_id, false)
		if not route_competitor.is_empty():
			closest_competitor_distance = mini(closest_competitor_distance, int(route_competitor.get("distance", 2147483647)))
		var own_score := best_for_house + _decision_unit_price(source_state, player_id, house, product_id)
		var competitor := _best_competitor_offer(source_state, distances, house_id, house, product_id, player_id)
		if competitor.is_empty():
			if not route_competitor.is_empty():
				var route_competitor_score := int(route_competitor.get("score", 2147483647))
				if own_score < route_competitor_score or (own_score == route_competitor_score and _turn_order_rank(source_state, player_id) <= _turn_order_rank(source_state, int(route_competitor.get("owner", -1)))):
					competitive += 1
					competitive_ids.append(house_id)
				else:
					restaurant_dominated += 1
					restaurant_dominated_ids.append(house_id)
				continue
			competitive += 1
			competitive_ids.append(house_id)
			continue
		contested += 1
		contested_ids.append(house_id)
		closest_competitor_distance = mini(closest_competitor_distance, int(competitor.get("distance", 2147483647)))
		var competitor_score := int(competitor.get("score", 2147483647))
		if own_score < competitor_score or (own_score == competitor_score and _turn_order_rank(source_state, player_id) <= _turn_order_rank(source_state, int(competitor.get("owner", -1)))):
			competitive += 1
			competitive_ids.append(house_id)
		else:
			lost_to_competitor += 1
			lost_to_competitor_ids.append(house_id)
	var average_distance := -1.0
	if serviceable > 0:
		average_distance = float(total_distance) / float(serviceable)
	opponent_capacity_gap_owner_ids.sort()
	opponent_capacity_gap_products.sort()
	return {
		"affected_houses": affected_house_ids.size(),
		"affected_house_ids": affected_house_ids.duplicate(),
		"serviceable_houses": serviceable,
		"serviceable_house_ids": serviceable_ids.duplicate(),
		"competitive_houses": competitive,
		"competitive_house_ids": competitive_ids.duplicate(),
		"contested_houses": contested,
		"contested_house_ids": contested_ids.duplicate(),
		"restaurant_dominated_houses": restaurant_dominated,
		"restaurant_dominated_house_ids": restaurant_dominated_ids.duplicate(),
		"lost_to_competitor_houses": lost_to_competitor,
		"lost_to_competitor_house_ids": lost_to_competitor_ids.duplicate(),
		"opponent_capacity_gap_houses": opponent_capacity_gap_houses,
		"opponent_capacity_gap_house_ids": opponent_capacity_gap_ids.duplicate(),
		"opponent_capacity_gap_prevented_sales": opponent_capacity_gap_prevented_sales,
		"opponent_capacity_gap_owner_ids": opponent_capacity_gap_owner_ids.duplicate(),
		"opponent_capacity_gap_products": opponent_capacity_gap_products.duplicate(),
		"closest_distance": closest_distance if serviceable > 0 else -1,
		"closest_competitor_distance": closest_competitor_distance if contested > 0 else -1,
		"average_distance": average_distance,
		"inventory_units": _inventory_count(observation, product_id),
		"can_supply_product": _can_actively_supply_product(observation, product_id),
		"can_future_supply_product": _can_supply_product(observation, product_id),
		"own_restaurants": _own_restaurant_count(observation),
		"distance_source": "road_graph",
	}

static func _finalize(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	var competitive_ids := _sorted_unique_strings(out.get("competitive_house_ids", []))
	var opponent_ids := _sorted_unique_strings(out.get("opponent_capacity_gap_house_ids", []))
	var restaurant_dominated_ids := _sorted_unique_strings(out.get("restaurant_dominated_house_ids", []))
	var inventory_units := int(out.get("inventory_units", 0))
	var can_supply := bool(out.get("can_supply_product", false))
	var can_future_supply := bool(out.get("can_future_supply_product", can_supply))
	var can_self_supply := inventory_units > 0 or can_supply or can_future_supply
	var raw_self_capture := int(out.get("competitive_houses", competitive_ids.size()))
	var self_capture := raw_self_capture if can_self_supply else 0
	var self_capture_ids := competitive_ids.duplicate() if can_self_supply else []
	var strategic_ids := self_capture_ids.duplicate()
	for house_id in opponent_ids:
		if not strategic_ids.has(house_id):
			strategic_ids.append(house_id)
	strategic_ids.sort()
	var opponent_pressure := int(out.get("opponent_capacity_gap_houses", opponent_ids.size()))
	out["self_capture_houses"] = self_capture
	out["self_capture_house_ids"] = self_capture_ids.duplicate()
	out["self_supply_blocked_houses"] = raw_self_capture if not can_self_supply else 0
	out["self_supply_blocked_house_ids"] = competitive_ids.duplicate() if not can_self_supply else []
	out["restaurant_dominated_houses"] = int(out.get("restaurant_dominated_houses", restaurant_dominated_ids.size()))
	out["restaurant_dominated_house_ids"] = restaurant_dominated_ids.duplicate()
	out["opponent_pressure_houses"] = opponent_pressure
	out["opponent_pressure_house_ids"] = opponent_ids.duplicate()
	out["strategic_houses"] = strategic_ids.size() if not strategic_ids.is_empty() else self_capture + opponent_pressure
	out["strategic_house_ids"] = strategic_ids.duplicate()
	out["marketing_pressure_houses"] = int(out.get("strategic_houses", 0))
	if self_capture > 0 and opponent_pressure > 0:
		out["pressure_mode"] = "mixed"
	elif self_capture > 0:
		out["pressure_mode"] = "self_capture"
	elif opponent_pressure > 0:
		out["pressure_mode"] = "opponent_pressure"
	else:
		out["pressure_mode"] = "none"
	return out

static func _best_competitor_offer(
	state: GameState,
	distances: Dictionary,
	house_id: String,
	house: Dictionary,
	product_id: String,
	player_id: int
) -> Dictionary:
	return _best_competitor_restaurant_offer(state, distances, house_id, house, product_id, player_id, true)

static func _best_competitor_restaurant_offer(
	state: GameState,
	distances: Dictionary,
	house_id: String,
	house: Dictionary,
	product_id: String,
	player_id: int,
	require_future_supply: bool
) -> Dictionary:
	if state == null or player_id < 0 or product_id.is_empty():
		return {}
	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return {}
	var restaurants: Dictionary = restaurants_val
	var best := {}
	for restaurant_id_val in restaurants.keys():
		var restaurant_id := str(restaurant_id_val)
		var rest_val = restaurants.get(restaurant_id_val, null)
		if not (rest_val is Dictionary):
			continue
		var owner := int(Dictionary(rest_val).get("owner", -1))
		if owner < 0 or owner == player_id:
			continue
		if require_future_supply and not _player_can_future_supply_product(state, owner, product_id):
			continue
		var per_rest: Dictionary = Dictionary(distances.get(restaurant_id, {}))
		var info: Dictionary = Dictionary(per_rest.get(house_id, {}))
		if not info.has("distance"):
			continue
		var distance := int(info.get("distance", 2147483647))
		if distance >= 2147483647:
			continue
		var score := distance + _decision_unit_price(state, owner, house, product_id)
		var offer := {
			"owner": owner,
			"distance": distance,
			"score": score,
		}
		if best.is_empty() or score < int(best.get("score", 2147483647)) or (score == int(best.get("score", 2147483647)) and _turn_order_rank(state, owner) < _turn_order_rank(state, int(best.get("owner", -1)))):
			best = offer
	return best

static func _opponent_capacity_gap_for_house(
	state: GameState,
	distances: Dictionary,
	house_id: String,
	house: Dictionary,
	product_id: String,
	player_id: int
) -> Dictionary:
	if state == null or product_id.is_empty() or player_id < 0:
		return {}
	var base_required := _required_from_house(house)
	if base_required.is_empty():
		return {}
	var augmented_required := base_required.duplicate(true)
	augmented_required[product_id] = int(augmented_required.get(product_id, 0)) + 1
	var base_competitor := _best_planned_offer_for_required(state, distances, house_id, house, base_required, player_id, "opponent")
	if base_competitor.is_empty():
		return {}
	var base_own := _best_planned_offer_for_required(state, distances, house_id, house, base_required, player_id, "own")
	if not base_own.is_empty() and _planned_offer_beats_or_ties(state, base_own, base_competitor):
		return {}
	var augmented_competitor := _best_planned_offer_for_required(state, distances, house_id, house, augmented_required, player_id, "opponent")
	if not augmented_competitor.is_empty():
		return {}
	return {
		"owner": int(base_competitor.get("owner", -1)),
		"product": product_id,
		"prevented_sales": 1,
		"base_score": int(base_competitor.get("score", 2147483647)),
	}

static func _best_planned_offer_for_required(
	state: GameState,
	distances: Dictionary,
	house_id: String,
	house: Dictionary,
	required: Dictionary,
	player_id: int,
	owner_filter: String
) -> Dictionary:
	if state == null or required.is_empty():
		return {}
	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return {}
	var restaurants: Dictionary = restaurants_val
	var best := {}
	for restaurant_id_val in restaurants.keys():
		var restaurant_id := str(restaurant_id_val)
		var rest_val = restaurants.get(restaurant_id_val, null)
		if not (rest_val is Dictionary):
			continue
		var owner := int(Dictionary(rest_val).get("owner", -1))
		if owner < 0:
			continue
		if owner_filter == "own" and owner != player_id:
			continue
		if owner_filter == "opponent" and owner == player_id:
			continue
		if not _player_can_plan_required(state, owner, required):
			continue
		var per_rest: Dictionary = Dictionary(distances.get(restaurant_id, {}))
		var info: Dictionary = Dictionary(per_rest.get(house_id, {}))
		if not info.has("distance"):
			continue
		var distance := int(info.get("distance", 2147483647))
		if distance >= 2147483647:
			continue
		var score := distance + _decision_unit_price_for_required(state, owner, house, required)
		var offer := {
			"owner": owner,
			"distance": distance,
			"score": score,
		}
		if best.is_empty() or _planned_offer_beats_or_ties(state, offer, best):
			best = offer
	return best

static func _planned_offer_beats_or_ties(state: GameState, offer: Dictionary, incumbent: Dictionary) -> bool:
	var offer_score := int(offer.get("score", 2147483647))
	var incumbent_score := int(incumbent.get("score", 2147483647))
	if offer_score != incumbent_score:
		return offer_score < incumbent_score
	return _turn_order_rank(state, int(offer.get("owner", -1))) <= _turn_order_rank(state, int(incumbent.get("owner", -1)))

static func _player_can_plan_required(state: GameState, player_id: int, required: Dictionary) -> bool:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return false
	var available := _player_planning_units_by_product(state, player_id)
	for product_key in required.keys():
		var product_id := str(product_key)
		var needed := maxi(0, int(required.get(product_key, 0)))
		if needed <= 0:
			continue
		if int(available.get(product_id, 0)) < needed:
			return false
	return true

static func _player_planning_units_by_product(state: GameState, player_id: int) -> Dictionary:
	var out := {}
	if state == null or player_id < 0 or player_id >= state.players.size():
		return out
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return out
	var player: Dictionary = player_val
	var inventory_val = player.get("inventory", {})
	if inventory_val is Dictionary:
		for product_key in Dictionary(inventory_val).keys():
			var product_id := str(product_key)
			if product_id.is_empty():
				continue
			out[product_id] = int(out.get(product_id, 0)) + maxi(0, int(Dictionary(inventory_val).get(product_key, 0)))
	if not EmployeeRegistryClass.is_loaded():
		return out
	for employee_id in _active_employee_ids(player):
		if not EmployeeRegistryClass.has(employee_id):
			continue
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if def.can_produce():
			var amount := 1
			var info := def.get_production_info()
			if info is Dictionary and int(Dictionary(info).get("amount", 0)) > 0:
				amount = int(Dictionary(info).get("amount", 1))
			for product_id in def.get_production_food_options():
				out[product_id] = int(out.get(product_id, 0)) + amount
		elif def.can_procure() or employee_id == "errand_boy":
			for product_id in _drink_product_ids():
				out[product_id] = int(out.get(product_id, 0)) + 1
	return out

static func _drink_product_ids() -> Array[String]:
	var out: Array[String] = []
	if not ProductRegistryClass.is_loaded():
		return out
	for product_id in ProductRegistryClass.get_all_ids():
		if ProductRegistryClass.is_drink(product_id):
			out.append(product_id)
	out.sort()
	return out

static func _required_from_house(house: Dictionary) -> Dictionary:
	var out := {}
	var demands_val = house.get("demands", [])
	if not (demands_val is Array):
		return out
	for demand_val in Array(demands_val):
		if not (demand_val is Dictionary):
			continue
		var product_id := str(Dictionary(demand_val).get("product", "")).strip_edges()
		if product_id.is_empty():
			continue
		out[product_id] = int(out.get(product_id, 0)) + 1
	return out

static func _demand_source_counts_by_product(house: Dictionary, player_id: int) -> Dictionary:
	var out := {}
	var demands_val = house.get("demands", [])
	if not (demands_val is Array):
		return out
	for demand_val in Array(demands_val):
		if not (demand_val is Dictionary):
			continue
		var demand: Dictionary = demand_val
		var product_id := str(demand.get("product", "")).strip_edges()
		if product_id.is_empty():
			continue
		var product: Dictionary = Dictionary(out.get(product_id, {}))
		if product.is_empty():
			product = {
				"own": 0,
				"opponent": 0,
				"neutral": 0,
			}
		var from_player := -1
		if demand.has("from_player"):
			from_player = int(demand.get("from_player", -1))
		if player_id >= 0 and from_player == player_id:
			product["own"] = int(product.get("own", 0)) + 1
		elif from_player >= 0:
			product["opponent"] = int(product.get("opponent", 0)) + 1
		else:
			product["neutral"] = int(product.get("neutral", 0)) + 1
		out[product_id] = product
	return out

static func _own_sourced_opponent_blocking_by_product(
	state: GameState,
	distances: Dictionary,
	house_id: String,
	house: Dictionary,
	required: Dictionary,
	source_counts_by_product: Dictionary,
	player_id: int
) -> Dictionary:
	var out := {}
	if state == null or required.is_empty() or player_id < 0:
		return out
	var full_competitor := _best_planned_offer_for_required(state, distances, house_id, house, required, player_id, "opponent")
	for product_key in source_counts_by_product.keys():
		var product_id := str(product_key)
		if product_id.is_empty():
			continue
		var source_counts: Dictionary = Dictionary(source_counts_by_product.get(product_key, {}))
		var own_amount := maxi(0, int(source_counts.get("own", 0)))
		if own_amount <= 0:
			continue
		var base_required := required.duplicate(true)
		var remaining := maxi(0, int(base_required.get(product_id, 0)) - own_amount)
		if remaining > 0:
			base_required[product_id] = remaining
		else:
			base_required.erase(product_id)
		if base_required.is_empty():
			continue
		var base_competitor := _best_planned_offer_for_required(state, distances, house_id, house, base_required, player_id, "opponent")
		if base_competitor.is_empty():
			continue
		if full_competitor.is_empty():
			out[product_id] = own_amount
	return out

static func _decision_unit_price(state: GameState, player_id: int, house: Dictionary, product_id: String) -> int:
	if state == null or player_id < 0 or product_id.is_empty():
		return 0
	var required := {}
	required[product_id] = 1
	return _decision_unit_price_for_required(state, player_id, house, required)

static func _decision_unit_price_for_required(state: GameState, player_id: int, house: Dictionary, required: Dictionary) -> int:
	if state == null or player_id < 0 or required.is_empty():
		return 0
	var breakdown_read := PricingPipelineClass.calculate_sale_breakdown(state, player_id, house, required)
	if not breakdown_read.ok:
		return 10
	var breakdown: Dictionary = Dictionary(breakdown_read.value)
	return int(breakdown.get("decision_unit_price", breakdown.get("unit_price", 10)))

static func _turn_order_rank(state: GameState, player_id: int) -> int:
	if state == null or player_id < 0:
		return 999999
	var idx := state.turn_order.find(player_id)
	return idx if idx >= 0 else 999999

static func _player_can_future_supply_product(state: GameState, player_id: int, product_id: String) -> bool:
	if state == null or player_id < 0 or player_id >= state.players.size() or product_id.is_empty():
		return false
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return false
	var player: Dictionary = player_val
	if _state_inventory_count(player, product_id) > 0:
		return true
	if not EmployeeRegistryClass.is_loaded():
		return false
	var is_drink := false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		is_drink = ProductRegistryClass.is_drink(product_id)
	for employee_id in _owned_employee_ids(player):
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

static func _state_inventory_count(player: Dictionary, product_id: String) -> int:
	var inventory_val = player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	return maxi(0, int(Dictionary(inventory_val).get(product_id, 0)))

static func _can_supply_product(observation: ObservationState, product_id: String) -> bool:
	if observation == null or product_id.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	var is_drink := false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		is_drink = ProductRegistryClass.is_drink(product_id)
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

static func _can_actively_supply_product(observation: ObservationState, product_id: String) -> bool:
	if observation == null or product_id.is_empty() or not EmployeeRegistryClass.is_loaded():
		return false
	var is_drink := false
	if ProductRegistryClass.is_loaded() and ProductRegistryClass.has(product_id):
		is_drink = ProductRegistryClass.is_drink(product_id)
	for employee_id in _active_employee_ids(observation.own_player):
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

static func _inventory_count(observation: ObservationState, product_id: String) -> int:
	if observation == null or product_id.is_empty():
		return 0
	var inventory_val = observation.own_player.get("inventory", {})
	if not (inventory_val is Dictionary):
		return 0
	return maxi(0, int(Dictionary(inventory_val).get(product_id, 0)))

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

static func _active_employee_ids(player: Dictionary) -> Array[String]:
	return _sorted_unique_strings(player.get("employees", []))

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

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out
