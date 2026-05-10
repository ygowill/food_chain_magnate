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
	var selection := _test_selection_uses_current_actor_perspective()
	if not selection.ok:
		return selection
	var value_score := _test_value_score_combines_strategy_path_and_evaluator()
	if not value_score.ok:
		return value_score
	var root_prior_guard := _test_final_root_selection_preserves_prior_when_under_sampled()
	if not root_prior_guard.ok:
		return root_prior_guard
	var short_circuit := _test_single_candidate_short_circuits_search()
	if not short_circuit.ok:
		return short_circuit
	var pass_only := _test_pass_only_candidates_short_circuit()
	if not pass_only.ok:
		return pass_only
	var legal_gate := _test_mcts_bot_skips_when_no_constructive_legal_action()
	if not legal_gate.ok:
		return legal_gate
	var direct := _test_choose_command_without_mutating_source(seed_val)
	if not direct.ok:
		return direct
	var deterministic := _test_mcts_search_is_deterministic(seed_val)
	if not deterministic.ok:
		return deterministic
	var wrapper := _test_mcts_bot_budget_expired_uses_beam_fallback(seed_val)
	if not wrapper.ok:
		return wrapper
	return Result.success({"cases": 9})

static func _test_selection_uses_current_actor_perspective() -> Result:
	var root_child_high := _make_test_node(1, "high", 2.0, 4, 0.1)
	var root_child_low := _make_test_node(1, "low", -1.0, 4, 0.1)
	var root_node := {
		"actor_id": 0,
		"visits": 8,
		"children": [root_child_high, root_child_low],
	}
	var root_selected = MCTSSearchClass._select_best_child(root_node, 0, 0.0)
	if not (root_selected is Dictionary):
		return Result.failure("root selection should return a child")
	if str(Dictionary(root_selected).get("macro_action_id", "")) != "high":
		return Result.failure("root actor should maximize root-perspective q: %s" % str(root_selected))

	var opponent_child_high := _make_test_node(0, "opp_high", 2.0, 4, 0.1)
	var opponent_child_low := _make_test_node(0, "opp_low", -1.0, 4, 0.1)
	var opponent_node := {
		"actor_id": 1,
		"visits": 8,
		"children": [opponent_child_high, opponent_child_low],
	}
	var opponent_selected = MCTSSearchClass._select_best_child(opponent_node, 0, 0.0)
	if not (opponent_selected is Dictionary):
		return Result.failure("opponent selection should return a child")
	if str(Dictionary(opponent_selected).get("macro_action_id", "")) != "opp_low":
		return Result.failure("opponent actor should minimize root-perspective q: %s" % str(opponent_selected))
	return Result.success()

static func _make_test_node(actor_id: int, macro_action_id: String, q: float, visits: int, prior: float) -> Dictionary:
	return {
		"actor_id": actor_id,
		"macro_action_id": macro_action_id,
		"visits": visits,
		"value_sum": q * float(visits),
		"prior": prior,
	}

static func _test_value_score_combines_strategy_path_and_evaluator() -> Result:
	var own_factor := MCTSSearchClass._path_contribution_factor(0, 0, 0.55, 0.92, 1)
	if not is_equal_approx(own_factor, 1.0):
		return Result.failure("root actor path contribution should be positive: %f" % own_factor)
	var opponent_factor := MCTSSearchClass._path_contribution_factor(1, 0, 0.55, 0.92, 2)
	if not is_equal_approx(opponent_factor, -0.506):
		return Result.failure("opponent path contribution should be negative and discounted: %f" % opponent_factor)
	var node := {
		"path_score": 10.0,
	}
	var value_score := MCTSSearchClass._node_value_score(node, 20.0, 0.35)
	if not is_equal_approx(value_score, 17.0):
		return Result.failure("MCTS value should combine path_score and weighted eval: %f" % value_score)
	return Result.success()

static func _test_final_root_selection_preserves_prior_when_under_sampled() -> Result:
	var high_prior := _make_test_node(1, "strategy_best", 5.0, 1, 0.7)
	high_prior["path_score"] = 70.0
	var shallow_q := _make_test_node(1, "shallow_q", 20.0, 2, 0.2)
	shallow_q["path_score"] = 20.0
	var low_prior := _make_test_node(1, "low_prior", 30.0, 1, 0.1)
	low_prior["path_score"] = 10.0
	var under_sampled := MCTSSearchClass._select_final_root_child([shallow_q, low_prior, high_prior], 2, false)
	if not bool(under_sampled.get("prior_guarded", false)):
		return Result.failure("under-sampled root should use prior guard: %s" % str(under_sampled))
	var under_nodes: Array = under_sampled.get("nodes", [])
	if under_nodes.is_empty() or str(Dictionary(under_nodes[0]).get("macro_action_id", "")) != "strategy_best":
		return Result.failure("under-sampled prior guard should preserve strategy prior: %s" % str(under_nodes))

	var enough_samples := MCTSSearchClass._select_final_root_child([shallow_q, low_prior, high_prior], 1, false)
	if bool(enough_samples.get("prior_guarded", false)):
		return Result.failure("sufficient root visits should use visit selection: %s" % str(enough_samples))
	var enough_nodes: Array = enough_samples.get("nodes", [])
	if enough_nodes.is_empty() or str(Dictionary(enough_nodes[0]).get("macro_action_id", "")) != "shallow_q":
		return Result.failure("sufficient root visits should choose by visits/q: %s" % str(enough_nodes))

	var budget_limited := MCTSSearchClass._select_final_root_child([shallow_q, low_prior, high_prior], 0, true)
	if not bool(budget_limited.get("prior_guarded", false)):
		return Result.failure("budget-limited root should use prior guard: %s" % str(budget_limited))
	var budget_nodes: Array = budget_limited.get("nodes", [])
	if budget_nodes.is_empty() or str(Dictionary(budget_nodes[0]).get("macro_action_id", "")) != "strategy_best":
		return Result.failure("budget-limited prior guard should preserve strategy prior: %s" % str(budget_nodes))
	return Result.success()

static func _test_single_candidate_short_circuits_search() -> Result:
	var command := Command.create("skip", 0, {})
	var macro := MacroAction.create("phase_skip", [command], 0.0)
	var payload := {
		"candidate_count": 1,
		"candidate_deduped_count": 0,
		"filter_stats": {},
	}
	var decision_read := MCTSSearchClass._strategy_short_circuit_decision(
		[{
			"macro": macro,
			"macro_action_id": macro.id,
			"action_id": "skip",
			"strategy_score": 12.5,
			"strategy_features": {"skip_penalty": 0.0},
		}],
		payload,
		null,
		AiDecisionContext.create(0, "", "", 1, 0, []),
		StrategyProfileClass.new(),
		{},
		[],
		Time.get_ticks_msec(),
		"single_root_candidate",
		0.35,
		0.55,
		0.92
	)
	if not decision_read.ok:
		return decision_read
	var decision: BotDecision = decision_read.value
	if decision.command != command:
		return Result.failure("single candidate short circuit should return best command")
	if str(decision.trace.get("mcts_short_circuit", "")) != "single_root_candidate":
		return Result.failure("single candidate short circuit should be traced: %s" % str(decision.trace))
	if int(decision.explanation.get("attempted_simulations", -1)) != 0:
		return Result.failure("single candidate short circuit should not simulate: %s" % str(decision.explanation))
	if not is_equal_approx(float(decision.score), 12.5):
		return Result.failure("single candidate short circuit should preserve strategy score: %f" % decision.score)
	return Result.success()

static func _test_pass_only_candidates_short_circuit() -> Result:
	var skip_sub := MacroAction.create("working_skip_sub_phase", [Command.create("skip_sub_phase", 0, {})], -0.1)
	var skip_phase := MacroAction.create("working_skip", [Command.create("skip", 0, {})], -0.1)
	var constructive := MacroAction.create("working_restaurant_0", [Command.create("place_restaurant", 0, {"anchor_pos": Vector2i(0, 0)})], 0.0)
	var pass_scored := [
		{
			"macro": skip_sub,
			"macro_action_id": skip_sub.id,
			"action_id": "skip_sub_phase",
			"strategy_score": -2.0,
		},
		{
			"macro": skip_phase,
			"macro_action_id": skip_phase.id,
			"action_id": "skip",
			"strategy_score": -8.0,
		},
	]
	var reason := MCTSSearchClass._root_short_circuit_reason(pass_scored)
	if reason != "pass_only_root_candidates":
		return Result.failure("pass-only root should short circuit: %s" % reason)
	var constructive_reason := MCTSSearchClass._root_short_circuit_reason(pass_scored + [{
		"macro": constructive,
		"macro_action_id": constructive.id,
		"action_id": "place_restaurant",
		"strategy_score": 5.0,
	}])
	if not constructive_reason.is_empty():
		return Result.failure("constructive root candidate should keep MCTS enabled: %s" % constructive_reason)
	var decision_read := MCTSSearchClass._strategy_short_circuit_decision(
		pass_scored,
		{
			"candidate_count": 2,
			"candidate_deduped_count": 0,
			"filter_stats": {},
		},
		null,
		AiDecisionContext.create(0, "", "", 1, 0, []),
		StrategyProfileClass.new(),
		{},
		[],
		Time.get_ticks_msec(),
		reason,
		0.35,
		0.55,
		0.92
	)
	if not decision_read.ok:
		return decision_read
	var decision: BotDecision = decision_read.value
	if decision.command == null or str(decision.command.action_id) != "skip_sub_phase":
		return Result.failure("pass-only short circuit should return best pass command: %s" % str(decision.command.to_dict() if decision.command != null else {}))
	if str(decision.trace.get("mcts_short_circuit", "")) != "pass_only_root_candidates":
		return Result.failure("pass-only short circuit should be traced: %s" % str(decision.trace))
	if int(decision.explanation.get("attempted_simulations", -1)) != 0:
		return Result.failure("pass-only short circuit should not simulate: %s" % str(decision.explanation))
	return Result.success()

static func _test_mcts_bot_skips_when_no_constructive_legal_action() -> Result:
	var bot := MCTSBotClass.new()
	if bot._has_constructive_mcts_action("working_place_restaurants_growth", ["skip", "skip_sub_phase"]):
		return Result.failure("MCTSBot should skip restaurant MCTS when only pass actions are legal")
	if not bot._has_constructive_mcts_action("working_place_restaurants_growth", ["skip_sub_phase", "place_restaurant"]):
		return Result.failure("MCTSBot should allow restaurant MCTS when placement is legal")
	if bot._has_constructive_mcts_action("working_place_houses_growth", ["skip_sub_phase"]):
		return Result.failure("MCTSBot should skip house MCTS when only pass actions are legal")
	if not bot._has_constructive_mcts_action("working_place_houses_growth", ["add_garden"]):
		return Result.failure("MCTSBot should allow house MCTS when garden placement is legal")
	if not bot._has_constructive_mcts_action("working_recruit_income_route", ["skip_sub_phase"]):
		return Result.failure("MCTSBot should not gate unknown explicitly-enabled strategy ids")
	return Result.success()

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
	if not features.has("mcts_value_score"):
		return Result.failure("MCTSSearch should expose value score: %s" % str(features))
	if not features.has("mcts_path_score"):
		return Result.failure("MCTSSearch should expose path score: %s" % str(features))
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
