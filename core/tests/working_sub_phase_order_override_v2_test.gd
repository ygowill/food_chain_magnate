# Working 子阶段顺序 override smoke test（M5+）
class_name WorkingSubPhaseOrderOverrideV2Test
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

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
		"working_sub_phase_order_override_test",
	], "res://modules;res://modules_test")
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var order: Array[String] = engine.phase_manager.get_working_sub_phase_order_names()
	if order.size() < 2 or order[0] != "Train" or order[1] != "Recruit":
		return Result.failure("working_sub_phase_order override 未生效: %s" % str(order))

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working
	var state := engine.get_state()
	var rs_val = state.round_state.get("working_sub_phase_order", [])
	if not (rs_val is Array):
		return Result.failure("round_state.working_sub_phase_order 缺失或类型错误（期望 Array）")
	var rs: Array = rs_val
	if rs.size() < 2 or str(rs[0]) != "Train" or str(rs[1]) != "Recruit":
		return Result.failure("round_state.working_sub_phase_order 未按 override 初始化: %s" % str(rs))

	return Result.success({
		"working_sub_phase_order": order,
	})
