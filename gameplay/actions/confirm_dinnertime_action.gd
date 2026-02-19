# 确认晚餐结算动作
# 清除 dinnertime pending_phase_action，允许 auto-advance 继续推进
class_name ConfirmDinnertimeAction
extends ActionExecutor

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

func _init() -> void:
	action_id = "confirm_dinnertime"
	display_name = "确认晚餐结算"
	description = "确认晚餐结算结果，推进到下一阶段"
	requires_actor = false
	is_mandatory = false

func _validate_specific(state: GameState, _command: Command) -> Result:
	if str(state.phase) != DefsClass.PHASE_DINNERTIME:
		return Result.failure("当前不在晚餐阶段")
	return Result.success()

func _apply_changes(state: GameState, _command: Command) -> Result:
	return RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		state.round_state, DefsClass.PHASE_DINNERTIME, [], "confirm_dinnertime"
	)
