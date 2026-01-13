# Game scene：事件日志控制器
# 负责：订阅 EventBus 事件，并写入 GameLogPanel（UI）
class_name GameEventLogController
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

const EVENT_TYPES_TO_LOG: Array[String] = [
	EventBus.EventType.PHASE_CHANGED,
	EventBus.EventType.SUB_PHASE_CHANGED,
	EventBus.EventType.ROUND_STARTED,
	EventBus.EventType.PLAYER_TURN_STARTED,
	EventBus.EventType.PLAYER_TURN_ENDED,
	EventBus.EventType.PLAYER_CASH_CHANGED,
	EventBus.EventType.EMPLOYEE_RECRUITED,
	EventBus.EventType.EMPLOYEE_TRAINED,
	EventBus.EventType.EMPLOYEE_FIRED,
	EventBus.EventType.RESTAURANT_PLACED,
	EventBus.EventType.RESTAURANT_MOVED,
	EventBus.EventType.HOUSE_PLACED,
	EventBus.EventType.GARDEN_ADDED,
	EventBus.EventType.FOOD_PRODUCED,
	EventBus.EventType.DRINKS_PROCURED,
	EventBus.EventType.MILESTONE_ACHIEVED,
]

var _game_log_panel = null
var _eventbus_source: String = ""

func setup(game_log_panel, restore_history: bool = true) -> void:
	if not is_instance_valid(game_log_panel):
		return
	_game_log_panel = game_log_panel
	if _eventbus_source.is_empty():
		_eventbus_source = "GameScene:%s" % str(get_instance_id())

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

func dispose() -> void:
	if not _eventbus_source.is_empty():
		EventBus.unsubscribe_all_from_source(_eventbus_source)
	_eventbus_source = ""
	_game_log_panel = null

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
		result.append(ev)

	return result

func _on_eventbus_event(event: Dictionary) -> void:
	if not is_instance_valid(_game_log_panel):
		return
	if not (event is Dictionary) or event.is_empty():
		return

	var t: String = str(event.get("type", ""))
	var data: Dictionary = event.get("data", {})

	match t:
		EventBus.EventType.PHASE_CHANGED:
			_game_log_panel.add_phase_log("%s -> %s (回合 %d)" % [
				str(data.get("old_phase", "")),
				str(data.get("new_phase", "")),
				int(data.get("round", -1)),
			], data)
		EventBus.EventType.SUB_PHASE_CHANGED:
			_game_log_panel.add_phase_log("子阶段: %s -> %s" % [
				str(data.get("old_sub_phase", "")),
				str(data.get("new_sub_phase", "")),
			], data)
		EventBus.EventType.ROUND_STARTED:
			_game_log_panel.add_phase_log("回合开始: %d" % int(data.get("round", -1)), data)
		EventBus.EventType.PLAYER_TURN_STARTED:
			_game_log_panel.add_phase_log("玩家 %d 开始回合" % (int(data.get("player_id", -1)) + 1), data)
		EventBus.EventType.PLAYER_TURN_ENDED:
			_game_log_panel.add_phase_log("玩家 %d 结束回合 (%s)" % [
				int(data.get("player_id", -1)) + 1,
				str(data.get("action", "")),
			], data)
		EventBus.EventType.PLAYER_CASH_CHANGED:
			_game_log_panel.add_event_log("玩家 %d 现金变化: %d -> %d (%+d)" % [
				int(data.get("player_id", -1)) + 1,
				int(data.get("old_cash", 0)),
				int(data.get("new_cash", 0)),
				int(data.get("delta", 0)),
			], data)
		EventBus.EventType.EMPLOYEE_RECRUITED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "招聘 %s" % str(data.get("employee_type", "")), data)
		EventBus.EventType.EMPLOYEE_TRAINED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "培训 %s -> %s" % [
				str(data.get("from_employee", "")),
				str(data.get("to_employee", "")),
			], data)
		EventBus.EventType.EMPLOYEE_FIRED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "解雇 %s" % str(data.get("employee_id", "")), data)
		EventBus.EventType.RESTAURANT_PLACED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "放置餐厅", data)
		EventBus.EventType.RESTAURANT_MOVED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "移动餐厅", data)
		EventBus.EventType.HOUSE_PLACED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "放置房屋", data)
		EventBus.EventType.GARDEN_ADDED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "添加花园", data)
		EventBus.EventType.FOOD_PRODUCED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "生产 %s" % str(data.get("product", "")), data)
		EventBus.EventType.DRINKS_PROCURED:
			_game_log_panel.add_player_log(int(data.get("player_id", -1)), "采购饮料", data)
		EventBus.EventType.MILESTONE_ACHIEVED:
			var milestone_id := str(data.get("milestone_id", ""))
			var player_id := int(data.get("player_id", -1))
			var name := milestone_id
			if MilestoneRegistryClass.is_loaded() and not milestone_id.is_empty():
				var def_val = MilestoneRegistryClass.get_def(milestone_id)
				if def_val != null and def_val is MilestoneDef:
					name = str((def_val as MilestoneDef).name)
			var who := "玩家%d" % (player_id + 1) if player_id >= 0 else "未知玩家"
			var text := "%s 获得里程碑：%s" % [who, name]
			if not milestone_id.is_empty() and name != milestone_id:
				text += " (%s)" % milestone_id
			_game_log_panel.add_event_log(text, data)
		_:
			_game_log_panel.add_debug_log("%s: %s" % [t, str(data)], data)
