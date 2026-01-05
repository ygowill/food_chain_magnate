# 跳过动作
# 玩家选择跳过当前回合的动作
class_name SkipAction
extends ActionExecutor

func _init() -> void:
	action_id = "skip"
	display_name = "跳过"
	description = "跳过当前动作机会"
	requires_actor = true
	is_mandatory = false

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合，当前玩家: %d" % current_player_id)

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id := command.actor

	# 记录本子阶段“已选择跳过”（用于未来的“所有玩家都 pass -> 自动推进子阶段”逻辑）
	# 注意：skip 不应写入 mandatory_actions_completed（强制动作完成记录）。
	if not state.sub_phase.is_empty() and state.round_state is Dictionary:
		assert(state.round_state.has("sub_phase_passed"), "skip: round_state 缺少 sub_phase_passed")
		var passed_val = state.round_state["sub_phase_passed"]
		if not (passed_val is Dictionary):
			return Result.failure("round_state.sub_phase_passed 类型错误（期望 Dictionary）")
		var passed: Dictionary = passed_val
		assert(passed.has(player_id) and (passed[player_id] is bool), "skip: sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % player_id)
		passed[player_id] = true
		state.round_state["sub_phase_passed"] = passed

	# 推进到下一个玩家
	state.current_player_index += 1
	if state.current_player_index >= state.turn_order.size():
		state.current_player_index = 0

	return Result.success()

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# 玩家回合结束
	events.append({
		"type": EventBus.EventType.PLAYER_TURN_ENDED,
		"data": {
			"player_id": command.actor,
			"action": "skip"
		}
	})

	# 下一个玩家回合开始
	var next_player_id := new_state.get_current_player_id()
	if next_player_id != command.actor:
		events.append({
			"type": EventBus.EventType.PLAYER_TURN_STARTED,
			"data": {
				"player_id": next_player_id
			}
		})

	return events
