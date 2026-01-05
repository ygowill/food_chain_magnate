# 阶段顺序 override smoke test（M5+）
class_name PhaseOrderOverrideV2Test
extends RefCounted

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
		"phase_order_override_test",
	], "res://modules;res://modules_test")
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var order: Array[String] = engine.phase_manager.get_phase_order_names()
	var expected: Array[String] = [
		"Restructuring",
		"OrderOfBusiness",
		"Working",
		"Dinnertime",
		"Marketing",
		"Payday",
		"Cleanup",
	]
	if order != expected:
		return Result.failure("phase_order override 未生效: %s != %s" % [str(order), str(expected)])

	# 同时验证 timestamp 会基于 round_state.phase_order（由 initialize 写入）
	var ts0 := PhaseManager.compute_timestamp(engine.get_state())
	if ts0 != 0:
		return Result.failure("Setup timestamp 应为 0，实际: %d" % ts0)

	var adv := engine.execute_command(Command.create_system("advance_phase"))
	if not adv.ok:
		return Result.failure("推进阶段失败: %s" % adv.error)
	var ts1 := PhaseManager.compute_timestamp(engine.get_state())
	if ts1 != 1100:
		return Result.failure("Restructuring timestamp 应为 1100，实际: %d" % ts1)

	return Result.success({
		"phase_order": order,
	})
