# CommandRunnerEventBuild：Cash 事件拆分
# 用途：从 state 差异推导玩家现金变化事件（日志/展示语义）。
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func build_player_cash_changed_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if not (old_state.players is Array) or not (new_state.players is Array):
		return events

	var dinnertime_report: Dictionary = {}
	var can_attach_dinnertime_breakdown := false
	if _is_entering_dinnertime(old_state, new_state):
		dinnertime_report = _read_dinnertime_report(new_state)
		can_attach_dinnertime_breakdown = not dinnertime_report.is_empty()

	var count := mini(old_state.players.size(), new_state.players.size())
	for player_id in range(count):
		var old_val = old_state.players[player_id]
		var new_val = new_state.players[player_id]
		if not (old_val is Dictionary) or not (new_val is Dictionary):
			continue
		var old_player: Dictionary = old_val
		var new_player: Dictionary = new_val
		var old_cash := int(old_player.get("cash", 0))
		var new_cash := int(new_player.get("cash", 0))
		if old_cash == new_cash:
			continue
		var delta := new_cash - old_cash
		var data := {
			"player_id": player_id,
			"old_cash": old_cash,
			"new_cash": new_cash,
			"delta": delta,
			"action_id": str(command.action_id),
			"phase": str(new_state.phase),
			"sub_phase": str(new_state.sub_phase),
		}

		if can_attach_dinnertime_breakdown and delta > 0:
			var breakdown := _build_dinnertime_income_breakdown(dinnertime_report, player_id, delta)
			if not breakdown.is_empty():
				data["income_breakdown"] = breakdown

		events.append({
			"type": EventBus.EventType.PLAYER_CASH_CHANGED,
			"data": data,
		})

	return events

static func _is_entering_dinnertime(old_state: GameState, new_state: GameState) -> bool:
	if old_state == null or new_state == null:
		return false
	if str(old_state.phase) == str(new_state.phase):
		return false
	return str(new_state.phase) == DefsClass.PHASE_DINNERTIME

static func _read_dinnertime_report(state: GameState) -> Dictionary:
	if state == null:
		return {}
	if not (state.round_state is Dictionary):
		return {}
	var v = Dictionary(state.round_state).get("dinnertime", null)
	if not (v is Dictionary):
		return {}
	return v as Dictionary

static func _get_array_int(arr_val, idx: int) -> int:
	if not (arr_val is Array):
		return 0
	var arr: Array = arr_val
	if idx < 0 or idx >= arr.size():
		return 0
	var v = arr[idx]
	if v is int:
		return int(v)
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return int(f)
	return 0

static func _build_dinnertime_income_breakdown(report: Dictionary, player_id: int, delta: int) -> Dictionary:
	if report == null or not (report is Dictionary) or report.is_empty():
		return {}
	if player_id < 0 or delta <= 0:
		return {}

	var income_sales_total := _get_array_int(report.get("income_sales", null), player_id)
	var income_house_bonus_total := _get_array_int(report.get("income_sale_house_bonus", null), player_id)
	var income_tips_total := _get_array_int(report.get("income_tips", null), player_id)
	var income_cfo_total := _get_array_int(report.get("income_cfo_bonus", null), player_id)

	var food_price := 0
	var garden_bonus := 0
	var marketing_bonus := 0
	var revenue_floor_adjustment := 0
	var sale_revenue_sum := 0

	var park_bonus := 0
	var fry_chef_bonus := 0

	var sales_val = report.get("sales", [])
	var sales: Array = sales_val if (sales_val is Array) else []
	for s_val in sales:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		if int(s.get("winner_owner", -1)) != player_id:
			continue

		var unit_price := int(s.get("unit_price", 0))
		var qty := int(s.get("quantity", 0))
		var base_price_part := unit_price * qty
		var sale_garden_bonus := base_price_part if bool(s.get("has_garden", false)) else 0
		var sale_marketing_bonus := int(s.get("bonus", 0))
		var sale_revenue := int(s.get("revenue", 0))

		food_price += base_price_part
		garden_bonus += sale_garden_bonus
		marketing_bonus += sale_marketing_bonus
		sale_revenue_sum += sale_revenue
		revenue_floor_adjustment += sale_revenue - (base_price_part + sale_garden_bonus + sale_marketing_bonus)

		var hb_breakdown_val = s.get("house_bonus_breakdown", null)
		if hb_breakdown_val is Dictionary:
			var hb_breakdown: Dictionary = hb_breakdown_val
			park_bonus += int(hb_breakdown.get("park", 0))
			fry_chef_bonus += int(hb_breakdown.get("fry_chef", 0))

	var route_purchase_income := income_sales_total - sale_revenue_sum
	var house_bonus_other := income_house_bonus_total - park_bonus - fry_chef_bonus
	if house_bonus_other < 0:
		house_bonus_other = 0

	var items: Array[Dictionary] = []
	_append_breakdown_item(items, "food_price", food_price)
	_append_breakdown_item(items, "garden_bonus", garden_bonus)
	_append_breakdown_item(items, "marketing_bonus", marketing_bonus)
	_append_breakdown_item(items, "route_purchase_income", route_purchase_income)
	_append_breakdown_item(items, "park_bonus", park_bonus)
	_append_breakdown_item(items, "fry_chef_bonus", fry_chef_bonus)
	_append_breakdown_item(items, "house_bonus_other", house_bonus_other)
	_append_breakdown_item(items, "tips", income_tips_total)
	_append_breakdown_item(items, "cfo_bonus", income_cfo_total)
	_append_breakdown_item(items, "revenue_floor_adjustment", revenue_floor_adjustment)

	var sum := 0
	for it_val in items:
		if not (it_val is Dictionary):
			continue
		sum += int((it_val as Dictionary).get("amount", 0))

	var residual := delta - sum
	_append_breakdown_item(items, "other", residual)

	# 若完全无法拆分（例如 report 缺失），则不附加，避免误导。
	var has_any := false
	for it_val in items:
		if not (it_val is Dictionary):
			continue
		if int((it_val as Dictionary).get("amount", 0)) != 0:
			has_any = true
			break
	if not has_any:
		return {}

	return {
		"context": "dinnertime_income",
		"total": delta,
		"items": items,
	}

static func _append_breakdown_item(items: Array[Dictionary], id: String, amount: int) -> void:
	if id.is_empty():
		return
	if amount == 0:
		return
	items.append({
		"id": id,
		"amount": amount,
	})
