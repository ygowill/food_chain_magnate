# CommandRunnerEventBuild：Phase/SubPhase 事件拆分
# 用途：从 phase/sub_phase 差异推导阶段变化事件（日志/展示语义）。
extends RefCounted

static func build_phase_changed_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if old_state.phase == new_state.phase:
		return events
	events.append({
		"type": EventBus.EventType.PHASE_CHANGED,
		"data": {
			"old_phase": old_state.phase,
			"new_phase": new_state.phase,
			"round": new_state.round_number
		}
	})
	return events

static func build_sub_phase_changed_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if old_state.sub_phase == new_state.sub_phase:
		return events
	if new_state.sub_phase.is_empty():
		return events
	events.append({
		"type": EventBus.EventType.SUB_PHASE_CHANGED,
		"data": {
			"old_sub_phase": old_state.sub_phase,
			"new_sub_phase": new_state.sub_phase
		}
	})
	return events

