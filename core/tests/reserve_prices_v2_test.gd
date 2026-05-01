# 模块14：储备价格（Reserve Prices）
class_name ReservePricesV2Test
extends RefCounted

const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const EntryClass = preload("res://modules/reserve_prices/rules/entry.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_setup_uses_alternate_reserve_cards(seed_val)
	if not r.ok:
		return r
	r = _test_init_state_preserves_valid_existing_selected()
	if not r.ok:
		return r
	r = _test_init_state_rejects_out_of_range_existing_selected_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_init_state_rejects_non_int_existing_selected_without_partial_mutation()
	if not r.ok:
		return r

	r = _test_first_break_sets_base_price_tie_20_wins(seed_val)
	if not r.ok:
		return r
	r = _test_first_break_sets_base_price_tie_5_wins_over_10(seed_val)
	if not r.ok:
		return r
	r = _test_first_break_rejects_invalid_bankruptcy_events_without_partial_mutation(seed_val)
	if not r.ok:
		return r

	return Result.success()

static func _test_init_state_preserves_valid_existing_selected() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [
		{
			"reserve_cards": [{"type": 99}],
			"reserve_card_selected": 2,
			"reserve_card_revealed": true,
		},
		{
			"reserve_card_selected": -1,
		},
	]

	var r := entry._init_state(state, null)
	if not r.ok:
		return Result.failure("_init_state 不应拒绝合法 reserve_card_selected: %s" % r.error)
	if int(state.players[0].get("reserve_card_selected", -999)) != 2:
		return Result.failure("合法 reserve_card_selected 应保留，实际: %s" % str(state.players[0].get("reserve_card_selected", null)))
	if int(state.players[1].get("reserve_card_selected", -999)) != -1:
		return Result.failure("-1 应保留为未选择，实际: %s" % str(state.players[1].get("reserve_card_selected", null)))
	if bool(state.players[0].get("reserve_card_revealed", true)):
		return Result.failure("_init_state 应将 reserve_card_revealed 设为 false")
	return _assert_reserve_price_cards(state.players[0].get("reserve_cards", null), "players[0].reserve_cards")

static func _test_init_state_rejects_out_of_range_existing_selected_without_partial_mutation() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [
		{
			"reserve_cards": [{"type": 99}],
			"reserve_card_selected": 3,
			"reserve_card_revealed": true,
		},
		{
			"reserve_card_selected": -1,
		},
	]
	var before := str(state.players)

	var r := entry._init_state(state, null)
	if r.ok:
		return Result.failure("越界 reserve_card_selected 应失败")
	var err := str(r.error)
	if err.find("reserve_card_selected") < 0 or err.find("越界") < 0:
		return Result.failure("错误信息应包含 reserve_card_selected 越界，实际: %s" % err)
	if str(state.players) != before:
		return Result.failure("失败时不应把非法 reserve_card_selected 重置或半初始化 reserve_cards")
	return Result.success()

static func _test_init_state_rejects_non_int_existing_selected_without_partial_mutation() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [
		{
			"reserve_cards": [{"type": 99}],
			"reserve_card_selected": 1.0,
			"reserve_card_revealed": true,
		},
		{
			"reserve_card_selected": -1,
		},
	]
	var before := str(state.players)

	var r := entry._init_state(state, null)
	if r.ok:
		return Result.failure("非 int reserve_card_selected 应失败")
	var err := str(r.error)
	if err.find("reserve_card_selected") < 0 or err.find("类型错误") < 0:
		return Result.failure("错误信息应包含 reserve_card_selected 类型错误，实际: %s" % err)
	if str(state.players) != before:
		return Result.failure("失败时不应把非法 reserve_card_selected 重置或半初始化 reserve_cards")
	return Result.success()

static func _assert_reserve_price_cards(cards_val, path: String) -> Result:
	if not (cards_val is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	var cards: Array = cards_val
	var expected_order: Array[int] = [5, 10, 20]
	if cards.size() != expected_order.size():
		return Result.failure("%s 张数错误，实际: %d" % [path, cards.size()])
	for i in range(expected_order.size()):
		var card_val = cards[i]
		if not (card_val is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		var card: Dictionary = card_val
		if int(card.get("type", -1)) != expected_order[i]:
			return Result.failure("%s 顺序应为 [5,10,20]，实际: %s" % [path, str(cards)])
		if card.has("cash") or card.has("ceo_slots"):
			return Result.failure("%s[%d] 不应包含 cash/ceo_slots" % [path, i])
	return Result.success()

static func _test_setup_uses_alternate_reserve_cards(seed_val: int) -> Result:
	var er := _make_engine(seed_val)
	if not er.ok:
		return er
	var e: GameEngine = er.value
	var s: GameState = e.get_state()

	# 开局应在 Setup/ReserveCards；并且 reserve_cards 使用模块14的替代卡（仅含 type，不含 cash/ceo_slots）
	if str(s.phase) != "Setup":
		return Result.failure("开局 phase 应为 Setup，实际: %s" % str(s.phase))
	if str(s.sub_phase) != "ReserveCards":
		return Result.failure("开局 sub_phase 应为 ReserveCards，实际: %s" % str(s.sub_phase))

	for pid in range(s.players.size()):
		var p_val = s.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("players[%d] 类型错误（期望 Dictionary）" % pid)
		var p: Dictionary = p_val

		var cards_val = p.get("reserve_cards", null)
		if not (cards_val is Array):
			return Result.failure("players[%d].reserve_cards 类型错误（期望 Array）" % pid)
		var cards: Array = cards_val
		if cards.size() != 3:
			return Result.failure("players[%d].reserve_cards 张数应为 3，实际: %d" % [pid, cards.size()])
		for i in range(cards.size()):
			var c_val = cards[i]
			if not (c_val is Dictionary):
				return Result.failure("players[%d].reserve_cards[%d] 类型错误（期望 Dictionary）" % [pid, i])
			var c: Dictionary = c_val
			if not c.has("type") or not (c.get("type", null) is int):
				return Result.failure("players[%d].reserve_cards[%d].type 缺失或类型错误（期望 int）" % [pid, i])
			var t: int = int(c["type"])
			if t != 5 and t != 10 and t != 20:
				return Result.failure("players[%d].reserve_cards[%d].type 非法（期望 5/10/20），实际: %d" % [pid, i, t])
			if c.has("cash") or c.has("ceo_slots"):
				return Result.failure("players[%d].reserve_cards[%d] 不应包含 cash/ceo_slots（应为替代储备卡）" % [pid, i])
		var expected_order: Array[int] = [5, 10, 20]
		for i in range(expected_order.size()):
			var c: Dictionary = cards[i]
			var actual_t: int = int(c.get("type", -1))
			var expected_t: int = expected_order[i]
			if actual_t != expected_t:
				return Result.failure("players[%d].reserve_cards 顺序应为 [5,10,20]，实际: %s" % [pid, str(cards)])

		# 仍需在 Setup/ReserveCards 由玩家选择；开局不应自动选中
		if int(p.get("reserve_card_selected", -999)) != -1:
			return Result.failure("players[%d].reserve_card_selected 开局应为 -1（未选择），实际: %s" % [pid, str(p.get("reserve_card_selected", null))])
		if bool(p.get("reserve_card_revealed", true)):
			return Result.failure("players[%d].reserve_card_revealed 开局应为 false" % pid)

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

static func _test_first_break_rejects_invalid_bankruptcy_events_without_partial_mutation(seed_val: int) -> Result:
	var er := _make_engine(seed_val + 2)
	if not er.ok:
		return er
	var e: GameEngine = er.value
	var s: GameState = e.get_state()

	s.players[0]["reserve_cards"] = [{"type": 5}, {"type": 10}, {"type": 20}]
	s.players[0]["reserve_card_selected"] = 0
	s.players[0]["reserve_card_revealed"] = false
	s.players[1]["reserve_cards"] = [{"type": 20}, {"type": 10}, {"type": 5}]
	s.players[1]["reserve_card_selected"] = 0
	s.players[1]["reserve_card_revealed"] = false
	s.round_state["bankruptcy"] = {
		"events": {},
	}
	s.bank["total"] = 0

	var players_before := str(s.players)
	var bank_before := str(s.bank)
	var rules_before := str(s.rules)
	var round_state_before := str(s.round_state)

	var r := BankruptcyRulesClass.ensure_bank_can_pay(s, 1, "test")
	if r.ok:
		return Result.failure("bankruptcy.events 类型错误时应失败")
	var err := str(r.error)
	if err.find("bankruptcy.events") < 0:
		return Result.failure("错误信息应包含 bankruptcy.events，实际: %s" % err)
	if str(s.players) != players_before:
		return Result.failure("失败时不应提前揭示储备卡或改写玩家状态")
	if str(s.bank) != bank_before:
		return Result.failure("失败时不应提前改写 bank 状态")
	if str(s.rules) != rules_before:
		return Result.failure("失败时不应提前改写 rules")
	if str(s.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")

	return Result.success()
