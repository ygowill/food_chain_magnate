extends RefCounted

static func try_get_working_employee_multiplier(state: GameState, player_id: int, employee_id: String) -> Result:
	# 扩展点：工作阶段中“有效员工数量”乘数（模块可写入 round_state.working_employee_multipliers）。
	# round_state.working_employee_multipliers: player_id -> { employee_id -> multiplier }
	if state == null:
		return Result.failure("working_multiplier: state 为空")
	if employee_id.is_empty():
		return Result.failure("working_multiplier: employee_id 不能为空")
	if not (state.round_state is Dictionary):
		return Result.failure("working_multiplier: round_state 类型错误（期望 Dictionary）")
	var val = state.round_state.get("working_employee_multipliers", null)
	if val == null:
		return Result.success(1)
	if not (val is Dictionary):
		return Result.failure("round_state.working_employee_multipliers 类型错误（期望 Dictionary）")
	var all: Dictionary = val
	if all.has(str(player_id)):
		return Result.failure("round_state.working_employee_multipliers 不应包含字符串玩家 key: %s" % str(player_id))
	if not all.has(player_id):
		return Result.success(1)
	var per_val = all[player_id]
	if not (per_val is Dictionary):
		return Result.failure("round_state.working_employee_multipliers[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val
	if not per_player.has(employee_id):
		return Result.success(1)
	var m_val = per_player[employee_id]
	if not (m_val is int):
		return Result.failure("round_state.working_employee_multipliers[%d].%s 类型错误（期望 int）" % [player_id, employee_id])
	var m: int = int(m_val)
	if m <= 0:
		return Result.failure("round_state.working_employee_multipliers[%d].%s 必须 > 0" % [player_id, employee_id])
	return Result.success(m)

static func get_working_employee_multiplier(state: GameState, player_id: int, employee_id: String) -> int:
	if state == null:
		return 1
	var read := try_get_working_employee_multiplier(state, player_id, employee_id)
	if not read.ok:
		return 1
	return int(read.value)

