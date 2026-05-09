class_name OSLASearchTest
extends RefCounted

const OSLASearchClass = preload("res://core/ai/search/osla_search.gd")
const OSLABotClass = preload("res://core/ai/bot/osla_bot.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const StrategyPhasePlannerClass = preload("res://core/ai/strategy/strategy_phase_planner.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var direct := _test_choose_command_without_mutating_source(seed_val)
	if not direct.ok:
		return direct
	var candidate_dedupe := _test_osla_search_dedupes_scored_candidates()
	if not candidate_dedupe.ok:
		return candidate_dedupe
	var deterministic := _test_osla_search_is_deterministic(seed_val)
	if not deterministic.ok:
		return deterministic
	var growth_route := _test_osla_search_uses_growth_route_breadth(seed_val)
	if not growth_route.ok:
		return growth_route
	var order_of_business_horizon := _test_osla_search_uses_order_of_business_response_horizon(seed_val)
	if not order_of_business_horizon.ok:
		return order_of_business_horizon
	var wrapper := _test_osla_bot_without_engine_uses_strategy_fallback(seed_val)
	if not wrapper.ok:
		return wrapper
	return Result.success({"cases": 6})

static func _test_choose_command_without_mutating_source(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var source_hash_before := str(engine.get_state().compute_hash())
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var decision_read := OSLASearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(180),
		{
			"max_candidates": 4,
			"opponent_max_candidates": 2,
			"opponent_max_valid_per_action": 2,
		}
	)
	if not decision_read.ok:
		return decision_read
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("OSLASearch must not mutate source engine")
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("OSLASearch returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("OSLASearch returned invalid command: %s" % valid.error)
	if str(decision.trace.get("bot", "")) != "OSLASearch":
		return Result.failure("OSLASearch trace should identify search: %s" % str(decision.trace))
	if int(decision.explanation.get("valid_candidate_count", 0)) <= 0:
		return Result.failure("OSLASearch explanation missing valid_candidate_count: %s" % str(decision.explanation))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if not features.has("osla_eval_score"):
		return Result.failure("OSLASearch should expose osla_eval_score: %s" % str(features))
	if not features.has("osla_budget_expired"):
		return Result.failure("OSLASearch should expose budget status in features: %s" % str(features))
	if not decision.explanation.has("budget_expired"):
		return Result.failure("OSLASearch should expose budget status in explanation: %s" % str(decision.explanation))
	var response_macro := str(features.get("osla_opponent_response_macro_id", ""))
	var response_skip := str(features.get("osla_opponent_response_skipped_reason", ""))
	if response_macro.is_empty() and response_skip.is_empty():
		return Result.failure("OSLASearch should expose opponent response result or skip reason: %s" % str(features))
	if not response_macro.is_empty() and int(features.get("osla_opponent_response_evaluated_count", 0)) <= 0:
		return Result.failure("OSLASearch should expose evaluated opponent response count: %s" % str(features))
	if not features.has("osla_deduped_candidates"):
		return Result.failure("OSLASearch should expose root candidate dedupe count: %s" % str(features))
	if not features.has("osla_opponent_response_deduped_candidates"):
		return Result.failure("OSLASearch should expose response candidate dedupe count: %s" % str(features))
	if not decision.explanation.has("candidate_deduped_count"):
		return Result.failure("OSLASearch should expose candidate dedupe count in explanation: %s" % str(decision.explanation))
	return Result.success()

static func _test_osla_search_dedupes_scored_candidates() -> Result:
	var lower := MacroAction.create(
		"z_lower_duplicate",
		[Command.create("recruit", 0, {"employee_type": "trainer", "slot": 1})],
		0.0,
		[],
		{}
	)
	var higher := MacroAction.create(
		"a_higher_duplicate",
		[Command.create("recruit", 0, {"slot": 1, "employee_type": "trainer"})],
		0.0,
		[],
		{}
	)
	var other := MacroAction.create(
		"other_recruit",
		[Command.create("recruit", 0, {"employee_type": "burger_cook", "slot": 1})],
		0.0,
		[],
		{}
	)
	var payload: Dictionary = OSLASearchClass._dedupe_scored_candidates([
		_scored_entry(lower, 10.0),
		_scored_entry(higher, 12.0),
		_scored_entry(other, 11.0),
	])
	if int(payload.get("deduped_count", -1)) != 1:
		return Result.failure("OSLASearch candidate dedupe should count one duplicate command: %s" % str(payload))
	var scored_val = payload.get("scored", [])
	if not (scored_val is Array):
		return Result.failure("OSLASearch candidate dedupe should return scored list: %s" % str(payload))
	var scored: Array = scored_val
	if scored.size() != 2:
		return Result.failure("OSLASearch candidate dedupe should keep two unique commands: %s" % str(scored))
	if not _scored_list_has_macro(scored, "a_higher_duplicate"):
		return Result.failure("OSLASearch candidate dedupe should keep higher scoring duplicate: %s" % str(scored))
	if not _scored_list_has_macro(scored, "other_recruit"):
		return Result.failure("OSLASearch candidate dedupe should keep unrelated command: %s" % str(scored))
	var tie_drop := MacroAction.create(
		"z_tie_drop",
		[Command.create("recruit", 0, {"employee_type": "trainer"})],
		0.0,
		[],
		{}
	)
	var tie_keep := MacroAction.create(
		"a_tie_keep",
		[Command.create("recruit", 0, {"employee_type": "trainer"})],
		0.0,
		[],
		{}
	)
	var tie_payload: Dictionary = OSLASearchClass._dedupe_scored_candidates([
		_scored_entry(tie_drop, 10.0),
		_scored_entry(tie_keep, 10.0),
	])
	var tie_scored: Array = Array(tie_payload.get("scored", []))
	if tie_scored.size() != 1 or str(Dictionary(tie_scored[0]).get("macro_action_id", "")) != "a_tie_keep":
		return Result.failure("OSLASearch candidate dedupe should tie-break by macro id: %s" % str(tie_payload))
	return Result.success()

static func _scored_entry(macro: MacroAction, score: float) -> Dictionary:
	return {
		"macro": macro,
		"macro_action_id": str(macro.id),
		"action_id": str(macro.commands[0].action_id) if not macro.commands.is_empty() else "",
		"strategy_score": float(score),
		"strategy_features": {},
		"tags": macro.tags.duplicate(),
	}

static func _scored_list_has_macro(scored: Array, macro_action_id: String) -> bool:
	for entry_val in scored:
		if not (entry_val is Dictionary):
			continue
		if str(Dictionary(entry_val).get("macro_action_id", "")) == macro_action_id:
			return true
	return false

static func _test_osla_search_uses_growth_route_breadth(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not working.ok:
		return working
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after advancing to Working")
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	if int(state.employee_pool.get("new_business_developer", 0)) <= 0:
		return Result.failure("OSLA growth smoke requires new_business_developer in pool")
	var actor := state.get_current_player_id()
	(state.players[actor]["employees"] as Array).append("new_business_developer")
	state.employee_pool["new_business_developer"] = int(state.employee_pool.get("new_business_developer", 0)) - 1
	if str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != DefsClass.SUB_PHASE_PLACE_HOUSES:
		return Result.failure("推进到 Working/PlaceHouses 失败：%s/%s" % [str(state.phase), str(state.sub_phase)])
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var profile = StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return Result.failure("StrategyProfile should load growth profile for osla growth smoke: %s" % profile_read.error)
	var search_options: Dictionary = StrategyPhasePlannerClass.build_search_options(data["observation"], data["context"], profile)
	if int(search_options.get("max_candidates", 0)) != 10:
		return Result.failure("OSLA growth smoke should widen candidate breadth: %s" % str(search_options))
	if int(search_options.get("opponent_max_candidates", 0)) != 4:
		return Result.failure("OSLA growth smoke should widen opponent breadth: %s" % str(search_options))
	if int(search_options.get("opponent_max_valid_per_action", 0)) != 4:
		return Result.failure("OSLA growth smoke should widen opponent valid coverage: %s" % str(search_options))
	var decision_read := OSLASearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(180),
		search_options
	)
	if not decision_read.ok:
		return decision_read
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("OSLA growth smoke returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("OSLA growth smoke returned invalid command: %s" % valid.error)
	if str(decision.trace.get("phase", "")) != DefsClass.PHASE_WORKING:
		return Result.failure("OSLA growth smoke should run inside Working: %s" % str(decision.explanation))
	if str(decision.trace.get("sub_phase", "")) != DefsClass.SUB_PHASE_PLACE_HOUSES:
		return Result.failure("OSLA growth smoke should run inside Working/PlaceHouses: %s" % str(decision.explanation))
	if int(decision.explanation.get("candidate_count", 0)) <= 1:
		return Result.failure("OSLA growth smoke should evaluate growth candidates beyond skip: %s" % str(decision.explanation))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if not features.has("osla_eval_score"):
		return Result.failure("OSLA growth smoke should expose eval score: %s" % str(features))
	if not features.has("osla_opponent_response_macro_id") and not features.has("osla_opponent_response_skipped_reason"):
		return Result.failure("OSLA growth smoke should expose opponent response result or skip reason: %s" % str(features))
	if int(features.get("osla_opponent_response_evaluated_count", 0)) <= 0 and str(features.get("osla_opponent_response_skipped_reason", "")) == "":
		return Result.failure("OSLA growth smoke should evaluate an opponent response when one is selected: %s" % str(features))
	return Result.success()

static func _test_osla_search_uses_order_of_business_response_horizon(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(3, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var order_of_business := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_ORDER_OF_BUSINESS, 400)
	if not order_of_business.ok:
		return order_of_business
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var profile = StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return Result.failure("StrategyProfile should load growth profile for osla order-of-business smoke: %s" % profile_read.error)
	var search_options: Dictionary = StrategyPhasePlannerClass.build_search_options(data["observation"], data["context"], profile)
	if int(search_options.get("opponent_response_horizon", 0)) != 2:
		return Result.failure("OSLA order-of-business smoke should use a two-step response horizon: %s" % str(search_options))
	var decision_read := OSLASearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(240),
		search_options
	)
	if not decision_read.ok:
		return decision_read
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("OSLA order-of-business smoke returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("OSLA order-of-business smoke returned invalid command: %s" % valid.error)
	if str(decision.trace.get("phase", "")) != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return Result.failure("OSLA order-of-business smoke should run inside OrderOfBusiness: %s" % str(decision.trace))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if int(features.get("osla_opponent_response_horizon", 0)) != 2:
		return Result.failure("OSLA order-of-business smoke should expose response horizon: %s" % str(features))
	if int(features.get("osla_opponent_response_chain_length", 0)) < 2:
		return Result.failure("OSLA order-of-business smoke should simulate two response steps in a 3p order pick: %s" % str(features))
	var chain_val = features.get("osla_opponent_response_chain", [])
	if not (chain_val is Array):
		return Result.failure("OSLA order-of-business smoke should expose response chain: %s" % str(features))
	var chain: Array = chain_val
	if chain.size() < 2:
		return Result.failure("OSLA order-of-business smoke response chain should contain two steps: %s" % str(chain))
	return Result.success()

static func _test_osla_search_is_deterministic(seed_val: int) -> Result:
	var first := _choose_once(seed_val)
	if not first.ok:
		return first
	var second := _choose_once(seed_val)
	if not second.ok:
		return second
	var first_decision: BotDecision = first.value
	var second_decision: BotDecision = second.value
	if first_decision.macro_action_id != second_decision.macro_action_id:
		return Result.failure("OSLASearch should choose deterministic macro: first=%s second=%s" % [first_decision.macro_action_id, second_decision.macro_action_id])
	if str(first_decision.command.to_dict()) != str(second_decision.command.to_dict()):
		return Result.failure("OSLASearch should choose deterministic command: first=%s second=%s" % [str(first_decision.command.to_dict()), str(second_decision.command.to_dict())])
	return Result.success()

static func _test_osla_bot_without_engine_uses_strategy_fallback(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var bot := OSLABotClass.new()
	var decision := bot.choose_command(
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(80)
	)
	if decision == null:
		return Result.failure("OSLABot returned null fallback decision")
	if decision.is_failure():
		return Result.failure("OSLABot fallback decision failed: %s" % decision.failure_reason)
	if decision.command == null:
		return Result.failure("OSLABot fallback returned empty command")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("OSLABot fallback returned invalid command: %s" % valid.error)
	return Result.success()

static func _choose_once(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	return OSLASearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(180),
		{
			"max_candidates": 4,
			"opponent_max_candidates": 2,
			"opponent_max_valid_per_action": 2,
		}
	)

static func _build_search_inputs(engine: GameEngine, seed_val: int) -> Result:
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	var player_id := state.get_current_player_id()
	var observation_read := ObservationAdapterClass.observe_for_player(engine, player_id)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var context_read := AiDecisionContext.from_observation(observation, seed_val, _allowed_internal_actions(observation))
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value
	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not ids_read.ok:
		return ids_read
	var legal_action_ids: Array[String] = ids_read.value
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	return Result.success({
		"observation": observation,
		"context": context,
		"legal_action_ids": legal_action_ids,
		"validate_fn": validate_fn,
	})

static func _allowed_internal_actions(observation: ObservationState) -> Array[String]:
	var decision_point := AiDecisionPointClass.from_observation(observation)
	match decision_point:
		AiDecisionPointClass.RESERVE_CARD:
			return ["select_reserve_card"]
		AiDecisionPointClass.RESTRUCTURING:
			return [
				"restructure_employee",
				"set_company_structure_direct",
				"set_company_structure_report",
				"submit_restructuring",
			]
		AiDecisionPointClass.CLEANUP_PENDING:
			return ["choose_fridge_keep"]
		_:
			return []
