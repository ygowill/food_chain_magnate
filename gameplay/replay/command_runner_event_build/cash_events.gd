# CommandRunnerEventBuild：Cash 事件拆分
# 用途：从 state 差异推导玩家现金变化事件（日志/展示语义）。
extends RefCounted

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

