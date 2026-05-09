class_name MCTSSearchTest
extends RefCounted

const MCTSSearchClass = preload("res://core/ai/search/mcts_search.gd")
const MCTSBotClass = preload("res://core/ai/bot/mcts_bot.gd")
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
	var deterministic := _test_mcts_search_is_deterministic(seed_val)
	if not deterministic.ok:
		return deterministic
	var wrapper := _test_mcts_bot_budget_expired_uses_beam_fallback(seed_val)
	if not wrapper.ok:
		return wrapper
	return Result.success({"cases": 3})

static func _test_choose_command_without_mutating_source(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_growth_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var source_hash_before := str(engine.get_state().compute_hash())
	var profile = StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return Result.failure("StrategyProfile should load growth profile for mcts smoke: %s" % profile_read.error)
	var search_options: Dictionary = StrategyPhasePlannerClass.build_search_options(data["observation"], data["context"], profile)
	if int(search_options.get("mcts_iterations", 0)) != 32:
		return Result.failure("MCTS growth smoke should widen iterations: %s" % str(search_options))
	if int(search_options.get("mcts_max_depth", 0)) != 4:
		return Result.failure("MCTS growth smoke should widen depth: %s" % str(search_options))
	if int(search_options.get("mcts_top_k_per_node", 0)) != 5:
		return Result.failure("MCTS growth smoke should widen branching: %s" % str(search_options))
	if float(search_options.get("mcts_exploration", 0.0)) != 1.25:
		return Result.failure("MCTS growth smoke should expose exploration constant: %s" % str(search_options))
	if int(search_options.get("mcts_min_simulation_budget_ms", 0)) != 24:
		return Result.failure("MCTS growth smoke should expose simulation budget floor: %s" % str(search_options))
	search_options["mcts_iterations"] = 12
	search_options["mcts_top_k_per_node"] = 4
	var decision_read := MCTSSearchClass.choose_command(
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
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("MCTSSearch must not mutate source engine")
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("MCTSSearch returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("MCTSSearch returned invalid command: %s" % valid.error)
	if str(decision.trace.get("bot", "")) != "MCTSSearch":
		return Result.failure("MCTSSearch trace should identify search: %s" % str(decision.trace))
	if str(decision.trace.get("search", "")) != "mcts":
		return Result.failure("MCTSSearch trace should use mcts search id: %s" % str(decision.trace))
	if int(decision.explanation.get("candidate_count", 0)) <= 1:
		return Result.failure("MCTSSearch growth smoke should evaluate branching candidates: %s" % str(decision.explanation))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if not features.has("mcts_final_features"):
		return Result.failure("MCTSSearch should expose evaluator features: %s" % str(features))
	if not features.has("mcts_iterations"):
		return Result.failure("MCTSSearch should expose iteration count: %s" % str(features))
	if not features.has("mcts_root_visits"):
		return Result.failure("MCTSSearch should expose root visits: %s" % str(features))
	if not features.has("mcts_expanded_nodes"):
		return Result.failure("MCTSSearch should expose expanded node count: %s" % str(features))
	if not features.has("mcts_attempted_simulations"):
		return Result.failure("MCTSSearch should expose attempted simulation count: %s" % str(features))
	if not features.has("mcts_selected_visits"):
		return Result.failure("MCTSSearch should expose selected visit count: %s" % str(features))
	if not features.has("mcts_selected_q"):
		return Result.failure("MCTSSearch should expose selected q: %s" % str(features))
	if not features.has("mcts_selected_prior"):
		return Result.failure("MCTSSearch should expose selected prior: %s" % str(features))
	if not features.has("mcts_eval_score"):
		return Result.failure("MCTSSearch should expose eval score: %s" % str(features))
	if not features.has("mcts_candidate_deduped_count"):
		return Result.failure("MCTSSearch should expose candidate dedupe count: %s" % str(features))
	if not features.has("mcts_simulation_ms"):
		return Result.failure("MCTSSearch should expose simulation timing: %s" % str(features))
	if not features.has("mcts_max_simulation_ms"):
		return Result.failure("MCTSSearch should expose max simulation timing: %s" % str(features))
	if not features.has("mcts_simulation_budget_skips"):
		return Result.failure("MCTSSearch should expose simulation budget skips: %s" % str(features))
	if not features.has("mcts_min_simulation_budget_ms"):
		return Result.failure("MCTSSearch should expose simulation budget floor: %s" % str(features))
	if not features.has("mcts_budget_guarded"):
		return Result.failure("MCTSSearch should expose budget guard status: %s" % str(features))
	if not decision.explanation.has("budget_expired"):
		return Result.failure("MCTSSearch should expose budget status in explanation: %s" % str(decision.explanation))
	if not decision.explanation.has("budget_guarded"):
		return Result.failure("MCTSSearch should expose budget guard status in explanation: %s" % str(decision.explanation))
	return Result.success()

static func _test_mcts_search_is_deterministic(seed_val: int) -> Result:
	var first := _choose_once(seed_val)
	if not first.ok:
		return first
	var second := _choose_once(seed_val)
	if not second.ok:
		return second
	var first_decision: BotDecision = first.value
	var second_decision: BotDecision = second.value
	if first_decision.macro_action_id != second_decision.macro_action_id:
		return Result.failure("MCTSSearch should choose deterministic macro: first=%s second=%s" % [first_decision.macro_action_id, second_decision.macro_action_id])
	if str(first_decision.command.to_dict()) != str(second_decision.command.to_dict()):
		return Result.failure("MCTSSearch should choose deterministic command: first=%s second=%s" % [str(first_decision.command.to_dict()), str(second_decision.command.to_dict())])
	return Result.success()

static func _test_mcts_bot_budget_expired_uses_beam_fallback(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_growth_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var bot := MCTSBotClass.new()
	var profile_read := bot.configure_profile("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var decision := bot.choose_command_with_engine(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(0)
	)
	if decision == null:
		return Result.failure("MCTSBot returned null fallback decision")
	if decision.is_failure():
		return Result.failure("MCTSBot fallback decision failed: %s" % decision.failure_reason)
	if decision.command == null:
		return Result.failure("MCTSBot fallback returned empty command")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("MCTSBot fallback returned invalid command: %s" % valid.error)
	if str(decision.explanation.get("fallback", "")) != "beam":
		return Result.failure("MCTSBot budget fallback should use beam: %s" % str(decision.explanation))
	if str(decision.trace.get("mcts_failure", "")).find("budget expired") < 0:
		return Result.failure("MCTSBot fallback trace should preserve mcts failure: %s" % str(decision.trace))
	return Result.success()

static func _choose_once(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_growth_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var profile = StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return Result.failure("StrategyProfile should load growth profile for mcts deterministic smoke: %s" % profile_read.error)
	var search_options: Dictionary = StrategyPhasePlannerClass.build_search_options(data["observation"], data["context"], profile)
	search_options["mcts_iterations"] = 12
	search_options["mcts_top_k_per_node"] = 4
	return MCTSSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(180),
		search_options
	)

static func _build_growth_search_inputs(engine: GameEngine, seed_val: int) -> Result:
	var working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not working.ok:
		return working
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null after advancing to Working")
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	if int(state.employee_pool.get("new_business_developer", 0)) <= 0:
		return Result.failure("MCTS growth smoke requires new_business_developer in pool")
	var actor := state.get_current_player_id()
	(state.players[actor]["employees"] as Array).append("new_business_developer")
	state.employee_pool["new_business_developer"] = int(state.employee_pool.get("new_business_developer", 0)) - 1
	if str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != DefsClass.SUB_PHASE_PLACE_HOUSES:
		return Result.failure("推进到 Working/PlaceHouses 失败：%s/%s" % [str(state.phase), str(state.sub_phase)])
	var observation_read := ObservationAdapterClass.observe_for_player(engine, actor)
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
