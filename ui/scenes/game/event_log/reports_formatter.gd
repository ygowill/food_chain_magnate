# GameEventLogFormatter：报表类事件拆分（Payday/Dinnertime）
extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

var _formatter = null

func setup(formatter) -> void:
	_formatter = formatter

func format_payday_report(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var round := int(data.get("round", -1))
	var report_val = data.get("report", null)
	if not (report_val is Dictionary):
		out.append(_formatter._event("发薪日结算报告缺失（回合 %d）" % round, data))
		return out
	var report: Dictionary = report_val

	var details_val = report.get("details", null)
	if not (details_val is Array):
		out.append(_formatter._event("发薪日结算报告缺失明细（回合 %d）" % round, report))
		return out
	var details: Array = details_val

	for item_val in details:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var player_id := int(item.get("player_id", -1))
		if player_id < 0:
			continue

		var due := int(item.get("due", 0))
		var unpaid := int(item.get("unpaid", 0))
		var salary_cost := int(item.get("salary_cost", item.get("base_salary_cost", 0)))
		var employee_count := _count_payday_base_salary_employees(item)
		var employee_text := _format_payday_salary_employees(item)
		var base_total := _compute_payday_base_salary_total(item, salary_cost)
		var reduction_text := _format_payday_reduction_summary(item, salary_cost)
		var final_paid := maxi(0, due - unpaid)

		var lines: Array[String] = [
			"发薪日",
			"薪资人员：%s" % (employee_text if not employee_text.is_empty() else "无"),
			"薪资基数：$%d/人，共%d人，合计$%d" % [salary_cost, employee_count, base_total],
			"减免：%s" % (reduction_text if not reduction_text.is_empty() else "无"),
		]

		var final_line := "最终支付：$%d" % final_paid
		if unpaid > 0:
			final_line += "（仍欠$%d）" % unpaid
		lines.append(final_line)

		var text := "\n".join(lines)

		var d := item.duplicate(true)
		d["round"] = round
		out.append(_formatter._player(player_id, text, d))

	return out

func _count_payday_base_salary_employees(item: Dictionary) -> int:
	var employees_val = item.get("employees", null)
	if not (employees_val is Array):
		return int(item.get("paid_employee_count", 0))
	var employees: Array = employees_val

	var count := 0
	for emp_val in employees:
		if not (emp_val is Dictionary):
			continue
		var emp: Dictionary = emp_val
		if bool(emp.get("base_requires_salary", false)):
			count += 1
	return count

func _compute_payday_base_salary_total(item: Dictionary, fallback_salary_cost: int) -> int:
	return _count_payday_base_salary_employees(item) * maxi(0, fallback_salary_cost)

func _format_payday_salary_employees(item: Dictionary) -> String:
	var employees_val = item.get("employees", null)
	if not (employees_val is Array):
		return ""
	var employees: Array = employees_val

	var name_counts := {}
	var ordered_names: Array[String] = []
	for emp_val in employees:
		if not (emp_val is Dictionary):
			continue
		var emp: Dictionary = emp_val
		if not bool(emp.get("base_requires_salary", false)):
			continue
		var employee_id := str(emp.get("employee_id", "")).strip_edges()
		var name := str(emp.get("name", "")).strip_edges()
		if name.is_empty():
			name = str(_formatter._employee_name(employee_id)).strip_edges()
		if name.is_empty():
			name = employee_id
		if name.is_empty():
			continue
		if not name_counts.has(name):
			name_counts[name] = 0
			ordered_names.append(name)
		name_counts[name] = int(name_counts.get(name, 0)) + 1

	var parts: Array[String] = []
	for name in ordered_names:
		var count := int(name_counts.get(name, 0))
		if count <= 0:
			continue
		if count == 1:
			parts.append(name)
		else:
			parts.append("%s×%d" % [name, count])
	return "、".join(parts)

func _format_payday_reduction_summary(item: Dictionary, fallback_salary_cost: int) -> String:
	var parts: Array[String] = []
	parts.append_array(_format_payday_waived_employee_reduction_parts(item, fallback_salary_cost))

	var discount := int(item.get("salary_discount", 0))
	if discount > 0:
		var discount_detail := _format_payday_discount_detail(item)
		if discount_detail.is_empty():
			parts.append("招聘折扣 -$%d" % discount)
		else:
			parts.append("招聘折扣 -$%d（%s）" % [discount, discount_detail])

	var delta := int(item.get("milestone_delta", 0))
	if delta != 0:
		var delta_label := _format_signed_money(delta)
		var ms_detail := _format_payday_milestone_delta_detail(item)
		if ms_detail.is_empty():
			parts.append("里程碑调整 %s" % delta_label)
		else:
			parts.append("里程碑调整 %s（%s）" % [delta_label, ms_detail])

	return "；".join(parts)

func _format_signed_money(amount: int) -> String:
	if amount < 0:
		return "-$%d" % abs(amount)
	return "+$%d" % amount

func _format_payday_waived_employee_reduction_parts(item: Dictionary, fallback_salary_cost: int) -> Array[String]:
	var out: Array[String] = []
	var employees_val = item.get("employees", null)
	if not (employees_val is Array):
		return out
	var employees: Array = employees_val

	for emp_val in employees:
		if not (emp_val is Dictionary):
			continue
		var emp: Dictionary = emp_val
		if not bool(emp.get("base_requires_salary", false)):
			continue
		if bool(emp.get("requires_salary", false)):
			continue

		var employee_id := str(emp.get("employee_id", "")).strip_edges()
		var name := str(emp.get("name", "")).strip_edges()
		if name.is_empty():
			name = str(_formatter._employee_name(employee_id)).strip_edges()
		if name.is_empty():
			name = employee_id
		if name.is_empty():
			continue

		var reason := _format_payday_waived_reasons(emp)
		if reason.is_empty():
			out.append("%s免薪 -$%d" % [name, fallback_salary_cost])
		else:
			out.append("%s免薪 -$%d（%s）" % [name, fallback_salary_cost, reason])

	return out

func _format_payday_waived_reasons(emp: Dictionary) -> String:
	var reasons_val = emp.get("salary_waived_reasons", null)
	if not (reasons_val is Array):
		return ""
	var labels: Array[String] = []
	var seen := {}
	for reason_val in reasons_val:
		if not (reason_val is Dictionary):
			continue
		var reason: Dictionary = reason_val
		var label := str(reason.get("label", "")).strip_edges()
		var mid := str(reason.get("milestone_id", "")).strip_edges()
		var mname := str(reason.get("milestone_name", "")).strip_edges()
		if not mname.is_empty():
			label = "%s：%s" % [label, mname] if not label.is_empty() else mname
		elif not mid.is_empty():
			label = "%s：%s" % [label, mid] if not label.is_empty() else mid
		if label.is_empty():
			continue
		if seen.has(label):
			continue
		seen[label] = true
		labels.append(label)
	return "，".join(labels)

func _format_payday_discount_detail(item: Dictionary) -> String:
	var sources_val = item.get("salary_discount_sources", null)
	if not (sources_val is Array):
		return ""
	var parts: Array[String] = []
	for source_val in sources_val:
		if not (source_val is Dictionary):
			continue
		var source: Dictionary = source_val
		var unused := int(source.get("unused_actions", 0))
		if unused <= 0:
			continue
		var employee_id := str(source.get("employee_id", "")).strip_edges()
		var name := str(source.get("name", "")).strip_edges()
		if name.is_empty():
			name = str(_formatter._employee_name(employee_id)).strip_edges()
		if name.is_empty():
			name = employee_id
		if name.is_empty():
			continue
		parts.append("%s 未用招聘x%d" % [name, unused])
	return "，".join(parts)

func _format_payday_milestone_delta_detail(item: Dictionary) -> String:
	var entries_val = item.get("milestone_salary_adjustments", null)
	if not (entries_val is Array):
		return ""
	var parts: Array[String] = []
	var seen := {}
	for entry_val in entries_val:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var amount := int(entry.get("amount", 0))
		if amount == 0:
			continue
		var name := str(entry.get("milestone_name", "")).strip_edges()
		if name.is_empty():
			name = str(entry.get("milestone_id", "")).strip_edges()
		if name.is_empty():
			name = "里程碑"
		if seen.has(name):
			continue
		seen[name] = true
		parts.append(name)
	return "、".join(parts)

func format_dinnertime_report(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var round := int(data.get("round", -1))
	var report_val = data.get("report", null)
	if not (report_val is Dictionary):
		out.append(_formatter._event("晚餐结算报告缺失（回合 %d）" % round, data))
		return out
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

	out.append(_formatter._event("晚餐结算（回合 %d）：售出 %d，未满足 %d" % [round, sales.size(), skipped.size()], data))

	# 1) 每个房屋消费记录
	for s_val in sales:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var owner := int(s.get("winner_owner", -1))
		var house_number := HouseNumberManagerClass.format_display_label(s.get("house_number", null), str(s.get("house_id", "")).strip_edges(), "")
		var rest_text: String = _formatter._format_restaurant_id_short(str(s.get("winner_restaurant_id", "")).strip_edges())
		var required_val = s.get("required", null)
		var required: Dictionary = required_val if (required_val is Dictionary) else {}
		var revenue := int(s.get("revenue", 0))
		var bonus := int(s.get("bonus", 0))
		var house_bonus := int(s.get("house_bonus", 0))
		var unit_price := int(s.get("unit_price", 0))
		var quantity := int(s.get("quantity", 0))
		var has_garden := bool(s.get("has_garden", false))
		var hb_breakdown_val = s.get("house_bonus_breakdown", null)
		var hb_breakdown: Dictionary = hb_breakdown_val if (hb_breakdown_val is Dictionary) else {}
		var hb_parts: Array[String] = _formatter._format_house_bonus_breakdown_parts(hb_breakdown)

		var items: String = _formatter._format_required_short(required, 3)
		var msg := "晚餐结算：房屋#%s 消费 %s" % [house_number, items]
		if not rest_text.is_empty():
			msg += " -> %s" % rest_text
		var total_income := revenue + house_bonus
		msg += " 收入 $%d" % total_income

		var breakdown_parts: Array[String] = []
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
		if owner >= 0:
			out.append(_formatter._player(owner, msg, s))
		else:
			out.append(_formatter._event(msg, s))

	for sk_val in skipped:
		if not (sk_val is Dictionary):
			continue
		var sk: Dictionary = sk_val
		var hn := HouseNumberManagerClass.format_display_label(sk.get("house_number", null), str(sk.get("house_id", "")).strip_edges(), "")
		var dcnt := int(sk.get("demands", 0))
		out.append(_formatter._event("晚餐结算：房屋#%s 未满足（需求 %d）" % [hn, dcnt], sk))

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

		var who := "玩家%d" % (pid + 1)
		if Globals != null:
			if Globals.has_method("get_player_name_compact"):
				var n := str(Globals.get_player_name_compact(pid)).strip_edges()
				if not n.is_empty():
					who = n
			elif Globals.has_method("get_player_name"):
				var n2 := str(Globals.get_player_name(pid)).strip_edges()
				if not n2.is_empty():
					who = n2

		out.append(_formatter._event("晚餐总结 %s: 总 $%d (售卖 $%d, 房屋奖 $%d, 服务员 $%d, CFO $%d)" % [
			who, tot_amt, s_amt, hb_amt, tips_amt, cfo_amt
		], {"round": round, "player_id": pid}))

	return out
