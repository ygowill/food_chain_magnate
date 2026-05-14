class_name StrategicPlanTest
extends RefCounted

const StrategicBotClass = preload("res://core/ai/bot/strategic_bot.gd")
const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const StrategicPlanClass = preload("res://core/ai/planning/strategic_plan.gd")
const StrategyPlanHintsClass = preload("res://core/ai/planning/strategic_plan_hints.gd")
const StrategicPlanGeneratorClass = preload("res://core/ai/planning/strategic_plan_generator.gd")
const StrategicPlanRunnerClass = preload("res://core/ai/planning/strategic_plan_runner.gd")
const StrategicPlanEvaluatorClass = preload("res://core/ai/planning/strategic_plan_evaluator.gd")
const StrategicSearchClass = preload("res://core/ai/planning/strategic_search.gd")
const StrategicMCTSSearchClass = preload("res://core/ai/planning/strategic_mcts_search.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var data := _test_plan_and_hints_roundtrip()
	if not data.ok:
		return data
	var generator := _test_generator_creates_income_and_supply_plans()
	if not generator.ok:
		return generator
	var generator_history := _test_generator_route_history_bias()
	if not generator_history.ok:
		return generator_history
	var hints := _test_hints_bias_strategy_scorer()
	if not hints.ok:
		return hints
	var candidate_order := _test_plan_hints_prioritize_candidate_generation()
	if not candidate_order.ok:
		return candidate_order
	var fallback := _test_strategic_bot_budget_fallback(seed_val)
	if not fallback.ok:
		return fallback
	var action_gate := _test_strategic_bot_non_strategic_action_gate(seed_val)
	if not action_gate.ok:
		return action_gate
	var route_alternatives := _test_strategic_search_requires_route_alternatives(seed_val)
	if not route_alternatives.ok:
		return route_alternatives
	var cache_reuse := _test_strategic_bot_plan_cache_reuse(seed_val)
	if not cache_reuse.ok:
		return cache_reuse
	var cache_scope := _test_strategic_bot_plan_cache_scopes_decision_window()
	if not cache_scope.ok:
		return cache_scope
	var route_memory := _test_strategic_bot_route_history_memory(seed_val)
	if not route_memory.ok:
		return route_memory
	var default_beam := _test_strategic_bot_default_beam_search(seed_val)
	if not default_beam.ok:
		return default_beam
	var growth_gate := _test_growth_plan_requires_income_footing()
	if not growth_gate.ok:
		return growth_gate
	var rollout := _test_rollout_search_and_evaluator(seed_val)
	if not rollout.ok:
		return rollout
	var progress := _test_route_progress_bonus_follows_execution_sequence(seed_val)
	if not progress.ok:
		return progress
	var milestone_progress := _test_route_progress_bonus_uses_incremental_milestones(seed_val)
	if not milestone_progress.ok:
		return milestone_progress
	var evaluator_guard := _test_evaluator_growth_bonus_requires_progress(seed_val)
	if not evaluator_guard.ok:
		return evaluator_guard
	var stall_guard := _test_evaluator_penalizes_stalled_route(seed_val)
	if not stall_guard.ok:
		return stall_guard
	var footing_guard := _test_route_transition_bonus_waits_for_cash_footing(seed_val)
	if not footing_guard.ok:
		return footing_guard
	var actionable_guard := _test_strategic_search_filters_stalled_routes()
	if not actionable_guard.ok:
		return actionable_guard
	var search_cost := _test_evaluator_search_cost_is_trace_only(seed_val)
	if not search_cost.ok:
		return search_cost
	var mcts_transposition := _test_strategic_mcts_transposition_registry_prunes_lower_or_equal_paths(seed_val)
	if not mcts_transposition.ok:
		return mcts_transposition
	var mcts_backprop_path := _test_strategic_mcts_backpropagates_best_leaf_path()
	if not mcts_backprop_path.ok:
		return mcts_backprop_path
	var mcts_root_selection := _test_strategic_mcts_root_selection_respects_visit_floor()
	if not mcts_root_selection.ok:
		return mcts_root_selection
	var mcts_search := _test_strategic_mcts_search_returns_plan_level_trace(seed_val)
	if not mcts_search.ok:
		return mcts_search
	var mcts_non_root := _test_strategic_mcts_expands_non_root_plan_nodes(seed_val)
	if not mcts_non_root.ok:
		return mcts_non_root
	var mcts_mode := _test_strategic_bot_mcts_mode(seed_val)
	if not mcts_mode.ok:
		return mcts_mode
	return Result.success({"cases": 27})

static func _test_plan_and_hints_roundtrip() -> Result:
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		42.5,
		["burger", "burger"],
		["house_near"],
		["campaign_manager"],
		{"cash_floor": 10, "preferred_marketing_board_numbers": [1, 2]},
		["income", "marketing"],
		2,
		16,
		["recruit", "train", "initiate_marketing", "produce_food"]
	)
	if not plan.is_valid():
		return Result.failure("StrategicPlan should be valid")
	var copy = StrategicPlanClass.from_dict(plan.to_dict())
	if str(copy.to_dict()) != str(plan.to_dict()):
		return Result.failure("StrategicPlan dict roundtrip mismatch: %s vs %s" % [str(copy.to_dict()), str(plan.to_dict())])
	copy.target_products.append("pizza")
	if plan.target_products.has("pizza"):
		return Result.failure("StrategicPlan duplicate should not alias arrays")

	var hints = StrategyPlanHintsClass.from_plan(plan)
	var hints_dict: Dictionary = hints.to_dict()
	if str(hints_dict.get("plan_id", "")) != "marketing_income_burger":
		return Result.failure("StrategyPlanHints should preserve plan id: %s" % str(hints_dict))
	if not Array(hints_dict.get("preferred_products", [])).has("burger"):
		return Result.failure("StrategyPlanHints should prefer target product: %s" % str(hints_dict))
	if not Array(hints_dict.get("preferred_employee_roles", [])).has("marketing"):
		return Result.failure("StrategyPlanHints should include marketing role: %s" % str(hints_dict))
	if Array(hints_dict.get("preferred_employee_roles", [])).has("procure_drink"):
		return Result.failure("StrategyPlanHints should not inject drink role for burger route: %s" % str(hints_dict))
	if not Array(hints_dict.get("preferred_actions", [])).has("initiate_marketing"):
		return Result.failure("StrategyPlanHints should include route actions: %s" % str(hints_dict))
	if Array(hints_dict.get("preferred_actions", [])).has("procure_drinks"):
		return Result.failure("StrategyPlanHints should not inject drink action for burger route: %s" % str(hints_dict))
	if Array(hints_dict.get("execution_sequence", [])).is_empty():
		return Result.failure("StrategyPlanHints should preserve execution sequence: %s" % str(hints_dict))
	var hints_copy = StrategyPlanHintsClass.from_dict(hints_dict)
	if str(hints_copy.to_dict()) != str(hints_dict):
		return Result.failure("StrategyPlanHints dict roundtrip mismatch: %s vs %s" % [str(hints_copy.to_dict()), str(hints_dict)])
	var drink_plan = StrategicPlanClass.create(
		"marketing_income_beer",
		0,
		"marketing_income",
		21.0,
		["beer"],
		[],
		[],
		{},
		["income", "marketing"],
		2,
		16,
		["initiate_marketing", "procure_drinks"]
	)
	var drink_hints = StrategyPlanHintsClass.from_plan(drink_plan)
	var drink_hints_dict: Dictionary = drink_hints.to_dict()
	if not Array(drink_hints_dict.get("preferred_employee_roles", [])).has("procure_drink"):
		return Result.failure("StrategyPlanHints should include drink role for beer route: %s" % str(drink_hints_dict))
	if Array(drink_hints_dict.get("preferred_employee_roles", [])).has("produce_food"):
		return Result.failure("StrategyPlanHints should not inject food role for drink-only route: %s" % str(drink_hints_dict))
	if not Array(drink_hints_dict.get("preferred_actions", [])).has("procure_drinks"):
		return Result.failure("StrategyPlanHints should include drink action for beer route: %s" % str(drink_hints_dict))
	if Array(drink_hints_dict.get("preferred_actions", [])).has("produce_food"):
		return Result.failure("StrategyPlanHints should not inject food action for drink-only route: %s" % str(drink_hints_dict))
	return Result.success()

static func _test_generator_creates_income_and_supply_plans() -> Result:
	var profile := StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	var read := StrategicPlanGeneratorClass.generate(observation, profile, {"max_plans": 6})
	if not read.ok:
		return read
	var plans: Array = read.value
	if plans.is_empty():
		return Result.failure("StrategicPlanGenerator should create plans for public burger demand")
	if not _has_plan(plans, "marketing_income", "burger"):
		return Result.failure("StrategicPlanGenerator should create burger marketing income plan: %s" % str(_plan_debug(plans)))
	if not _has_plan(plans, "supply_capacity", "burger"):
		return Result.failure("StrategicPlanGenerator should create burger supply plan: %s" % str(_plan_debug(plans)))
	var ids := {}
	var last_score := INF
	for plan_val in plans:
		if plan_val == null or not plan_val.has_method("to_trace_dict"):
			return Result.failure("generator returned non-plan value: %s" % str(plan_val))
		var plan = plan_val
		if ids.has(plan.id):
			return Result.failure("generator should dedupe plan ids: %s" % str(_plan_debug(plans)))
		ids[plan.id] = true
		if plan.prior_score > last_score:
			return Result.failure("generator should return plans in descending prior order: %s" % str(_plan_debug(plans)))
		last_score = plan.prior_score

	var empty := StrategicPlanGeneratorClass.generate(_synthetic_empty_observation(), profile, {"max_plans": 6})
	if not empty.ok:
		return empty
	if not Array(empty.value).is_empty():
		return Result.failure("StrategicPlanGenerator should return empty plans when no route exists: %s" % str(_plan_debug(empty.value)))
	return Result.success()

static func _test_generator_route_history_bias() -> Result:
	var profile := StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	var read := StrategicPlanGeneratorClass.generate(observation, profile, {
		"max_plans": 4,
		"route_history": ["marketing_income"],
	})
	if not read.ok:
		return read
	var plans: Array = read.value
	if plans.is_empty():
		return Result.failure("StrategicPlanGenerator should create follow-up plans after route history: %s" % str(_plan_debug(plans)))
	var first_plan_val = plans[0]
	if first_plan_val == null or not first_plan_val.has_method("to_trace_dict"):
		return Result.failure("StrategicPlanGenerator should return plans: %s" % str(_plan_debug(plans)))
	var first_plan = first_plan_val
	if str(first_plan.route_type) != "supply_capacity":
		return Result.failure("StrategicPlanGenerator should prefer supply follow-up after marketing history: %s" % str(_plan_debug(plans)))

	var early_observation := _synthetic_income_observation()
	early_observation.own_player["cash"] = 0
	var early_read := StrategicPlanGeneratorClass.generate(early_observation, profile, {
		"max_plans": 4,
		"route_history": ["marketing_income"],
	})
	if not early_read.ok:
		return early_read
	var early_plans: Array = early_read.value
	if early_plans.is_empty():
		return Result.failure("StrategicPlanGenerator should keep income plans under early cash pressure: %s" % str(_plan_debug(early_plans)))
	var early_first_plan_val = early_plans[0]
	if early_first_plan_val == null or not early_first_plan_val.has_method("to_trace_dict"):
		return Result.failure("StrategicPlanGenerator should return early income plans: %s" % str(_plan_debug(early_plans)))
	var early_first_plan = early_first_plan_val
	if str(early_first_plan.route_type) != "marketing_income":
		return Result.failure("StrategicPlanGenerator should not switch away from marketing before cash footing: %s" % str(_plan_debug(early_plans)))
	return Result.success()

static func _test_hints_bias_strategy_scorer() -> Result:
	var profile := StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	var burger_macro := MacroAction.create(
		"produce_burger",
		[Command.create("produce_food", 0, {"employee_type": "burger_cook", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var pizza_macro := MacroAction.create(
		"produce_pizza",
		[Command.create("produce_food", 0, {"employee_type": "pizza_cook", "food_type": "pizza"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var base_burger: Dictionary = StrategyScorerClass.score_macro(observation, burger_macro, profile)
	var base_pizza: Dictionary = StrategyScorerClass.score_macro(observation, pizza_macro, profile)
	var hints = StrategyPlanHintsClass.create("pizza_switch", ["pizza"], ["produce_food"])
	var hinted_burger: Dictionary = StrategyScorerClass.score_macro(observation, burger_macro, profile, {"plan_hints": hints})
	var hinted_pizza: Dictionary = StrategyScorerClass.score_macro(observation, pizza_macro, profile, {"plan_hints": hints})
	var burger_delta := float(hinted_burger.get("score", 0.0)) - float(base_burger.get("score", 0.0))
	var pizza_delta := float(hinted_pizza.get("score", 0.0)) - float(base_pizza.get("score", 0.0))
	if pizza_delta <= burger_delta:
		return Result.failure("plan hints should bias preferred product more strongly: burger_delta=%f pizza_delta=%f" % [burger_delta, pizza_delta])
	var pizza_features: Dictionary = Dictionary(hinted_pizza.get("features", {}))
	if float(pizza_features.get("plan_hints_bonus", 0.0)) <= 0.0 or str(pizza_features.get("plan_id", "")) != "pizza_switch":
		return Result.failure("hinted score should expose plan bonus/id: %s" % str(pizza_features))

	var action_macro := MacroAction.create(
		"produce_burger_again",
		[Command.create("produce_food", 0, {"employee_type": "burger_cook", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var skip_macro := MacroAction.create(
		"skip_sub_phase",
		[Command.create("skip_sub_phase", 0, {})],
		0.0,
		["working", "fallback"],
		{}
	)
	var action_hints = StrategyPlanHintsClass.create("action_bias", [], [], [], [], [], [], 0.0, 0, [], ["produce_food"])
	var action_base: Dictionary = StrategyScorerClass.score_macro(observation, action_macro, profile)
	var action_skip_base: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile)
	var action_hinted: Dictionary = StrategyScorerClass.score_macro(observation, action_macro, profile, {"plan_hints": action_hints})
	var skip_hinted: Dictionary = StrategyScorerClass.score_macro(observation, skip_macro, profile, {"plan_hints": action_hints})
	var action_delta := float(action_hinted.get("score", 0.0)) - float(action_base.get("score", 0.0))
	var skip_delta := float(skip_hinted.get("score", 0.0)) - float(action_skip_base.get("score", 0.0))
	if action_delta <= skip_delta:
		return Result.failure("preferred_actions should bias matching actions more strongly: action_delta=%f skip_delta=%f" % [action_delta, skip_delta])
	var action_features: Dictionary = Dictionary(action_hinted.get("features", {}))
	if str(action_features.get("plan_hints_action_match", "")) != "produce_food":
		return Result.failure("preferred_actions should expose action match feature: %s" % str(action_features))
	var sequence_hints = StrategyPlanHintsClass.create("sequence_bias", [], [], [], [], [], [], 0.0, 0, [], ["produce_food", "recruit"], ["recruit", "produce_food"])
	var recruit_macro := MacroAction.create(
		"recruit_marketing",
		[Command.create("recruit", 0, {"employee_type": "marketing_trainee"})],
		0.0,
		["working", "recruit"],
		{}
	)
	var sequence_recruit_base: Dictionary = StrategyScorerClass.score_macro(observation, recruit_macro, profile)
	var sequence_recruit_hinted: Dictionary = StrategyScorerClass.score_macro(observation, recruit_macro, profile, {"plan_hints": sequence_hints})
	var sequence_recruit_delta := float(sequence_recruit_hinted.get("score", 0.0)) - float(sequence_recruit_base.get("score", 0.0))
	if sequence_recruit_delta <= action_delta:
		return Result.failure("execution_sequence should bias earlier actions more strongly: recruit_delta=%f action_delta=%f" % [sequence_recruit_delta, action_delta])
	var sequence_features: Dictionary = Dictionary(sequence_recruit_hinted.get("features", {}))
	if int(sequence_features.get("plan_hints_sequence_index", -1)) != 0 or str(sequence_features.get("plan_hints_sequence_match", "")) != "recruit":
		return Result.failure("execution_sequence should expose sequence features: %s" % str(sequence_features))
	return Result.success()

static func _test_plan_hints_prioritize_candidate_generation() -> Result:
	var profile := StrategyProfileClass.new()
	profile.configure_base_revenue()
	var observation := _synthetic_income_observation()
	var context_read := AiDecisionContext.from_observation(observation, 12345, [])
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value
	var validate_fn := func(_command: Command) -> Result:
		return Result.success()
	var read := CandidateGeneratorClass.generate(
		observation,
		context,
		["produce_food"],
		validate_fn,
		{
			"max_valid_per_action": 4,
			"plan_hints": StrategyPlanHintsClass.create("pizza_first", ["pizza"], ["produce_food"], [], [], [], [], 0.0, 0, [], [], ["produce_food"])
		}
	)
	if not read.ok:
		return read
	var candidates: Array = Array(read.value.get("candidates", []))
	if candidates.is_empty():
		return Result.failure("CandidateGenerator should produce candidates for hinted supply routing")
	var first_macro_val = candidates[0]
	if not (first_macro_val is MacroAction):
		return Result.failure("CandidateGenerator should return macros: %s" % str(candidates))
	var first_macro: MacroAction = first_macro_val
	var first_command: Command = Array(first_macro.commands)[0]
	if first_command == null or str(first_command.params.get("food_type", "")) != "pizza":
		return Result.failure("CandidateGenerator should prioritize hinted product first: %s" % str(first_macro.to_debug_dict()))

	var train_observation := _synthetic_income_observation()
	train_observation.sub_phase = DefsClass.SUB_PHASE_TRAIN
	train_observation.own_player["employees"] = ["burger_cook"]
	train_observation.own_player["reserve_employees"] = ["kitchen_trainee"]
	train_observation.employee_pool_public["burger_cook"] = 1
	train_observation.employee_pool_public["pizza_cook"] = 1
	var train_context_read := AiDecisionContext.from_observation(train_observation, 12345, [])
	if not train_context_read.ok:
		return train_context_read
	var train_read := CandidateGeneratorClass.generate(
		train_observation,
		train_context_read.value,
		["train"],
		validate_fn,
		{
			"max_valid_per_action": 4,
			"plan_hints": StrategyPlanHintsClass.create("train_pizza_first", ["pizza"], ["produce_food"], ["pizza_cook"], [], [], [], 0.0, 0, [], ["train", "produce_food"], ["train", "produce_food"])
		}
	)
	if not train_read.ok:
		return train_read
	var train_candidates: Array = Array(train_read.value.get("candidates", []))
	if train_candidates.is_empty():
		return Result.failure("CandidateGenerator should produce train candidates for hinted training")
	var train_first_val = train_candidates[0]
	if not (train_first_val is MacroAction):
		return Result.failure("CandidateGenerator should return train macros: %s" % str(train_candidates))
	var train_first: MacroAction = train_first_val
	var train_command: Command = Array(train_first.commands)[0]
	if train_command == null or str(train_command.params.get("to_employee", "")) != "pizza_cook":
		return Result.failure("CandidateGenerator should prioritize hinted train target first: %s" % str(train_first.to_debug_dict()))
	return Result.success()

static func _test_route_progress_bonus_follows_execution_sequence(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var plan = StrategicPlanClass.create(
		"marketing_progress",
		0,
		"marketing_income",
		0.0,
		["burger"],
		["house_near"],
		["campaign_manager"],
		{},
		["marketing"],
		2,
		16,
		["recruit", "train", "initiate_marketing"]
	)
	var matching_rollout := {
		"engine": data["engine"],
		"commands_executed": [
			{"actor": 0, "action_id": "recruit", "params": {"employee_type": "marketing_trainee"}},
			{"actor": 0, "action_id": "train", "params": {"from_employee": "marketing_trainee", "to_employee": "campaign_manager"}},
			{"actor": 0, "action_id": "initiate_marketing", "params": {"employee_type": "campaign_manager", "product": "burger"}},
		],
		"cash_before": 0,
		"cash_min_after_first_positive": 0,
		"cash_max_seen": 0,
		"search_time_ms": 0,
		"milestones_gained": [],
	}
	var matching_eval := StrategicPlanEvaluatorClass.evaluate_rollout(plan, matching_rollout, profile)
	if not matching_eval.ok:
		return matching_eval
	var matching_breakdown: Dictionary = Dictionary(Dictionary(matching_eval.value).get("breakdown", {}))
	if float(matching_breakdown.get("route_progress_bonus", 0.0)) <= 0.0:
		return Result.failure("route progress bonus should reward execution sequence progress: %s" % str(matching_breakdown))
	var skipped_rollout := matching_rollout.duplicate(true)
	skipped_rollout["commands_executed"] = [
		{"actor": 0, "action_id": "skip", "params": {}},
	]
	var skipped_eval := StrategicPlanEvaluatorClass.evaluate_rollout(plan, skipped_rollout, profile)
	if not skipped_eval.ok:
		return skipped_eval
	var skipped_breakdown: Dictionary = Dictionary(Dictionary(skipped_eval.value).get("breakdown", {}))
	if float(matching_breakdown.get("route_progress_bonus", 0.0)) <= float(skipped_breakdown.get("route_progress_bonus", 0.0)):
		return Result.failure("route progress bonus should prefer matching sequence over skip: %s vs %s" % [str(matching_breakdown), str(skipped_breakdown)])
	return Result.success()

static func _test_route_progress_bonus_uses_incremental_milestones(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var plan = StrategicPlanClass.create(
		"supply_progress",
		0,
		"supply_capacity",
		0.0,
		["burger"],
		["house_near"],
		["burger_cook"],
		{},
		["supply"],
		2,
		16,
		["train", "produce_food"]
	)
	var base_rollout := {
		"engine": data["engine"],
		"commands_executed": [
			{"actor": 0, "action_id": "skip", "params": {}},
		],
		"cash_before": 0,
		"cash_min_after_first_positive": 0,
		"cash_max_seen": 0,
		"search_time_ms": 0,
		"milestones_gained": [],
		"salary_due_estimate": 0,
	}
	var base_eval := StrategicPlanEvaluatorClass.evaluate_rollout(plan, base_rollout, profile)
	if not base_eval.ok:
		return base_eval
	var milestone_rollout := base_rollout.duplicate(true)
	milestone_rollout["milestones_gained"] = ["first_train"]
	var milestone_eval := StrategicPlanEvaluatorClass.evaluate_rollout(plan, milestone_rollout, profile)
	if not milestone_eval.ok:
		return milestone_eval
	var base_breakdown: Dictionary = Dictionary(Dictionary(base_eval.value).get("breakdown", {}))
	var milestone_breakdown: Dictionary = Dictionary(Dictionary(milestone_eval.value).get("breakdown", {}))
	if float(milestone_breakdown.get("route_progress_bonus", 0.0)) <= float(base_breakdown.get("route_progress_bonus", 0.0)):
		return Result.failure("route progress bonus should use rollout milestones_gained incrementally: %s vs %s" % [str(milestone_breakdown), str(base_breakdown)])
	return Result.success()

static func _test_strategic_bot_budget_fallback(seed_val: int) -> Result:
	var inputs_read := _build_working_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var bot := StrategicBotClass.new()
	var profile_read := bot.configure_profile("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var decision := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(40)
	)
	if decision == null or decision.is_failure() or decision.command == null:
		return Result.failure("StrategicBot should fallback to StrategyBot under tiny budget")
	var trace: Dictionary = decision.trace
	if str(trace.get("strategic_failure", "")) != "insufficient_plan_search_budget":
		return Result.failure("StrategicBot budget fallback should be explicit: %s" % str(trace))
	var valid := LegalActionServiceClass.validate_command(data["engine"], decision.command, data["context"])
	if not valid.ok:
		return Result.failure("StrategicBot fallback returned invalid command: %s" % valid.error)
	return Result.success()

static func _test_strategic_bot_non_strategic_action_gate(seed_val: int) -> Result:
	var inputs_read := _build_working_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var bot := StrategicBotClass.new()
	var profile_read := bot.configure_profile("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var search_read := bot.configure_search_options({
		"strategic_budget_profile": "play",
		"strategic_search": "mcts",
		"strategic_min_search_budget_ms": 16,
		"strategic_min_plans_for_rollout": 1,
		"strategic_max_plans": 3,
		"strategic_horizon_decisions": 4,
		"strategic_horizon_rounds": 1,
		"strategic_rollout_step_budget_ms": 20,
		"strategic_config_id": "mcts_gate_test",
	})
	if not search_read.ok:
		return search_read
	var non_strategic_ids: Array[String] = []
	for action_id_val in Array(data["legal_action_ids"]):
		var action_id := str(action_id_val)
		if action_id == "skip" or action_id == "skip_sub_phase":
			non_strategic_ids.append(action_id)
	if non_strategic_ids.is_empty():
		return Result.failure("StrategicBot action gate fixture should expose a legal non-strategic skip action: %s" % str(data["legal_action_ids"]))
	var decision := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		non_strategic_ids,
		data["validate_fn"],
		TimeBudget.start(160)
	)
	if decision == null or decision.is_failure() or decision.command == null:
		return Result.failure("StrategicBot should fallback when no strategic action is legal")
	var trace: Dictionary = decision.trace
	if str(trace.get("strategic_failure", "")) != "no_strategic_legal_actions":
		return Result.failure("StrategicBot non-strategic action gate should be explicit: %s" % str(trace))
	if trace.has("evaluated_plans"):
		return Result.failure("StrategicBot should not evaluate plans without strategic legal actions: %s" % str(trace))
	return Result.success()

static func _test_strategic_search_requires_route_alternatives(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var observation := _synthetic_growth_observation(true)
	var generated := StrategicPlanGeneratorClass.generate(
		observation,
		profile,
		{
			"source_state": engine.get_state(),
			"max_plans": 6,
		}
	)
	if not generated.ok:
		return generated
	var generated_plans: Array = Array(generated.value)
	if generated_plans.is_empty():
		return Result.failure("route-alternative fixture should generate at least one plan: %s" % str(_plan_debug(generated.value)))
	var route_alternative_count := generated_plans.size()
	var search_read := StrategicSearchClass.choose_plan_beam(
		engine,
		observation,
		profile,
		TimeBudget.start(1000),
		{
			"max_plans": 6,
			"min_plans_for_rollout": route_alternative_count + 1,
			"horizon_decisions": 4,
			"horizon_rounds": 1,
			"step_budget_ms": 20,
		}
	)
	if search_read.ok:
		return Result.failure("StrategicSearch should not run beam when route alternatives are insufficient")
	if search_read.error.find("insufficient route alternatives") < 0:
		return Result.failure("StrategicSearch route alternative failure should be explicit: %s" % search_read.error)
	return Result.success()

static func _test_strategic_bot_plan_cache_reuse(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var bot := StrategicBotClass.new()
	var profile_read := bot.configure_profile("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var search_read := bot.configure_search_options({
		"strategic_search": "beam",
		"strategic_min_search_budget_ms": 16,
		"strategic_min_plans_for_rollout": 1,
		"strategic_max_plans": 2,
		"strategic_horizon_decisions": 4,
		"strategic_horizon_rounds": 1,
		"strategic_rollout_step_budget_ms": 20,
		"strategic_config_id": "cache_reuse_test",
	})
	if not search_read.ok:
		return search_read
	var first := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(600)
	)
	if first == null or first.is_failure() or first.command == null:
		return Result.failure("StrategicBot should produce a plan-backed decision for cache reuse: %s" % str(first))
	var first_trace: Dictionary = Dictionary(first.trace)
	if str(first_trace.get("search", "")) != "strategic":
		return Result.failure("StrategicBot first decision should search strategically: %s" % str(first_trace))
	var first_plan_id := str(first_trace.get("plan_id", ""))
	if first_plan_id.is_empty():
		return Result.failure("StrategicBot first decision should expose plan id: %s" % str(first_trace))
	bot._clear_route_history()
	var second := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(40)
	)
	if second == null or second.is_failure() or second.command == null:
		return Result.failure("StrategicBot should reuse cached plan under tight follow-up budget: %s" % str(second))
	var second_trace: Dictionary = Dictionary(second.trace)
	if str(second_trace.get("search", "")) != "strategic_cached":
		return Result.failure("StrategicBot should mark cached plan reuse: %s" % str(second_trace))
	if str(second_trace.get("plan_id", "")) != first_plan_id:
		return Result.failure("StrategicBot cached plan should match initial plan: %s vs %s" % [str(second_trace), first_plan_id])
	if int(second_trace.get("plan_search_time_ms", -1)) != 0:
		return Result.failure("StrategicBot cached plan should not re-run beam: %s" % str(second_trace))
	var valid := LegalActionServiceClass.validate_command(data["engine"], second.command, data["context"])
	if not valid.ok:
		return Result.failure("StrategicBot cached decision should remain valid: %s" % valid.error)
	return Result.success()

static func _test_strategic_bot_plan_cache_scopes_decision_window() -> Result:
	var bot := StrategicBotClass.new()
	var observation := _synthetic_income_observation()
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	var context := AiDecisionContext.create(
		observation.viewer_player_id,
		observation.phase,
		observation.sub_phase,
		observation.round_number,
		12345,
		[]
	)
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		observation.viewer_player_id,
		"marketing_income",
		10.0,
		["burger"],
		["house_near"],
		["campaign_manager"],
		{"cash_floor": 10},
		["marketing"],
		2,
		16,
		["recruit", "initiate_marketing", "produce_food"]
	)
	bot._store_plan_cache(observation, context, plan, {"score": 10.0}, ["skip_sub_phase", "recruit"])
	var same_window_plan = bot._cached_plan_for_current_window(observation, context, ["recruit", "skip"])
	if same_window_plan == null:
		return Result.failure("StrategicBot cache should survive non-strategic legal action noise within the same decision window")
	var shifted := _synthetic_income_observation()
	shifted.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var shifted_context := AiDecisionContext.create(
		shifted.viewer_player_id,
		shifted.phase,
		shifted.sub_phase,
		shifted.round_number,
		12345,
		[]
	)
	var shifted_plan = bot._cached_plan_for_current_window(shifted, shifted_context, ["skip_sub_phase", "produce_food"])
	if shifted_plan != null:
		return Result.failure("StrategicBot cache should not cross Working sub-phase windows")
	var changed_action_plan = bot._cached_plan_for_current_window(observation, context, ["skip_sub_phase", "train"])
	if changed_action_plan != null:
		return Result.failure("StrategicBot cache should not cross strategic legal action signatures")
	return Result.success()

static func _test_strategic_bot_route_history_memory(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var bot := StrategicBotClass.new()
	var profile_read := bot.configure_profile("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var search_read := bot.configure_search_options({
		"strategic_search": "beam",
		"strategic_min_search_budget_ms": 16,
		"strategic_min_plans_for_rollout": 1,
		"strategic_max_plans": 2,
		"strategic_horizon_decisions": 4,
		"strategic_horizon_rounds": 1,
		"strategic_rollout_step_budget_ms": 20,
		"strategic_config_id": "route_history_memory_test",
	})
	if not search_read.ok:
		return search_read
	var first := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(600)
	)
	if first == null or first.is_failure() or first.command == null:
		return Result.failure("StrategicBot should produce a plan-backed decision before recording route history: %s" % str(first))
	var first_trace: Dictionary = Dictionary(first.trace)
	var first_route_type := str(first_trace.get("route_type", "")).strip_edges()
	if first_route_type.is_empty():
		return Result.failure("StrategicBot should expose selected route type before recording history: %s" % str(first_trace))
	if not Array(first_trace.get("strategic_route_history", [])).is_empty():
		return Result.failure("StrategicBot should trace empty route history before the first record: %s" % str(first_trace))
	var recorded_history := bot._route_history_for_search()
	if recorded_history.size() != 1 or str(recorded_history[0]) != first_route_type:
		return Result.failure("StrategicBot should record the selected route type: history=%s trace=%s" % [str(recorded_history), str(first_trace)])

	var second := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(220)
	)
	if second == null or second.is_failure() or second.command == null:
		return Result.failure("StrategicBot should keep planning after route history changes: %s" % str(second))
	var second_trace: Dictionary = Dictionary(second.trace)
	if str(second_trace.get("search", "")) != "strategic":
		return Result.failure("StrategicBot should invalidate cached plan when route history changes: %s" % str(second_trace))
	if bool(second_trace.get("strategic_plan_cached", true)):
		return Result.failure("StrategicBot should mark route-history cache miss as uncached: %s" % str(second_trace))
	var second_history := Array(second_trace.get("strategic_route_history", []))
	if second_history.is_empty() or str(second_history[0]) != first_route_type:
		return Result.failure("StrategicBot second trace should carry forward prior route history: %s" % str(second_trace))

	var same_player_context := AiDecisionContext.create(
		data["context"].player_id,
		data["context"].phase,
		data["context"].sub_phase,
		int(data["context"].round_number) + 1,
		int(data["context"].decision_seed) + 1,
		[]
	)
	if bot._should_reset_route_history(same_player_context):
		return Result.failure("StrategicBot should keep route history for the same player in later rounds")
	var other_player_context := AiDecisionContext.create(
		int(data["context"].player_id) + 1,
		data["context"].phase,
		data["context"].sub_phase,
		data["context"].round_number,
		data["context"].decision_seed,
		[]
	)
	if not bot._should_reset_route_history(other_player_context):
		return Result.failure("StrategicBot should reset route history when the player changes")

	var profile := StrategyProfileClass.new()
	var profile_check := profile.configure("base_revenue_growth_v1")
	if not profile_check.ok:
		return profile_check
	var mcts_read := StrategicSearchClass.choose_plan_mcts(
		data["engine"],
		data["observation"],
		profile,
		TimeBudget.start(600),
		{
			"route_history": ["marketing_income"],
			"max_plans": 2,
			"min_plans_for_rollout": 1,
			"horizon_decisions": 4,
			"horizon_rounds": 1,
			"step_budget_ms": 20,
			"mcts_iterations": 2,
			"mcts_max_depth": 2,
			"mcts_top_k_per_node": 2,
		}
	)
	if not mcts_read.ok:
		return mcts_read
	var mcts_payload: Dictionary = Dictionary(mcts_read.value)
	var mcts_evaluated_plans: Array = Array(mcts_payload.get("evaluated_plans", []))
	if mcts_evaluated_plans.is_empty():
		return Result.failure("Strategic plan MCTS should expose evaluated plan nodes for route history tracing: %s" % str(mcts_payload))
	var first_eval_val = mcts_evaluated_plans[0]
	if not (first_eval_val is Dictionary):
		return Result.failure("Strategic plan MCTS should return evaluated nodes as dictionaries: %s" % str(mcts_payload))
	var first_eval: Dictionary = first_eval_val
	var rollout_history := Array(first_eval.get("route_history", []))
	if rollout_history.is_empty() or str(rollout_history[0]) != "marketing_income":
		return Result.failure("Strategic plan MCTS should preserve incoming route history in rollout trace: %s" % str(first_eval))
	return Result.success()

static func _test_strategic_bot_default_beam_search(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var bot := StrategicBotClass.new()
	var profile_read := bot.configure_profile("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var decision := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(1600)
	)
	if decision == null or decision.is_failure() or decision.command == null:
		return Result.failure("StrategicBot should enter strategic search with default rollout gate: %s" % str(decision))
	var trace: Dictionary = Dictionary(decision.trace)
	var search := str(trace.get("search", ""))
	if search == "strategic":
		if str(trace.get("strategic_search", "")) != "compared":
			return Result.failure("StrategicBot default rollout gate should use compared mode: %s" % str(trace))
		if str(trace.get("plan_id", "")).is_empty():
			return Result.failure("StrategicBot default rollout gate should expose selected plan: %s" % str(trace))
		var hard_gate: Dictionary = Dictionary(trace.get("strategic_hard_gate", {}))
		if hard_gate.is_empty():
			return Result.failure("StrategicBot compared override should expose hard gate trace: %s" % str(trace))
	elif search == "strategy":
		var failure := str(trace.get("strategic_failure", ""))
		if failure.find("choose_plan_compared") < 0:
			return Result.failure("StrategicBot default fallback should come from compared search: %s" % str(trace))
	else:
		return Result.failure("StrategicBot default rollout gate should use compared search or fallback: %s" % str(trace))
	var valid := LegalActionServiceClass.validate_command(data["engine"], decision.command, data["context"])
	if not valid.ok:
		return Result.failure("StrategicBot default rollout gate returned invalid command: %s" % valid.error)
	return Result.success()

static func _test_rollout_search_and_evaluator(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var engine: GameEngine = data["engine"]
	var source_hash := str(engine.get_state().compute_hash())
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var plans_read := StrategicPlanGeneratorClass.generate(
		data["observation"],
		profile,
		{
			"source_state": engine.get_state(),
			"max_plans": 3,
		}
	)
	if not plans_read.ok:
		return plans_read
	var plans: Array = plans_read.value
	if plans.is_empty():
		return Result.failure("StrategicPlanGenerator should create at least one rollout plan")
	var plan = plans[0]
	var first_rollout := StrategicPlanRunnerClass.rollout(
		engine,
		plan,
		profile,
		{
			"horizon_decisions": 4,
			"horizon_rounds": 1,
			"step_budget_ms": 20,
			"budget": TimeBudget.start(160),
			"route_history": ["marketing_income"],
		}
	)
	if not first_rollout.ok:
		return first_rollout
	var first_rollout_payload: Dictionary = Dictionary(first_rollout.value)
	if str(engine.get_state().compute_hash()) != source_hash:
		return Result.failure("StrategicPlanRunner should not mutate source engine")
	var second_rollout := StrategicPlanRunnerClass.rollout(
		engine,
		plan,
		profile,
		{
			"horizon_decisions": 4,
			"horizon_rounds": 1,
			"step_budget_ms": 20,
			"budget": TimeBudget.start(160),
			"route_history": ["marketing_income"],
		}
	)
	if not second_rollout.ok:
		return second_rollout
	if str(_rollout_actions(first_rollout_payload)) != str(_rollout_actions(second_rollout.value)):
		return Result.failure("StrategicPlanRunner should be deterministic for same state/plan")
	var route_history := Array(first_rollout_payload.get("route_history", []))
	if str(route_history) != str(["marketing_income"]):
		return Result.failure("StrategicPlanRunner should preserve route_history in rollout payload: %s" % str(first_rollout_payload))
	var eval_read := StrategicPlanEvaluatorClass.evaluate_rollout(plan, first_rollout_payload, profile)
	if not eval_read.ok:
		return eval_read
	var eval_payload: Dictionary = Dictionary(eval_read.value)
	var breakdown: Dictionary = Dictionary(eval_payload.get("breakdown", {}))
	for key in ["cash_delta", "cash_min_after_first_positive", "milestone_value", "salary_shortfall_penalty", "route_completion_bonus", "route_transition_bonus", "route_stall_penalty", "search_cost_penalty"]:
		if not breakdown.has(key):
			return Result.failure("StrategicPlanEvaluator should expose breakdown key %s: %s" % [key, str(breakdown)])
	var telemetry: Dictionary = Dictionary(eval_payload.get("telemetry", {}))
	for key in ["milestones_gained", "demand_created", "demand_sold", "lost_to_competitor", "salary_due_estimate"]:
		if not telemetry.has(key):
			return Result.failure("StrategicPlanEvaluator should expose telemetry key %s: %s" % [key, str(telemetry)])
	var transition_plan = StrategicPlanClass.create(
		"supply_transition_bonus",
		plan.owner_player_id,
		"supply_capacity",
		0.0,
		["burger"],
		["house_near"],
		["burger_cook"],
		{},
		["supply"],
		2,
		16,
		["train", "produce_food"]
	)
	var repeat_route_rollout: Dictionary = first_rollout_payload.duplicate(true)
	repeat_route_rollout["route_history"] = ["supply_capacity", "supply_capacity"]
	repeat_route_rollout["cash_before"] = 18
	repeat_route_rollout["cash_min_after_first_positive"] = 18
	repeat_route_rollout["cash_max_seen"] = 24
	var switch_route_rollout: Dictionary = first_rollout_payload.duplicate(true)
	switch_route_rollout["route_history"] = ["marketing_income", "marketing_income"]
	switch_route_rollout["cash_before"] = 18
	switch_route_rollout["cash_min_after_first_positive"] = 18
	switch_route_rollout["cash_max_seen"] = 24
	var repeat_route_eval := StrategicPlanEvaluatorClass.evaluate_rollout(transition_plan, repeat_route_rollout, profile)
	if not repeat_route_eval.ok:
		return repeat_route_eval
	var switch_route_eval := StrategicPlanEvaluatorClass.evaluate_rollout(transition_plan, switch_route_rollout, profile)
	if not switch_route_eval.ok:
		return switch_route_eval
	var repeat_breakdown: Dictionary = Dictionary(Dictionary(repeat_route_eval.value).get("breakdown", {}))
	var switch_breakdown: Dictionary = Dictionary(Dictionary(switch_route_eval.value).get("breakdown", {}))
	if float(switch_breakdown.get("route_transition_bonus", 0.0)) <= float(repeat_breakdown.get("route_transition_bonus", 0.0)):
		return Result.failure("route transition bonus should prefer marketing-to-supply switch over repeated supply: %s vs %s" % [str(switch_breakdown), str(repeat_breakdown)])
	if float(Dictionary(switch_route_eval.value).get("score", 0.0)) <= float(Dictionary(repeat_route_eval.value).get("score", 0.0)):
		return Result.failure("route transition bonus should affect evaluator score: %s vs %s" % [str(switch_route_eval.value), str(repeat_route_eval.value)])
	var search_read := StrategicSearchClass.choose_plan_beam(
		engine,
		data["observation"],
		profile,
		TimeBudget.start(220),
		{
			"max_plans": 2,
			"horizon_decisions": 4,
			"horizon_rounds": 1,
			"step_budget_ms": 20,
		}
	)
	if not search_read.ok:
		return search_read
	var search_payload: Dictionary = search_read.value
	var selected_plan = search_payload.get("plan", null)
	if selected_plan == null or not selected_plan.has_method("to_trace_dict"):
		return Result.failure("StrategicSearch should return best plan: %s" % str(search_payload))
	if Array(search_payload.get("evaluated_plans", [])).is_empty():
		return Result.failure("StrategicSearch should trace evaluated plans: %s" % str(search_payload))
	var search_telemetry: Dictionary = Dictionary(search_payload.get("telemetry", {}))
	if search_telemetry.is_empty():
		return Result.failure("StrategicSearch should expose top-level telemetry: %s" % str(search_payload))
	return Result.success()

static func _test_growth_plan_requires_income_footing() -> Result:
	var profile := StrategyProfileClass.new()
	profile.configure_base_revenue()
	var early := _synthetic_growth_observation(false)
	var early_read := StrategicPlanGeneratorClass.generate(early, profile, {"max_plans": 6})
	if not early_read.ok:
		return early_read
	if _has_route_type(Array(early_read.value), "growth"):
		return Result.failure("StrategicPlanGenerator should not create speculative growth before income footing: %s" % str(_plan_debug(early_read.value)))
	var grounded := _synthetic_growth_observation(true)
	var grounded_read := StrategicPlanGeneratorClass.generate(grounded, profile, {"max_plans": 6})
	if not grounded_read.ok:
		return grounded_read
	if not _has_route_type(Array(grounded_read.value), "growth"):
		return Result.failure("StrategicPlanGenerator should create growth plan once income footing exists: %s" % str(_plan_debug(grounded_read.value)))
	return Result.success()

static func _test_evaluator_growth_bonus_requires_progress(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var observation := _synthetic_growth_observation(true)
	var plans_read := StrategicPlanGeneratorClass.generate(
		observation,
		profile,
		{
			"source_state": engine.get_state(),
			"max_plans": 6,
		}
	)
	if not plans_read.ok:
		return plans_read
	var growth_plan = null
	for plan_val in Array(plans_read.value):
		if plan_val != null and plan_val.has_method("to_trace_dict") and str(plan_val.route_type) == "growth":
			growth_plan = plan_val
			break
	if growth_plan == null:
		return Result.failure("StrategicPlanGenerator should create a growth plan for evaluator guard")
	var no_progress_rollout := {
		"engine": engine,
		"commands_executed": [
			{
				"actor": growth_plan.owner_player_id,
				"action_id": "skip",
				"params": {},
			},
		],
		"cash_before": int(observation.own_player.get("cash", 0)),
		"cash_min_after_first_positive": 0,
		"cash_max_seen": int(observation.own_player.get("cash", 0)),
		"search_time_ms": 0,
	}
	var no_progress_eval := StrategicPlanEvaluatorClass.evaluate_rollout(growth_plan, no_progress_rollout, profile)
	if not no_progress_eval.ok:
		return no_progress_eval
	var no_progress_breakdown: Dictionary = Dictionary(Dictionary(no_progress_eval.value).get("breakdown", {}))
	if float(no_progress_breakdown.get("route_completion_bonus", 0.0)) > 0.0:
		return Result.failure("growth plan should not get completion bonus without growth progress: %s" % str(no_progress_breakdown))
	var progress_rollout := no_progress_rollout.duplicate(true)
	progress_rollout["commands_executed"] = [
		{
			"actor": growth_plan.owner_player_id,
			"action_id": "place_house",
			"params": {},
		},
	]
	var progress_eval := StrategicPlanEvaluatorClass.evaluate_rollout(growth_plan, progress_rollout, profile)
	if not progress_eval.ok:
		return progress_eval
	var progress_breakdown: Dictionary = Dictionary(Dictionary(progress_eval.value).get("breakdown", {}))
	if float(progress_breakdown.get("route_completion_bonus", 0.0)) <= 0.0:
		return Result.failure("growth plan should get completion bonus for growth progress: %s" % str(progress_breakdown))
	return Result.success()

static func _test_evaluator_penalizes_stalled_route(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		0.0,
		["burger"],
		["house_left"],
		["campaign_manager"],
		{},
		["marketing"],
		2,
		16,
		["recruit", "initiate_marketing", "produce_food"]
	)
	var stalled_rollout := {
		"engine": data["engine"],
		"commands_executed": [
			{"actor": 0, "action_id": "skip_sub_phase", "params": {}},
		],
		"cash_before": 0,
		"cash_min_after_first_positive": 0,
		"cash_max_seen": 0,
		"search_time_ms": 0,
		"milestones_gained": [],
		"demand_created": 0,
		"demand_sold": 0,
	}
	var stalled_eval := StrategicPlanEvaluatorClass.evaluate_rollout(plan, stalled_rollout, profile)
	if not stalled_eval.ok:
		return stalled_eval
	var stalled_payload: Dictionary = Dictionary(stalled_eval.value)
	var stalled_breakdown: Dictionary = Dictionary(stalled_payload.get("breakdown", {}))
	var stalled_telemetry: Dictionary = Dictionary(stalled_payload.get("telemetry", {}))
	if not bool(stalled_telemetry.get("route_stalled", false)):
		return Result.failure("stalled route should be marked in telemetry: %s" % str(stalled_telemetry))
	if float(stalled_breakdown.get("route_stall_penalty", 0.0)) >= 0.0:
		return Result.failure("stalled route should receive a negative penalty: %s" % str(stalled_breakdown))

	var progress_rollout := stalled_rollout.duplicate(true)
	progress_rollout["commands_executed"] = [
		{"actor": 0, "action_id": "initiate_marketing", "params": {"product": "burger"}},
	]
	var progress_eval := StrategicPlanEvaluatorClass.evaluate_rollout(plan, progress_rollout, profile)
	if not progress_eval.ok:
		return progress_eval
	var progress_payload: Dictionary = Dictionary(progress_eval.value)
	var progress_breakdown: Dictionary = Dictionary(progress_payload.get("breakdown", {}))
	var progress_telemetry: Dictionary = Dictionary(progress_payload.get("telemetry", {}))
	if bool(progress_telemetry.get("route_stalled", false)):
		return Result.failure("route action progress should clear stalled telemetry: %s" % str(progress_telemetry))
	if float(progress_breakdown.get("route_stall_penalty", -1.0)) != 0.0:
		return Result.failure("route action progress should not receive stalled penalty: %s" % str(progress_breakdown))
	if float(progress_payload.get("score", 0.0)) <= float(stalled_payload.get("score", 0.0)):
		return Result.failure("route progress should score above stalled route: stalled=%s progress=%s" % [str(stalled_breakdown), str(progress_breakdown)])
	return Result.success()

static func _test_route_transition_bonus_waits_for_cash_footing(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var repeat_plan = StrategicPlanClass.create(
		"marketing_repeat",
		0,
		"marketing_income",
		0.0,
		["burger"],
		["house_left"],
		["campaign_manager"],
		{},
		["marketing"],
		2,
		16,
		["recruit", "initiate_marketing", "produce_food"]
	)
	var switch_plan = StrategicPlanClass.create(
		"supply_switch",
		0,
		"supply_capacity",
		0.0,
		["burger"],
		["house_left"],
		["burger_cook"],
		{},
		["supply"],
		2,
		16,
		["train", "produce_food"]
	)
	var early_rollout := {
		"engine": data["engine"],
		"commands_executed": [
			{"actor": 0, "action_id": "initiate_marketing", "params": {"product": "burger"}},
		],
		"cash_before": 0,
		"cash_min_after_first_positive": 0,
		"cash_max_seen": 0,
		"route_history": ["marketing_income"],
		"search_time_ms": 0,
		"milestones_gained": [],
		"demand_created": 0,
		"demand_sold": 0,
	}
	var early_repeat_eval := StrategicPlanEvaluatorClass.evaluate_rollout(repeat_plan, early_rollout, profile)
	if not early_repeat_eval.ok:
		return early_repeat_eval
	var early_switch_eval := StrategicPlanEvaluatorClass.evaluate_rollout(switch_plan, early_rollout, profile)
	if not early_switch_eval.ok:
		return early_switch_eval
	var early_repeat_breakdown: Dictionary = Dictionary(Dictionary(early_repeat_eval.value).get("breakdown", {}))
	var early_switch_breakdown: Dictionary = Dictionary(Dictionary(early_switch_eval.value).get("breakdown", {}))
	var early_repeat_bonus := float(early_repeat_breakdown.get("route_transition_bonus", 0.0))
	var early_switch_bonus := float(early_switch_breakdown.get("route_transition_bonus", 0.0))
	if early_repeat_bonus <= 0.0:
		return Result.failure("route transition bonus should keep early marketing route positive before cash footing: %s" % str(early_repeat_breakdown))
	if early_switch_bonus > 0.0:
		return Result.failure("route transition bonus should not reward early marketing-to-supply switch before cash footing: %s" % str(early_switch_breakdown))
	if early_switch_bonus > early_repeat_bonus:
		return Result.failure("route transition bonus should not prefer early marketing-to-supply switch before cash footing: switch=%f repeat=%f" % [early_switch_bonus, early_repeat_bonus])

	var grounded_rollout := early_rollout.duplicate(true)
	grounded_rollout["cash_before"] = 18
	grounded_rollout["cash_min_after_first_positive"] = 18
	grounded_rollout["cash_max_seen"] = 24
	var grounded_repeat_eval := StrategicPlanEvaluatorClass.evaluate_rollout(repeat_plan, grounded_rollout, profile)
	if not grounded_repeat_eval.ok:
		return grounded_repeat_eval
	var grounded_switch_eval := StrategicPlanEvaluatorClass.evaluate_rollout(switch_plan, grounded_rollout, profile)
	if not grounded_switch_eval.ok:
		return grounded_switch_eval
	var grounded_repeat_bonus := float(Dictionary(Dictionary(grounded_repeat_eval.value).get("breakdown", {})).get("route_transition_bonus", 0.0))
	var grounded_switch_bonus := float(Dictionary(Dictionary(grounded_switch_eval.value).get("breakdown", {})).get("route_transition_bonus", 0.0))
	if grounded_switch_bonus <= grounded_repeat_bonus:
		return Result.failure("route transition bonus should prefer marketing-to-supply switch after cash footing: switch=%f repeat=%f" % [grounded_switch_bonus, grounded_repeat_bonus])
	if grounded_switch_bonus <= early_switch_bonus:
		return Result.failure("route transition bonus should increase after cash footing: early=%f grounded=%f" % [early_switch_bonus, grounded_switch_bonus])
	return Result.success()

static func _test_strategic_search_filters_stalled_routes() -> Result:
	var evaluated: Array[Dictionary] = [
		{
			"plan_id": "stalled",
			"score": 500.0,
			"telemetry": {"route_stalled": true},
		},
		{
			"plan_id": "progress",
			"score": 10.0,
			"telemetry": {"route_stalled": false},
		},
		{
			"plan_id": "failed",
			"score": -INF,
			"telemetry": {},
		},
	]
	var actionable := StrategicSearchClass._actionable_evaluated(evaluated)
	if actionable.size() != 1 or str(actionable[0].get("plan_id", "")) != "progress":
		return Result.failure("StrategicSearch should keep only non-stalled evaluated plans: %s" % str(actionable))
	var mcts_actionable := StrategicMCTSSearchClass._actionable_nodes([
		{
			"plan_id": "stalled",
			"leaf_telemetry": {"route_stalled": true},
		},
		{
			"plan_id": "progress",
			"leaf_telemetry": {"route_stalled": false},
		},
	])
	if mcts_actionable.size() != 1 or str(mcts_actionable[0].get("plan_id", "")) != "progress":
		return Result.failure("StrategicMCTSSearch should keep only actionable root nodes: %s" % str(mcts_actionable))
	var all_stalled := StrategicSearchClass._actionable_evaluated([
		{"plan_id": "stalled", "score": 500.0, "telemetry": {"route_stalled": true}},
	])
	if not all_stalled.is_empty():
		return Result.failure("StrategicSearch should reject all-stalled route sets: %s" % str(all_stalled))
	var mcts_all_stalled := StrategicMCTSSearchClass._actionable_nodes([
		{"plan_id": "stalled", "leaf_telemetry": {"route_stalled": true}},
	])
	if not mcts_all_stalled.is_empty():
		return Result.failure("StrategicMCTSSearch should reject all-stalled root sets: %s" % str(mcts_all_stalled))
	var stalled_best_child: Variant = StrategicMCTSSearchClass._select_best_child({
		"visits": 4,
		"children": [
			{
				"plan_id": "stalled",
				"prior_score": 999.0,
				"visits": 1,
				"q": 999.0,
				"depth": 1,
				"leaf_telemetry": {"route_stalled": true},
			},
			{
				"plan_id": "progress",
				"prior_score": 1.0,
				"visits": 1,
				"q": 1.0,
				"depth": 1,
				"leaf_telemetry": {"route_stalled": false},
			},
		]
	}, 1.15)
	if stalled_best_child == null or str(Dictionary(stalled_best_child).get("plan_id", "")) != "progress":
		return Result.failure("StrategicMCTSSearch should skip stalled non-root children during selection: %s" % str(stalled_best_child))
	var stalled_plan = StrategicPlanClass.create(
		"stalled_leaf",
		0,
		"marketing_income",
		1.0,
		["burger"],
		[],
		["campaign_manager"],
		{},
		["marketing"],
		1,
		1,
		["initiate_marketing"]
	)
	var stalled_leaf := {
		"engine": null,
		"depth": 1,
		"terminal": false,
		"expanded": true,
		"children": [],
		"plan_entries": [
			{
				"plan": stalled_plan,
				"plan_id": stalled_plan.id,
				"route_type": stalled_plan.route_type,
				"prior_score": stalled_plan.prior_score,
			},
		],
		"leaf_telemetry": {"route_stalled": true},
	}
	var stalled_route_read := StrategicMCTSSearchClass._select_leaf(
		stalled_leaf,
		0,
		null,
		{},
		1,
		2,
		20,
		TimeBudget.start(160),
		0.0,
		1.0,
		1,
		1,
		false,
		[],
		{}
	)
	if not stalled_route_read.ok:
		return stalled_route_read
	var stalled_route: Dictionary = Dictionary(stalled_route_read.value)
	if int(stalled_route.get("attempted_rollouts", -1)) != 0:
		return Result.failure("StrategicMCTSSearch should not spend rollout budget on stalled non-root leaves: %s" % str(stalled_route))
	if int(stalled_route.get("expanded_nodes", -1)) != 0:
		return Result.failure("StrategicMCTSSearch should not expand stalled non-root leaves: %s" % str(stalled_route))
	if Array(stalled_route.get("path", [])).size() != 1:
		return Result.failure("StrategicMCTSSearch should return the stalled leaf without descending further: %s" % str(stalled_route))
	if not bool(Dictionary(stalled_route.get("leaf", {})).get("terminal", false)):
		return Result.failure("StrategicMCTSSearch should mark stalled non-root leaves terminal: %s" % str(stalled_route))
	return Result.success()

static func _test_evaluator_search_cost_is_trace_only(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var plans_read := StrategicPlanGeneratorClass.generate(
		data["observation"],
		profile,
		{
			"source_state": data["engine"].get_state(),
			"max_plans": 3,
		}
	)
	if not plans_read.ok:
		return plans_read
	var plans: Array = plans_read.value
	if plans.is_empty():
		return Result.failure("StrategicPlanGenerator should provide a plan for search cost guard")
	var plan = plans[0]
	var rollout_read := StrategicPlanRunnerClass.rollout(
		data["engine"],
		plan,
		profile,
		{
			"horizon_decisions": 4,
			"horizon_rounds": 1,
			"step_budget_ms": 20,
			"budget": TimeBudget.start(160),
		}
	)
	if not rollout_read.ok:
		return rollout_read
	var rollout_a: Dictionary = Dictionary(rollout_read.value).duplicate(true)
	var rollout_b: Dictionary = rollout_a.duplicate(true)
	rollout_a["search_time_ms"] = 0
	rollout_b["search_time_ms"] = 5000
	var eval_a := StrategicPlanEvaluatorClass.evaluate_rollout(plan, rollout_a, profile)
	if not eval_a.ok:
		return eval_a
	var eval_b := StrategicPlanEvaluatorClass.evaluate_rollout(plan, rollout_b, profile)
	if not eval_b.ok:
		return eval_b
	var score_a := float(Dictionary(eval_a.value).get("score", 0.0))
	var score_b := float(Dictionary(eval_b.value).get("score", 0.0))
	if not is_equal_approx(score_a, score_b):
		return Result.failure("search cost should not change strategic score: %f vs %f" % [score_a, score_b])
	var breakdown_a: Dictionary = Dictionary(Dictionary(eval_a.value).get("breakdown", {}))
	var breakdown_b: Dictionary = Dictionary(Dictionary(eval_b.value).get("breakdown", {}))
	if is_equal_approx(float(breakdown_a.get("search_cost_penalty", 0.0)), float(breakdown_b.get("search_cost_penalty", 0.0))):
		return Result.failure("search cost penalty trace should still reflect elapsed search time: %s vs %s" % [str(breakdown_a), str(breakdown_b)])
	return Result.success()

static func _test_strategic_mcts_transposition_registry_prunes_lower_or_equal_paths(seed_val: int) -> Result:
	var best_state_scores := {}
	var first := {
		"state_key": "same_state|same_plan",
		"leaf_value_score": 10.0,
	}
	var first_payload := StrategicMCTSSearchClass._register_transposition_state(first, best_state_scores)
	if not bool(first_payload.get("keep", false)) or bool(first_payload.get("duplicate", false)) or bool(first_payload.get("pruned", false)):
		return Result.failure("first plan-state visit should be kept without duplicate/pruned flags: %s" % str(first_payload))
	if not is_equal_approx(float(best_state_scores.get("same_state|same_plan", 0.0)), 10.0):
		return Result.failure("first plan-state visit should register value score: %s" % str(best_state_scores))

	var equal := {
		"state_key": "same_state|same_plan",
		"leaf_value_score": 10.0,
	}
	var equal_payload := StrategicMCTSSearchClass._register_transposition_state(equal, best_state_scores)
	if bool(equal_payload.get("keep", true)) or not bool(equal_payload.get("duplicate", false)) or not bool(equal_payload.get("pruned", false)):
		return Result.failure("equal duplicate plan-state should be pruned: %s" % str(equal_payload))

	var lower := {
		"state_key": "same_state|same_plan",
		"leaf_value_score": 9.0,
	}
	var lower_payload := StrategicMCTSSearchClass._register_transposition_state(lower, best_state_scores)
	if bool(lower_payload.get("keep", true)) or not bool(lower_payload.get("duplicate", false)) or not bool(lower_payload.get("pruned", false)):
		return Result.failure("lower duplicate plan-state should be pruned: %s" % str(lower_payload))
	if not is_equal_approx(float(best_state_scores.get("same_state|same_plan", 0.0)), 10.0):
		return Result.failure("pruned duplicate should not lower best plan-state score: %s" % str(best_state_scores))

	var higher := {
		"state_key": "same_state|same_plan",
		"leaf_value_score": 12.0,
	}
	var higher_payload := StrategicMCTSSearchClass._register_transposition_state(higher, best_state_scores)
	if not bool(higher_payload.get("keep", false)) or not bool(higher_payload.get("duplicate", false)) or bool(higher_payload.get("pruned", false)):
		return Result.failure("higher duplicate plan-state should be kept and update best score: %s" % str(higher_payload))
	if not is_equal_approx(float(best_state_scores.get("same_state|same_plan", 0.0)), 12.0):
		return Result.failure("higher duplicate should update best plan-state score: %s" % str(best_state_scores))

	var no_key := {
		"leaf_value_score": -3.0,
	}
	var no_key_payload := StrategicMCTSSearchClass._register_transposition_state(no_key, best_state_scores)
	if not bool(no_key_payload.get("keep", false)) or bool(no_key_payload.get("duplicate", false)) or bool(no_key_payload.get("pruned", false)):
		return Result.failure("missing plan-state key should remain keepable without duplicate/pruned flags: %s" % str(no_key_payload))

	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var same_state_engine: GameEngine = data["engine"]
	var plan_a = StrategicPlanClass.create("same_state_plan_a", 0, "marketing_income", 10.0)
	var plan_b = StrategicPlanClass.create("same_state_plan_b", 0, "marketing_income", 10.0)
	var plan_a_key := StrategicMCTSSearchClass._state_key_for_engine(same_state_engine, plan_a.id)
	var plan_b_key := StrategicMCTSSearchClass._state_key_for_engine(same_state_engine, plan_b.id)
	if plan_a_key.is_empty() or plan_b_key.is_empty():
		return Result.failure("plan-state keys should be available for active plans: %s / %s" % [plan_a_key, plan_b_key])
	if plan_a_key == plan_b_key:
		return Result.failure("plan-state key should include active plan id: %s vs %s" % [plan_a_key, plan_b_key])

	var plan_state_scores := {}
	var plan_node_a := StrategicMCTSSearchClass._make_node(same_state_engine, 0, plan_a, 1, 0.0)
	plan_node_a["leaf_value_score"] = 10.0
	var plan_node_b := StrategicMCTSSearchClass._make_node(same_state_engine, 0, plan_b, 1, 0.0)
	plan_node_b["leaf_value_score"] = 10.0
	var plan_node_a_payload := StrategicMCTSSearchClass._register_transposition_state(plan_node_a, plan_state_scores)
	var plan_node_b_payload := StrategicMCTSSearchClass._register_transposition_state(plan_node_b, plan_state_scores)
	if not bool(plan_node_a_payload.get("keep", false)) or bool(plan_node_a_payload.get("duplicate", false)) or bool(plan_node_a_payload.get("pruned", false)):
		return Result.failure("first active-plan node should be kept as a unique plan-state: %s" % str(plan_node_a_payload))
	if not bool(plan_node_b_payload.get("keep", false)) or bool(plan_node_b_payload.get("duplicate", false)) or bool(plan_node_b_payload.get("pruned", false)):
		return Result.failure("same engine state with a different active plan should stay unique: %s" % str(plan_node_b_payload))
	if not plan_state_scores.has(plan_a_key) or not plan_state_scores.has(plan_b_key):
		return Result.failure("active-plan transposition registry should store both plan-state keys: %s" % str(plan_state_scores))
	return Result.success()

static func _test_strategic_mcts_backpropagates_best_leaf_path() -> Result:
	var root := {}
	var child := {}
	var leaf := {
		"depth": 2,
		"path": [
			{"plan_id": "income", "depth": 1},
			{"plan_id": "supply", "depth": 2},
		],
	}
	StrategicMCTSSearchClass._backpropagate([root, child, leaf], 15.0)
	if int(root.get("visits", 0)) != 1 or int(child.get("visits", 0)) != 1 or int(leaf.get("visits", 0)) != 1:
		return Result.failure("MCTS backprop should increment visits along the plan path: root=%s child=%s leaf=%s" % [str(root), str(child), str(leaf)])
	if not is_equal_approx(float(root.get("q", 0.0)), 15.0):
		return Result.failure("MCTS backprop should update q from leaf value: %s" % str(root))
	var best_path: Array = Array(root.get("best_leaf_path", []))
	if best_path.size() != 2:
		return Result.failure("MCTS backprop should preserve best leaf plan path: %s" % str(root))
	if str(Dictionary(best_path[1]).get("plan_id", "")) != "supply":
		return Result.failure("MCTS best path should keep the leaf continuation plan: %s" % str(best_path))
	var weaker_leaf := {
		"depth": 1,
		"path": [
			{"plan_id": "weaker", "depth": 1},
		],
	}
	StrategicMCTSSearchClass._backpropagate([root, child, weaker_leaf], 10.0)
	if str(Dictionary(Array(root.get("best_leaf_path", []))[0]).get("plan_id", "")) != "income":
		return Result.failure("lower value leaf should not replace best path: %s" % str(root))
	var stronger_leaf := {
		"depth": 1,
		"path": [
			{"plan_id": "stronger", "depth": 1},
		],
	}
	StrategicMCTSSearchClass._backpropagate([root, child, stronger_leaf], 16.0)
	if str(Dictionary(Array(root.get("best_leaf_path", []))[0]).get("plan_id", "")) != "stronger":
		return Result.failure("higher value leaf should replace best path: %s" % str(root))
	if int(root.get("best_leaf_depth", 0)) != 1:
		return Result.failure("best leaf depth should track selected best path depth: %s" % str(root))
	return Result.success()

static func _test_strategic_mcts_root_selection_respects_visit_floor() -> Result:
	var prior_guard_nodes: Array = [
		{
			"plan_id": "searched",
			"visits": 1,
			"q": 20.0,
			"prior_score": 1.0,
		},
		{
			"plan_id": "prior",
			"visits": 0,
			"q": 0.0,
			"prior_score": 100.0,
		},
	]
	var prior_guard := StrategicMCTSSearchClass._select_final_root_child(prior_guard_nodes, 2, true)
	if str(prior_guard.get("selection_mode", "")) != "prior_guard" or not bool(prior_guard.get("prior_guarded", false)):
		return Result.failure("MCTS root selection should stay prior-guarded before the visit floor: %s" % str(prior_guard))
	if str(Dictionary(Array(prior_guard.get("nodes", []))[0]).get("plan_id", "")) != "prior":
		return Result.failure("MCTS root selection should prefer prior when the visit floor is not met: %s" % str(prior_guard))
	if not bool(prior_guard.get("budget_limited", false)):
		return Result.failure("MCTS root selection should preserve budget_limited telemetry: %s" % str(prior_guard))

	var visit_nodes: Array = [
		{
			"plan_id": "searched",
			"visits": 2,
			"q": 20.0,
			"prior_score": 1.0,
		},
		{
			"plan_id": "prior",
			"visits": 2,
			"q": 1.0,
			"prior_score": 100.0,
		},
	]
	var visit_selection := StrategicMCTSSearchClass._select_final_root_child(visit_nodes, 2, true)
	if str(visit_selection.get("selection_mode", "")) != "visits" or bool(visit_selection.get("prior_guarded", true)):
		return Result.failure("MCTS root selection should use visits once the floor is satisfied, even under budget pressure: %s" % str(visit_selection))
	if str(Dictionary(Array(visit_selection.get("nodes", []))[0]).get("plan_id", "")) != "searched":
		return Result.failure("MCTS root selection should prefer the stronger searched root once the visit floor is met: %s" % str(visit_selection))
	return Result.success()

static func _test_strategic_mcts_search_returns_plan_level_trace(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var bot := StrategicBotClass.new()
	var options_read := bot.configure_search_options({
		"strategic_search": "mcts",
		"strategic_min_search_budget_ms": 16,
		"strategic_min_plans_for_rollout": 1,
		"strategic_max_plans": 3,
		"strategic_horizon_decisions": 4,
		"strategic_horizon_rounds": 1,
		"strategic_rollout_step_budget_ms": 20,
		"mcts_iterations": 4,
		"mcts_max_depth": 2,
		"mcts_top_k_per_node": 3,
	})
	if not options_read.ok:
		return options_read
	var effective_options: Dictionary = bot._effective_options()
	if int(effective_options.get("max_plans", 0)) != 3:
		return Result.failure("StrategicBot mcts options should map strategic_max_plans to max_plans: %s" % str(effective_options))
	if int(effective_options.get("horizon_decisions", 0)) != 4:
		return Result.failure("StrategicBot mcts options should map strategic_horizon_decisions: %s" % str(effective_options))
	if int(effective_options.get("horizon_rounds", 0)) != 1:
		return Result.failure("StrategicBot mcts options should map strategic_horizon_rounds: %s" % str(effective_options))
	if int(effective_options.get("step_budget_ms", 0)) != 20:
		return Result.failure("StrategicBot mcts options should map strategic_rollout_step_budget_ms: %s" % str(effective_options))
	if int(effective_options.get("min_plans_for_rollout", 0)) != 1:
		return Result.failure("StrategicBot mcts options should map strategic_min_plans_for_rollout: %s" % str(effective_options))
	var search_read := StrategicSearchClass.choose_plan_mcts(
		data["engine"],
		data["observation"],
		profile,
		TimeBudget.start(600),
		effective_options
	)
	if not search_read.ok:
		return search_read
	var payload: Dictionary = Dictionary(search_read.value)
	if payload.has("command"):
		return Result.failure("Strategic plan MCTS should return a plan payload, not a raw command: %s" % str(payload))
	var plan_val = payload.get("plan", null)
	if plan_val == null or not plan_val.has_method("to_trace_dict"):
		return Result.failure("Strategic plan MCTS should return the selected plan: %s" % str(payload))
	if int(payload.get("mcts_iterations", 0)) <= 0:
		return Result.failure("Strategic plan MCTS should execute plan-level iterations: %s" % str(payload))
	if int(payload.get("mcts_root_visits", 0)) <= 0:
		return Result.failure("Strategic plan MCTS should backpropagate root visits: %s" % str(payload))
	if not payload.has("mcts_selected_q"):
		return Result.failure("Strategic plan MCTS should expose selected plan q: %s" % str(payload))
	if Array(payload.get("mcts_selected_path", [])).is_empty():
		return Result.failure("Strategic plan MCTS should expose selected plan continuation path: %s" % str(payload))
	if str(payload.get("mcts_selected_state_key", "")).is_empty():
		return Result.failure("Strategic plan MCTS should expose selected plan-state key: %s" % str(payload))
	var selected_route_types: Array = Array(payload.get("mcts_selected_route_types", []))
	if selected_route_types.is_empty():
		return Result.failure("Strategic plan MCTS should expose selected route types: %s" % str(payload))
	if int(payload.get("mcts_route_switch_count", -1)) != StrategicMCTSSearchClass._route_switch_count(selected_route_types):
		return Result.failure("Strategic plan MCTS route switch count should match selected route types: %s" % str(payload))
	if not payload.has("mcts_non_root_populated_nodes") or not payload.has("mcts_non_root_expanded_nodes") or not payload.has("mcts_non_root_candidate_count"):
		return Result.failure("Strategic plan MCTS should expose non-root expansion metrics: %s" % str(payload))
	if not payload.has("mcts_plan_state_deduped_nodes") or not payload.has("mcts_plan_transposition_pruned_nodes"):
		return Result.failure("Strategic plan MCTS should expose plan transposition metrics: %s" % str(payload))
	var evaluated_plans: Array = Array(payload.get("evaluated_plans", []))
	if evaluated_plans.is_empty():
		return Result.failure("Strategic plan MCTS should expose evaluated plan nodes: %s" % str(payload))
	var first_eval_val = evaluated_plans[0]
	if not (first_eval_val is Dictionary):
		return Result.failure("Strategic plan MCTS evaluated node should be a dictionary: %s" % str(payload))
	var first_eval: Dictionary = first_eval_val
	if not first_eval.has("visits") or not first_eval.has("q"):
		return Result.failure("Strategic plan MCTS evaluated node should expose visits/q: %s" % str(first_eval))
	if str(first_eval.get("state_key", "")).is_empty():
		return Result.failure("Strategic plan MCTS evaluated node should expose its plan-state key: %s" % str(first_eval))
	if int(first_eval.get("depth", 0)) <= 0:
		return Result.failure("Strategic plan MCTS evaluated node should be below root: %s" % str(first_eval))
	var path: Array = Array(first_eval.get("path", []))
	if path.is_empty():
		return Result.failure("Strategic plan MCTS evaluated node should expose a plan path: %s" % str(first_eval))
	var best_path: Array = Array(first_eval.get("best_path", []))
	if best_path.is_empty():
		return Result.failure("Strategic plan MCTS evaluated node should expose its best continuation path: %s" % str(first_eval))
	var best_route_types: Array = Array(first_eval.get("best_route_types", []))
	if best_route_types.is_empty():
		return Result.failure("Strategic plan MCTS evaluated node should expose best route types: %s" % str(first_eval))
	if int(first_eval.get("route_switch_count", -1)) != StrategicMCTSSearchClass._route_switch_count(best_route_types):
		return Result.failure("Strategic plan MCTS evaluated node route switch count should match best route types: %s" % str(first_eval))
	for path_item_val in path:
		if not (path_item_val is Dictionary):
			return Result.failure("Strategic plan MCTS path entries should be dictionaries: %s" % str(path))
		var path_item: Dictionary = path_item_val
		if str(path_item.get("plan_id", "")).is_empty():
			return Result.failure("Strategic plan MCTS path entries should identify plans: %s" % str(path))
		if path_item.has("command") or path_item.has("commands_executed"):
			return Result.failure("Strategic plan MCTS path should stay at plan level: %s" % str(path))
	return Result.success()

static func _test_strategic_mcts_expands_non_root_plan_nodes(seed_val: int) -> Result:
	var route_types := StrategicMCTSSearchClass._route_types_for_path([
		{"route_type": "marketing_income"},
		{"route_type": "supply_capacity"},
		{"route_type": "supply_capacity"},
		{"route_type": "price_recovery"},
	])
	if route_types.size() != 4 or str(route_types[0]) != "marketing_income":
		return Result.failure("MCTS route type helper should preserve path order: %s" % str(route_types))
	if StrategicMCTSSearchClass._route_switch_count(route_types) != 2:
		return Result.failure("MCTS route switch helper should count route transitions: %s" % str(route_types))

	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var profile := StrategyProfileClass.new()
	var profile_read := profile.configure("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var search_read := StrategicSearchClass.choose_plan_mcts(
		data["engine"],
		data["observation"],
		profile,
		TimeBudget.start(1200),
		{
			"max_plans": 1,
			"min_plans_for_rollout": 1,
			"horizon_decisions": 4,
			"horizon_rounds": 1,
			"step_budget_ms": 20,
			"mcts_iterations": 3,
			"mcts_max_depth": 2,
			"mcts_top_k_per_node": 1,
			"mcts_root_prior_min_visits_per_child": 0,
		}
	)
	if not search_read.ok:
		return search_read
	var payload: Dictionary = Dictionary(search_read.value)
	if int(payload.get("mcts_non_root_populated_nodes", 0)) <= 0:
		return Result.failure("Strategic plan MCTS should regenerate candidates below root: %s" % str(payload))
	if int(payload.get("mcts_non_root_candidate_count", 0)) <= 0:
		return Result.failure("Strategic plan MCTS should count non-root generated candidates: %s" % str(payload))
	if int(payload.get("mcts_non_root_expanded_nodes", 0)) <= 0:
		return Result.failure("Strategic plan MCTS should expand at least one non-root plan node: %s" % str(payload))
	var features: Dictionary = Dictionary(payload.get("features", {}))
	if int(features.get("mcts_non_root_populated_nodes", 0)) != int(payload.get("mcts_non_root_populated_nodes", 0)):
		return Result.failure("Strategic plan MCTS features should mirror non-root metrics: features=%s payload=%s" % [str(features), str(payload)])
	if Array(payload.get("mcts_selected_route_types", [])).is_empty():
		return Result.failure("Strategic plan MCTS should expose selected route type sequence: %s" % str(payload))
	return Result.success()

static func _test_strategic_bot_mcts_mode(seed_val: int) -> Result:
	var inputs_read := _build_income_route_inputs(seed_val)
	if not inputs_read.ok:
		return inputs_read
	var data: Dictionary = inputs_read.value
	var bot := StrategicBotClass.new()
	var profile_read := bot.configure_profile("base_revenue_growth_v1")
	if not profile_read.ok:
		return profile_read
	var search_read := bot.configure_search_options({
		"strategic_search": "mcts",
		"strategic_min_search_budget_ms": 16,
		"strategic_min_plans_for_rollout": 1,
		"strategic_max_plans": 3,
		"strategic_horizon_decisions": 4,
		"strategic_horizon_rounds": 1,
		"strategic_rollout_step_budget_ms": 20,
		"strategic_config_id": "mcts_smoke",
	})
	if not search_read.ok:
		return search_read
	var decision := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(600)
	)
	if decision == null or decision.is_failure() or decision.command == null:
		return Result.failure("StrategicBot should produce a decision in mcts mode: %s" % str(decision))
	var trace: Dictionary = Dictionary(decision.trace)
	if str(trace.get("strategic_search", "")) != "mcts":
		return Result.failure("StrategicBot should trace mcts search mode: %s" % str(trace))
	if str(trace.get("strategic_budget_profile", "")) != "play":
		return Result.failure("StrategicBot should trace strategic budget profile: %s" % str(trace))
	if str(trace.get("search", "")) != "strategic":
		return Result.failure("StrategicBot mcts mode should still be a strategic decision: %s" % str(trace))
	if str(trace.get("plan_id", "")).is_empty():
		return Result.failure("StrategicBot mcts mode should expose selected plan: %s" % str(trace))
	if Array(trace.get("mcts_selected_path", [])).is_empty():
		return Result.failure("StrategicBot mcts mode should expose selected plan continuation path: %s" % str(trace))
	if str(trace.get("mcts_selected_state_key", "")).is_empty():
		return Result.failure("StrategicBot mcts mode should expose selected plan-state key: %s" % str(trace))
	if Array(trace.get("mcts_selected_route_types", [])).is_empty():
		return Result.failure("StrategicBot mcts mode should expose selected route types: %s" % str(trace))
	if not trace.has("mcts_route_switch_count"):
		return Result.failure("StrategicBot mcts mode should expose route switch count: %s" % str(trace))
	if not trace.has("mcts_non_root_populated_nodes") or not trace.has("mcts_non_root_expanded_nodes") or not trace.has("mcts_non_root_candidate_count"):
		return Result.failure("StrategicBot mcts mode should expose non-root expansion metrics: %s" % str(trace))
	if not trace.has("mcts_plan_state_deduped_nodes"):
		return Result.failure("StrategicBot mcts mode should expose plan-state dedupe count: %s" % str(trace))
	if not trace.has("mcts_plan_transposition_pruned_nodes"):
		return Result.failure("StrategicBot mcts mode should expose plan transposition prune count: %s" % str(trace))
	if not decision.explanation.has("mcts_plan_state_deduped_nodes"):
		return Result.failure("StrategicBot mcts explanation should expose plan-state dedupe count: %s" % str(decision.explanation))
	if not decision.explanation.has("mcts_plan_transposition_pruned_nodes"):
		return Result.failure("StrategicBot mcts explanation should expose plan transposition prune count: %s" % str(decision.explanation))
	if str(decision.explanation.get("mcts_selected_state_key", "")).is_empty():
		return Result.failure("StrategicBot mcts explanation should expose selected plan-state key: %s" % str(decision.explanation))
	if Array(decision.explanation.get("mcts_selected_route_types", [])).is_empty():
		return Result.failure("StrategicBot mcts explanation should expose selected route types: %s" % str(decision.explanation))
	if not decision.explanation.has("mcts_non_root_populated_nodes"):
		return Result.failure("StrategicBot mcts explanation should expose non-root expansion metrics: %s" % str(decision.explanation))
	var valid := LegalActionServiceClass.validate_command(data["engine"], decision.command, data["context"])
	if not valid.ok:
		return Result.failure("StrategicBot mcts mode returned invalid command: %s" % valid.error)
	var breakdown: Dictionary = Dictionary(trace.get("plan_eval_breakdown", {}))
	if breakdown.is_empty():
		return Result.failure("StrategicBot mcts mode should expose plan breakdown: %s" % str(trace))
	var telemetry: Dictionary = Dictionary(trace.get("plan_eval_telemetry", {}))
	if telemetry.is_empty():
		return Result.failure("StrategicBot mcts mode should expose plan telemetry: %s" % str(trace))
	var evaluated_plans: Array = Array(trace.get("evaluated_plans", []))
	if evaluated_plans.is_empty():
		return Result.failure("StrategicBot mcts mode should expose evaluated plans: %s" % str(trace))
	var first_eval_val = evaluated_plans[0]
	if not (first_eval_val is Dictionary):
		return Result.failure("StrategicBot mcts mode should expose evaluated plan telemetry: %s" % str(trace))
	var first_eval: Dictionary = first_eval_val
	if Dictionary(first_eval.get("telemetry", {})).is_empty():
		return Result.failure("StrategicBot mcts mode should expose evaluated plan telemetry: %s" % str(trace))
	if str(first_eval.get("state_key", "")).is_empty():
		return Result.failure("StrategicBot mcts mode should expose evaluated plan-state key: %s" % str(trace))
	if Array(first_eval.get("path", [])).is_empty():
		return Result.failure("StrategicBot mcts mode should expose evaluated plan path: %s" % str(trace))
	if Array(first_eval.get("best_path", [])).is_empty():
		return Result.failure("StrategicBot mcts mode should expose evaluated plan best continuation path: %s" % str(trace))
	if Array(first_eval.get("best_route_types", [])).is_empty():
		return Result.failure("StrategicBot mcts mode should expose evaluated plan best route types: %s" % str(trace))
	bot._clear_route_history()
	var cached := bot.choose_command_with_engine(
		data["engine"],
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(40)
	)
	if cached == null or cached.is_failure() or cached.command == null:
		return Result.failure("StrategicBot mcts mode should reuse cached plan under tight follow-up budget: %s" % str(cached))
	var cached_trace: Dictionary = Dictionary(cached.trace)
	if str(cached_trace.get("strategic_search", "")) != "mcts":
		return Result.failure("StrategicBot cached mcts decision should preserve search mode: %s" % str(cached_trace))
	if str(cached_trace.get("strategic_budget_profile", "")) != "play":
		return Result.failure("StrategicBot cached mcts decision should preserve budget profile: %s" % str(cached_trace))
	if str(cached_trace.get("search", "")) != "strategic_cached":
		return Result.failure("StrategicBot mcts mode should mark cached plan reuse: %s" % str(cached_trace))
	if str(cached_trace.get("plan_id", "")) != str(trace.get("plan_id", "")):
		return Result.failure("StrategicBot cached mcts plan should match initial plan: %s vs %s" % [str(cached_trace), str(trace)])
	if int(cached_trace.get("plan_search_time_ms", -1)) != 0:
		return Result.failure("StrategicBot cached mcts plan should not re-run search: %s" % str(cached_trace))
	var cached_valid := LegalActionServiceClass.validate_command(data["engine"], cached.command, data["context"])
	if not cached_valid.ok:
		return Result.failure("StrategicBot cached mcts decision should remain valid: %s" % cached_valid.error)
	return Result.success()

static func _build_working_inputs(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 40)
	if not working.ok:
		return working
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	var actor := state.get_current_player_id()
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
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	return Result.success({
		"engine": engine,
		"observation": observation,
		"context": context,
		"legal_action_ids": ids_read.value,
		"validate_fn": validate_fn,
	})

static func _build_income_route_inputs(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [])
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.current_player_index = 0
	state.round_number = 2
	state.players[0]["cash"] = 0
	state.players[0]["inventory"] = {}
	state.players[1]["inventory"] = {}
	state.rules["salary_cost"] = 5
	state.milestone_pool = ["first_burger_produced", "first_burger_marketed", "first_billboard"]
	var take := StateUpdaterClass.take_from_pool(state, "kitchen_trainee", 1)
	if not take.ok:
		return Result.failure("income route fixture take kitchen_trainee failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "kitchen_trainee", false)
	if not add.ok:
		return Result.failure("income route fixture add kitchen_trainee failed: %s" % add.error)
	RoadGraphCacheClass.invalidate_road_graph(state)
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	var observation_read := ObservationAdapterClass.observe_for_player(engine, 0)
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
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	return Result.success({
		"engine": engine,
		"observation": observation,
		"context": context,
		"legal_action_ids": ids_read.value,
		"validate_fn": validate_fn,
	})

static func _sync_initial_checkpoint_to_current_state(engine: GameEngine) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("cannot sync checkpoint: engine/state is null")
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("cannot sync checkpoint: checkpoint[0] missing")
	var state := engine.get_state()
	var checkpoint: Dictionary = engine.checkpoints[0]
	checkpoint["state_dict"] = state.to_dict().duplicate(true)
	checkpoint["hash"] = state.compute_hash()
	engine.checkpoints[0] = checkpoint
	engine.command_history.clear()
	engine.current_command_index = -1
	var total_cash_read := InvariantsClass.compute_total_cash(state)
	if not total_cash_read.ok:
		return total_cash_read
	engine.set_initial_total_cash_for_invariants(int(total_cash_read.value))
	var employee_totals_read := InvariantsClass.compute_employee_base_totals_for_invariants(state)
	if not employee_totals_read.ok:
		return employee_totals_read
	engine.set_initial_employee_totals_for_invariants(employee_totals_read.value)
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

static func _synthetic_income_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": ["burger_cook", "pizza_cook"],
		"reserve_employees": ["kitchen_trainee"],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
		"milestones": [],
	}
	observation.map_public = {
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
					{"product": "burger"},
					{"product": "burger"},
					{"product": "burger"},
				],
			},
		},
		"restaurants": {
			"rest_near": {
				"restaurant_id": "rest_near",
				"owner": 0,
				"anchor_pos": Vector2i(3, 2),
			},
		},
	}
	observation.employee_pool_public = {
		"campaign_manager": 1,
		"burger_cook": 1,
		"kitchen_trainee": 1,
	}
	return observation

static func _synthetic_empty_observation() -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 1
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player = {
		"id": 0,
		"cash": 20,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"inventory": {},
		"milestones": [],
	}
	observation.map_public = {
		"houses": {},
		"restaurants": {},
		"house_number_supply_remaining": [],
	}
	observation.employee_pool_public = {}
	return observation

static func _synthetic_growth_observation(has_income_footing: bool) -> ObservationState:
	var observation := ObservationState.new()
	observation.viewer_player_id = 0
	observation.round_number = 2
	observation.phase = DefsClass.PHASE_WORKING
	observation.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	observation.own_player = {
		"id": 0,
		"cash": 50 if has_income_footing else 0,
		"employees": ["ceo", "burger_cook", "campaign_manager"] if has_income_footing else ["ceo"],
		"reserve_employees": ["new_business_developer"],
		"busy_marketers": [],
		"restaurants": ["rest_near"],
		"inventory": {},
		"milestones": ["first_burger_marketed", "first_burger_produced"] if has_income_footing else [],
	}
	observation.map_public = {
		"houses": {
			"house_near": {
				"house_number": 1,
				"anchor_pos": Vector2i(2, 2),
				"demands": [
					{"product": "burger"},
					{"product": "burger"},
					{"product": "burger"},
				] if has_income_footing else [],
			},
		},
		"restaurants": {
			"rest_near": {
				"restaurant_id": "rest_near",
				"owner": 0,
				"anchor_pos": Vector2i(3, 2),
			},
		},
		"house_number_supply_remaining": [2, 3, 4],
	}
	observation.employee_pool_public = {
		"new_business_developer": 1,
	}
	return observation

static func _has_plan(plans: Array, route_type: String, product_id: String) -> bool:
	for plan_val in plans:
		if plan_val == null or not plan_val.has_method("to_trace_dict"):
			continue
		var plan = plan_val
		if plan.route_type == route_type and plan.target_products.has(product_id):
			return true
	return false

static func _has_route_type(plans: Array, route_type: String) -> bool:
	for plan_val in plans:
		if plan_val == null or not plan_val.has_method("to_trace_dict"):
			continue
		var plan = plan_val
		if str(plan.route_type) == route_type:
			return true
	return false

static func _plan_debug(plans: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for plan_val in plans:
		if plan_val != null and plan_val.has_method("to_trace_dict"):
			out.append(plan_val.to_trace_dict())
	return out

static func _rollout_actions(rollout: Dictionary) -> Array:
	var out := []
	for item_val in Array(rollout.get("commands_executed", [])):
		if item_val is Dictionary:
			var item: Dictionary = item_val
			out.append({
				"actor": int(item.get("actor", -1)),
				"action_id": str(item.get("action_id", "")),
				"params": Dictionary(item.get("params", {})).duplicate(true),
			})
	return out
