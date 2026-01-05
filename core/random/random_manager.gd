# 受控随机管理器
# 基于种子的确定性随机数生成，支持回放一致性
class_name RandomManager
extends RefCounted

# 内部随机数生成器
var _rng: RandomNumberGenerator
var _initial_seed: int
var _call_count: int = 0

# 调用历史（用于调试和验证）
var _history: Array[Dictionary] = []
var _record_history: bool = false

# 构造函数
func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_initial_seed = seed_value
	_rng.seed = seed_value
	# 重要：仅设置 seed 在某些实现下可能不足以保证“同 seed 同序列”；
	# 同时固定 state，确保跨实例/跨运行的序列一致。
	_rng.state = int(seed_value)
	_call_count = 0

# === 基础随机方法 ===

# 生成指定范围内的随机整数 [from, to]
func randi_range(from: int, to: int) -> int:
	var result := _rng.randi_range(from, to)
	_record_call("randi_range", {"from": from, "to": to}, result)
	return result

# 生成 [0, 1) 范围的随机浮点数
func randf() -> float:
	var result := _rng.randf()
	_record_call("randf", {}, result)
	return result

# 生成指定范围内的随机浮点数
func randf_range(from: float, to: float) -> float:
	var result := _rng.randf_range(from, to)
	_record_call("randf_range", {"from": from, "to": to}, result)
	return result

# 生成随机无符号整数
func randi() -> int:
	var result := _rng.randi()
	_record_call("randi", {}, result)
	return result

# === 高级随机方法 ===

# 洗牌数组（原地修改）
func shuffle(array: Array) -> void:
	var n := array.size()
	for i in range(n - 1, 0, -1):
		var j := self.randi_range(0, i)
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp

# 返回洗牌后的新数组（不修改原数组）
func shuffled(array: Array) -> Array:
	var copy := array.duplicate()
	shuffle(copy)
	return copy

# 从数组中随机选择一个元素
func pick(array: Array):
	if array.is_empty():
		return null
	var index := self.randi_range(0, array.size() - 1)
	return array[index]

# 从数组中随机选择多个元素（不重复）
func pick_multiple(array: Array, count: int) -> Array:
	if count >= array.size():
		return shuffled(array)

	var indices := []
	for i in range(array.size()):
		indices.append(i)
	self.shuffle(indices)

	var result := []
	for i in range(count):
		result.append(array[indices[i]])
	return result

# 加权随机选择
# weights 数组与 items 数组对应，权重越大概率越高
func weighted_pick(items: Array, weights: Array[float]):
	if items.is_empty() or items.size() != weights.size():
		return null

	var total_weight := 0.0
	for w in weights:
		total_weight += w

	if total_weight <= 0:
		return self.pick(items)

	var roll := self.randf() * total_weight
	var cumulative := 0.0

	for i in range(items.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return items[i]

	return items[-1]

# 布尔随机（指定概率为 true）
func chance(probability: float) -> bool:
	return self.randf() < probability

# 骰子投掷
func roll_dice(sides: int = 6) -> int:
	return self.randi_range(1, sides)

# 多个骰子投掷
func roll_dice_multiple(count: int, sides: int = 6) -> Array[int]:
	var results: Array[int] = []
	for i in range(count):
		results.append(self.roll_dice(sides))
	return results

# === 状态管理 ===

# 重置到初始状态
func reset() -> void:
	_rng.seed = _initial_seed
	_rng.state = int(_initial_seed)
	_call_count = 0
	_history.clear()

# 设置新的种子
func set_seed(seed_value: int) -> void:
	_initial_seed = seed_value
	_rng.seed = seed_value
	_rng.state = int(seed_value)
	_call_count = 0

# 获取当前种子
func get_seed() -> int:
	return _initial_seed

# 获取调用次数
func get_call_count() -> int:
	return _call_count

# 快进到指定调用次数
func fast_forward(target_count: int) -> void:
	while _call_count < target_count:
		_rng.randi()
		_call_count += 1

# === 历史记录 ===

func _record_call(method: String, params: Dictionary, result) -> void:
	_call_count += 1

	if _record_history:
		_history.append({
			"call_index": _call_count,
			"method": method,
			"params": params,
			"result": result
		})

# 启用/禁用历史记录
func set_record_history(enabled: bool) -> void:
	_record_history = enabled
	if not enabled:
		_history.clear()

# 获取历史记录
func get_history() -> Array[Dictionary]:
	return _history.duplicate()

# === 序列化 ===

func to_dict() -> Dictionary:
	return {
		"initial_seed": _initial_seed,
		"call_count": _call_count
	}

static func from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("RandomManager.from_dict: data 类型错误（期望 Dictionary）")

	if not data.has("initial_seed"):
		return Result.failure("RandomManager 缺少字段: initial_seed")
	if not data.has("call_count"):
		return Result.failure("RandomManager 缺少字段: call_count")

	var seed_val = data.get("initial_seed", null)
	var call_val = data.get("call_count", null)
	if not (seed_val is int or seed_val is float):
		return Result.failure("RandomManager.initial_seed 类型错误（期望整数）")
	if not (call_val is int or call_val is float):
		return Result.failure("RandomManager.call_count 类型错误（期望整数）")

	var seed_value: int = int(seed_val)
	var call_count: int = int(call_val)
	if call_count < 0:
		return Result.failure("RandomManager.call_count 不能为负数: %d" % call_count)

	var manager := RandomManager.new(seed_value)
	manager.fast_forward(call_count)
	return Result.success(manager)

# === 调试 ===

func _to_string() -> String:
	return "[RandomManager seed=%d calls=%d]" % [_initial_seed, _call_count]

func dump() -> String:
	var output := "=== RandomManager ===\n"
	output += "Seed: %d\n" % _initial_seed
	output += "Call Count: %d\n" % _call_count
	output += "History Recording: %s\n" % ("ON" if _record_history else "OFF")

	if _record_history and _history.size() > 0:
		output += "Recent Calls:\n"
		var start = max(0, _history.size() - 10)
		for i in range(start, _history.size()):
			var h := _history[i]
			output += "  #%d: %s(%s) = %s\n" % [
				h.call_index, h.method, str(h.params), str(h.result)
			]

	return output
