# 银行破产规则（Breaking the Bank）
# 从 DinnertimeSettlement 抽离：当银行不足以支付时，触发储备卡注入与 CEO 卡槽重设；
# 第二次破产允许银行透支，并在 Dinnertime 结束后终局。
class_name BankruptcyRules
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const BankruptcyRegistryClass = preload("res://core/rules/bankruptcy_registry.gd")

static func pay_bank_to_player(state: GameState, player_id: int, amount: int, reason: String) -> Result:
	if amount <= 0:
		return Result.success()

	var ensure := ensure_bank_can_pay(state, amount, reason)
	if not ensure.ok:
		return ensure

	var pay := StateUpdaterClass.player_receive_from_bank(state, player_id, amount)
	if not pay.ok:
		return pay

	var warnings: Array[String] = []
	warnings.append_array(ensure.warnings)

	var cash_read := _get_player_cash(state, player_id)
	if not cash_read.ok:
		return cash_read
	var cash: int = int(cash_read.value)

	# 里程碑：首个拥有$20 / 首个拥有$100（允许在任何获得现金时检查；不依赖“刚好达到”）
	if cash >= 20:
		var ms20 := MilestoneSystemClass.process_event(state, "CashReached", {"player_id": player_id, "value": 20})
		if not ms20.ok:
			warnings.append("里程碑触发失败(CashReached/20): 玩家 %d: %s" % [player_id, ms20.error])
		else:
			warnings.append_array(ms20.warnings)
	if cash >= 100:
		var ms100 := MilestoneSystemClass.process_event(state, "CashReached", {"player_id": player_id, "value": 100})
		if not ms100.ok:
			warnings.append("里程碑触发失败(CashReached/100): 玩家 %d: %s" % [player_id, ms100.error])
		else:
			warnings.append_array(ms100.warnings)

	return Result.success().with_warnings(warnings)

static func _get_player_cash(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("BankruptcyRules: state 为空")
	if not (state.players is Array):
		return Result.failure("BankruptcyRules: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("BankruptcyRules: player_id 越界: %d" % player_id)
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("BankruptcyRules: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("cash") or not (player["cash"] is int):
		return Result.failure("BankruptcyRules: player[%d].cash 缺失或类型错误（期望 int）" % player_id)
	return Result.success(int(player["cash"]))

static func ensure_bank_can_pay(state: GameState, amount: int, reason: String) -> Result:
	if state == null:
		return Result.failure("BankruptcyRules: state 为空")
	if not (state.bank is Dictionary):
		return Result.failure("BankruptcyRules: state.bank 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("BankruptcyRules: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("BankruptcyRules: state.round_state 类型错误（期望 Dictionary）")
	if not state.bank.has("total") or not (state.bank["total"] is int):
		return Result.failure("BankruptcyRules: state.bank.total 缺失或类型错误（期望 int）")
	if not state.bank.has("broke_count") or not (state.bank["broke_count"] is int):
		return Result.failure("BankruptcyRules: state.bank.broke_count 缺失或类型错误（期望 int）")

	var warnings: Array[String] = []
	if amount <= 0:
		return Result.success()

	var safety := 0
	while safety < 3:
		safety += 1
		var bank_total: int = int(state.bank["total"])
		if bank_total >= amount:
			return Result.success().with_warnings(warnings)

		var broke_count: int = int(state.bank["broke_count"])
		if broke_count <= 0:
			var first := _break_the_bank_first_time(state, reason, amount)
			if not first.ok:
				return first
			warnings.append_array(first.warnings)
			continue

		if broke_count == 1:
			var second := _break_the_bank_second_time(state, reason, amount)
			if not second.ok:
				return second
			warnings.append_array(second.warnings)
			# 第二次破产后允许银行透支，支付可继续进行
			return Result.success().with_warnings(warnings)

		# broke_count >= 2：允许透支
		return Result.success().with_warnings(warnings)

	return Result.failure("银行破产处理超出安全上限")

static func _break_the_bank_first_time(state: GameState, trigger_reason: String, required_payment: int) -> Result:
	if not state.bank.has("broke_count") or not (state.bank["broke_count"] is int):
		return Result.failure("银行第一次破产失败：state.bank.broke_count 缺失或类型错误（期望 int）")
	if int(state.bank["broke_count"]) != 0:
		return Result.success()
	if not state.bank.has("total") or not (state.bank["total"] is int):
		return Result.failure("银行第一次破产失败：state.bank.total 缺失或类型错误（期望 int）")
	if not state.bank.has("reserve_added_total") or not (state.bank["reserve_added_total"] is int):
		return Result.failure("银行第一次破产失败：state.bank.reserve_added_total 缺失或类型错误（期望 int）")

	# 允许模块替换“第一次破产”的规则（例如模块14：Reserve Prices）
	if BankruptcyRegistryClass.is_loaded() and BankruptcyRegistryClass.has_first_break_handler():
		var cb := BankruptcyRegistryClass.get_first_break_handler()
		var r = cb.call(state, trigger_reason, required_payment)
		if not (r is Result):
			return Result.failure("银行第一次破产失败：模块 handler 必须返回 Result (%s)" % BankruptcyRegistryClass.get_first_break_source())
		return r

	var bank_before: int = int(state.bank["total"])
	var total_added := 0
	var slot_counts: Dictionary = {}
	var revealed: Array[Dictionary] = []

	for player_id in range(state.players.size()):
		var player_val = state.players[player_id]
		if not (player_val is Dictionary):
			return Result.failure("银行第一次破产失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)
		var player: Dictionary = player_val

		if not player.has("reserve_card_selected") or not (player["reserve_card_selected"] is int):
			return Result.failure("银行第一次破产失败：player[%d].reserve_card_selected 缺失或类型错误（期望 int）" % player_id)
		var selected_index: int = int(player["reserve_card_selected"])

		var card_read := _get_selected_reserve_card(player, player_id)
		if not card_read.ok:
			return card_read
		var card: Dictionary = card_read.value

		if not card.has("cash") or not (card["cash"] is int):
			return Result.failure("银行第一次破产失败：reserve_card.cash 类型错误（期望 int）")
		if not card.has("ceo_slots") or not (card["ceo_slots"] is int):
			return Result.failure("银行第一次破产失败：reserve_card.ceo_slots 类型错误（期望 int）")
		var cash: int = int(card["cash"])
		var slots: int = int(card["ceo_slots"])
		if cash < 0:
			return Result.failure("银行第一次破产失败：reserve_card.cash 不能为负数: %d" % cash)
		if slots < 1:
			return Result.failure("银行第一次破产失败：reserve_card.ceo_slots 必须 >= 1，实际: %d" % slots)

		total_added += cash
		var prev_count := 0
		if slot_counts.has(slots):
			prev_count = int(slot_counts[slots])
		slot_counts[slots] = prev_count + 1

		player["reserve_card_revealed"] = true
		revealed.append({
			"player_id": player_id,
			"selected_index": selected_index,
			"card": card,
		})

	var chosen_slots := 3
	var best_count := -1
	for k in slot_counts.keys():
		var slots_val := int(k)
		var count_val := int(slot_counts[k])
		if count_val > best_count or (count_val == best_count and slots_val > chosen_slots):
			best_count = count_val
			chosen_slots = slots_val

	state.bank["broke_count"] = 1
	state.bank["ceo_slots_after_first_break"] = chosen_slots
	state.bank["total"] = bank_before + total_added
	state.bank["reserve_added_total"] = int(state.bank["reserve_added_total"]) + total_added

	for pid in range(state.players.size()):
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			return Result.failure("银行第一次破产失败：players[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = player_val
		if not player.has("company_structure") or not (player["company_structure"] is Dictionary):
			return Result.failure("银行第一次破产失败：player[%d].company_structure 缺失或类型错误（期望 Dictionary）" % pid)
		var cs: Dictionary = player["company_structure"]
		cs["ceo_slots"] = chosen_slots
		player["company_structure"] = cs
		state.players[pid] = player

	_record_bankruptcy_event(state, {
		"kind": "first",
		"trigger_reason": trigger_reason,
		"required_payment": required_payment,
		"bank_total_before": bank_before,
		"reserve_added": total_added,
		"bank_total_after": int(state.bank["total"]),
		"ceo_slots": chosen_slots,
		"revealed_cards": revealed,
	})

	return Result.success().with_warning("银行第一次破产：注入 $%d，CEO 新卡槽数=%d" % [total_added, chosen_slots])

static func _break_the_bank_second_time(state: GameState, trigger_reason: String, required_payment: int) -> Result:
	if not state.bank.has("broke_count") or not (state.bank["broke_count"] is int):
		return Result.failure("银行第二次破产失败：state.bank.broke_count 缺失或类型错误（期望 int）")
	if int(state.bank["broke_count"]) >= 2:
		return Result.success()
	if not state.bank.has("total") or not (state.bank["total"] is int):
		return Result.failure("银行第二次破产失败：state.bank.total 缺失或类型错误（期望 int）")

	var bank_before: int = int(state.bank["total"])
	state.bank["broke_count"] = 2

	_record_bankruptcy_event(state, {
		"kind": "second",
		"trigger_reason": trigger_reason,
		"required_payment": required_payment,
		"bank_total_before": bank_before,
	})

	state.round_state["game_over"] = {
		"reason": "bankruptcy",
		"round": state.round_number,
		"phase": state.phase,
	}

	return Result.success().with_warning("银行第二次破产：本局游戏将在晚餐阶段结束后立刻结束（跳过 Payday）")

static func _get_selected_reserve_card(player: Dictionary, player_id: int) -> Result:
	if not player.has("reserve_cards") or not (player["reserve_cards"] is Array):
		return Result.failure("银行第一次破产失败：player[%d].reserve_cards 类型错误（期望 Array）" % player_id)
	var cards: Array = player["reserve_cards"]
	if cards.is_empty():
		return Result.failure("银行第一次破产失败：player[%d].reserve_cards 不能为空" % player_id)

	if not player.has("reserve_card_selected") or not (player["reserve_card_selected"] is int):
		return Result.failure("银行第一次破产失败：player[%d].reserve_card_selected 缺失或类型错误（期望 int）" % player_id)
	var idx: int = int(player["reserve_card_selected"])
	if idx < 0 or idx >= cards.size():
		return Result.failure("银行第一次破产失败：player[%d].reserve_card_selected 越界: %d" % [player_id, idx])

	var card_val = cards[idx]
	if not (card_val is Dictionary):
		return Result.failure("银行第一次破产失败：reserve_cards[%d] 类型错误（期望 Dictionary）" % idx)
	return Result.success(card_val)

static func _record_bankruptcy_event(state: GameState, event: Dictionary) -> void:
	assert(state != null, "BankruptcyRules._record_bankruptcy_event: state 为空")
	assert(state.round_state is Dictionary, "BankruptcyRules._record_bankruptcy_event: state.round_state 类型错误（期望 Dictionary）")
	assert(event is Dictionary, "BankruptcyRules._record_bankruptcy_event: event 类型错误（期望 Dictionary）")

	var bankruptcy: Dictionary = {}
	if state.round_state.has("bankruptcy"):
		assert(state.round_state["bankruptcy"] is Dictionary, "BankruptcyRules._record_bankruptcy_event: round_state.bankruptcy 类型错误（期望 Dictionary）")
		bankruptcy = state.round_state["bankruptcy"]

	var events: Array = []
	if bankruptcy.has("events"):
		assert(bankruptcy["events"] is Array, "BankruptcyRules._record_bankruptcy_event: round_state.bankruptcy.events 类型错误（期望 Array）")
		events = bankruptcy["events"]
	events.append(event)
	bankruptcy["events"] = events
	state.round_state["bankruptcy"] = bankruptcy
