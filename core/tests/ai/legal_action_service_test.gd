class_name LegalActionServiceTest
extends RefCounted

const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_internal_reserve_action_requires_whitelist()
	if not r.ok:
		return r
	r = _test_validate_internal_command_requires_context_permission()
	if not r.ok:
		return r
	r = _test_debug_internal_action_never_enters_whitelist()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_engine() -> Result:
	var engine := GameEngine.new()
	var init: Result = engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	if engine.get_state() == null:
		return Result.failure("engine state is null")
	return Result.success(engine)

static func _make_context(engine: GameEngine, allowed_internal_actions: Array[String]) -> AiDecisionContext:
	var state := engine.get_state()
	var current_player := state.get_current_player_id()
	return AiDecisionContext.create(
		current_player,
		str(state.phase),
		str(state.sub_phase),
		int(state.round_number),
		12345,
		allowed_internal_actions
	)

static func _test_internal_reserve_action_requires_whitelist() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var no_internal_context := _make_context(engine, [])
	var no_internal_ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, no_internal_context)
	if not no_internal_ids_read.ok:
		return no_internal_ids_read
	var no_internal_ids: Array[String] = no_internal_ids_read.value
	if no_internal_ids.has("select_reserve_card"):
		return Result.failure("select_reserve_card should not be exposed without explicit internal whitelist")

	var context := _make_context(engine, ["select_reserve_card"])
	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not ids_read.ok:
		return ids_read
	var ids: Array[String] = ids_read.value
	if not ids.has("select_reserve_card"):
		return Result.failure("select_reserve_card should be exposed for ReserveCards decision")
	return Result.success()

static func _test_validate_internal_command_requires_context_permission() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()
	var current_player := state.get_current_player_id()
	var command := Command.create("select_reserve_card", current_player, {"selected_index": 0})

	var denied := LegalActionServiceClass.validate_command(engine, command, _make_context(engine, []))
	if denied.ok:
		return Result.failure("internal command should fail without context permission")

	var allowed := LegalActionServiceClass.validate_command(engine, command, _make_context(engine, ["select_reserve_card"]))
	if not allowed.ok:
		return Result.failure("internal command should validate with context permission: %s" % allowed.error)
	return Result.success()

static func _test_debug_internal_action_never_enters_whitelist() -> Result:
	var engine_read := _make_engine()
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var context := _make_context(engine, ["debug_give_money"])
	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not ids_read.ok:
		return ids_read
	var ids: Array[String] = ids_read.value
	if ids.has("debug_give_money"):
		return Result.failure("debug_give_money must not be exposed to Bot legal actions")
	var debug_command := Command.create("debug_give_money", context.player_id, {"amount": 10})
	var validate := LegalActionServiceClass.validate_command(engine, debug_command, context)
	if validate.ok:
		return Result.failure("debug_give_money should fail LegalActionService validation")
	return Result.success()
