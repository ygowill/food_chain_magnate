class_name GreedySearchTest
extends RefCounted

const GreedySearchClass = preload("res://core/ai/search/greedy_search.gd")
const GreedyBotClass = preload("res://core/ai/bot/greedy_bot.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const EvaluatorClass = preload("res://core/ai/evaluation/evaluator.gd")
const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var reserve := _test_choose_reserve_without_mutating_source(seed_val)
	if not reserve.ok:
		return reserve
	var fallback := _test_greedy_bot_expired_budget_uses_legal_fallback(seed_val)
	if not fallback.ok:
		return fallback
	var eval := _test_evaluator_prefers_useful_no_salary_entry_employee(seed_val)
	if not eval.ok:
		return eval
	var payday := _test_payday_fire_candidates_require_salary_shortfall(seed_val)
	if not payday.ok:
		return payday
	var prior_order := _test_search_orders_candidates_by_prior_before_simulation()
	if not prior_order.ok:
		return prior_order
	return Result.success({"cases": 5})

static func _test_choose_reserve_without_mutating_source(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var source_hash_before := str(engine.get_state().compute_hash())
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var decision_read := GreedySearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(50),
		{"max_valid_per_action": 8}
	)
	if not decision_read.ok:
		return decision_read
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("GreedySearch must not mutate source engine")
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("GreedySearch returned empty decision")
	if decision.command.action_id != "select_reserve_card":
		return Result.failure("expected select_reserve_card, got %s" % decision.command.action_id)
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("GreedySearch returned invalid command: %s" % valid.error)
	if int(decision.explanation.get("candidate_count", 0)) <= 0:
		return Result.failure("GreedySearch explanation missing candidate_count")
	if int(decision.explanation.get("valid_candidate_count", 0)) <= 0:
		return Result.failure("GreedySearch explanation missing valid_candidate_count")
	var trace_check := _assert_decision_trace(decision)
	if not trace_check.ok:
		return trace_check
	return Result.success()

static func _test_greedy_bot_expired_budget_uses_legal_fallback(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var bot := GreedyBotClass.new()
	var decision := bot.choose_command_with_engine(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(0)
	)
	if decision == null:
		return Result.failure("GreedyBot returned null decision for expired budget")
	if decision.is_failure():
		return Result.failure("GreedyBot should fallback to legal command for expired budget: %s" % decision.failure_reason)
	if decision.command == null:
		return Result.failure("GreedyBot fallback returned empty command")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("GreedyBot fallback returned invalid command: %s" % valid.error)
	if str(decision.explanation.get("fallback", "")) != "random_legal":
		return Result.failure("GreedyBot expired budget should use random_legal fallback: %s" % str(decision.explanation))
	if not bool(decision.trace.get("fallback_after_budget_expired", false)):
		return Result.failure("GreedyBot fallback trace should mark expired budget: %s" % str(decision.trace))
	return Result.success()

static func _test_evaluator_prefers_useful_no_salary_entry_employee(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var pid := engine.get_state().get_current_player_id()
	var salaried := _score_minimal_player(pid, ["brand_director"], [])
	if not salaried.ok:
		return salaried
	var entry := _score_minimal_player(pid, ["marketing_trainee"], [])
	if not entry.ok:
		return entry
	if float(entry.value.get("score", 0.0)) <= float(salaried.value.get("score", 0.0)):
		return Result.failure("Evaluator should prefer no-salary entry marketing employee over salaried director: entry=%s salaried=%s" % [str(entry.value), str(salaried.value)])
	var no_marketing := _score_minimal_player(pid, [], [])
	if not no_marketing.ok:
		return no_marketing
	var with_marketing := _score_minimal_player(pid, [], [{"owner": pid}])
	if not with_marketing.ok:
		return with_marketing
	if float(with_marketing.value.get("score", 0.0)) <= float(no_marketing.value.get("score", 0.0)):
		return Result.failure("Evaluator should reward own marketing pipeline: with=%s without=%s" % [str(with_marketing.value), str(no_marketing.value)])
	return Result.success()

static func _score_minimal_player(player_id: int, reserve_employees: Array, marketing_instances: Array) -> Result:
	var observation := ObservationState.new()
	observation.viewer_player_id = player_id
	observation.own_player = {
		"cash": 0,
		"inventory": {},
		"employees": ["ceo"],
		"reserve_employees": reserve_employees.duplicate(),
		"busy_marketers": [],
		"restaurants": [],
		"milestones": [],
	}
	observation.bank_public = {}
	observation.marketing_instances_public = marketing_instances.duplicate(true)
	return EvaluatorClass.score_observation(observation, player_id)

static func _test_payday_fire_candidates_require_salary_shortfall(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var context := AiDecisionContext.create(0, DefsClass.PHASE_PAYDAY, "", 1, seed_val, [])
	var legal: Array[String] = ["fire", "skip"]

	var no_salary := CandidateGeneratorClass.generate(
		_payday_observation(0, ["errand_boy"], 0),
		context,
		legal,
		Callable(),
		{"max_valid_per_action": 8}
	)
	if not no_salary.ok:
		return no_salary
	if _candidate_has_action(no_salary.value, "fire"):
		return Result.failure("Payday candidates should not fire no-salary errand_boy without salary shortfall: %s" % str(_candidate_ids(no_salary.value)))
	if not _candidate_has_action(no_salary.value, "skip"):
		return Result.failure("Payday candidates should keep skip when no fire is needed: %s" % str(_candidate_ids(no_salary.value)))

	var salaried_shortfall := CandidateGeneratorClass.generate(
		_payday_observation(0, ["burger_cook"], 0),
		context,
		legal,
		Callable(),
		{"max_valid_per_action": 8}
	)
	if not salaried_shortfall.ok:
		return salaried_shortfall
	if not _candidate_has_action(salaried_shortfall.value, "fire"):
		return Result.failure("Payday candidates should fire salaried employees when cash is short: %s" % str(_candidate_ids(salaried_shortfall.value)))
	return Result.success()

static func _test_search_orders_candidates_by_prior_before_simulation() -> Result:
	var low := MacroAction.create("z_low", [], 0.0)
	var high_b := MacroAction.create("b_high", [], 2.0)
	var high_a := MacroAction.create("a_high", [], 2.0)
	var candidates := [low, high_b, high_a]
	GreedySearchClass._sort_candidates_for_search(candidates)
	var ordered := []
	for macro_val in candidates:
		if macro_val is MacroAction:
			ordered.append((macro_val as MacroAction).id)
	if str(ordered) != str(["a_high", "b_high", "z_low"]):
		return Result.failure("GreedySearch should order by prior desc then id: %s" % str(ordered))
	return Result.success()

static func _payday_observation(player_id: int, reserve_employees: Array, cash: int) -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = player_id
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_PAYDAY
	observation.sub_phase = ""
	observation.rules_public = {"salary_cost": 5}
	observation.own_player = {
		"cash": int(cash),
		"inventory": {},
		"employees": ["ceo"],
		"reserve_employees": reserve_employees.duplicate(),
		"busy_marketers": [],
		"restaurants": [],
		"milestones": [],
	}
	return observation

static func _candidate_has_action(payload: Dictionary, action_id: String) -> bool:
	for macro_val in Array(payload.get("candidates", [])):
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		for command in macro.commands:
			if command != null and str(command.action_id) == action_id:
				return true
	return false

static func _candidate_ids(payload: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for macro_val in Array(payload.get("candidates", [])):
		if macro_val is MacroAction:
			out.append(str((macro_val as MacroAction).id))
	return out

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

static func _assert_decision_trace(decision: BotDecision) -> Result:
	if decision == null:
		return Result.failure("decision is null")
	var trace := decision.trace
	if trace.is_empty():
		return Result.failure("GreedySearch decision trace is empty")
	if int(trace.get("candidate_count", 0)) != int(decision.explanation.get("candidate_count", -1)):
		return Result.failure("trace candidate_count does not match explanation")
	if int(trace.get("valid_candidate_count", 0)) != int(decision.explanation.get("valid_candidate_count", -1)):
		return Result.failure("trace valid_candidate_count does not match explanation")
	if str(trace.get("observation_hash", "")).is_empty():
		return Result.failure("trace observation_hash is empty")
	if str(trace.get("chosen_action_id", "")) != str(decision.command.action_id):
		return Result.failure("trace chosen_action_id mismatch: %s" % str(trace))
	if Dictionary(trace.get("chosen_params", {})) != decision.command.params:
		return Result.failure("trace chosen_params mismatch: %s" % str(trace))
	if not is_equal_approx(float(trace.get("score", 0.0)), float(decision.score)):
		return Result.failure("trace score mismatch: %s vs %s" % [str(trace.get("score", null)), str(decision.score)])
	var top_val = trace.get("top_candidates", [])
	if not (top_val is Array) or Array(top_val).is_empty():
		return Result.failure("trace top_candidates is empty")
	var top: Dictionary = Dictionary(Array(top_val)[0])
	if str(top.get("macro_action_id", "")) != str(decision.macro_action_id):
		return Result.failure("top candidate should explain chosen macro: %s" % str(top))
	if str(top.get("action_id", "")) != str(decision.command.action_id):
		return Result.failure("top candidate action_id mismatch: %s" % str(top))
	if not (top.get("features", null) is Dictionary):
		return Result.failure("top candidate missing features: %s" % str(top))
	if int(trace.get("time_ms", -1)) < 0:
		return Result.failure("trace time_ms is invalid: %s" % str(trace.get("time_ms", null)))
	return Result.success()

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
