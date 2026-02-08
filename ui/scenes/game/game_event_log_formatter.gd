# Game scene：事件日志格式化器
# 负责：把 EventBus 的事件字典转换为 GameLogPanel 的日志条目（纯格式化，不直接操作节点）。
class_name GameEventLogFormatter
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const ReportsFormatterClass = preload("res://ui/scenes/game/game_event_log_reports_formatter.gd")

const PRICE_ACTION_LOG_TEXT: Dictionary = {
	"set_price": "设定价格（-$1）",
	"set_discount": "设定折扣（-$3）",
	"set_luxury_price": "设定奢侈品价格（+$10）",
}

const CASH_INCOME_BREAKDOWN_LABELS: Dictionary = {
	"food_price": "食物售价",
	"garden_bonus": "花园加成",
	"marketing_bonus": "营销加成",
	"route_purchase_income": "沿路购买收入",
	"park_bonus": "公园加成",
	"fry_chef_bonus": "薯条主厨加成",
	"house_bonus_other": "其它房屋加成",
	"tips": "服务员收入",
	"cfo_bonus": "CFO 加成",
	"revenue_floor_adjustment": "下限调整",
	"other": "其它",
}

const HOUSE_BONUS_BREAKDOWN_LABELS: Dictionary = {
	"park": "公园加成",
	"fry_chef": "薯条主厨加成",
}

var _reports_formatter = null

func format(event: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (event is Dictionary) or event.is_empty():
		return out

	var t: String = str(event.get("type", ""))
	var data_val = event.get("data", null)
	var data: Dictionary = data_val if (data_val is Dictionary) else {}

	match t:
		EventBus.EventType.PHASE_CHANGED:
			out.append(_phase("%s -> %s (回合 %d)" % [
				str(data.get("old_phase", "")),
				str(data.get("new_phase", "")),
				int(data.get("round", -1)),
			], data))
		EventBus.EventType.SUB_PHASE_CHANGED:
			out.append(_phase("子阶段: %s -> %s" % [
				str(data.get("old_sub_phase", "")),
				str(data.get("new_sub_phase", "")),
			], data))
		EventBus.EventType.ROUND_STARTED:
			out.append(_phase("回合开始: %d" % int(data.get("round", -1)), data))
		EventBus.EventType.ROUND_ENDED:
			var round := int(data.get("round", -1))
			var next_round := int(data.get("next_round", -1))
			var text := "回合结束: %d" % round
			if next_round > 0 and next_round != round:
				text += " -> %d" % next_round
			out.append(_phase(text, data))
		EventBus.EventType.TURN_ORDER_FINALIZED:
			var round := int(data.get("round", -1))
			var order_val = data.get("turn_order", null)
			var order: Array = order_val if (order_val is Array) else []
			var parts: Array[String] = []
			for pid_val in order:
				var pid := int(pid_val)
				parts.append("玩家%d" % (pid + 1))
			var text := "行动顺序"
			if round >= 0:
				text += "（回合 %d）" % round
			if not parts.is_empty():
				text += "：" + " -> ".join(parts)
			out.append(_event(text, data))
		EventBus.EventType.PLAYER_TURN_STARTED:
			out.append(_phase("玩家 %d 开始回合" % (int(data.get("player_id", -1)) + 1), data))
		EventBus.EventType.PLAYER_TURN_ENDED:
			out.append(_phase("玩家 %d 结束回合 (%s)" % [
				int(data.get("player_id", -1)) + 1,
				str(data.get("action", "")),
			], data))
		EventBus.EventType.PLAYER_CASH_CHANGED:
			var breakdown_suffix := _format_cash_income_breakdown_suffix(data)
			var base_text := "玩家 %d 现金变化: %d -> %d (%+d)" % [
				int(data.get("player_id", -1)) + 1,
				int(data.get("old_cash", 0)),
				int(data.get("new_cash", 0)),
				int(data.get("delta", 0)),
			]
			out.append(_event(base_text + breakdown_suffix, data))
		EventBus.EventType.PLAYER_BROKE:
			var player_id := int(data.get("player_id", -1))
			var reason := str(data.get("reason", "")).strip_edges()
			var cash := int(data.get("cash", 0))
			var text := "玩家 %d 破产（现金: %d）" % [player_id + 1, cash]
			if not reason.is_empty():
				text += "：" + reason
			out.append(_event(text, data))
		EventBus.EventType.COMMAND_EXECUTED:
			# CommandRunner 会为每条命令广播 COMMAND_EXECUTED；这里仅记录定价类强制动作（用于“自动完成”可见性）。
			if not data.has("price_modifier"):
				return out
			var action_id := str(data.get("action_id", "")).strip_edges()
			if not PRICE_ACTION_LOG_TEXT.has(action_id):
				return out
			var player_id := int(data.get("player_id", -1))
			if player_id < 0:
				return out
			out.append(_player(player_id, str(PRICE_ACTION_LOG_TEXT[action_id]), data))
		EventBus.EventType.EMPLOYEE_ACTIVATED:
			var player_id := int(data.get("player_id", -1))
			var employee_id := str(data.get("employee_id", "")).strip_edges()
			var location := _format_employee_location(str(data.get("location", "")).strip_edges())
			var employee_name := _employee_name(employee_id)
			var text := "员工启用：%s" % (employee_name if not employee_name.is_empty() else employee_id)
			if not location.is_empty():
				text += "（%s）" % location
			out.append(_player(player_id, text, data))
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
			out.append(_player(player_id, text, data))
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
			var parts: Array[String] = []
			var steps := maxi(1, int(data.get("steps", 1)))
			parts.append("%d步" % steps)
			var trainer_id := str(data.get("trainer_id", "")).strip_edges()
			if not trainer_id.is_empty():
				var trainer_name := _employee_name(trainer_id)
				parts.append("培训员：%s" % (trainer_name if not trainer_name.is_empty() else trainer_id))
			if bool(data.get("from_pending", false)):
				parts.append("预支清账")
			if not parts.is_empty():
				text += "（%s）" % "，".join(parts)
			out.append(_player(player_id, text, data))
		EventBus.EventType.EMPLOYEE_FIRED:
			var player_id := int(data.get("player_id", -1))
			var employee_id := str(data.get("employee_id", "")).strip_edges()
			var employee_name := _employee_name(employee_id)
			var location := _format_employee_location(str(data.get("location", "")).strip_edges())
			var text := "解雇 %s" % (employee_name if not employee_name.is_empty() else employee_id)
			if not location.is_empty():
				text += "（%s）" % location
			out.append(_player(player_id, text, data))
		EventBus.EventType.RESTAURANT_PLACED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var rest_text := _format_restaurant_id_short(str(data.get("restaurant_id", "")).strip_edges())
			var pos_text := _format_position(data.get("position", null))
			var text := "放置餐厅"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			var parts2: Array[String] = []
			if not rest_text.is_empty():
				parts2.append(rest_text)
			if not pos_text.is_empty():
				parts2.append(pos_text)
			if not parts2.is_empty():
				text += "：" + " ".join(parts2)
			out.append(_player(player_id, text, data))
		EventBus.EventType.RESTAURANT_MOVED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var rest_text2 := _format_restaurant_id_short(str(data.get("restaurant_id", "")).strip_edges())
			var pos_text := _format_position(data.get("position", null))
			var rotation := int(data.get("rotation", 0))
			var text := "移动餐厅"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			var parts3: Array[String] = []
			if not rest_text2.is_empty():
				parts3.append(rest_text2)
			if not pos_text.is_empty():
				parts3.append(pos_text)
			if rotation != 0:
				parts3.append("旋转%d°" % rotation)
			if not parts3.is_empty():
				text += "：" + " ".join(parts3)
			out.append(_player(player_id, text, data))
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
			out.append(_player(player_id, text, data))
		EventBus.EventType.GARDEN_ADDED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var house_number := int(data.get("house_number", -1))
			var house_id := str(data.get("house_id", "")).strip_edges()
			var direction := _format_direction(str(data.get("direction", "")).strip_edges())
			var pos_text := _format_position(data.get("position", null))
			var details2: Array[String] = []
			if house_number > 0:
				details2.append("房屋#%d" % house_number)
			elif not house_id.is_empty():
				details2.append("房屋%s" % house_id)
			if not direction.is_empty():
				details2.append(direction)
			if not pos_text.is_empty():
				details2.append(pos_text)
			var text := "添加花园"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not details2.is_empty():
				text += "：" + " ".join(details2)
			out.append(_player(player_id, text, data))
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
			out.append(_player(player_id, text, data))
		EventBus.EventType.FOOD_SOLD:
			var player_id := int(data.get("player_id", -1))
			var house_number := str(data.get("house_number", "")).strip_edges()
			var rest_text := _format_restaurant_id_short(str(data.get("restaurant_id", "")).strip_edges())
			var required_val = data.get("required", null)
			var required: Dictionary = required_val if (required_val is Dictionary) else {}
			var items := _format_required_short(required, 4)
			var revenue := int(data.get("revenue", 0))
			var bonus := int(data.get("bonus", 0))
			var house_bonus := int(data.get("house_bonus", 0))
			var hb_breakdown_val = data.get("house_bonus_breakdown", null)
			var hb_breakdown: Dictionary = hb_breakdown_val if (hb_breakdown_val is Dictionary) else {}
			var hb_parts := _format_house_bonus_breakdown_parts(hb_breakdown)
			var msg := "售出"
			if not house_number.is_empty():
				msg += "：房屋#%s" % house_number
			if not items.is_empty():
				msg += " 消费 %s" % items
			if not rest_text.is_empty():
				msg += " -> %s" % rest_text
			msg += " 收入 $%d" % revenue
			if bonus != 0 or house_bonus != 0:
				var parts: Array[String] = []
				parts.append("奖励 $%d" % bonus)
				var house_part := "房屋奖 $%d" % house_bonus
				if house_bonus != 0 and not hb_parts.is_empty():
					house_part += "：" + "，".join(hb_parts)
				parts.append(house_part)
				msg += " (" + ", ".join(parts) + ")"
			out.append(_player(player_id, msg, data))
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
			out.append(_player(player_id, text, data))
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
			out.append(_player(player_id, text, data))
		EventBus.EventType.MARKETING_PLACED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name := _employee_name(employee_type)
			var board_number := int(data.get("board_number", 0))
			var marketing_type := str(data.get("marketing_type", "")).strip_edges()
			if marketing_type.is_empty() and board_number > 0 and MarketingRegistryClass.is_loaded():
				var def_val = MarketingRegistryClass.get_def(board_number)
				if def_val != null and def_val is MarketingDef:
					marketing_type = str((def_val as MarketingDef).type).strip_edges()
			var mtype := _format_marketing_type_short(marketing_type)
			var product_id := str(data.get("product", "")).strip_edges()
			var product_name := _product_name(product_id)
			var remaining_duration := int(data.get("remaining_duration", int(data.get("duration", 0))))
			var duration_text := ""
			if remaining_duration == -1:
				duration_text = "永久"
			elif remaining_duration > 0:
				duration_text = "持续%d回合" % remaining_duration
			var axis := _format_marketing_axis(str(data.get("axis", "")).strip_edges())
			var pos_text := _format_position(data.get("position", null))
			var parts: Array[String] = []
			if not mtype.is_empty():
				parts.append(mtype)
			if not product_name.is_empty():
				parts.append(product_name)
			if not duration_text.is_empty():
				parts.append(duration_text)
			if not axis.is_empty():
				parts.append(axis)
			if not pos_text.is_empty():
				parts.append(pos_text)
			var text := "放置营销"
			if not employee_name.is_empty():
				text += "（%s）" % employee_name
			if not parts.is_empty():
				text += "：" + " ".join(parts)
			out.append(_player(player_id, text, data))
		EventBus.EventType.MARKETING_EXPIRED:
			var player_id := int(data.get("player_id", -1))
			var mtype2 := _format_marketing_type_short(str(data.get("marketing_type", "")).strip_edges())
			var axis2 := _format_marketing_axis(str(data.get("axis", "")).strip_edges())
			var product_id2 := str(data.get("product", "")).strip_edges()
			var product_name2 := _product_name(product_id2)
			var pos_text2 := _format_position(data.get("position", null))
			var before_duration := int(data.get("duration_before", 0))
			var after_duration := int(data.get("duration_after", 0))
			var parts2: Array[String] = []
			if not mtype2.is_empty():
				parts2.append(mtype2)
			if not product_name2.is_empty():
				parts2.append(product_name2)
			if not axis2.is_empty():
				parts2.append(axis2)
			if before_duration > 0 or after_duration > 0:
				parts2.append("剩余%d→%d" % [before_duration, after_duration])
			if not pos_text2.is_empty():
				parts2.append(pos_text2)
			var text := "营销到期"
			if not parts2.is_empty():
				text += "：" + " ".join(parts2)
			out.append(_player(player_id, text, data))
		EventBus.EventType.DEMAND_GENERATED:
			var player_id := int(data.get("player_id", -1))
			var mtype3 := _format_marketing_type_short(str(data.get("marketing_type", "")).strip_edges())
			var product_id3 := str(data.get("product", "")).strip_edges()
			var product_name3 := _product_name(product_id3)
			var demands_added := int(data.get("demands_added", 0))
			var hn_val = data.get("affected_house_numbers", null)
			if hn_val == null:
				hn_val = data.get("houses", null)
			var house_numbers_text2 := _format_house_numbers_short(hn_val, 6)
			var text := "生成需求"
			var parts3: Array[String] = []
			if not mtype3.is_empty():
				parts3.append(mtype3)
			if not product_name3.is_empty():
				parts3.append(product_name3)
			if demands_added > 0:
				parts3.append("新增需求x%d" % demands_added)
			if not house_numbers_text2.is_empty():
				parts3.append(house_numbers_text2)
			if not parts3.is_empty():
				text += "：" + " ".join(parts3)
			out.append(_player(player_id, text, data))
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
			out.append(_event(text, data))
		EventBus.EventType.GAME_STARTED:
			out.append(_system("游戏开始", data))
		EventBus.EventType.GAME_ENDED:
			var reason := str(data.get("reason", "")).strip_edges()
			var text := "游戏结束"
			if not reason.is_empty():
				text += "：" + reason
			out.append(_system(text, data))
		EventBus.EventType.PAYDAY_REPORT:
			out.append_array(_format_payday_report(data))
		EventBus.EventType.DINNERTIME_REPORT:
			out.append_array(_format_dinnertime_report(data))
		_:
			out.append(_debug("%s: %s" % [t, str(data)], data))

	return out

func _system(message: String, details: Dictionary) -> Dictionary:
	return {"type": GameLogPanel.LogType.SYSTEM, "message": message, "details": details}

func _phase(message: String, details: Dictionary) -> Dictionary:
	return {"type": GameLogPanel.LogType.PHASE, "message": message, "details": details}

func _player(player_id: int, message: String, details: Dictionary) -> Dictionary:
	var full_message := "玩家%d: %s" % [player_id + 1, message]
	return {"type": GameLogPanel.LogType.PLAYER, "message": full_message, "details": details}

func _event(message: String, details: Dictionary) -> Dictionary:
	return {"type": GameLogPanel.LogType.GAME_EVENT, "message": message, "details": details}

func _debug(message: String, details: Dictionary) -> Dictionary:
	return {"type": GameLogPanel.LogType.DEBUG, "message": message, "details": details}

func _ensure_reports_formatter() -> void:
	if _reports_formatter == null or not is_instance_valid(_reports_formatter):
		_reports_formatter = ReportsFormatterClass.new()
		_reports_formatter.setup(self)

func _format_payday_report(data: Dictionary) -> Array[Dictionary]:
	_ensure_reports_formatter()
	return _reports_formatter.format_payday_report(data)

func _format_dinnertime_report(data: Dictionary) -> Array[Dictionary]:
	_ensure_reports_formatter()
	return _reports_formatter.format_dinnertime_report(data)

func _format_cash_income_breakdown_suffix(details: Dictionary) -> String:
	if details == null or not (details is Dictionary):
		return ""
	var breakdown_val = details.get("income_breakdown", null)
	if not (breakdown_val is Dictionary):
		return ""
	var breakdown: Dictionary = breakdown_val
	if str(breakdown.get("context", "")).strip_edges() != "dinnertime_income":
		return ""
	var items_val = breakdown.get("items", null)
	if not (items_val is Array):
		return ""
	var items: Array = items_val
	if items.is_empty():
		return ""

	var parts: Array[String] = []
	for it_val in items:
		if not (it_val is Dictionary):
			continue
		var it: Dictionary = it_val
		var id := str(it.get("id", "")).strip_edges()
		var amt := int(it.get("amount", 0))
		if id.is_empty() or amt == 0:
			continue
		var label := str(CASH_INCOME_BREAKDOWN_LABELS.get(id, id)).strip_edges()
		if label.is_empty():
			label = id
		parts.append("%s $%d" % [label, amt])

	if parts.is_empty():
		return ""
	return "（晚餐收入来源：" + "，".join(parts) + "）"

func _format_house_bonus_breakdown_parts(breakdown: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if breakdown == null or not (breakdown is Dictionary) or breakdown.is_empty():
		return out

	var used: Dictionary = {}
	for key in ["park", "fry_chef"]:
		if not breakdown.has(key):
			continue
		var amt := int(breakdown.get(key, 0))
		if amt == 0:
			continue
		used[key] = true
		var label := str(HOUSE_BONUS_BREAKDOWN_LABELS.get(key, key)).strip_edges()
		if label.is_empty():
			label = key
		out.append("%s $%d" % [label, amt])

	var remaining: Array[String] = []
	for k_val in breakdown.keys():
		var k := str(k_val).strip_edges()
		if k.is_empty() or used.has(k):
			continue
		remaining.append(k)
	remaining.sort()
	for k in remaining:
		var amt2 := int(breakdown.get(k, 0))
		if amt2 == 0:
			continue
		var label2 := str(HOUSE_BONUS_BREAKDOWN_LABELS.get(k, k)).strip_edges()
		if label2.is_empty():
			label2 = k
		out.append("%s $%d" % [label2, amt2])

	return out

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
