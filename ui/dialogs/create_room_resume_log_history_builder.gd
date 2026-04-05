extends RefCounted

const EventHistoryRebuildClass = preload("res://core/engine/game_engine/event_history_rebuild.gd")

const GAME_EVENT_LOG_FORMATTER_SCRIPT_PATH := "res://ui/scenes/game/event_log/formatter.gd"
const PRICE_ACTION_LOG_TEXT: Dictionary = {
	"set_price": "设定价格（-$1）",
	"set_discount": "设定折扣（-$3）",
	"set_luxury_price": "设定奢侈品价格（+$10）",
}
const EVENT_TYPES_TO_LOG: Array[String] = [
	EventBus.EventType.PHASE_CHANGED,
	EventBus.EventType.SUB_PHASE_CHANGED,
	EventBus.EventType.ROUND_STARTED,
	EventBus.EventType.ROUND_ENDED,
	EventBus.EventType.TURN_ORDER_FINALIZED,
	EventBus.EventType.PAYDAY_REPORT,
	EventBus.EventType.DINNERTIME_REPORT,
	EventBus.EventType.PLAYER_TURN_STARTED,
	EventBus.EventType.PLAYER_TURN_ENDED,
	EventBus.EventType.PLAYER_CASH_CHANGED,
	EventBus.EventType.PLAYER_BROKE,
	EventBus.EventType.COMMAND_EXECUTED,
	EventBus.EventType.EMPLOYEE_ACTIVATED,
	EventBus.EventType.EMPLOYEE_RECRUITED,
	EventBus.EventType.EMPLOYEE_TRAINED,
	EventBus.EventType.EMPLOYEE_FIRED,
	EventBus.EventType.RESTAURANT_PLACED,
	EventBus.EventType.RESTAURANT_MOVED,
	EventBus.EventType.HOUSE_PLACED,
	EventBus.EventType.GARDEN_ADDED,
	EventBus.EventType.FOOD_PRODUCED,
	EventBus.EventType.FOOD_DISCARDED,
	EventBus.EventType.DRINKS_PROCURED,
	EventBus.EventType.MARKETING_PLACED,
	EventBus.EventType.MARKETING_EXPIRED,
	EventBus.EventType.DEMAND_GENERATED,
	EventBus.EventType.MILESTONE_ACHIEVED,
	EventBus.EventType.GAME_STARTED,
	EventBus.EventType.GAME_ENDED,
]

func build(engine: GameEngine, original_current_index: int) -> Result:
	if engine == null:
		return Result.failure("恢复日志构建失败：engine 为空")

	var max_index := int(engine.command_history.size()) - 1
	var normalized_original := mini(maxi(int(original_current_index), -1), max_index)
	var items: Array[Dictionary] = [_make_item(-1, "开局（未执行命令）", false, false)]
	var warnings: Array[String] = []

	var history_events: Array = []
	var history_r: Result = EventHistoryRebuildClass.build(engine, max_index)
	if history_r.ok:
		if history_r.value is Array:
			history_events = history_r.value
		warnings.append_array(history_r.warnings)
	else:
		warnings.append("无法构建完整日志历史，已回退为关键恢复时间点：%s" % history_r.error)

	var formatter = _create_formatter()
	if not history_events.is_empty():
		if formatter == null or not is_instance_valid(formatter):
			warnings.append("无法加载日志格式化器，已回退为关键恢复时间点列表。")
		else:
			var order := 0
			for event_val in history_events:
				if not (event_val is Dictionary):
					continue
				var event: Dictionary = Dictionary(event_val)
				if not _should_log_event(event):
					continue
				var command_index := _infer_command_index(event)
				var entries: Array = formatter.format(event)
				for entry_val in entries:
					if not (entry_val is Dictionary):
						continue
					var entry: Dictionary = Dictionary(entry_val)
					var message := str(entry.get("message", "")).strip_edges()
					if message.is_empty():
						continue
					var item := _make_item(command_index, message, true, false)
					item["order"] = order
					items.append(item)
					order += 1

	if formatter != null and is_instance_valid(formatter) and formatter.has_method("dispose"):
		formatter.dispose()

	var original_item_index := _attach_anchor(items, normalized_original, "原存档点", "该位置无可展示日志")
	var full_history_item_index := -1
	if max_index >= 0 and max_index != normalized_original:
		full_history_item_index = _attach_anchor(items, max_index, "完整历史末尾", "该位置无可展示日志")

	_finalize_display_texts(items)

	return Result.success({
		"items": items,
		"selected_item_index": original_item_index,
		"original_item_index": original_item_index,
		"full_history_item_index": full_history_item_index,
		"max_command_index": max_index,
	}).with_warnings(warnings)

static func _make_item(command_index: int, message: String, is_log: bool, synthetic: bool) -> Dictionary:
	return {
		"command_index": int(command_index),
		"message": str(message).strip_edges(),
		"display_text": str(message).strip_edges(),
		"is_log": bool(is_log),
		"synthetic": bool(synthetic),
		"tags": [],
	}

static func _create_formatter():
	var formatter_script = ResourceLoader.load(
		GAME_EVENT_LOG_FORMATTER_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if formatter_script == null:
		return null
	return formatter_script.new()

static func _should_log_event(event: Dictionary) -> bool:
	if event == null or not (event is Dictionary):
		return false
	var event_type := str(event.get("type", "")).strip_edges()
	if event_type.is_empty():
		return false
	if not EVENT_TYPES_TO_LOG.has(event_type):
		return false
	if event_type != EventBus.EventType.COMMAND_EXECUTED:
		return true

	var data_val = event.get("data", null)
	if not (data_val is Dictionary):
		return false
	var data: Dictionary = data_val
	if not data.has("price_modifier"):
		return false
	var action_id := str(data.get("action_id", "")).strip_edges()
	return PRICE_ACTION_LOG_TEXT.has(action_id)

static func _infer_command_index(event: Dictionary) -> int:
	if event == null or not (event is Dictionary):
		return -1
	var data_val = event.get("data", null)
	if not (data_val is Dictionary):
		return -1
	var data: Dictionary = data_val
	var ci_val = data.get("command_index", null)
	if ci_val is int:
		return int(ci_val)
	if ci_val is float:
		var f: float = float(ci_val)
		if f == floor(f):
			return int(f)
	return -1

static func _attach_anchor(items: Array[Dictionary], anchor_command_index: int, tag: String, fallback_message: String) -> int:
	var target_item_index := -1
	if anchor_command_index <= -1 and not items.is_empty():
		target_item_index = 0
	else:
		for i in range(items.size() - 1, -1, -1):
			var item_val = items[i]
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = item_val
			if int(item.get("command_index", -999999)) != int(anchor_command_index):
				continue
			target_item_index = i
			break

	if target_item_index < 0:
		var insert_at := items.size()
		for i in range(items.size() - 1, -1, -1):
			var item_val2 = items[i]
			if not (item_val2 is Dictionary):
				continue
			var item2: Dictionary = item_val2
			if int(item2.get("command_index", -999999)) <= int(anchor_command_index):
				insert_at = i + 1
				break
		var synthetic_item := _make_item(anchor_command_index, fallback_message, false, true)
		items.insert(insert_at, synthetic_item)
		target_item_index = insert_at

	var target_item: Dictionary = items[target_item_index]
	var tags: Array = target_item.get("tags", [])
	if not tags.has(tag):
		tags.append(tag)
	target_item["tags"] = tags
	items[target_item_index] = target_item
	return target_item_index

static func _finalize_display_texts(items: Array[Dictionary]) -> void:
	for i in range(items.size()):
		var item_val = items[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var tags_val = item.get("tags", [])
		var tags: Array = tags_val if (tags_val is Array) else []
		var tag_parts: Array[String] = []
		for tag_val in tags:
			var tag := str(tag_val).strip_edges()
			if tag.is_empty():
				continue
			tag_parts.append("【%s】" % tag)

		var message := str(item.get("message", "")).strip_edges()
		var prefix := " ".join(tag_parts)
		var display_text := message
		if not prefix.is_empty():
			display_text = "%s %s" % [prefix, message] if not message.is_empty() else prefix
		item["display_text"] = display_text
		items[i] = item
