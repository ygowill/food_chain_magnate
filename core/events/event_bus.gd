# 事件总线
# 全局事件订阅/发射系统，支持事件历史记录
extends Node

# 事件类型常量
class EventType:
	# 阶段相关
	const PHASE_CHANGED := "phase_changed"
	const SUB_PHASE_CHANGED := "sub_phase_changed"
	const ROUND_STARTED := "round_started"
	const ROUND_ENDED := "round_ended"

	# 玩家相关
	const PLAYER_TURN_STARTED := "player_turn_started"
	const PLAYER_TURN_ENDED := "player_turn_ended"
	const PLAYER_CASH_CHANGED := "player_cash_changed"
	const PLAYER_BROKE := "player_broke"

	# 员工相关
	const EMPLOYEE_RECRUITED := "employee_recruited"
	const EMPLOYEE_TRAINED := "employee_trained"
	const EMPLOYEE_FIRED := "employee_fired"
	const EMPLOYEE_ACTIVATED := "employee_activated"

	# 餐厅相关
	const RESTAURANT_PLACED := "restaurant_placed"
	const RESTAURANT_MOVED := "restaurant_moved"
	const HOUSE_PLACED := "house_placed"
	const GARDEN_ADDED := "garden_added"
	const FOOD_PRODUCED := "food_produced"
	const FOOD_SOLD := "food_sold"
	const FOOD_DISCARDED := "food_discarded"
	const DRINKS_PROCURED := "drinks_procured"

	# 营销相关
	const MARKETING_PLACED := "marketing_placed"
	const MARKETING_EXPIRED := "marketing_expired"
	const DEMAND_GENERATED := "demand_generated"

	# 系统相关
	const COMMAND_EXECUTED := "command_executed"
	const STATE_CHANGED := "state_changed"
	const CHECKPOINT_CREATED := "checkpoint_created"
	const GAME_STARTED := "game_started"
	const GAME_ENDED := "game_ended"

	# 里程碑相关
	const MILESTONE_ACHIEVED := "milestone_achieved"

# 订阅者存储
# event_type -> Array[{callback: Callable, priority: int, source: String}]
var _subscribers: Dictionary = {}

# 事件历史（用于调试和回放验证）
var _event_history: Array[Dictionary] = []
var _history_enabled: bool = true
var _max_history_size: int = 1000

# 事件序列号（用于确定性排序）
var _event_sequence: int = 0

func _ready() -> void:
	GameLog.info("EventBus", "事件总线初始化完成")

# === 订阅管理 ===

# 订阅事件
# priority: 数值越小优先级越高（默认100）
func subscribe(event_type: String, callback: Callable, priority: int = 100, source: String = "") -> void:
	if not _subscribers.has(event_type):
		_subscribers[event_type] = []

	var subscriber := {
		"callback": callback,
		"priority": priority,
		"source": source if not source.is_empty() else _get_caller_info()
	}

	_subscribers[event_type].append(subscriber)

	# 按优先级排序
	_subscribers[event_type].sort_custom(func(a, b): return a.priority < b.priority)

	if DebugFlags.verbose_logging:
		GameLog.debug("EventBus", "订阅事件: %s (优先级: %d, 来源: %s)" % [
			event_type, priority, subscriber.source
		])

# 取消订阅
func unsubscribe(event_type: String, callback: Callable) -> bool:
	if not _subscribers.has(event_type):
		return false

	var subscribers: Array = _subscribers[event_type]
	for i in range(subscribers.size() - 1, -1, -1):
		if subscribers[i].callback == callback:
			subscribers.remove_at(i)
			if DebugFlags.verbose_logging:
				GameLog.debug("EventBus", "取消订阅: %s" % event_type)
			return true

	return false

# 取消指定来源的所有订阅
func unsubscribe_all_from_source(source: String) -> int:
	var count := 0
	for event_type in _subscribers:
		var subscribers: Array = _subscribers[event_type]
		for i in range(subscribers.size() - 1, -1, -1):
			if subscribers[i].source == source:
				subscribers.remove_at(i)
				count += 1

	if count > 0:
		GameLog.info("EventBus", "取消来自 %s 的 %d 个订阅" % [source, count])
	return count

# === 事件发射 ===

# 发射事件
func emit_event(event_type: String, data: Dictionary = {}) -> void:
	_event_sequence += 1

	var event := {
		"type": event_type,
		"data": data,
		"sequence": _event_sequence,
		# 为保证回放/日志可比对，这里使用确定性的序号作为“事件时间戳”
		"timestamp": _event_sequence
	}
	# 仅用于调试展示（非确定性）
	if DebugFlags.debug_mode:
		event["real_time_msec"] = Time.get_ticks_msec()

	# 记录历史
	if _history_enabled:
		_add_to_history(event)

	# 通知订阅者
	if _subscribers.has(event_type):
		var subscribers: Array = _subscribers[event_type]
		var snapshot: Array = subscribers.duplicate()
		for subscriber_val in snapshot:
			if not (subscriber_val is Dictionary):
				continue
			var subscriber: Dictionary = subscriber_val
			var cb: Callable = subscriber.get("callback", Callable())
			if not cb.is_valid():
				continue
			cb.call(event)

		# 清理已失效的回调（例如订阅者对象已释放）
		var removed := 0
		for i in range(subscribers.size() - 1, -1, -1):
			var subscriber_val2 = subscribers[i]
			if not (subscriber_val2 is Dictionary):
				subscribers.remove_at(i)
				removed += 1
				continue
			var subscriber2: Dictionary = subscriber_val2
			var cb2: Callable = subscriber2.get("callback", Callable())
			if not cb2.is_valid():
				subscribers.remove_at(i)
				removed += 1

		if removed > 0 and DebugFlags.verbose_logging:
			GameLog.debug("EventBus", "已移除 %d 个无效订阅: %s" % [removed, event_type])

	if DebugFlags.verbose_logging:
		GameLog.debug("EventBus", "发射事件: %s (序号: %d)" % [event_type, _event_sequence])

# 批量发射事件（保证顺序）
func emit_events(events: Array[Dictionary]) -> void:
	for event_data in events:
		var event_type: String = event_data.get("type", "")
		var data: Dictionary = event_data.get("data", {})
		if not event_type.is_empty():
			emit_event(event_type, data)

# === 历史管理 ===

func _add_to_history(event: Dictionary) -> void:
	_event_history.append(event)

	# 限制历史大小
	while _event_history.size() > _max_history_size:
		_event_history.pop_front()

# 获取事件历史
func get_history(count: int = -1) -> Array[Dictionary]:
	if count < 0 or count >= _event_history.size():
		return _event_history.duplicate()

	var result: Array[Dictionary] = []
	var start := _event_history.size() - count
	for i in range(start, _event_history.size()):
		result.append(_event_history[i])
	return result

# 获取特定类型的事件历史
func get_history_by_type(event_type: String, count: int = -1) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for event in _event_history:
		if event.type == event_type:
			filtered.append(event)

	if count < 0 or count >= filtered.size():
		return filtered

	return filtered.slice(filtered.size() - count)

# 清空历史
func clear_history() -> void:
	_event_history.clear()
	GameLog.info("EventBus", "事件历史已清空")

# 启用/禁用历史记录
func set_history_enabled(enabled: bool) -> void:
	_history_enabled = enabled

# 设置历史最大容量
func set_max_history_size(size: int) -> void:
	_max_history_size = max(100, size)

# === 查询 ===

# 获取某事件类型的订阅者数量
func get_subscriber_count(event_type: String) -> int:
	if _subscribers.has(event_type):
		return _subscribers[event_type].size()
	return 0

# 获取所有事件类型
func get_all_event_types() -> Array:
	return _subscribers.keys()

# 检查是否有订阅者
func has_subscribers(event_type: String) -> bool:
	return _subscribers.has(event_type) and _subscribers[event_type].size() > 0

# === 调试 ===

func _get_caller_info() -> String:
	# 获取调用者信息（用于调试）
	var stack := get_stack()
	if stack.size() > 2:
		var caller = stack[2]
		return "%s:%d" % [caller.source.get_file(), caller.line]
	return "unknown"

# 获取状态摘要
func get_status() -> Dictionary:
	var subscriber_counts := {}
	for event_type in _subscribers:
		subscriber_counts[event_type] = _subscribers[event_type].size()

	return {
		"event_types": _subscribers.size(),
		"total_subscribers": _get_total_subscribers(),
		"history_size": _event_history.size(),
		"event_sequence": _event_sequence,
		"subscriber_counts": subscriber_counts
	}

func _get_total_subscribers() -> int:
	var total := 0
	for event_type in _subscribers:
		total += _subscribers[event_type].size()
	return total

# 打印调试信息
func dump() -> String:
	var output := "=== EventBus Status ===\n"
	output += "Event Sequence: %d\n" % _event_sequence
	output += "History Size: %d / %d\n" % [_event_history.size(), _max_history_size]
	output += "Subscriptions:\n"

	for event_type in _subscribers:
		var subs: Array = _subscribers[event_type]
		output += "  %s: %d subscribers\n" % [event_type, subs.size()]
		for sub in subs:
			output += "    - priority: %d, source: %s\n" % [sub.priority, sub.source]

	return output
