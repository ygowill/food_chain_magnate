# Game scene：事件日志控制器
# 负责：订阅 EventBus 事件，并写入 GameLogPanel（UI）
class_name GameEventLogController
extends RefCounted

const GameEventLogFormatterClass = preload("res://ui/scenes/game/game_event_log_formatter.gd")

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
	EventBus.EventType.COMMAND_EXECUTED, # 仅筛选少量需要展示的动作（避免日志过噪）
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

var _game_log_panel = null
var _eventbus_source: String = ""
var _formatter = null # GameEventLogFormatter（避免 class_name cache 未更新导致的类型解析失败）

func setup(game_log_panel, restore_history: bool = true) -> void:
	if not is_instance_valid(game_log_panel):
		return
	_game_log_panel = game_log_panel
	if _eventbus_source.is_empty():
		_eventbus_source = "GameScene:%s" % str(get_instance_id())
	if _formatter == null:
		_formatter = GameEventLogFormatterClass.new()

	_game_log_panel.clear_logs()
	var history_events: Array[Dictionary] = []
	if restore_history:
		history_events = _collect_history_events()
	var restored_count := history_events.size()
	if restored_count > 0:
		_game_log_panel.add_system_log("事件日志已启用（已恢复 %d 条历史日志）" % restored_count)
		for event in history_events:
			_on_eventbus_event(event)
	else:
		_game_log_panel.add_system_log("事件日志已启用")

	for t in EVENT_TYPES_TO_LOG:
		EventBus.subscribe(t, Callable(self, "_on_eventbus_event"), 100, _eventbus_source)

func rebuild_from_history() -> void:
	# 用于 undo/redo/时间线回退：EventBus.history 已被重建，但 UI 面板需要重新从 history 恢复显示。
	if not is_instance_valid(_game_log_panel):
		return

	_game_log_panel.clear_logs()
	var history_events: Array[Dictionary] = _collect_history_events()
	var restored_count := history_events.size()
	if restored_count > 0:
		_game_log_panel.add_system_log("事件日志已更新（已恢复 %d 条历史日志）" % restored_count)
		for event in history_events:
			_on_eventbus_event(event)
	else:
		_game_log_panel.add_system_log("事件日志已更新")

func dispose() -> void:
	if not _eventbus_source.is_empty():
		EventBus.unsubscribe_all_from_source(_eventbus_source)
	_eventbus_source = ""
	_game_log_panel = null
	_formatter = null

func _collect_history_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var history: Array = EventBus.get_history()
	if history.is_empty():
		return result

	var type_set := {}
	for t in EVENT_TYPES_TO_LOG:
		type_set[str(t)] = true

	for ev_val in history:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t: String = str(ev.get("type", ""))
		if t.is_empty():
			continue
		if not type_set.has(t):
			continue
		if t == EventBus.EventType.COMMAND_EXECUTED:
			var data_val = ev.get("data", null)
			if not (data_val is Dictionary):
				continue
			var data: Dictionary = data_val
			if not data.has("price_modifier"):
				continue
			var action_id := str(data.get("action_id", "")).strip_edges()
			if not GameEventLogFormatterClass.PRICE_ACTION_LOG_TEXT.has(action_id):
				continue
		result.append(ev)

	return result

func _on_eventbus_event(event: Dictionary) -> void:
	if not is_instance_valid(_game_log_panel):
		return
	if not (event is Dictionary) or event.is_empty():
		return
	if _formatter == null:
		_formatter = GameEventLogFormatterClass.new()

	var entries: Array = _formatter.format(event)
	for e_val in entries:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		var type_val = e.get("type", GameLogPanel.LogType.DEBUG)
		var msg := str(e.get("message", ""))
		if msg.is_empty():
			continue
		var details_val = e.get("details", {})
		var details: Dictionary = details_val if (details_val is Dictionary) else {}
		_game_log_panel.add_log(int(type_val), msg, details)
