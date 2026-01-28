extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func get_house(state, house_id: String) -> Dictionary:
	if state == null:
		return {}
	if house_id.is_empty():
		return {}
	var houses_read := MapStateAccessClass.require_houses(state, "")
	if not houses_read.ok:
		return {}
	var houses: Dictionary = houses_read.value
	var h_val = houses.get(house_id, null)
	if h_val is Dictionary:
		return h_val
	return {}

static func get_restaurant(state, restaurant_id: String) -> Dictionary:
	if state == null:
		return {}
	if restaurant_id.is_empty():
		return {}
	var restaurants_read := MapStateAccessClass.require_restaurants(state, "")
	if not restaurants_read.ok:
		return {}
	var restaurants: Dictionary = restaurants_read.value
	var r_val = restaurants.get(restaurant_id, null)
	if r_val is Dictionary:
		return r_val
	return {}

static func get_player_restaurants(state, player_id: int) -> Array[String]:
	if state == null:
		return []
	var restaurants_read := MapStateAccessClass.require_restaurants(state, "")
	if not restaurants_read.ok:
		return []
	var restaurants: Dictionary = restaurants_read.value
	var result: Array[String] = []
	for rest_id_val in restaurants.keys():
		if not (rest_id_val is String):
			continue
		var rid := str(rest_id_val)
		if rid.is_empty():
			continue
		var rest_val = restaurants.get(rid, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var owner_val = rest.get("owner", null)
		if owner_val is int and int(owner_val) == player_id:
			result.append(rid)
	result.sort()
	return result

static func get_sorted_house_ids(state) -> Result:
	var houses_read := MapStateAccessClass.require_houses(state, "Structures.get_sorted_house_ids")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	return HouseNumberManagerClass.get_sorted_house_ids(houses)
