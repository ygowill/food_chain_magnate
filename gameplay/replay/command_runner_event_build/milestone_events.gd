# CommandRunnerEventBuild：Milestone 事件拆分
# 用途：从 state 差异推导里程碑达成事件（日志/展示语义）。
extends RefCounted

const DeferredEventPolicyClass = preload("res://gameplay/replay/step_timeline_build/deferred_event_policy.gd")

const MILESTONE_FIRST_THROW_AWAY := "first_throw_away"

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
			var data := {
				"player_id": player_id,
				"milestone_id": milestone_id,
				"action_id": str(command.action_id),
				"phase": str(new_state.phase),
				"sub_phase": str(new_state.sub_phase),
				"round": int(new_state.round_number),
			}
			if milestone_id == MILESTONE_FIRST_THROW_AWAY:
				data = DeferredEventPolicyClass.mark_cleanup_after_discards(data)
			events.append({
				"type": EventBus.EventType.MILESTONE_ACHIEVED,
				"data": data,
			})

	return events
