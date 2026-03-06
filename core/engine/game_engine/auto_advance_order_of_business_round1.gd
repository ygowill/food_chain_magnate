extends RefCounted

const RoundStateOrderOfBusinessClass = preload("res://core/utils/round_state_order_of_business.gd")

static func auto_finalize_order_of_business_round1(state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("OrderOfBusiness auto finalize: state 为空")
	if not (state_in.round_state is Dictionary):
		return Result.failure("OrderOfBusiness auto finalize: state.round_state 类型错误（期望 Dictionary）")
	var oob_read := RoundStateOrderOfBusinessClass.require_order_of_business(state_in.round_state, "OrderOfBusiness auto finalize")
	if not oob_read.ok:
		return oob_read
	var oob: Dictionary = oob_read.value

	var finalized_read := RoundStateOrderOfBusinessClass.require_finalized(oob, "OrderOfBusiness auto finalize")
	if not finalized_read.ok:
		return finalized_read
	if bool(finalized_read.value):
		return Result.success()

	var previous_turn_read := RoundStateOrderOfBusinessClass.require_previous_turn_order(oob, "OrderOfBusiness auto finalize")
	if not previous_turn_read.ok:
		return previous_turn_read
	var prev_val: Array = previous_turn_read.value

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

