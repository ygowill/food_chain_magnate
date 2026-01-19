# 设定奢侈品价格动作（奢侈品经理的强制动作）
# 激活奢侈品经理效果：基础单价 +$10
class_name SetLuxuryPriceAction
extends ActionExecutor

const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")

func _init() -> void:
	action_id = "set_luxury_price"
	display_name = "设定奢侈品价格"
	description = "激活奢侈品经理效果（+$10）"
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

	# 检查玩家是否有奢侈品经理
	var player := state.get_player(player_id)
	if MandatoryActionsRulesClass.find_provider_employee_id(player, action_id).is_empty():
		return Result.failure("玩家没有奢侈品经理")

	# 检查本回合是否已执行此动作
	if MandatoryActionsRulesClass.has_completed_this_round(state, player_id, action_id):
		return Result.failure("本回合已设定奢侈品价格")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id := command.actor
	var player := state.get_player(player_id)
	var provider_id := MandatoryActionsRulesClass.find_provider_employee_id(player, action_id)
	if provider_id.is_empty():
		return Result.failure("玩家没有奢侈品经理")

	# 记录强制动作已完成
	MandatoryActionsRulesClass.mark_completed(state, player_id, action_id)

	# 设置价格修正（存储在 round_state 中）
	if not state.round_state.has("price_modifiers"):
		state.round_state["price_modifiers"] = {}
	if not state.round_state.price_modifiers.has(player_id):
		state.round_state.price_modifiers[player_id] = {}

	state.round_state.price_modifiers[player_id][provider_id] = 10

	return Result.success({
		"player_id": player_id,
		"modifier": 10
	})

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	events.append({
		"type": EventBus.EventType.COMMAND_EXECUTED,
		"data": {
			"action_id": action_id,
			"player_id": command.actor,
			"mandatory": true,
			"price_modifier": 10
		}
	})

	return events
