# Settlement trigger override smoke test（M5+）
class_name SettlementTriggerOverrideV2Test
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
		"settlement_trigger_override_test",
	], "res://modules;res://modules_test")
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# Restructuring -> OrderOfBusiness（触发 enter settlement）
	var state := engine.get_state()
	state.round_number = 2
	state.phase = "Restructuring"
	state.sub_phase = ""

	var adv1 := engine.execute_command(Command.create_system("advance_phase"))
	if not adv1.ok:
		return Result.failure("推进到 OrderOfBusiness 失败: %s" % adv1.error)
	if engine.get_state().phase != "OrderOfBusiness":
		return Result.failure("当前应为 OrderOfBusiness，实际: %s" % engine.get_state().phase)

	var rs: Dictionary = engine.get_state().round_state
	if not bool(rs.get("oob_enter_settled", false)):
		return Result.failure("OrderOfBusiness enter settlement 未被触发")

	return Result.success()
