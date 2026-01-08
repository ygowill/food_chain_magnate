extends RefCounted

static func get_working_employee_multiplier(state: GameState, player_id: int, employee_id: String) -> int:
	# 扩展点：工作阶段中“有效员工数量”乘数（模块可写入 round_state.working_employee_multipliers）。
	# round_state.working_employee_multipliers: player_id -> { employee_id -> multiplier }
	if state == null:
		return 1
	assert(not employee_id.is_empty(), "employee_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	var val = state.round_state.get("working_employee_multipliers", null)
	if val == null:
		return 1
	assert(val is Dictionary, "round_state.working_employee_multipliers 类型错误（期望 Dictionary）")
	var all: Dictionary = val
	assert(not all.has(str(player_id)), "round_state.working_employee_multipliers 不应包含字符串玩家 key: %s" % str(player_id))
	if not all.has(player_id):
		return 1
	var per_val = all[player_id]
	assert(per_val is Dictionary, "round_state.working_employee_multipliers[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val
	if not per_player.has(employee_id):
		return 1
	var m_val = per_player[employee_id]
	assert(m_val is int, "round_state.working_employee_multipliers[%d].%s 类型错误（期望 int）" % [player_id, employee_id])
	var m: int = int(m_val)
	assert(m > 0, "round_state.working_employee_multipliers[%d].%s 必须 > 0" % [player_id, employee_id])
	return m

