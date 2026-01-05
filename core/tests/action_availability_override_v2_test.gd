# Action availability override smoke test（M5+）
class_name ActionAvailabilityOverrideV2Test
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"action_availability_override_test",
	], "res://modules;res://modules_test")
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	state.phase = "Working"

	# Train 子阶段：应能看到 recruit（被模组覆盖）
	state.sub_phase = "Train"
	var actions_train := engine.get_available_actions()
	if not actions_train.has("recruit"):
		return Result.failure("Working/Train 应包含 recruit（override 生效），实际: %s" % str(actions_train))

	# Recruit 子阶段：应不可用
	state.sub_phase = "Recruit"
	var actions_recruit := engine.get_available_actions()
	if actions_recruit.has("recruit"):
		return Result.failure("Working/Recruit 不应包含 recruit（override 生效），实际: %s" % str(actions_recruit))

	# 执行时也必须被拦截（Fail Fast）
	var cmd := Command.create("recruit", state.get_current_player_id(), {
		"employee_type": _pick_any_entry_level_employee_id(state),
	})
	var exec_r := engine.execute_command(cmd)
	if exec_r.ok:
		return Result.failure("Working/Recruit 执行 recruit 应失败，但实际成功")

	return Result.success()

static func _pick_any_entry_level_employee_id(state: GameState) -> String:
	var keys: Array = state.employee_pool.keys()
	keys.sort()
	for k in keys:
		if not (k is String):
			continue
		var emp_id: String = str(k)
		if emp_id.is_empty():
			continue
		if EmployeeRulesClass.is_entry_level(emp_id):
			return emp_id
	return str(keys[0])
