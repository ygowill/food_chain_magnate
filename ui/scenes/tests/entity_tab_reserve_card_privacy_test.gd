# EntityTab：玩家详情不泄露他人储备卡信息（reserve_cards）
extends RefCounted

const EntityTabScript = preload("res://ui/scenes/debug/tabs/entity_tab.gd")

static func run() -> Result:
	var engine := GameEngine.new()
	var init: Result = engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	# 固定他人储备卡（便于断言）
	state.players[1]["reserve_cards"] = [{"type": 5}, {"type": 10}, {"type": 20}]
	state.players[1]["reserve_card_selected"] = 1
	state.players[1]["reserve_card_revealed"] = false
	state.players[0]["can_peek_all_reserve_cards"] = false

	var tab = EntityTabScript.new()
	if tab == null or not is_instance_valid(tab):
		return Result.failure("实例化 EntityTab 失败")

	# 未揭示：应隐藏 reserve_cards 与 reserve_card_selected
	var sanitized: Dictionary = tab._sanitize_player_dict_for_viewer(state.players[1], 1, 0, state)
	if str(sanitized.get("reserve_card_selected", "")) != "<hidden>":
		return Result.failure("未揭示时应隐藏他人 reserve_card_selected")

	var cards_val = sanitized.get("reserve_cards", null)
	if not (cards_val is Array):
		return Result.failure("sanitized.reserve_cards 类型错误（期望 Array）")
	var cards: Array = cards_val
	if cards.size() != 3:
		return Result.failure("sanitized.reserve_cards 张数应为 3，实际: %d" % cards.size())
	for i in range(cards.size()):
		if str(cards[i]) != "<hidden>":
			return Result.failure("未揭示时应隐藏他人 reserve_cards[%d]" % i)

	# 揭示后：仅公开已选择的那一张卡
	state.players[1]["reserve_card_revealed"] = true
	var sanitized2: Dictionary = tab._sanitize_player_dict_for_viewer(state.players[1], 1, 0, state)
	var cards2_val = sanitized2.get("reserve_cards", null)
	if not (cards2_val is Array):
		return Result.failure("揭示后 sanitized.reserve_cards 类型错误（期望 Array）")
	var cards2: Array = cards2_val
	if cards2.size() != 3:
		return Result.failure("揭示后 sanitized.reserve_cards 张数应为 3，实际: %d" % cards2.size())
	if cards2[0] != "<hidden>" or cards2[2] != "<hidden>":
		return Result.failure("揭示后未选择的 reserve_cards 应隐藏")
	if not (cards2[1] is Dictionary):
		return Result.failure("揭示后选择卡应为 Dictionary")
	if int(Dictionary(cards2[1]).get("type", -1)) != 10:
		return Result.failure("揭示后选择卡应为 type=10，实际: %s" % str(Dictionary(cards2[1]).get("type", null)))

	# 里程碑能力：允许查看全部储备卡
	state.players[0]["can_peek_all_reserve_cards"] = true
	var sanitized3: Dictionary = tab._sanitize_player_dict_for_viewer(state.players[1], 1, 0, state)
	var cards3_val = sanitized3.get("reserve_cards", null)
	if not (cards3_val is Array):
		return Result.failure("peek 后 sanitized.reserve_cards 类型错误（期望 Array）")
	var cards3: Array = cards3_val
	if cards3.size() != 3:
		return Result.failure("peek 后 sanitized.reserve_cards 张数应为 3，实际: %d" % cards3.size())
	for i in range(cards3.size()):
		if not (cards3[i] is Dictionary):
			return Result.failure("peek 后 reserve_cards[%d] 应为 Dictionary" % i)

	return Result.success()

