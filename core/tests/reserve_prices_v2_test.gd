# 模块14：储备价格（Reserve Prices）
class_name ReservePricesV2Test
extends RefCounted

const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_first_break_sets_base_price_tie_20_wins(seed_val)
	if not r.ok:
		return r
	r = _test_first_break_sets_base_price_tie_5_wins_over_10(seed_val)
	if not r.ok:
		return r

	return Result.success()

static func _make_engine(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"reserve_prices",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	return Result.success(e)

static func _force_first_break(e: GameEngine) -> Result:
	var s: GameState = e.get_state()
	# 强制破产：将银行置 0 并要求支付 1
	s.bank["total"] = 0
	var before: int = int(s.bank["reserve_added_total"])
	var r := BankruptcyRulesClass.ensure_bank_can_pay(s, 1, "test")
	if not r.ok:
		return r
	if int(s.bank.get("broke_count", -1)) != 1:
		return Result.failure("第一次破产后 broke_count 应为 1，实际: %s" % str(s.bank.get("broke_count", null)))
	var added := int(s.bank.get("reserve_added_total", 0)) - before
	if added != 400:
		return Result.failure("第一次破产注资应为 $200/人（2人=$400），实际增加: %d" % added)
	return Result.success()

static func _test_first_break_sets_base_price_tie_20_wins(seed_val: int) -> Result:
	var er := _make_engine(seed_val)
	if not er.ok:
		return er
	var e: GameEngine = er.value
	var s: GameState = e.get_state()

	# 伪造储备卡选择：玩家0选5，玩家1选20 -> 平局按 20 胜出
	s.players[0]["reserve_cards"] = [{"type": 5}, {"type": 10}, {"type": 20}]
	s.players[0]["reserve_card_selected"] = 0
	s.players[0]["reserve_card_revealed"] = false
	s.players[1]["reserve_cards"] = [{"type": 20}, {"type": 10}, {"type": 5}]
	s.players[1]["reserve_card_selected"] = 0
	s.players[1]["reserve_card_revealed"] = false

	var ceo0_before: int = int(s.players[0]["company_structure"]["ceo_slots"])
	var ceo1_before: int = int(s.players[1]["company_structure"]["ceo_slots"])

	var r := _force_first_break(e)
	if not r.ok:
		return r

	if int(s.rules.get("base_unit_price", -1)) != 20:
		return Result.failure("base_unit_price 应变为 20（平局 20 胜出），实际: %s" % str(s.rules.get("base_unit_price", null)))

	# CEO 卡槽不应变化
	if int(s.players[0]["company_structure"]["ceo_slots"]) != ceo0_before:
		return Result.failure("Reserve Prices 不应修改 CEO 卡槽数（player0）")
	if int(s.players[1]["company_structure"]["ceo_slots"]) != ceo1_before:
		return Result.failure("Reserve Prices 不应修改 CEO 卡槽数（player1）")

	if not bool(s.players[0].get("reserve_card_revealed", false)) or not bool(s.players[1].get("reserve_card_revealed", false)):
		return Result.failure("第一次破产后 reserve_card_revealed 应为 true")

	return Result.success()

static func _test_first_break_sets_base_price_tie_5_wins_over_10(seed_val: int) -> Result:
	var er := _make_engine(seed_val + 1)
	if not er.ok:
		return er
	var e: GameEngine = er.value
	var s: GameState = e.get_state()

	# 平局 5 vs 10 -> 5 胜出
	s.players[0]["reserve_cards"] = [{"type": 5}, {"type": 10}, {"type": 20}]
	s.players[0]["reserve_card_selected"] = 0
	s.players[0]["reserve_card_revealed"] = false
	s.players[1]["reserve_cards"] = [{"type": 10}, {"type": 20}, {"type": 5}]
	s.players[1]["reserve_card_selected"] = 0
	s.players[1]["reserve_card_revealed"] = false

	var r := _force_first_break(e)
	if not r.ok:
		return r

	if int(s.rules.get("base_unit_price", -1)) != 5:
		return Result.failure("base_unit_price 应变为 5（平局 5 胜出 10），实际: %s" % str(s.rules.get("base_unit_price", null)))

	return Result.success()

