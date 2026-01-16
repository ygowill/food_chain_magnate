# hooks/settlement 回调契约测试（P1.4）
# 目的：确保回调必须返回 Result；否则至少 warning，且在 DebugFlags 下升级为 failure。
class_name CallbackResultContractTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const HooksClass = preload("res://core/engine/phase_manager/hooks.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

static func run() -> Result:
	var expect_fail := DebugFlags.is_debug_mode()

	var state := GameState.new()
	state.players = []
	state.round_state = {}

	# Case A: PhaseManager hooks（返回非 Result）
	var hooks := HooksClass.new(
		[DefsClass.Phase.WORKING],
		[DefsClass.WorkingSubPhase.RECRUIT],
		[0, 1, 2, 3]
	)
	var bad_hook := _BadHook.new()
	hooks.register_phase_hook(DefsClass.Phase.WORKING, 0, Callable(bad_hook, "bad_hook"), 100, "CallbackResultContractTest")
	var hr: Result = hooks.run_phase_hooks(DefsClass.Phase.WORKING, 0, state)
	if expect_fail:
		if hr.ok:
			return Result.failure("Phase hooks: 预期 debug 模式下非 Result 返回应失败，但实际 ok=true")
	else:
		if not hr.ok:
			return Result.failure("Phase hooks: 预期非 debug 模式下应仅 warning，但实际失败: %s" % hr.error)
		if hr.warnings.is_empty():
			return Result.failure("Phase hooks: 预期产生 warning，但 warnings 为空")

	# Case B: SettlementRegistry（primary 返回非 Result）
	var reg := SettlementRegistryClass.new()
	var bad_settlement := _BadSettlement.new()
	var rr := reg.register_primary(DefsClass.Phase.WORKING, SettlementRegistryClass.Point.ENTER, Callable(bad_settlement, "bad_settlement"), "CallbackResultContractTest")
	if not rr.ok:
		return Result.failure("register_primary 失败: %s" % rr.error)
	var sr: Result = reg.run(DefsClass.Phase.WORKING, SettlementRegistryClass.Point.ENTER, state, null)
	if expect_fail:
		if sr.ok:
			return Result.failure("SettlementRegistry: 预期 debug 模式下非 Result 返回应失败，但实际 ok=true")
	else:
		if not sr.ok:
			return Result.failure("SettlementRegistry: 预期非 debug 模式下应仅 warning，但实际失败: %s" % sr.error)
		if sr.warnings.is_empty():
			return Result.failure("SettlementRegistry: 预期产生 warning，但 warnings 为空")

	return Result.success()

class _BadHook:
	extends RefCounted

	func bad_hook(_state: GameState):
		# 故意不返回 Result（返回 null）
		pass

class _BadSettlement:
	extends RefCounted

	func bad_settlement(_state: GameState, _phase_manager):
		# 故意不返回 Result（返回 null）
		pass

