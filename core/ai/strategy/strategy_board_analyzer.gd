class_name StrategyBoardAnalyzer
extends RefCounted

const IDEAL_SERVICE_DISTANCE := 4
const MAX_HEURISTIC_DISTANCE := 8

static func restaurant_placement_value(observation: ObservationState, params: Dictionary, income_analysis: Dictionary) -> Dictionary:
	var anchor := _read_vector2i(params.get("position", Vector2i.ZERO))
	var houses_val = observation.map_public.get("houses", {}) if observation != null else {}
	if not (houses_val is Dictionary):
		return _empty_restaurant_payload(anchor)
	var houses: Dictionary = houses_val
	var nearest_distance := 2147483647
	var nearby_houses := 0
	var nearby_demand := 0
	var total_demand := 0
	var unserviceable_demand_covered := 0
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
		if distance <= IDEAL_SERVICE_DISTANCE:
			nearby_houses += 1
			nearby_demand += demand_count
		house_value += house_base * 0.75
		if demand_count > 0:
			house_value += house_base * float(demand_count) * 2.0
			if observation != null and _min_house_distance_to_owned_restaurant(observation, house_id) < 0:
				unserviceable_demand_covered += demand_count
				house_value += house_base * float(demand_count) * 1.25
	var own_restaurants := int(income_analysis.get("own_restaurants", 0))
	if own_restaurants <= 0 and nearby_houses > 0:
		house_value += 10.0
	if total_demand > 0 and nearby_demand <= 0:
		house_value -= 8.0
	var nearest := nearest_distance if nearest_distance < 2147483647 else -1
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": nearest,
		"nearby_houses": nearby_houses,
		"nearby_demand": nearby_demand,
		"total_public_demand": total_demand,
		"unserviceable_demand_covered": unserviceable_demand_covered,
		"placement_value": house_value,
	}

static func _empty_restaurant_payload(anchor: Vector2i) -> Dictionary:
	return {
		"candidate_anchor": [anchor.x, anchor.y],
		"nearest_house_distance": -1,
		"nearby_houses": 0,
		"nearby_demand": 0,
		"total_public_demand": 0,
		"unserviceable_demand_covered": 0,
		"placement_value": 0.0,
	}

static func _house_demand_count(house: Dictionary) -> int:
	var demands_val = house.get("demands", [])
	if demands_val is Array:
		return Array(demands_val).size()
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
