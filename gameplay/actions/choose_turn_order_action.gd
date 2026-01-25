# 决定顺序动作（Order of Business）
# 在“决定顺序”阶段，玩家按选择顺序挑选自己的行动顺序位置。
class_name ChooseTurnOrderAction
extends ActionExecutor

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = "choose_turn_order"
	display_name = "选择顺序"
	description = "在决定顺序阶段选择行动顺序位置"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["OrderOfBusiness"]
	phase_manager = manager

func _validate_specific(state: GameState, command: Command) -> Result:
	var player_count := state.players.size()

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

	if picks.has(command.actor):
		return Result.failure("你已选择过位置")

	var pos_result := require_int_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var position: int = pos_result.value
	if position < 0 or position >= player_count:
		return Result.failure("无效 position: %d" % position)

	if picks[position] != -1:
		return Result.failure("该位置已被占用: %d" % position)

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var pos_result := require_int_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var position: int = pos_result.value
	var player_count := state.players.size()
	var warnings: Array[String] = []

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

		# NOTE: 阶段推进由 AutoAdvance 负责（保证“选择顺序”日志归属 OrderOfBusiness，再进入 Working）。

	state.round_state["order_of_business"] = oob

	return Result.success({
		"player_id": command.actor,
		"position": position
	}).with_warnings(warnings)

func _generate_specific_events(old_state: GameState, new_state: GameState, _command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# 最终行动顺序落地事件（用于日志显示/回放恢复）。
	var old_finalized := false
	var new_finalized := false
	if old_state != null and (old_state.round_state is Dictionary):
		var oob_old_val = Dictionary(old_state.round_state).get("order_of_business", null)
		if oob_old_val is Dictionary:
			var oob_old: Dictionary = oob_old_val
			if oob_old.has("finalized") and (oob_old["finalized"] is bool):
				old_finalized = bool(oob_old["finalized"])
	if new_state != null and (new_state.round_state is Dictionary):
		var oob_new_val = Dictionary(new_state.round_state).get("order_of_business", null)
		if oob_new_val is Dictionary:
			var oob_new: Dictionary = oob_new_val
			if oob_new.has("finalized") and (oob_new["finalized"] is bool):
				new_finalized = bool(oob_new["finalized"])

	if (not old_finalized) and new_finalized:
		var final_order: Array[int] = []
		for pid in new_state.turn_order:
			final_order.append(int(pid))
		events.append({
			"type": EventBus.EventType.TURN_ORDER_FINALIZED,
			"data": {
				"round": int(new_state.round_number),
				"turn_order": final_order,
			}
		})

	# 若本动作触发了自动推进阶段，则补齐 phase/sub_phase 事件（原先由手动 advance_phase 触发）
	if old_state.phase != new_state.phase:
		if str(old_state.phase) == "Dinnertime":
			var report: Dictionary = {}
			if old_state.round_state is Dictionary:
				var v = Dictionary(old_state.round_state).get("dinnertime", null)
				if v is Dictionary:
					report = Dictionary(v).duplicate(true)
			events.append({
				"type": EventBus.EventType.DINNERTIME_REPORT,
				"data": {
					"round": old_state.round_number,
					"from_phase": str(old_state.phase),
					"to_phase": str(new_state.phase),
					"report": report,
				}
			})

		events.append({
			"type": EventBus.EventType.PHASE_CHANGED,
			"data": {
				"old_phase": old_state.phase,
				"new_phase": new_state.phase,
				"round": new_state.round_number
			}
		})

		if old_state.round_number != new_state.round_number:
			events.append({
				"type": EventBus.EventType.ROUND_STARTED,
				"data": {
					"round": new_state.round_number
				}
			})

	if old_state.sub_phase != new_state.sub_phase and not new_state.sub_phase.is_empty():
		events.append({
			"type": EventBus.EventType.SUB_PHASE_CHANGED,
			"data": {
				"old_sub_phase": old_state.sub_phase,
				"new_sub_phase": new_state.sub_phase
			}
		})

	return events
