extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

func register(registrar) -> Result:
	var r = registrar.register_phase_sub_phase_order_override(Phase.PAYDAY, ["PaydayExtra"], 100)
	if not r.ok:
		return r
	return registrar.register_named_sub_phase_hook("PaydayExtra", HookType.BEFORE_ENTER, Callable(self, "_on_payday_extra_before_enter"), 100)

func _on_payday_extra_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("payday_sub_phase_test: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("payday_sub_phase_test: round_state 类型错误（期望 Dictionary）")
	state.round_state["payday_extra_entered"] = true
	return Result.success()
