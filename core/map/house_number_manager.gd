# 房屋编号管理器
# 管理房屋编号的分配和排序
class_name HouseNumberManager
extends RefCounted

# === 初始化 ===

# 从烘焙的地图初始化，返回下一个可用的房屋编号
static func initialize_from_baked_map(houses: Dictionary) -> Result:
	var max_number := 0

	for house_id in houses:
		var house_val = houses[house_id]
		if not (house_val is Dictionary):
			return Result.failure("HouseNumberManager.initialize_from_baked_map: houses[%s] 类型错误（期望 Dictionary）" % str(house_id))
		var house: Dictionary = house_val
		if not house.has("house_number"):
			return Result.failure("HouseNumberManager.initialize_from_baked_map: houses[%s] 缺少 house_number" % str(house_id))
		var num = house["house_number"]
		if not (num is int or num is float or num is String):
			return Result.failure("HouseNumberManager.initialize_from_baked_map: houses[%s].house_number 类型错误（期望 int/float/String）" % str(house_id))

		# 处理数值类型
		if num is int:
			max_number = max(max_number, int(num))
		elif num is float:
			max_number = max(max_number, int(num))
		# 字符串编号不计入最大值 (如 π, √2)

	return Result.success(max_number + 1)

# === 编号分配 ===

# 为新房屋分配编号
static func assign_house_number(state_map: Dictionary) -> Result:
	if state_map == null or not (state_map is Dictionary):
		return Result.failure("HouseNumberManager.assign_house_number: state_map 类型错误（期望 Dictionary）")
	if not state_map.has("next_house_number"):
		return Result.failure("HouseNumberManager.assign_house_number: state_map 缺少 next_house_number")
	var num_val = state_map.get("next_house_number", null)
	if not (num_val is int):
		return Result.failure("HouseNumberManager.assign_house_number: next_house_number 类型错误（期望 int）")
	var number: int = int(num_val)
	if number <= 0:
		return Result.failure("HouseNumberManager.assign_house_number: next_house_number 非法: %d" % number)
	state_map["next_house_number"] = number + 1
	return Result.success(number)

# 为新房屋生成唯一 ID
static func generate_house_id(state_map: Dictionary) -> Result:
	if state_map == null or not (state_map is Dictionary):
		return Result.failure("HouseNumberManager.generate_house_id: state_map 类型错误（期望 Dictionary）")
	if not state_map.has("houses") or not (state_map["houses"] is Dictionary):
		return Result.failure("HouseNumberManager.generate_house_id: state_map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state_map["houses"]
	var counter := houses.size() + 1

	while houses.has("house_%d" % counter):
		counter += 1

	return Result.success("house_%d" % counter)

# === 排序 ===

# 获取按编号排序的房屋 ID 列表 (用于晚餐阶段)
static func get_sorted_house_ids(houses: Dictionary) -> Result:
	if houses == null or not (houses is Dictionary):
		return Result.failure("HouseNumberManager.get_sorted_house_ids: houses 类型错误（期望 Dictionary）")
	var house_list := []

	for house_id in houses:
		var house_val = houses[house_id]
		var id: String = str(house_id)
		if id.is_empty():
			return Result.failure("HouseNumberManager.get_sorted_house_ids: house_id 不能为空")
		if not (house_val is Dictionary):
			return Result.failure("HouseNumberManager.get_sorted_house_ids: houses[%s] 类型错误（期望 Dictionary）" % id)
		var house: Dictionary = house_val
		if not house.has("house_number"):
			return Result.failure("HouseNumberManager.get_sorted_house_ids: houses[%s] 缺少 house_number" % id)
		house_list.append({
			"id": id,
			"number": house["house_number"],
			"sort_key": _get_sort_key(house["house_number"])
		})

	# 排序
	house_list.sort_custom(func(a, b): return _compare_sort_keys(a.sort_key, b.sort_key))

	var result: Array[String] = []
	for item in house_list:
		result.append(str(item.id))

	return Result.success(result)

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
static func get_first_house_id(houses: Dictionary) -> Result:
	var sorted_read := get_sorted_house_ids(houses)
	if not sorted_read.ok:
		return sorted_read
	var sorted: Array[String] = sorted_read.value
	if sorted.is_empty():
		return Result.success("")
	return Result.success(sorted[0])

# 获取编号最大的房屋 ID
static func get_last_house_id(houses: Dictionary) -> Result:
	var sorted_read := get_sorted_house_ids(houses)
	if not sorted_read.ok:
		return sorted_read
	var sorted: Array[String] = sorted_read.value
	if sorted.is_empty():
		return Result.success("")
	return Result.success(sorted[sorted.size() - 1])

# 获取指定编号范围内的房屋
static func get_houses_in_range(houses: Dictionary, min_num: float, max_num: float) -> Result:
	if houses == null or not (houses is Dictionary):
		return Result.failure("HouseNumberManager.get_houses_in_range: houses 类型错误（期望 Dictionary）")
	var result: Array[String] = []
	var sort_keys := {}

	for house_id in houses:
		var house_val = houses[house_id]
		var id: String = str(house_id)
		if id.is_empty():
			return Result.failure("HouseNumberManager.get_houses_in_range: house_id 不能为空")
		if not (house_val is Dictionary):
			return Result.failure("HouseNumberManager.get_houses_in_range: houses[%s] 类型错误（期望 Dictionary）" % id)
		var house: Dictionary = house_val
		if not house.has("house_number"):
			return Result.failure("HouseNumberManager.get_houses_in_range: houses[%s] 缺少 house_number" % id)
		var num = house["house_number"]
		var sort_key := _get_sort_key(num)

		if sort_key.type == "numeric":
			if sort_key.value >= min_num and sort_key.value <= max_num:
				result.append(id)
				sort_keys[id] = sort_key

	# 排序结果
	result.sort_custom(func(a, b):
		var key_a = sort_keys.get(a, null)
		var key_b = sort_keys.get(b, null)
		return _compare_sort_keys(key_a, key_b)
	)

	return Result.success(result)

# 根据编号查找房屋 ID
static func find_house_by_number(houses: Dictionary, number) -> Result:
	if houses == null or not (houses is Dictionary):
		return Result.failure("HouseNumberManager.find_house_by_number: houses 类型错误（期望 Dictionary）")
	for house_id in houses:
		var house_val = houses[house_id]
		var id: String = str(house_id)
		if id.is_empty():
			return Result.failure("HouseNumberManager.find_house_by_number: house_id 不能为空")
		if not (house_val is Dictionary):
			return Result.failure("HouseNumberManager.find_house_by_number: houses[%s] 类型错误（期望 Dictionary）" % id)
		var house: Dictionary = house_val
		if not house.has("house_number"):
			return Result.failure("HouseNumberManager.find_house_by_number: houses[%s] 缺少 house_number" % id)
		if house["house_number"] == number:
			return Result.success(id)

	return Result.success("")

# === 验证 ===

# 检查编号是否已存在
static func is_number_taken(houses: Dictionary, number) -> Result:
	var r := find_house_by_number(houses, number)
	if not r.ok:
		return r
	return Result.success(not str(r.value).is_empty())

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
	var sorted_read := get_sorted_house_ids(houses)
	if not sorted_read.ok:
		return "=== House Order ===\n<error: %s>\n" % str(sorted_read.error)
	var sorted: Array[String] = sorted_read.value

	for i in sorted.size():
		var house_id := sorted[i]
		var house_val = houses[house_id]
		if not (house_val is Dictionary):
			output += "%d. %s (invalid house)\n" % [i + 1, house_id]
			continue
		var house: Dictionary = house_val
		if not house.has("house_number"):
			output += "%d. %s (missing house_number)\n" % [i + 1, house_id]
			continue
		var num = house["house_number"]
		output += "%d. %s (num: %s)\n" % [i + 1, house_id, str(num)]

	return output
