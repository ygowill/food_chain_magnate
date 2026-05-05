class_name ObservationAdapterTest
extends RefCounted

const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_self_can_see_own_reserve_cards()
	if not r.ok:
		return r
	r = _test_opponent_unrevealed_reserve_cards_are_hidden()
	if not r.ok:
		return r
	r = _test_peek_can_see_opponent_reserve_cards()
	if not r.ok:
		return r
	r = _test_revealed_reserve_card_only_shows_selected_card()
	if not r.ok:
		return r
	r = _test_unfinalized_restructuring_hides_opponent_structure()
	if not r.ok:
		return r
	r = _test_finalized_restructuring_reveals_opponent_structure()
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _make_engine() -> Result:
	var engine := GameEngine.new()
	var init: Result = engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.players[0]["reserve_cards"] = [{"type": "own_a"}, {"type": "own_b"}, {"type": "own_c"}]
	state.players[0]["reserve_card_selected"] = 1
	state.players[0]["reserve_card_revealed"] = false
	state.players[0]["can_peek_all_reserve_cards"] = false
	state.players[1]["reserve_cards"] = [{"type": "secret_a"}, {"type": "secret_b"}, {"type": "secret_c"}]
	state.players[1]["reserve_card_selected"] = 2
	state.players[1]["reserve_card_revealed"] = false
	state.players[1]["can_peek_all_reserve_cards"] = false
	state.players[1]["company_structure"] = {
		"ceo_slots": 1,
		"structure": [{"employee_id": "secret_manager"}],
	}
	return Result.success(engine)

static func _observe(engine: GameEngine, viewer_player_id: int) -> Result:
	var observe := ObservationAdapterClass.observe_for_player(engine, viewer_player_id)
	if not observe.ok:
		return Result.failure("observe failed: %s" % observe.error)
	if observe.value == null or not (observe.value is ObservationState):
		return Result.failure("observe value type error")
	return observe

static func _test_self_can_see_own_reserve_cards() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var observe := _observe(engine, 0)
	if not observe.ok:
		return observe
	var obs: ObservationState = observe.value
	if int(obs.own_player.get("reserve_card_selected", -1)) != 1:
		return Result.failure("own reserve_card_selected should be visible")
	var cards_val = obs.own_player.get("reserve_cards", null)
	if not (cards_val is Array):
		return Result.failure("own reserve_cards type error")
	var cards: Array = cards_val
	if cards.size() != 3 or not (cards[1] is Dictionary):
		return Result.failure("own reserve_cards should contain dictionaries")
	return Result.success()

static func _test_opponent_unrevealed_reserve_cards_are_hidden() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var observe := _observe(engine, 0)
	if not observe.ok:
		return observe
	var obs: ObservationState = observe.value
	var opponent := obs.public_players[1]
	if str(opponent.get("reserve_card_selected", "")) != "<hidden>":
		return Result.failure("opponent reserve_card_selected should be hidden")
	var cards_val = opponent.get("reserve_cards", null)
	if not (cards_val is Array):
		return Result.failure("opponent reserve_cards type error")
	for card in cards_val:
		if str(card) != "<hidden>":
			return Result.failure("unrevealed opponent reserve card leaked: %s" % str(card))
	if str(opponent).find("secret_b") >= 0:
		return Result.failure("hidden reserve card content leaked in opponent public dict")
	return Result.success()

static func _test_peek_can_see_opponent_reserve_cards() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()
	state.players[0]["can_peek_all_reserve_cards"] = true
	var observe := _observe(engine, 0)
	if not observe.ok:
		return observe
	var obs: ObservationState = observe.value
	var cards_val = obs.public_players[1].get("reserve_cards", null)
	if not (cards_val is Array):
		return Result.failure("peek reserve_cards type error")
	var cards: Array = cards_val
	for i in range(cards.size()):
		if not (cards[i] is Dictionary):
			return Result.failure("peek reserve_cards[%d] should be visible" % i)
	return Result.success()

static func _test_revealed_reserve_card_only_shows_selected_card() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()
	state.players[1]["reserve_card_revealed"] = true
	var observe := _observe(engine, 0)
	if not observe.ok:
		return observe
	var obs: ObservationState = observe.value
	var cards_val = obs.public_players[1].get("reserve_cards", null)
	if not (cards_val is Array):
		return Result.failure("revealed reserve_cards type error")
	var cards: Array = cards_val
	if str(cards[0]) != "<hidden>" or str(cards[1]) != "<hidden>":
		return Result.failure("unselected revealed reserve cards should stay hidden")
	if not (cards[2] is Dictionary) or str(Dictionary(cards[2]).get("type", "")) != "secret_c":
		return Result.failure("selected revealed reserve card should be visible")
	return Result.success()

static func _test_unfinalized_restructuring_hides_opponent_structure() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()
	state.round_state["restructuring"] = {
		"submitted": {0: false, 1: false},
		"finalized": false,
	}
	var observe := _observe(engine, 0)
	if not observe.ok:
		return observe
	var obs: ObservationState = observe.value
	var opponent := obs.public_players[1]
	var cs_val = opponent.get("company_structure", null)
	if not (cs_val is Dictionary) or not bool(Dictionary(cs_val).get("hidden", false)):
		return Result.failure("unfinalized opponent company_structure should be hidden")
	if str(opponent).find("secret_manager") >= 0:
		return Result.failure("hidden company structure content leaked")
	var own_cs = obs.own_player.get("company_structure", null)
	if not (own_cs is Dictionary) or bool(Dictionary(own_cs).get("hidden", false)):
		return Result.failure("own company_structure should remain visible")
	return Result.success()

static func _test_finalized_restructuring_reveals_opponent_structure() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()
	state.round_state["restructuring"] = {
		"submitted": {0: true, 1: true},
		"finalized": true,
	}
	var observe := _observe(engine, 0)
	if not observe.ok:
		return observe
	var obs: ObservationState = observe.value
	var opponent := obs.public_players[1]
	var cs_val = opponent.get("company_structure", null)
	if not (cs_val is Dictionary):
		return Result.failure("finalized opponent company_structure should be dictionary")
	if str(cs_val).find("secret_manager") < 0:
		return Result.failure("finalized opponent company_structure should be visible")
	return Result.success()
