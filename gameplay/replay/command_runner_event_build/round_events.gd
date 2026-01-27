# CommandRunnerEventBuild：Round 事件拆分
# 用途：从 phase change 的 state 差异推导回合开始/结束事件（日志/展示语义）。
extends RefCounted

static func build_round_boundary_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if old_state.round_number == new_state.round_number:
		return events

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
	return events

