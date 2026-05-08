class_name BeamSearch
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const ForwardSimulatorClass = preload("res://core/ai/simulation/forward_simulator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const EvaluatorClass = preload("res://core/ai/evaluation/evaluator.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const DEFAULT_BEAM_WIDTH := 4
const DEFAULT_MAX_DEPTH := 3
const DEFAULT_TOP_K_PER_NODE := 3
const DEFAULT_EVALUATOR_WEIGHT := 0.35
const DEFAULT_OPPONENT_WEIGHT := 0.55
const DEFAULT_PATH_DISCOUNT := 0.92

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
		return Result.failure("BeamSearch.choose_command: engine is null")
	if observation == null:
		return Result.failure("BeamSearch.choose_command: observation is null")
	if context == null:
		return Result.failure("BeamSearch.choose_command: context is null")
	if budget != null and budget.expired():
		return Result.failure("BeamSearch.choose_command: budget expired before search")

	var start_ms := Time.get_ticks_msec()
	var profile = options.get("profile", null)
	if profile == null:
		profile = StrategyProfileClass.new()
		profile.configure_base_revenue()

	var discarded: Array[String] = []
	var root_read := _generate_scored_candidates(
		engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		profile,
		options,
		discarded
	)
	if not root_read.ok:
		return root_read
	var root_payload: Dictionary = root_read.value
	var root_scored: Array = root_payload.get("scored", [])
	if root_scored.is_empty():
		return Result.failure("BeamSearch.choose_command: no root candidates scored: %s" % "; ".join(discarded.slice(0, 8)))

	var beam_width := maxi(1, int(options.get("beam_width", DEFAULT_BEAM_WIDTH)))
	var max_depth := maxi(1, int(options.get("max_depth", DEFAULT_MAX_DEPTH)))
	var top_k_per_node := maxi(1, int(options.get("top_k_per_node", DEFAULT_TOP_K_PER_NODE)))
	var evaluator_weight := float(options.get("evaluator_weight", DEFAULT_EVALUATOR_WEIGHT))
	var opponent_weight := float(options.get("opponent_weight", DEFAULT_OPPONENT_WEIGHT))
	var path_discount := clampf(float(options.get("path_discount", DEFAULT_PATH_DISCOUNT)), 0.0, 1.0)

	var attempted_simulations := 0
	var expanded_nodes := 0
	var deepest_depth := 0
	var budget_expired := false
	var initial_nodes: Array[Dictionary] = []
	var root_limit := mini(top_k_per_node, root_scored.size())
	for i in range(root_limit):
		if budget != null and budget.expired() and attempted_simulations > 0:
			budget_expired = true
			break
		var root_entry: Dictionary = root_scored[i]
		var root_macro: MacroAction = root_entry.get("macro", null)
		if root_macro == null or root_macro.commands.is_empty():
			continue
		attempted_simulations += 1
		var sim_read := ForwardSimulatorClass.simulate_commands(engine, root_macro.commands, {"mode": "after_command"})
		if not sim_read.ok:
			discarded.append("%s: root simulation failed: %s" % [root_macro.id, sim_read.error])
			continue
		var sim_payload: Dictionary = Dictionary(sim_read.value)
		var sim_engine: GameEngine = sim_payload.get("engine", null)
		if sim_engine == null:
			discarded.append("%s: root simulation missing engine" % root_macro.id)
			continue
		var node := _make_node(
			sim_engine,
			root_macro,
			[
				_path_item(root_macro, context.player_id, float(root_entry.get("strategy_score", 0.0)), 1.0),
			],
			float(root_entry.get("strategy_score", 0.0)),
			1
		)
		var eval_read := _evaluate_node(node, context.player_id, evaluator_weight)
		if not eval_read.ok:
			discarded.append("%s: root node evaluation failed: %s" % [root_macro.id, eval_read.error])
			continue
		initial_nodes.append(eval_read.value)
		deepest_depth = maxi(deepest_depth, 1)

	if initial_nodes.is_empty():
		return Result.failure("BeamSearch.choose_command: no root candidate simulated successfully: %s" % "; ".join(discarded.slice(0, 8)))
	_sort_nodes(initial_nodes)
	var beam := initial_nodes.slice(0, beam_width)
	var all_evaluated := beam.duplicate(true)

	for depth in range(2, max_depth + 1):
		if budget != null and budget.expired():
			budget_expired = true
			break
		var next_nodes: Array[Dictionary] = []
		for node_val in beam:
			if budget != null and budget.expired():
				budget_expired = true
				break
			var node: Dictionary = node_val
			var expansion_read := _expand_node(
				node,
				context.player_id,
				profile,
				options,
				top_k_per_node,
				opponent_weight,
				path_discount,
				budget,
				discarded
			)
			if not expansion_read.ok:
				discarded.append("%s: expansion skipped: %s" % [str(node.get("root_macro_id", "")), expansion_read.error])
				continue
			var expansion: Dictionary = expansion_read.value
			attempted_simulations += int(expansion.get("attempted_simulations", 0))
			expanded_nodes += int(expansion.get("expanded_nodes", 0))
			if bool(expansion.get("budget_expired", false)):
				budget_expired = true
			var children: Array = expansion.get("nodes", [])
			for child_val in children:
				if not (child_val is Dictionary):
					continue
				var eval_child := _evaluate_node(Dictionary(child_val), context.player_id, evaluator_weight)
				if not eval_child.ok:
					discarded.append("child evaluation failed: %s" % eval_child.error)
					continue
				next_nodes.append(eval_child.value)
		if next_nodes.is_empty():
			break
		_sort_nodes(next_nodes)
		deepest_depth = maxi(deepest_depth, depth)
		beam = next_nodes.slice(0, beam_width)
		all_evaluated.append_array(beam)

	if all_evaluated.is_empty():
		return Result.failure("BeamSearch.choose_command: no beam nodes evaluated")
	_sort_nodes(all_evaluated)
	var best_node: Dictionary = all_evaluated[0]
	var best_macro: MacroAction = best_node.get("root_macro", null)
	if best_macro == null or best_macro.commands.is_empty():
		return Result.failure("BeamSearch.choose_command: best node missing root macro")
	var best_command: Command = best_macro.commands[0]
	var features: Dictionary = Dictionary(best_node.get("features", {})).duplicate(true)
	features["beam_width"] = beam_width
	features["beam_max_depth"] = max_depth
	features["beam_deepest_depth"] = deepest_depth
	features["beam_top_k_per_node"] = top_k_per_node
	features["beam_path"] = Array(best_node.get("path", [])).duplicate(true)
	features["beam_selected_depth"] = int(best_node.get("depth", 0))
	features["beam_path_score"] = float(best_node.get("path_score", 0.0))
	features["beam_eval_score"] = float(best_node.get("eval_score", 0.0))
	features["beam_evaluator_weight"] = evaluator_weight
	features["beam_opponent_weight"] = opponent_weight
	features["beam_path_discount"] = path_discount
	features["beam_attempted_simulations"] = attempted_simulations
	features["beam_expanded_nodes"] = expanded_nodes
	features["beam_budget_expired"] = budget_expired
	features["beam_budget_ms"] = int(budget.budget_ms) if budget != null else -1
	features["beam_budget_elapsed_ms"] = int(budget.elapsed_ms()) if budget != null else -1
	features["beam_budget_remaining_ms"] = int(budget.remaining_ms()) if budget != null else -1

	var top_nodes := _top_node_trace(all_evaluated, 5)
	return Result.success(BotDecision.create(
		best_command,
		best_macro.id,
		float(best_node.get("total_score", 0.0)),
		{
			"features": features,
			"candidate_count": int(root_payload.get("candidate_count", 0)),
			"valid_candidate_count": all_evaluated.size(),
			"attempted_simulations": attempted_simulations,
			"expanded_nodes": expanded_nodes,
			"budget_expired": budget_expired,
			"filter_stats": Dictionary(root_payload.get("filter_stats", {})).duplicate(true),
		},
		{
			"bot": "BeamSearch",
			"search": "beam",
			"strategy_profile": str(profile.id),
			"phase": str(observation.phase),
			"sub_phase": str(observation.sub_phase),
			"player_id": context.player_id,
			"candidate_count": int(root_payload.get("candidate_count", 0)),
			"valid_candidate_count": all_evaluated.size(),
			"attempted_simulations": attempted_simulations,
			"expanded_nodes": expanded_nodes,
			"budget_expired": budget_expired,
			"beam_width": beam_width,
			"max_depth": max_depth,
			"deepest_depth": deepest_depth,
			"top_nodes": top_nodes,
			"discarded_reasons": discarded.slice(0, 20),
			"time_ms": Time.get_ticks_msec() - start_ms,
		}
	))

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
	gen_options["max_valid_per_action"] = maxi(1, int(profile.max_valid_per_action))
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
	return Result.success({
		"scored": scored,
		"candidate_count": candidates.size(),
		"filter_stats": Dictionary(filter_payload.get("stats", {})).duplicate(true),
	})

static func _expand_node(
	node: Dictionary,
	root_player_id: int,
	profile,
	options: Dictionary,
	top_k_per_node: int,
	opponent_weight: float,
	path_discount: float,
	budget: TimeBudget,
	discarded: Array[String]
) -> Result:
	var engine: GameEngine = node.get("engine", null)
	if engine == null:
		return Result.failure("node engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("node state is null")
	if str(state.phase) == DefsClass.PHASE_GAME_OVER:
		return Result.failure("node is game over")
	var actor := BotControllerClass.resolve_next_player_id(engine)
	if actor < 0:
		return Result.failure("cannot resolve next player")
	var observation_read := ObservationAdapterClass.observe_for_player(engine, actor)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var context_read := AiDecisionContext.from_observation(
		observation,
		_make_decision_seed(engine, actor),
		_allowed_internal_actions(observation)
	)
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value
	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not ids_read.ok:
		return ids_read
	var legal_ids: Array[String] = ids_read.value
	if legal_ids.is_empty():
		return Result.failure("no legal actions")
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	var gen_read := _generate_scored_candidates(engine, observation, context, legal_ids, validate_fn, profile, options, discarded)
	if not gen_read.ok:
		return gen_read
	var scored: Array = Dictionary(gen_read.value).get("scored", [])
	var limit := mini(maxi(1, top_k_per_node), scored.size())
	var attempted := 0
	var expanded := 0
	var children: Array[Dictionary] = []
	var budget_expired := false
	var contribution_factor := 1.0 if actor == root_player_id else -maxf(0.0, opponent_weight)
	var depth := int(node.get("depth", 0)) + 1
	var discount := pow(path_discount, float(maxi(0, depth - 1)))
	for i in range(limit):
		if budget != null and budget.expired() and attempted > 0:
			budget_expired = true
			break
		var entry: Dictionary = scored[i]
		var macro: MacroAction = entry.get("macro", null)
		if macro == null or macro.commands.is_empty():
			continue
		attempted += 1
		var sim_read := ForwardSimulatorClass.simulate_commands(engine, macro.commands, {"mode": "after_command"})
		if not sim_read.ok:
			discarded.append("%s: beam simulation failed: %s" % [macro.id, sim_read.error])
			continue
		var sim_payload: Dictionary = Dictionary(sim_read.value)
		var sim_engine: GameEngine = sim_payload.get("engine", null)
		if sim_engine == null:
			discarded.append("%s: beam simulation missing engine" % macro.id)
			continue
		var strategy_score := float(entry.get("strategy_score", 0.0))
		var contribution := strategy_score * contribution_factor * discount
		var path := Array(node.get("path", [])).duplicate(true)
		path.append(_path_item(macro, actor, strategy_score, contribution_factor * discount))
		children.append(_make_node(
			sim_engine,
			node.get("root_macro", null),
			path,
			float(node.get("path_score", 0.0)) + contribution,
			depth
		))
		expanded += 1
	return Result.success({
		"nodes": children,
		"attempted_simulations": attempted,
		"expanded_nodes": expanded,
		"budget_expired": budget_expired,
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

static func _evaluate_node(node: Dictionary, root_player_id: int, evaluator_weight: float) -> Result:
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
	var eval_score := float(eval_payload.get("score", 0.0))
	var path_score := float(node.get("path_score", 0.0))
	out["eval_score"] = eval_score
	out["total_score"] = path_score + eval_score * evaluator_weight
	out["features"] = {
		"beam_final_features": Dictionary(eval_payload.get("features", {})).duplicate(true),
	}
	return Result.success(out)

static func _make_node(
	engine: GameEngine,
	root_macro: MacroAction,
	path: Array,
	path_score: float,
	depth: int
) -> Dictionary:
	return {
		"engine": engine,
		"root_macro": root_macro,
		"root_macro_id": str(root_macro.id) if root_macro != null else "",
		"path": path.duplicate(true),
		"path_score": float(path_score),
		"depth": int(depth),
		"eval_score": 0.0,
		"total_score": -INF,
		"features": {},
	}

static func _path_item(macro: MacroAction, actor: int, strategy_score: float, contribution_factor: float) -> Dictionary:
	var command: Command = macro.commands[0] if macro != null and not macro.commands.is_empty() else null
	return {
		"actor": actor,
		"macro_action_id": str(macro.id) if macro != null else "",
		"action_id": str(command.action_id) if command != null else "",
		"params": command.params.duplicate(true) if command != null else {},
		"strategy_score": float(strategy_score),
		"contribution_factor": float(contribution_factor),
		"score_contribution": float(strategy_score) * float(contribution_factor),
	}

static func _top_node_trace(nodes: Array, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var limit := mini(maxi(0, count), nodes.size())
	for i in range(limit):
		var node: Dictionary = nodes[i]
		out.append({
			"root_macro_id": str(node.get("root_macro_id", "")),
			"score": float(node.get("total_score", 0.0)),
			"path_score": float(node.get("path_score", 0.0)),
			"eval_score": float(node.get("eval_score", 0.0)),
			"depth": int(node.get("depth", 0)),
			"path": Array(node.get("path", [])).duplicate(true),
		})
	return out

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
		var ascore := float(ad.get("total_score", 0.0))
		var bscore := float(bd.get("total_score", 0.0))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		var aroot := str(ad.get("root_macro_id", ""))
		var broot := str(bd.get("root_macro_id", ""))
		if aroot != broot:
			return aroot < broot
		return str(ad.get("path", [])) < str(bd.get("path", []))
	)

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
