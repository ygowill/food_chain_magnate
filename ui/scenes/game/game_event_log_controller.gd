# Game scene：事件日志控制器
# 负责：订阅 EventBus 事件，并写入 GameLogPanel（UI）
class_name GameEventLogController
extends RefCounted

var _game_log_panel = null

func setup(game_log_panel) -> void:
	if not is_instance_valid(game_log_panel):
		return
	_game_log_panel = game_log_panel

	_game_log_panel.clear_logs()
	_game_log_panel.add_system_log("事件日志已启用")

	var event_types: Array[String] = [
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

	for t in event_types:
		EventBus.subscribe(t, Callable(self, "_on_eventbus_event"), 100, "GameScene")

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
			_game_log_panel.add_event_log("里程碑达成: %s" % str(data.get("milestone_id", "")), data)
		_:
			_game_log_panel.add_debug_log("%s: %s" % [t, str(data)], data)
