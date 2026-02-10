extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
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

static func get_restaurant_entrance_points(state: GameState, restaurant_id: String, rest: Dictionary) -> Result:
	if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
		return Result.failure("restaurants[%s].entrance_pos 缺失或类型错误（期望 Vector2i）" % restaurant_id)
	var entrance: Vector2i = rest["entrance_pos"]
	var entrance_only: Array[Vector2i] = [entrance]

	# owner 缺失/越界：容错为“无免下车”
	if not rest.has("owner") or not (rest["owner"] is int):
		return Result.success(entrance_only)
	var owner: int = int(rest["owner"])
	if state == null or not (state.players is Array) or owner < 0 or owner >= (state.players as Array).size():
		return Result.success(entrance_only)

	var player_val = (state.players as Array)[owner]
	if not (player_val is Dictionary):
		return Result.failure("players[%d] 类型错误（期望 Dictionary）" % owner)
	var player: Dictionary = player_val

	# 免下车：只要在岗有 drivethrough 标签员工，即视为本回合四角都可进出。
	var drive_thru_active := EmployeeRulesClass.count_active_by_tag(player, "drivethrough") > 0
	if not drive_thru_active:
		return Result.success(entrance_only)

	if not rest.has("cells") or not (rest["cells"] is Array):
		return Result.failure("restaurants[%s].cells 缺失或类型错误（期望 Array[Vector2i]）" % restaurant_id)
	var cells_any: Array = rest["cells"]
	if cells_any.is_empty():
		return Result.success(entrance_only)

	var cells: Array[Vector2i] = []
	for i in range(cells_any.size()):
		var c = cells_any[i]
		if not (c is Vector2i):
			return Result.failure("restaurants[%s].cells[%d] 类型错误（期望 Vector2i）" % [restaurant_id, i])
		cells.append(c)

	var bounds := MapUtilsClass.get_footprint_bounds(cells)
	if not (bounds.has("min") and bounds["min"] is Vector2i):
		return Result.failure("MapUtils.get_footprint_bounds: 缺少/错误 min（期望 Vector2i）")
	if not (bounds.has("max") and bounds["max"] is Vector2i):
		return Result.failure("MapUtils.get_footprint_bounds: 缺少/错误 max（期望 Vector2i）")
	var min_pos: Vector2i = bounds["min"]
	var max_pos: Vector2i = bounds["max"]
	var points: Array[Vector2i] = [
		Vector2i(min_pos.x, min_pos.y),
		Vector2i(max_pos.x, min_pos.y),
		Vector2i(min_pos.x, max_pos.y),
		Vector2i(max_pos.x, max_pos.y),
	]
	return Result.success(points)

static func get_sorted_house_ids(state) -> Result:
	var houses_read := MapStateAccessClass.require_houses(state, "Structures.get_sorted_house_ids")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	return HouseNumberManagerClass.get_sorted_house_ids(houses)
