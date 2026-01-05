extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

func register(registrar) -> Result:
	var r0 = registrar.register_phase_hook(Phase.MARKETING, HookType.BEFORE_ENTER, Callable(self, "_on_marketing_before_enter"))
	if not r0.ok:
		return r0
	var r = registrar.register_primary_settlement(Phase.MARKETING, SettlementRegistryClass.Point.EXIT, Callable(self, "_on_marketing_exit"))
	if not r.ok:
		return r
	# 进入 Marketing 时同时触发 ENTER 与 EXIT
	return registrar.register_settlement_triggers_override(
		Phase.MARKETING,
		"enter",
		[SettlementRegistryClass.Point.ENTER, SettlementRegistryClass.Point.EXIT],
		100
	)

func _on_marketing_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("settlement_trigger_override_points_order_test: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("settlement_trigger_override_points_order_test: state.round_state 类型错误（期望 Dictionary）")
	state.round_state["points_order"] = ["enter"]
	return Result.success()

func _on_marketing_exit(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("settlement_trigger_override_points_order_test: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("settlement_trigger_override_points_order_test: state.round_state 类型错误（期望 Dictionary）")
	var order: Array[String] = []
	if state.round_state.has("points_order"):
		var v = state.round_state.get("points_order", null)
		if v is Array:
			var a: Array = v
			for i in range(a.size()):
				order.append(str(a[i]))
	order.append("exit")
	state.round_state["points_order"] = order
	return Result.success()
