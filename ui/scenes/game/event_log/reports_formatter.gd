# GameEventLogFormatter：报表类事件拆分（Payday/Dinnertime）
extends RefCounted

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
		var paid_cash := int(item.get("paid", 0))
		var unpaid := int(item.get("unpaid", 0))
		var discount := int(item.get("salary_discount", 0))
		var delta := int(item.get("milestone_delta", 0))

		var token_total := 0
		var paid_tokens_val = item.get("paid_with_tokens", null)
		if paid_tokens_val is Dictionary:
			var paid_tokens: Dictionary = paid_tokens_val
			for k in paid_tokens.keys():
				token_total += int(paid_tokens.get(k, 0))

		var extra_parts: Array[String] = []
		if discount > 0:
			extra_parts.append("折扣-$%d" % discount)
		if delta != 0:
			extra_parts.append("里程碑%+d" % delta)

		var text := "发薪日"
		if due == 0 and paid_cash == 0 and unpaid == 0 and token_total == 0:
			text += "：无需支付"
			if not extra_parts.is_empty():
				text += "（%s）" % "，".join(extra_parts)
		else:
			text += "：应付$%d" % due

			var pay_parts: Array[String] = []
			if paid_cash > 0:
				pay_parts.append("现金$%d" % paid_cash)
			if token_total > 0:
				pay_parts.append("代币x%d" % token_total)
			if not pay_parts.is_empty():
				text += "，支付：" + " + ".join(pay_parts)

			if unpaid > 0:
				text += "，欠薪$%d" % unpaid

			if not extra_parts.is_empty():
				text += "（%s）" % "，".join(extra_parts)

		var d := item.duplicate(true)
		d["round"] = round
		out.append(_formatter._player(player_id, text, d))

	return out

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
		var house_number := str(s.get("house_number", "")).strip_edges()
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
		var hn := str(sk.get("house_number", "")).strip_edges()
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

		out.append(_formatter._event("晚餐总结 玩家%d: 总 $%d (售卖 $%d, 房屋奖 $%d, 服务员 $%d, CFO $%d)" % [
			pid + 1, tot_amt, s_amt, hb_amt, tips_amt, cfo_amt
		], {"round": round, "player_id": pid}))

	return out
