extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const RandomManagerClass = preload("res://core/random/random_manager.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

const MODULE_ID := "reserve_prices"
const FIRST_BREAK_ADD_PER_PLAYER := 200
const CARDS_PER_PLAYER := 3
const ALLOWED_TYPES: Array[int] = [5, 10, 20]

func register(registrar) -> Result:
	var r = registrar.register_phase_hook(Phase.RESTRUCTURING, HookType.BEFORE_ENTER, Callable(self, "_on_restructuring_before_enter"), 0)
	if not r.ok:
		return r

	r = registrar.register_bankruptcy_handler("first_break", Callable(self, "_on_bank_first_break"))
	if not r.ok:
		return r

	return Result.success()

func _on_restructuring_before_enter(state: GameState) -> Result:
	# 仅在第 1 回合进入 Restructuring 时初始化替代储备卡
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if int(state.round_number) != 1:
		return Result.success()
	if not (state.players is Array):
		return Result.failure("%s: state.players 类型错误（期望 Array）" % MODULE_ID)

	var deck: Array[Dictionary] = []
	for t in ALLOWED_TYPES:
		# 18 张替代卡：每种类型 6 张（总计 18）
		for _i in range(6):
			deck.append({"type": int(t)})

	var rng := RandomManagerClass.new(int(state.seed) + 14014)
	rng.shuffle(deck)

	var need := state.players.size() * CARDS_PER_PLAYER
	if deck.size() < need:
		return Result.failure("%s: 替代储备卡不足: need=%d deck=%d" % [MODULE_ID, need, deck.size()])

	var cursor := 0
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("%s: players[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var player: Dictionary = p_val

		var cards: Array = []
		for _j in range(CARDS_PER_PLAYER):
			cards.append(deck[cursor])
			cursor += 1

		player["reserve_cards"] = cards
		if not player.has("reserve_card_selected") or not (player["reserve_card_selected"] is int):
			player["reserve_card_selected"] = 0
		var sel: int = int(player["reserve_card_selected"])
		if sel < 0 or sel >= CARDS_PER_PLAYER:
			player["reserve_card_selected"] = 0
		player["reserve_card_revealed"] = false
		state.players[pid] = player

	return Result.success()

func _on_bank_first_break(state: GameState, trigger_reason: String, required_payment: int) -> Result:
	# 规则：第一次破产固定注入 $200/玩家，并用储备卡多数决定 base_unit_price（20>5>10）
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.bank is Dictionary):
		return Result.failure("%s: state.bank 类型错误（期望 Dictionary）" % MODULE_ID)
	if not (state.players is Array):
		return Result.failure("%s: state.players 类型错误（期望 Array）" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not (state.rules is Dictionary):
		return Result.failure("%s: state.rules 类型错误（期望 Dictionary）" % MODULE_ID)

	if not state.bank.has("broke_count") or not (state.bank["broke_count"] is int):
		return Result.failure("%s: bank.broke_count 缺失或类型错误（期望 int）" % MODULE_ID)
	if int(state.bank["broke_count"]) != 0:
		return Result.success()
	if not state.bank.has("total") or not (state.bank["total"] is int):
		return Result.failure("%s: bank.total 缺失或类型错误（期望 int）" % MODULE_ID)
	if not state.bank.has("reserve_added_total") or not (state.bank["reserve_added_total"] is int):
		return Result.failure("%s: bank.reserve_added_total 缺失或类型错误（期望 int）" % MODULE_ID)

	var bank_before: int = int(state.bank["total"])
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
	state.bank["broke_count"] = 1
	state.bank["total"] = bank_before + total_added
	state.bank["reserve_added_total"] = int(state.bank["reserve_added_total"]) + total_added

	_record_bankruptcy_event(state, {
		"kind": "first",
		"variant": MODULE_ID,
		"trigger_reason": trigger_reason,
		"required_payment": required_payment,
		"bank_total_before": bank_before,
		"reserve_added": total_added,
		"bank_total_after": int(state.bank["total"]),
		"base_unit_price": new_base,
		"revealed_cards": revealed,
	})

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

static func _record_bankruptcy_event(state: GameState, event: Dictionary) -> void:
	assert(state != null, "%s: _record_bankruptcy_event state 为空" % MODULE_ID)
	assert(state.round_state is Dictionary, "%s: _record_bankruptcy_event state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	assert(event is Dictionary, "%s: _record_bankruptcy_event event 类型错误（期望 Dictionary）" % MODULE_ID)

	var bankruptcy: Dictionary = {}
	if state.round_state.has("bankruptcy"):
		assert(state.round_state["bankruptcy"] is Dictionary, "%s: round_state.bankruptcy 类型错误（期望 Dictionary）" % MODULE_ID)
		bankruptcy = state.round_state["bankruptcy"]

	var events: Array = []
	if bankruptcy.has("events"):
		assert(bankruptcy["events"] is Array, "%s: round_state.bankruptcy.events 类型错误（期望 Array）" % MODULE_ID)
		events = bankruptcy["events"]
	events.append(event)
	bankruptcy["events"] = events
	state.round_state["bankruptcy"] = bankruptcy

