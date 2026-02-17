# GameEventLogFormatter：事件类型分派（拆分自 game_event_log_formatter.gd）
extends RefCounted

const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

const PRICE_ACTION_LOG_TEXT: Dictionary = {
	"set_price": "设定价格（-$1）",
	"set_discount": "设定折扣（-$3）",
	"set_luxury_price": "设定奢侈品价格（+$10）",
}

var _formatter = null

func setup(formatter) -> void:
	_formatter = formatter

func format_event(t: String, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _formatter == null or not is_instance_valid(_formatter):
		return out

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
			var total_income := revenue + house_bonus
			msg += " 收入 $%d" % total_income

			var breakdown_parts: Array[String] = []
			var unit_price := int(data.get("unit_price", 0))
			var quantity := int(data.get("quantity", 0))
			if quantity < 0:
				quantity = 0
			var has_garden := bool(data.get("has_garden", false))

			var can_decompose_sale_revenue := unit_price != 0 and quantity > 0
			if can_decompose_sale_revenue:
				var food_price := unit_price * quantity
				var garden_bonus := food_price if has_garden else 0
				var floor_adjustment := revenue - (food_price + garden_bonus + bonus)
				if food_price != 0:
					breakdown_parts.append("食物售价 $%d" % food_price)
				if garden_bonus != 0:
					breakdown_parts.append("花园加成 $%d" % garden_bonus)
				if bonus != 0:
					breakdown_parts.append("营销加成 $%d" % bonus)
				if floor_adjustment != 0:
					breakdown_parts.append("下限调整 $%d" % floor_adjustment)
			else:
				var sale_part := "售卖收入 $%d" % revenue
				if bonus != 0:
					sale_part += "（含营销加成 $%d）" % bonus
				breakdown_parts.append(sale_part)

			if house_bonus != 0 or not hb_parts.is_empty():
				if not hb_parts.is_empty():
					var hb_known := 0
					for k_val in hb_breakdown.keys():
						hb_known += int(hb_breakdown.get(k_val, 0))
					var hb_other := house_bonus - hb_known
					if hb_other < 0:
						hb_other = 0
					var all_parts: Array[String] = hb_parts.duplicate()
					if hb_other != 0:
						all_parts.append("其它房屋加成 $%d" % hb_other)
					breakdown_parts.append("房屋奖：" + "，".join(all_parts))
				else:
					breakdown_parts.append("房屋奖 $%d" % house_bonus)

			if not breakdown_parts.is_empty():
				msg += "（" + "，".join(breakdown_parts) + "）"

			var route_text := _format_route_purchases_short(data.get("route_purchases", null), 4)
			if not route_text.is_empty():
				msg += "；" + route_text
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
			var milestone_id := str(data.get("milestone_id", "")).strip_edges()
			var player_id := int(data.get("player_id", -1))
			var name := _milestone_name(milestone_id)
			var who := "玩家%d" % (player_id + 1) if player_id >= 0 else "未知玩家"
			var text := "%s 获得里程碑：%s" % [who, name if not name.is_empty() else milestone_id]
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
	return _formatter._system(message, details)

func _phase(message: String, details: Dictionary) -> Dictionary:
	return _formatter._phase(message, details)

func _player(player_id: int, message: String, details: Dictionary) -> Dictionary:
	return _formatter._player(player_id, message, details)

func _event(message: String, details: Dictionary) -> Dictionary:
	return _formatter._event(message, details)

func _debug(message: String, details: Dictionary) -> Dictionary:
	return _formatter._debug(message, details)

func _milestone_name(milestone_id: String) -> String:
	return _formatter._milestone_name(milestone_id)

func _employee_name(employee_id: String) -> String:
	return _formatter._employee_name(employee_id)

func _product_name(product_id: String) -> String:
	return _formatter._product_name(product_id)

func _format_employee_location(location: String) -> String:
	return _formatter._format_employee_location(location)

func _format_restaurant_id_short(restaurant_id: String) -> String:
	return _formatter._format_restaurant_id_short(restaurant_id)

func _format_position(pos) -> String:
	return _formatter._format_position(pos)

func _format_direction(direction: String) -> String:
	return _formatter._format_direction(direction)

func _format_required_short(required: Dictionary, limit: int) -> String:
	return _formatter._format_required_short(required, limit)

func _format_house_bonus_breakdown_parts(breakdown: Dictionary) -> Array[String]:
	return _formatter._format_house_bonus_breakdown_parts(breakdown)

func _format_route_purchases_short(route_purchases, limit: int) -> String:
	return _formatter._format_route_purchases_short(route_purchases, limit)

func _format_drinks_procured(drinks_procured: Dictionary) -> String:
	return _formatter._format_drinks_procured(drinks_procured)

func _format_picked_drink_sources_short(picked_sources, limit: int) -> String:
	return _formatter._format_picked_drink_sources_short(picked_sources, limit)

func _format_marketing_type_short(marketing_type: String) -> String:
	return _formatter._format_marketing_type_short(marketing_type)

func _format_marketing_axis(axis: String) -> String:
	return _formatter._format_marketing_axis(axis)

func _format_house_numbers_short(house_numbers, limit: int) -> String:
	return _formatter._format_house_numbers_short(house_numbers, limit)

func _format_payday_report(data: Dictionary) -> Array[Dictionary]:
	return _formatter._format_payday_report(data)

func _format_dinnertime_report(data: Dictionary) -> Array[Dictionary]:
	return _formatter._format_dinnertime_report(data)

func _format_cash_income_breakdown_suffix(details: Dictionary) -> String:
	return _formatter._format_cash_income_breakdown_suffix(details)
