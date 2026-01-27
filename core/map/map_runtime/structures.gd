extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

static func get_house(state, house_id: String) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	if house_id.is_empty():
		return {}
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return {}
	var houses: Dictionary = state.map["houses"]
	var h_val = houses.get(house_id, null)
	if h_val is Dictionary:
		return h_val
	return {}

static func get_restaurant(state, restaurant_id: String) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	if restaurant_id.is_empty():
		return {}
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return {}
	var restaurants: Dictionary = state.map["restaurants"]
	var r_val = restaurants.get(restaurant_id, null)
	if r_val is Dictionary:
		return r_val
	return {}

static func get_player_restaurants(state, player_id: int) -> Array[String]:
	if state == null or not (state.map is Dictionary):
		return []
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return []
	var restaurants: Dictionary = state.map["restaurants"]
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
	if state == null or not (state.map is Dictionary):
		return Result.failure("Structures.get_sorted_house_ids: state.map 类型错误（期望 Dictionary）")
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("Structures.get_sorted_house_ids: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	return HouseNumberManagerClass.get_sorted_house_ids(houses)
