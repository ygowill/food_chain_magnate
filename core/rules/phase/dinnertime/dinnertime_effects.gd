# DinnertimeSettlement：EffectRegistry 调用封装
class_name DinnertimeEffects
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

static func apply_employee_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")
	if segment.is_empty():
		return Result.failure("晚餐结算失败：effect segment 不能为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("晚餐结算失败：effect ctx 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("晚餐结算失败：player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var employees_val = player.get("employees", null)
	if not (employees_val is Array):
		return Result.failure("晚餐结算失败：player[%d].employees 类型错误（期望 Array）" % player_id)
	var employees: Array = employees_val

	var warnings: Array[String] = []
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("晚餐结算失败：player[%d].employees[%d] 类型错误（期望 String）" % [player_id, i])
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("晚餐结算失败：player[%d].employees[%d] 不能为空" % [player_id, i])

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			return Result.failure("晚餐结算失败：未知员工定义: %s" % emp_id)
		if not (def_val is EmployeeDef):
			return Result.failure("晚餐结算失败：员工定义类型错误（期望 EmployeeDef）: %s" % emp_id)
		var def: EmployeeDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(segment) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)

static func apply_milestone_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")
	if segment.is_empty():
		return Result.failure("晚餐结算失败：effect segment 不能为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("晚餐结算失败：effect ctx 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("晚餐结算失败：player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return Result.failure("晚餐结算失败：player[%d].milestones 类型错误（期望 Array）" % player_id)
	var milestones: Array = milestones_val

	var warnings: Array[String] = []
	for i in range(milestones.size()):
		var ms_val = milestones[i]
		if not (ms_val is String):
			return Result.failure("晚餐结算失败：player[%d].milestones[%d] 类型错误（期望 String）" % [player_id, i])
		var ms_id: String = str(ms_val)
		if ms_id.is_empty():
			return Result.failure("晚餐结算失败：player[%d].milestones[%d] 不能为空" % [player_id, i])

		var def_val = MilestoneRegistryClass.get_def(ms_id)
		if def_val == null:
			return Result.failure("晚餐结算失败：未知里程碑定义: %s" % ms_id)
		if not (def_val is MilestoneDef):
			return Result.failure("晚餐结算失败：里程碑定义类型错误（期望 MilestoneDef）: %s" % ms_id)
		var def: MilestoneDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(segment) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)

static func apply_global_effects_by_segment(
	state: GameState,
	player_id_for_ctx: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")
	if segment.is_empty():
		return Result.failure("晚餐结算失败：effect segment 不能为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("晚餐结算失败：effect ctx 类型错误（期望 Dictionary）")
	if not (state.round_state is Dictionary):
		return Result.failure("晚餐结算失败：state.round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("晚餐结算失败：state.map 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []

	var sources: Array = []
	sources.append(state.round_state.get("global_effect_ids", null))
	sources.append(state.map.get("global_effect_ids", null))
	for src in sources:
		if src == null:
			continue
		if not (src is Array):
			return Result.failure("晚餐结算失败：global_effect_ids 类型错误（期望 Array[String]）")
		var ids: Array = src
		for i in range(ids.size()):
			var v = ids[i]
			if not (v is String):
				return Result.failure("晚餐结算失败：global_effect_ids[%d] 类型错误（期望 String）" % i)
			var effect_id: String = str(v)
			if effect_id.is_empty():
				return Result.failure("晚餐结算失败：global_effect_ids[%d] 不能为空" % i)
			if effect_id.find(segment) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id_for_ctx, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)
