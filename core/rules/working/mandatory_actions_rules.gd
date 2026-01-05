# 强制动作规则（从 PhaseManager 抽离）
# 目标：集中管理“哪些员工需要强制动作”与“离开 Working 前是否已完成”的校验逻辑。
class_name MandatoryActionsRules
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

# 检查所有玩家是否完成了必须的强制动作
static func check_mandatory_actions_completed(state: GameState) -> Result:
	if state == null:
		return Result.failure("MandatoryActionsRules: state 为空")
	if not (state.players is Array):
		return Result.failure("MandatoryActionsRules: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("MandatoryActionsRules: state.round_state 类型错误（期望 Dictionary）")

	if not state.round_state.has("mandatory_actions_completed"):
		return Result.failure("MandatoryActionsRules: round_state.mandatory_actions_completed 缺失")
	var mac_val = state.round_state["mandatory_actions_completed"]
	if not (mac_val is Dictionary):
		return Result.failure("MandatoryActionsRules: round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mandatory_actions_completed: Dictionary = mac_val

	var missing_actions: Array[Dictionary] = []

	for player_id in range(state.players.size()):
		var player_val = state.players[player_id]
		if not (player_val is Dictionary):
			return Result.failure("MandatoryActionsRules: players[%d] 类型错误（期望 Dictionary）" % player_id)
		var player: Dictionary = player_val

		var required := get_required_mandatory_actions(player)
		if not mandatory_actions_completed.has(player_id):
			return Result.failure("MandatoryActionsRules: mandatory_actions_completed 缺少玩家 key: %d" % player_id)
		var completed_val = mandatory_actions_completed[player_id]
		if not (completed_val is Array):
			return Result.failure("MandatoryActionsRules: mandatory_actions_completed[%d] 类型错误（期望 Array）" % player_id)
		var completed: Array = completed_val

		for action_id in required:
			if not completed.has(action_id):
				missing_actions.append({
					"player_id": player_id,
					"action_id": action_id
				})

	if missing_actions.is_empty():
		return Result.success()

	# 构建错误消息
	var error_parts: Array[String] = []
	for missing in missing_actions:
		error_parts.append("玩家 %d 未完成: %s" % [missing.player_id, missing.action_id])

	return Result.failure("存在未完成的强制动作: %s" % ", ".join(error_parts))

# 获取玩家必须执行的强制动作列表
static func get_required_mandatory_actions(player: Dictionary) -> Array[String]:
	var required: Array[String] = []
	assert(player.has("employees") and (player["employees"] is Array), "MandatoryActionsRules.get_required_mandatory_actions: player.employees 缺失或类型错误（期望 Array[String]）")
	var employees: Array = player["employees"]

	for i in range(employees.size()):
		var emp_val = employees[i]
		assert(emp_val is String, "MandatoryActionsRules.get_required_mandatory_actions: player.employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = emp_val
		assert(not emp_id.is_empty(), "MandatoryActionsRules.get_required_mandatory_actions: player.employees[%d] 不应为空字符串" % i)

		var emp_def = EmployeeRegistryClass.get_def(emp_id)
		assert(emp_def != null, "MandatoryActionsRules.get_required_mandatory_actions: 未知员工类型: %s" % emp_id)

		if emp_def.mandatory:
			var action_id: String = str(emp_def.mandatory_action_id)
			if action_id.is_empty():
				continue  # 自动应用，无需动作
			if not required.has(action_id):
				required.append(action_id)

	return required

# 获取所有玩家的强制动作状态（用于 UI 显示）
static func get_mandatory_actions_status(state: GameState) -> Result:
	if state == null:
		return Result.failure("MandatoryActionsRules: state 为空")
	if not (state.players is Array):
		return Result.failure("MandatoryActionsRules: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("MandatoryActionsRules: state.round_state 类型错误（期望 Dictionary）")

	if not state.round_state.has("mandatory_actions_completed"):
		return Result.failure("MandatoryActionsRules: round_state.mandatory_actions_completed 缺失")
	var mac_val = state.round_state["mandatory_actions_completed"]
	if not (mac_val is Dictionary):
		return Result.failure("MandatoryActionsRules: round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mandatory_actions_completed: Dictionary = mac_val

	var status: Dictionary = {}

	for player_id in range(state.players.size()):
		var player_val = state.players[player_id]
		if not (player_val is Dictionary):
			return Result.failure("MandatoryActionsRules: players[%d] 类型错误（期望 Dictionary）" % player_id)
		var player: Dictionary = player_val

		var required := get_required_mandatory_actions(player)
		if not mandatory_actions_completed.has(player_id):
			return Result.failure("MandatoryActionsRules: mandatory_actions_completed 缺少玩家 key: %d" % player_id)
		var completed_val = mandatory_actions_completed[player_id]
		if not (completed_val is Array):
			return Result.failure("MandatoryActionsRules: mandatory_actions_completed[%d] 类型错误（期望 Array）" % player_id)
		var completed: Array = completed_val

		var player_status: Array[Dictionary] = []
		for action_id in required:
			player_status.append({
				"action_id": action_id,
				"completed": completed.has(action_id)
			})

		status[player_id] = player_status

	return Result.success(status)
