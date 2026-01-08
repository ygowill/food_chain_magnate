# 阶段管理器
# 管理游戏七阶段和工作子阶段的状态机，支持钩子系统
class_name PhaseManager
extends RefCounted

# === 常量定义 ===

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const HooksClass = preload("res://core/engine/phase_manager/hooks.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")
const AdvancementClass = preload("res://core/engine/phase_manager/advancement.gd")
const OrderConfigClass = preload("res://core/engine/phase_manager/order_config.gd")
const SettlementTriggersClass = preload("res://core/engine/phase_manager/settlement_triggers.gd")

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
	return SettlementTriggersClass.build_default_settlement_triggers_on_enter()

func _build_default_settlement_triggers_on_exit() -> Dictionary:
	return SettlementTriggersClass.build_default_settlement_triggers_on_exit()

func set_settlement_triggers_on_enter(phase: int, points: Array) -> Result:
	return _set_settlement_triggers(phase, "enter", points)

func set_settlement_triggers_on_exit(phase: int, points: Array) -> Result:
	return _set_settlement_triggers(phase, "exit", points)

func _set_settlement_triggers(phase: int, timing: String, points: Array) -> Result:
	return SettlementTriggersClass.set_settlement_triggers(self, phase, timing, points)

func _run_settlement_triggers(timing: String, phase: int, state: GameState) -> Result:
	return SettlementTriggersClass.run_settlement_triggers(self, timing, phase, state)

func _build_phase_order_names(order_enums: Array[int]) -> Array[String]:
	return OrderConfigClass.build_phase_order_names(order_enums)

func set_phase_order(order_names: Array) -> Result:
	return OrderConfigClass.set_phase_order(self, order_names)

func get_phase_order_names() -> Array[String]:
	return _phase_order_names.duplicate()

func _build_default_working_sub_phase_order_names() -> Array[String]:
	return OrderConfigClass.build_default_working_sub_phase_order_names()

func set_working_sub_phase_order(order_names: Array) -> Result:
	return OrderConfigClass.set_working_sub_phase_order(self, order_names)

func get_working_sub_phase_order_names() -> Array[String]:
	return _working_sub_phase_order_names.duplicate()

func set_cleanup_sub_phase_order(order_names: Array) -> Result:
	return OrderConfigClass.set_cleanup_sub_phase_order(self, order_names)

func get_cleanup_sub_phase_order_names() -> Array[String]:
	return _cleanup_sub_phase_order_names.duplicate()

func set_phase_sub_phase_order(phase: int, order_names: Array) -> Result:
	return OrderConfigClass.set_phase_sub_phase_order(self, phase, order_names)

func get_phase_sub_phase_order_names(phase: int) -> Array[String]:
	return OrderConfigClass.get_phase_sub_phase_order_names(self, phase)

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
	return SettlementTriggersClass.validate_required_primary_settlements(self)

func _is_settlement_scheduled(phase: int, point: int) -> bool:
	return SettlementTriggersClass.is_settlement_scheduled(self, phase, point)

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
	return AdvancementClass.advance_phase(self, state)

# 推进子阶段（Working 或模块注入的 Cleanup 子阶段）
func advance_sub_phase(state: GameState) -> Result:
	return AdvancementClass.advance_sub_phase(self, state)

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
