# Game scene：事件日志格式化器
# 负责：把 EventBus 的事件字典转换为 GameLogPanel 的日志条目（纯格式化，不直接操作节点）。
class_name GameEventLogFormatter
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const REPORTS_FORMATTER_SCRIPT_PATH := "res://ui/scenes/game/event_log/reports_formatter.gd"
const CASES_FORMATTER_SCRIPT_PATH := "res://ui/scenes/game/event_log/formatter_cases.gd"

const CASH_INCOME_BREAKDOWN_LABELS: Dictionary = {
	"food_price": "食物售价",
	"garden_bonus": "花园加成",
	"marketing_bonus": "营销加成",
	"route_purchase_income": "沿路购买收入",
	"house_bonus_other": "其它房屋加成",
	"tips": "服务员收入",
	"cfo_bonus": "CFO 加成",
	"revenue_floor_adjustment": "下限调整",
	"other": "其它",
}

var _reports_formatter = null
var _cases_formatter = null

func format(event: Dictionary) -> Array[Dictionary]:
	if not (event is Dictionary) or event.is_empty():
		return []

	var t: String = str(event.get("type", ""))
	var data_val = event.get("data", null)
	var data: Dictionary = data_val if (data_val is Dictionary) else {}

	_ensure_cases_formatter()
	if _cases_formatter != null and is_instance_valid(_cases_formatter):
		return _cases_formatter.format_event(t, data)
	return [_debug("%s: %s" % [t, str(data)], data)]

func _ensure_cases_formatter() -> void:
	if _cases_formatter != null and is_instance_valid(_cases_formatter):
		return
	var cases_formatter_script = ResourceLoader.load(
		CASES_FORMATTER_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if cases_formatter_script == null:
		return
	_cases_formatter = cases_formatter_script.new()
	if _cases_formatter != null and is_instance_valid(_cases_formatter):
		_cases_formatter.setup(self)

func _milestone_name(milestone_id: String) -> String:
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return ""

	var name := mid
	if MilestoneRegistryClass.is_loaded():
		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val != null and def_val is MilestoneDef:
			var n := str((def_val as MilestoneDef).name).strip_edges()
			if not n.is_empty():
				name = n

	var suffixes: Array[String] = [
		" (" + mid + ")",
		"(" + mid + ")",
		" （" + mid + "）",
		"（" + mid + "）",
	]
	for suffix in suffixes:
		if name.ends_with(suffix):
			return name.substr(0, name.length() - suffix.length()).strip_edges()

	return name

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
		var reports_formatter_script = ResourceLoader.load(
			REPORTS_FORMATTER_SCRIPT_PATH,
			"Script",
			ResourceLoader.CACHE_MODE_IGNORE
		)
		if reports_formatter_script == null:
			return
		_reports_formatter = reports_formatter_script.new()
		if _reports_formatter != null and is_instance_valid(_reports_formatter):
			_reports_formatter.setup(self)

func _format_payday_report(data: Dictionary) -> Array[Dictionary]:
	_ensure_reports_formatter()
	if _reports_formatter == null or not is_instance_valid(_reports_formatter):
		return []
	return _reports_formatter.format_payday_report(data)

func _format_dinnertime_report(data: Dictionary) -> Array[Dictionary]:
	_ensure_reports_formatter()
	if _reports_formatter == null or not is_instance_valid(_reports_formatter):
		return []
	return _reports_formatter.format_dinnertime_report(data)

func dispose() -> void:
	_reports_formatter = null
	_cases_formatter = null

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
		var label := ""
		if id.begins_with("house_bonus:"):
			label = _format_house_bonus_key_label(id.substr("house_bonus:".length()))
		else:
			label = str(CASH_INCOME_BREAKDOWN_LABELS.get(id, id)).strip_edges()
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

	var keys: Array[String] = []
	for k_val in breakdown.keys():
		var k := str(k_val).strip_edges()
		if k.is_empty():
			continue
		keys.append(k)
	keys.sort()
	for k in keys:
		var amt := int(breakdown.get(k, 0))
		if amt == 0:
			continue
		var label := _format_house_bonus_key_label(k)
		if label.is_empty():
			label = k
		out.append("%s $%d" % [label, amt])

	return out

func _format_house_bonus_key_label(key: String) -> String:
	var k := str(key).strip_edges()
	if k.is_empty():
		return ""

	if EmployeeRegistryClass.is_loaded():
		var emp_val = EmployeeRegistryClass.get_def(k)
		if emp_val != null and emp_val is EmployeeDef:
			var emp: EmployeeDef = emp_val
			var name := str(emp.name).strip_edges()
			if not name.is_empty():
				return "%s加成" % name

	if PieceRegistryClass.is_loaded() and PieceRegistryClass.has(k):
		var piece_val = PieceRegistryClass.get_def(k)
		if piece_val != null and piece_val is PieceDef:
			var piece: PieceDef = piece_val
			var display_name := str(piece.display_name).strip_edges()
			if not display_name.is_empty():
				return "%s加成" % display_name

	return "%s加成" % k

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

func _format_route_purchase_source_short(source_kind: String, source_id: String) -> String:
	var k := str(source_kind).strip_edges()
	var id := str(source_id).strip_edges()
	if k == "restaurant":
		return _format_restaurant_id_short(id)
	if not id.is_empty():
		return id
	return k

func _format_route_purchases_short(route_purchases_val, max_items: int = 4) -> String:
	if route_purchases_val == null or not (route_purchases_val is Array):
		return ""
	var purchases: Array = route_purchases_val
	if purchases.is_empty():
		return ""

	var parts: Array[String] = []
	for v in purchases:
		if not (v is Dictionary):
			continue
		var p: Dictionary = v
		var kind := str(p.get("kind", "")).strip_edges()

		var seller := int(p.get("seller", -1))
		var seller_text := ("玩家%d" % (seller + 1)) if seller >= 0 else "玩家?"

		var kind_text := _product_name(kind)
		if kind_text.is_empty():
			kind_text = kind

		var src_text := _format_route_purchase_source_short(
			str(p.get("source_kind", "")),
			str(p.get("source_id", ""))
		)
		var price := int(p.get("price", 0))

		var seg := seller_text
		if not kind_text.is_empty():
			seg += " " + kind_text
		if not src_text.is_empty():
			seg += " " + src_text
		if price != 0:
			seg += " $%d" % price
		parts.append(seg)

	if parts.is_empty():
		return ""

	var shown: Array[String] = []
	for i in range(min(parts.size(), maxi(1, int(max_items)))):
		shown.append(parts[i])
	var suffix := ""
	if parts.size() > shown.size():
		suffix = " 等%d次" % parts.size()
	return "沿路购买×%d：" % parts.size() + "，".join(shown) + suffix

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
