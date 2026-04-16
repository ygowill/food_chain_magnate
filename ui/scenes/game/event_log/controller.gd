# Game scene：事件日志控制器
# 负责：订阅 EventBus 事件，并写入 GameLogPanel（UI）
class_name GameEventLogController
extends RefCounted

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
	_ensure_formatter()

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
	if _formatter != null and is_instance_valid(_formatter):
		if _formatter.has_method("dispose"):
			_formatter.dispose()
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
			if not PRICE_ACTION_LOG_TEXT.has(action_id):
				continue
		result.append(ev)

	return result

func _on_eventbus_event(event: Dictionary) -> void:
	if not is_instance_valid(_game_log_panel):
		return
	if not (event is Dictionary) or event.is_empty():
		return
	# 根因修复：
	# - 当 GameLogPanel 已进入 step_timeline 模式后，实时 EventBus 事件会在下一次
	#   apply_live_log_timeline_from_engine 中被统一投影到 _timeline_entries。
	# - 若这里仍直接 add_log，会把同一事件再写入 _extra_entries，
	#   后续 timeline append/load 后就会出现 recruit/train 等日志重复一份。
	# - 因此 timeline 模式下交给 timeline 刷新链路唯一产生日志；仅在 flat/legacy 模式下直接追加。
	if _game_log_panel.has_method("has_step_timeline_loaded") and bool(_game_log_panel.call("has_step_timeline_loaded")):
		return
	_ensure_formatter()
	if _formatter == null or not is_instance_valid(_formatter):
		return

	var cmd_index := _infer_command_index(event)
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
		var entry_id: int = _game_log_panel.add_log(int(type_val), msg, details)
		if _game_log_panel.has_method("set_entry_command_index"):
			_game_log_panel.set_entry_command_index(entry_id, cmd_index)

func _ensure_formatter() -> void:
	if _formatter != null and is_instance_valid(_formatter):
		return
	var formatter_script = ResourceLoader.load(
		GAME_EVENT_LOG_FORMATTER_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if formatter_script == null:
		return
	_formatter = formatter_script.new()

func _infer_command_index(event: Dictionary) -> int:
	if event == null or not (event is Dictionary):
		return -1
	var data_val = event.get("data", null)
	if data_val is Dictionary:
		var data: Dictionary = data_val
		var ci_val = data.get("command_index", null)
		if ci_val is int:
			return int(ci_val)
		if ci_val is float:
			var f: float = float(ci_val)
			if f == floor(f):
				return int(f)

	# 运行时事件通常不携带 command_index：用当前引擎指针兜底。
	if Globals != null and Globals.current_game_engine != null:
		return int(Globals.current_game_engine.current_command_index)
	return -1
