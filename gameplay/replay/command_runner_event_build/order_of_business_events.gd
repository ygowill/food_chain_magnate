# CommandRunnerEventBuild：OrderOfBusiness 事件拆分
# 用途：从 round_state.order_of_business 中推导“行动顺序最终落地”事件（日志/展示语义）。
extends RefCounted

static func build_turn_order_finalized_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if str(old_state.phase) != "OrderOfBusiness":
		return events
	if str(old_state.phase) == str(new_state.phase):
		return events

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
	if old_finalized or (not new_finalized):
		return events

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
	return events

