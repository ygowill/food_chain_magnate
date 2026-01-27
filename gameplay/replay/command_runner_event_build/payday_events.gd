# CommandRunnerEventBuild：Payday 事件拆分
# 用途：从 round_state.payday 中推导 payday 结算报告事件（日志/展示语义）。
extends RefCounted

static func build_payday_report_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if str(old_state.phase) != "Payday":
		return events
	if str(old_state.phase) == str(new_state.phase):
		return events

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
	return events

