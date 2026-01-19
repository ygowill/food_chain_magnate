# 设定折扣动作（折扣经理的强制动作）
# 激活折扣经理效果：基础单价 -$3
class_name SetDiscountAction
extends ActionExecutor

const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")

func _init() -> void:
	action_id = "set_discount"
	display_name = "设定折扣"
	description = "激活折扣经理效果（-$3）"
	requires_actor = true
	is_mandatory = true
	allowed_phases = ["Working"]
	allowed_sub_phases = []  # 任何子阶段都可以执行

func _validate_specific(state: GameState, command: Command) -> Result:
	var player_id := command.actor

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if player_id != current_player_id:
		return Result.failure("不是你的回合")

	# 检查玩家是否有折扣经理
	var player := state.get_player(player_id)
	if MandatoryActionsRulesClass.find_provider_employee_id(player, action_id).is_empty():
		return Result.failure("玩家没有折扣经理")

	# 检查本回合是否已执行此动作
	if MandatoryActionsRulesClass.has_completed_this_round(state, player_id, action_id):
		return Result.failure("本回合已设定折扣")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id := command.actor
	var warnings: Array[String] = []
	var player := state.get_player(player_id)
	var provider_id := MandatoryActionsRulesClass.find_provider_employee_id(player, action_id)
	if provider_id.is_empty():
		return Result.failure("玩家没有折扣经理")

	# 记录强制动作已完成
	MandatoryActionsRulesClass.mark_completed(state, player_id, action_id)

	# 设置价格修正（存储在 round_state 中）
	if not state.round_state.has("price_modifiers"):
		state.round_state["price_modifiers"] = {}
	if not state.round_state.price_modifiers.has(player_id):
		state.round_state.price_modifiers[player_id] = {}

	state.round_state.price_modifiers[player_id][provider_id] = -3

	# 使用员工：用于 FIRST DISCOUNT MANAGER USED
	EmployeeUsageHelperClass.append_use_employee_warning(warnings, state, player_id, provider_id)

	# 若玩家具有“折扣移除银行资金”效果，则标记为“下回合 Restructuring 结束扣款”
	var p_val = state.players[player_id]
	if p_val is Dictionary:
		var p: Dictionary = p_val
		if bool(p.get("bank_burn_on_discount_ge_3", false)):
			p["bank_burn_pending"] = true
			state.players[player_id] = p

	var ms := MilestoneSystemClass.process_event(state, "LowerPrice", {"player_id": player_id})

	var result := Result.success({
		"player_id": player_id,
		"modifier": -3
	}).with_warnings(warnings)
	if not ms.ok:
		result.with_warning("里程碑触发失败(LowerPrice): %s" % ms.error)
	return result

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	events.append({
		"type": EventBus.EventType.COMMAND_EXECUTED,
		"data": {
			"action_id": action_id,
			"player_id": command.actor,
			"mandatory": true,
			"price_modifier": -3
		}
	})

	return events
