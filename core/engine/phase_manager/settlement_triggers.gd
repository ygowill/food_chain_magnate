extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const Phase = DefsClass.Phase
const PHASE_NAMES = DefsClass.PHASE_NAMES

static func build_default_settlement_triggers_on_enter() -> Dictionary:
	var out: Dictionary = {}
	out[Phase.DINNERTIME] = [SettlementRegistryClass.Point.ENTER]
	out[Phase.MARKETING] = [SettlementRegistryClass.Point.ENTER]
	out[Phase.CLEANUP] = [SettlementRegistryClass.Point.ENTER]
	return out

static func build_default_settlement_triggers_on_exit() -> Dictionary:
	var out: Dictionary = {}
	out[Phase.PAYDAY] = [SettlementRegistryClass.Point.EXIT]
	return out

static func set_settlement_triggers(phase_manager, phase: int, timing: String, points: Array) -> Result:
	if phase == Phase.SETUP or phase == Phase.GAME_OVER:
		return Result.failure("settlement_triggers 不允许包含 Setup/GameOver")
	if points == null or not (points is Array):
		return Result.failure("settlement_triggers.%s[%s] 类型错误（期望 Array）" % [timing, str(PHASE_NAMES.get(phase, phase))])

	var out: Array[int] = []
	var seen := {}
	for i in range(points.size()):
		var v = points[i]
		if not (v is int):
			return Result.failure("settlement_triggers.%s[%s][%d] 类型错误（期望 int）" % [timing, str(PHASE_NAMES.get(phase, phase)), i])
		var p: int = int(v)
		if p != SettlementRegistryClass.Point.ENTER and p != SettlementRegistryClass.Point.EXIT:
			return Result.failure("settlement_triggers.%s[%s][%d] 不支持的 point: %d" % [timing, str(PHASE_NAMES.get(phase, phase)), i, p])
		if seen.has(p):
			return Result.failure("settlement_triggers.%s[%s] point 重复: %d" % [timing, str(PHASE_NAMES.get(phase, phase)), p])
		seen[p] = true
		out.append(p)

	if timing == "enter":
		if out.is_empty():
			phase_manager._settlement_triggers_on_enter.erase(phase)
		else:
			phase_manager._settlement_triggers_on_enter[phase] = out
		return Result.success()
	if timing == "exit":
		if out.is_empty():
			phase_manager._settlement_triggers_on_exit.erase(phase)
		else:
			phase_manager._settlement_triggers_on_exit[phase] = out
		return Result.success()
	return Result.failure("未知 settlement_triggers timing: %s" % timing)

static func run_settlement_triggers(phase_manager, timing: String, phase: int, state: GameState) -> Result:
	if phase_manager._settlement_registry == null:
		return Result.failure("SettlementRegistry 未设置")
	if state == null:
		return Result.failure("Settlement triggers: state 为空")

	var points: Array = []
	if timing == "enter":
		if phase_manager._settlement_triggers_on_enter.has(phase):
			points = phase_manager._settlement_triggers_on_enter.get(phase, [])
	elif timing == "exit":
		if phase_manager._settlement_triggers_on_exit.has(phase):
			points = phase_manager._settlement_triggers_on_exit.get(phase, [])
	else:
		return Result.failure("Settlement triggers: 未知 timing: %s" % timing)

	if points.is_empty():
		return Result.success()

	var warnings: Array[String] = []
	for i in range(points.size()):
		var p_val = points[i]
		if not (p_val is int):
			return Result.failure("Settlement triggers: points[%d] 类型错误（期望 int）" % i)
		var point: int = int(p_val)
		var r: Result = phase_manager._settlement_registry.run(phase, point, state, phase_manager)
		if not r.ok:
			return r
		warnings.append_array(r.warnings)
	return Result.success().with_warnings(warnings)

static func validate_required_primary_settlements(phase_manager) -> Result:
	if phase_manager._settlement_registry == null:
		return Result.failure("SettlementRegistry 未设置")

	var missing: Array[String] = []
	if not phase_manager._settlement_registry.has_primary(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER):
		missing.append("Dinnertime:enter")
	if not phase_manager._settlement_registry.has_primary(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT):
		missing.append("Payday:exit")
	if not phase_manager._settlement_registry.has_primary(Phase.MARKETING, SettlementRegistryClass.Point.ENTER):
		missing.append("Marketing:enter")
	if not phase_manager._settlement_registry.has_primary(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER):
		missing.append("Cleanup:enter")

	var unscheduled: Array[String] = []
	if not is_settlement_scheduled(phase_manager, Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER):
		unscheduled.append("Dinnertime:enter")
	if not is_settlement_scheduled(phase_manager, Phase.PAYDAY, SettlementRegistryClass.Point.EXIT):
		unscheduled.append("Payday:exit")
	if not is_settlement_scheduled(phase_manager, Phase.MARKETING, SettlementRegistryClass.Point.ENTER):
		unscheduled.append("Marketing:enter")
	if not is_settlement_scheduled(phase_manager, Phase.CLEANUP, SettlementRegistryClass.Point.ENTER):
		unscheduled.append("Cleanup:enter")

	if not missing.is_empty():
		return Result.failure(", ".join(missing))
	if not unscheduled.is_empty():
		return Result.failure("未配置结算触发点: %s" % ", ".join(unscheduled))
	return Result.success()

static func is_settlement_scheduled(phase_manager, phase: int, point: int) -> bool:
	if phase_manager._settlement_triggers_on_enter.has(phase):
		var a: Array = phase_manager._settlement_triggers_on_enter.get(phase, [])
		if a.has(point):
			return true
	if phase_manager._settlement_triggers_on_exit.has(phase):
		var b: Array = phase_manager._settlement_triggers_on_exit.get(phase, [])
		if b.has(point):
			return true
	return false

