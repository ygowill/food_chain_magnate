# RulesetV2：state initializer / order override / trigger override 下沉
class_name RulesetV2StateAndOrder
extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func register_state_initializer(
	ruleset,
	initializer_id: String,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if initializer_id.is_empty():
		return Result.failure("RulesetV2: state initializer_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: state initializer callback 无效: %s" % initializer_id)
	for item_val in ruleset.state_initializers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == initializer_id:
			return Result.failure("RulesetV2: state initializer 重复注册: %s (module:%s)" % [initializer_id, source_module_id])
	ruleset.state_initializers.append({
		"id": initializer_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	ruleset.state_initializers.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.id) != str(b.id):
			return str(a.id) < str(b.id)
		return str(a.source) < str(b.source)
	)
	return Result.success()

static func apply_state_initializers(ruleset, state: GameState, rng_manager = null) -> Result:
	if state == null:
		return Result.failure("RulesetV2: state 为空")
	var warnings: Array[String] = []
	for i in range(ruleset.state_initializers.size()):
		var item_val = ruleset.state_initializers[i]
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

static func register_employee_pool_patch(
	ruleset,
	patch_id: String,
	employee_id: String,
	delta: int,
	source_module_id: String = ""
) -> Result:
	if patch_id.is_empty():
		return Result.failure("RulesetV2: employee_pool patch_id 不能为空")
	if employee_id.is_empty():
		return Result.failure("RulesetV2: employee_pool employee_id 不能为空")
	if delta <= 0:
		return Result.failure("RulesetV2: employee_pool delta 必须 > 0")

	# 允许不同模块重复注册同 patch_id（用于“只加一次”语义），但内容必须一致
	for item_val in ruleset.employee_pool_patches:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) != patch_id:
			continue
		if str(item.get("employee_id", "")) != employee_id or int(item.get("delta", 0)) != delta:
			return Result.failure("RulesetV2: employee_pool 同 patch_id 内容不一致: %s" % patch_id)
		return Result.success()

	ruleset.employee_pool_patches.append({
		"id": patch_id,
		"employee_id": employee_id,
		"delta": delta,
		"source": source_module_id,
	})
	return Result.success()

static func register_phase_order_override(
	ruleset,
	order_names: Array,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: phase_order 类型错误（期望 Array[String]）")
	if order_names.is_empty():
		return Result.failure("RulesetV2: phase_order 不能为空")
	if ruleset.phase_order_override != null:
		var prev_source := str(ruleset.phase_order_override.get("source", ""))
		return Result.failure("RulesetV2: phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])
	ruleset.phase_order_override = {
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	}
	return Result.success()

static func register_working_sub_phase_order_override(
	ruleset,
	order_names: Array,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: working_sub_phase_order 类型错误（期望 Array[String]）")
	if order_names.is_empty():
		return Result.failure("RulesetV2: working_sub_phase_order 不能为空")
	if ruleset.working_sub_phase_order_override != null:
		var prev_source := str(ruleset.working_sub_phase_order_override.get("source", ""))
		return Result.failure("RulesetV2: working_sub_phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])
	ruleset.working_sub_phase_order_override = {
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	}
	return Result.success()

static func register_cleanup_sub_phase_order_override(
	ruleset,
	order_names: Array,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: cleanup_sub_phase_order 类型错误（期望 Array[String]）")
	if order_names.is_empty():
		return Result.failure("RulesetV2: cleanup_sub_phase_order 不能为空")
	if ruleset.cleanup_sub_phase_order_override != null:
		var prev_source := str(ruleset.cleanup_sub_phase_order_override.get("source", ""))
		return Result.failure("RulesetV2: cleanup_sub_phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])
	ruleset.cleanup_sub_phase_order_override = {
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	}
	return Result.success()

static func register_settlement_triggers_override(
	ruleset,
	phase: int,
	timing: String,
	points: Array,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if timing != "enter" and timing != "exit":
		return Result.failure("RulesetV2: settlement_triggers timing 不支持: %s" % timing)
	if points == null or not (points is Array):
		return Result.failure("RulesetV2: settlement_triggers points 类型错误（期望 Array[int]）")
	if phase == PhaseDefsClass.Phase.SETUP or phase == PhaseDefsClass.Phase.GAME_OVER:
		return Result.failure("RulesetV2: settlement_triggers 不允许包含 Setup/GameOver")

	for item_val in ruleset.settlement_triggers_override:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("phase", -1)) == phase and str(item.get("timing", "")) == timing:
			var prev_source := str(item.get("source", ""))
			return Result.failure("RulesetV2: settlement_triggers_override 重复注册（%s vs %s）" % [prev_source, source_module_id])

	ruleset.settlement_triggers_override.append({
		"phase": phase,
		"timing": timing,
		"points": points.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	})
	ruleset.settlement_triggers_override.sort_custom(func(a, b) -> bool:
		return int(a.get("priority", 100)) > int(b.get("priority", 100))
	)
	return Result.success()

static func register_phase_sub_phase_order_override(
	ruleset,
	phase: int,
	order_names: Array,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if phase == PhaseDefsClass.Phase.WORKING:
		return Result.failure("RulesetV2: phase_sub_phase_order_override 不支持 Working（请使用 working_sub_phase_order_override）")
	if phase == PhaseDefsClass.Phase.CLEANUP:
		return Result.failure("RulesetV2: phase_sub_phase_order_override 不支持 Cleanup（请使用 cleanup_sub_phase_order_override/insertions）")
	if phase == PhaseDefsClass.Phase.SETUP or phase == PhaseDefsClass.Phase.GAME_OVER:
		return Result.failure("RulesetV2: phase_sub_phase_order_override 不允许包含 Setup/GameOver")
	if order_names == null or not (order_names is Array):
		return Result.failure("RulesetV2: phase_sub_phase_order 类型错误（期望 Array[String]）")

	for item_val in ruleset.phase_sub_phase_order_overrides:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("phase", -1)) == phase:
			var prev_source := str(item.get("source", ""))
			return Result.failure("RulesetV2: phase_sub_phase_order_override 重复注册（%s vs %s）" % [prev_source, source_module_id])

	ruleset.phase_sub_phase_order_overrides.append({
		"phase": phase,
		"order": order_names.duplicate(),
		"priority": int(priority),
		"source": source_module_id,
	})
	ruleset.phase_sub_phase_order_overrides.sort_custom(func(a, b) -> bool:
		return int(a.get("priority", 100)) > int(b.get("priority", 100))
	)
	return Result.success()

