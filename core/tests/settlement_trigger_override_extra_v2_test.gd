# Settlement trigger override extra tests（M5+）
class_name SettlementTriggerOverrideExtraV2Test
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var r1 := _test_invalid_required_fails(player_count, seed)
	if not r1.ok:
		return r1
	var r2 := _test_exit_trigger_runs(player_count, seed)
	if not r2.ok:
		return r2
	var r3 := _test_multiple_points_order(player_count, seed)
	if not r3.ok:
		return r3
	return Result.success()

static func _test_invalid_required_fails(player_count: int, seed: int) -> Result:
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
		"settlement_trigger_override_invalid_required",
	], "res://modules;res://modules_test")
	if init.ok:
		return Result.failure("移除 Dinnertime:enter 映射后应 init fail")
	if init.error.find("未配置结算触发点") < 0:
		return Result.failure("错误信息应包含“未配置结算触发点”，实际: %s" % init.error)
	if init.error.find("Dinnertime:enter") < 0:
		return Result.failure("错误信息应包含“Dinnertime:enter”，实际: %s" % init.error)
	return Result.success()

static func _test_exit_trigger_runs(player_count: int, seed: int) -> Result:
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
		"settlement_trigger_override_exit_test",
	], "res://modules;res://modules_test")
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# Setup -> Restructuring
	var adv0 := engine.execute_command(Command.create_system("advance_phase"))
	if not adv0.ok:
		return Result.failure("推进到 Restructuring 失败: %s" % adv0.error)
	# Restructuring -> OrderOfBusiness（离开 Restructuring 时触发 exit settlement）
	var adv1 := engine.execute_command(Command.create_system("advance_phase"))
	if not adv1.ok:
		return Result.failure("推进到 OrderOfBusiness 失败: %s" % adv1.error)

	var rs: Dictionary = engine.get_state().round_state
	if not bool(rs.get("restructuring_exit_settled", false)):
		return Result.failure("Restructuring exit settlement 未被触发")
	return Result.success()

static func _test_multiple_points_order(player_count: int, seed: int) -> Result:
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
		"settlement_trigger_override_points_order_test",
	], "res://modules;res://modules_test")
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_mk := TestPhaseUtilsClass.advance_until_phase(engine, "Marketing", 80)
	if not to_mk.ok:
		return to_mk

	if engine.get_state().phase != "Marketing":
		return Result.failure("当前应为 Marketing，实际: %s" % engine.get_state().phase)
	var rs: Dictionary = engine.get_state().round_state
	var arr: Array = rs.get("points_order", [])
	if arr.size() != 2 or str(arr[0]) != "enter" or str(arr[1]) != "exit":
		return Result.failure("points 顺序/触发不符合预期: %s" % str(arr))
	return Result.success()
