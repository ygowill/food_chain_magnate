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
	if engine.get_state().sub_phase != "Train":
		return Result.failure("进入 Working 后子阶段应为 Train（override），实际: %s" % engine.get_state().sub_phase)

	return Result.success({
		"working_sub_phase_order": order,
	})
