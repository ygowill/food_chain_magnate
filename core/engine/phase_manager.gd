# 阶段管理器
# 管理游戏七阶段和工作子阶段的状态机，支持钩子系统
class_name PhaseManager
extends RefCounted

# === 常量定义 ===

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const HooksClass = preload("res://core/engine/phase_manager/hooks.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const Phase = DefsClass.Phase
const WorkingSubPhase = DefsClass.WorkingSubPhase
const PHASE_NAMES = DefsClass.PHASE_NAMES
const PHASE_ORDER = DefsClass.PHASE_ORDER
const SUB_PHASE_NAMES = DefsClass.SUB_PHASE_NAMES
const SUB_PHASE_ORDER = DefsClass.SUB_PHASE_ORDER

# 钩子类型
enum HookType {
	BEFORE_ENTER,
	AFTER_ENTER,
	BEFORE_EXIT,
	AFTER_EXIT
}

# === 钩子存储 ===
# phase -> hook_type -> Array[{callback, priority, source}]
var _hooks = null

# === 可插拔系统 ===
var _marketing_range_calculator = null
var _settlement_registry = null
var _effect_registry = null
var _phase_order_enums: Array[int] = []
var _phase_order_names: Array[String] = []
var _settlement_triggers_on_enter: Dictionary = {}  # phase_enum -> Array[int] (SettlementRegistry.Point)
var _settlement_triggers_on_exit: Dictionary = {}  # phase_enum -> Array[int] (SettlementRegistry.Point)
var _working_sub_phase_order_names: Array[String] = []
var _cleanup_sub_phase_order_names: Array[String] = []
var _phase_sub_phase_orders: Dictionary = {}  # phase_enum -> Array[String]

# === 初始化 ===

func _init() -> void:
	_hooks = HooksClass.new(PHASE_NAMES.keys(), SUB_PHASE_NAMES.keys(), HookType.values())
	_marketing_range_calculator = MarketingRangeCalculatorClass.new()
	_settlement_registry = null
	_effect_registry = null
	_phase_order_enums = []
	for p in PHASE_ORDER:
		_phase_order_enums.append(int(p))
	_phase_order_names = _build_phase_order_names(_phase_order_enums)
	_settlement_triggers_on_enter = _build_default_settlement_triggers_on_enter()
	_settlement_triggers_on_exit = _build_default_settlement_triggers_on_exit()
	_working_sub_phase_order_names = _build_default_working_sub_phase_order_names()
	_cleanup_sub_phase_order_names = []
	_phase_sub_phase_orders = {}

func _build_default_settlement_triggers_on_enter() -> Dictionary:
	var out: Dictionary = {}
	out[Phase.DINNERTIME] = [SettlementRegistryClass.Point.ENTER]
	out[Phase.MARKETING] = [SettlementRegistryClass.Point.ENTER]
	out[Phase.CLEANUP] = [SettlementRegistryClass.Point.ENTER]
	return out

func _build_default_settlement_triggers_on_exit() -> Dictionary:
	var out: Dictionary = {}
	out[Phase.PAYDAY] = [SettlementRegistryClass.Point.EXIT]
	return out

func set_settlement_triggers_on_enter(phase: int, points: Array) -> Result:
	return _set_settlement_triggers(phase, "enter", points)

func set_settlement_triggers_on_exit(phase: int, points: Array) -> Result:
	return _set_settlement_triggers(phase, "exit", points)

func _set_settlement_triggers(phase: int, timing: String, points: Array) -> Result:
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
			_settlement_triggers_on_enter.erase(phase)
		else:
			_settlement_triggers_on_enter[phase] = out
		return Result.success()
	if timing == "exit":
		if out.is_empty():
			_settlement_triggers_on_exit.erase(phase)
		else:
			_settlement_triggers_on_exit[phase] = out
		return Result.success()
	return Result.failure("未知 settlement_triggers timing: %s" % timing)

func _run_settlement_triggers(timing: String, phase: int, state: GameState) -> Result:
	if _settlement_registry == null:
		return Result.failure("SettlementRegistry 未设置")
	if state == null:
		return Result.failure("Settlement triggers: state 为空")

	var points: Array = []
	if timing == "enter":
		if _settlement_triggers_on_enter.has(phase):
			points = _settlement_triggers_on_enter.get(phase, [])
	elif timing == "exit":
		if _settlement_triggers_on_exit.has(phase):
			points = _settlement_triggers_on_exit.get(phase, [])
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
		var r: Result = _settlement_registry.run(phase, point, state, self)
		if not r.ok:
			return r
		warnings.append_array(r.warnings)
	return Result.success().with_warnings(warnings)

func _build_phase_order_names(order_enums: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for i in range(order_enums.size()):
		var p: int = int(order_enums[i])
		out.append(str(PHASE_NAMES.get(p, "")))
	return out

func set_phase_order(order_names: Array) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("phase_order 类型错误（期望 Array）")
	if order_names.is_empty():
		return Result.failure("phase_order 不能为空")

	var out_enums: Array[int] = []
	var out_names: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("phase_order[%d] 类型错误（期望 String）" % i)
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("phase_order[%d] 不能为空" % i)
		if seen.has(name):
			return Result.failure("phase_order 重复: %s" % name)
		var p_enum := get_phase_enum(name)
		if p_enum == -1:
			return Result.failure("phase_order[%d] 未知阶段: %s" % [i, name])
		if p_enum == Phase.SETUP or p_enum == Phase.GAME_OVER:
			return Result.failure("phase_order 不允许包含 Setup/GameOver: %s" % name)
		seen[name] = true
		out_enums.append(p_enum)
		out_names.append(name)

	# 约束：仅允许对基础阶段顺序（PHASE_ORDER）做重排，不支持添加/删除阶段（保持 core 默认阶段集合）
	if out_enums.size() != PHASE_ORDER.size():
		return Result.failure("phase_order 长度必须为 %d，实际: %d" % [PHASE_ORDER.size(), out_enums.size()])
	for base_enum in PHASE_ORDER:
		var base_name: String = str(PHASE_NAMES[base_enum])
		if not seen.has(base_name):
			return Result.failure("phase_order 缺少基础阶段: %s" % base_name)

	_phase_order_enums = out_enums
	_phase_order_names = out_names
	return Result.success()

func get_phase_order_names() -> Array[String]:
	return _phase_order_names.duplicate()

func _build_default_working_sub_phase_order_names() -> Array[String]:
	var out: Array[String] = []
	for i in range(SUB_PHASE_ORDER.size()):
		var sub_id = SUB_PHASE_ORDER[i]
		out.append(str(SUB_PHASE_NAMES[sub_id]))
	return out

func set_working_sub_phase_order(order_names: Array) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("working_sub_phase_order 类型错误（期望 Array）")
	if order_names.is_empty():
		return Result.failure("working_sub_phase_order 不能为空")

	var out: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("working_sub_phase_order[%d] 类型错误（期望 String）" % i)
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("working_sub_phase_order[%d] 不能为空" % i)
		if seen.has(name):
			return Result.failure("working_sub_phase_order 重复: %s" % name)
		seen[name] = true
		out.append(name)

	# 必须包含所有基础 Working 子阶段（严格模式：避免核心状态机失配）
	for sub_id in SUB_PHASE_ORDER:
		var base_name: String = str(SUB_PHASE_NAMES[sub_id])
		if not seen.has(base_name):
			return Result.failure("working_sub_phase_order 缺少基础子阶段: %s" % base_name)

	_working_sub_phase_order_names = out
	return Result.success()

func get_working_sub_phase_order_names() -> Array[String]:
	return _working_sub_phase_order_names.duplicate()

func set_cleanup_sub_phase_order(order_names: Array) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("cleanup_sub_phase_order 类型错误（期望 Array）")

	var out: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("cleanup_sub_phase_order[%d] 类型错误（期望 String）" % i)
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("cleanup_sub_phase_order[%d] 不能为空" % i)
		if seen.has(name):
			return Result.failure("cleanup_sub_phase_order 重复: %s" % name)
		seen[name] = true
		out.append(name)

	_cleanup_sub_phase_order_names = out
	return Result.success()

func get_cleanup_sub_phase_order_names() -> Array[String]:
	return _cleanup_sub_phase_order_names.duplicate()

func set_phase_sub_phase_order(phase: int, order_names: Array) -> Result:
	if phase == Phase.WORKING:
		return Result.failure("phase_sub_phase_order: Working 请使用 set_working_sub_phase_order")
	if phase == Phase.CLEANUP:
		return Result.failure("phase_sub_phase_order: Cleanup 请使用 set_cleanup_sub_phase_order")
	if phase == Phase.SETUP or phase == Phase.GAME_OVER:
		return Result.failure("phase_sub_phase_order 不允许包含 Setup/GameOver")
	if order_names == null or not (order_names is Array):
		return Result.failure("phase_sub_phase_order[%s] 类型错误（期望 Array）" % str(PHASE_NAMES.get(phase, phase)))

	if order_names.is_empty():
		_phase_sub_phase_orders.erase(phase)
		return Result.success()

	var out: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("phase_sub_phase_order[%s][%d] 类型错误（期望 String）" % [str(PHASE_NAMES.get(phase, phase)), i])
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("phase_sub_phase_order[%s][%d] 不能为空" % [str(PHASE_NAMES.get(phase, phase)), i])
		if seen.has(name):
			return Result.failure("phase_sub_phase_order[%s] 重复: %s" % [str(PHASE_NAMES.get(phase, phase)), name])
		seen[name] = true
		out.append(name)

	_phase_sub_phase_orders[phase] = out
	return Result.success()

func get_phase_sub_phase_order_names(phase: int) -> Array[String]:
	if _phase_sub_phase_orders.has(phase):
		var v = _phase_sub_phase_orders.get(phase, null)
		if v is Array:
			return (v as Array).duplicate()
	return []

func _run_working_sub_phase_hooks(sub_phase_name: String, hook_type: int, state: GameState) -> Result:
	var warnings: Array[String] = []

	# 1) 基础枚举 hooks（若存在）
	var sub_enum := get_sub_phase_enum(sub_phase_name)
	if sub_enum != -1:
		var r1: Result = _hooks.run_sub_phase_hooks(sub_enum, hook_type, state)
		if not r1.ok:
			return r1
		warnings.append_array(r1.warnings)

	# 2) 自定义/按名 hooks（也允许对基础子阶段按名补充）
	var r2: Result = _hooks.run_sub_phase_hooks_by_name(sub_phase_name, hook_type, state)
	if not r2.ok:
		return r2
	warnings.append_array(r2.warnings)
	return Result.success().with_warnings(warnings)

func _run_named_sub_phase_hooks(sub_phase_name: String, hook_type: int, state: GameState) -> Result:
	var r: Result = _hooks.run_sub_phase_hooks_by_name(sub_phase_name, hook_type, state)
	if not r.ok:
		return r
	return Result.success().with_warnings(r.warnings)

func set_marketing_range_calculator(calculator) -> void:
	if calculator == null:
		_marketing_range_calculator = MarketingRangeCalculatorClass.new()
	else:
		_marketing_range_calculator = calculator

func get_marketing_range_calculator():
	return _marketing_range_calculator

func set_settlement_registry(registry) -> void:
	_settlement_registry = registry

func get_settlement_registry():
	return _settlement_registry

func set_effect_registry(registry) -> void:
	_effect_registry = registry

func get_effect_registry():
	return _effect_registry

func validate_required_primary_settlements() -> Result:
	if _settlement_registry == null:
		return Result.failure("SettlementRegistry 未设置")

	var missing: Array[String] = []
	if not _settlement_registry.has_primary(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER):
		missing.append("Dinnertime:enter")
	if not _settlement_registry.has_primary(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT):
		missing.append("Payday:exit")
	if not _settlement_registry.has_primary(Phase.MARKETING, SettlementRegistryClass.Point.ENTER):
		missing.append("Marketing:enter")
	if not _settlement_registry.has_primary(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER):
		missing.append("Cleanup:enter")

	var unscheduled: Array[String] = []
	if not _is_settlement_scheduled(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER):
		unscheduled.append("Dinnertime:enter")
	if not _is_settlement_scheduled(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT):
		unscheduled.append("Payday:exit")
	if not _is_settlement_scheduled(Phase.MARKETING, SettlementRegistryClass.Point.ENTER):
		unscheduled.append("Marketing:enter")
	if not _is_settlement_scheduled(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER):
		unscheduled.append("Cleanup:enter")

	if not missing.is_empty():
		return Result.failure(", ".join(missing))
	if not unscheduled.is_empty():
		return Result.failure("未配置结算触发点: %s" % ", ".join(unscheduled))
	return Result.success()

func _is_settlement_scheduled(phase: int, point: int) -> bool:
	if _settlement_triggers_on_enter.has(phase):
		var a: Array = _settlement_triggers_on_enter.get(phase, [])
		if a.has(point):
			return true
	if _settlement_triggers_on_exit.has(phase):
		var b: Array = _settlement_triggers_on_exit.get(phase, [])
		if b.has(point):
			return true
	return false

func get_marketing_rounds(state: GameState) -> Result:
	var marketing_rounds := 1
	var rs: Dictionary = state.round_state
	if rs.has("marketing_rounds"):
		var mr_val = rs.get("marketing_rounds", 1)
		if mr_val is int:
			marketing_rounds = int(mr_val)
		elif mr_val is float:
			var f: float = float(mr_val)
			if f != floor(f):
				return Result.failure("round_state.marketing_rounds 必须为整数，实际: %s" % str(mr_val))
			marketing_rounds = int(f)
		else:
			return Result.failure("round_state.marketing_rounds 类型错误（期望 int），实际: %s" % str(typeof(mr_val)))
		if marketing_rounds <= 0:
			return Result.failure("round_state.marketing_rounds 必须 > 0，实际: %d" % marketing_rounds)
	return Result.success(marketing_rounds)

# === 阶段推进 ===

# 推进到下一阶段
func advance_phase(state: GameState) -> Result:
	var current_phase := get_phase_enum(state.phase)
	if current_phase == -1:
		return Result.failure("未知当前阶段: %s" % state.phase)
	if current_phase == Phase.GAME_OVER:
		return Result.failure("游戏已结束")

	# 通用：若当前阶段存在待处理的“阶段内必做动作”，禁止推进到下一阶段（由模块注入）。
	if state.round_state is Dictionary and state.round_state.has("pending_phase_actions"):
		var ppa_val = state.round_state.get("pending_phase_actions", null)
		if not (ppa_val is Dictionary):
			return Result.failure("round_state.pending_phase_actions 类型错误（期望 Dictionary）")
		var pending: Dictionary = ppa_val
		var key := str(state.phase)
		if pending.has(key):
			var list_val = pending.get(key, null)
			if not (list_val is Array):
				return Result.failure("round_state.pending_phase_actions[%s] 类型错误（期望 Array）" % key)
			var list: Array = list_val
			if not list.is_empty():
				return Result.failure("当前阶段仍有待处理动作，无法推进：%s" % key)

	var all_warnings: Array[String] = []
	var old_phase := state.phase
	var old_sub_phase := state.sub_phase
	var old_round_number := state.round_number
	var old_map_snapshot: Dictionary = state.map.duplicate(true)
	var old_marketing_instances_snapshot: Array = state.marketing_instances.duplicate(true)
	var old_bank_snapshot: Dictionary = state.bank.duplicate(true)
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)
	var old_players_snapshot: Array = state.players.duplicate(true)

	# 执行当前阶段退出钩子
	var exit_result = _hooks.run_phase_hooks(current_phase, HookType.BEFORE_EXIT, state)
	if not exit_result.ok:
		return exit_result
	all_warnings.append_array(exit_result.warnings)

	# 阶段离开时结算（可由模块覆盖触发点映射）
	var exit_settlements := _run_settlement_triggers("exit", current_phase, state)
	if not exit_settlements.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return exit_settlements
	all_warnings.append_array(exit_settlements.warnings)

	# 确定下一阶段
	var next_phase: int
	if current_phase == Phase.SETUP:
		# Setup -> Restructuring，同时增加回合数
		next_phase = Phase.RESTRUCTURING
		state.round_number += 1
	elif current_phase == Phase.CLEANUP:
		# Cleanup -> Restructuring（新回合）
		next_phase = Phase.RESTRUCTURING
		state.round_number += 1
	else:
		# 找到当前阶段在顺序中的位置
		var current_index := _phase_order_enums.find(current_phase)
		if current_index == -1 or current_index >= _phase_order_enums.size() - 1:
			next_phase = Phase.CLEANUP
		else:
			next_phase = _phase_order_enums[current_index + 1]

			pass

	# 可选：模块可强制指定 next_phase（用于特殊规则，例如第二次破产后立刻终局）。
	# 约定：写入 round_state.force_next_phase = "<PhaseName>"，在本次推进时生效，之后清空。
	if state.round_state is Dictionary and state.round_state.has("force_next_phase"):
		var f_val = state.round_state.get("force_next_phase", null)
		if not (f_val is String):
			return Result.failure("round_state.force_next_phase 类型错误（期望 String）")
		var f_name: String = str(f_val)
		if f_name.is_empty():
			return Result.failure("round_state.force_next_phase 不能为空")
		var f_enum := get_phase_enum(f_name)
		if f_enum == -1:
			return Result.failure("round_state.force_next_phase 未知阶段: %s" % f_name)
		next_phase = f_enum
		state.round_state.erase("force_next_phase")

	# 更新状态
	state.phase = PHASE_NAMES[next_phase]
	state.sub_phase = ""
	if state.round_state is Dictionary:
		state.round_state["prev_phase"] = old_phase
		state.round_state["prev_sub_phase"] = old_sub_phase
		state.round_state["phase_order"] = _phase_order_names.duplicate()
		WorkingFlowClass.reset_sub_phase_passed(state)

	# 执行退出后钩子
	var after_exit_result = _hooks.run_phase_hooks(current_phase, HookType.AFTER_EXIT, state)
	if not after_exit_result.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return after_exit_result
	all_warnings.append_array(after_exit_result.warnings)

	# 执行新阶段进入钩子
	var before_enter_result = _hooks.run_phase_hooks(next_phase, HookType.BEFORE_ENTER, state)
	if not before_enter_result.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return before_enter_result
	all_warnings.append_array(before_enter_result.warnings)

	# Marketing 结算：必须在 BEFORE_ENTER hooks 之后执行，便于模块注入结算轮次数等参数。
	# 阶段进入时结算（BEFORE_ENTER hooks 已执行；可由模块覆盖触发点映射）
	var enter_settlements := _run_settlement_triggers("enter", next_phase, state)
	if not enter_settlements.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return enter_settlements
	all_warnings.append_array(enter_settlements.warnings)

	# Cleanup 阶段：若存在模块注入的子阶段，自动进入第一个子阶段
	if next_phase == Phase.CLEANUP and not _cleanup_sub_phase_order_names.is_empty():
		state.sub_phase = _cleanup_sub_phase_order_names[0]
		if state.round_state is Dictionary:
			state.round_state["cleanup_sub_phase_order"] = _cleanup_sub_phase_order_names.duplicate()
			WorkingFlowClass.reset_sub_phase_passed(state)
		state.current_player_index = 0

		var sub_before_cleanup = _run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
		if not sub_before_cleanup.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_before_cleanup
		all_warnings.append_array(sub_before_cleanup.warnings)

		var sub_after_cleanup = _run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
		if not sub_after_cleanup.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_after_cleanup
		all_warnings.append_array(sub_after_cleanup.warnings)

	# 如果是工作阶段，自动进入第一个子阶段
	if next_phase == Phase.WORKING:
		state.sub_phase = _working_sub_phase_order_names[0]
		state.round_state["working_sub_phase_order"] = _working_sub_phase_order_names.duplicate()

		var sub_before = _run_working_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
		if not sub_before.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_before
		all_warnings.append_array(sub_before.warnings)

		var sub_after = _run_working_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
		if not sub_after.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_after
		all_warnings.append_array(sub_after.warnings)

	# 其它阶段：若模块为该阶段配置了子阶段顺序，则自动进入第一个子阶段
	if next_phase != Phase.WORKING and next_phase != Phase.CLEANUP and _phase_sub_phase_orders.has(next_phase):
		var order_val = _phase_sub_phase_orders.get(next_phase, null)
		if not (order_val is Array):
			return Result.failure("phase_sub_phase_order 内部类型错误: %s" % str(PHASE_NAMES.get(next_phase, next_phase)))
		var order: Array = order_val
		if not order.is_empty():
			state.sub_phase = str(order[0])
			if state.round_state is Dictionary:
				var phase_orders: Dictionary = {}
				if state.round_state.has("phase_sub_phase_orders") and (state.round_state["phase_sub_phase_orders"] is Dictionary):
					phase_orders = state.round_state["phase_sub_phase_orders"]
				phase_orders[state.phase] = order.duplicate()
				state.round_state["phase_sub_phase_orders"] = phase_orders
				WorkingFlowClass.reset_sub_phase_passed(state)
			state.current_player_index = 0

			var sub_before_generic = _run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
			if not sub_before_generic.ok:
				state.phase = old_phase
				state.sub_phase = old_sub_phase
				state.round_number = old_round_number
				state.map = old_map_snapshot
				state.marketing_instances = old_marketing_instances_snapshot
				state.bank = old_bank_snapshot
				state.round_state = old_round_state_snapshot
				state.players = old_players_snapshot
				return sub_before_generic
			all_warnings.append_array(sub_before_generic.warnings)

			var sub_after_generic = _run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
			if not sub_after_generic.ok:
				state.phase = old_phase
				state.sub_phase = old_sub_phase
				state.round_number = old_round_number
				state.map = old_map_snapshot
				state.marketing_instances = old_marketing_instances_snapshot
				state.bank = old_bank_snapshot
				state.round_state = old_round_state_snapshot
				state.players = old_players_snapshot
				return sub_after_generic
			all_warnings.append_array(sub_after_generic.warnings)

	# 执行进入后钩子
	var after_enter_result = _hooks.run_phase_hooks(next_phase, HookType.AFTER_ENTER, state)
	if not after_enter_result.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return after_enter_result
	all_warnings.append_array(after_enter_result.warnings)

	GameLog.info("PhaseManager", "阶段推进: %s -> %s (回合 %d)" % [
		old_phase, state.phase, state.round_number
	])

	return Result.success({
		"old_phase": old_phase,
		"new_phase": state.phase,
		"round_number": state.round_number
	}).with_warnings(all_warnings)

# 推进子阶段（Working 或模块注入的 Cleanup 子阶段）
func advance_sub_phase(state: GameState) -> Result:
	if state.phase == "Working":
		return _advance_working_sub_phase(state)
	if state.phase == "Cleanup":
		return _advance_cleanup_sub_phase(state)
	var phase_enum := get_phase_enum(state.phase)
	if phase_enum == -1:
		return Result.failure("未知当前阶段: %s" % state.phase)
	var order := get_phase_sub_phase_order_names(phase_enum)
	if order.is_empty():
		return Result.failure("当前阶段不支持推进子阶段: %s" % state.phase)
	return _advance_generic_sub_phase(state, order)
	return Result.failure("当前阶段不支持推进子阶段: %s" % state.phase)

func _advance_generic_sub_phase(state: GameState, order_names: Array[String]) -> Result:
	var current_name: String = state.sub_phase
	var current_index := order_names.find(current_name)
	if current_index == -1:
		return Result.failure("未知当前子阶段: %s" % current_name)

	var all_warnings: Array[String] = []
	var old_sub := state.sub_phase
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)

	var before_exit = _run_named_sub_phase_hooks(current_name, HookType.BEFORE_EXIT, state)
	if not before_exit.ok:
		return before_exit
	all_warnings.append_array(before_exit.warnings)

	if current_index >= order_names.size() - 1:
		var after_exit_last = _run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
		if not after_exit_last.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return after_exit_last
		all_warnings.append_array(after_exit_last.warnings)

		var adv := advance_phase(state)
		if adv.ok:
			adv.with_warnings(all_warnings)
		return adv

	state.sub_phase = str(order_names[current_index + 1])
	WorkingFlowClass.reset_sub_phase_passed(state)
	var phase_orders: Dictionary = {}
	if state.round_state.has("phase_sub_phase_orders") and (state.round_state["phase_sub_phase_orders"] is Dictionary):
		phase_orders = state.round_state["phase_sub_phase_orders"]
	phase_orders[state.phase] = order_names.duplicate()
	state.round_state["phase_sub_phase_orders"] = phase_orders

	var after_exit = _run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
	if not after_exit.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return after_exit
	all_warnings.append_array(after_exit.warnings)

	var sub_before_enter = _run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
	if not sub_before_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_before_enter
	all_warnings.append_array(sub_before_enter.warnings)

	var sub_after_enter = _run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
	if not sub_after_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_after_enter
	all_warnings.append_array(sub_after_enter.warnings)

	GameLog.info("PhaseManager", "子阶段推进: %s -> %s" % [old_sub, state.sub_phase])
	return Result.success({
		"old_sub_phase": old_sub,
		"new_sub_phase": state.sub_phase
	}).with_warnings(all_warnings)

func _advance_working_sub_phase(state: GameState) -> Result:
	if _working_sub_phase_order_names.is_empty():
		return Result.failure("working_sub_phase_order 未初始化")
	var current_name: String = state.sub_phase
	var current_index := _working_sub_phase_order_names.find(current_name)
	if current_index == -1:
		return Result.failure("未知当前子阶段: %s" % current_name)

	var all_warnings: Array[String] = []
	var old_sub := state.sub_phase
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)

	# 执行当前子阶段退出钩子
	var before_exit = _run_working_sub_phase_hooks(current_name, HookType.BEFORE_EXIT, state)
	if not before_exit.ok:
		return before_exit
	all_warnings.append_array(before_exit.warnings)

	# 确定下一子阶段
	if current_index >= _working_sub_phase_order_names.size() - 1:
		# 最后一个子阶段：结束当前玩家的 Working 回合 -> 下一位玩家从第一个子阶段开始；
		# 若所有玩家都已确认结束，则离开 Working 进入下一主阶段。
		var after_exit_last = _run_working_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
		if not after_exit_last.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return after_exit_last
		all_warnings.append_array(after_exit_last.warnings)

		if not (state.round_state is Dictionary):
			return Result.failure("Working: round_state 类型错误（期望 Dictionary）")
		if not state.round_state.has("sub_phase_passed"):
			return Result.failure("Working: round_state.sub_phase_passed 缺失")
		var passed_val = state.round_state["sub_phase_passed"]
		if not (passed_val is Dictionary):
			return Result.failure("Working: round_state.sub_phase_passed 类型错误（期望 Dictionary）")
		var passed: Dictionary = passed_val

		var all_passed := true
		for pid in range(state.players.size()):
			assert(passed.has(pid) and (passed[pid] is bool), "Working: sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % pid)
			if not bool(passed[pid]):
				all_passed = false
				break

		if all_passed:
			var adv := advance_phase(state)
			if adv.ok:
				adv.with_warnings(all_warnings)
			return adv

		var size := state.turn_order.size()
		if size <= 0:
			return Result.failure("turn_order 为空")

		var next_idx := -1
		for offset in range(1, size + 1):
			var idx := state.current_player_index + offset
			if idx >= size:
				idx = idx % size
			var pid_val = state.turn_order[idx]
			if not (pid_val is int):
				continue
			var pid2: int = int(pid_val)
			if not bool(passed.get(pid2, false)):
				next_idx = idx
				break

		if next_idx == -1:
			return Result.failure("Working: 未找到下一位未确认结束的玩家（sub_phase_passed 可能损坏）")

		state.current_player_index = next_idx
		state.sub_phase = _working_sub_phase_order_names[0]
		WorkingFlowClass.reset_working_sub_phase_state(state)
		state.round_state["working_sub_phase_order"] = _working_sub_phase_order_names.duplicate()

		var sub_before_enter0 = _run_working_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
		if not sub_before_enter0.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return sub_before_enter0
		all_warnings.append_array(sub_before_enter0.warnings)

		var sub_after_enter0 = _run_working_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
		if not sub_after_enter0.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return sub_after_enter0
		all_warnings.append_array(sub_after_enter0.warnings)

		GameLog.info("PhaseManager", "Working 回合切换：进入玩家 %d，从子阶段 %s 开始" % [
			state.get_current_player_id(),
			state.sub_phase
		])

		return Result.success({
			"old_sub_phase": old_sub,
			"new_sub_phase": state.sub_phase
		}).with_warnings(all_warnings)

	state.sub_phase = _working_sub_phase_order_names[current_index + 1]
	WorkingFlowClass.reset_working_sub_phase_state(state)
	state.round_state["working_sub_phase_order"] = _working_sub_phase_order_names.duplicate()

	# 执行退出后钩子
	var after_exit = _run_working_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
	if not after_exit.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return after_exit
	all_warnings.append_array(after_exit.warnings)

	# 执行新子阶段进入钩子
	var sub_before_enter = _run_working_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
	if not sub_before_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_before_enter
	all_warnings.append_array(sub_before_enter.warnings)

	var sub_after_enter = _run_working_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
	if not sub_after_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_after_enter
	all_warnings.append_array(sub_after_enter.warnings)

	GameLog.info("PhaseManager", "子阶段推进: %s -> %s" % [old_sub, state.sub_phase])

	return Result.success({
		"old_sub_phase": old_sub,
		"new_sub_phase": state.sub_phase
	}).with_warnings(all_warnings)

func _advance_cleanup_sub_phase(state: GameState) -> Result:
	if _cleanup_sub_phase_order_names.is_empty():
		return Result.failure("cleanup_sub_phase_order 未初始化")
	var current_name: String = state.sub_phase
	var current_index := _cleanup_sub_phase_order_names.find(current_name)
	if current_index == -1:
		return Result.failure("未知当前子阶段: %s" % current_name)

	var all_warnings: Array[String] = []
	var old_sub := state.sub_phase
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)

	var before_exit = _run_named_sub_phase_hooks(current_name, HookType.BEFORE_EXIT, state)
	if not before_exit.ok:
		return before_exit
	all_warnings.append_array(before_exit.warnings)

	if current_index >= _cleanup_sub_phase_order_names.size() - 1:
		var after_exit_last = _run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
		if not after_exit_last.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return after_exit_last
		all_warnings.append_array(after_exit_last.warnings)

		var adv := advance_phase(state)
		if adv.ok:
			adv.with_warnings(all_warnings)
		return adv

	state.sub_phase = _cleanup_sub_phase_order_names[current_index + 1]
	if state.round_state is Dictionary:
		state.round_state["cleanup_sub_phase_order"] = _cleanup_sub_phase_order_names.duplicate()
		WorkingFlowClass.reset_sub_phase_passed(state)
	state.current_player_index = 0

	var after_exit = _run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
	if not after_exit.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return after_exit
	all_warnings.append_array(after_exit.warnings)

	var sub_before_enter = _run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
	if not sub_before_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_before_enter
	all_warnings.append_array(sub_before_enter.warnings)

	var sub_after_enter = _run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
	if not sub_after_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_after_enter
	all_warnings.append_array(sub_after_enter.warnings)

	GameLog.info("PhaseManager", "子阶段推进(Cleanup): %s -> %s" % [old_sub, state.sub_phase])

	return Result.success({
		"old_sub_phase": old_sub,
		"new_sub_phase": state.sub_phase
	}).with_warnings(all_warnings)

# === 钩子管理 ===

# 注册阶段钩子
func register_phase_hook(
	phase: int,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source: String = ""
) -> void:
	_hooks.register_phase_hook(phase, hook_type, callback, priority, source)

# 注册子阶段钩子
func register_sub_phase_hook(
	sub_phase: int,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source: String = ""
) -> void:
	_hooks.register_sub_phase_hook(sub_phase, hook_type, callback, priority, source)

func register_sub_phase_hook_by_name(
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source: String = ""
) -> void:
	_hooks.register_sub_phase_hook_by_name(sub_phase_name, hook_type, callback, priority, source)

# 取消钩子
func unregister_hook(phase: int, hook_type: int, callback: Callable) -> bool:
	return _hooks.unregister_hook(phase, hook_type, callback)

# === 查询方法 ===

# 获取阶段序号（用于游戏内时间戳/确定性日志）
# 约定：
# - Setup = 0
# - 其余按 PHASE_ORDER 顺序从 1 开始
static func get_phase_index(phase_name: String) -> int:
	return DefsClass.get_phase_index(phase_name)

# 从字符串获取阶段枚举
static func get_phase_enum(phase_name: String) -> int:
	return DefsClass.get_phase_enum(phase_name)

# 从字符串获取子阶段枚举
static func get_sub_phase_enum(sub_phase_name: String) -> int:
	return DefsClass.get_sub_phase_enum(sub_phase_name)

# 获取阶段名称
static func get_phase_name(phase: int) -> String:
	return DefsClass.get_phase_name(phase)

# 获取子阶段名称
static func get_sub_phase_name(sub_phase: int) -> String:
	return DefsClass.get_sub_phase_name(sub_phase)

# 检查是否在工作阶段
static func is_working_phase(state: GameState) -> bool:
	return DefsClass.is_working_phase(state)

# 获取当前子阶段索引
static func get_sub_phase_index(state: GameState) -> int:
	return DefsClass.get_sub_phase_index(state)

# 计算确定性的“游戏内时间戳”
# 对齐 docs/design.md（round * 1000 + phase_index * 100 + sub_phase_index）
static func compute_timestamp(state: GameState) -> int:
	return DefsClass.compute_timestamp(state)

# 获取阶段进度（用于显示）
static func get_phase_progress(state: GameState) -> Dictionary:
	return DefsClass.get_phase_progress(state)

# === 调试 ===

func dump() -> String:
	if _hooks == null:
		return "=== PhaseManager ===\n[no hooks]\n"
	return _hooks.dump()
