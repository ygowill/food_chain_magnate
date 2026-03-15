# GameEventLogFormatter：营销/采购饮料相关事件格式化（拆分自 game_event_log_formatter_cases.gd）
extends RefCounted

const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

var _formatter = null

func setup(formatter) -> void:
	_formatter = formatter

func format_event(t: String, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _formatter == null or not is_instance_valid(_formatter):
		return out

	match t:
		EventBus.EventType.DRINKS_PROCURED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name: String = str(_formatter._employee_name(employee_type))
			var drinks_text: String = str(_formatter._format_drinks_procured(data.get("drinks_procured", {})))
			var rest_text: String = str(_formatter._format_restaurant_id_short(str(data.get("restaurant_id", "")).strip_edges()))
			var sources_text: String = str(_formatter._format_picked_drink_sources_short(data.get("picked_sources", null), 3))
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
			out.append(_formatter._player(player_id, text, data))
		EventBus.EventType.MARKETING_PLACED:
			var player_id := int(data.get("player_id", -1))
			var employee_type := str(data.get("employee_type", "")).strip_edges()
			var employee_name: String = str(_formatter._employee_name(employee_type))
			var board_number := int(data.get("board_number", 0))
			var marketing_type := str(data.get("marketing_type", "")).strip_edges()
			if marketing_type.is_empty() and board_number > 0 and MarketingRegistryClass.is_loaded():
				var def_val = MarketingRegistryClass.get_def(board_number)
				if def_val != null and def_val is MarketingDef:
					marketing_type = str((def_val as MarketingDef).type).strip_edges()
			var mtype: String = str(_formatter._format_marketing_type_short(marketing_type))
			var product_id := str(data.get("product", "")).strip_edges()
			var product_name: String = str(_formatter._product_name(product_id))
			var remaining_duration := int(data.get("remaining_duration", int(data.get("duration", 0))))
			var duration_text := ""
			if remaining_duration == -1:
				duration_text = "永久"
			elif remaining_duration > 0:
				duration_text = "持续%d回合" % remaining_duration
			var axis: String = str(_formatter._format_marketing_axis(str(data.get("axis", "")).strip_edges()))
			var pos_text: String = str(_formatter._format_position(data.get("position", null)))
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
			out.append(_formatter._player(player_id, text, data))
		EventBus.EventType.MARKETING_EXPIRED:
			var player_id := int(data.get("player_id", -1))
			var mtype2: String = str(_formatter._format_marketing_type_short(str(data.get("marketing_type", "")).strip_edges()))
			var axis2: String = str(_formatter._format_marketing_axis(str(data.get("axis", "")).strip_edges()))
			var product_id2 := str(data.get("product", "")).strip_edges()
			var product_name2: String = str(_formatter._product_name(product_id2))
			var pos_text2: String = str(_formatter._format_position(data.get("position", null)))
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
				parts2.append("剩余%d->%d" % [before_duration, after_duration])
			if not pos_text2.is_empty():
				parts2.append(pos_text2)
			var text := "营销到期"
			if not parts2.is_empty():
				text += "：" + " ".join(parts2)
			out.append(_formatter._player(player_id, text, data))
		EventBus.EventType.DEMAND_GENERATED:
			var player_id := int(data.get("player_id", -1))
			var mtype3: String = str(_formatter._format_marketing_type_short(str(data.get("marketing_type", "")).strip_edges()))
			var product_id3 := str(data.get("product", "")).strip_edges()
			var product_name3: String = str(_formatter._product_name(product_id3))
			var demands_added := int(data.get("demands_added", 0))
			var hn_val = data.get("affected_house_numbers", null)
			if hn_val == null:
				hn_val = data.get("houses", null)
			var house_numbers_text2: String = str(_formatter._format_house_numbers_short(hn_val, 6))
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
			out.append(_formatter._player(player_id, text, data))
		_:
			pass

	return out
