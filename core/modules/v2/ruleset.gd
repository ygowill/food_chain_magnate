# 模块系统 V2：Ruleset（每局由启用模块注册得到的规则集合）
class_name RulesetV2
extends RefCounted

const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const MapGenerationRegistryClass = preload("res://core/rules/map_generation_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var settlement_registry = SettlementRegistryClass.new()
var effect_registry = EffectRegistryClass.new()
var milestone_effect_registry = MilestoneEffectRegistryClass.new()
var map_generation_registry = MapGenerationRegistryClass.new()
var employee_patches: Array[Dictionary] = []  # [{target_id, patch, source}]
var milestone_patches: Array[Dictionary] = []  # [{target_id, patch, source}]
var phase_hooks: Array[Dictionary] = []  # [{phase, hook_type, callback, priority, source}]
var sub_phase_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var named_sub_phase_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var action_executors: Array = []  # Array[ActionExecutor]
var action_validators: Array[Dictionary] = []  # [{action_id, validator_id, callback, priority, source}]
var global_action_validators: Array[Dictionary] = []  # [{validator_id, callback, priority, source}]
var action_availability_overrides: Array[Dictionary] = []  # [{action_id, points, priority, source}]
var marketing_type_registrations: Array[Dictionary] = []  # [{type_id, requires_edge, range_handler, source}]
var marketing_initiation_providers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var bankruptcy_handlers: Array[Dictionary] = []  # [{kind, callback, source}]
var dinnertime_demand_providers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var dinnertime_route_purchase_providers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var employee_pool_patches: Array[Dictionary] = []  # [{id, employee_id, delta, source}]
var working_sub_phase_insertions: Array[Dictionary] = []  # [{sub_phase, after, before, priority, source}]
var working_sub_phase_name_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var cleanup_sub_phase_insertions: Array[Dictionary] = []  # [{sub_phase, after, before, priority, source}]
var cleanup_sub_phase_name_hooks: Array[Dictionary] = []  # [{sub_phase, hook_type, callback, priority, source}]
var phase_order_override = null  # {order:Array[String], priority:int, source:String}
var working_sub_phase_order_override = null  # {order:Array[String], priority:int, source:String}
var cleanup_sub_phase_order_override = null  # {order:Array[String], priority:int, source:String}
var settlement_triggers_override: Array[Dictionary] = []  # [{phase, timing, points, source}]
var phase_sub_phase_order_overrides: Array[Dictionary] = []  # [{phase, order, priority, source}]
var state_initializers: Array[Dictionary] = []  # [{id, callback, priority, source}]
var _entry_instances: Array = []

func retain_entry_instance(inst) -> void:
	if inst == null:
		return
	_entry_instances.append(inst)

func register_employee_patch(target_employee_id: String, patch: Dictionary, source_module_id: String = "") -> Result:
	if target_employee_id.is_empty():
		return Result.failure("RulesetV2: target_employee_id 不能为空")
	if patch == null or not (patch is Dictionary):
		return Result.failure("RulesetV2: patch 类型错误（期望 Dictionary）")
	employee_patches.append({
		"target_id": target_employee_id,
		"patch": patch.duplicate(true),
		"source": source_module_id,
	})
	return Result.success()

func register_milestone_patch(target_milestone_id: String, patch: Dictionary, source_module_id: String = "") -> Result:
	if target_milestone_id.is_empty():
		return Result.failure("RulesetV2: target_milestone_id 不能为空")
	if patch == null or not (patch is Dictionary):
		return Result.failure("RulesetV2: milestone patch 类型错误（期望 Dictionary）")
	milestone_patches.append({
		"target_id": target_milestone_id,
		"patch": patch.duplicate(true),
		"source": source_module_id,
	})
	return Result.success()

func apply_employee_patches(catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if employee_patches.is_empty():
		return Result.success()
	if not (catalog.employees is Dictionary):
		return Result.failure("RulesetV2: catalog.employees 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []
	for i in range(employee_patches.size()):
		var item_val = employee_patches[i]
		if not (item_val is Dictionary):
			return Result.failure("RulesetV2: employee_patches[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var target_val = item.get("target_id", null)
		if not (target_val is String):
			return Result.failure("RulesetV2: employee_patches[%d].target_id 类型错误（期望 String）" % i)
		var target_id: String = str(target_val)
		if target_id.is_empty():
			return Result.failure("RulesetV2: employee_patches[%d].target_id 不能为空" % i)
		if not catalog.employees.has(target_id):
			return Result.failure("RulesetV2: employee patch 目标员工不存在: %s" % target_id)

		var def_val = catalog.employees.get(target_id, null)
		if def_val == null or not (def_val is EmployeeDefClass):
			return Result.failure("RulesetV2: catalog.employees[%s] 类型错误（期望 EmployeeDef）" % target_id)
		var def: EmployeeDef = def_val

		var patch_val = item.get("patch", null)
		if not (patch_val is Dictionary):
			return Result.failure("RulesetV2: employee_patches[%d].patch 类型错误（期望 Dictionary）" % i)
		var patch: Dictionary = patch_val

		var apply_r := _apply_employee_patch(def, patch, target_id)
		if not apply_r.ok:
			return apply_r
		warnings.append_array(apply_r.warnings)

	return Result.success().with_warnings(warnings)

func apply_milestone_patches(catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if milestone_patches.is_empty():
		return Result.success()
	if not (catalog.milestones is Dictionary):
		return Result.failure("RulesetV2: catalog.milestones 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []
	for i in range(milestone_patches.size()):
		var item_val = milestone_patches[i]
		if not (item_val is Dictionary):
			return Result.failure("RulesetV2: milestone_patches[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var target_val = item.get("target_id", null)
		if not (target_val is String):
			return Result.failure("RulesetV2: milestone_patches[%d].target_id 类型错误（期望 String）" % i)
		var target_id: String = str(target_val)
		if target_id.is_empty():
			return Result.failure("RulesetV2: milestone_patches[%d].target_id 不能为空" % i)
		if not catalog.milestones.has(target_id):
			return Result.failure("RulesetV2: milestone patch 目标里程碑不存在: %s" % target_id)

		var def_val = catalog.milestones.get(target_id, null)
		if def_val == null or not (def_val is MilestoneDefClass):
			return Result.failure("RulesetV2: catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % target_id)
		var def: MilestoneDef = def_val

		var patch_val = item.get("patch", null)
		if not (patch_val is Dictionary):
			return Result.failure("RulesetV2: milestone_patches[%d].patch 类型错误（期望 Dictionary）" % i)
		var patch: Dictionary = patch_val

		var apply_r := _apply_milestone_patch(def, patch, target_id)
		if not apply_r.ok:
			return apply_r
		warnings.append_array(apply_r.warnings)

	return Result.success().with_warnings(warnings)

static func _apply_employee_patch(def: EmployeeDef, patch: Dictionary, target_id: String) -> Result:
	assert(def != null, "RulesetV2._apply_employee_patch: def 为空")
	assert(not target_id.is_empty(), "RulesetV2._apply_employee_patch: target_id 不能为空")

	# 受控 patch：当前仅支持向数组字段追加（去重）
	# - add_train_to: Array[String]
	if patch.has("add_train_to"):
		var add_val = patch.get("add_train_to", null)
		if not (add_val is Array):
			return Result.failure("RulesetV2: employee patch %s.add_train_to 类型错误（期望 Array[String]）" % target_id)
		var add_any: Array = add_val
		for j in range(add_any.size()):
			var v = add_any[j]
			if not (v is String):
				return Result.failure("RulesetV2: employee patch %s.add_train_to[%d] 类型错误（期望 String）" % [target_id, j])
			var to_id: String = str(v)
			if to_id.is_empty():
				return Result.failure("RulesetV2: employee patch %s.add_train_to[%d] 不能为空" % [target_id, j])
			if not def.train_to.has(to_id):
				def.train_to.append(to_id)

	return Result.success()

static func _apply_milestone_patch(def: MilestoneDef, patch: Dictionary, target_id: String) -> Result:
	assert(def != null, "RulesetV2._apply_milestone_patch: def 为空")
	assert(not target_id.is_empty(), "RulesetV2._apply_milestone_patch: target_id 不能为空")

	# 受控 patch：
	# - set_expires_at: int | null
	if patch.has("set_expires_at"):
		var v = patch.get("set_expires_at", null)
		if v == null:
			def.expires_at = null
		else:
			if not (v is int):
				return Result.failure("RulesetV2: milestone patch %s.set_expires_at 类型错误（期望 int|null）" % target_id)
			var exp: int = int(v)
			if exp < 0:
				return Result.failure("RulesetV2: milestone patch %s.set_expires_at 必须 >= 0，实际: %d" % [target_id, exp])
			def.expires_at = exp

	return Result.success()

func register_phase_hook(phase: int, hook_type: int, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if not callback.is_valid():
		return Result.failure("RulesetV2: phase hook callback 无效")
	if phase < 0 or phase > PhaseDefsClass.Phase.GAME_OVER:
		return Result.failure("RulesetV2: phase hook phase 越界: %d" % phase)
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: phase hook hook_type 越界: %d" % hook_type)
	phase_hooks.append({
		"phase": phase,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_sub_phase_hook(sub_phase: int, hook_type: int, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if not callback.is_valid():
		return Result.failure("RulesetV2: sub_phase hook callback 无效")
	if sub_phase < 0 or sub_phase > PhaseDefsClass.WorkingSubPhase.PLACE_RESTAURANTS:
		return Result.failure("RulesetV2: sub_phase hook sub_phase 越界: %d" % sub_phase)
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: sub_phase hook hook_type 越界: %d" % hook_type)
	sub_phase_hooks.append({
		"sub_phase": sub_phase,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_named_sub_phase_hook(sub_phase_name: String, hook_type: int, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: named_sub_phase_hook sub_phase_name 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: named_sub_phase_hook callback 无效")
	named_sub_phase_hooks.append({
		"sub_phase": sub_phase_name,
		"hook_type": hook_type,
		"callback": callback,
		"priority": int(priority),
		"source": source_module_id,
	})
	return Result.success()

func register_working_sub_phase_insertion(
	sub_phase_name: String,
	after_sub_phase_name: String,
	before_sub_phase_name: String,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")
	if after_sub_phase_name.is_empty() and before_sub_phase_name.is_empty():
		return Result.failure("RulesetV2: after/before 不能同时为空")

	for item_val in working_sub_phase_insertions:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("sub_phase", "")) == sub_phase_name:
			return Result.failure("RulesetV2: working sub_phase 重复插入: %s (module:%s)" % [sub_phase_name, source_module_id])

	working_sub_phase_insertions.append({
		"sub_phase": sub_phase_name,
		"after": after_sub_phase_name,
		"before": before_sub_phase_name,
		"priority": priority,
		"source": source_module_id,
	})
	working_sub_phase_insertions.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

func register_working_sub_phase_hook(
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: sub_phase hook callback 无效")
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: sub_phase hook hook_type 越界: %d" % hook_type)

	working_sub_phase_name_hooks.append({
		"sub_phase": sub_phase_name,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	working_sub_phase_name_hooks.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

func register_cleanup_sub_phase_insertion(
	sub_phase_name: String,
	after_sub_phase_name: String,
	before_sub_phase_name: String,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")

	for item_val in cleanup_sub_phase_insertions:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("sub_phase", "")) == sub_phase_name:
			return Result.failure("RulesetV2: cleanup sub_phase 重复插入: %s (module:%s)" % [sub_phase_name, source_module_id])

	cleanup_sub_phase_insertions.append({
		"sub_phase": sub_phase_name,
		"after": after_sub_phase_name,
		"before": before_sub_phase_name,
		"priority": priority,
		"source": source_module_id,
	})
	cleanup_sub_phase_insertions.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

func register_cleanup_sub_phase_hook(
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: sub_phase hook callback 无效")
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: sub_phase hook hook_type 越界: %d" % hook_type)

	cleanup_sub_phase_name_hooks.append({
		"sub_phase": sub_phase_name,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	cleanup_sub_phase_name_hooks.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

func register_action_executor(executor, source_module_id: String = "") -> Result:
	# 允许模块注册自定义 ActionExecutor（Strict Mode：重复 action_id 直接失败）。
	if executor == null:
		return Result.failure("RulesetV2: executor 为空")
	if not (executor is ActionExecutor):
		return Result.failure("RulesetV2: executor 类型错误（期望 ActionExecutor）")
	if executor.action_id.is_empty():
		return Result.failure("RulesetV2: executor.action_id 不能为空 (%s)" % source_module_id)
	for existing in action_executors:
		if existing is ActionExecutor and str(existing.action_id) == str(executor.action_id):
			return Result.failure("RulesetV2: action executor 重复注册: %s (module:%s)" % [executor.action_id, source_module_id])
	action_executors.append(executor)
	return Result.success()

func register_marketing_type(type_id: String, config: Dictionary, range_handler: Callable, source_module_id: String = "") -> Result:
	if type_id.is_empty():
		return Result.failure("RulesetV2: marketing type_id 不能为空")
	if config == null or not (config is Dictionary):
		return Result.failure("RulesetV2: marketing config 类型错误（期望 Dictionary）")
	if not range_handler.is_valid():
		return Result.failure("RulesetV2: marketing range_handler 无效: %s" % type_id)

	for item_val in marketing_type_registrations:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("type_id", "")) == type_id:
			return Result.failure("RulesetV2: marketing type 重复注册: %s (module:%s)" % [type_id, source_module_id])

	var requires_edge := false
	if config.has("requires_edge"):
		var v = config.get("requires_edge", false)
		if not (v is bool):
			return Result.failure("RulesetV2: marketing config.requires_edge 类型错误（期望 bool）: %s" % type_id)
		requires_edge = bool(v)

	marketing_type_registrations.append({
		"type_id": type_id,
		"requires_edge": requires_edge,
		"range_handler": range_handler,
		"source": source_module_id,
	})
	return Result.success()

func register_action_validator(action_id: String, validator_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if action_id.is_empty():
		return Result.failure("RulesetV2: action_id 不能为空")
	if validator_id.is_empty():
		return Result.failure("RulesetV2: validator_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: action validator callback 无效")
	for item_val in action_validators:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("action_id", "")) == action_id and str(item.get("validator_id", "")) == validator_id:
			return Result.failure("RulesetV2: action validator 重复注册: %s/%s (module:%s)" % [action_id, validator_id, source_module_id])
	action_validators.append({
		"action_id": action_id,
		"validator_id": validator_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_global_action_validator(validator_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if validator_id.is_empty():
		return Result.failure("RulesetV2: validator_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: global action validator callback 无效")
	for item_val in global_action_validators:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("validator_id", "")) == validator_id:
			return Result.failure("RulesetV2: global action validator 重复注册: %s (module:%s)" % [validator_id, source_module_id])
	global_action_validators.append({
		"validator_id": validator_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_action_availability_override(action_id: String, points: Array, priority: int = 100, source_module_id: String = "") -> Result:
	if action_id.is_empty():
		return Result.failure("RulesetV2: action_availability_override action_id 不能为空")
	if points == null or not (points is Array):
		return Result.failure("RulesetV2: action_availability_override points 类型错误（期望 Array[Dictionary]）")

	for i in range(points.size()):
		var pv = points[i]
		if not (pv is Dictionary):
			return Result.failure("RulesetV2: action_availability_override points[%d] 类型错误（期望 Dictionary）" % i)
		var p: Dictionary = pv
		var phase_name: String = str(p.get("phase", ""))
		if phase_name.is_empty():
			return Result.failure("RulesetV2: action_availability_override points[%d].phase 不能为空" % i)
		if not p.has("sub_phase"):
			return Result.failure("RulesetV2: action_availability_override points[%d] 缺少字段: sub_phase" % i)
		var sub_name: String = str(p.get("sub_phase", ""))
		if sub_name.is_empty() and str(p.get("sub_phase", "")) != "":
			return Result.failure("RulesetV2: action_availability_override points[%d].sub_phase 类型错误（期望 String）" % i)

	action_availability_overrides.append({
		"action_id": action_id,
		"points": points.duplicate(true),
		"priority": int(priority),
		"source": source_module_id,
	})
	action_availability_overrides.sort_custom(func(a, b) -> bool:
		var pa: int = int(a.get("priority", 100))
		var pb: int = int(b.get("priority", 100))
		if pa != pb:
			return pa > pb
		var sa: String = str(a.get("source", ""))
		var sb: String = str(b.get("source", ""))
		return sa < sb
	)
	return Result.success()

func register_marketing_initiation_provider(provider_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if provider_id.is_empty():
		return Result.failure("RulesetV2: marketing initiation provider_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: marketing initiation provider callback 无效: %s" % provider_id)
	for item_val in marketing_initiation_providers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == provider_id:
			return Result.failure("RulesetV2: marketing initiation provider 重复注册: %s (module:%s)" % [provider_id, source_module_id])
	marketing_initiation_providers.append({
		"id": provider_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	marketing_initiation_providers.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.id) != str(b.id):
			return str(a.id) < str(b.id)
		return str(a.source) < str(b.source)
	)
	return Result.success()

func register_bankruptcy_handler(kind: String, callback: Callable, source_module_id: String = "") -> Result:
	if kind.is_empty():
		return Result.failure("RulesetV2: bankruptcy kind 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: bankruptcy handler callback 无效: %s" % kind)
	for item_val in bankruptcy_handlers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("kind", "")) == kind:
			return Result.failure("RulesetV2: bankruptcy handler 重复注册: %s (module:%s)" % [kind, source_module_id])
	bankruptcy_handlers.append({
		"kind": kind,
		"callback": callback,
		"source": source_module_id,
	})
	return Result.success()

func register_dinnertime_demand_provider(provider_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if provider_id.is_empty():
		return Result.failure("RulesetV2: dinnertime demand provider_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: dinnertime demand provider callback 无效: %s" % provider_id)
	for item_val in dinnertime_demand_providers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == provider_id:
			return Result.failure("RulesetV2: dinnertime demand provider 重复注册: %s (module:%s)" % [provider_id, source_module_id])
	dinnertime_demand_providers.append({
		"id": provider_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_dinnertime_route_purchase_provider(provider_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if provider_id.is_empty():
		return Result.failure("RulesetV2: dinnertime route provider_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: dinnertime route provider callback 无效: %s" % provider_id)
	for item_val in dinnertime_route_purchase_providers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == provider_id:
			return Result.failure("RulesetV2: dinnertime route provider 重复注册: %s (module:%s)" % [provider_id, source_module_id])
	dinnertime_route_purchase_providers.append({
		"id": provider_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

func register_state_initializer(initializer_id: String, callback: Callable, priority: int = 100, source_module_id: String = "") -> Result:
	if initializer_id.is_empty():
		return Result.failure("RulesetV2: state initializer_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: state initializer callback 无效: %s" % initializer_id)
	for item_val in state_initializers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == initializer_id:
			return Result.failure("RulesetV2: state initializer 重复注册: %s (module:%s)" % [initializer_id, source_module_id])
	state_initializers.append({
		"id": initializer_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	state_initializers.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.id) != str(b.id):
			return str(a.id) < str(b.id)
		return str(a.source) < str(b.source)
	)
	return Result.success()

func apply_state_initializers(state: GameState, rng_manager = null) -> Result:
	if state == null:
		return Result.failure("RulesetV2: state 为空")
	var warnings: Array[String] = []
	for i in range(state_initializers.size()):
		var item_val = state_initializers[i]
		if not (item_val is Dictionary):
			return Result.failure("RulesetV2: state_initializers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var cb: Callable = item.get("callback", Callable())
		if not cb.is_valid():
			return Result.failure("RulesetV2: state_initializers[%d] callback 无效" % i)
		var r = cb.call(state, rng_manager)
		if r == null or not (r is Result):
			return Result.failure("RulesetV2: state initializer 返回值类型错误（期望 Result）")
		var rr: Result = r
		if not rr.ok:
			return rr
		warnings.append_array(rr.warnings)
	return Result.success().with_warnings(warnings)

func register_employee_pool_patch(patch_id: String, employee_id: String, delta: int, source_module_id: String = "") -> Result:
	if patch_id.is_empty():
		return Result.failure("RulesetV2: employee_pool patch_id 不能为空")
	if employee_id.is_empty():
		return Result.failure("RulesetV2: employee_pool employee_id 不能为空")
	if delta <= 0:
		return Result.failure("RulesetV2: employee_pool delta 必须 > 0")

	# 允许不同模块重复注册同 patch_id（用于“只加一次”语义），但内容必须一致
	for item_val in employee_pool_patches:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) != patch_id:
			continue
		if str(item.get("employee_id", "")) != employee_id or int(item.get("delta", 0)) != delta:
			return Result.failure("RulesetV2: employee_pool 同 patch_id 内容不一致: %s" % patch_id)
		return Result.success()

	employee_pool_patches.append({
		"id": patch_id,
		"employee_id": employee_id,
		"delta": delta,
		"source": source_module_id,
	})
	return Result.success()

func register_phase_order_override(order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: phase_order 类型错误（期望 Array[String]）")
	if order_names.is_empty():
		return Result.failure("RulesetV2: phase_order 不能为空")
	if phase_order_override != null:
		var prev_source := str(phase_order_override.get("source", ""))
		return Result.failure("RulesetV2: phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])
	phase_order_override = {
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	}
	return Result.success()

func register_working_sub_phase_order_override(order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: working_sub_phase_order 类型错误（期望 Array[String]）")
	if order_names.is_empty():
		return Result.failure("RulesetV2: working_sub_phase_order 不能为空")
	if working_sub_phase_order_override != null:
		var prev_source := str(working_sub_phase_order_override.get("source", ""))
		return Result.failure("RulesetV2: working_sub_phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])
	working_sub_phase_order_override = {
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	}
	return Result.success()

func register_cleanup_sub_phase_order_override(order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: cleanup_sub_phase_order 类型错误（期望 Array[String]）")
	if order_names.is_empty():
		return Result.failure("RulesetV2: cleanup_sub_phase_order 不能为空")
	if cleanup_sub_phase_order_override != null:
		var prev_source := str(cleanup_sub_phase_order_override.get("source", ""))
		return Result.failure("RulesetV2: cleanup_sub_phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])
	cleanup_sub_phase_order_override = {
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	}
	return Result.success()

func register_settlement_triggers_override(phase: int, timing: String, points: Array, priority: int = 100, source_module_id: String = "") -> Result:
	if timing != "enter" and timing != "exit":
		return Result.failure("RulesetV2: settlement_triggers timing 不支持: %s" % timing)
	if points == null or not (points is Array):
		return Result.failure("RulesetV2: settlement_triggers points 类型错误（期望 Array[int]）")
	if phase == PhaseDefsClass.Phase.SETUP or phase == PhaseDefsClass.Phase.GAME_OVER:
		return Result.failure("RulesetV2: settlement_triggers 不允许包含 Setup/GameOver")

	for item_val in settlement_triggers_override:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("phase", -1)) == phase and str(item.get("timing", "")) == timing:
			var prev_source := str(item.get("source", ""))
			return Result.failure("RulesetV2: settlement_triggers_override 重复注册（%s vs %s）" % [prev_source, source_module_id])

	settlement_triggers_override.append({
		"phase": phase,
		"timing": timing,
		"points": points.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	})
	settlement_triggers_override.sort_custom(func(a, b) -> bool:
		return int(a.get("priority", 100)) > int(b.get("priority", 100))
	)
	return Result.success()

func register_phase_sub_phase_order_override(phase: int, order_names: Array, priority: int = 100, source_module_id: String = "") -> Result:
	if phase == PhaseDefsClass.Phase.WORKING:
		return Result.failure("RulesetV2: phase_sub_phase_order_override 不支持 Working（请使用 working_sub_phase_order_override）")
	if phase == PhaseDefsClass.Phase.CLEANUP:
		return Result.failure("RulesetV2: phase_sub_phase_order_override 不支持 Cleanup（请使用 cleanup_sub_phase_order_override/insertions）")
	if phase == PhaseDefsClass.Phase.SETUP or phase == PhaseDefsClass.Phase.GAME_OVER:
		return Result.failure("RulesetV2: phase_sub_phase_order_override 不允许包含 Setup/GameOver")
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: phase_sub_phase_order 类型错误（期望 Array[String]）")

	for item_val in phase_sub_phase_order_overrides:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("phase", -1)) == phase:
			var prev_source := str(item.get("source", ""))
			return Result.failure("RulesetV2: phase_sub_phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])

	phase_sub_phase_order_overrides.append({
		"phase": phase,
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	})
	phase_sub_phase_order_overrides.sort_custom(func(a, b) -> bool:
		return int(a.get("priority", 100)) > int(b.get("priority", 100))
	)
	return Result.success()

func apply_hooks_to_phase_manager(phase_manager) -> Result:
	if phase_manager == null:
		return Result.failure("RulesetV2: phase_manager 为空")
	if not phase_manager.has_method("register_phase_hook") \
			or not phase_manager.has_method("register_sub_phase_hook") \
			or not phase_manager.has_method("set_working_sub_phase_order") \
			or not phase_manager.has_method("set_cleanup_sub_phase_order") \
			or not phase_manager.has_method("set_phase_order") \
			or not phase_manager.has_method("set_phase_sub_phase_order"):
		return Result.failure("RulesetV2: phase_manager 缺少 hook 注册方法")

	for i in range(phase_hooks.size()):
		var h_val = phase_hooks[i]
		if not (h_val is Dictionary):
			return Result.failure("RulesetV2: phase_hooks[%d] 类型错误（期望 Dictionary）" % i)
		var h: Dictionary = h_val
		var cb: Callable = h.get("callback", Callable())
		var phase: int = int(h.get("phase", -1))
		var hook_type: int = int(h.get("hook_type", -1))
		var prio: int = int(h.get("priority", 100))
		var src: String = str(h.get("source", ""))
		if not cb.is_valid():
			return Result.failure("RulesetV2: phase_hooks[%d] callback 无效" % i)
		phase_manager.register_phase_hook(phase, hook_type, cb, prio, src)

	for i in range(sub_phase_hooks.size()):
		var h2_val = sub_phase_hooks[i]
		if not (h2_val is Dictionary):
			return Result.failure("RulesetV2: sub_phase_hooks[%d] 类型错误（期望 Dictionary）" % i)
		var h2: Dictionary = h2_val
		var cb2: Callable = h2.get("callback", Callable())
		var sub_phase: int = int(h2.get("sub_phase", -1))
		var hook_type2: int = int(h2.get("hook_type", -1))
		var prio2: int = int(h2.get("priority", 100))
		var src2: String = str(h2.get("source", ""))
		if not cb2.is_valid():
			return Result.failure("RulesetV2: sub_phase_hooks[%d] callback 无效" % i)
		phase_manager.register_sub_phase_hook(sub_phase, hook_type2, cb2, prio2, src2)

	# custom named subphase hooks (by name, independent of phase)
	if not named_sub_phase_hooks.is_empty():
		if not phase_manager.has_method("register_sub_phase_hook_by_name"):
			return Result.failure("RulesetV2: phase_manager 缺少 register_sub_phase_hook_by_name")
		for i in range(named_sub_phase_hooks.size()):
			var h0_val = named_sub_phase_hooks[i]
			if not (h0_val is Dictionary):
				return Result.failure("RulesetV2: named_sub_phase_hooks[%d] 类型错误（期望 Dictionary）" % i)
			var h0: Dictionary = h0_val
			var cb0: Callable = h0.get("callback", Callable())
			var name0: String = str(h0.get("sub_phase", ""))
			var hook_type0: int = int(h0.get("hook_type", -1))
			var prio0: int = int(h0.get("priority", 100))
			var src0: String = str(h0.get("source", ""))
			if name0.is_empty():
				return Result.failure("RulesetV2: named_sub_phase_hooks[%d].sub_phase 不能为空" % i)
			if not cb0.is_valid():
				return Result.failure("RulesetV2: named_sub_phase_hooks[%d] callback 无效" % i)
			phase_manager.register_sub_phase_hook_by_name(name0, hook_type0, cb0, prio0, src0)

	# working subphase order (base + insertions)
	if working_sub_phase_order_override != null and not working_sub_phase_insertions.is_empty():
		return Result.failure("RulesetV2: working_sub_phase_order_override 与 insertions 不能同时使用")
	var order_names: Array[String] = []
	for sub_id in PhaseDefsClass.SUB_PHASE_ORDER:
		order_names.append(str(PhaseDefsClass.SUB_PHASE_NAMES[sub_id]))

	for i in range(working_sub_phase_insertions.size()):
		var ins_val = working_sub_phase_insertions[i]
		if not (ins_val is Dictionary):
			return Result.failure("RulesetV2: working_sub_phase_insertions[%d] 类型错误（期望 Dictionary）" % i)
		var ins: Dictionary = ins_val
		var name: String = str(ins.get("sub_phase", ""))
		var after: String = str(ins.get("after", ""))
		var before: String = str(ins.get("before", ""))
		if name.is_empty():
			return Result.failure("RulesetV2: working_sub_phase_insertions[%d].sub_phase 不能为空" % i)
		if order_names.has(name):
			return Result.failure("RulesetV2: working sub_phase 重复: %s" % name)

		var insert_index := -1
		if not after.is_empty():
			var idx_after := order_names.find(after)
			if idx_after == -1:
				return Result.failure("RulesetV2: working sub_phase after 未找到: %s (insert:%s)" % [after, name])
			insert_index = idx_after + 1
		if not before.is_empty():
			var idx_before := order_names.find(before)
			if idx_before == -1:
				return Result.failure("RulesetV2: working sub_phase before 未找到: %s (insert:%s)" % [before, name])
			if insert_index == -1:
				insert_index = idx_before
			else:
				if insert_index > idx_before:
					return Result.failure("RulesetV2: working sub_phase after/before 顺序冲突: after=%s before=%s (insert:%s)" % [after, before, name])
		if insert_index == -1:
			return Result.failure("RulesetV2: working sub_phase 插入位置非法: %s" % name)

		order_names.insert(insert_index, name)

	if working_sub_phase_order_override != null:
		var o2_val = working_sub_phase_order_override.get("order", null)
		if not (o2_val is Array):
			return Result.failure("RulesetV2: working_sub_phase_order_override.order 类型错误（期望 Array）")
		var override_names: Array[String] = []
		var raw: Array = o2_val
		for i in range(raw.size()):
			if not (raw[i] is String):
				return Result.failure("RulesetV2: working_sub_phase_order_override.order[%d] 类型错误（期望 String）" % i)
			override_names.append(str(raw[i]))
		order_names = override_names

	var set_order: Result = phase_manager.set_working_sub_phase_order(order_names)
	if not set_order.ok:
		return set_order

	# custom working subphase hooks (by name)
	if not working_sub_phase_name_hooks.is_empty():
		if not phase_manager.has_method("register_sub_phase_hook_by_name"):
			return Result.failure("RulesetV2: phase_manager 缺少 register_sub_phase_hook_by_name")
		for i in range(working_sub_phase_name_hooks.size()):
			var h3_val = working_sub_phase_name_hooks[i]
			if not (h3_val is Dictionary):
				return Result.failure("RulesetV2: working_sub_phase_name_hooks[%d] 类型错误（期望 Dictionary）" % i)
			var h3: Dictionary = h3_val
			var cb3: Callable = h3.get("callback", Callable())
			var name3: String = str(h3.get("sub_phase", ""))
			var hook_type3: int = int(h3.get("hook_type", -1))
			var prio3: int = int(h3.get("priority", 100))
			var src3: String = str(h3.get("source", ""))
			if name3.is_empty():
				return Result.failure("RulesetV2: working_sub_phase_name_hooks[%d].sub_phase 不能为空" % i)
			if not cb3.is_valid():
				return Result.failure("RulesetV2: working_sub_phase_name_hooks[%d] callback 无效" % i)
			phase_manager.register_sub_phase_hook_by_name(name3, hook_type3, cb3, prio3, src3)

	# cleanup subphase order (custom only)
	if cleanup_sub_phase_order_override != null and not cleanup_sub_phase_insertions.is_empty():
		return Result.failure("RulesetV2: cleanup_sub_phase_order_override 与 insertions 不能同时使用")
	var cleanup_order_names: Array[String] = []
	if cleanup_sub_phase_order_override != null:
		var o3_val = cleanup_sub_phase_order_override.get("order", null)
		if not (o3_val is Array):
			return Result.failure("RulesetV2: cleanup_sub_phase_order_override.order 类型错误（期望 Array）")
		var override_names2: Array[String] = []
		var raw2: Array = o3_val
		for i in range(raw2.size()):
			if not (raw2[i] is String):
				return Result.failure("RulesetV2: cleanup_sub_phase_order_override.order[%d] 类型错误（期望 String）" % i)
			override_names2.append(str(raw2[i]))
		cleanup_order_names = override_names2
	for i in range(cleanup_sub_phase_insertions.size()):
		var ins_val2 = cleanup_sub_phase_insertions[i]
		if not (ins_val2 is Dictionary):
			return Result.failure("RulesetV2: cleanup_sub_phase_insertions[%d] 类型错误（期望 Dictionary）" % i)
		var ins2: Dictionary = ins_val2
		var name4: String = str(ins2.get("sub_phase", ""))
		var after4: String = str(ins2.get("after", ""))
		var before4: String = str(ins2.get("before", ""))
		if name4.is_empty():
			return Result.failure("RulesetV2: cleanup_sub_phase_insertions[%d].sub_phase 不能为空" % i)
		if cleanup_order_names.has(name4):
			return Result.failure("RulesetV2: cleanup sub_phase 重复: %s" % name4)

		var insert_index2 := -1
		if cleanup_order_names.is_empty() and after4.is_empty() and before4.is_empty():
			insert_index2 = 0
		else:
			if not after4.is_empty():
				var idx_after2 := cleanup_order_names.find(after4)
				if idx_after2 == -1:
					return Result.failure("RulesetV2: cleanup sub_phase after 未找到: %s (insert:%s)" % [after4, name4])
				insert_index2 = idx_after2 + 1
			if not before4.is_empty():
				var idx_before2 := cleanup_order_names.find(before4)
				if idx_before2 == -1:
					return Result.failure("RulesetV2: cleanup sub_phase before 未找到: %s (insert:%s)" % [before4, name4])
				if insert_index2 == -1:
					insert_index2 = idx_before2
				else:
					if insert_index2 > idx_before2:
						return Result.failure("RulesetV2: cleanup sub_phase after/before 顺序冲突: after=%s before=%s (insert:%s)" % [after4, before4, name4])
			if insert_index2 == -1:
				return Result.failure("RulesetV2: cleanup sub_phase 插入位置非法: %s" % name4)

		cleanup_order_names.insert(insert_index2, name4)

	if not cleanup_order_names.is_empty():
		var set_cleanup_order: Result = phase_manager.set_cleanup_sub_phase_order(cleanup_order_names)
		if not set_cleanup_order.ok:
			return set_cleanup_order

	# custom cleanup subphase hooks (by name)
	if not cleanup_sub_phase_name_hooks.is_empty():
		if not phase_manager.has_method("register_sub_phase_hook_by_name"):
			return Result.failure("RulesetV2: phase_manager 缺少 register_sub_phase_hook_by_name")
		for i in range(cleanup_sub_phase_name_hooks.size()):
			var h4_val = cleanup_sub_phase_name_hooks[i]
			if not (h4_val is Dictionary):
				return Result.failure("RulesetV2: cleanup_sub_phase_name_hooks[%d] 类型错误（期望 Dictionary）" % i)
			var h4: Dictionary = h4_val
			var cb4: Callable = h4.get("callback", Callable())
			var name5: String = str(h4.get("sub_phase", ""))
			var hook_type4: int = int(h4.get("hook_type", -1))
			var prio4: int = int(h4.get("priority", 100))
			var src4: String = str(h4.get("source", ""))
			if name5.is_empty():
				return Result.failure("RulesetV2: cleanup_sub_phase_name_hooks[%d].sub_phase 不能为空" % i)
			if not cb4.is_valid():
				return Result.failure("RulesetV2: cleanup_sub_phase_name_hooks[%d] callback 无效" % i)
			phase_manager.register_sub_phase_hook_by_name(name5, hook_type4, cb4, prio4, src4)

	# settlement triggers override
	if not settlement_triggers_override.is_empty():
		if not phase_manager.has_method("set_settlement_triggers_on_enter") or not phase_manager.has_method("set_settlement_triggers_on_exit"):
			return Result.failure("RulesetV2: phase_manager 缺少 settlement_triggers 设置方法")
		for i in range(settlement_triggers_override.size()):
			var item_val5 = settlement_triggers_override[i]
			if not (item_val5 is Dictionary):
				return Result.failure("RulesetV2: settlement_triggers_override[%d] 类型错误（期望 Dictionary）" % i)
			var item5: Dictionary = item_val5
			var phase5: int = int(item5.get("phase", -1))
			var timing5: String = str(item5.get("timing", ""))
			var points5 = item5.get("points", null)
			if not (points5 is Array):
				return Result.failure("RulesetV2: settlement_triggers_override[%d].points 类型错误（期望 Array）" % i)
			var set_r: Result
			if timing5 == "enter":
				set_r = phase_manager.set_settlement_triggers_on_enter(phase5, points5)
			elif timing5 == "exit":
				set_r = phase_manager.set_settlement_triggers_on_exit(phase5, points5)
			else:
				return Result.failure("RulesetV2: settlement_triggers_override[%d].timing 不支持: %s" % [i, timing5])
			if not set_r.ok:
				return set_r

	# phase sub phase order overrides
	if not phase_sub_phase_order_overrides.is_empty():
		for i in range(phase_sub_phase_order_overrides.size()):
			var item_val6 = phase_sub_phase_order_overrides[i]
			if not (item_val6 is Dictionary):
				return Result.failure("RulesetV2: phase_sub_phase_order_overrides[%d] 类型错误（期望 Dictionary）" % i)
			var item6: Dictionary = item_val6
			var phase6: int = int(item6.get("phase", -1))
			var order6 = item6.get("order", null)
			if not (order6 is Array):
				return Result.failure("RulesetV2: phase_sub_phase_order_overrides[%d].order 类型错误（期望 Array）" % i)
			var set_r2: Result = phase_manager.set_phase_sub_phase_order(phase6, order6)
			if not set_r2.ok:
				return set_r2

	# phase order override (optional)
	if phase_order_override != null:
		var o_val = phase_order_override.get("order", null)
		if not (o_val is Array):
			return Result.failure("RulesetV2: phase_order_override.order 类型错误（期望 Array）")
		var r_set_phase: Result = phase_manager.set_phase_order(o_val)
		if not r_set_phase.ok:
			return r_set_phase

	return Result.success()

func validate_content_effect_handlers(catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if not (catalog.employees is Dictionary):
		return Result.failure("RulesetV2: catalog.employees 类型错误（期望 Dictionary）")
	if not (catalog.employee_sources is Dictionary):
		return Result.failure("RulesetV2: catalog.employee_sources 类型错误（期望 Dictionary）")
	if not (catalog.milestones is Dictionary):
		return Result.failure("RulesetV2: catalog.milestones 类型错误（期望 Dictionary）")
	if not (catalog.milestone_sources is Dictionary):
		return Result.failure("RulesetV2: catalog.milestone_sources 类型错误（期望 Dictionary）")

	var missing: Dictionary = {}  # effect_id -> Array[String] refs

	for emp_id_val in catalog.employees.keys():
		if not (emp_id_val is String):
			return Result.failure("RulesetV2: catalog.employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		var def_val = catalog.employees.get(emp_id, null)
		if def_val == null:
			return Result.failure("RulesetV2: catalog.employees[%s] 为空" % emp_id)
		if not (def_val is EmployeeDefClass):
			return Result.failure("RulesetV2: catalog.employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var def: EmployeeDef = def_val
		for i in range(def.effect_ids.size()):
			var eid: String = def.effect_ids[i]
			if effect_registry.has_handler(eid):
				continue
			if not missing.has(eid):
				missing[eid] = []
			var src: String = str(catalog.employee_sources.get(emp_id, ""))
			var refs: Array = missing[eid]
			refs.append("employee:%s (module:%s)" % [emp_id, src])
			missing[eid] = refs

	for ms_id_val in catalog.milestones.keys():
		if not (ms_id_val is String):
			return Result.failure("RulesetV2: catalog.milestones key 类型错误（期望 String）")
		var ms_id: String = str(ms_id_val)
		var def_val = catalog.milestones.get(ms_id, null)
		if def_val == null:
			return Result.failure("RulesetV2: catalog.milestones[%s] 为空" % ms_id)
		if not (def_val is MilestoneDefClass):
			return Result.failure("RulesetV2: catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % ms_id)
		var def: MilestoneDef = def_val
		for i in range(def.effect_ids.size()):
			var eid: String = def.effect_ids[i]
			if effect_registry.has_handler(eid):
				continue
			if not missing.has(eid):
				missing[eid] = []
			var src: String = str(catalog.milestone_sources.get(ms_id, ""))
			var refs: Array = missing[eid]
			refs.append("milestone:%s (module:%s)" % [ms_id, src])
			missing[eid] = refs

	if missing.is_empty():
		return Result.success()

	var effect_ids: Array[String] = []
	for k in missing.keys():
		if k is String:
			effect_ids.append(str(k))
	effect_ids.sort()

	var parts: Array[String] = []
	for eid in effect_ids:
		var refs: Array = missing.get(eid, [])
		refs.sort()
		var refs_str := ", ".join(Array(refs, TYPE_STRING, "", null))
		parts.append("%s <- %s" % [eid, refs_str])

	return Result.failure("缺少 effect handler: %s" % " | ".join(parts))

func validate_content_milestone_effect_handlers(catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if not (catalog.milestones is Dictionary):
		return Result.failure("RulesetV2: catalog.milestones 类型错误（期望 Dictionary）")
	if not (catalog.milestone_sources is Dictionary):
		return Result.failure("RulesetV2: catalog.milestone_sources 类型错误（期望 Dictionary）")

	var missing: Dictionary = {}  # effect_type -> Array[String] refs

	for ms_id_val in catalog.milestones.keys():
		if not (ms_id_val is String):
			return Result.failure("RulesetV2: catalog.milestones key 类型错误（期望 String）")
		var ms_id: String = str(ms_id_val)
		var def_val = catalog.milestones.get(ms_id, null)
		if def_val == null:
			return Result.failure("RulesetV2: catalog.milestones[%s] 为空" % ms_id)
		if not (def_val is MilestoneDefClass):
			return Result.failure("RulesetV2: catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % ms_id)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("RulesetV2: %s.effects[%d] 类型错误（期望 Dictionary）" % [ms_id, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("RulesetV2: %s.effects[%d].type 类型错误（期望 String）" % [ms_id, e_i])
			var t: String = str(type_val)
			if t.is_empty():
				return Result.failure("RulesetV2: %s.effects[%d].type 不能为空" % [ms_id, e_i])
			if milestone_effect_registry.has_handler(t):
				continue

			if not missing.has(t):
				missing[t] = []
			var src: String = str(catalog.milestone_sources.get(ms_id, ""))
			var refs: Array = missing[t]
			refs.append("%s.effects[%d] (module:%s)" % [ms_id, e_i, src])
			missing[t] = refs

	if missing.is_empty():
		return Result.success()

	var types: Array[String] = []
	for k in missing.keys():
		if k is String:
			types.append(str(k))
	types.sort()

	var parts: Array[String] = []
	for t in types:
		var refs: Array = missing.get(t, [])
		refs.sort()
		var refs_str := ", ".join(Array(refs, TYPE_STRING, "", null))
		parts.append("%s <- %s" % [t, refs_str])

	return Result.failure("缺少 milestone effect handler: %s" % " | ".join(parts))
