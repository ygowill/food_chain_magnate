# 房屋编号管理器
# 管理房屋编号的分配和排序
class_name HouseNumberManager
extends RefCounted

# === 初始化 ===

# 从烘焙的地图初始化，返回下一个可用的房屋编号
static func initialize_from_baked_map(houses: Dictionary) -> int:
	var max_number := 0

	for house_id in houses:
		var house_val = houses[house_id]
		assert(
			house_val is Dictionary,
			"HouseNumberManager.initialize_from_baked_map: houses[%s] 类型错误（期望 Dictionary）" % str(house_id)
		)
		var house: Dictionary = house_val
		assert(
			house.has("house_number"),
			"HouseNumberManager.initialize_from_baked_map: houses[%s] 缺少 house_number" % str(house_id)
		)
		var num = house["house_number"]
		assert(
			num is int or num is float or num is String,
			"HouseNumberManager.initialize_from_baked_map: houses[%s].house_number 类型错误（期望 int/float/String）" % str(house_id)
		)

		# 处理数值类型
		if num is int:
			max_number = max(max_number, int(num))
		elif num is float:
			max_number = max(max_number, int(num))
		# 字符串编号不计入最大值 (如 π, √2)

	return max_number + 1

# === 编号分配 ===

# 为新房屋分配编号
static func assign_house_number(state_map: Dictionary) -> int:
	assert(state_map.has("next_house_number"), "HouseNumberManager.assign_house_number: state_map 缺少 next_house_number")
	var num_val = state_map["next_house_number"]
	assert(num_val is int, "HouseNumberManager.assign_house_number: next_house_number 类型错误（期望 int）")
	var number: int = int(num_val)
	assert(number > 0, "HouseNumberManager.assign_house_number: next_house_number 非法: %d" % number)
	state_map["next_house_number"] = number + 1
	return number

# 为新房屋生成唯一 ID
static func generate_house_id(state_map: Dictionary) -> String:
	assert(state_map.has("houses") and (state_map["houses"] is Dictionary), "HouseNumberManager.generate_house_id: state_map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state_map["houses"]
	var counter := houses.size() + 1

	while houses.has("house_%d" % counter):
		counter += 1

	return "house_%d" % counter

# === 排序 ===

# 获取按编号排序的房屋 ID 列表 (用于晚餐阶段)
static func get_sorted_house_ids(houses: Dictionary) -> Array[String]:
	var house_list := []

	for house_id in houses:
		var house_val = houses[house_id]
		assert(
			house_val is Dictionary,
			"HouseNumberManager.get_sorted_house_ids: houses[%s] 类型错误（期望 Dictionary）" % str(house_id)
		)
		var house: Dictionary = house_val
		assert(
			house.has("house_number"),
			"HouseNumberManager.get_sorted_house_ids: houses[%s] 缺少 house_number" % str(house_id)
		)
		house_list.append({
			"id": house_id,
			"number": house["house_number"],
			"sort_key": _get_sort_key(house["house_number"])
		})

	# 排序
	house_list.sort_custom(func(a, b): return _compare_sort_keys(a.sort_key, b.sort_key))

	var result: Array[String] = []
	for item in house_list:
		result.append(item.id)

	return result

# 获取排序键
static func _get_sort_key(house_number) -> Dictionary:
	if house_number is int:
		return {"type": "numeric", "value": float(house_number)}
	elif house_number is float:
		return {"type": "numeric", "value": house_number}
	elif house_number is String:
		# 尝试解析为数值
		if house_number.is_valid_float():
			return {"type": "numeric", "value": house_number.to_float()}
		# 特殊字符处理
		var special_values := {
			"π": 3.14159,
			"pi": 3.14159,
			"√2": 1.41421,
			"sqrt2": 1.41421,
			"e": 2.71828
		}
		if special_values.has(house_number):
			return {"type": "numeric", "value": special_values[house_number]}
		# 普通字符串
		return {"type": "string", "value": house_number}
	else:
		return {"type": "string", "value": str(house_number)}

# 比较排序键
static func _compare_sort_keys(a: Dictionary, b: Dictionary) -> bool:
	# 数值在字符串之前
	if a.type == "numeric" and b.type == "string":
		return true
	if a.type == "string" and b.type == "numeric":
		return false

	# 同类型比较
	if a.type == "numeric":
		return a.value < b.value
	else:
		return a.value < b.value  # 字符串比较

# === 查询 ===

# 获取编号最小的房屋 ID
static func get_first_house_id(houses: Dictionary) -> String:
	var sorted := get_sorted_house_ids(houses)
	if sorted.is_empty():
		return ""
	return sorted[0]

# 获取编号最大的房屋 ID
static func get_last_house_id(houses: Dictionary) -> String:
	var sorted := get_sorted_house_ids(houses)
	if sorted.is_empty():
		return ""
	return sorted[sorted.size() - 1]

# 获取指定编号范围内的房屋
static func get_houses_in_range(houses: Dictionary, min_num: float, max_num: float) -> Array[String]:
	var result: Array[String] = []

	for house_id in houses:
		var house_val = houses[house_id]
		assert(
			house_val is Dictionary,
			"HouseNumberManager.get_houses_in_range: houses[%s] 类型错误（期望 Dictionary）" % str(house_id)
		)
		var house: Dictionary = house_val
		assert(
			house.has("house_number"),
			"HouseNumberManager.get_houses_in_range: houses[%s] 缺少 house_number" % str(house_id)
		)
		var num = house["house_number"]
		var sort_key := _get_sort_key(num)

		if sort_key.type == "numeric":
			if sort_key.value >= min_num and sort_key.value <= max_num:
				result.append(str(house_id))

	# 排序结果
	result.sort_custom(func(a, b):
		var house_a_val = houses[a]
		assert(house_a_val is Dictionary, "HouseNumberManager.get_houses_in_range: houses[%s] 类型错误（期望 Dictionary）" % str(a))
		var house_a: Dictionary = house_a_val
		assert(house_a.has("house_number"), "HouseNumberManager.get_houses_in_range: houses[%s] 缺少 house_number" % str(a))

		var house_b_val = houses[b]
		assert(house_b_val is Dictionary, "HouseNumberManager.get_houses_in_range: houses[%s] 类型错误（期望 Dictionary）" % str(b))
		var house_b: Dictionary = house_b_val
		assert(house_b.has("house_number"), "HouseNumberManager.get_houses_in_range: houses[%s] 缺少 house_number" % str(b))

		var key_a := _get_sort_key(house_a["house_number"])
		var key_b := _get_sort_key(house_b["house_number"])
		return _compare_sort_keys(key_a, key_b)
	)

	return result

# 根据编号查找房屋 ID
static func find_house_by_number(houses: Dictionary, number) -> String:
	for house_id in houses:
		var house_val = houses[house_id]
		assert(house_val is Dictionary, "HouseNumberManager.find_house_by_number: houses[%s] 类型错误（期望 Dictionary）" % str(house_id))
		var house: Dictionary = house_val
		assert(house.has("house_number"), "HouseNumberManager.find_house_by_number: houses[%s] 缺少 house_number" % str(house_id))
		if house["house_number"] == number:
			return house_id

	return ""

# === 验证 ===

# 检查编号是否已存在
static func is_number_taken(houses: Dictionary, number) -> bool:
	return not find_house_by_number(houses, number).is_empty()

# 检查编号是否有效
static func is_valid_number(number) -> bool:
	if number is int:
		return number > 0
	if number is float:
		return number > 0
	if number is String:
		return not number.is_empty()
	return false

# === 调试 ===

static func dump_house_order(houses: Dictionary) -> String:
	var output := "=== House Order ===\n"
	var sorted := get_sorted_house_ids(houses)

	for i in sorted.size():
		var house_id := sorted[i]
		var house_val = houses[house_id]
		assert(house_val is Dictionary, "HouseNumberManager.dump_house_order: houses[%s] 类型错误（期望 Dictionary）" % str(house_id))
		var house: Dictionary = house_val
		assert(house.has("house_number"), "HouseNumberManager.dump_house_order: houses[%s] 缺少 house_number" % str(house_id))
		var num = house["house_number"]
		output += "%d. %s (num: %s)\n" % [i + 1, house_id, str(num)]

	return output
