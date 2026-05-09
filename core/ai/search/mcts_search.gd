class_name MCTSSearch
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const ForwardSimulatorClass = preload("res://core/ai/simulation/forward_simulator.gd")
const AiEngineForkClass = preload("res://core/ai/simulation/ai_engine_fork.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const EvaluatorClass = preload("res://core/ai/evaluation/evaluator.gd")
const SearchCandidateUtilsClass = preload("res://core/ai/search/search_candidate_utils.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const DEFAULT_MCTS_ITERATIONS := 24
const DEFAULT_MCTS_MAX_DEPTH := 3
const DEFAULT_MCTS_TOP_K_PER_NODE := 4
const DEFAULT_MCTS_EXPLORATION := 1.25
const DEFAULT_MCTS_MIN_SIMULATION_BUDGET_MS := 24

static func choose_command(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget = null,
	options: Dictionary = {}
) -> Result:
	if engine == null:
		return Result.failure("MCTSSearch.choose_command: engine is null")
	if observation == null:
		return Result.failure("MCTSSearch.choose_command: observation is null")
	if context == null:
		return Result.failure("MCTSSearch.choose_command: context is null")
	if budget != null and budget.expired():
		return Result.failure("MCTSSearch.choose_command: budget expired before search")
	var outer_start_ms := Time.get_ticks_msec()
	var fork_start_ms := Time.get_ticks_msec()
	var search_engine_read := AiEngineForkClass.fork_from_engine(engine)
	var fork_ms := Time.get_ticks_msec() - fork_start_ms
	if not search_engine_read.ok:
		engine.activate_registry_bundles()
		return Result.failure("MCTSSearch.choose_command: failed to fork search engine: %s" % search_engine_read.error)
	var search_engine: GameEngine = search_engine_read.value
	var search_read := _choose_command_with_engine(
		search_engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		budget,
		options
	)
	engine.activate_registry_bundles()
	if search_read.ok and search_read.value is BotDecision:
		var decision: BotDecision = search_read.value
		var total_ms := Time.get_ticks_msec() - outer_start_ms
		decision.trace["mcts_fork_ms"] = fork_ms
		decision.trace["mcts_total_time_ms"] = total_ms
		decision.trace["time_ms"] = total_ms
		decision.explanation["time_ms"] = total_ms
		var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
		features["mcts_fork_ms"] = fork_ms
		features["mcts_total_time_ms"] = total_ms
		decision.explanation["features"] = features
	return search_read

static func _choose_command_with_engine(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	_validate_command: Callable,
	budget: TimeBudget = null,
	options: Dictionary = {}
) -> Result:

	var start_ms := Time.get_ticks_msec()
	var search_options: Dictionary = options.duplicate()
	if budget != null:
		search_options["budget"] = budget
	var profile = search_options.get("profile", null)
	if profile == null:
		profile = StrategyProfileClass.new()
		profile.configure_base_revenue()

	var discarded: Array[String] = []
	var root_validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	var root_generate_start_ms := Time.get_ticks_msec()
	var root_read := _generate_scored_candidates(
		engine,
		observation,
		context,
		legal_action_ids,
		root_validate_fn,
		profile,
		search_options,
		discarded
	)
	var root_generate_ms := Time.get_ticks_msec() - root_generate_start_ms
	if not root_read.ok:
		return root_read
	var root_payload: Dictionary = Dictionary(root_read.value)
	var root_scored: Array = root_payload.get("scored", [])
	if root_scored.is_empty():
		return Result.failure("MCTSSearch.choose_command: no root candidates scored: %s" % "; ".join(discarded.slice(0, 8)))

	var iterations := maxi(1, int(search_options.get("mcts_iterations", DEFAULT_MCTS_ITERATIONS)))
	var max_depth := maxi(1, int(search_options.get("mcts_max_depth", DEFAULT_MCTS_MAX_DEPTH)))
	var top_k_per_node := maxi(1, int(search_options.get("mcts_top_k_per_node", DEFAULT_MCTS_TOP_K_PER_NODE)))
	var exploration := maxf(0.0, float(search_options.get("mcts_exploration", DEFAULT_MCTS_EXPLORATION)))
	var min_simulation_budget_ms := maxi(0, int(search_options.get("mcts_min_simulation_budget_ms", DEFAULT_MCTS_MIN_SIMULATION_BUDGET_MS)))
	var root_max_valid_per_action := maxi(1, int(search_options.get("max_valid_per_action", profile.max_valid_per_action)))
	var opponent_max_valid_per_action := maxi(1, int(search_options.get("opponent_max_valid_per_action", root_max_valid_per_action)))

	var root_node := _make_node(engine, context.player_id, null, null, [], 0.0, 0, 1.0)
	root_node["expanded"] = true
	root_node["candidate_count"] = int(root_payload.get("candidate_count", 0))
	root_node["candidate_deduped_count"] = int(root_payload.get("candidate_deduped_count", 0))
	root_node["filter_stats"] = Dictionary(root_payload.get("filter_stats", {})).duplicate(true)
	root_node["unexpanded_entries"] = _prepare_candidate_entries(root_scored, top_k_per_node)
	_assign_candidate_priors(root_node["unexpanded_entries"])

	var root_eval_start_ms := Time.get_ticks_msec()
	var root_eval_read := _evaluate_node(root_node, context.player_id)
	var root_eval_ms := Time.get_ticks_msec() - root_eval_start_ms
	if not root_eval_read.ok:
		return root_eval_read
	var root_eval_payload: Dictionary = Dictionary(root_eval_read.value)
	root_node["leaf_eval_score"] = float(root_eval_payload.get("eval_score", 0.0))
	root_node["leaf_features"] = Dictionary(root_eval_payload.get("features", {})).duplicate(true)

	var attempted_simulations := 0
	var expanded_nodes := 0
	var candidate_deduped_count := int(root_payload.get("candidate_deduped_count", 0))
	var deepest_depth := 0
	var budget_expired := false
	var budget_guarded := false
	var executed_iterations := 0
	var selection_ms := 0
	var simulation_ms := 0
	var max_simulation_ms := 0
	var simulation_budget_skips := 0
	var leaf_eval_ms := 0
	var backprop_ms := 0
	for _iteration in range(iterations):
		if budget != null and budget.expired():
			budget_expired = true
			break
		var selection_start_ms := Time.get_ticks_msec()
		var selection_read := _select_leaf(
			root_node,
			context.player_id,
			profile,
			search_options,
			top_k_per_node,
			root_max_valid_per_action,
			opponent_max_valid_per_action,
			max_depth,
			min_simulation_budget_ms,
			budget,
			exploration,
			discarded
		)
		selection_ms += Time.get_ticks_msec() - selection_start_ms
		if not selection_read.ok:
			return selection_read
		var selection: Dictionary = Dictionary(selection_read.value)
		attempted_simulations += int(selection.get("attempted_simulations", 0))
		expanded_nodes += int(selection.get("expanded_nodes", 0))
		candidate_deduped_count += int(selection.get("candidate_deduped_count", 0))
		simulation_ms += int(selection.get("simulation_ms", 0))
		max_simulation_ms = maxi(max_simulation_ms, int(selection.get("max_simulation_ms", 0)))
		simulation_budget_skips += int(selection.get("simulation_budget_skips", 0))
		if bool(selection.get("budget_expired", false)):
			budget_expired = true
		var selection_budget_guarded := bool(selection.get("budget_guarded", false))
		if selection_budget_guarded:
			budget_guarded = true
		var leaf: Dictionary = selection.get("leaf", null)
		if leaf == null:
			break
		var leaf_eval_start_ms := Time.get_ticks_msec()
		var eval_read := _evaluate_node(leaf, context.player_id)
		leaf_eval_ms += Time.get_ticks_msec() - leaf_eval_start_ms
		if not eval_read.ok:
			return eval_read
		var eval_payload: Dictionary = Dictionary(eval_read.value)
		var leaf_eval_score := float(eval_payload.get("eval_score", 0.0))
		leaf["leaf_eval_score"] = leaf_eval_score
		leaf["leaf_features"] = Dictionary(eval_payload.get("features", {})).duplicate(true)
		var backprop_start_ms := Time.get_ticks_msec()
		_backpropagate(Array(selection.get("path", [])), leaf_eval_score)
		backprop_ms += Time.get_ticks_msec() - backprop_start_ms
		executed_iterations += 1
		deepest_depth = maxi(deepest_depth, int(leaf.get("depth", 0)))
		if bool(selection.get("budget_expired", false)):
			budget_expired = true
			break
		if selection_budget_guarded:
			break

	var root_children: Array = Array(root_node.get("children", []))
	if root_children.is_empty():
		return Result.failure("MCTSSearch.choose_command: no root children evaluated: %s" % "; ".join(discarded.slice(0, 8)))
	var final_sort_start_ms := Time.get_ticks_msec()
	_sort_nodes(root_children)
	var final_sort_ms := Time.get_ticks_msec() - final_sort_start_ms
	var best_child: Dictionary = Dictionary(root_children[0])
	var best_macro: MacroAction = best_child.get("root_macro", null)
	if best_macro == null or best_macro.commands.is_empty():
		return Result.failure("MCTSSearch.choose_command: best node missing root macro")

	var best_command: Command = best_macro.commands[0]
	var best_q := _node_q(best_child)
	var best_visits := int(best_child.get("visits", 0))
	var best_prior := float(best_child.get("prior", 0.0))
	var best_eval_score := float(best_child.get("leaf_eval_score", 0.0))
	var features: Dictionary = Dictionary(best_child.get("leaf_features", {})).duplicate(true)
	features["mcts_final_features"] = Dictionary(best_child.get("leaf_features", {})).duplicate(true)
	features["mcts_iterations"] = executed_iterations
	features["mcts_root_visits"] = int(root_node.get("visits", 0))
	features["mcts_root_q"] = _node_q(root_node)
	features["mcts_root_value_sum"] = float(root_node.get("value_sum", 0.0))
	features["mcts_expanded_nodes"] = expanded_nodes
	features["mcts_attempted_simulations"] = attempted_simulations
	features["mcts_candidate_deduped_count"] = candidate_deduped_count
	features["mcts_deepest_depth"] = deepest_depth
	features["mcts_selected_visits"] = best_visits
	features["mcts_selected_q"] = best_q
	features["mcts_selected_prior"] = best_prior
	features["mcts_eval_score"] = best_eval_score
	features["mcts_root_child_count"] = root_children.size()
	features["mcts_max_depth"] = max_depth
	features["mcts_top_k_per_node"] = top_k_per_node
	features["mcts_exploration"] = exploration
	features["mcts_root_max_valid_per_action"] = root_max_valid_per_action
	features["mcts_opponent_max_valid_per_action"] = opponent_max_valid_per_action
	features["mcts_path"] = Array(best_child.get("path", [])).duplicate(true)
	features["mcts_budget_expired"] = budget_expired
	features["mcts_budget_guarded"] = budget_guarded
	features["mcts_budget_ms"] = int(budget.budget_ms) if budget != null else -1
	features["mcts_budget_elapsed_ms"] = int(budget.elapsed_ms()) if budget != null else -1
	features["mcts_budget_remaining_ms"] = int(budget.remaining_ms()) if budget != null else -1
	features["mcts_root_generate_ms"] = root_generate_ms
	features["mcts_root_eval_ms"] = root_eval_ms
	features["mcts_selection_ms"] = selection_ms
	features["mcts_simulation_ms"] = simulation_ms
	features["mcts_max_simulation_ms"] = max_simulation_ms
	features["mcts_simulation_budget_skips"] = simulation_budget_skips
	features["mcts_min_simulation_budget_ms"] = min_simulation_budget_ms
	features["mcts_leaf_eval_ms"] = leaf_eval_ms
	features["mcts_backprop_ms"] = backprop_ms
	features["mcts_final_sort_ms"] = final_sort_ms

	var top_nodes := _top_node_trace(root_children, 5)
	return Result.success(BotDecision.create(
		best_command,
		best_macro.id,
		best_q,
		{
			"features": features,
			"candidate_count": int(root_payload.get("candidate_count", 0)),
			"valid_candidate_count": root_children.size(),
			"attempted_simulations": attempted_simulations,
			"expanded_nodes": expanded_nodes,
			"candidate_deduped_count": candidate_deduped_count,
			"budget_expired": budget_expired,
			"budget_guarded": budget_guarded,
			"filter_stats": Dictionary(root_payload.get("filter_stats", {})).duplicate(true),
			"time_ms": Time.get_ticks_msec() - start_ms,
		},
		{
			"bot": "MCTSSearch",
			"search": "mcts",
			"strategy_profile": str(profile.id),
			"phase": str(observation.phase),
			"sub_phase": str(observation.sub_phase),
			"player_id": context.player_id,
			"candidate_count": int(root_payload.get("candidate_count", 0)),
			"valid_candidate_count": root_children.size(),
			"attempted_simulations": attempted_simulations,
			"expanded_nodes": expanded_nodes,
			"candidate_deduped_count": candidate_deduped_count,
			"budget_expired": budget_expired,
			"mcts_iterations": executed_iterations,
			"mcts_root_visits": int(root_node.get("visits", 0)),
			"mcts_root_q": _node_q(root_node),
			"mcts_expanded_nodes": expanded_nodes,
			"mcts_attempted_simulations": attempted_simulations,
			"mcts_candidate_deduped_count": candidate_deduped_count,
			"mcts_deepest_depth": deepest_depth,
			"mcts_root_child_count": root_children.size(),
			"mcts_selected_visits": best_visits,
			"mcts_selected_q": best_q,
			"mcts_selected_prior": best_prior,
			"mcts_eval_score": best_eval_score,
			"mcts_budget_guarded": budget_guarded,
			"mcts_root_generate_ms": root_generate_ms,
			"mcts_root_eval_ms": root_eval_ms,
			"mcts_selection_ms": selection_ms,
			"mcts_simulation_ms": simulation_ms,
			"mcts_max_simulation_ms": max_simulation_ms,
			"mcts_simulation_budget_skips": simulation_budget_skips,
			"mcts_min_simulation_budget_ms": min_simulation_budget_ms,
			"mcts_leaf_eval_ms": leaf_eval_ms,
			"mcts_backprop_ms": backprop_ms,
			"mcts_final_sort_ms": final_sort_ms,
			"mcts_top_nodes": top_nodes,
			"discarded_reasons": discarded.slice(0, 20),
			"time_ms": Time.get_ticks_msec() - start_ms,
		}
	))

static func _select_leaf(
	node: Dictionary,
	root_player_id: int,
	profile,
	options: Dictionary,
	top_k_per_node: int,
	root_max_valid_per_action: int,
	opponent_max_valid_per_action: int,
	max_depth: int,
	min_simulation_budget_ms: int,
	budget: TimeBudget,
	exploration: float,
	discarded: Array[String]
) -> Result:
	var path: Array[Dictionary] = []
	var current: Dictionary = node
	var attempted_simulations := 0
	var expanded_nodes := 0
	var candidate_deduped_count := 0
	var simulation_ms := 0
	var max_simulation_ms := 0
	var simulation_budget_skips := 0
	var budget_expired := false
	var budget_guarded := false
	while true:
		path.append(current)
		if int(current.get("depth", 0)) >= max_depth:
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_simulations": attempted_simulations,
				"expanded_nodes": expanded_nodes,
				"candidate_deduped_count": candidate_deduped_count,
				"budget_expired": budget_expired,
			})
		if bool(current.get("terminal", false)):
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_simulations": attempted_simulations,
				"expanded_nodes": expanded_nodes,
				"candidate_deduped_count": candidate_deduped_count,
				"budget_expired": budget_expired,
			})
		if not bool(current.get("expanded", false)):
			var populate_read := _populate_node_candidates(
				current,
				root_player_id,
				profile,
				options,
				top_k_per_node,
				root_max_valid_per_action,
				opponent_max_valid_per_action,
				budget,
				discarded
			)
			if not populate_read.ok:
				return populate_read
			var populate_payload: Dictionary = Dictionary(populate_read.value)
			candidate_deduped_count += int(populate_payload.get("candidate_deduped_count", 0))
			if bool(populate_payload.get("budget_expired", false)):
				budget_expired = true
				return Result.success({
					"leaf": current,
					"path": path,
					"attempted_simulations": attempted_simulations,
					"expanded_nodes": expanded_nodes,
					"candidate_deduped_count": candidate_deduped_count,
					"budget_expired": budget_expired,
				})
		var unexpanded_val = current.get("unexpanded_entries", [])
		if unexpanded_val is Array and not Array(unexpanded_val).is_empty():
			var expand_read := _expand_next_child(current, budget, min_simulation_budget_ms, discarded)
			if not expand_read.ok:
				return expand_read
			var expand_payload: Dictionary = Dictionary(expand_read.value)
			var expanded_now := int(expand_payload.get("expanded_nodes", 0)) > 0
			attempted_simulations += int(expand_payload.get("attempted_simulations", 0))
			expanded_nodes += int(expand_payload.get("expanded_nodes", 0))
			simulation_ms += int(expand_payload.get("simulation_ms", 0))
			max_simulation_ms = maxi(max_simulation_ms, int(expand_payload.get("max_simulation_ms", 0)))
			simulation_budget_skips += int(expand_payload.get("simulation_budget_skips", 0))
			if bool(expand_payload.get("budget_expired", false)):
				budget_expired = true
			if bool(expand_payload.get("budget_guarded", false)):
				budget_guarded = true
			var leaf_val = expand_payload.get("leaf", null)
			if leaf_val is Dictionary:
				var leaf: Dictionary = Dictionary(leaf_val)
				if expanded_now:
					path.append(leaf)
				return Result.success({
					"leaf": leaf,
					"path": path,
					"attempted_simulations": attempted_simulations,
					"expanded_nodes": expanded_nodes,
					"candidate_deduped_count": candidate_deduped_count,
					"budget_expired": budget_expired,
					"budget_guarded": budget_guarded,
					"simulation_ms": simulation_ms,
					"max_simulation_ms": max_simulation_ms,
					"simulation_budget_skips": simulation_budget_skips,
				})
			current["terminal"] = true
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_simulations": attempted_simulations,
				"expanded_nodes": expanded_nodes,
				"candidate_deduped_count": candidate_deduped_count,
				"budget_expired": budget_expired,
				"budget_guarded": budget_guarded,
				"simulation_ms": simulation_ms,
				"max_simulation_ms": max_simulation_ms,
				"simulation_budget_skips": simulation_budget_skips,
			})
		var children_val = current.get("children", [])
		if not (children_val is Array) or Array(children_val).is_empty():
			current["terminal"] = true
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_simulations": attempted_simulations,
				"expanded_nodes": expanded_nodes,
				"candidate_deduped_count": candidate_deduped_count,
				"budget_expired": budget_expired,
			})
		var selected: Variant = _select_best_child(current, root_player_id, exploration)
		if selected == null:
			current["terminal"] = true
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_simulations": attempted_simulations,
				"expanded_nodes": expanded_nodes,
				"candidate_deduped_count": candidate_deduped_count,
				"budget_expired": budget_expired,
			})
		current = selected
	return Result.failure("MCTSSearch._select_leaf: unexpected selection exit")

static func _populate_node_candidates(
	node: Dictionary,
	root_player_id: int,
	profile,
	options: Dictionary,
	top_k_per_node: int,
	root_max_valid_per_action: int,
	opponent_max_valid_per_action: int,
	budget: TimeBudget,
	discarded: Array[String]
) -> Result:
	if budget != null and budget.expired():
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": true,
		})
	if bool(node.get("expanded", false)):
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})

	var engine: GameEngine = node.get("engine", null)
	if engine == null:
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})
	var actor_id := int(node.get("actor_id", -1))
	if actor_id < 0:
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})

	var observation_read := ObservationAdapterClass.observe_for_player(engine, actor_id)
	if not observation_read.ok:
		discarded.append("mcts: observation failed for player %d: %s" % [actor_id, observation_read.error])
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})
	var observation: ObservationState = observation_read.value
	node["observation"] = observation

	var context_read := AiDecisionContext.from_observation(
		observation,
		_make_decision_seed(engine, actor_id),
		_allowed_internal_actions(observation)
	)
	if not context_read.ok:
		discarded.append("mcts: context failed for player %d: %s" % [actor_id, context_read.error])
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})
	var context: AiDecisionContext = context_read.value
	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not ids_read.ok:
		discarded.append("mcts: legal action lookup failed for player %d: %s" % [actor_id, ids_read.error])
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})
	var legal_ids: Array[String] = ids_read.value
	if legal_ids.is_empty():
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})

	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	var node_options := options.duplicate()
	node_options["max_valid_per_action"] = root_max_valid_per_action if actor_id == root_player_id else opponent_max_valid_per_action
	var gen_read := _generate_scored_candidates(
		engine,
		observation,
		context,
		legal_ids,
		validate_fn,
		profile,
		node_options,
		discarded
	)
	if not gen_read.ok:
		discarded.append("mcts: candidate generation failed for player %d: %s" % [actor_id, gen_read.error])
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"candidate_deduped_count": 0,
			"budget_expired": false,
		})

	var gen_payload: Dictionary = Dictionary(gen_read.value)
	var scored: Array = gen_payload.get("scored", [])
	var candidate_deduped_count := int(gen_payload.get("candidate_deduped_count", 0))
	var limit := mini(top_k_per_node, scored.size())
	var entries: Array[Dictionary] = SearchCandidateUtilsClass.copy_scored_candidates(scored.slice(0, limit))
	_assign_candidate_priors(entries)
	node["unexpanded_entries"] = entries
	node["candidate_count"] = int(gen_payload.get("candidate_count", 0))
	node["candidate_deduped_count"] = candidate_deduped_count
	node["filter_stats"] = Dictionary(gen_payload.get("filter_stats", {})).duplicate(true)
	node["expanded"] = true
	if entries.is_empty():
		node["terminal"] = true
	return Result.success({
		"attempted_simulations": 0,
		"expanded_nodes": 0,
		"candidate_deduped_count": candidate_deduped_count,
		"budget_expired": false,
	})

static func _expand_next_child(node: Dictionary, budget: TimeBudget, min_simulation_budget_ms: int, discarded: Array[String]) -> Result:
	var entries_val = node.get("unexpanded_entries", [])
	if not (entries_val is Array):
		node["terminal"] = true
		return Result.success({
			"leaf": node,
			"attempted_simulations": 0,
			"expanded_nodes": 0,
			"budget_expired": false,
			"budget_guarded": false,
			"simulation_ms": 0,
			"max_simulation_ms": 0,
			"simulation_budget_skips": 0,
		})
	var entries: Array = entries_val
	var attempted := 0
	var simulation_ms := 0
	var max_simulation_ms := 0
	while not entries.is_empty():
		if budget != null and budget.expired():
			return Result.success({
				"leaf": node,
				"attempted_simulations": attempted,
				"expanded_nodes": 0,
				"budget_expired": true,
				"budget_guarded": false,
				"simulation_ms": simulation_ms,
				"max_simulation_ms": max_simulation_ms,
				"simulation_budget_skips": 0,
			})
		if _should_skip_simulation_for_budget(budget, min_simulation_budget_ms):
			discarded.append("mcts: remaining budget %dms is below simulation floor %dms" % [budget.remaining_ms(), min_simulation_budget_ms])
			return Result.success({
				"leaf": node,
				"attempted_simulations": attempted,
				"expanded_nodes": 0,
				"budget_expired": false,
				"budget_guarded": true,
				"simulation_ms": simulation_ms,
				"max_simulation_ms": max_simulation_ms,
				"simulation_budget_skips": 1,
			})
		var entry_val = entries[0]
		entries.remove_at(0)
		node["unexpanded_entries"] = entries
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_val)
		var macro: MacroAction = entry.get("macro", null)
		if macro == null or macro.commands.is_empty():
			discarded.append("mcts: empty macro candidate")
			continue
		attempted += 1
		var sim_start_ms := Time.get_ticks_msec()
		var sim_read := ForwardSimulatorClass.simulate_commands(node.get("engine", null), macro.commands, {
			"mode": "after_command",
			"budget": budget,
		})
		var sim_elapsed_ms := Time.get_ticks_msec() - sim_start_ms
		simulation_ms += sim_elapsed_ms
		max_simulation_ms = maxi(max_simulation_ms, sim_elapsed_ms)
		if not sim_read.ok:
			discarded.append("%s: mcts simulation failed: %s" % [macro.id, sim_read.error])
			if budget != null and budget.expired():
				return Result.success({
					"leaf": node,
					"attempted_simulations": attempted,
					"expanded_nodes": 0,
					"budget_expired": true,
					"budget_guarded": false,
					"simulation_ms": simulation_ms,
					"max_simulation_ms": max_simulation_ms,
					"simulation_budget_skips": 0,
				})
			continue
		var sim_payload: Dictionary = Dictionary(sim_read.value)
		var sim_engine: GameEngine = sim_payload.get("engine", null)
		if sim_engine == null:
			discarded.append("%s: mcts simulation missing engine" % macro.id)
			continue
		var child_actor := BotControllerClass.resolve_next_player_id(sim_engine)
		if child_actor < 0:
			discarded.append("%s: mcts cannot resolve next player" % macro.id)
			continue
		var root_macro: MacroAction = node.get("root_macro", null)
		if root_macro == null:
			root_macro = macro
		var path: Array = Array(node.get("path", [])).duplicate(true)
		path.append(_path_item(macro, int(node.get("actor_id", -1)), float(entry.get("strategy_score", 0.0)), float(entry.get("prior", 0.0))))
		var child := _make_node(
			sim_engine,
			child_actor,
			root_macro,
			macro,
			path,
			float(node.get("path_score", 0.0)) + float(entry.get("strategy_score", 0.0)),
			int(node.get("depth", 0)) + 1,
			float(entry.get("prior", 0.0))
		)
		child["strategy_score"] = float(entry.get("strategy_score", 0.0))
		child["action_id"] = str(entry.get("action_id", ""))
		child["macro_action_id"] = str(entry.get("macro_action_id", ""))
		child["leaf_features"] = {}
		var children: Array = node.get("children", [])
		children.append(child)
		node["children"] = children
		return Result.success({
			"leaf": child,
			"attempted_simulations": attempted,
			"expanded_nodes": 1,
			"budget_expired": budget != null and budget.expired(),
			"budget_guarded": false,
			"simulation_ms": simulation_ms,
			"max_simulation_ms": max_simulation_ms,
			"simulation_budget_skips": 0,
		})
	node["terminal"] = true
	return Result.success({
		"leaf": node,
		"attempted_simulations": attempted,
		"expanded_nodes": 0,
		"budget_expired": false,
		"budget_guarded": false,
		"simulation_ms": simulation_ms,
		"max_simulation_ms": max_simulation_ms,
		"simulation_budget_skips": 0,
	})

static func _should_skip_simulation_for_budget(budget: TimeBudget, min_simulation_budget_ms: int) -> bool:
	if budget == null:
		return false
	if min_simulation_budget_ms <= 0:
		return false
	return budget.remaining_ms() < min_simulation_budget_ms

static func _generate_scored_candidates(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	profile,
	options: Dictionary,
	discarded: Array[String]
) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if observation == null:
		return Result.failure("observation is null")
	if context == null:
		return Result.failure("context is null")

	var gen_options := options.duplicate()
	gen_options["source_state"] = engine.get_state()
	gen_options["max_valid_per_action"] = maxi(1, int(options.get("max_valid_per_action", profile.max_valid_per_action)))
	var gen_read := CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_command, gen_options)
	if not gen_read.ok:
		return gen_read
	var gen_payload: Dictionary = Dictionary(gen_read.value)
	var candidates_val = gen_payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.failure("CandidateGenerator returned invalid candidates")
	var candidates: Array = candidates_val
	if candidates.is_empty():
		return Result.failure("no candidates generated")
	discarded.append_array(_copy_string_array(gen_payload.get("discarded_reasons", [])))

	var source_state := engine.get_state()
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile, source_state)
	var filter_payload: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, candidates, profile, {
		"source_state": source_state,
		"income_analysis": income_analysis,
	})
	var filtered_val = filter_payload.get("candidates", [])
	if not (filtered_val is Array):
		return Result.failure("StrategyCandidateFilter returned invalid candidates")
	candidates = filtered_val
	discarded.append_array(_copy_string_array(filter_payload.get("discarded_reasons", [])))
	if candidates.is_empty():
		return Result.failure("StrategyCandidateFilter discarded all candidates")

	var scored := _score_candidates(observation, candidates, profile, engine.get_state(), discarded)
	if scored.is_empty():
		return Result.failure("no candidates scored")
	_sort_scored_candidates(scored)
	var dedupe_payload := _dedupe_scored_candidates(scored)
	scored = SearchCandidateUtilsClass.copy_scored_candidates(dedupe_payload.get("scored", []))
	_sort_scored_candidates(scored)
	return Result.success({
		"scored": scored,
		"candidate_count": candidates.size(),
		"candidate_deduped_count": int(dedupe_payload.get("deduped_count", 0)),
		"filter_stats": Dictionary(filter_payload.get("stats", {})).duplicate(true),
	})

static func _score_candidates(
	observation: ObservationState,
	candidates: Array,
	profile,
	source_state: GameState,
	discarded: Array[String]
) -> Array[Dictionary]:
	var scored: Array[Dictionary] = []
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			discarded.append("candidate is not MacroAction")
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			discarded.append("%s: empty command list" % macro.id)
			continue
		var score_payload := StrategyScorerClass.score_macro(observation, macro, profile, {"source_state": source_state})
		var first_command: Command = macro.commands[0]
		scored.append({
			"macro": macro,
			"macro_action_id": macro.id,
			"action_id": str(first_command.action_id),
			"strategy_score": float(score_payload.get("score", -INF)),
			"strategy_features": Dictionary(score_payload.get("features", {})).duplicate(true),
			"tags": macro.tags.duplicate(),
		})
	return scored

static func _evaluate_node(node: Dictionary, root_player_id: int) -> Result:
	var engine: GameEngine = node.get("engine", null)
	if engine == null:
		return Result.failure("node engine is null")
	var obs_read := ObservationAdapterClass.observe_for_player(engine, root_player_id)
	if not obs_read.ok:
		return obs_read
	var eval_read := EvaluatorClass.score_observation(obs_read.value, root_player_id)
	if not eval_read.ok:
		return eval_read
	var eval_payload: Dictionary = Dictionary(eval_read.value)
	var out := node.duplicate(true)
	out["eval_score"] = float(eval_payload.get("score", 0.0))
	out["features"] = {
		"mcts_final_features": Dictionary(eval_payload.get("features", {})).duplicate(true),
	}
	return Result.success(out)

static func _make_node(
	engine: GameEngine,
	actor_id: int,
	root_macro: MacroAction,
	macro: MacroAction,
	path: Array,
	path_score: float,
	depth: int,
	prior: float
) -> Dictionary:
	return {
		"engine": engine,
		"actor_id": actor_id,
		"root_macro": root_macro,
		"root_macro_id": str(root_macro.id) if root_macro != null else "",
		"macro": macro,
		"macro_action_id": str(macro.id) if macro != null else "",
		"action_id": str(macro.commands[0].action_id) if macro != null and not macro.commands.is_empty() else "",
		"state_key": _state_key_for_engine(engine),
		"path": path.duplicate(true),
		"path_score": float(path_score),
		"depth": int(depth),
		"prior": float(prior),
		"visits": 0,
		"value_sum": 0.0,
		"q": 0.0,
		"leaf_eval_score": 0.0,
		"leaf_features": {},
		"children": [],
		"unexpanded_entries": [],
		"expanded": false,
		"terminal": false,
		"candidate_count": 0,
		"candidate_deduped_count": 0,
		"filter_stats": {},
		"strategy_score": 0.0,
	}

static func _path_item(macro: MacroAction, actor: int, strategy_score: float, prior: float) -> Dictionary:
	var command: Command = macro.commands[0] if macro != null and not macro.commands.is_empty() else null
	return {
		"actor": actor,
		"macro_action_id": str(macro.id) if macro != null else "",
		"action_id": str(command.action_id) if command != null else "",
		"params": command.params.duplicate(true) if command != null else {},
		"strategy_score": float(strategy_score),
		"prior": float(prior),
		"score_contribution": float(strategy_score),
	}

static func _backpropagate(path: Array, leaf_value: float) -> void:
	for node_val in path:
		if not (node_val is Dictionary):
			continue
		var node: Dictionary = node_val
		node["visits"] = int(node.get("visits", 0)) + 1
		node["value_sum"] = float(node.get("value_sum", 0.0)) + leaf_value
		node["q"] = _node_q(node)
		node["leaf_eval_score"] = leaf_value

static func _node_q(node: Dictionary) -> float:
	var visits := int(node.get("visits", 0))
	if visits <= 0:
		return 0.0
	return float(node.get("value_sum", 0.0)) / float(visits)

static func _select_best_child(node: Dictionary, root_player_id: int, exploration: float) -> Variant:
	var children_val = node.get("children", [])
	if not (children_val is Array):
		return null
	var children: Array = children_val
	if children.is_empty():
		return null
	var parent_visits := maxi(1, int(node.get("visits", 0)))
	var best_child = null
	var best_score := -INF
	var best_visits := -1
	var best_prior := -INF
	var best_macro_id := ""
	for child_val in children:
		if not (child_val is Dictionary):
			continue
		var child: Dictionary = child_val
		var sign := 1.0 if int(child.get("actor_id", -1)) == root_player_id else -1.0
		var prior := maxf(0.0, float(child.get("prior", 0.0)))
		var q := _node_q(child)
		var child_visits := int(child.get("visits", 0))
		var score := sign * q + exploration * prior * sqrt(float(parent_visits)) / float(child_visits + 1)
		var macro_id := str(child.get("macro_action_id", ""))
		if best_child == null or score > best_score or (is_equal_approx(score, best_score) and (child_visits > best_visits or (child_visits == best_visits and (prior > best_prior or (is_equal_approx(prior, best_prior) and macro_id < best_macro_id))))) :
			best_child = child
			best_score = score
			best_visits = child_visits
			best_prior = prior
			best_macro_id = macro_id
	return best_child

static func _assign_candidate_priors(entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		return
	var min_score := INF
	for entry in entries:
		min_score = minf(min_score, float(entry.get("strategy_score", 0.0)))
	var total_weight := 0.0
	var weights: Array[float] = []
	for entry in entries:
		var weight := maxf(0.0, float(entry.get("strategy_score", 0.0)) - min_score) + 1.0
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0:
		total_weight = float(entries.size())
		for i in range(entries.size()):
			entries[i]["prior"] = 1.0 / total_weight
		return
	for i in range(entries.size()):
		entries[i]["prior"] = weights[i] / total_weight

static func _prepare_candidate_entries(scored: Array, top_k_per_node: int) -> Array[Dictionary]:
	var limit := mini(maxi(1, top_k_per_node), scored.size())
	return SearchCandidateUtilsClass.copy_scored_candidates(scored.slice(0, limit))

static func _dedupe_scored_candidates(scored: Array[Dictionary]) -> Dictionary:
	return SearchCandidateUtilsClass.dedupe_scored_candidates(scored)

static func _sort_scored_candidates(scored: Array[Dictionary]) -> void:
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ascore := float(a.get("strategy_score", 0.0))
		var bscore := float(b.get("strategy_score", 0.0))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		return str(a.get("macro_action_id", "")) < str(b.get("macro_action_id", ""))
	)

static func _sort_nodes(nodes: Array) -> void:
	nodes.sort_custom(func(a, b) -> bool:
		if not (a is Dictionary):
			return false
		if not (b is Dictionary):
			return true
		var ad: Dictionary = a
		var bd: Dictionary = b
		var avisits := int(ad.get("visits", 0))
		var bvisits := int(bd.get("visits", 0))
		if avisits != bvisits:
			return avisits > bvisits
		var aq := _node_q(ad)
		var bq := _node_q(bd)
		if not is_equal_approx(aq, bq):
			return aq > bq
		var aprior := float(ad.get("prior", 0.0))
		var bprior := float(bd.get("prior", 0.0))
		if not is_equal_approx(aprior, bprior):
			return aprior > bprior
		var apath := float(ad.get("path_score", 0.0))
		var bpath := float(bd.get("path_score", 0.0))
		if not is_equal_approx(apath, bpath):
			return apath > bpath
		return str(ad.get("macro_action_id", "")) < str(bd.get("macro_action_id", ""))
	)

static func _top_node_trace(nodes: Array, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var limit := mini(maxi(0, count), nodes.size())
	for i in range(limit):
		var node: Dictionary = nodes[i]
		out.append({
			"root_macro_id": str(node.get("root_macro_id", "")),
			"macro_action_id": str(node.get("macro_action_id", "")),
			"visits": int(node.get("visits", 0)),
			"q": _node_q(node),
			"prior": float(node.get("prior", 0.0)),
			"leaf_eval_score": float(node.get("leaf_eval_score", 0.0)),
			"depth": int(node.get("depth", 0)),
			"path_score": float(node.get("path_score", 0.0)),
			"path": Array(node.get("path", [])).duplicate(true),
		})
	return out

static func _state_key_for_engine(engine: GameEngine) -> String:
	if engine == null:
		return ""
	var state := engine.get_state()
	if state == null:
		return ""
	var hash_value := str(state.compute_hash())
	var phase := str(state.phase)
	var sub_phase := str(state.sub_phase)
	var next_player := BotControllerClass.resolve_next_player_id(engine)
	return "%s|%s|%s|%d" % [hash_value, phase, sub_phase, next_player]

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

static func _make_decision_seed(engine: GameEngine, player_id: int) -> int:
	if engine == null:
		return player_id
	var state := engine.get_state()
	if state == null:
		return player_id
	return int(state.round_number) * 100000 + int(engine.command_history.size()) * 100 + player_id

static func _copy_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			out.append(str(item))
	return out
