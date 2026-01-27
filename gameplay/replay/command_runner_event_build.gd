# CommandRunner：事件构建（日志/展示语义）
# 该文件位于 gameplay 层：用于 UI/回放/日志从 state 差异推导事件，不属于 core 执行内核。
extends RefCounted

const DinnertimeEventsClass = preload("res://gameplay/replay/command_runner_event_build/dinnertime_events.gd")
const MarketingEventsClass = preload("res://gameplay/replay/command_runner_event_build/marketing_events.gd")
const CleanupEventsClass = preload("res://gameplay/replay/command_runner_event_build/cleanup_events.gd")
const OrderOfBusinessEventsClass = preload("res://gameplay/replay/command_runner_event_build/order_of_business_events.gd")
const PaydayEventsClass = preload("res://gameplay/replay/command_runner_event_build/payday_events.gd")

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
		events.append_array(OrderOfBusinessEventsClass.build_turn_order_finalized_events(old_state, new_state))

		# Dinnertime 结算报告：在离开 Dinnertime 时发射（便于 UI/日志按事件历史恢复，且不依赖当前 state）。
		events.append_array(DinnertimeEventsClass.build_dinnertime_report_events(old_state, new_state))

		# Payday 结算报告：在离开 Payday 时发射（PaydaySettlement 在 exit hook 运行，报告写入 new_state.round_state.payday）。
		events.append_array(PaydayEventsClass.build_payday_report_events(old_state, new_state))

		# Marketing 结算摘要：在离开 Marketing 时发射（便于 UI 日志从 EventBus.history 恢复）。
		# issue_tracker #48: per board 1 log entry, with details in event data.
		if str(old_state.phase) == "Marketing":
			events.append_array(MarketingEventsClass.build_marketing_demand_generated_events(old_state))
			events.append_array(MarketingEventsClass.build_marketing_expired_events(old_state))

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
			events.append_array(CleanupEventsClass.build_cleanup_inventory_discarded_events(new_state))

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
	return DinnertimeEventsClass.build_food_sold_events_from_dinnertime_report(dinnertime_state, report)

static func build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	return MarketingEventsClass.build_marketing_demand_generated_events(marketing_state)

static func build_marketing_expired_events(marketing_state: GameState) -> Array[Dictionary]:
	return MarketingEventsClass.build_marketing_expired_events(marketing_state)

static func build_cleanup_inventory_discarded_events(cleanup_state: GameState) -> Array[Dictionary]:
	return CleanupEventsClass.build_cleanup_inventory_discarded_events(cleanup_state)

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
