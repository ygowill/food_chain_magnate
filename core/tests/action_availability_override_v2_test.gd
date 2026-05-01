# Action availability override smoke test（M5+）
class_name ActionAvailabilityOverrideV2Test
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const ActionAvailabilityRegistryClass = preload("res://core/actions/action_availability_registry.gd")
const RulesetV2Class = preload("res://core/modules/v2/ruleset.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var semantic_r := _test_invalid_override_points_fail()
	if not semantic_r.ok:
		return semantic_r

	var malformed_r := _test_malformed_override_item_fails_action_wiring()
	if not malformed_r.ok:
		return malformed_r

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
	state.phase = DefsClass.PHASE_WORKING

	# Train 子阶段：应能看到 recruit（被模组覆盖）
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN
	var actions_train := engine.get_available_actions()
	if not actions_train.has("recruit"):
		return Result.failure("Working/Train 应包含 recruit（override 生效），实际: %s" % str(actions_train))

	# Recruit 子阶段：应不可用
	state.sub_phase = DefsClass.SUB_PHASE_RECRUIT
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

static func _test_invalid_override_points_fail() -> Result:
	var unknown_phase_r := _assert_override_compile_fails(
		[{"phase": "BadPhase", "sub_phase": ""}],
		"未知 phase"
	)
	if not unknown_phase_r.ok:
		return unknown_phase_r

	var unknown_working_sub_phase_r := _assert_override_compile_fails(
		[{"phase": DefsClass.PHASE_WORKING, "sub_phase": "BadSubPhase"}],
		"不包含 sub_phase"
	)
	if not unknown_working_sub_phase_r.ok:
		return unknown_working_sub_phase_r

	var invalid_setup_sub_phase_r := _assert_override_compile_fails(
		[{"phase": DefsClass.PHASE_SETUP, "sub_phase": DefsClass.SUB_PHASE_PLACE_RESTAURANTS}],
		"Setup 不包含 sub_phase"
	)
	if not invalid_setup_sub_phase_r.ok:
		return invalid_setup_sub_phase_r

	return Result.success()

static func _assert_override_compile_fails(points: Array, expected_error_fragment: String) -> Result:
	var registry := ActionAvailabilityRegistryClass.new()
	var reg_r := registry.register_action_points_override("recruit", points, 100, "test")
	if not reg_r.ok:
		return Result.failure("register_action_points_override 失败: %s" % reg_r.error)
	var compile_r := registry.compile_with_validation(["recruit"], PhaseManager.new())
	if compile_r.ok:
		return Result.failure("非法 action availability override 应编译失败: %s" % str(points))
	if str(compile_r.error).find(expected_error_fragment) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [expected_error_fragment, compile_r.error])
	return Result.success()

static func _test_malformed_override_item_fails_action_wiring() -> Result:
	var engine := GameEngine.new()
	engine.ruleset_v2 = RulesetV2Class.new()
	engine.ruleset_v2.action_availability_overrides.append({
		"action_id": "recruit",
		"points": "bad",
		"priority": 100,
		"source": "test",
	})
	var setup_r := engine.setup_action_registry({})
	if setup_r.ok:
		return Result.failure("malformed action_availability_override item 应导致 action wiring 失败")
	if str(setup_r.error).find("points") < 0:
		return Result.failure("错误信息应包含 points，实际: %s" % setup_r.error)
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
