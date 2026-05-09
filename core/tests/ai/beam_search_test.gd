class_name BeamSearchTest
extends RefCounted

const BeamSearchClass = preload("res://core/ai/search/beam_search.gd")
const BeamBotClass = preload("res://core/ai/bot/beam_bot.gd")
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
	var candidate_dedupe := _test_beam_search_dedupes_scored_candidates()
	if not candidate_dedupe.ok:
		return candidate_dedupe
	var deterministic := _test_beam_search_is_deterministic(seed_val)
	if not deterministic.ok:
		return deterministic
	var depth_two := _test_beam_search_selects_depth_two_same_actor_recruit_path(seed_val)
	if not depth_two.ok:
		return depth_two
	var growth_route := _test_beam_search_uses_growth_route_horizon(seed_val)
	if not growth_route.ok:
		return growth_route
	var dedupe := _test_beam_search_dedupes_duplicate_state_nodes()
	if not dedupe.ok:
		return dedupe
	var transposition := _test_beam_search_prunes_lower_transposition_nodes()
	if not transposition.ok:
		return transposition
	var wrapper := _test_beam_bot_without_engine_uses_fallback(seed_val)
	if not wrapper.ok:
		return wrapper
	return Result.success({"cases": 8})

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
	var decision_read := BeamSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(260),
		{
			"beam_width": 2,
			"max_depth": 2,
			"top_k_per_node": 2,
		}
	)
	if not decision_read.ok:
		return decision_read
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("BeamSearch must not mutate source engine")
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("BeamSearch returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("BeamSearch returned invalid command: %s" % valid.error)
	if str(decision.trace.get("bot", "")) != "BeamSearch":
		return Result.failure("BeamSearch trace should identify search: %s" % str(decision.trace))
	if int(decision.explanation.get("valid_candidate_count", 0)) <= 0:
		return Result.failure("BeamSearch explanation missing valid_candidate_count: %s" % str(decision.explanation))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if not features.has("beam_eval_score"):
		return Result.failure("BeamSearch should expose beam_eval_score: %s" % str(features))
	if int(features.get("beam_deepest_depth", 0)) < 2:
		return Result.failure("BeamSearch should expand beyond the root decision in this smoke setup: %s" % str(features))
	if int(features.get("beam_expanded_nodes", 0)) <= 0:
		return Result.failure("BeamSearch should expose expanded node count: %s" % str(features))
	if int(features.get("beam_selected_depth", 0)) <= 0:
		return Result.failure("BeamSearch should expose selected node depth: %s" % str(features))
	if not features.has("beam_budget_expired"):
		return Result.failure("BeamSearch should expose budget status in features: %s" % str(features))
	if not features.has("beam_candidate_deduped_count"):
		return Result.failure("BeamSearch should expose candidate dedupe count in features: %s" % str(features))
	if not features.has("beam_deduped_nodes"):
		return Result.failure("BeamSearch should expose state dedupe count in features: %s" % str(features))
	if not features.has("beam_transposition_pruned_nodes"):
		return Result.failure("BeamSearch should expose transposition prune count in features: %s" % str(features))
	if not decision.explanation.has("budget_expired"):
		return Result.failure("BeamSearch should expose budget status in explanation: %s" % str(decision.explanation))
	if not decision.explanation.has("candidate_deduped_count"):
		return Result.failure("BeamSearch should expose candidate dedupe count in explanation: %s" % str(decision.explanation))
	if not decision.explanation.has("deduped_nodes"):
		return Result.failure("BeamSearch should expose state dedupe count in explanation: %s" % str(decision.explanation))
	if not decision.explanation.has("transposition_pruned_nodes"):
		return Result.failure("BeamSearch should expose transposition prune count in explanation: %s" % str(decision.explanation))
	var path_val = features.get("beam_path", [])
	if not (path_val is Array) or Array(path_val).is_empty():
		return Result.failure("BeamSearch should expose non-empty path: %s" % str(features))
	return Result.success()

static func _test_beam_search_dedupes_scored_candidates() -> Result:
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
	var payload: Dictionary = BeamSearchClass._dedupe_scored_candidates([
		_scored_entry(lower, 10.0),
		_scored_entry(higher, 12.0),
		_scored_entry(other, 11.0),
	])
	if int(payload.get("deduped_count", -1)) != 1:
		return Result.failure("BeamSearch candidate dedupe should count one duplicate command: %s" % str(payload))
	var scored_val = payload.get("scored", [])
	if not (scored_val is Array):
		return Result.failure("BeamSearch candidate dedupe should return scored list: %s" % str(payload))
	var scored: Array = scored_val
	if scored.size() != 2:
		return Result.failure("BeamSearch candidate dedupe should keep two unique commands: %s" % str(scored))
	if not _scored_list_has_macro(scored, "a_higher_duplicate"):
		return Result.failure("BeamSearch candidate dedupe should keep higher scoring duplicate: %s" % str(scored))
	if not _scored_list_has_macro(scored, "other_recruit"):
		return Result.failure("BeamSearch candidate dedupe should keep unrelated command: %s" % str(scored))
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
	var tie_payload: Dictionary = BeamSearchClass._dedupe_scored_candidates([
		_scored_entry(tie_drop, 10.0),
		_scored_entry(tie_keep, 10.0),
	])
	var tie_scored: Array = Array(tie_payload.get("scored", []))
	if tie_scored.size() != 1 or str(Dictionary(tie_scored[0]).get("macro_action_id", "")) != "a_tie_keep":
		return Result.failure("BeamSearch candidate dedupe should tie-break by macro id: %s" % str(tie_payload))
	return Result.success()

static func _test_beam_search_is_deterministic(seed_val: int) -> Result:
	var first := _choose_once(seed_val)
	if not first.ok:
		return first
	var second := _choose_once(seed_val)
	if not second.ok:
		return second
	var first_decision: BotDecision = first.value
	var second_decision: BotDecision = second.value
	if first_decision.macro_action_id != second_decision.macro_action_id:
		return Result.failure("BeamSearch should choose deterministic macro: first=%s second=%s" % [first_decision.macro_action_id, second_decision.macro_action_id])
	if str(first_decision.command.to_dict()) != str(second_decision.command.to_dict()):
		return Result.failure("BeamSearch should choose deterministic command: first=%s second=%s" % [str(first_decision.command.to_dict()), str(second_decision.command.to_dict())])
	return Result.success()

static func _test_beam_search_selects_depth_two_same_actor_recruit_path(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var scenario := _prepare_replay_safe_recruiter_followup_state(engine)
	if not scenario.ok:
		return scenario
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var decision_read := BeamSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		null,
		{
			"beam_width": 2,
			"max_depth": 2,
			"top_k_per_node": 3,
		}
	)
	if not decision_read.ok:
		return decision_read
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("BeamSearch depth-two scenario returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("BeamSearch depth-two scenario returned invalid command: %s" % valid.error)
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if int(features.get("beam_deepest_depth", 0)) < 2:
		return Result.failure("BeamSearch should expand to depth two with an active recruiter: %s" % str(features))
	if int(features.get("beam_selected_depth", 0)) < 2:
		return Result.failure("BeamSearch should be able to select a depth-two same-actor recruit path: %s" % str(features))
	if int(features.get("beam_expanded_nodes", 0)) <= 0:
		return Result.failure("BeamSearch depth-two scenario should expand child nodes: %s" % str(features))
	var path_val = features.get("beam_path", [])
	if not (path_val is Array):
		return Result.failure("BeamSearch depth-two scenario path should be an Array: %s" % str(features))
	var path: Array = path_val
	if path.size() < 2:
		return Result.failure("BeamSearch depth-two scenario path should include two decisions: %s" % str(path))
	var actor := int(data["context"].player_id)
	for i in range(2):
		if not (path[i] is Dictionary):
			return Result.failure("BeamSearch path[%d] should be Dictionary: %s" % [i, str(path)])
		var step: Dictionary = path[i]
		if int(step.get("actor", -1)) != actor:
			return Result.failure("BeamSearch path[%d] should stay on root actor %d: %s" % [i, actor, str(path)])
		if str(step.get("action_id", "")) != "recruit":
			return Result.failure("BeamSearch path[%d] should be recruit: %s" % [i, str(path)])
	return Result.success()

static func _test_beam_search_uses_growth_route_horizon(seed_val: int) -> Result:
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
		return Result.failure("Beam growth smoke requires new_business_developer in pool")
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
		return Result.failure("StrategyProfile should load growth profile for beam growth smoke: %s" % profile_read.error)
	var search_options: Dictionary = StrategyPhasePlannerClass.build_search_options(data["observation"], data["context"], profile)
	if int(search_options.get("max_depth", 0)) != 4:
		return Result.failure("Beam growth smoke should carry a depth-4 horizon: %s" % str(search_options))
	if int(search_options.get("beam_width", 0)) != 6:
		return Result.failure("Beam growth smoke should carry widened beam width: %s" % str(search_options))
	if int(search_options.get("max_candidates", 0)) != 10:
		return Result.failure("Beam growth smoke should carry widened candidate breadth: %s" % str(search_options))
	if int(search_options.get("opponent_max_candidates", 0)) != 4:
		return Result.failure("Beam growth smoke should carry widened opponent breadth: %s" % str(search_options))
	if int(search_options.get("opponent_max_valid_per_action", 0)) != 4:
		return Result.failure("Beam growth smoke should carry widened opponent valid coverage: %s" % str(search_options))
	var decision_read := BeamSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(260),
		search_options
	)
	if not decision_read.ok:
		return decision_read
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("Beam growth smoke returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("Beam growth smoke returned invalid command: %s" % valid.error)
	if str(decision.trace.get("phase", "")) != DefsClass.PHASE_WORKING:
		return Result.failure("Beam growth smoke should run inside Working: %s" % str(decision.explanation))
	if str(decision.trace.get("sub_phase", "")) != DefsClass.SUB_PHASE_PLACE_HOUSES:
		return Result.failure("Beam growth smoke should run inside Working/PlaceHouses: %s" % str(decision.explanation))
	if int(decision.explanation.get("candidate_count", 0)) <= 1:
		return Result.failure("Beam growth smoke should evaluate growth candidates beyond skip: %s" % str(decision.explanation))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if int(features.get("beam_max_depth", 0)) != 4:
		return Result.failure("Beam growth smoke should expose depth-4 horizon: %s" % str(features))
	if int(features.get("beam_width", 0)) != 6:
		return Result.failure("Beam growth smoke should expose widened beam width: %s" % str(features))
	if int(features.get("beam_top_k_per_node", 0)) != 5:
		return Result.failure("Beam growth smoke should expose widened top-K breadth: %s" % str(features))
	if int(features.get("beam_opponent_top_k_per_node", 0)) != 4:
		return Result.failure("Beam growth smoke should expose opponent branch breadth: %s" % str(features))
	if int(features.get("beam_root_max_valid_per_action", 0)) != 24:
		return Result.failure("Beam growth smoke should expose root valid-action breadth: %s" % str(features))
	if int(features.get("beam_opponent_max_valid_per_action", 0)) != 4:
		return Result.failure("Beam growth smoke should expose opponent valid-action breadth: %s" % str(features))
	if int(features.get("beam_expanded_nodes", 0)) <= 0:
		return Result.failure("Beam growth smoke should expand at least one node: %s" % str(features))
	if int(features.get("beam_deepest_depth", 0)) < 2:
		return Result.failure("Beam growth smoke should expand beyond the root: %s" % str(features))
	return Result.success()

static func _test_beam_search_dedupes_duplicate_state_nodes() -> Result:
	var lower := {
		"state_key": "same_state",
		"root_macro_id": "lower",
		"total_score": 10.0,
		"path_score": 8.0,
		"path": [{"macro_action_id": "lower"}],
	}
	var higher := {
		"state_key": "same_state",
		"root_macro_id": "higher",
		"total_score": 12.0,
		"path_score": 9.0,
		"path": [{"macro_action_id": "higher"}],
	}
	var other := {
		"state_key": "other_state",
		"root_macro_id": "other",
		"total_score": 11.0,
		"path_score": 7.0,
		"path": [{"macro_action_id": "other"}],
	}
	var payload: Dictionary = BeamSearchClass._dedupe_nodes_by_state([lower, higher, other])
	if int(payload.get("deduped_count", -1)) != 1:
		return Result.failure("BeamSearch state dedupe should count one duplicate: %s" % str(payload))
	var nodes_val = payload.get("nodes", [])
	if not (nodes_val is Array):
		return Result.failure("BeamSearch state dedupe should return nodes: %s" % str(payload))
	var nodes: Array = Array(nodes_val)
	if nodes.size() != 2:
		return Result.failure("BeamSearch state dedupe should keep two unique states: %s" % str(nodes))
	if str(Dictionary(nodes[0]).get("root_macro_id", "")) != "higher":
		return Result.failure("BeamSearch state dedupe should keep highest scoring duplicate first: %s" % str(nodes))
	if str(Dictionary(nodes[1]).get("root_macro_id", "")) != "other":
		return Result.failure("BeamSearch state dedupe should keep unrelated state: %s" % str(nodes))
	return Result.success()

static func _test_beam_search_prunes_lower_transposition_nodes() -> Result:
	var best_state_scores := {}
	var higher := {
		"state_key": "same_state",
		"root_macro_id": "higher",
		"total_score": 12.0,
		"path_score": 9.0,
		"path": [{"macro_action_id": "higher"}],
	}
	var lower := {
		"state_key": "same_state",
		"root_macro_id": "lower",
		"total_score": 10.0,
		"path_score": 8.0,
		"path": [{"macro_action_id": "lower"}],
	}
	var other := {
		"state_key": "other_state",
		"root_macro_id": "other",
		"total_score": 11.0,
		"path_score": 7.0,
		"path": [{"macro_action_id": "other"}],
	}
	var payload: Dictionary = BeamSearchClass._prune_nodes_by_transposition([higher, lower, other], best_state_scores)
	if int(payload.get("pruned_count", -1)) != 1:
		return Result.failure("BeamSearch transposition prune should count one lower duplicate: %s" % str(payload))
	var nodes_val = payload.get("nodes", [])
	if not (nodes_val is Array):
		return Result.failure("BeamSearch transposition prune should return nodes: %s" % str(payload))
	var nodes: Array = Array(nodes_val)
	if nodes.size() != 2:
		return Result.failure("BeamSearch transposition prune should keep two nodes: %s" % str(nodes))
	if str(Dictionary(nodes[0]).get("root_macro_id", "")) != "higher":
		return Result.failure("BeamSearch transposition prune should keep higher-scoring duplicate: %s" % str(nodes))
	if str(Dictionary(nodes[1]).get("root_macro_id", "")) != "other":
		return Result.failure("BeamSearch transposition prune should keep unrelated state: %s" % str(nodes))
	if not best_state_scores.has("same_state") or not is_equal_approx(float(best_state_scores.get("same_state", 0.0)), 12.0):
		return Result.failure("BeamSearch transposition prune should store best score per state: %s" % str(best_state_scores))
	return Result.success()

static func _test_beam_bot_without_engine_uses_fallback(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var bot := BeamBotClass.new()
	var decision := bot.choose_command(
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(80)
	)
	if decision == null:
		return Result.failure("BeamBot returned null fallback decision")
	if decision.is_failure():
		return Result.failure("BeamBot fallback decision failed: %s" % decision.failure_reason)
	if decision.command == null:
		return Result.failure("BeamBot fallback returned empty command")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("BeamBot fallback returned invalid command: %s" % valid.error)
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
	return BeamSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(260),
		{
			"beam_width": 2,
			"max_depth": 2,
			"top_k_per_node": 2,
		}
	)

static func _prepare_replay_safe_recruiter_followup_state(engine: GameEngine) -> Result:
	var working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not working.ok:
		return working
	var first_actor := engine.get_state().get_current_player_id()
	var first_recruit := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "recruiting_girl"}))
	if not first_recruit.ok:
		return Result.failure("recruiting_girl setup recruit failed: %s" % first_recruit.error)
	var restructuring := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_RESTRUCTURING, 80)
	if not restructuring.ok:
		return restructuring
	var place := engine.execute_command(Command.create("set_company_structure_direct", first_actor, {
		"slot_index": 0,
		"employee_id": "recruiting_girl",
	}))
	if not place.ok:
		return Result.failure("recruiting_girl setup structure placement failed: %s" % place.error)
	var next_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 80)
	if not next_working.ok:
		return next_working
	var safety := 0
	while engine.get_state().get_current_player_id() != first_actor:
		safety += 1
		if safety > 20:
			return Result.failure("recruiting_girl setup failed to rotate back to original actor")
		var end_turn := TestPhaseUtilsClass.end_current_player_working_turn(engine, 50)
		if not end_turn.ok:
			return end_turn
		if engine.get_state().phase != DefsClass.PHASE_WORKING:
			return Result.failure("recruiting_girl setup left Working before original actor returned")
	if str(engine.get_state().sub_phase) != DefsClass.SUB_PHASE_RECRUIT:
		return Result.failure("recruiting_girl setup should end at Working/Recruit, got %s/%s" % [str(engine.get_state().phase), str(engine.get_state().sub_phase)])
	return Result.success()

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
