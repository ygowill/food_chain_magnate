# hooks/settlement 回调契约测试（P1.4）
# 目的：确保 hook/settlement 回调必须返回 Result。
class_name CallbackResultContractTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const HooksClass = preload("res://core/engine/phase_manager/hooks.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

static func run() -> Result:
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
	if hr.ok:
		return Result.failure("Phase hooks: 非 Result 返回应始终失败")
	var hook_err := str(hr.error)
	if hook_err.find("必须返回 Result") < 0:
		return Result.failure("Phase hooks: 错误信息应包含 必须返回 Result，实际: %s" % hook_err)

	# Case B: SettlementRegistry（primary 返回非 Result）
	var reg := SettlementRegistryClass.new()
	var bad_settlement := _BadSettlement.new()
	var rr := reg.register_primary(DefsClass.Phase.WORKING, SettlementRegistryClass.Point.ENTER, Callable(bad_settlement, "bad_settlement"), "CallbackResultContractTest")
	if not rr.ok:
		return Result.failure("register_primary 失败: %s" % rr.error)
	var sr: Result = reg.run(DefsClass.Phase.WORKING, SettlementRegistryClass.Point.ENTER, state, null)
	if sr.ok:
		return Result.failure("SettlementRegistry: primary 非 Result 返回应始终失败")
	var settlement_err := str(sr.error)
	if settlement_err.find("必须返回 Result") < 0:
		return Result.failure("SettlementRegistry: primary 错误信息应包含 必须返回 Result，实际: %s" % settlement_err)

	var ext_r := _test_bad_extension_settlement_fails(state)
	if not ext_r.ok:
		return ext_r

	return Result.success()

static func _test_bad_extension_settlement_fails(state: GameState) -> Result:
	var reg := SettlementRegistryClass.new()
	var good_settlement := _GoodSettlement.new()
	var bad_settlement := _BadSettlement.new()
	var primary_r := reg.register_primary(DefsClass.Phase.WORKING, SettlementRegistryClass.Point.EXIT, Callable(good_settlement, "ok"), "CallbackResultContractTest")
	if not primary_r.ok:
		return Result.failure("register_primary(good) 失败: %s" % primary_r.error)
	var ext_r := reg.register_extension(DefsClass.Phase.WORKING, SettlementRegistryClass.Point.EXIT, Callable(bad_settlement, "bad_settlement"), 50, "CallbackResultContractTest")
	if not ext_r.ok:
		return Result.failure("register_extension 失败: %s" % ext_r.error)
	var run_r: Result = reg.run(DefsClass.Phase.WORKING, SettlementRegistryClass.Point.EXIT, state, null)
	if run_r.ok:
		return Result.failure("SettlementRegistry: extension 非 Result 返回应始终失败")
	var err := str(run_r.error)
	if err.find("必须返回 Result") < 0 or err.find("extension") < 0:
		return Result.failure("SettlementRegistry: extension 错误信息应包含 必须返回 Result/extension，实际: %s" % err)
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

class _GoodSettlement:
	extends RefCounted

	func ok(_state: GameState, _phase_manager) -> Result:
		return Result.success()
