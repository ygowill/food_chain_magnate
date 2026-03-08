# DinnertimeSettlement：EffectRegistry 调用封装
class_name DinnertimeEffects
extends RefCounted

const DinnertimeRulesClass = preload("res://core/rules/dinnertime_rules.gd")
const GlobalEffectListClass = preload("res://core/rules/global_effect_list.gd")
const EffectIdsSegmentInvokerClass = preload("res://core/rules/effect_ids_segment_invoker.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const WorkingMultiplierClass = preload("res://core/rules/employee_rules/working_multiplier.gd")

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

	var employees_read := PlayerStateAccessClass.require_employees(player, "player[%d]" % player_id, "晚餐结算失败：")
	if not employees_read.ok:
		return employees_read
	var employees: Array = employees_read.value

	var warnings: Array[String] = []
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("晚餐结算失败：player[%d].employees[%d] 类型错误（期望 String）" % [player_id, i])
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("晚餐结算失败：player[%d].employees[%d] 不能为空" % [player_id, i])

		var employee_read := DinnertimeRulesClass.require_employee_def(emp_id)
		if not employee_read.ok:
			return employee_read
		var def: EmployeeDef = employee_read.value

		var mult := maxi(1, WorkingMultiplierClass.get_working_employee_multiplier(state, player_id, emp_id))
		for _k in range(mult):
			var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
				effect_registry,
				def.effect_ids,
				segment,
				[state, player_id, ctx],
				"晚餐结算失败：",
				"EmployeeDef[%s].effect_ids" % emp_id
			)
			if not inv.ok:
				return inv
			warnings.append_array(inv.warnings)

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

	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % player_id, "晚餐结算失败：")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value

	var warnings: Array[String] = []
	for i in range(milestones.size()):
		var ms_val = milestones[i]
		if not (ms_val is String):
			return Result.failure("晚餐结算失败：player[%d].milestones[%d] 类型错误（期望 String）" % [player_id, i])
		var ms_id: String = str(ms_val)
		if ms_id.is_empty():
			return Result.failure("晚餐结算失败：player[%d].milestones[%d] 不能为空" % [player_id, i])

		var milestone_read := DinnertimeRulesClass.require_milestone_def(ms_id)
		if not milestone_read.ok:
			return milestone_read
		var def: MilestoneDef = milestone_read.value

		var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
			effect_registry,
			def.effect_ids,
			segment,
			[state, player_id, ctx],
			"晚餐结算失败：",
			"MilestoneDef[%s].effect_ids" % ms_id
		)
		if not inv.ok:
			return inv
		warnings.append_array(inv.warnings)

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

	var ids_read := GlobalEffectListClass.get_all_effect_ids(state)
	if not ids_read.ok:
		return ids_read
	warnings.append_array(ids_read.warnings)
	var ids_any: Array = ids_read.value

	var inv := EffectIdsSegmentInvokerClass.invoke_effect_ids_by_segment(
		effect_registry,
		ids_any,
		segment,
		[state, player_id_for_ctx, ctx],
		"晚餐结算失败：",
		"global_effect_ids"
	)
	if not inv.ok:
		return inv
	warnings.append_array(inv.warnings)

	return Result.success().with_warnings(warnings)
