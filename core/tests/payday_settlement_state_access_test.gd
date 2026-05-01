# payday settlement 状态访问回归测试
class_name PaydaySettlementStateAccessTest
extends RefCounted

const PaydaySettlementClass = preload("res://modules/base_rules/rules/phase/payday_settlement.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count < 2:
		player_count = 2

	var recruit_key_r := _test_recruit_used_string_key_fails_fast(player_count, seed_val)
	if not recruit_key_r.ok:
		return recruit_key_r

	var inventory_r := _test_inventory_malformed_fails_fast(player_count, seed_val + 17)
	if not inventory_r.ok:
		return inventory_r

	return Result.success({"cases": 2})

static func _test_recruit_used_string_key_fails_fast(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.round_state["recruit_used"] = {
		"0": 1,
		0: 0,
	}
	var players_before := str(state.players)
	var bank_before := str(state.bank)
	var round_state_before := str(state.round_state)

	var apply := PaydaySettlementClass.apply(state, engine.phase_manager)
	if apply.ok:
		return Result.failure("recruit_used 使用字符串玩家 key 时应失败")
	var err := str(apply.error)
	if err.find("recruit_used") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("错误信息应包含 recruit_used 与 字符串玩家 key，实际: %s" % err)
	if str(state.players) != players_before:
		return Result.failure("失败时不应提前改写 players")
	if str(state.bank) != bank_before:
		return Result.failure("失败时不应提前改写 bank")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	return Result.success()

static func _test_inventory_malformed_fails_fast(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化 inventory malformed 用例失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.players[0]["inventory"] = []
	var players_before := str(state.players)
	var bank_before := str(state.bank)
	var round_state_before := str(state.round_state)

	var apply := PaydaySettlementClass.apply(state, engine.phase_manager)
	if apply.ok:
		return Result.failure("player.inventory 类型错误时 PaydaySettlement 不应自动修补为 {}")
	var err := str(apply.error)
	if err.find("inventory") < 0 or err.find("Dictionary") < 0:
		return Result.failure("错误信息应包含 inventory 与 Dictionary，实际: %s" % err)
	if str(state.players) != players_before:
		return Result.failure("inventory 类型错误失败时不应改写 players")
	if str(state.bank) != bank_before:
		return Result.failure("inventory 类型错误失败时不应改写 bank")
	if str(state.round_state) != round_state_before:
		return Result.failure("inventory 类型错误失败时不应改写 round_state")

	return Result.success()
