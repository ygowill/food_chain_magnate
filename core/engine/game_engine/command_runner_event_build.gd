# CommandRunner：事件构建（抽离自 command_runner.gd）
# 目标：把“日志/展示语义”的事件生成逻辑从命令执行主流程中分离，降低单文件职责负担。
extends RefCounted

static func build_milestone_achieved_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if not (old_state.players is Array) or not (new_state.players is Array):
		return events

	var count := mini(old_state.players.size(), new_state.players.size())
	for player_id in range(count):
		var old_val = old_state.players[player_id]
		var new_val = new_state.players[player_id]
		if not (old_val is Dictionary) or not (new_val is Dictionary):
			continue
		var old_player: Dictionary = old_val
		var new_player: Dictionary = new_val

		var old_ms_val = old_player.get("milestones", [])
		var new_ms_val = new_player.get("milestones", [])
		if not (old_ms_val is Array) or not (new_ms_val is Array):
			continue
		var old_ms: Array = old_ms_val
		var new_ms: Array = new_ms_val

		var old_set := {}
		for mid_val in old_ms:
			if not (mid_val is String):
				continue
			var mid: String = str(mid_val)
			if mid.is_empty():
				continue
			old_set[mid] = true

		var added: Array[String] = []
		for mid_val2 in new_ms:
			if not (mid_val2 is String):
				continue
			var mid2: String = str(mid_val2)
			if mid2.is_empty():
				continue
			if old_set.has(mid2):
				continue
			added.append(mid2)

		if added.is_empty():
			continue
		added.sort()

		for milestone_id in added:
			events.append({
				"type": EventBus.EventType.MILESTONE_ACHIEVED,
				"data": {
					"player_id": player_id,
					"milestone_id": milestone_id,
					"action_id": str(command.action_id),
					"phase": str(new_state.phase),
					"sub_phase": str(new_state.sub_phase),
					"round": int(new_state.round_number),
				}
			})

	return events

static func build_phase_change_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events

	# 阶段变化事件
	if old_state.phase != new_state.phase:
		# 最终行动顺序落地事件（首轮 OrderOfBusiness auto finalize 依赖此事件用于日志显示/回放恢复）。
		if str(old_state.phase) == "OrderOfBusiness":
			var old_finalized := false
			var new_finalized := false
			if old_state.round_state is Dictionary:
				var oob_old_val = Dictionary(old_state.round_state).get("order_of_business", null)
				if oob_old_val is Dictionary:
					var oob_old: Dictionary = oob_old_val
					if oob_old.has("finalized") and (oob_old["finalized"] is bool):
						old_finalized = bool(oob_old["finalized"])
			if new_state.round_state is Dictionary:
				var oob_new_val = Dictionary(new_state.round_state).get("order_of_business", null)
				if oob_new_val is Dictionary:
					var oob_new: Dictionary = oob_new_val
					if oob_new.has("finalized") and (oob_new["finalized"] is bool):
						new_finalized = bool(oob_new["finalized"])
			if (not old_finalized) and new_finalized:
				var final_order: Array[int] = []
				for pid in new_state.turn_order:
					final_order.append(int(pid))
				events.append({
					"type": EventBus.EventType.TURN_ORDER_FINALIZED,
					"data": {
						"round": int(new_state.round_number),
						"turn_order": final_order,
					}
				})

		# Dinnertime 结算报告：在离开 Dinnertime 时发射（便于 UI/日志按事件历史恢复，且不依赖当前 state）。
		if str(old_state.phase) == "Dinnertime":
			var report: Dictionary = {}
			if old_state.round_state is Dictionary:
				var v = Dictionary(old_state.round_state).get("dinnertime", null)
				if v is Dictionary:
					report = Dictionary(v).duplicate(true)
			events.append({
				"type": EventBus.EventType.DINNERTIME_REPORT,
				"data": {
					"round": old_state.round_number,
					"from_phase": str(old_state.phase),
					"to_phase": str(new_state.phase),
					"report": report,
				}
			})
			# 细粒度售卖事件：从 dinnertime 报告中拆分出来（便于 UI 日志筛选/回放核对）。
			events.append_array(_build_food_sold_events_from_dinnertime_report(old_state, report))

		# Payday 结算报告：在离开 Payday 时发射（PaydaySettlement 在 exit hook 运行，报告写入 new_state.round_state.payday）。
		if str(old_state.phase) == "Payday":
			var report_payday: Dictionary = {}
			if new_state.round_state is Dictionary:
				var v2 = Dictionary(new_state.round_state).get("payday", null)
				if v2 is Dictionary:
					report_payday = Dictionary(v2).duplicate(true)
			events.append({
				"type": EventBus.EventType.PAYDAY_REPORT,
				"data": {
					"round": old_state.round_number,
					"from_phase": str(old_state.phase),
					"to_phase": str(new_state.phase),
					"report": report_payday,
				}
			})

		# Marketing 结算摘要：在离开 Marketing 时发射（便于 UI 日志从 EventBus.history 恢复）。
		# issue_tracker #48: per board 1 log entry, with details in event data.
		if str(old_state.phase) == "Marketing":
			events.append_array(_build_marketing_demand_generated_events(old_state))
			events.append_array(_build_marketing_expired_events(old_state))

		events.append({
			"type": EventBus.EventType.PHASE_CHANGED,
			"data": {
				"old_phase": old_state.phase,
				"new_phase": new_state.phase,
				"round": new_state.round_number
			}
		})

		# Cleanup 库存丢弃：在进入 Cleanup 时发射（清理结算在 Cleanup:enter 运行）。
		if str(new_state.phase) == "Cleanup":
			events.append_array(_build_cleanup_inventory_discarded_events(new_state))

		# 回合开始/结束事件
		if old_state.round_number != new_state.round_number:
			events.append({
				"type": EventBus.EventType.ROUND_ENDED,
				"data": {
					"round": old_state.round_number,
					"next_round": new_state.round_number,
				}
			})
			events.append({
				"type": EventBus.EventType.ROUND_STARTED,
				"data": {
					"round": new_state.round_number
				}
			})

	# 子阶段变化事件
	if old_state.sub_phase != new_state.sub_phase and not new_state.sub_phase.is_empty():
		events.append({
			"type": EventBus.EventType.SUB_PHASE_CHANGED,
			"data": {
				"old_sub_phase": old_state.sub_phase,
				"new_sub_phase": new_state.sub_phase
			}
		})

	return events

static func build_food_sold_events_from_dinnertime_report(dinnertime_state: GameState, report: Dictionary) -> Array[Dictionary]:
	return _build_food_sold_events_from_dinnertime_report(dinnertime_state, report)

static func build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	return _build_marketing_demand_generated_events(marketing_state)

static func build_marketing_expired_events(marketing_state: GameState) -> Array[Dictionary]:
	return _build_marketing_expired_events(marketing_state)

static func build_cleanup_inventory_discarded_events(cleanup_state: GameState) -> Array[Dictionary]:
	return _build_cleanup_inventory_discarded_events(cleanup_state)

static func _build_food_sold_events_from_dinnertime_report(dinnertime_state: GameState, report: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if dinnertime_state == null:
		return out
	if report == null or not (report is Dictionary):
		return out

	var sales_val = Dictionary(report).get("sales", null)
	if not (sales_val is Array):
		return out
	var round := int(dinnertime_state.round_number)

	for s_val in Array(sales_val):
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var player_id := int(s.get("winner_owner", -1))
		if player_id < 0:
			continue

		var required: Dictionary = {}
		var required_val = s.get("required", null)
		if required_val is Dictionary:
			required = Dictionary(required_val).duplicate(true)

		out.append({
			"type": EventBus.EventType.FOOD_SOLD,
			"data": {
				"round": round,
				"player_id": player_id,
				"house_id": str(s.get("house_id", "")).strip_edges(),
				"house_number": s.get("house_number", null),
				"restaurant_id": str(s.get("winner_restaurant_id", "")).strip_edges(),
				"required": required,
				"revenue": int(s.get("revenue", 0)),
				"bonus": int(s.get("bonus", 0)),
				"house_bonus": int(s.get("house_bonus", 0)),
			}
		})

	return out

static func _build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marketing_state == null:
		return out
	if not (marketing_state.round_state is Dictionary):
		return out

	var marketing_val = Dictionary(marketing_state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var marketing: Dictionary = marketing_val
	var processed_val = marketing.get("processed", null)
	if not (processed_val is Array):
		return out

	var houses_by_id: Dictionary = {}
	if marketing_state.map is Dictionary:
		var houses_val = Dictionary(marketing_state.map).get("houses", null)
		if houses_val is Dictionary:
			houses_by_id = houses_val

	for p_val in Array(processed_val):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val

		var board_number := int(p.get("board_number", 0))
		var owner := int(p.get("owner", -1))
		var marketing_type := str(p.get("type", "")).strip_edges()
		var employee_type := str(p.get("employee_type", "")).strip_edges()
		var product := str(p.get("product", "")).strip_edges()
		var demands_added := int(p.get("demands_added", 0))

		var affected_ids: Array[String] = []
		var affected_numbers: Array[int] = []
		var affected_val = p.get("affected_houses", null)
		if affected_val is Array:
			for hid_val in Array(affected_val):
				var hid := str(hid_val).strip_edges()
				if hid.is_empty():
					continue
				affected_ids.append(hid)
				var hn := _try_get_house_number(houses_by_id, hid)
				if hn > 0:
					affected_numbers.append(hn)

		var pos_arr: Array = []
		var wp_val = p.get("world_pos", null)
		if wp_val is Vector2i:
			var wp: Vector2i = wp_val
			pos_arr = [wp.x, wp.y]
		elif wp_val is Array:
			pos_arr = Array(wp_val)

		out.append({
			"type": EventBus.EventType.DEMAND_GENERATED,
			"data": {
				"round": int(marketing_state.round_number),
				"player_id": owner,
				"board_number": board_number,
				"marketing_type": marketing_type,
				"employee_type": employee_type,
				"product": product,
				"demands_added": demands_added,
				"affected_houses": affected_ids,
				"affected_house_numbers": affected_numbers,
				"position": pos_arr,
			}
		})

	return out

static func _build_marketing_expired_events(marketing_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marketing_state == null:
		return out
	if not (marketing_state.round_state is Dictionary):
		return out

	var marketing_val = Dictionary(marketing_state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var marketing: Dictionary = marketing_val
	var processed_val = marketing.get("processed", null)
	if not (processed_val is Array):
		return out

	var round := int(marketing_state.round_number)

	for p_val in Array(processed_val):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		if not bool(p.get("expired", false)):
			continue

		var board_number := int(p.get("board_number", 0))
		var owner := int(p.get("owner", -1))
		if owner < 0:
			continue
		var marketing_type := str(p.get("type", "")).strip_edges()
		var employee_type := str(p.get("employee_type", "")).strip_edges()
		var product := str(p.get("product", "")).strip_edges()

		var pos_arr: Array = []
		var wp_val = p.get("world_pos", null)
		if wp_val is Vector2i:
			var wp: Vector2i = wp_val
			pos_arr = [wp.x, wp.y]
		elif wp_val is Array:
			pos_arr = Array(wp_val)

		out.append({
			"type": EventBus.EventType.MARKETING_EXPIRED,
			"data": {
				"round": round,
				"player_id": owner,
				"board_number": board_number,
				"marketing_type": marketing_type,
				"employee_type": employee_type,
				"product": product,
				"position": pos_arr,
				"duration_before": int(p.get("duration_before", 0)),
				"duration_after": int(p.get("duration_after", 0)),
			}
		})

	return out

static func _build_cleanup_inventory_discarded_events(cleanup_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cleanup_state == null:
		return out
	if not (cleanup_state.round_state is Dictionary):
		return out

	var cleanup_val = Dictionary(cleanup_state.round_state).get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return out
	var cleanup: Dictionary = cleanup_val
	var inv_val = cleanup.get("inventory_discarded", null)
	if not (inv_val is Array):
		return out
	var round := int(cleanup_state.round_number)

	for item_val in Array(inv_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var player_id := int(item.get("player_id", -1))
		if player_id < 0:
			continue

		var discarded_val = item.get("discarded", null)
		if not (discarded_val is Dictionary):
			continue
		var discarded: Dictionary = Dictionary(discarded_val).duplicate(true)
		if discarded.is_empty():
			continue

		out.append({
			"type": EventBus.EventType.FOOD_DISCARDED,
			"data": {
				"round": round,
				"player_id": player_id,
				"has_fridge": bool(item.get("has_fridge", false)),
				"discarded": discarded,
			}
		})

	return out

static func _try_get_house_number(houses_by_id: Dictionary, house_id: String) -> int:
	if houses_by_id == null or houses_by_id.is_empty():
		return -1
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return -1
	if not houses_by_id.has(hid):
		return -1
	var h_val = houses_by_id.get(hid, null)
	if not (h_val is Dictionary):
		return -1
	var h: Dictionary = h_val
	var n_val = h.get("house_number", null)
	if n_val is int:
		return int(n_val)
	if n_val is float:
		var f: float = float(n_val)
		if f == floor(f):
			return int(f)
	return -1

static func build_player_cash_changed_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if not (old_state.players is Array) or not (new_state.players is Array):
		return events

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
		events.append({
			"type": EventBus.EventType.PLAYER_CASH_CHANGED,
			"data": {
				"player_id": player_id,
				"old_cash": old_cash,
				"new_cash": new_cash,
				"delta": new_cash - old_cash,
				"action_id": str(command.action_id),
				"phase": str(new_state.phase),
				"sub_phase": str(new_state.sub_phase),
			}
		})

	return events
