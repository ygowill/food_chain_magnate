# 非 Working/Cleanup 阶段子阶段 smoke test（M5+）
class_name PaydaySubPhaseV2Test
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
		"payday_sub_phase_test",
	], "res://modules;res://modules_test")
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_payday := TestPhaseUtilsClass.advance_until_phase(engine, "Payday", 80)
	if not to_payday.ok:
		return to_payday
	if engine.get_state().sub_phase != "PaydayExtra":
		return Result.failure("进入 Payday 后子阶段应为 PaydayExtra，实际: %s" % engine.get_state().sub_phase)
	if not bool(engine.get_state().round_state.get("payday_extra_entered", false)):
		return Result.failure("PaydayExtra BEFORE_ENTER hook 未触发")

	# 遵循 advance_phase_action 的门禁：所有玩家必须 pass 才能推进子阶段（这里直接标记）
	var rs: Dictionary = engine.get_state().round_state
	if not rs.has("sub_phase_passed") or not (rs["sub_phase_passed"] is Dictionary):
		return Result.failure("round_state.sub_phase_passed 缺失或类型错误")
	var passed: Dictionary = rs["sub_phase_passed"]
	for pid in range(engine.get_state().players.size()):
		passed[pid] = true

	var adv := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
	if not adv.ok:
		return Result.failure("推进 Payday 子阶段失败: %s" % adv.error)
	if engine.get_state().phase != "Restructuring":
		return Result.failure("推进子阶段后应进入 Restructuring（Marketing/Cleanup 已自动结算跳过），实际: %s" % engine.get_state().phase)
	return Result.success()
