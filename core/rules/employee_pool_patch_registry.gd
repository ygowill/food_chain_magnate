class_name EmployeePoolPatchRegistry
extends RefCounted

# EmployeePoolPatchRegistry：模块可对“初始 employee_pool”进行受控调整（例如：额外 +1 张 luxury_manager）。
# 设计目标：
# - Strict Mode：引用不存在的 employee_id 直接失败
# - 支持“只加一次”的去重（同 patch_id 多次注册但内容一致 -> 去重；内容不一致 -> 失败）

static var _patches: Array[Dictionary] = [] # [{id, employee_id, delta, source}]
static var _loaded: bool = false

static func reset() -> void:
	_patches = []
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("EmployeePoolPatchRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("EmployeePoolPatchRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("EmployeePoolPatchRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.employee_pool_patches is Array):
		return Result.failure("EmployeePoolPatchRegistry.configure_from_ruleset: ruleset.employee_pool_patches 类型错误（期望 Array）")

	_patches = []

	var seen := {}
	for i in range(ruleset.employee_pool_patches.size()):
		var item_val = ruleset.employee_pool_patches[i]
		if not (item_val is Dictionary):
			return Result.failure("EmployeePoolPatchRegistry: employee_pool_patches[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("EmployeePoolPatchRegistry: employee_pool_patches[%d].id 类型错误（期望 String）" % i)
		var patch_id: String = str(id_val)
		if patch_id.is_empty():
			return Result.failure("EmployeePoolPatchRegistry: employee_pool_patches[%d].id 不能为空" % i)

		var emp_val = item.get("employee_id", null)
		if not (emp_val is String):
			return Result.failure("EmployeePoolPatchRegistry: employee_pool_patches[%d].employee_id 类型错误（期望 String）" % i)
		var employee_id: String = str(emp_val)
		if employee_id.is_empty():
			return Result.failure("EmployeePoolPatchRegistry: employee_pool_patches[%d].employee_id 不能为空" % i)

		var delta_val = item.get("delta", null)
		if not (delta_val is int):
			return Result.failure("EmployeePoolPatchRegistry: employee_pool_patches[%d].delta 类型错误（期望 int）" % i)
		var delta: int = int(delta_val)
		if delta <= 0:
			return Result.failure("EmployeePoolPatchRegistry: employee_pool_patches[%d].delta 必须 > 0" % i)

		if seen.has(patch_id):
			var prev: Dictionary = seen[patch_id]
			if str(prev.get("employee_id", "")) != employee_id or int(prev.get("delta", 0)) != delta:
				return Result.failure("EmployeePoolPatchRegistry: 同 patch_id 内容不一致: %s" % patch_id)
			continue
		seen[patch_id] = {
			"employee_id": employee_id,
			"delta": delta,
		}
		_patches.append({
			"id": patch_id,
			"employee_id": employee_id,
			"delta": delta,
			"source": str(item.get("source", "")),
		})

	return Result.success()

static func apply_to_state(state: GameState) -> Result:
	if not _loaded:
		return Result.failure("EmployeePoolPatchRegistry 未初始化：请先调用 reset()")
	if state == null:
		return Result.failure("EmployeePoolPatchRegistry.apply_to_state: state 为空")
	if not (state.employee_pool is Dictionary):
		return Result.failure("EmployeePoolPatchRegistry.apply_to_state: state.employee_pool 类型错误（期望 Dictionary）")

	if _patches.is_empty():
		return Result.success()

	for patch_val in _patches:
		if not (patch_val is Dictionary):
			return Result.failure("EmployeePoolPatchRegistry.apply_to_state: patch 类型错误（期望 Dictionary）")
		var patch: Dictionary = patch_val

		var emp_id: String = str(patch.get("employee_id", ""))
		if emp_id.is_empty():
			return Result.failure("EmployeePoolPatchRegistry.apply_to_state: patch.employee_id 为空")
		if not state.employee_pool.has(emp_id):
			return Result.failure("EmployeePoolPatchRegistry.apply_to_state: 目标员工不在 employee_pool 中: %s" % emp_id)

		var before_val = state.employee_pool.get(emp_id, null)
		if not (before_val is int):
			return Result.failure("EmployeePoolPatchRegistry.apply_to_state: employee_pool[%s] 类型错误（期望 int）" % emp_id)
		var before: int = int(before_val)

		var delta: int = int(patch.get("delta", 0))
		if delta <= 0:
			return Result.failure("EmployeePoolPatchRegistry.apply_to_state: patch.delta 无效: %d" % delta)

		var after := before + delta
		state.employee_pool[emp_id] = after

	return Result.success()

