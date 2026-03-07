extends RefCounted

const BankStateAccessClass = preload("res://core/state/bank_state_access.gd")

const MODULE_ID := "reserve_prices"
const FIRST_BREAK_ADD_PER_PLAYER := 200
const CARDS_PER_PLAYER := 3
const ALLOWED_TYPES: Array[int] = [5, 10, 20]

func register(registrar) -> Result:
	var r = registrar.register_state_initializer("%s:init_state" % MODULE_ID, Callable(self, "_init_state"), 0)
	if not r.ok:
		return r

	r = registrar.register_bankruptcy_handler("first_break", Callable(self, "_on_bank_first_break"))
	if not r.ok:
		return r

	return Result.success()

func _init_state(state: GameState, _rng_manager) -> Result:
	# 规则：开局使用“替代储备卡”集合（每位玩家固定顺序：5,10,20）
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.players is Array):
		return Result.failure("%s: state.players 类型错误（期望 Array）" % MODULE_ID)
	if ALLOWED_TYPES.size() != CARDS_PER_PLAYER:
		return Result.failure("%s: ALLOWED_TYPES 与 CARDS_PER_PLAYER 不一致（types=%d cards_per_player=%d）" % [MODULE_ID, ALLOWED_TYPES.size(), CARDS_PER_PLAYER])

	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("%s: players[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var player: Dictionary = p_val

		var cards: Array = []
		for t in ALLOWED_TYPES:
			cards.append({"type": int(t)})

		player["reserve_cards"] = cards
		var sel := -1
		if player.has("reserve_card_selected"):
			var sel_val = player.get("reserve_card_selected", -1)
			if sel_val is int:
				sel = int(sel_val)
			elif sel_val is float:
				var f: float = float(sel_val)
				if f == floor(f):
					sel = int(f)
		if sel < -1 or sel >= CARDS_PER_PLAYER:
			sel = -1
		player["reserve_card_selected"] = sel
		player["reserve_card_revealed"] = false
		state.players[pid] = player

	return Result.success()

func _on_bank_first_break(state: GameState, trigger_reason: String, required_payment: int) -> Result:
	# 规则：第一次破产固定注入 $200/玩家，并用储备卡多数决定 base_unit_price（20>5>10）
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.players is Array):
		return Result.failure("%s: state.players 类型错误（期望 Array）" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not (state.rules is Dictionary):
		return Result.failure("%s: state.rules 类型错误（期望 Dictionary）" % MODULE_ID)

	var broke_count_read := BankStateAccessClass.require_broke_count(state, MODULE_ID)
	if not broke_count_read.ok:
		return broke_count_read
	if int(broke_count_read.value) != 0:
		return Result.success()
	var total_read := BankStateAccessClass.require_total(state, MODULE_ID)
	if not total_read.ok:
		return total_read
	var reserve_added_total_read := BankStateAccessClass.require_reserve_added_total(state, MODULE_ID)
	if not reserve_added_total_read.ok:
		return reserve_added_total_read

	var bankruptcy_target_check := _validate_bankruptcy_event_write_target(state)
	if not bankruptcy_target_check.ok:
		return bankruptcy_target_check

	var bank_before: int = int(total_read.value)
	var total_added: int = int(state.players.size()) * FIRST_BREAK_ADD_PER_PLAYER

	var counts := {5: 0, 10: 0, 20: 0}
	var revealed: Array[Dictionary] = []

	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("%s: players[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var player: Dictionary = p_val

		if not player.has("reserve_cards") or not (player["reserve_cards"] is Array):
			return Result.failure("%s: player[%d].reserve_cards 缺失或类型错误（期望 Array）" % [MODULE_ID, pid])
		var cards: Array = player["reserve_cards"]
		if cards.size() != CARDS_PER_PLAYER:
			return Result.failure("%s: player[%d].reserve_cards 张数错误（期望 %d），实际: %d" % [MODULE_ID, pid, CARDS_PER_PLAYER, cards.size()])

		if not player.has("reserve_card_selected") or not (player["reserve_card_selected"] is int):
			return Result.failure("%s: player[%d].reserve_card_selected 缺失或类型错误（期望 int）" % [MODULE_ID, pid])
		var idx: int = int(player["reserve_card_selected"])
		if idx < 0 or idx >= cards.size():
			return Result.failure("%s: player[%d].reserve_card_selected 越界: %d" % [MODULE_ID, pid, idx])

		var card_val = cards[idx]
		if not (card_val is Dictionary):
			return Result.failure("%s: player[%d].reserve_cards[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, pid, idx])
		var card: Dictionary = card_val
		if not card.has("type") or not (card["type"] is int):
			return Result.failure("%s: reserve_card.type 缺失或类型错误（期望 int）" % MODULE_ID)
		var t: int = int(card["type"])
		if not ALLOWED_TYPES.has(t):
			return Result.failure("%s: reserve_card.type 非法（期望 5/10/20），实际: %d" % [MODULE_ID, t])

		counts[t] = int(counts[t]) + 1
		player["reserve_card_revealed"] = true
		state.players[pid] = player
		revealed.append({
			"player_id": pid,
			"selected_index": idx,
			"card": card,
		})

	var new_base := _pick_base_price(counts)
	if new_base <= 0:
		return Result.failure("%s: 无法确定 base_unit_price" % MODULE_ID)

	state.rules["base_unit_price"] = new_base
	var set_broke := BankStateAccessClass.set_broke_count(state, 1, MODULE_ID)
	if not set_broke.ok:
		return set_broke
	var inject := BankStateAccessClass.apply_reserve_injection(state, total_added, MODULE_ID)
	if not inject.ok:
		return inject
	var bank_after_first_break: int = int((inject.value as Dictionary).get("total", bank_before + total_added))

	var record_event := _record_bankruptcy_event(state, {
		"kind": "first",
		"variant": MODULE_ID,
		"trigger_reason": trigger_reason,
		"required_payment": required_payment,
		"bank_total_before": bank_before,
		"reserve_added": total_added,
		"bank_total_after": bank_after_first_break,
		"base_unit_price": new_base,
		"revealed_cards": revealed,
	})
	if not record_event.ok:
		return record_event

	return Result.success().with_warning("银行第一次破产(Reserve Prices)：注入 $%d，base_unit_price=%d" % [total_added, new_base])

static func _pick_base_price(counts: Dictionary) -> int:
	var best_count := -1
	var best_price := 10
	# tie-break：20 > 5 > 10
	var order: Array[int] = [20, 5, 10]
	for p in order:
		var c := int(counts.get(p, 0))
		if c > best_count:
			best_count = c
			best_price = p
		elif c == best_count and _tie_break(p, best_price):
			best_price = p
	return best_price

static func _tie_break(candidate: int, current: int) -> bool:
	if candidate == current:
		return false
	if candidate == 20:
		return true
	if current == 20:
		return false
	if candidate == 5 and current == 10:
		return true
	return false

static func _validate_bankruptcy_event_write_target(state: GameState) -> Result:
	if state == null:
		return Result.failure("%s: _validate_bankruptcy_event_write_target state 为空" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: _validate_bankruptcy_event_write_target state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.round_state.has("bankruptcy"):
		return Result.success()
	var bankruptcy_val = state.round_state.get("bankruptcy", null)
	if not (bankruptcy_val is Dictionary):
		return Result.failure("%s: round_state.bankruptcy 类型错误（期望 Dictionary）" % MODULE_ID)
	var bankruptcy: Dictionary = bankruptcy_val
	if bankruptcy.has("events") and not (bankruptcy.get("events", null) is Array):
		return Result.failure("%s: round_state.bankruptcy.events 类型错误（期望 Array）" % MODULE_ID)
	return Result.success()

static func _record_bankruptcy_event(state: GameState, event: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: _record_bankruptcy_event state 为空" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: _record_bankruptcy_event state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not (event is Dictionary):
		return Result.failure("%s: _record_bankruptcy_event event 类型错误（期望 Dictionary）" % MODULE_ID)

	var bankruptcy: Dictionary = {}
	if state.round_state.has("bankruptcy"):
		var bankruptcy_val = state.round_state.get("bankruptcy", null)
		if not (bankruptcy_val is Dictionary):
			return Result.failure("%s: round_state.bankruptcy 类型错误（期望 Dictionary）" % MODULE_ID)
		bankruptcy = Dictionary(bankruptcy_val).duplicate(true)

	var events: Array = []
	if bankruptcy.has("events"):
		var events_val = bankruptcy.get("events", null)
		if not (events_val is Array):
			return Result.failure("%s: round_state.bankruptcy.events 类型错误（期望 Array）" % MODULE_ID)
		events = Array(events_val).duplicate(true)
	events.append(event.duplicate(true))
	bankruptcy["events"] = events
	state.round_state["bankruptcy"] = bankruptcy
	return Result.success()
