extends RefCounted

const EffectIdsSegmentInvokerClass = preload("res://core/rules/effect_ids_segment_invoker.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

const EFFECT_SEG_PAYDAY_SALARY_DISCOUNT := ":payday:salary_discount:"
const RECRUIT_TRACK_ID := "recruit"

static func collect_for_player(
	state: GameState,
	player_id: int,
	player_override: Dictionary = {},
	effect_registry = null
) -> Result:
	if state == null:
		return Result.failure("PaydaySalaryDiscountUsage: state 为空")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("PaydaySalaryDiscountUsage: player_id 越界: %d" % player_id)
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("PaydaySalaryDiscountUsage: EmployeeRegistry 未初始化")

	var sync_read := StaffStateClass.ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read

	var player: Dictionary = player_override
	if player.is_empty():
		var player_read := PlayerStateAccessClass.require_player(state, player_id, "PaydaySalaryDiscountUsage")
		if not player_read.ok:
			return player_read
		player = player_read.value

	var active_ids_read := PlayerStateAccessClass.require_employees_staff_ids(player, "player[%d]" % player_id, "PaydaySalaryDiscountUsage")
	if not active_ids_read.ok:
		return active_ids_read
	var active_ids: Array = active_ids_read.value

	var registry_read := PlayerStateAccessClass.require_staff_registry(player, "player[%d]" % player_id, "PaydaySalaryDiscountUsage")
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value

	var capacity := 0
	var used_actions := 0
	var sources: Dictionary = {}
	var staff_sources: Array[Dictionary] = []
	var warnings: Array[String] = []

	for i in range(active_ids.size()):
		var staff_id := int(active_ids[i])
		if staff_id <= 0:
			return Result.failure("PaydaySalaryDiscountUsage: player[%d].employees_staff_ids[%d] 必须为正整数" % [player_id, i])
		if not registry.has(staff_id):
			return Result.failure("PaydaySalaryDiscountUsage: player[%d].staff_registry 缺少 staff_id=%d" % [player_id, staff_id])
		var record_val = registry.get(staff_id, null)
		if not (record_val is Dictionary):
			return Result.failure("PaydaySalaryDiscountUsage: player[%d].staff_registry[%d] 类型错误（期望 Dictionary）" % [player_id, staff_id])
		var record: Dictionary = record_val
		var emp_id := str(record.get("employee_type", "")).strip_edges()
		if emp_id.is_empty():
			return Result.failure("PaydaySalaryDiscountUsage: player[%d].staff_registry[%d].employee_type 不能为空" % [player_id, staff_id])

		var cap_read := _get_discount_capacity_for_employee(state, player_id, emp_id, effect_registry)
		if not cap_read.ok:
			return cap_read
		warnings.append_array(cap_read.warnings)
		var cap := int(cap_read.value)
		if cap <= 0:
			continue

		var used_read := StaffStateClass.get_staff_track_used(state, staff_id, RECRUIT_TRACK_ID)
		if not used_read.ok:
			return used_read
		var used := int(used_read.value)
		var capped_used := mini(used, cap)

		capacity += cap
		used_actions += capped_used
		sources[emp_id] = int(sources.get(emp_id, 0)) + maxi(0, cap - capped_used)
		staff_sources.append({
			"staff_id": staff_id,
			"employee_type": emp_id,
			"capacity": cap,
			"used": capped_used,
			"raw_used": used,
			"unused": maxi(0, cap - capped_used),
		})

	return Result.success({
		"salary_discount_recruit_capacity": capacity,
		"salary_discount_used_actions": used_actions,
		"salary_discount_unused_actions": maxi(0, capacity - used_actions),
		"discount_sources": sources,
		"staff_sources": staff_sources,
	}).with_warnings(warnings)

static func collect_for_state_player(state: GameState, player_id: int, effect_registry = null) -> Result:
	return collect_for_player(state, player_id, {}, effect_registry)

static func _get_discount_capacity_for_employee(
	state: GameState,
	player_id: int,
	employee_id: String,
	effect_registry
) -> Result:
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return Result.failure("PaydaySalaryDiscountUsage: employee_id 不能为空")
	var def_val = EmployeeRegistryClass.get_def(emp_id)
	if def_val == null:
		return Result.failure("PaydaySalaryDiscountUsage: 未知员工定义: %s" % emp_id)
	if not (def_val is EmployeeDef):
		return Result.failure("PaydaySalaryDiscountUsage: 员工定义类型错误（期望 EmployeeDef）: %s" % emp_id)
	var def: EmployeeDef = def_val

	if effect_registry == null:
		if not _has_salary_discount_effect(def):
			return Result.success(0)
		var fallback_cap := int(def.recruit_capacity)
		if fallback_cap <= 0:
			return Result.failure("PaydaySalaryDiscountUsage: %s.recruit_capacity 必须 > 0" % emp_id)
		return Result.success(fallback_cap)

	var ctx := {"salary_discount_recruit_capacity": 0}
	var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
		effect_registry,
		def.effect_ids,
		EFFECT_SEG_PAYDAY_SALARY_DISCOUNT,
		[state, player_id, ctx, emp_id],
		"PaydaySalaryDiscountUsage",
		"EmployeeDef[%s].effect_ids" % emp_id
	)
	if not inv.ok:
		return inv
	var cap_val = ctx.get("salary_discount_recruit_capacity", null)
	if not (cap_val is int):
		return Result.failure("PaydaySalaryDiscountUsage: ctx.salary_discount_recruit_capacity 类型错误（期望 int）")
	return Result.success(int(cap_val)).with_warnings(inv.warnings)

static func _has_salary_discount_effect(def: EmployeeDef) -> bool:
	for eff_id in def.effect_ids:
		var s := str(eff_id)
		if s.find(EFFECT_SEG_PAYDAY_SALARY_DISCOUNT) >= 0:
			return true
	return false
