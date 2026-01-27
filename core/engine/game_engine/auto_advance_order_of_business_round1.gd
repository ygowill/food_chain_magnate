extends RefCounted

static func auto_finalize_order_of_business_round1(state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("OrderOfBusiness auto finalize: state 为空")
	if not (state_in.round_state is Dictionary):
		return Result.failure("OrderOfBusiness auto finalize: state.round_state 类型错误（期望 Dictionary）")
	if not state_in.round_state.has("order_of_business") or not (state_in.round_state["order_of_business"] is Dictionary):
		return Result.failure("OrderOfBusiness auto finalize: round_state.order_of_business 缺失或类型错误（期望 Dictionary）")
	var oob: Dictionary = state_in.round_state["order_of_business"]

	if not oob.has("finalized") or not (oob["finalized"] is bool):
		return Result.failure("OrderOfBusiness auto finalize: finalized 缺失或类型错误（期望 bool）")
	if bool(oob["finalized"]):
		return Result.success()

	if not oob.has("previous_turn_order") or not (oob["previous_turn_order"] is Array):
		return Result.failure("OrderOfBusiness auto finalize: previous_turn_order 缺失或类型错误（期望 Array）")
	var prev_val: Array = oob["previous_turn_order"]

	var player_count := state_in.players.size()
	if prev_val.size() != player_count:
		return Result.failure("OrderOfBusiness auto finalize: previous_turn_order 长度错误: %d（期望 %d）" % [prev_val.size(), player_count])

	var seen := {}
	var final_order: Array[int] = []
	for i in range(prev_val.size()):
		var pid_val = prev_val[i]
		if not (pid_val is int):
			return Result.failure("OrderOfBusiness auto finalize: previous_turn_order[%d] 类型错误（期望 int）" % i)
		var pid: int = int(pid_val)
		if pid < 0 or pid >= player_count:
			return Result.failure("OrderOfBusiness auto finalize: previous_turn_order[%d] 超出范围: %d" % [i, pid])
		if seen.has(pid):
			return Result.failure("OrderOfBusiness auto finalize: previous_turn_order 重复玩家: %d" % pid)
		seen[pid] = true
		final_order.append(pid)

	var picks: Array = []
	for pid2 in final_order:
		picks.append(pid2)

	oob["picks"] = picks
	oob["finalized"] = true
	state_in.round_state["order_of_business"] = oob

	state_in.turn_order = final_order
	state_in.current_player_index = 0

	return Result.success()

