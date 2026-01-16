extends RefCounted

static func was_milestone_awarded_this_turn(state: GameState, player_id: int, milestone_id: String) -> bool:
	if state == null:
		return false
	if milestone_id.is_empty():
		return false
	if not (state.round_state is Dictionary):
		return false
	if not state.round_state.has("milestones_auto_awarded"):
		return false
	var log_val = state.round_state.get("milestones_auto_awarded", null)
	if not (log_val is Array):
		return false
	var log: Array = log_val
	for entry_val in log:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if int(entry.get("player_id", -1)) != player_id:
			continue
		if str(entry.get("milestone_id", "")) != milestone_id:
			continue
		return true
	return false
