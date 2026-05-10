class_name StrategicMCTSSearch
extends RefCounted

const StrategicPlanGeneratorClass = preload("res://core/ai/planning/strategic_plan_generator.gd")
const StrategicPlanRunnerClass = preload("res://core/ai/planning/strategic_plan_runner.gd")
const StrategicPlanEvaluatorClass = preload("res://core/ai/planning/strategic_plan_evaluator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")

const DEFAULT_MCTS_ITERATIONS := 16
const DEFAULT_MCTS_MAX_DEPTH := 2
const DEFAULT_MCTS_TOP_K_PER_NODE := 4
const DEFAULT_MCTS_EXPLORATION := 1.15
const DEFAULT_MCTS_PRIOR_WEIGHT := 0.2
const DEFAULT_MCTS_ROOT_PRIOR_MIN_VISITS_PER_CHILD := 2
const DEFAULT_STEP_BUDGET_MS := 40

static func choose_plan_mcts(
	engine: GameEngine,
	observation: ObservationState,
	profile = null,
	budget: TimeBudget = null,
	options: Dictionary = {}
) -> Result:
	if engine == null:
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: engine is null")
	if observation == null:
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: observation is null")
	if budget != null and budget.expired():
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: budget expired before search")

	var start_ms := Time.get_ticks_msec()
	var root_player_id := int(observation.viewer_player_id)
	var generator_options := options.duplicate()
	generator_options["source_state"] = engine.get_state()
	var base_route_history := _route_history_array(options.get("route_history", []))
	generator_options["route_history"] = base_route_history.duplicate(true)
	var plans_read := StrategicPlanGeneratorClass.generate(observation, profile, generator_options)
	if not plans_read.ok:
		return plans_read
	var plans: Array = plans_read.value
	if plans.is_empty():
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: no plans generated")

	var max_plans := maxi(1, int(options.get("max_plans", plans.size())))
	var min_plans_for_rollout := mini(max_plans, maxi(1, int(options.get("min_plans_for_rollout", 1))))
	if plans.size() < min_plans_for_rollout:
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: insufficient route alternatives (%d < %d)" % [plans.size(), min_plans_for_rollout])
	var top_k_per_node := maxi(1, int(options.get("mcts_top_k_per_node", DEFAULT_MCTS_TOP_K_PER_NODE)))
	var iterations := maxi(1, int(options.get("mcts_iterations", DEFAULT_MCTS_ITERATIONS)))
	var max_depth := maxi(1, int(options.get("mcts_max_depth", DEFAULT_MCTS_MAX_DEPTH)))
	var exploration := maxf(0.0, float(options.get("mcts_exploration", DEFAULT_MCTS_EXPLORATION)))
	var prior_weight := maxf(0.0, float(options.get("mcts_prior_weight", DEFAULT_MCTS_PRIOR_WEIGHT)))
	var root_prior_min_visits_per_child := maxi(0, int(options.get("mcts_root_prior_min_visits_per_child", DEFAULT_MCTS_ROOT_PRIOR_MIN_VISITS_PER_CHILD)))
	var step_budget_ms := maxi(1, int(options.get("step_budget_ms", DEFAULT_STEP_BUDGET_MS)))
	var horizon_decisions := maxi(1, int(options.get("horizon_decisions", DEFAULT_MCTS_MAX_DEPTH * 8)))
	var horizon_rounds := maxi(1, int(options.get("horizon_rounds", 2)))
	var limit := mini(max_plans, plans.size())

	var root := _make_node(engine, root_player_id, null, 0, 0.0)
	root["expanded"] = true
	root["plan_entries"] = _prepare_plan_entries(plans.slice(0, limit))
	root["candidate_count"] = plans.size()
	root["candidate_deduped_count"] = plans.size()
	root["root_player_id"] = root_player_id
	root["route_history"] = base_route_history.duplicate(true)
	root["non_root_populated_nodes"] = 0
	root["non_root_expanded_nodes"] = 0
	root["non_root_candidate_count"] = 0

	var attempted_rollouts := 0
	var expanded_nodes := 0
	var deepest_depth := 0
	var budget_expired := false
	var budget_guarded := false
	var rollout_ms_sum := 0
	var rollout_ms_max := 0
	var eval_ms_sum := 0
	var backprop_ms := 0
	var executed_iterations := 0
	var plan_state_deduped_nodes := 0
	var plan_transposition_pruned_nodes := 0
	var non_root_populated_nodes := 0
	var non_root_expanded_nodes := 0
	var non_root_candidate_count := 0
	var best_state_scores: Dictionary = {}

	for _iteration in range(iterations):
		if budget != null and budget.expired():
			budget_expired = true
			break
		var selection_start_ms := Time.get_ticks_msec()
		var selection_read := _select_leaf(
			root,
			root_player_id,
			profile,
			options,
			top_k_per_node,
			max_depth,
			step_budget_ms,
			budget,
			prior_weight,
			exploration,
			horizon_decisions,
			horizon_rounds,
			budget_guarded,
			base_route_history,
			best_state_scores
		)
		if not selection_read.ok:
			return selection_read
		var selection: Dictionary = Dictionary(selection_read.value)
		attempted_rollouts += int(selection.get("attempted_rollouts", 0))
		expanded_nodes += int(selection.get("expanded_nodes", 0))
		plan_state_deduped_nodes += int(selection.get("plan_state_deduped_nodes", 0))
		plan_transposition_pruned_nodes += int(selection.get("plan_transposition_pruned_nodes", 0))
		deepest_depth = maxi(deepest_depth, int(selection.get("deepest_depth", 0)))
		rollout_ms_sum += int(selection.get("rollout_ms", 0))
		rollout_ms_max = maxi(rollout_ms_max, int(selection.get("rollout_ms_max", 0)))
		eval_ms_sum += int(selection.get("eval_ms", 0))
		if bool(selection.get("budget_expired", false)):
			budget_expired = true
		if bool(selection.get("budget_guarded", false)):
			budget_guarded = true
		var leaf: Dictionary = selection.get("leaf", null)
		if leaf == null:
			break
		var backprop_start_ms := Time.get_ticks_msec()
		_backpropagate(Array(selection.get("path", [])), float(leaf.get("leaf_value_score", 0.0)))
		backprop_ms += Time.get_ticks_msec() - backprop_start_ms
		executed_iterations += 1
		if bool(selection.get("budget_expired", false)):
			budget_expired = true
			break
		if bool(selection.get("budget_guarded", false)):
			budget_guarded = true
			break
		var iteration_elapsed := Time.get_ticks_msec() - selection_start_ms
		if budget != null and budget.expired():
			budget_expired = true
			break

	non_root_populated_nodes = int(root.get("non_root_populated_nodes", 0))
	non_root_expanded_nodes = int(root.get("non_root_expanded_nodes", 0))
	non_root_candidate_count = int(root.get("non_root_candidate_count", 0))

	var root_children: Array = Array(root.get("children", []))
	if root_children.is_empty():
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: no root children evaluated")
	var root_raw_child_count := root_children.size()
	root_children = _actionable_nodes(root_children)
	if root_children.is_empty():
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: no root children made route progress")
	var root_selection_payload := _select_final_root_child(root_children, root_prior_min_visits_per_child, budget_expired or budget_guarded)
	root_children = Array(root_selection_payload.get("nodes", root_children))
	var best_child: Dictionary = Dictionary(root_children[0])
	var best_plan = best_child.get("plan", null)
	if best_plan == null or not best_plan.has_method("to_trace_dict"):
		return Result.failure("StrategicMCTSSearch.choose_plan_mcts: best node missing plan")

	var best_q := _node_q(best_child)
	var best_visits := int(best_child.get("visits", 0))
	var best_prior := float(best_child.get("prior_score", 0.0))
	var best_eval_score := float(best_child.get("leaf_eval_score", 0.0))
	var best_value_score := float(best_child.get("leaf_value_score", best_q))
	var best_path_score := float(best_child.get("path_score", 0.0))
	var selected_path := Array(best_child.get("best_leaf_path", best_child.get("path", []))).duplicate(true)
	var selected_leaf_depth := int(best_child.get("best_leaf_depth", best_child.get("depth", 0)))
	var selected_leaf_value_score := float(best_child.get("best_leaf_value_score", best_value_score))
	var selected_state_key := str(best_child.get("state_key", ""))
	var selected_route_types := _route_types_for_path(selected_path)
	var selected_route_switch_count := _route_switch_count(selected_route_types)
	var root_selection_mode := str(root_selection_payload.get("selection_mode", "visits"))
	var root_prior_guarded := bool(root_selection_payload.get("prior_guarded", false))
	var root_min_required_visits := int(root_selection_payload.get("min_required_visits", 0))
	var features: Dictionary = Dictionary(best_child.get("leaf_features", {})).duplicate(true)
	features["mcts_final_features"] = Dictionary(best_child.get("leaf_features", {})).duplicate(true)
	features["mcts_iterations"] = executed_iterations
	features["mcts_root_visits"] = int(root.get("visits", 0))
	features["mcts_root_q"] = _node_q(root)
	features["mcts_root_value_sum"] = float(root.get("value_sum", 0.0))
	features["mcts_expanded_nodes"] = expanded_nodes
	features["mcts_attempted_rollouts"] = attempted_rollouts
	features["mcts_deepest_depth"] = deepest_depth
	features["mcts_selected_visits"] = best_visits
	features["mcts_selected_q"] = best_q
	features["mcts_selected_prior"] = best_prior
	features["mcts_eval_score"] = best_eval_score
	features["mcts_value_score"] = best_value_score
	features["mcts_path_score"] = best_path_score
	features["mcts_selected_path"] = selected_path.duplicate(true)
	features["mcts_selected_leaf_depth"] = selected_leaf_depth
	features["mcts_selected_leaf_value_score"] = selected_leaf_value_score
	features["mcts_selected_state_key"] = selected_state_key
	features["mcts_selected_route_types"] = selected_route_types.duplicate()
	features["mcts_route_switch_count"] = selected_route_switch_count
	features["mcts_root_child_count"] = root_children.size()
	features["mcts_root_raw_child_count"] = root_raw_child_count
	features["mcts_max_depth"] = max_depth
	features["mcts_top_k_per_node"] = top_k_per_node
	features["mcts_exploration"] = exploration
	features["mcts_prior_weight"] = prior_weight
	features["mcts_root_selection_mode"] = root_selection_mode
	features["mcts_root_prior_guarded"] = root_prior_guarded
	features["mcts_root_prior_min_visits_per_child"] = root_prior_min_visits_per_child
	features["mcts_root_min_required_visits"] = root_min_required_visits
	features["mcts_budget_expired"] = budget_expired
	features["mcts_budget_guarded"] = budget_guarded
	features["mcts_budget_ms"] = int(budget.budget_ms) if budget != null else -1
	features["mcts_budget_elapsed_ms"] = int(budget.elapsed_ms()) if budget != null else -1
	features["mcts_budget_remaining_ms"] = int(budget.remaining_ms()) if budget != null else -1
	features["mcts_rollout_ms_sum"] = rollout_ms_sum
	features["mcts_rollout_ms_max"] = rollout_ms_max
	features["mcts_eval_ms_sum"] = eval_ms_sum
	features["mcts_backprop_ms"] = backprop_ms
	features["mcts_plan_state_deduped_nodes"] = plan_state_deduped_nodes
	features["mcts_plan_transposition_pruned_nodes"] = plan_transposition_pruned_nodes
	features["mcts_non_root_populated_nodes"] = non_root_populated_nodes
	features["mcts_non_root_expanded_nodes"] = non_root_expanded_nodes
	features["mcts_non_root_candidate_count"] = non_root_candidate_count

	var top_plans := _trace_evaluated(root_children, 5)
	return Result.success({
		"plan": best_plan,
		"score": best_value_score,
		"eval_score": best_eval_score,
		"features": features,
		"candidate_count": int(root.get("candidate_count", 0)),
		"evaluated_count": root_children.size(),
		"evaluated_plans": top_plans,
		"telemetry": Dictionary(best_child.get("leaf_telemetry", {})).duplicate(true),
		"time_ms": Time.get_ticks_msec() - start_ms,
		"budget_expired": budget_expired,
		"budget_guarded": budget_guarded,
		"mcts_iterations": executed_iterations,
		"mcts_root_visits": int(root.get("visits", 0)),
		"mcts_root_q": _node_q(root),
		"mcts_selected_q": best_q,
		"mcts_selected_value_score": best_value_score,
		"mcts_root_child_count": root_children.size(),
		"mcts_root_raw_child_count": root_raw_child_count,
		"mcts_root_prior_guarded": root_prior_guarded,
		"mcts_root_selection_mode": root_selection_mode,
		"mcts_root_min_required_visits": root_min_required_visits,
		"mcts_selected_path": selected_path,
		"mcts_selected_leaf_depth": selected_leaf_depth,
		"mcts_selected_leaf_value_score": selected_leaf_value_score,
		"mcts_selected_state_key": selected_state_key,
		"mcts_selected_route_types": selected_route_types,
		"mcts_route_switch_count": selected_route_switch_count,
		"mcts_plan_state_deduped_nodes": plan_state_deduped_nodes,
		"mcts_plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
		"mcts_non_root_populated_nodes": non_root_populated_nodes,
		"mcts_non_root_expanded_nodes": non_root_expanded_nodes,
		"mcts_non_root_candidate_count": non_root_candidate_count,
		"plan_eval_breakdown": Dictionary(best_child.get("leaf_breakdown", {})).duplicate(true),
	})

static func _select_leaf(
	node: Dictionary,
	root_player_id: int,
	profile,
	options: Dictionary,
	top_k_per_node: int,
	max_depth: int,
	step_budget_ms: int,
	budget: TimeBudget,
	prior_weight: float,
	exploration: float,
	horizon_decisions: int,
	horizon_rounds: int,
	budget_guarded: bool,
	base_route_history: Array[String],
	best_state_scores: Dictionary
) -> Result:
	var path: Array[Dictionary] = []
	var current: Dictionary = node
	var attempted_rollouts := 0
	var expanded_nodes := 0
	var plan_state_deduped_nodes := 0
	var plan_transposition_pruned_nodes := 0
	var rollout_ms := 0
	var rollout_ms_max := 0
	var eval_ms := 0
	var deepest_depth := 0
	while true:
		path.append(current)
		deepest_depth = maxi(deepest_depth, int(current.get("depth", 0)))
		if int(current.get("depth", 0)) >= max_depth:
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_rollouts": attempted_rollouts,
				"expanded_nodes": expanded_nodes,
				"plan_state_deduped_nodes": plan_state_deduped_nodes,
				"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
				"deepest_depth": deepest_depth,
				"budget_expired": false,
				"budget_guarded": budget_guarded,
				"rollout_ms": rollout_ms,
				"rollout_ms_max": rollout_ms_max,
				"eval_ms": eval_ms,
			})
		if bool(current.get("terminal", false)):
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_rollouts": attempted_rollouts,
				"expanded_nodes": expanded_nodes,
				"plan_state_deduped_nodes": plan_state_deduped_nodes,
				"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
				"deepest_depth": deepest_depth,
				"budget_expired": false,
				"budget_guarded": budget_guarded,
				"rollout_ms": rollout_ms,
				"rollout_ms_max": rollout_ms_max,
				"eval_ms": eval_ms,
			})
		if not bool(current.get("expanded", false)):
			var populate_read := _populate_node_candidates(
				current,
				root_player_id,
				profile,
				options,
				top_k_per_node,
				budget,
				base_route_history
			)
			if not populate_read.ok:
				return populate_read
			var populate_payload: Dictionary = Dictionary(populate_read.value)
			if int(current.get("depth", 0)) > 0 and int(current.get("candidate_count", 0)) > 0:
				node["non_root_populated_nodes"] = int(node.get("non_root_populated_nodes", 0)) + 1
				node["non_root_candidate_count"] = int(node.get("non_root_candidate_count", 0)) + int(current.get("candidate_count", 0))
			if bool(populate_payload.get("budget_expired", false)):
				return Result.success({
					"leaf": current,
					"path": path,
					"attempted_rollouts": attempted_rollouts,
					"expanded_nodes": expanded_nodes,
					"plan_state_deduped_nodes": plan_state_deduped_nodes,
					"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
					"deepest_depth": deepest_depth,
					"budget_expired": true,
					"budget_guarded": budget_guarded,
					"rollout_ms": rollout_ms,
					"rollout_ms_max": rollout_ms_max,
					"eval_ms": eval_ms,
				})
			if bool(populate_payload.get("budget_guarded", false)):
				return Result.success({
					"leaf": current,
					"path": path,
					"attempted_rollouts": attempted_rollouts,
					"expanded_nodes": expanded_nodes,
					"plan_state_deduped_nodes": plan_state_deduped_nodes,
					"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
					"deepest_depth": deepest_depth,
					"budget_expired": false,
					"budget_guarded": true,
					"rollout_ms": rollout_ms,
					"rollout_ms_max": rollout_ms_max,
					"eval_ms": eval_ms,
				})
		var unexpanded_val = current.get("plan_entries", [])
		if unexpanded_val is Array and not Array(unexpanded_val).is_empty():
			var expand_read := _expand_next_child(
				current,
				root_player_id,
				profile,
				options,
				step_budget_ms,
				budget,
				prior_weight,
				horizon_decisions,
				horizon_rounds,
				base_route_history,
				best_state_scores
			)
			if not expand_read.ok:
				return expand_read
			var expand_payload: Dictionary = Dictionary(expand_read.value)
			var expanded_now := int(expand_payload.get("expanded_nodes", 0)) > 0
			attempted_rollouts += int(expand_payload.get("attempted_rollouts", 0))
			expanded_nodes += int(expand_payload.get("expanded_nodes", 0))
			plan_state_deduped_nodes += int(expand_payload.get("plan_state_deduped_nodes", 0))
			plan_transposition_pruned_nodes += int(expand_payload.get("plan_transposition_pruned_nodes", 0))
			if expanded_now and int(current.get("depth", 0)) > 0:
				node["non_root_expanded_nodes"] = int(node.get("non_root_expanded_nodes", 0)) + 1
			rollout_ms += int(expand_payload.get("rollout_ms", 0))
			rollout_ms_max = maxi(rollout_ms_max, int(expand_payload.get("rollout_ms_max", 0)))
			eval_ms += int(expand_payload.get("eval_ms", 0))
			if bool(expand_payload.get("budget_expired", false)):
				return Result.success({
					"leaf": expand_payload.get("leaf", current),
					"path": path,
					"attempted_rollouts": attempted_rollouts,
					"expanded_nodes": expanded_nodes,
					"plan_state_deduped_nodes": plan_state_deduped_nodes,
					"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
					"deepest_depth": deepest_depth,
					"budget_expired": true,
					"budget_guarded": budget_guarded,
					"rollout_ms": rollout_ms,
					"rollout_ms_max": rollout_ms_max,
					"eval_ms": eval_ms,
				})
			if bool(expand_payload.get("budget_guarded", false)):
				return Result.success({
					"leaf": expand_payload.get("leaf", current),
					"path": path,
					"attempted_rollouts": attempted_rollouts,
					"expanded_nodes": expanded_nodes,
					"plan_state_deduped_nodes": plan_state_deduped_nodes,
					"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
					"deepest_depth": deepest_depth,
					"budget_expired": false,
					"budget_guarded": true,
					"rollout_ms": rollout_ms,
					"rollout_ms_max": rollout_ms_max,
					"eval_ms": eval_ms,
				})
			var leaf_val = expand_payload.get("leaf", null)
			if leaf_val is Dictionary:
				var leaf: Dictionary = Dictionary(leaf_val)
				if expanded_now:
					path.append(leaf)
				return Result.success({
					"leaf": leaf,
					"path": path,
					"attempted_rollouts": attempted_rollouts,
					"expanded_nodes": expanded_nodes,
					"plan_state_deduped_nodes": plan_state_deduped_nodes,
					"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
					"deepest_depth": maxi(deepest_depth, int(leaf.get("depth", 0))),
					"budget_expired": false,
					"budget_guarded": budget_guarded,
					"rollout_ms": rollout_ms,
					"rollout_ms_max": rollout_ms_max,
					"eval_ms": eval_ms,
				})
			current["terminal"] = true
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_rollouts": attempted_rollouts,
				"expanded_nodes": expanded_nodes,
				"plan_state_deduped_nodes": plan_state_deduped_nodes,
				"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
				"deepest_depth": deepest_depth,
				"budget_expired": false,
				"budget_guarded": budget_guarded,
				"rollout_ms": rollout_ms,
				"rollout_ms_max": rollout_ms_max,
				"eval_ms": eval_ms,
			})
		var children_val = current.get("children", [])
		if not (children_val is Array) or Array(children_val).is_empty():
			current["terminal"] = true
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_rollouts": attempted_rollouts,
				"expanded_nodes": expanded_nodes,
				"plan_state_deduped_nodes": plan_state_deduped_nodes,
				"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
				"deepest_depth": deepest_depth,
				"budget_expired": false,
				"budget_guarded": budget_guarded,
				"rollout_ms": rollout_ms,
				"rollout_ms_max": rollout_ms_max,
				"eval_ms": eval_ms,
			})
		var selected: Variant = _select_best_child(current, exploration)
		if selected == null:
			current["terminal"] = true
			return Result.success({
				"leaf": current,
				"path": path,
				"attempted_rollouts": attempted_rollouts,
				"expanded_nodes": expanded_nodes,
				"plan_state_deduped_nodes": plan_state_deduped_nodes,
				"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
				"deepest_depth": deepest_depth,
				"budget_expired": false,
				"budget_guarded": budget_guarded,
				"rollout_ms": rollout_ms,
				"rollout_ms_max": rollout_ms_max,
				"eval_ms": eval_ms,
			})
		current = selected
	return Result.failure("StrategicMCTSSearch._select_leaf: unexpected selection exit")

static func _populate_node_candidates(
	node: Dictionary,
	root_player_id: int,
	profile,
	options: Dictionary,
	top_k_per_node: int,
	budget: TimeBudget,
	base_route_history: Array[String]
) -> Result:
	if budget != null and budget.expired():
		return Result.success({
			"budget_expired": true,
			"budget_guarded": false,
		})
	if bool(node.get("expanded", false)):
		return Result.success({
			"budget_expired": false,
			"budget_guarded": false,
		})
	var engine: GameEngine = node.get("engine", null)
	if engine == null:
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"budget_expired": false,
			"budget_guarded": false,
		})
	var observation_read := ObservationAdapterClass.observe_for_player(engine, root_player_id)
	if not observation_read.ok:
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"budget_expired": false,
			"budget_guarded": false,
		})
	var observation: ObservationState = observation_read.value
	var generator_options := options.duplicate()
	generator_options["source_state"] = engine.get_state()
	generator_options["max_plans"] = maxi(top_k_per_node, int(options.get("max_plans", top_k_per_node)))
	generator_options["route_history"] = _combined_route_history(base_route_history, _route_types_for_path(Array(node.get("path", []))))
	var plans_read := StrategicPlanGeneratorClass.generate(observation, profile, generator_options)
	if not plans_read.ok:
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"budget_expired": false,
			"budget_guarded": false,
		})
	var plans: Array = plans_read.value
	if plans.is_empty():
		node["terminal"] = true
		node["expanded"] = true
		return Result.success({
			"budget_expired": false,
			"budget_guarded": false,
		})
	var limit := mini(top_k_per_node, plans.size())
	var entries := _prepare_plan_entries(plans.slice(0, limit))
	node["plan_entries"] = entries
	node["expanded"] = true
	node["candidate_count"] = plans.size()
	node["candidate_deduped_count"] = plans.size()
	if entries.is_empty():
		node["terminal"] = true
	return Result.success({
		"budget_expired": false,
		"budget_guarded": false,
	})

static func _expand_next_child(
	node: Dictionary,
	root_player_id: int,
	profile,
	options: Dictionary,
	step_budget_ms: int,
	budget: TimeBudget,
	prior_weight: float,
	horizon_decisions: int,
	horizon_rounds: int,
	base_route_history: Array[String],
	best_state_scores: Dictionary
) -> Result:
	if budget != null and int(budget.remaining_ms()) < maxi(1, step_budget_ms):
		return Result.success({
			"leaf": node,
			"attempted_rollouts": 0,
			"expanded_nodes": 0,
			"plan_state_deduped_nodes": 0,
			"plan_transposition_pruned_nodes": 0,
			"budget_expired": false,
			"budget_guarded": true,
			"rollout_ms": 0,
			"rollout_ms_max": 0,
			"eval_ms": 0,
		})
	var entries_val = node.get("plan_entries", [])
	if not (entries_val is Array):
		node["terminal"] = true
		return Result.success({
			"leaf": node,
			"attempted_rollouts": 0,
			"expanded_nodes": 0,
			"plan_state_deduped_nodes": 0,
			"plan_transposition_pruned_nodes": 0,
			"budget_expired": false,
			"budget_guarded": false,
			"rollout_ms": 0,
			"rollout_ms_max": 0,
			"eval_ms": 0,
		})
	var entries: Array = entries_val
	var attempted := 0
	var plan_state_deduped_nodes := 0
	var plan_transposition_pruned_nodes := 0
	var rollout_ms := 0
	var rollout_ms_max := 0
	var eval_ms := 0
	while not entries.is_empty():
		if budget != null and budget.expired():
			return Result.success({
				"leaf": node,
				"attempted_rollouts": attempted,
				"expanded_nodes": 0,
				"plan_state_deduped_nodes": plan_state_deduped_nodes,
				"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
				"budget_expired": true,
				"budget_guarded": false,
				"rollout_ms": rollout_ms,
				"rollout_ms_max": rollout_ms_max,
				"eval_ms": eval_ms,
			})
		var entry_val = entries[0]
		entries.remove_at(0)
		node["plan_entries"] = entries
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_val)
		var plan = entry.get("plan", null)
		if plan == null or not plan.has_method("is_valid"):
			continue
		attempted += 1
		var plan_horizon_decisions := mini(maxi(1, horizon_decisions), maxi(1, int(plan.horizon_decisions)))
		var plan_horizon_rounds := mini(maxi(1, horizon_rounds), maxi(1, int(plan.horizon_rounds)))
		var route_history := _combined_route_history(base_route_history, _route_types_for_path(Array(node.get("path", []))))
		var rollout_start_ms := Time.get_ticks_msec()
		var rollout_read := StrategicPlanRunnerClass.rollout(
			node.get("engine", null),
			plan,
			profile,
			{
				"horizon_decisions": plan_horizon_decisions,
				"horizon_rounds": plan_horizon_rounds,
				"step_budget_ms": step_budget_ms,
				"budget": budget,
				"route_history": route_history,
			}
		)
		var rollout_elapsed_ms := Time.get_ticks_msec() - rollout_start_ms
		rollout_ms += rollout_elapsed_ms
		rollout_ms_max = maxi(rollout_ms_max, rollout_elapsed_ms)
		if not rollout_read.ok:
			continue
		var rollout_payload: Dictionary = Dictionary(rollout_read.value)
		var eval_start_ms := Time.get_ticks_msec()
		var eval_read := StrategicPlanEvaluatorClass.evaluate_rollout(plan, rollout_payload, profile)
		eval_ms += Time.get_ticks_msec() - eval_start_ms
		if not eval_read.ok:
			continue
		var eval_payload: Dictionary = Dictionary(eval_read.value)
		var child_engine: GameEngine = rollout_payload.get("engine", null)
		if child_engine == null:
			continue
		var depth := int(node.get("depth", 0)) + 1
		var path: Array = Array(node.get("path", [])).duplicate(true)
		var path_contribution := float(plan.prior_score) * prior_weight * pow(0.92, float(maxi(0, depth - 1)))
		var child := _make_node(child_engine, root_player_id, plan, depth, float(node.get("path_score", 0.0)) + path_contribution)
		child["path"] = path
		child["path"].append(_path_item(plan, depth, path_contribution))
		child["rollout"] = _rollout_trace_payload(rollout_payload)
		child["leaf_eval_score"] = float(eval_payload.get("score", 0.0))
		child["leaf_value_score"] = float(child.get("path_score", 0.0)) + float(eval_payload.get("score", 0.0))
		child["leaf_features"] = Dictionary(eval_payload.get("features", {})).duplicate(true)
		child["leaf_breakdown"] = Dictionary(eval_payload.get("breakdown", {})).duplicate(true)
		child["leaf_telemetry"] = Dictionary(eval_payload.get("telemetry", {})).duplicate(true)
		child["plan_prior_score"] = float(plan.prior_score)
		child["plan_id"] = plan.id
		child["route_type"] = plan.route_type
		child["root_player_id"] = root_player_id
		child["rollout_stop_reason"] = str(rollout_payload.get("phase_stop_reason", ""))
		child["rollout_commands"] = Array(rollout_payload.get("commands_executed", [])).size()
		var transposition := _register_transposition_state(child, best_state_scores)
		if bool(transposition.get("duplicate", false)):
			plan_state_deduped_nodes += 1
		if bool(transposition.get("pruned", false)):
			plan_transposition_pruned_nodes += 1
			continue
		var children: Array = node.get("children", [])
		children.append(child)
		node["children"] = children
		return Result.success({
			"leaf": child,
			"attempted_rollouts": attempted,
			"expanded_nodes": 1,
			"plan_state_deduped_nodes": plan_state_deduped_nodes,
			"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
			"budget_expired": budget != null and budget.expired(),
			"budget_guarded": false,
			"rollout_ms": rollout_ms,
			"rollout_ms_max": rollout_ms_max,
			"eval_ms": eval_ms,
		})
	node["terminal"] = true
	return Result.success({
		"leaf": node,
		"attempted_rollouts": attempted,
		"expanded_nodes": 0,
		"plan_state_deduped_nodes": plan_state_deduped_nodes,
		"plan_transposition_pruned_nodes": plan_transposition_pruned_nodes,
		"budget_expired": false,
		"budget_guarded": false,
		"rollout_ms": rollout_ms,
		"rollout_ms_max": rollout_ms_max,
		"eval_ms": eval_ms,
	})

static func _prepare_plan_entries(plans: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for plan_val in plans:
		if plan_val == null or not plan_val.has_method("is_valid"):
			continue
		var plan = plan_val
		entries.append({
			"plan": plan,
			"plan_id": plan.id,
			"route_type": plan.route_type,
			"prior_score": float(plan.prior_score),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aprior := float(a.get("prior_score", 0.0))
		var bprior := float(b.get("prior_score", 0.0))
		if not is_equal_approx(aprior, bprior):
			return aprior > bprior
		return str(a.get("plan_id", "")) < str(b.get("plan_id", ""))
	)
	return entries

static func _select_best_child(node: Dictionary, exploration: float) -> Variant:
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
	var best_plan_id := ""
	for child_val in children:
		if not (child_val is Dictionary):
			continue
		var child: Dictionary = child_val
		var prior := maxf(0.0, float(child.get("prior_score", 0.0)))
		var q := _node_q(child)
		var child_visits := int(child.get("visits", 0))
		var score := q + exploration * prior * sqrt(float(parent_visits)) / float(child_visits + 1)
		var plan_id := str(child.get("plan_id", ""))
		if best_child == null or score > best_score or (is_equal_approx(score, best_score) and (child_visits > best_visits or (child_visits == best_visits and (prior > best_prior or (is_equal_approx(prior, best_prior) and plan_id < best_plan_id))))) :
			best_child = child
			best_score = score
			best_visits = child_visits
			best_prior = prior
			best_plan_id = plan_id
	return best_child

static func _backpropagate(path: Array, leaf_value: float) -> void:
	var leaf_path: Array = []
	var leaf_depth := 0
	if not path.is_empty() and path[path.size() - 1] is Dictionary:
		var leaf: Dictionary = path[path.size() - 1]
		leaf_path = Array(leaf.get("path", [])).duplicate(true)
		leaf_depth = int(leaf.get("depth", 0))
	for node_val in path:
		if not (node_val is Dictionary):
			continue
		var node: Dictionary = node_val
		node["visits"] = int(node.get("visits", 0)) + 1
		node["value_sum"] = float(node.get("value_sum", 0.0)) + leaf_value
		node["q"] = _node_q(node)
		node["leaf_value_score"] = leaf_value
		var should_update_best := not node.has("best_leaf_value_score")
		if not should_update_best:
			var previous_best := float(node.get("best_leaf_value_score", -INF))
			should_update_best = leaf_value > previous_best or (is_equal_approx(leaf_value, previous_best) and leaf_depth > int(node.get("best_leaf_depth", -1)))
		if should_update_best:
			node["best_leaf_value_score"] = leaf_value
			node["best_leaf_depth"] = leaf_depth
			node["best_leaf_path"] = leaf_path.duplicate(true)

static func _node_q(node: Dictionary) -> float:
	var visits := int(node.get("visits", 0))
	if visits <= 0:
		return 0.0
	return float(node.get("value_sum", 0.0)) / float(visits)

static func _select_final_root_child(nodes: Array, min_visits_per_child: int, budget_limited: bool) -> Dictionary:
	var sorted_nodes := nodes.duplicate()
	var min_required_visits := maxi(0, min_visits_per_child) * sorted_nodes.size()
	var total_visits := 0
	for node_val in sorted_nodes:
		if node_val is Dictionary:
			total_visits += int(Dictionary(node_val).get("visits", 0))
	var use_prior_guard := budget_limited or (min_required_visits > 0 and total_visits < min_required_visits)
	if use_prior_guard:
		_sort_nodes_by_prior_guard(sorted_nodes)
		return {
			"nodes": sorted_nodes,
			"selection_mode": "prior_guard",
			"prior_guarded": true,
			"min_required_visits": min_required_visits,
			"total_visits": total_visits,
		}
	_sort_nodes(sorted_nodes)
	return {
		"nodes": sorted_nodes,
		"selection_mode": "visits",
		"prior_guarded": false,
		"min_required_visits": min_required_visits,
		"total_visits": total_visits,
	}

static func _actionable_nodes(nodes: Array) -> Array:
	var out: Array = []
	for node_val in nodes:
		if not (node_val is Dictionary):
			continue
		var node: Dictionary = node_val
		var telemetry: Dictionary = Dictionary(node.get("leaf_telemetry", {}))
		if bool(telemetry.get("route_stalled", false)):
			continue
		out.append(node)
	return out

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
		var aq := float(ad.get("q", 0.0))
		var bq := float(bd.get("q", 0.0))
		if not is_equal_approx(aq, bq):
			return aq > bq
		var aprior := float(ad.get("prior_score", 0.0))
		var bprior := float(bd.get("prior_score", 0.0))
		if not is_equal_approx(aprior, bprior):
			return aprior > bprior
		return str(ad.get("plan_id", "")) < str(bd.get("plan_id", ""))
	)

static func _sort_nodes_by_prior_guard(nodes: Array) -> void:
	nodes.sort_custom(func(a, b) -> bool:
		if not (a is Dictionary):
			return false
		if not (b is Dictionary):
			return true
		var ad: Dictionary = a
		var bd: Dictionary = b
		var aprior := float(ad.get("prior_score", 0.0))
		var bprior := float(bd.get("prior_score", 0.0))
		if not is_equal_approx(aprior, bprior):
			return aprior > bprior
		var apath := float(ad.get("path_score", 0.0))
		var bpath := float(bd.get("path_score", 0.0))
		if not is_equal_approx(apath, bpath):
			return apath > bpath
		return str(ad.get("plan_id", "")) < str(bd.get("plan_id", ""))
	)

static func _trace_evaluated(nodes: Array, limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(mini(maxi(0, limit), nodes.size())):
		var item_val = nodes[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var rollout: Dictionary = Dictionary(item.get("rollout", {}))
		var path: Array = Array(item.get("path", [])).duplicate(true)
		var best_path: Array = Array(item.get("best_leaf_path", item.get("path", []))).duplicate(true)
		var route_types := _route_types_for_path(path)
		var best_route_types := _route_types_for_path(best_path)
		var route_history := Array(rollout.get("route_history", [])).duplicate(true)
		out.append({
			"plan_id": str(item.get("plan_id", "")),
			"route_type": str(item.get("route_type", "")),
			"prior_score": float(item.get("prior_score", 0.0)),
			"score": float(item.get("q", item.get("leaf_value_score", 0.0))),
			"eval_score": float(item.get("leaf_eval_score", 0.0)),
			"state_key": str(item.get("state_key", "")),
			"breakdown": Dictionary(item.get("leaf_breakdown", item.get("leaf_features", {}))).duplicate(true),
			"telemetry": Dictionary(item.get("leaf_telemetry", {})).duplicate(true),
			"stop_reason": str(item.get("rollout_stop_reason", rollout.get("phase_stop_reason", ""))),
			"commands": int(item.get("rollout_commands", Array(rollout.get("commands_executed", [])).size())),
			"visits": int(item.get("visits", 0)),
			"q": float(item.get("q", 0.0)),
			"depth": int(item.get("depth", 0)),
			"path": path,
			"best_path": best_path,
			"route_types": route_types,
			"best_route_types": best_route_types,
			"route_history": route_history,
			"route_switch_count": _route_switch_count(best_route_types),
			"best_leaf_depth": int(item.get("best_leaf_depth", item.get("depth", 0))),
			"best_leaf_value_score": float(item.get("best_leaf_value_score", item.get("leaf_value_score", 0.0))),
		})
	return out

static func _rollout_trace_payload(rollout: Dictionary) -> Dictionary:
	return {
		"commands_executed": Array(rollout.get("commands_executed", [])).duplicate(true),
		"route_history": Array(rollout.get("route_history", [])).duplicate(true),
		"round_delta": int(rollout.get("round_delta", 0)),
		"phase_stop_reason": str(rollout.get("phase_stop_reason", "")),
		"cash_before": int(rollout.get("cash_before", 0)),
		"cash_after": int(rollout.get("cash_after", 0)),
		"cash_max_seen": int(rollout.get("cash_max_seen", 0)),
		"cash_min_after_first_positive": int(rollout.get("cash_min_after_first_positive", 0)),
		"search_time_ms": int(rollout.get("search_time_ms", 0)),
		"fork_ms": int(rollout.get("fork_ms", 0)),
	}

static func _make_node(
	engine: GameEngine,
	root_player_id: int,
	plan,
	depth: int,
	path_score: float
) -> Dictionary:
	return {
		"engine": engine,
		"root_player_id": root_player_id,
		"plan": plan,
		"plan_id": str(plan.id) if plan != null else "",
		"route_type": str(plan.route_type) if plan != null else "",
		"prior_score": float(plan.prior_score) if plan != null else 0.0,
		"state_key": _state_key_for_engine(engine, str(plan.id) if plan != null else ""),
		"depth": int(depth),
		"path_score": float(path_score),
		"visits": 0,
		"value_sum": 0.0,
		"q": 0.0,
		"leaf_eval_score": 0.0,
		"leaf_value_score": 0.0,
		"leaf_features": {},
		"children": [],
		"plan_entries": [],
		"expanded": false,
		"terminal": false,
		"candidate_count": 0,
		"candidate_deduped_count": 0,
	}

static func _path_item(plan, depth: int, path_contribution: float) -> Dictionary:
	return {
		"plan_id": str(plan.id) if plan != null else "",
		"route_type": str(plan.route_type) if plan != null else "",
		"prior_score": float(plan.prior_score) if plan != null else 0.0,
		"depth": int(depth),
		"path_contribution": float(path_contribution),
	}

static func _route_history_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var route_type := ""
			if item is Dictionary:
				route_type = str(Dictionary(item).get("route_type", ""))
			else:
				route_type = str(item)
			route_type = route_type.strip_edges()
			if not route_type.is_empty():
				out.append(route_type)
	return out

static func _combined_route_history(base_route_history: Array[String], path_route_types: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for base_route_val in base_route_history:
		var base_route := str(base_route_val).strip_edges()
		if not base_route.is_empty():
			out.append(base_route)
	for path_route_val in path_route_types:
		var path_route := str(path_route_val).strip_edges()
		if not path_route.is_empty():
			out.append(path_route)
	return out

static func _route_types_for_path(path: Array) -> Array[String]:
	var route_types: Array[String] = []
	for path_item_val in path:
		if not (path_item_val is Dictionary):
			continue
		var route_type := str(Dictionary(path_item_val).get("route_type", "")).strip_edges()
		if route_type.is_empty():
			continue
		route_types.append(route_type)
	return route_types

static func _route_switch_count(route_types: Array) -> int:
	var previous := ""
	var switch_count := 0
	for route_type_val in route_types:
		var route_type := str(route_type_val).strip_edges()
		if route_type.is_empty():
			continue
		if not previous.is_empty() and route_type != previous:
			switch_count += 1
		previous = route_type
	return switch_count

static func _register_transposition_state(node: Dictionary, best_state_scores: Dictionary) -> Dictionary:
	var state_key := str(node.get("state_key", ""))
	if state_key.is_empty():
		var engine_val = node.get("engine", null)
		var node_engine: GameEngine = engine_val if engine_val is GameEngine else null
		state_key = _state_key_for_engine(node_engine, str(node.get("plan_id", "")))
		if not state_key.is_empty():
			node["state_key"] = state_key
	if state_key.is_empty():
		return {
			"keep": true,
			"duplicate": false,
			"pruned": false,
			"score": _node_transposition_score(node),
			"best_score": -INF,
		}
	var score := _node_transposition_score(node)
	if best_state_scores.has(state_key):
		var best_score := float(best_state_scores.get(state_key, -INF))
		if score < best_score or is_equal_approx(score, best_score):
			return {
				"keep": false,
				"duplicate": true,
				"pruned": true,
				"score": score,
				"best_score": best_score,
			}
		best_state_scores[state_key] = score
		return {
			"keep": true,
			"duplicate": true,
			"pruned": false,
			"score": score,
			"best_score": score,
		}
	best_state_scores[state_key] = score
	return {
		"keep": true,
		"duplicate": false,
		"pruned": false,
		"score": score,
		"best_score": score,
	}

static func _node_transposition_score(node: Dictionary) -> float:
	return float(node.get("leaf_value_score", node.get("path_score", -INF)))

static func _state_key_for_engine(engine: GameEngine, active_plan_id: String = "") -> String:
	if engine == null:
		return ""
	var state := engine.get_state()
	if state == null:
		return ""
	return "%s|%s|%s|%d|%s" % [
		str(state.compute_hash()),
		str(state.phase),
		str(state.sub_phase),
		int(state.get_current_player_id()),
		active_plan_id,
	]
