extends RefCounted

# === 数值操作 ===

# 增加数值
static func increment(dict: Dictionary, key: String, amount: int = 1) -> int:
	assert(dict != null, "StateUpdater.increment: dict 为空")
	assert(not key.is_empty(), "StateUpdater.increment: key 不能为空")
	var current := 0
	if dict.has(key):
		assert(dict[key] is int, "StateUpdater.increment: %s 类型错误（期望 int）" % key)
		current = int(dict[key])
	var new_value := current + amount
	dict[key] = new_value
	return new_value

# 减少数值（不低于0）
static func decrement(dict: Dictionary, key: String, amount: int = 1) -> int:
	assert(dict != null, "StateUpdater.decrement: dict 为空")
	assert(not key.is_empty(), "StateUpdater.decrement: key 不能为空")
	var current := 0
	if dict.has(key):
		assert(dict[key] is int, "StateUpdater.decrement: %s 类型错误（期望 int）" % key)
		current = int(dict[key])
	var new_value = max(0, current - amount)
	dict[key] = new_value
	return new_value

# 设置数值（带范围限制）
static func set_clamped(dict: Dictionary, key: String, value: int, min_val: int = 0, max_val: int = 999999) -> int:
	assert(dict != null, "StateUpdater.set_clamped: dict 为空")
	assert(not key.is_empty(), "StateUpdater.set_clamped: key 不能为空")
	var clamped := clampi(value, min_val, max_val)
	dict[key] = clamped
	return clamped

# === 数组操作 ===

# 添加到数组
static func append_to_array(dict: Dictionary, key: String, item) -> void:
	assert(dict != null, "StateUpdater.append_to_array: dict 为空")
	assert(not key.is_empty(), "StateUpdater.append_to_array: key 不能为空")
	assert(dict.has(key), "StateUpdater.append_to_array: dict 缺少 key: %s" % key)
	assert(dict[key] is Array, "StateUpdater.append_to_array: %s 类型错误（期望 Array）" % key)
	dict[key].append(item)

# 从数组移除第一个匹配项
static func remove_from_array(dict: Dictionary, key: String, item) -> bool:
	assert(dict != null, "StateUpdater.remove_from_array: dict 为空")
	assert(not key.is_empty(), "StateUpdater.remove_from_array: key 不能为空")
	assert(dict.has(key), "StateUpdater.remove_from_array: dict 缺少 key: %s" % key)
	assert(dict[key] is Array, "StateUpdater.remove_from_array: %s 类型错误（期望 Array）" % key)
	var arr: Array = dict[key]
	var index := arr.find(item)
	if index >= 0:
		arr.remove_at(index)
		return true
	return false

# 从数组移除指定索引
static func remove_at_index(dict: Dictionary, key: String, index: int) -> bool:
	assert(dict != null, "StateUpdater.remove_at_index: dict 为空")
	assert(not key.is_empty(), "StateUpdater.remove_at_index: key 不能为空")
	assert(dict.has(key), "StateUpdater.remove_at_index: dict 缺少 key: %s" % key)
	assert(dict[key] is Array, "StateUpdater.remove_at_index: %s 类型错误（期望 Array）" % key)
	var arr: Array = dict[key]
	if index >= 0 and index < arr.size():
		arr.remove_at(index)
		return true
	return false

