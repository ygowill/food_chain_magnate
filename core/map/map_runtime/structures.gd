extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

static func get_house(state, house_id: String) -> Dictionary:
	assert(state != null, "MapRuntime.get_house: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_house: state.map 类型错误（期望 Dictionary）")
	assert(not house_id.is_empty(), "MapRuntime.get_house: house_id 不能为空")
	assert(state.map.has("houses") and (state.map["houses"] is Dictionary), "MapRuntime.get_house: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	assert(houses.has(house_id), "MapRuntime.get_house: house_id 不存在: %s" % house_id)
	var h_val = houses[house_id]
	assert(h_val is Dictionary, "MapRuntime.get_house: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	return h_val

static func get_restaurant(state, restaurant_id: String) -> Dictionary:
	assert(state != null, "MapRuntime.get_restaurant: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_restaurant: state.map 类型错误（期望 Dictionary）")
	assert(not restaurant_id.is_empty(), "MapRuntime.get_restaurant: restaurant_id 不能为空")
	assert(state.map.has("restaurants") and (state.map["restaurants"] is Dictionary), "MapRuntime.get_restaurant: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]
	assert(restaurants.has(restaurant_id), "MapRuntime.get_restaurant: restaurant_id 不存在: %s" % restaurant_id)
	var r_val = restaurants[restaurant_id]
	assert(r_val is Dictionary, "MapRuntime.get_restaurant: restaurants[%s] 类型错误（期望 Dictionary）" % restaurant_id)
	return r_val

static func get_player_restaurants(state, player_id: int) -> Array[String]:
	assert(state != null, "MapRuntime.get_player_restaurants: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_player_restaurants: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("restaurants") and (state.map["restaurants"] is Dictionary), "MapRuntime.get_player_restaurants: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]
	var result: Array[String] = []
	for rest_id in restaurants:
		assert(rest_id is String, "MapRuntime.get_player_restaurants: restaurants key 类型错误（期望 String）")
		var rid: String = str(rest_id)
		var rest_val = restaurants[rest_id]
		assert(rest_val is Dictionary, "MapRuntime.get_player_restaurants: restaurants[%s] 类型错误（期望 Dictionary）" % rid)
		var rest: Dictionary = rest_val
		assert(rest.has("owner") and (rest["owner"] is int), "MapRuntime.get_player_restaurants: restaurants[%s].owner 缺失或类型错误（期望 int）" % rid)
		if int(rest["owner"]) == player_id:
			result.append(rid)
	result.sort()
	return result

static func get_sorted_house_ids(state) -> Array[String]:
	assert(state != null, "MapRuntime.get_sorted_house_ids: state 为空")
	assert(state.map is Dictionary, "MapRuntime.get_sorted_house_ids: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("houses") and (state.map["houses"] is Dictionary), "MapRuntime.get_sorted_house_ids: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	return HouseNumberManagerClass.get_sorted_house_ids(houses)

