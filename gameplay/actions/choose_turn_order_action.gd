# 决定顺序动作（Order of Business）
# 在“决定顺序”阶段，玩家按选择顺序挑选自己的行动顺序位置。
class_name ChooseTurnOrderAction
extends ActionExecutor

func _init() -> void:
	action_id = "choose_turn_order"
	display_name = "选择顺序"
	description = "在决定顺序阶段选择行动顺序位置"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["OrderOfBusiness"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var pos_result := require_int_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var position: int = pos_result.value
	var player_count := state.players.size()
	if position < 0 or position >= player_count:
		return Result.failure("无效 position: %d" % position)

	# 当前选择者：在 OrderOfBusiness 期间 turn_order 被设置为 selection_order
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if not (state.round_state is Dictionary):
		return Result.failure("round_state 格式错误")

	if not state.round_state.has("order_of_business") or not (state.round_state["order_of_business"] is Dictionary):
		return Result.failure("OrderOfBusiness 未初始化")
	var oob: Dictionary = state.round_state["order_of_business"]

	if not oob.has("finalized") or not (oob["finalized"] is bool):
		return Result.failure("OrderOfBusiness finalized 缺失或类型错误")
	if bool(oob["finalized"]):
		return Result.failure("OrderOfBusiness 已完成选择")

	if not oob.has("picks") or not (oob["picks"] is Array):
		return Result.failure("OrderOfBusiness picks 缺失或类型错误")
	var picks: Array = oob["picks"]
	if picks.size() != player_count:
		return Result.failure("OrderOfBusiness picks 长度不匹配")

	if picks[position] != -1:
		return Result.failure("该位置已被占用: %d" % position)

	if picks.has(command.actor):
		return Result.failure("你已选择过位置")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var pos_result := require_int_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var position: int = pos_result.value
	var player_count := state.players.size()

	if not (state.round_state is Dictionary):
		return Result.failure("round_state 格式错误")
	if not state.round_state.has("order_of_business") or not (state.round_state["order_of_business"] is Dictionary):
		return Result.failure("OrderOfBusiness 未初始化")
	var oob: Dictionary = state.round_state["order_of_business"]
	if not oob.has("picks") or not (oob["picks"] is Array):
		return Result.failure("OrderOfBusiness picks 缺失或类型错误")
	var picks: Array = oob["picks"]
	picks[position] = command.actor
	oob["picks"] = picks

	# 推进到下一位选择者
	state.current_player_index += 1

	# 所有人都选完后，落地 turn_order
	if state.current_player_index >= player_count:
		if picks.has(-1):
			return Result.failure("OrderOfBusiness 未完成选择，无法结算 turn_order")

		var final_order: Array[int] = []
		for pid in picks:
			final_order.append(int(pid))
		state.turn_order = final_order
		state.current_player_index = 0
		oob["finalized"] = true

	state.round_state["order_of_business"] = oob

	return Result.success({
		"player_id": command.actor,
		"position": position
	})
