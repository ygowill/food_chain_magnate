# Game scene：事件日志控制器
# 负责：订阅 EventBus 事件，并写入 GameLogPanel（UI）
class_name GameEventLogController
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

const EVENT_TYPES_TO_LOG: Array[String] = [
	EventBus.EventType.PHASE_CHANGED,
	EventBus.EventType.SUB_PHASE_CHANGED,
	EventBus.EventType.ROUND_STARTED,
	EventBus.EventType.ROUND_ENDED,
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
	EventBus.EventType.FOOD_SOLD,
	EventBus.EventType.FOOD_DISCARDED,
	EventBus.EventType.DRINKS_PROCURED,
	EventBus.EventType.MARKETING_PLACED,
	EventBus.EventType.MARKETING_EXPIRED,
	EventBus.EventType.DEMAND_GENERATED,
	EventBus.EventType.MILESTONE_ACHIEVED,
	EventBus.EventType.GAME_STARTED,
	EventBus.EventType.GAME_ENDED,
]

const PRICE_ACTION_LOG_TEXT: Dictionary = {
	"set_price": "设定价格（-$1）",
	"set_discount": "设定折扣（-$3）",
	"set_luxury_price": "设定奢侈品价格（+$10）",
}

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
		EventBus.EventType.ROUND_ENDED:
			var round := int(data.get("round", -1))
			var next_round := int(data.get("next_round", -1))
			var text := "回合结束: %d" % round
			if next_round > 0 and next_round != round:
				text += " -> %d" % next_round
			_game_log_panel.add_phase_log(text, data)
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
		EventBus.EventType.PLAYER_BROKE:
			var player_id := int(data.get("player_id", -1))
			var reason := str(data.get("reason", "")).strip_edges()
			var cash := int(data.get("cash", 0))
			var text := "玩家 %d 破产（现金: %d）" % [player_id + 1, cash]
			if not reason.is_empty():
				text += "：" + reason
			_game_log_panel.add_event_log(text, data)
		EventBus.EventType.COMMAND_EXECUTED:
			# CommandRunner 会为每条命令广播 COMMAND_EXECUTED；这里仅记录定价类强制动作（用于“自动完成”可见性）。
			if not data.has("price_modifier"):
				return
			var action_id := str(data.get("action_id", "")).strip_edges()
			if not PRICE_ACTION_LOG_TEXT.has(action_id):
				return
			var player_id := int(data.get("player_id", -1))
			if player_id < 0:
				return
			_game_log_panel.add_player_log(player_id, str(PRICE_ACTION_LOG_TEXT[action_id]), data)
		EventBus.EventType.EMPLOYEE_ACTIVATED:
			var player_id := int(data.get("player_id", -1))
			var employee_id := str(data.get("employee_id", "")).strip_edges()
			var location := _format_employee_location(str(data.get("location", "")).strip_edges())
			var employee_name := _employee_name(employee_id)
			var text := "员工启用：%s" % (employee_name if not employee_name.is_empty() else employee_id)
			if not location.is_empty():
				text += "（%s）" % location
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.EMPLOYEE_RECRUITED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var text := "招聘 %s" % (employee_name if not employee_name.is_empty() else employee_type)
			var flags: Array[String] = []
			var to_reserve_val = data.get("to_reserve", null)
			if to_reserve_val is bool:
				flags.append("待命" if bool(to_reserve_val) else "在岗")
			if bool(data.get("on_credit", false)):
				flags.append("缺货预支")
			if not flags.is_empty():
				text += "（%s）" % "，".join(flags)
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.EMPLOYEE_TRAINED:
			var player_id := int(data.get("player_id", -1))
			var from_employee := str(data.get("from_employee", "")).strip_edges()
			var to_employee := str(data.get("to_employee", "")).strip_edges()
			var from_name := _employee_name(from_employee)
			var to_name := _employee_name(to_employee)
			var text := "培训 %s -> %s" % [
				from_name if not from_name.is_empty() else from_employee,
				to_name if not to_name.is_empty() else to_employee,
			]
			if bool(data.get("from_pending", false)):
				text += "（预支清账）"
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.EMPLOYEE_FIRED:
			var player_id := int(data.get("player_id", -1))
			var employee_id := str(data.get("employee_id", "")).strip_edges()
			var employee_name := _employee_name(employee_id)
			var location := _format_employee_location(str(data.get("location", "")).strip_edges())
			var text := "解雇 %s" % (employee_name if not employee_name.is_empty() else employee_id)
			if not location.is_empty():
				text += "（%s）" % location
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.RESTAURANT_PLACED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var pos_text := _format_position(data.get("position", null))
			var text := "放置餐厅"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not pos_text.is_empty():
				text += " %s" % pos_text
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.RESTAURANT_MOVED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var pos_text := _format_position(data.get("position", null))
			var rotation := int(data.get("rotation", 0))
			var text := "移动餐厅"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not pos_text.is_empty():
				text += " %s" % pos_text
			if rotation != 0:
				text += " 旋转%d°" % rotation
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.HOUSE_PLACED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var house_number := int(data.get("house_number", -1))
			var pos_text := _format_position(data.get("position", null))
			var text := "放置房屋"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if house_number > 0:
				text += " #%d" % house_number
			if not pos_text.is_empty():
				text += " %s" % pos_text
			if bool(data.get("has_garden", false)):
				text += "（含花园）"
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.GARDEN_ADDED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var house_number := int(data.get("house_number", -1))
			var house_id := str(data.get("house_id", "")).strip_edges()
			var direction := _format_direction(str(data.get("direction", "")).strip_edges())
			var pos_text := _format_position(data.get("position", null))
			var details: Array[String] = []
			if house_number > 0:
				details.append("房屋#%d" % house_number)
			elif not house_id.is_empty():
				details.append("房屋%s" % house_id)
			if not direction.is_empty():
				details.append(direction)
			if not pos_text.is_empty():
				details.append(pos_text)
			var text := "添加花园"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not details.is_empty():
				text += "：" + " ".join(details)
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.FOOD_PRODUCED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var food_type := str(data.get("food_type", "")).strip_edges()
			if food_type.is_empty():
				food_type = str(data.get("product", "")).strip_edges()
			var food_name := _product_name(food_type)
			var amount := int(data.get("amount", 0))
			var text := "生产食物"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not food_name.is_empty():
				if amount > 0:
					text += "：" + "%s x%d" % [food_name, amount]
				else:
					text += "：" + food_name
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.FOOD_SOLD:
			var player_id := int(data.get("player_id", -1))
			var house_number := str(data.get("house_number", "")).strip_edges()
			var rest_text := _format_restaurant_id_short(str(data.get("restaurant_id", "")).strip_edges())
			var required_val = data.get("required", null)
			var required: Dictionary = required_val if (required_val is Dictionary) else {}
			var req_text := _format_required_short(required, 4)
			var revenue := int(data.get("revenue", 0))
			var bonus := int(data.get("bonus", 0))
			var house_bonus := int(data.get("house_bonus", 0))

			var text := "售出"
			if not house_number.is_empty():
				text += "：房屋#%s" % house_number
			if not rest_text.is_empty():
				text += " -> %s" % rest_text
			var meta: Array[String] = []
			if not req_text.is_empty():
				meta.append("需求: %s" % req_text)
			if revenue != 0:
				meta.append("收入: %d" % revenue)
			if bonus != 0:
				meta.append("营销奖励: %+d" % bonus)
			if house_bonus != 0:
				meta.append("房屋奖励: %+d" % house_bonus)
			if not meta.is_empty():
				text += "（%s）" % "；".join(meta)
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.FOOD_DISCARDED:
			var player_id := int(data.get("player_id", -1))
			var discarded_val = data.get("discarded", null)
			var discarded: Dictionary = discarded_val if (discarded_val is Dictionary) else {}
			var disc_text := _format_required_short(discarded, 5)
			var has_fridge := bool(data.get("has_fridge", false))
			var text := "清理库存"
			if not disc_text.is_empty():
				text += "：丢弃 %s" % disc_text
			text += "（%s）" % ("有冰箱" if has_fridge else "无冰箱")
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.DRINKS_PROCURED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var drinks_text := _format_drinks_procured(data.get("drinks_procured", {}))
			var rest_text := _format_restaurant_id_short(str(data.get("restaurant_id", "")).strip_edges())
			var sources_text := _format_picked_drink_sources_short(data.get("picked_sources", null), 3)
			var text := "采购饮料"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not drinks_text.is_empty():
				text += "：" + drinks_text
			var meta: Array[String] = []
			if not rest_text.is_empty():
				meta.append("起点: %s" % rest_text)
			if not sources_text.is_empty():
				meta.append("进货点: %s" % sources_text)
			if not meta.is_empty():
				text += "（%s）" % "；".join(meta)
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.DEMAND_GENERATED:
			var player_id := int(data.get("player_id", -1))
			var board_number := int(data.get("board_number", 0))
			var marketing_type := _format_marketing_type_short(str(data.get("marketing_type", "")).strip_edges())
			var product_name := _product_name(str(data.get("product", "")).strip_edges())
			var demands_added := int(data.get("demands_added", 0))
			var houses_text := _format_house_numbers_short(data.get("affected_house_numbers", null), 4)

			var parts: Array[String] = []
			if board_number > 0:
				parts.append("板#%d" % board_number)
			if not product_name.is_empty():
				parts.append(product_name)
			if not marketing_type.is_empty():
				parts.append(marketing_type)
			if not houses_text.is_empty():
				parts.append("覆盖%s" % houses_text)
			if demands_added != 0:
				parts.append("%+d需求" % demands_added)

			var text := "营销生效"
			if not parts.is_empty():
				text += "：" + " ".join(parts)
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.MARKETING_EXPIRED:
			var player_id := int(data.get("player_id", -1))
			var board_number := int(data.get("board_number", 0))
			var marketing_type := _format_marketing_type_short(str(data.get("marketing_type", "")).strip_edges())
			var product_name := _product_name(str(data.get("product", "")).strip_edges())
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var duration_before := int(data.get("duration_before", 0))
			var duration_after := int(data.get("duration_after", 0))

			var parts: Array[String] = []
			if board_number > 0:
				parts.append("板#%d" % board_number)
			if not product_name.is_empty():
				parts.append(product_name)
			if not marketing_type.is_empty():
				parts.append(marketing_type)
			if not employee_name.is_empty():
				parts.append(employee_name)
			if duration_before > 0 or duration_after > 0:
				parts.append("%d->%d" % [duration_before, duration_after])

			var text := "营销到期"
			if not parts.is_empty():
				text += "：" + " ".join(parts)
			_game_log_panel.add_player_log(player_id, text, data)
		EventBus.EventType.MARKETING_PLACED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var product_name := _product_name(str(data.get("product", "")).strip_edges())
			var board_number := int(data.get("board_number", 0))
			var duration := int(data.get("duration", 0))
			var axis := _format_marketing_axis(str(data.get("axis", "")).strip_edges())
			var pos_text := _format_position(data.get("position", null))
			var parts: Array[String] = []
			if board_number > 0:
				parts.append("板#%d" % board_number)
			if not product_name.is_empty():
				parts.append(product_name)
			if duration > 0:
				parts.append("%d回合" % duration)
			if not axis.is_empty():
				parts.append(axis)
			if not pos_text.is_empty():
				parts.append(pos_text)
			var text := "发起营销"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not parts.is_empty():
				text += "：" + " ".join(parts)
			_game_log_panel.add_player_log(player_id, text, data)
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
		EventBus.EventType.GAME_STARTED:
			_game_log_panel.add_system_log("游戏开始", data)
		EventBus.EventType.GAME_ENDED:
			var reason := str(data.get("reason", "")).strip_edges()
			var text := "游戏结束"
			if not reason.is_empty():
				text += "：" + reason
			_game_log_panel.add_system_log(text, data)
		EventBus.EventType.DINNERTIME_REPORT:
			_log_dinnertime_report(data)
		_:
			_game_log_panel.add_debug_log("%s: %s" % [t, str(data)], data)

func _product_name(product_id: String) -> String:
	var pid := str(product_id).strip_edges()
	if pid.is_empty():
		return ""
	if ProductRegistryClass.is_loaded():
		var def_val = ProductRegistryClass.get_def(pid)
		if def_val != null and def_val is ProductDef:
			var n := str((def_val as ProductDef).name).strip_edges()
			if not n.is_empty():
				return n
	return pid

func _employee_name(employee_type: String) -> String:
	var eid := str(employee_type).strip_edges()
	if eid.is_empty():
		return ""
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(eid)
		if def_val != null and def_val is EmployeeDef:
			var name := str((def_val as EmployeeDef).name).strip_edges()
			if not name.is_empty():
				return name
	return eid

func _format_position(pos_val) -> String:
	if pos_val == null:
		return ""
	if pos_val is Vector2i:
		var p: Vector2i = pos_val
		return "(%d,%d)" % [p.x, p.y]
	if pos_val is Array:
		var arr: Array = pos_val
		if arr.size() >= 2:
			var x_val = arr[0]
			var y_val = arr[1]
			if (x_val is int or x_val is float) and (y_val is int or y_val is float):
				return "(%d,%d)" % [int(x_val), int(y_val)]
	return ""

func _format_employee_location(location: String) -> String:
	match str(location).strip_edges():
		"active":
			return "在岗"
		"reserve":
			return "待命"
		"busy":
			return "忙碌营销"
		_:
			return ""

func _format_direction(direction: String) -> String:
	match str(direction).strip_edges():
		"N":
			return "北"
		"E":
			return "东"
		"S":
			return "南"
		"W":
			return "西"
		_:
			return ""

func _format_marketing_axis(axis: String) -> String:
	match str(axis).strip_edges():
		"row":
			return "横向"
		"col":
			return "纵向"
		_:
			return ""

func _format_marketing_type_short(marketing_type: String) -> String:
	match str(marketing_type).strip_edges():
		"billboard":
			return "广告牌"
		"mailbox":
			return "邮箱"
		"radio":
			return "电台"
		"airplane":
			return "飞机"
		_:
			return str(marketing_type).strip_edges()

func _format_restaurant_id_short(restaurant_id: String) -> String:
	var rid := str(restaurant_id).strip_edges()
	if rid.is_empty():
		return ""
	if rid.begins_with("rest_"):
		var tail := rid.substr(5)
		if tail.is_valid_int():
			return "餐厅#%d" % (int(tail) + 1)
	return rid

func _format_picked_drink_sources_short(picked_sources_val, max_items: int = 3) -> String:
	if picked_sources_val == null or not (picked_sources_val is Array):
		return ""
	var picked_sources: Array = picked_sources_val
	if picked_sources.is_empty():
		return ""

	# product_id -> count
	var counts: Dictionary = {}
	for src_val in picked_sources:
		if not (src_val is Dictionary):
			continue
		var src: Dictionary = src_val
		var pid := str(src.get("type", "")).strip_edges()
		if pid.is_empty():
			continue
		counts[pid] = int(counts.get(pid, 0)) + 1

	if counts.is_empty():
		return ""

	var keys := counts.keys()
	keys.sort()
	var parts: Array[String] = []
	var shown := 0
	for k_val in keys:
		if shown >= max_items:
			break
		var pid2 := str(k_val).strip_edges()
		if pid2.is_empty():
			continue
		var c := int(counts.get(k_val, 0))
		if c <= 0:
			continue
		if c > 1:
			parts.append("%s x%d" % [_product_name(pid2), c])
		else:
			parts.append(_product_name(pid2))
		shown += 1

	var suffix := ""
	if keys.size() > shown:
		suffix = " ..."
	return "，".join(parts) + suffix

func _format_house_numbers_short(house_numbers_val, max_items: int = 4) -> String:
	if house_numbers_val == null or not (house_numbers_val is Array):
		return ""
	var arr: Array = house_numbers_val
	if arr.is_empty():
		return ""
	var nums: Array[int] = []
	for v in arr:
		if v is int:
			if int(v) > 0:
				nums.append(int(v))
		elif v is float:
			var f: float = float(v)
			if f == floor(f) and int(f) > 0:
				nums.append(int(f))
	if nums.is_empty():
		return ""
	nums.sort()

	var shown := mini(nums.size(), maxi(1, max_items))
	var parts: Array[String] = []
	for i in range(shown):
		parts.append("#%d" % nums[i])
	var text := "房屋" + ",".join(parts)
	if nums.size() > shown:
		text += "…(共%d)" % nums.size()
	return text

func _format_drinks_procured(drinks_procured_val) -> String:
	if drinks_procured_val == null or not (drinks_procured_val is Dictionary):
		return ""
	var drinks_procured: Dictionary = drinks_procured_val
	if drinks_procured.is_empty():
		return ""
	var keys := drinks_procured.keys()
	keys.sort()
	var parts: Array[String] = []
	for k_val in keys:
		var pid := str(k_val).strip_edges()
		if pid.is_empty():
			continue
		var amount := int(drinks_procured.get(k_val, 0))
		if amount <= 0:
			continue
		parts.append("%s x%d" % [_product_name(pid), amount])
	return " + ".join(parts)

func _format_required_short(required: Dictionary, max_items: int = 3) -> String:
	if required == null or not (required is Dictionary) or required.is_empty():
		return ""
	var keys := required.keys()
	keys.sort()
	var parts: Array[String] = []
	var shown := 0
	for k_val in keys:
		if shown >= max_items:
			break
		var pid := str(k_val).strip_edges()
		if pid.is_empty():
			continue
		var c := int(required.get(k_val, 0))
		if c <= 0:
			continue
		parts.append("%s x%d" % [_product_name(pid), c])
		shown += 1
	var suffix := ""
	if keys.size() > shown:
		suffix = " ..."
	return " + ".join(parts) + suffix

func _log_dinnertime_report(data: Dictionary) -> void:
	if not is_instance_valid(_game_log_panel):
		return
	var round := int(data.get("round", -1))
	var report_val = data.get("report", null)
	if not (report_val is Dictionary):
		_game_log_panel.add_event_log("晚餐结算报告缺失（回合 %d）" % round, data)
		return
	var report: Dictionary = report_val

	var sales_val = report.get("sales", null)
	var skipped_val = report.get("skipped", null)
	var income_sales_val = report.get("income_sales", null)
	var income_house_bonus_val = report.get("income_sale_house_bonus", null)
	var income_tips_val = report.get("income_tips", null)
	var income_cfo_val = report.get("income_cfo_bonus", null)
	var total_income_val = report.get("total_income", null)

	var sales: Array = sales_val if (sales_val is Array) else []
	var skipped: Array = skipped_val if (skipped_val is Array) else []

	_game_log_panel.add_event_log("晚餐结算（回合 %d）：售出 %d，未满足 %d" % [round, sales.size(), skipped.size()], data)

	# 1) 每个房屋消费记录
	for s_val in sales:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var owner := int(s.get("winner_owner", -1))
		var house_number := str(s.get("house_number", "")).strip_edges()
		var required_val = s.get("required", null)
		var required: Dictionary = required_val if (required_val is Dictionary) else {}
		var revenue := int(s.get("revenue", 0))
		var bonus := int(s.get("bonus", 0))
		var house_bonus := int(s.get("house_bonus", 0))

		var items := _format_required_short(required, 3)
		var msg := "晚餐：房屋#%s 消费 %s 收入 $%d" % [house_number, items, revenue]
		if bonus != 0 or house_bonus != 0:
			msg += " (奖励 $%d, 房屋奖 $%d)" % [bonus, house_bonus]
		if owner >= 0:
			_game_log_panel.add_player_log(owner, msg, s)
		else:
			_game_log_panel.add_event_log(msg, s)

	for sk_val in skipped:
		if not (sk_val is Dictionary):
			continue
		var sk: Dictionary = sk_val
		var hn := str(sk.get("house_number", "")).strip_edges()
		var dcnt := int(sk.get("demands", 0))
		_game_log_panel.add_event_log("晚餐：房屋#%s 未满足（需求 %d）" % [hn, dcnt], sk)

	# 2) 总结报告（按玩家/按分类）
	var income_sales: Array = income_sales_val if (income_sales_val is Array) else []
	var income_house_bonus: Array = income_house_bonus_val if (income_house_bonus_val is Array) else []
	var income_tips: Array = income_tips_val if (income_tips_val is Array) else []
	var income_cfo: Array = income_cfo_val if (income_cfo_val is Array) else []
	var total_income: Array = total_income_val if (total_income_val is Array) else []

	var player_count := maxi(income_sales.size(), total_income.size())
	for pid in range(player_count):
		var s_amt := int(income_sales[pid]) if pid < income_sales.size() else 0
		var hb_amt := int(income_house_bonus[pid]) if pid < income_house_bonus.size() else 0
		var tips_amt := int(income_tips[pid]) if pid < income_tips.size() else 0
		var cfo_amt := int(income_cfo[pid]) if pid < income_cfo.size() else 0
		var tot_amt := int(total_income[pid]) if pid < total_income.size() else (s_amt + hb_amt + tips_amt + cfo_amt)

		_game_log_panel.add_event_log("晚餐总结 玩家%d: 总 $%d (售卖 $%d, 房屋奖 $%d, 服务员 $%d, CFO $%d)" % [
			pid + 1, tot_amt, s_amt, hb_amt, tips_amt, cfo_amt
		], {"round": round, "player_id": pid})
