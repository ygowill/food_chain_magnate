# 结束回合动作（内部）
# 仅推进 current_player_index（不写入 sub_phase_passed；不等同于“确认结束/结束子阶段”）
class_name EndTurnAction
extends ActionExecutor

func _init() -> void:
	action_id = "end_turn"
	display_name = "结束回合"
	description = "推进到下一位玩家"
	requires_actor = true
	is_mandatory = false
	is_internal = true

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if state.phase == "GameOver":
		return Result.failure("游戏已结束")

	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if state.turn_order.is_empty():
		return Result.failure("turn_order 为空")

	return Result.success()

func _apply_changes(state: GameState, _command: Command) -> Result:
	var size := state.turn_order.size()
	if size <= 0:
		return Result.failure("turn_order 为空")

	var passed := {}
	if state.round_state is Dictionary and state.round_state.has("sub_phase_passed") and (state.round_state["sub_phase_passed"] is Dictionary):
		passed = state.round_state["sub_phase_passed"]

	# 找到下一位“未确认结束”的玩家；若全部已确认结束，则保持现状（等待自动推进阶段逻辑处理）
	for offset in range(1, size + 1):
		var idx := state.current_player_index + offset
		if idx >= size:
			idx = idx % size
		var pid_val = state.turn_order[idx]
		if not (pid_val is int):
			continue
		var pid: int = int(pid_val)
		if not bool(passed.get(pid, false)):
			state.current_player_index = idx
			return Result.success()

	# 全员已确认结束：不改变 current_player_index
	return Result.success()

func _generate_specific_events(_old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	events.append({
		"type": EventBus.EventType.PLAYER_TURN_ENDED,
		"data": {
			"player_id": command.actor,
			"action": "end_turn"
		}
	})

	var next_player_id := new_state.get_current_player_id()
	if next_player_id != command.actor:
		events.append({
			"type": EventBus.EventType.PLAYER_TURN_STARTED,
			"data": {
				"player_id": next_player_id
			}
		})

	return events
