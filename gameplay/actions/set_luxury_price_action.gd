# 设定奢侈品价格动作（奢侈品经理的强制动作）
# 激活奢侈品经理效果：基础单价 +$10
class_name SetLuxuryPriceAction
extends ActionExecutor

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

func _init() -> void:
	action_id = "set_luxury_price"
	display_name = "设定奢侈品价格"
	description = "激活奢侈品经理效果（+$10）"
	requires_actor = true
	is_mandatory = true
	allowed_phases = ["Working"]
	allowed_sub_phases = []  # 任何子阶段都可以执行

func _validate_specific(state: GameState, command: Command) -> Result:
	var player_id := command.actor

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if player_id != current_player_id:
		return Result.failure("不是你的回合")

	# 检查玩家是否有奢侈品经理
	var player := state.get_player(player_id)
	if _find_mandatory_action_provider_employee_id(player, action_id).is_empty():
		return Result.failure("玩家没有奢侈品经理")

	# 检查本回合是否已执行此动作
	if _has_completed_this_round(state, player_id):
		return Result.failure("本回合已设定奢侈品价格")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id := command.actor
	var player := state.get_player(player_id)
	var provider_id := _find_mandatory_action_provider_employee_id(player, action_id)
	if provider_id.is_empty():
		return Result.failure("玩家没有奢侈品经理")

	# 记录强制动作已完成
	_mark_mandatory_completed(state, player_id)

	# 设置价格修正（存储在 round_state 中）
	if not state.round_state.has("price_modifiers"):
		state.round_state["price_modifiers"] = {}
	if not state.round_state.price_modifiers.has(player_id):
		state.round_state.price_modifiers[player_id] = {}

	state.round_state.price_modifiers[player_id][provider_id] = 10

	return Result.success({
		"player_id": player_id,
		"modifier": 10
	})

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	events.append({
		"type": EventBus.EventType.COMMAND_EXECUTED,
		"data": {
			"action_id": action_id,
			"player_id": command.actor,
			"mandatory": true,
			"price_modifier": 10
		}
	})

	return events

# === 辅助方法 ===

func _find_mandatory_action_provider_employee_id(player: Dictionary, mandatory_action_id: String) -> String:
	if mandatory_action_id.is_empty():
		return ""
	assert(player.has("employees") and (player["employees"] is Array), "set_luxury_price: player.employees 缺失或类型错误（期望 Array[String]）")
	var employees: Array = player["employees"]
	for i in range(employees.size()):
		var emp_val = employees[i]
		assert(emp_val is String, "set_luxury_price: player.employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = emp_val
		assert(not emp_id.is_empty(), "set_luxury_price: player.employees[%d] 不应为空字符串" % i)
		var def = EmployeeRegistryClass.get_def(emp_id)
		if def != null and def is EmployeeDef:
			var emp_def: EmployeeDef = def
			if emp_def.mandatory_action_id == mandatory_action_id:
				return emp_id
	return ""

func _has_completed_this_round(state: GameState, player_id: int) -> bool:
	assert(state.round_state is Dictionary, "set_luxury_price: state.round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("mandatory_actions_completed"), "set_luxury_price: round_state 缺少 mandatory_actions_completed")
	var mac_val = state.round_state["mandatory_actions_completed"]
	assert(mac_val is Dictionary, "set_luxury_price: round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mac: Dictionary = mac_val
	assert(mac.has(player_id), "set_luxury_price: mandatory_actions_completed 缺少玩家 key: %d" % player_id)
	var completed_val = mac[player_id]
	assert(completed_val is Array, "set_luxury_price: mandatory_actions_completed[%d] 类型错误（期望 Array）" % player_id)
	var completed: Array = completed_val
	return completed.has(action_id)

func _mark_mandatory_completed(state: GameState, player_id: int) -> void:
	assert(state.round_state is Dictionary, "set_luxury_price: state.round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("mandatory_actions_completed"), "set_luxury_price: round_state 缺少 mandatory_actions_completed")
	var mac_val = state.round_state["mandatory_actions_completed"]
	assert(mac_val is Dictionary, "set_luxury_price: round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mac: Dictionary = mac_val
	assert(mac.has(player_id), "set_luxury_price: mandatory_actions_completed 缺少玩家 key: %d" % player_id)
	var completed_val = mac[player_id]
	assert(completed_val is Array, "set_luxury_price: mandatory_actions_completed[%d] 类型错误（期望 Array）" % player_id)
	var completed: Array = completed_val
	if not completed.has(action_id):
		completed.append(action_id)
